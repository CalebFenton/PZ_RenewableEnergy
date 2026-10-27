-- The banks on the authority: the Global Object System that keeps them, the charge pass,
-- placing and removing banks, the bank tiles' life in the map, and the jobs at a bank.
--
-- The vanilla Global Object System saves each bank's table with the world (not in the
-- chunk), so a bank keeps charging and draining while nobody is near it, and its sync
-- key pushes the bank's summary to every client (zombie/globalObjects).

if isClient() then return end

require "Map/SGlobalObjectSystem"
require "TimedActions/ISDestroyStuffAction"
local Specs = require "RenewableEnergy/Specs"
local Sprites = require "RenewableEnergy/Sprites"
local Sun = require "RenewableEnergy/Sun"
local Fumes = require "RenewableEnergy/Fumes"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local PanelSource = require "RenewableEnergy/PowerBank/PanelSource"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local TreadmillSource = require "RenewableEnergy/PowerBank/TreadmillSource"
local Wear = require "RenewableEnergy/PowerBank/Wear"
local Wiring = require "RenewableEnergy/PowerBank/Wiring"
local Payers = require "RenewableEnergy/PowerBank/Payers"
local Bank = require "RenewableEnergy/PowerBank/Bank"
require "RenewableEnergy/PowerBank/BankParts"
require "RenewableEnergy/PowerBank/Backup"
require "RenewableEnergy/PowerBank/BankStatus"
local Action = require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local Items = require "cf_commonlib/Items"
local LibObjectSystem = require "cf_commonlib/ObjectSystem"
local Squares = require "cf_commonlib/Squares"
local Tiles = require "cf_commonlib/Tiles"

local BankSystem = LibObjectSystem.deriveSystem(PowerBank, Bank)

-- Values of the ChargeFreq sandbox option.
local EVERY_TEN_MINUTES = 1
-- A pass integrates the sun in steps this long (hours), so an hourly pass still follows
-- the sun's curve.
local SUN_STEP = 1 / 6
-- Longer gaps than this between passes (a save loaded after the clock jumped) count as
-- this long, so one pass never swings the charge by days of sun (Bank:catchUp).
BankSystem.longestPass = 24

local deriveInitSystem, deriveInitLuaObjects = BankSystem.initSystem, BankSystem.initLuaObjects

function BankSystem:initSystem()
    deriveInitSystem(self)
    if SandboxVars.RenewableEnergy.ChargeFreq == EVERY_TEN_MINUTES then
        Events.EveryTenMinutes.Add(BankSystem.updateAll)
    else
        Events.EveryHours.Add(BankSystem.updateAll)
        -- Hourly bank passes settle before the gas pass. Keep ten-minute billing too:
        -- gas settlement can change running generators between those hourly updates.
        Events.EveryTenMinutes.Add(Payers.billGenerators)
    end
end

-- A status left in older saves is dropped.
function BankSystem:initLuaObjects()
    deriveInitLuaObjects(self)
    for i = 1, self:getLuaObjectCount() do
        self:getLuaObjectByIndex(i).status = nil
    end
end

-- Set while makeBank takes away a working bank to rebuild it: the bank's state on the global
-- object stays for the rebuilt bank to load.
local rebuilding = false

