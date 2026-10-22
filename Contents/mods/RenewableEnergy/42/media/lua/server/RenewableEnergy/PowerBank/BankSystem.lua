-- The banks on the authority: the Global Object System that keeps them, the charge pass,
-- placing and removing banks, and the bank tiles' life in the map.
--
-- The vanilla Global Object System saves each bank's table with the world (not in the
-- chunk), so a bank keeps charging and draining while nobody is near it, and its sync
-- key pushes the bank's summary to every client (zombie/globalObjects).

if isClient() then return end

require "Map/SGlobalObjectSystem"
require "TimedActions/ISDestroyStuffAction"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/PowerBank/PanelSource"
require "RenewableEnergy/PowerBank/Treadmill"
require "RenewableEnergy/PowerBank/TreadmillSource"
local Bank = require "RenewableEnergy/PowerBank/Bank"

RenewableEnergy = RenewableEnergy or {}
local Sprites, Sun, PowerBank = RenewableEnergy.Sprites, RenewableEnergy.Sun, RenewableEnergy.PowerBank
local Sources, PanelSource, Treadmill = RenewableEnergy.Sources, RenewableEnergy.PanelSource, RenewableEnergy.Treadmill

local BankSystem = SGlobalObjectSystem:derive("RenewableEnergy_BankSystem")
RenewableEnergy.BankSystem = BankSystem

-- Values of the ChargeFreq sandbox option.
local EVERY_TEN_MINUTES = 1
-- A pass integrates the sun in steps this long (hours), so an hourly pass still follows
-- the sun's curve.
local SUN_STEP = 1 / 6
-- Longer gaps than this between passes (a save loaded after the clock jumped) count as
-- this long, so one pass never swings the charge by days of sun.
local LONGEST_PASS = 24

function BankSystem:new()
    return SGlobalObjectSystem.new(self, PowerBank.SYSTEM_NAME)
end

function BankSystem:initSystem()
    PowerBank.serverSystem = self
    self.system:setObjectModDataKeys(Bank.SAVED_FIELDS)
    self.system:setObjectSyncKeys({ "summary" })
    if SandboxVars.RenewableEnergy.ChargeFreq == EVERY_TEN_MINUTES then
        Events.EveryTenMinutes.Add(BankSystem.updateAll)
    else
        Events.EveryHours.Add(BankSystem.updateAll)
    end
end

-- Each loaded bank gets the summary the clients are sent, which isn't saved, before any client
-- connects. A status left in older saves is dropped.
function BankSystem:initLuaObjects()
    SGlobalObjectSystem.initLuaObjects(self)
    for i = 1, self:getLuaObjectCount() do
        local bank = self:getLuaObjectByIndex(i)
        bank.status = nil
        bank.summary = bank:buildSummary()
    end
end

function BankSystem:isValidIsoObject(isoObject)
    return PowerBank.isBank(isoObject)
end

function BankSystem:newLuaObject(globalObject)
    return Bank:new(self, globalObject)
end

-- Set while makeBank takes away a working bank to rebuild it: the bank's state on the global
-- object stays for the rebuilt bank to load.
local rebuilding = false

--- Make a bank tile into a working bank: an IsoGenerator, the only thing that powers the
--- squares around it, with the tile's container for its batteries. `from`, a placed bank
--- tile that isn't a generator yet, hands over its container and modData.
--- A bank the world spawns (no `from`) was installed, so it comes connected; a tile a player
--- placed must be connected like a generator, and a bank rebuilt keeps its flag.
local function makeBank(square, spriteName, index, from)
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
    square:AddSpecialObject(generator, math.min(index, square:getObjects():size()))
    container = generator:getContainer()
    if container then
        container:setExplored(true)
        PowerBank.adoptContainer(container)
    end
    generator:transmitCompleteItemToClients()
    -- On a server each of these syncs the generator by its index on the square; a sync can reach a
    -- client before the generator does and be dropped there, so a client asks again ("resync").
    generator:setCondition(100)
    generator:setFuel(10)
    generator:setConnected(connected)
    triggerEvent("OnObjectAdded", generator)
    return generator
end

--- A working bank of tile `spriteName` (a bank's Sprites field value) at `index` on the
--- square, or on top when `index` is nil or negative. Authority only.
function PowerBank.place(square, spriteName, index)
    local top = square:getObjects():size()
    return makeBank(square, spriteName, (index and index >= 0) and index or top, nil)
end

--- Switch a bank off, forget it and take its tile away, contents and all. Authority only.
function PowerBank.remove(isoObject)
    local square = isoObject and isoObject:getSquare()
    if square then
        square:transmitRemoveItemFromSquare(isoObject)
    end
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
    if generator:isActivated() then
        generator:setActivated(false)
    end
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
        local found = PowerBank.bankOfSource(x, y, z)
        local bank = found and self:getLuaObjectAt(found.x, found.y, found.z)
        if bank then
            -- What the source made up to now counts.
            BankSystem.updateBank(bank)
            bank:removeSource(x, y, z)
            bank:sendStatus()
        end
        -- A wired treadmill picked up or destroyed leaves its wire on the floor; the item it
        -- becomes doesn't keep the wiring (ISMoveableSpriteProps keeps a plain tile's movableData
        -- alone).
        if Treadmill.isWiredTile(isoObject) then
            RenewableEnergy.TreadmillSource.unwire(isoObject)
        end
    end
