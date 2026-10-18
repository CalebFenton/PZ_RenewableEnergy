if isClient() then
    return
end

require "Moveables/ISMoveableSpriteProps"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/BankSystem"
require "RenewableEnergy/PowerBank/Commands"

-- Battery banks, crates of solar gear and panels that the mod places in the world: in sheds,
-- garages and storage rooms the first time someone sees them, and at the named solar sites of
-- SolarSites.lua. Each container is stocked once, when it appears, and is explored, so neither
-- the room's loot nor loot respawn ever fills it.

RenewableEnergy = RenewableEnergy or {}
local WorldSpawns = {}
RenewableEnergy.WorldSpawns = WorldSpawns

local Sprites = RenewableEnergy.Sprites
local Specs = RenewableEnergy.Specs
local PowerBank = RenewableEnergy.PowerBank
local Battery = RenewableEnergy.Battery
local MODULE = Specs.factoryModule

-- Module conditions. A cracked module lies in a garage with a broken cover glass; a weathered
-- one has stood on a roof since the late 1980s. Site panels and crates hold a mix of both.
WorldSpawns.CRACKED = { min = 20, max = 50 }
WorldSpawns.WEATHERED = { min = 60, max = 100 }
WorldSpawns.SITE_CRACKED_SHARE = 0.35

-- Rooms that may hold a bank, the bank's stock, and one in how many of them does at the
-- Uncommon setting.
WorldSpawns.BANK_ROOMS = {
    shed = { odds = 12, stock = "shed" },
    garagestorage = { odds = 12, stock = "shed" },
    storageunit = { odds = 12, stock = "storageUnit" },
    farmstorage = { odds = 8, stock = "farmStorage" },
    electronicsstorage = { odds = 3, stock = "electronicsStorage" },
}
WorldSpawns.CRATE_ROOMS = { garagestorage = 33, storageunit = 16 }
-- The odds above are multiplied by these for each Battery Bank Spawn setting. Crates follow the
-- same setting.
WorldSpawns.RARITY = { nil, 10, 3, 1 }

local CAR_BATTERIES = {
    { "Base.CarBattery1", 4 }, { "Base.CarBattery2", 3 }, { "Base.CarBattery3", 2 },
}
local function withTypes(base, extra)
    local types = {}
    for _, entry in ipairs(base) do
        table.insert(types, entry)
    end
    for _, entry in ipairs(extra) do
        table.insert(types, entry)
    end
    return types
end