--- Make a bank tile into a working bank: an IsoGenerator, the only thing that powers the
--- squares around it, with the tile's container for its batteries. `from`, a placed bank
--- tile that isn't a generator yet, hands over its container and modData.
--- A bank the world spawns (no `from`) was installed, so it comes connected; a tile a player
--- placed must be connected like a generator, and a bank rebuilt keeps its flag.
local function makeBank(square, spriteName, index, from, fill)
    local connected = from == nil or (instanceof(from, "IsoGenerator") and from:isConnected())
    local container = from and from:getContainer()
    local modData = {}
    if from then
        for key, value in pairs(from:getModData()) do
            modData[key] = value
        end
        rebuilding = true
        square:transmitRemoveItemFromSquare(from)
        rebuilding = false
    end

    local generator = IsoGenerator.new(square:getCell())
    generator:setSprite(getSprite(spriteName))
    generator:setSquare(square)
    local generatorModData = generator:getModData()
    for key, value in pairs(modData) do
        generatorModData[key] = value
    end
    if container then
        generator:setContainer(container)
    else
        -- IsoGenerator.addToWorld doesn't build containers, unlike IsoObject's.
        generator:createContainersFromSpriteProperties()
    end
    Tiles.addToWorld(square, generator, {
        index = math.min(index, square:getObjects():size()),
        beforeSend = function()
            container = generator:getContainer()
            if container then
                container:setExplored(true)
            end
            if fill then
                fill(container)
            end
        end,
        -- On a server each of these syncs the generator by its index on the square; a sync can reach a
        -- client before the generator does and be dropped there, so a client asks again ("resync").
        afterSend = function()
            generator:setCondition(100)
            generator:setFuel(10)
            generator:setConnected(connected)
        end,
    })
    return generator
end

--- A working bank of tile `spriteName` (a bank's tile in any facing) at `index` on the square, or
--- on top when `index` is nil or negative. `fill(container)`, if given, stocks it before the
--- complete object is sent and its record first reads the parts. Authority only.
function BankSystem.place(square, spriteName, index, fill)
    local top = square:getObjects():size()
    return makeBank(square, spriteName, (index and index >= 0) and index or top, nil, fill)
end

function BankSystem:OnObjectAdded(isoObject)
    local name = Sprites.nameOf(isoObject)
    if PowerBank.bankOfSprite(name) and not PowerBank.isBank(isoObject) then
        -- A bank tile placed as a moveable is a plain IsoObject.
        makeBank(isoObject:getSquare(), name, isoObject:getObjectIndex(), isoObject)
    elseif PowerBank.isBank(isoObject) then
        self:loadIsoObject(isoObject)
    else
        -- Placing a mount, rotating it (picked up and placed again) and world spawns all land
        -- here, with the modules the item carried.
        PanelSource.showCracks(isoObject)
    end
end

-- Squares stay powered by a running generator after it is removed, until
-- setSurroundingElectricity runs on it switched off (IsoChunk.isGeneratorPoweringSquare).
local function unpower(generator)
    Fumes.setBankRunning(generator, false)
end

function BankSystem:OnObjectAboutToBeRemoved(isoObject)
    if PowerBank.isBank(isoObject) then
        unpower(isoObject)
        local bank = not rebuilding and self:getLuaObjectOnSquare(isoObject:getSquare())
        if bank then
            self:removeLuaObject(bank)
        end
    elseif Sources.kindOf(isoObject) then
        local x, y, z = isoObject:getX(), isoObject:getY(), isoObject:getZ()
        local bank = BankSystem.bankOfSourceAt(x, y, z)
        if bank then
            BankSystem.dropSource(bank, x, y, z)
        end
        -- A wired treadmill picked up or destroyed leaves its wire on the floor; the item it
        -- becomes doesn't keep the wiring (ISMoveableSpriteProps keeps a plain tile's movableData
        -- alone).
        if Treadmill.isWiredTile(isoObject) then
            TreadmillSource.unwire(isoObject)
        end
    end
end

-- A sledgehammer is the one way a bank leaves with batteries in it (picking up and scrapping need
-- it empty, ISMoveableSpriteProps), and it dumps them on the floor before it takes the tile
-- (ISDestroyStuffAction.complete, IsoObject.dumpContentsInSquare). The bank comes up to now first,
-- so they leave with what the time since its last pass gave and took.
local vanillaDestroyComplete = ISDestroyStuffAction.complete
function ISDestroyStuffAction:complete()
    local bank = self.item and PowerBank.isBank(self.item) and BankSystem.instance:getLuaObjectOnSquare(self.item:getSquare())
    if bank then
        bank:update()
    end
    return vanillaDestroyComplete(self)
end

-- Real milliseconds a player waits between refreshes of one bank, since each refresh makes the
-- bank look at its container again and sends its status to everyone watching it.
local REFRESH_MS = 1000

