-- The banks on the authority: the Global Object System that keeps them, the charge pass,
-- placing and removing banks, and the bank tiles' life in the map.
--
-- The vanilla Global Object System saves each bank's table with the world (not in the
-- chunk), so a bank keeps charging and draining while nobody is near it, and its sync
-- keys push the bank's status to every client (zombie/globalObjects).

if isClient() then return end

require "Map/SGlobalObjectSystem"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/PowerBank"
local Bank = require "RenewableEnergy/PowerBank/Bank"

RenewableEnergy = RenewableEnergy or {}
local Specs, Sun, PowerBank = RenewableEnergy.Specs, RenewableEnergy.Sun, RenewableEnergy.PowerBank

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
-- The bank container's filter, by the dotted path the game resolves.
local ACCEPT_FUNCTION = "RenewableEnergy.PowerBank.acceptItem"
-- MapObjects keeps one function per sprite and priority.
local LOAD_PRIORITY = 6

function BankSystem:new()
    return SGlobalObjectSystem.new(self, PowerBank.SYSTEM_NAME)
end

function BankSystem:initSystem()
    PowerBank.serverSystem = self
    self.system:setObjectModDataKeys(Bank.SAVED_FIELDS)
    self.system:setObjectSyncKeys({ "status" })
    if SandboxVars.RenewableEnergy.ChargeFreq == EVERY_TEN_MINUTES then
        Events.EveryTenMinutes.Add(BankSystem.updateAll)
    else
        Events.EveryHours.Add(BankSystem.updateAll)
    end
end

function BankSystem:isValidIsoObject(isoObject)
    return PowerBank.isBank(isoObject)
end

function BankSystem:newLuaObject(globalObject)
    return Bank:new(self, globalObject)
end

-- Placing and removing -------------------------------------------------------------------

--- Make a bank tile into a working bank: an IsoGenerator, the only thing that powers the
--- squares around it, with the tile's container for its batteries. `from`, a placed bank
--- tile that isn't a generator yet, hands over its container and modData.
local function makeBank(square, spriteName, index, from)
    local container = from and from:getContainer()
    local modData = {}
    if from then
        for key, value in pairs(from:getModData()) do
            modData[key] = value
        end
        square:transmitRemoveItemFromSquare(from)
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
        -- Neither saved nor sent, so every side sets it on its own copy.
        container:setAcceptItemFunction(ACCEPT_FUNCTION)
    end
    generator:transmitCompleteItemToClients()
    -- On a server each of these syncs the generator, which names it by its index on the
    -- square, so they come after the clients have it.
    generator:setCondition(100)
    generator:setFuel(10)
    generator:setConnected(true)
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
    local name = isoObject:getSprite() and isoObject:getSprite():getName()
    if PowerBank.bankOfSprite(name) and not PowerBank.isBank(isoObject) then
        -- A bank tile placed as a moveable is a plain IsoObject.
        makeBank(isoObject:getSquare(), name, isoObject:getObjectIndex(), isoObject)
    elseif PowerBank.isBank(isoObject) then
        self:loadIsoObject(isoObject)
    elseif PowerBank.sourceKind(isoObject) then
        -- Placing a mount, rotating it (picked up and placed again) and world spawns all land
        -- here, with the modules the item carried.
        PowerBank.showCracks(isoObject)
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
        local bank = self:getLuaObjectOnSquare(isoObject:getSquare())
        if bank then
            self:removeLuaObject(bank)
        end
    elseif PowerBank.sourceKind(isoObject) then
        local x, y, z = isoObject:getX(), isoObject:getY(), isoObject:getZ()
        for i = 1, self:getLuaObjectCount() do
            local bank = self:getLuaObjectByIndex(i)
            if bank:removeSource(x, y, z) then
                bank:sendStatus()
            end
        end
    end
end

-- Clients ask only for a fresh status, which the status window may do from any distance. Every
-- job that changes a bank comes as a RenewableEnergyAction, whose complete() checks the character
-- is at it, so a forged command packet can't reach a bank from afar.
function BankSystem:OnClientCommand(command, player, args)
    if command == "refresh" then
        PowerBank.perform(player, command, args)
    end
end

-- Map loading ----------------------------------------------------------------------------

-- A bank's chunk loaded. Rebuild a bank tile that isn't a working bank (a placement that
-- failed halfway, a map or stash placing the bare tile) so a reload repairs it.
local function loadBank(isoObject)
    if not PowerBank.isBank(isoObject) or not isoObject:getContainer() then
        makeBank(isoObject:getSquare(), isoObject:getSprite():getName(), isoObject:getObjectIndex(), isoObject)
        return
    end
    isoObject:getContainer():setAcceptItemFunction(ACCEPT_FUNCTION)
    BankSystem.instance:loadIsoObject(isoObject)
end

for _, name in ipairs(PowerBank.bankSprites()) do
    MapObjects.OnLoadWithSprite(name, loadBank, LOAD_PRIORITY)
end

-- A panel's chunk loaded: its overlays were saved with it, but a save from before the mod drew
-- cracks has none.
local mountSprites = { RenewableEnergy.Sprites.flat }
for _, mount in ipairs({ "wall", "rack" }) do
    for _, facings in pairs(RenewableEnergy.Sprites[mount]) do
        for _, name in pairs(facings) do
            table.insert(mountSprites, name)
        end
    end
end
MapObjects.OnLoadWithSprite(mountSprites, PowerBank.showCracks, LOAD_PRIORITY)

-- The charge pass ------------------------------------------------------------------------

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
        local cache = {}
        return function(kind, facing)
            local key = kind .. (facing or "")
            if not cache[key] then
                local total = 0
                for _, sun in ipairs(suns) do
                    total = total + Sun.planeIrradiance(sun, kind, facing, skies)
                end
                cache[key] = total / steps
            end
            return cache[key]
        end
    end
    return {
        weather = weather,
        precipitation = climate:getPrecipitationIntensity(),
        airC = climate:getTemperature(),
        elevation = Sun.elevation(),
        stormHours = Bank.stormHours(hours),
        irradiance = averaged(weather),
        clearIrradiance = averaged(Sun.CLEAR_WEATHER),
    }
end

-- Game hours since the bank's last pass, at most LONGEST_PASS, and the pass's end time.
local function passHours(bank)
    local now = getGameTime():getWorldAgeHours()
    return math.min(LONGEST_PASS, now - (bank.lastHour or now)), now
end

--- Bring one bank up to now.
function BankSystem.updateBank(bank)
    local hours, now = passHours(bank)
    bank.lastHour = now
    if hours > 0 then
        bank:update(hours, BankSystem.passContext(hours))
    end
end

function BankSystem.updateAll()
    local self = BankSystem.instance
    local contexts = {}
    for i = 1, self:getLuaObjectCount() do
        local bank = self:getLuaObjectByIndex(i)
        local hours, now = passHours(bank)
        bank.lastHour = now
        if hours > 0 then
            -- Banks placed at different times run different spans; each span's light is
            -- worked out once.
            local key = string.format("%.4f", hours)
            contexts[key] = contexts[key] or BankSystem.passContext(hours)
            bank:update(hours, contexts[key])
        end
    end
end

SGlobalObjectSystem.RegisterSystemClass(BankSystem)

return BankSystem