-- What a bank holds when it appears, by stock name: its tile (a Sprites field); batteries, a
-- count from min to max of types picked by weight, era batteries of the kind someone in 1993
-- would have wired to it; and for each other part the chance of one and its type by weight.
-- Chargers are vanilla's Car Battery Charger, which kept many a cabin battery topped up.
WorldSpawns.BANK_STOCK = {
    shed = {
        sprite = "batteryBoxWood",
        batteries = { min = 1, max = 2, types = withTypes(CAR_BATTERIES, { { "RenewableEnergy.DeepCycleBattery", 2 } }) },
        inverter = { chance = 0.4, types = { { "RenewableEnergy.PlugInInverter", 1 } } },
        charger = { chance = 0.3, types = { { Specs.charger, 1 } } },
    },
    storageUnit = {
        sprite = "batteryBoxMetal",
        batteries = { min = 1, max = 2, types = withTypes(CAR_BATTERIES, { { "RenewableEnergy.DeepCycleBattery", 3 } }) },
        inverter = { chance = 0.4, types = { { "RenewableEnergy.PlugInInverter", 2 }, { "RenewableEnergy.PowerInverter", 1 } } },
        charger = { chance = 0.3, types = { { Specs.charger, 1 } } },
    },
    farmStorage = {
        sprite = "batteryRackWood",
        batteries = { min = 2, max = 6, types = withTypes(CAR_BATTERIES, { { "RenewableEnergy.DeepCycleBattery", 9 } }) },
        inverter = { chance = 0.5, types = { { "RenewableEnergy.PowerInverter", 1 } } },
        controller = { chance = 0.3, types = { { Specs.controller, 1 } } },
        charger = { chance = 0.4, types = { { Specs.charger, 1 } } },
    },
    electronicsStorage = {
        sprite = "batteryRackMetal",
        batteries = { min = 2, max = 8, types = {
            { "RenewableEnergy.DeepCycleBattery", 7 }, { "RenewableEnergy.L16Battery", 2 },
        } },
        inverter = { chance = 0.5, types = {
            { "RenewableEnergy.PowerInverter", 4 }, { "RenewableEnergy.InverterCharger", 1 },
        } },
        controller = { chance = 0.3, types = { { Specs.controller, 1 } } },
        charger = { chance = 0.3, types = { { Specs.charger, 1 } } },
    },
    -- The named sites' banks.
    farmHouse = {
        sprite = "batteryBoxWood",
        batteries = { min = 1, max = 2, types = withTypes(CAR_BATTERIES, { { "RenewableEnergy.DeepCycleBattery", 9 } }) },
        inverter = { chance = 0.7, types = { { "RenewableEnergy.PlugInInverter", 1 } } },
        charger = { chance = 0.5, types = { { Specs.charger, 1 } } },
    },
    camper = {
        sprite = "batteryBoxWood",
        batteries = { min = 1, max = 1, types = { { "RenewableEnergy.DeepCycleBattery", 1 } } },
        inverter = { chance = 0.6, types = { { "RenewableEnergy.PlugInInverter", 1 } } },
    },
    ranger = {
        sprite = "batteryBoxMetal",
        batteries = { min = 2, max = 2, types = { { "RenewableEnergy.DeepCycleBattery", 1 } } },
        inverter = { chance = 0.8, types = { { "RenewableEnergy.PowerInverter", 1 } } },
        charger = { chance = 0.5, types = { { Specs.charger, 1 } } },
    },
    relay = {
        sprite = "batteryRackMetal",
        batteries = { min = 4, max = 8, types = { { "RenewableEnergy.L16Battery", 1 } } },
        inverter = { chance = 1, types = { { "RenewableEnergy.InverterCharger", 1 } } },
        controller = { chance = 0.5, types = { { Specs.controller, 1 } } },
    },
    powerYard = {
        sprite = "batteryBankMetal",
        batteries = { min = 6, max = 12, types = { { "RenewableEnergy.L16Battery", 1 } } },
        inverter = { chance = 1, types = { { "RenewableEnergy.InverterCharger", 1 } } },
        controller = { chance = 1, types = { { Specs.controller, 1 } } },
        charger = { chance = 0.5, types = { { Specs.charger, 1 } } },
    },
}

-- What a crate holds, by stock name: lines of { item, min, max, loot rarity option } (count
-- scaled by the option; none: always the count). Modules get a site module's condition.
WorldSpawns.CRATE_STOCK = {
    -- An RV or cabin solar kit someone put away in a garage or storage unit.
    kit = {
        { MODULE, 1, 2, "LRMSolarPanels" },
        { "RenewableEnergy.DeepCycleBattery", 1, 2, "LRMBatteries" },
        { "RenewableEnergy.ChargeController", 0, 1, "LRMMisc" },
        { "RenewableEnergy.PowerInverter", 0, 1, "LRMMisc" },
        { "RenewableEnergy.HomesteadPowerMag1", 0, 1, "LRMMisc" },
        { "Base.ElectricWire", 4, 8 },
        { "Base.Screws", 1, 2 },
    },
    -- The power company's spares for its pilot solar installations.
    powerYard = {
        { MODULE, 3, 5, "LRMSolarPanels" },
        { "RenewableEnergy.HomesteadPowerMag2", 1, 1, "LRMMisc" },
        { "RenewableEnergy.BatteryElectrolyte", 1, 3, "LRMBatteries" },
        { "RenewableEnergy.ChargeController", 0, 1, "LRMMisc" },
        { "Base.ElectricWire", 6, 12 },
    },
}

-- Module conditions

--- A whole number from range.min to range.max, both included.
function WorldSpawns.rollBetween(range)
    return ZombRand(range.min, range.max + 1)
end

function WorldSpawns.crackedCondition()
    return WorldSpawns.rollBetween(WorldSpawns.CRACKED)