end

-- A sledgehammer is the one way a bank leaves with batteries in it (picking up and scrapping need
-- it empty, ISMoveableSpriteProps), and it dumps them on the floor before it takes the tile
-- (ISDestroyStuffAction.complete, IsoObject.dumpContentsInSquare). The bank comes up to now first,
-- so they leave with what the time since its last pass gave and took.
local destroyComplete = ISDestroyStuffAction.complete
function ISDestroyStuffAction:complete()
    local bank = self.item and PowerBank.isBank(self.item) and BankSystem.instance:getLuaObjectOnSquare(self.item:getSquare())
    if bank then
        BankSystem.updateBank(bank)
    end
    return destroyComplete(self)
end

-- Clients only watch a bank's status, which the status window does while it is open. Every job
-- that changes a bank comes as a RenewableEnergyAction, whose complete() checks the character is
-- at it, so a forged command packet can't reach a bank from afar.

-- Real milliseconds a player waits between refreshes of one bank, since each refresh makes the
-- bank look at its container again and sends its status to everyone watching it.
local REFRESH_MS = 1000

--- The bank at `position`, or nil, also when `position` isn't a { x, y, z } place.
function BankSystem.bankAt(position)
    local system = PowerBank.serverSystem
    if not (system and PowerBank.isPosition(position)) then
        return nil
    end
    return system:getLuaObjectAt(position.x, position.y, position.z)
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

function BankSystem:OnClientCommand(command, player, args)
    local bank = player and type(args) == "table" and BankSystem.bankAt(args.bank)
    if not bank then return end
    if command == "watch" and bank:inViewOf(player) then
        local new = bank:watch(player)
        if mayRefresh(bank, player) then
            PowerBank.perform(player, "refresh", args)
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
    PowerBank.adoptContainer(isoObject:getContainer())
    BankSystem.instance:loadIsoObject(isoObject)
end

for _, name in ipairs(PowerBank.bankSprites()) do
    MapObjects.OnLoadWithSprite(name, loadBank, Sprites.LOAD_PRIORITY)
end

-- A panel's chunk loaded: its overlays are saved with it, but older saves may lack the cracks.
for kind in pairs(RenewableEnergy.Specs.mounts) do
    MapObjects.OnLoadWithSprite(Sprites.namesOf(kind), PanelSource.showCracks, Sprites.LOAD_PRIORITY)
end

--- What every bank in this pass shares: the weather, the light on each mount averaged over
--- the `hours` up to now (and what it would be under a clear sky), and the hours of storm
--- that can crack modules.
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
        stormHours = PanelSource.stormHours(hours),
        irradiance = averaged(weather),
        clearIrradiance = averaged(Sun.CLEAR_WEATHER),
    }
end

-- Game hours since the bank's last pass, at most LONGEST_PASS, and the pass's end time.
local function passHours(bank)
    local now = getGameTime():getWorldAgeHours()
    return math.min(LONGEST_PASS, now - (bank.lastHour or now)), now
end

--- A pass context for each span of hours, worked out once and shared by every bank that runs
--- that span: banks placed at different times run different spans.
function BankSystem.sharedContexts()
    local contexts = {}
    return function(hours)
        local key = string.format("%.4f", hours)
        contexts[key] = contexts[key] or BankSystem.passContext(hours)
        return contexts[key]
    end
end

--- Bring one bank up to now. `contextFor(hours)`, optional, gives the pass context for the span
--- (BankSystem.passContext unless given).
function BankSystem.updateBank(bank, contextFor)
    local hours, now = passHours(bank)
    bank.lastHour = now
    if hours > 0 then
        bank:update(hours, (contextFor or BankSystem.passContext)(hours))
    end
end

function BankSystem.updateAll()
    local self = BankSystem.instance
    local contextFor = BankSystem.sharedContexts()
    for i = 1, self:getLuaObjectCount() do
        BankSystem.updateBank(self:getLuaObjectByIndex(i), contextFor)
    end
    -- Banks that came on or went off change what each generator nearby pays.
    RenewableEnergy.Payers.billGenerators()
end

SGlobalObjectSystem.RegisterSystemClass(BankSystem)

return BankSystem