--- The bank at `position`, or nil, also when `position` isn't a { x, y, z } place.
function BankSystem.bankAt(position)
    local system = PowerBank.serverSystem
    if not (system and Squares.isPosition(position)) then
        return nil
    end
    return system:getLuaObjectAt(position.x, position.y, position.z)
end

--- The bank the source at x, y, z feeds, or nil.
function BankSystem.bankOfSourceAt(x, y, z)
    local found = PowerBank.bankOfSource(x, y, z)
    return found and BankSystem.bankAt(found) or nil
end

local function mayRefresh(bank, player)
    -- Each player's last refresh, by name, kept unsaved on the bank's record: it goes when the bank
    -- goes, and a bank built in its place starts afresh.
    bank.refreshedAt = bank.refreshedAt or {}
    local now, name = getTimestampMs(), player:getUsername()
    local last = bank.refreshedAt[name]
    if last and now - last < REFRESH_MS then
        return false
    end
    bank.refreshedAt[name] = now
    return true
end

-- A client sends only "watch", "unwatch" and "resync". Every job that changes a bank comes as a
-- RenewableEnergyAction, whose complete() checks the character is at it, so a forged command
-- packet can't reach a bank from afar.
function BankSystem:OnClientCommand(command, player, args)
    local bank = player and type(args) == "table" and BankSystem.bankAt(args.bank)
    if not bank then return end
    if command == "watch" and bank:inViewOf(player) then
        local new = bank:watch(player)
        if mayRefresh(bank, player) then
            bank:refresh()
        elseif new then
            -- A window closed and opened again within the wait still needs the status.
            bank:sendStatusTo(player)
        end
    elseif command == "unwatch" then
        bank:unwatch(player)
    elseif command == "resync" and bank:inViewOf(player) then
        local isoObject = bank:getIsoObject()
        if isoObject then
            isoObject:sync()
        end
    end
end

-- A bank's chunk loaded. Rebuild a bank tile that isn't a working bank (a placement that
-- failed halfway, a map or stash placing the bare tile) so a reload repairs it.
local function loadBank(isoObject)
    if not PowerBank.isBank(isoObject) or not isoObject:getContainer() then
        makeBank(isoObject:getSquare(), Sprites.nameOf(isoObject), isoObject:getObjectIndex(), isoObject)
        return
    end
    BankSystem.instance:loadIsoObject(isoObject)
end

Tiles.onLoad(PowerBank.bankSprites(), loadBank, { first = true })

-- A panel's chunk loaded: its overlays are saved with it, but older saves may lack the cracks.
for kind in pairs(Specs.mounts) do
    Tiles.onLoad(Sprites.namesOf(kind), PanelSource.showCracks)
end

--- What every bank in this pass shares: the weather, and the light on each mount averaged over
--- the `hours` up to now (and what it would be under a clear sky).
function BankSystem.passContext(hours)
    local climate = getClimateManager()
    local weather = Sun.weatherNow()
    local steps = math.max(1, math.ceil(hours / SUN_STEP))
    local suns = {}
    for i = 1, steps do
        table.insert(suns, Sun.positionNow(hours * (i - 0.5) / steps))
    end
    local function averaged(skies)
        -- By kind, then facing ("" for none), so a lookup builds no string.
        local cache = {}
        return function(kind, facing)
            local byFacing = cache[kind]
            if not byFacing then
                byFacing = {}
                cache[kind] = byFacing
            end
            local key = facing or ""
            local average = byFacing[key]
            if not average then
                local total = 0
                for _, sun in ipairs(suns) do
                    total = total + Sun.planeIrradiance(sun, kind, facing, skies)
                end
                average = total / steps
                byFacing[key] = average
            end
            return average
        end
    end
    return {
        weather = weather,
        precipitation = climate:getPrecipitationIntensity(),
        airC = climate:getTemperature(),
        elevation = Sun.elevation(),
        windKph = climate:getWindspeedKph(),
        irradiance = averaged(weather),
        clearIrradiance = averaged(Sun.CLEAR_WEATHER),
    }
end