end

function WorldSpawns.weatheredCondition()
    return WorldSpawns.rollBetween(WorldSpawns.WEATHERED)
end

-- A site module's condition: cracked or weathered.
local function siteModuleCondition()
    if ZombRandFloat(0, 1) < WorldSpawns.SITE_CRACKED_SHARE then
        return WorldSpawns.crackedCondition()
    end
    return WorldSpawns.weatheredCondition()
end

--- `count` factory modules at site conditions, as a mount's PowerBank.MODULES list.
function WorldSpawns.siteModules(count)
    local modules = {}
    for i = 1, count do
        modules[i] = { type = MODULE, condition = siteModuleCondition() }
    end
    return modules
end

--- Adds a factory module at `condition` to the container.
function WorldSpawns.addModule(container, condition)
    local item = container:AddItem(MODULE)
    if item then
        RenewableEnergy.Wear.setCondition(item, condition)
    end
    return item
end

-- Stocking

--- `count` × `multiplier`, rounded up or down at random so that the average scales exactly: a
--- rarity of 0.5 halves the items on average, even where the count is 1.
function WorldSpawns.scaled(count, multiplier)
    local expected = count * multiplier
    local whole = math.floor(expected)
    return ZombRandFloat(0, 1) < expected - whole and whole + 1 or whole
end

local function pickByWeight(types)
    local total = 0
    for _, entry in ipairs(types) do
        total = total + entry[2]
    end
    local roll = ZombRandFloat(0, total)
    for _, entry in ipairs(types) do
        roll = roll - entry[2]
        if roll < 0 then
            return entry[1]
        end
    end
    return types[#types][1]
end

local function addFound(container, fullType)
    if fullType == MODULE then
        return WorldSpawns.addModule(container, siteModuleCondition())
    end
    local item = container:AddItem(fullType)
    if item and Battery.isBattery(item) then
        Battery.setFoundCharge(item)
    end
    return item
end

-- Adds one of `part`'s types with its chance × `multiplier`, if the bank has a slot for it.
local function maybeAddPart(container, part, multiplier, slots)
    if part and slots > 0 and ZombRandFloat(0, 1) < part.chance * multiplier then
        addFound(container, pickByWeight(part.types))
    end
end

--- Fills a bank's container as BANK_STOCK[stockName] says, scaled by the loot rarity options,
--- its batteries at a part charge.
---@param container ItemContainer
---@param stockName string a BANK_STOCK key
function WorldSpawns.stockBank(container, stockName)
    local stock = WorldSpawns.BANK_STOCK[stockName]
    local spec = PowerBank.bankOfSprite(Sprites[stock.sprite]).spec
    local options = SandboxVars.RenewableEnergy
    local batteries = WorldSpawns.scaled(WorldSpawns.rollBetween(stock.batteries), options.LRMBatteries)
    for _ = 1, math.min(batteries, spec.maxBatteries) do
        addFound(container, pickByWeight(stock.batteries.types))
    end
    maybeAddPart(container, stock.inverter, options.LRMMisc, spec.maxInverters)
    maybeAddPart(container, stock.controller, options.LRMMisc, spec.maxControllers)
    maybeAddPart(container, stock.charger, options.LRMMisc, spec.maxChargers)
end

--- Fills a crate as CRATE_STOCK[stockName] says.
---@param container ItemContainer
---@param stockName string a CRATE_STOCK key
function WorldSpawns.stockCrate(container, stockName)
    for _, line in ipairs(WorldSpawns.CRATE_STOCK[stockName]) do
        local count = ZombRand(line[2], line[3] + 1)
        if line[4] then
            count = WorldSpawns.scaled(count, SandboxVars.RenewableEnergy[line[4]])
        end
        for _ = 1, count do
            addFound(container, line[1])
        end
    end
end

-- Placing

--- Places a bank stocked as BANK_STOCK[stockName] says, connected and switched off. Banks stand
--- only indoors (PowerBank.canPlaceBank), so nothing is placed on another square.
---@param square IsoGridSquare
---@param stockName string a BANK_STOCK key
---@return IsoGenerator?
function WorldSpawns.placeBank(square, stockName)
    if not PowerBank.canPlaceBank(square) then
        print("RenewableEnergy: no bank at " .. square:getX() .. "," .. square:getY() .. "," .. square:getZ() .. ", which is not indoors")
        return nil
    end
    local bank = PowerBank.place(square, Sprites[WorldSpawns.BANK_STOCK[stockName].sprite], -1)
    local container = bank:getContainer()
    WorldSpawns.stockBank(container, stockName)
    -- PowerBank.place sent the bank to the clients while it was empty.
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        sendAddItemToContainer(container, items:get(i))
    end
    RenewableEnergy.BankSystem.instance:getLuaObjectOnSquare(square):refresh()
    return bank
end

--- Places a crate of solar gear stocked as CRATE_STOCK[stockName] says, with the lid overlay
--- vanilla gives a filled container (CrateOverlays.lua), as ItemPickerJava does after filling one.
---@param square IsoGridSquare
---@param stockName string a CRATE_STOCK key
---@return IsoObject
function WorldSpawns.placeCrate(square, stockName)
    local crate = IsoObject.new(square:getCell(), square, Sprites.crate)
    crate:createContainersFromSpriteProperties()
    local container = crate:getContainer()
    WorldSpawns.stockCrate(container, stockName)
    container:setExplored(true)
    square:AddSpecialObject(crate)
    if isServer() then
        crate:transmitCompleteItemToClients()
    end
    -- After the clients have the crate: on a server this sends its overlay, naming the crate by its
    -- index on the square (IsoObject.setOverlaySprite).
    ItemPickerJava.updateOverlaySprite(crate)
    -- The game fires OnObjectAdded only for an object a client sends (AddItemToMapPacket), so an
    -- object Lua places fires it itself, as vanilla's TrapBO does.
    triggerEvent("OnObjectAdded", crate)
    return crate
end

--- Places a moveable tile the way a player's placing it would, from the item its tile gives
--- back, carrying `modData` (keys copied onto the item, which placing copies onto the object).
---@param square IsoGridSquare
---@param spriteName string a mount tile of Sprites, or a garden light
---@param modData table?
function WorldSpawns.placeMoveable(square, spriteName, modData)
    local sprite = getSprite(spriteName)
    local item = instanceItem(sprite:getProperties():get("CustomItem"))
    for key, value in pairs(modData or {}) do
        item:getModData()[key] = value
    end
    ISMoveableSpriteProps.new(sprite):placeMoveableInternal(nil, square, item, spriteName)
end

--- Places a panel mount holding `modules` (a PowerBank.MODULES list).
function WorldSpawns.placePanel(square, spriteName, modules)
    WorldSpawns.placeMoveable(square, spriteName, { [PowerBank.MODULES] = modules })
end

-- Rooms seen for the first time

local function oneIn(n)
    return ZombRand(n) == 0
end

local INDOOR_TRIES = 10

-- A free square of the room where a bank may stand, or nil.
local function indoorSquare(room)
    for _ = 1, INDOOR_TRIES do
        local square = room:getRandomFreeSquare()
        if square and PowerBank.canPlaceBank(square) then
            return square
        end
    end
    return nil
end

local function onSeeNewRoom(room)
    local rarity = WorldSpawns.RARITY[SandboxVars.RenewableEnergy.BatteryBankSpawn]
    if not rarity then
        return
    end
    local name = room:getName()
    local bank = WorldSpawns.BANK_ROOMS[name]
    if bank and oneIn(bank.odds * rarity) then
        local square = indoorSquare(room)
        if square then
            WorldSpawns.placeBank(square, bank.stock)
        end
    end
    local crateOdds = WorldSpawns.CRATE_ROOMS[name]
    if crateOdds and oneIn(crateOdds * rarity) then
        local square = room:getRandomFreeSquare()
        if square then
            WorldSpawns.placeCrate(square, "kit")
        end
    end
end

-- Fires on the server and in single player (IsoCell.ProcessSpottedRooms), once per room.
Events.OnSeeNewRoom.Add(onSeeNewRoom)

return WorldSpawns