-- A pass context for each span of hours, worked out once and shared by every bank that runs
-- that span: banks placed at different times run different spans.
local function sharedContexts()
    local contexts = {}
    return function(hours)
        local key = string.format("%.4f", hours)
        contexts[key] = contexts[key] or BankSystem.passContext(hours)
        return contexts[key]
    end
end

--- Brings `bank` up to now, so what the source at x, y, z made counts, then takes the source off
--- the bank and settles it.
function BankSystem.dropSource(bank, x, y, z)
    bank:catchUp()
    bank:removeSource(x, y, z)
    bank:afterChange()
end

--- Banks `hours` of a run, at most one run's, on the wired treadmill tile `tile` with the bank it
--- feeds, for the passes to come (TreadmillSource.credit). Returns whether a bank took it.
function BankSystem.creditTreadmill(tile, hours)
    local x, y, z = tile:getX(), tile:getY(), tile:getZ()
    local bank = Treadmill.isWired(tile) and BankSystem.bankOfSourceAt(x, y, z)
    local source = bank and bank:findSource(x, y, z)
    if not source then
        return false
    end
    TreadmillSource.credit(source, hours)
    return true
end

--- Every bank up to now in one pass sharing the contexts of their spans, then one bill for every
--- change they made, then what each shows and tells.
function BankSystem.updateAll()
    local contextFor = sharedContexts()
    PowerBank.each(function(bank)
        bank:catchUp(contextFor)
    end)
    Payers.billGenerators()
    PowerBank.each(function(bank)
        bank:showBatteries()
        bank:sendStatus()
    end)
end

-- What each bank job does to the bank's record `bank` (its tile `isoObject`) beyond taking its
-- materials and giving its XP, by its row of BankJobs.JOBS. Returns whether it was done.
local DO = {
    [BankJobs.TURN_ON] = function(character, bank, row)
        bank.on = row.on
        bank:powerUp()
        return true
    end,
    -- setConnected syncs the generator to the clients.
    [BankJobs.CONNECT] = function(character, bank, row, isoObject)
        isoObject:setConnected(row.connected)
        bank.connected = row.connected
        bank:powerUp()
        return true
    end,
    -- The bank's container filter refuses every transfer, so the part is moved here, past it.
    [BankJobs.WIRE_IN] = function(character, bank, row, isoObject, item)
        Items.takeItem(character, item)
        Items.addItem(isoObject:getContainer(), item)
        Wiring.teach(character, item, Wiring.PART_ONCE_KEY, Wiring.forPart(item:getFullType()))
        bank:powerUp()
        return true
    end,
    -- The battery leaves with the bank's shared charge as it is now.
    [BankJobs.UNWIRE] = function(character, bank, row, isoObject, item)
        bank:writeBatteries(isoObject:getContainer(), false)
        Items.takeItem(character, item)
        Items.giveItems(character, item)
        Wiring.refund(character, Wiring.forPart(item:getFullType()))
        bank:powerUp()
        return true
    end,
    [BankJobs.REPAIR] = function(character, bank, row, isoObject, item)
        Wear.setCondition(item, item:getCondition() + Specs.partRepair.condition)
        sendItemStats(item)
        bank:powerUp()
        return true
    end,
    [BankJobs.RENAME] = function(character, bank, row, isoObject, name)
        name = BankJobs.trimName(name)
        bank.name = name ~= "" and name or nil
        return true
    end,
}
DO[BankJobs.TURN_OFF] = DO[BankJobs.TURN_ON]
DO[BankJobs.DISCONNECT] = DO[BankJobs.CONNECT]

--- The authority's side of the jobs at a bank (cf_commonlib's ObjectSystem.jobSite): the bank is
--- caught up at its old state, the job changes it, then it settles once (Bank:afterChange), even
--- when the job was refused, since the catch-up alone can change who runs. Activation never waits
--- for the settlement.
BankSystem.jobSite = LibObjectSystem.jobSite(PowerBank, DO)
Action.serve({ bank = BankSystem.jobSite })

SGlobalObjectSystem.RegisterSystemClass(BankSystem)

return BankSystem
