-- Battery banks and crates of solar gear that the mod places in the world: in sheds, garages and
-- storage rooms the first time someone sees them, and at the named solar sites of SolarSites.lua.
-- What each holds, as stock tables; its items are worn and charged as finds (Finds). Each
-- container is stocked once, when it appears, and is explored, so neither the room's loot nor
-- loot respawn ever fills it.

if isClient() then return end

local Sprites = require "RenewableEnergy/Sprites"
local Specs = require "RenewableEnergy/Specs"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local BankSystem = require "RenewableEnergy/PowerBank/BankSystem"
local Finds = require "RenewableEnergy/Items/Finds"
local Place = require "RenewableEnergy/World/Place"
local Chance = require "cf_commonlib/Chance"
local Items = require "cf_commonlib/Items"
local Squares = require "cf_commonlib/Squares"

local WorldSpawns = {}

local MODULE = Specs.factoryModule

-- Rooms that may hold a bank, the bank's stock, and one in how many of them does at the
-- Uncommon setting. Garages are many, so theirs is rarer: a battery box in every few streets
-- reads as a bank on every corner.
WorldSpawns.BANK_ROOMS = {
    shed = { odds = 12, stock = "shed" },
    garagestorage = { odds = 24, stock = "shed" },
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
-- would have wired to it, worn as their `wear` (a Finds.BATTERY_WEAR profile) says; and for each
-- other part the chance of one and its type by weight. `modules`, for a bank a room spawns, is the
-- chance of min to max factory modules lying beside it (layModulesBeside), so that a battery box
-- seldom stands with nothing to charge it. One lucky find gives a good start, not a finished house.
WorldSpawns.BANK_STOCK = {
    shed = {
        sprite = "batteryBoxWood",
        batteries = { min = 1, max = 2, wear = "worn", types = withTypes(CAR_BATTERIES, { { "RenewableEnergy.DeepCycleBattery", 2 } }) },
        inverter = { chance = 0.4, types = { { "RenewableEnergy.PlugInInverter", 1 } } },
        charger = { chance = 0.3, types = { { Specs.charger, 1 } } },
        modules = { chance = 0.6, min = 1, max = 2 },
    },
    storageUnit = {
        sprite = "batteryBoxMetal",
        batteries = { min = 1, max = 2, wear = "used", types = withTypes(CAR_BATTERIES, { { "RenewableEnergy.DeepCycleBattery", 3 } }) },
        inverter = { chance = 0.4, types = { { "RenewableEnergy.PlugInInverter", 2 }, { "RenewableEnergy.PowerInverter", 1 } } },
        charger = { chance = 0.3, types = { { Specs.charger, 1 } } },
        modules = { chance = 0.6, min = 1, max = 2 },
    },
    farmStorage = {
        sprite = "batteryRackWood",
        batteries = { min = 3, max = 5, wear = "worn", types = withTypes(CAR_BATTERIES, { { "RenewableEnergy.DeepCycleBattery", 21 } }) },
        inverter = { chance = 0.5, types = { { "RenewableEnergy.PowerInverter", 1 } } },
        controller = { chance = 0.3, types = { { Specs.controller, 1 } } },
        charger = { chance = 0.4, types = { { Specs.charger, 1 } } },
    },
    electronicsStorage = {
        sprite = "batteryRackMetal",
        batteries = { min = 4, max = 6, wear = "stock", types = {
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
        batteries = { min = 1, max = 2, wear = "used", types = withTypes(CAR_BATTERIES, { { "RenewableEnergy.DeepCycleBattery", 9 } }) },
        inverter = { chance = 0.7, types = { { "RenewableEnergy.PlugInInverter", 1 } } },
        charger = { chance = 0.5, types = { { Specs.charger, 1 } } },
    },
    camper = {
        sprite = "batteryBoxWood",
        batteries = { min = 1, max = 1, wear = "used", types = { { "RenewableEnergy.DeepCycleBattery", 1 } } },
        inverter = { chance = 0.6, types = { { "RenewableEnergy.PlugInInverter", 1 } } },
    },
    ranger = {
        sprite = "batteryBoxMetal",
        batteries = { min = 2, max = 2, wear = "used", types = { { "RenewableEnergy.DeepCycleBattery", 1 } } },
        inverter = { chance = 0.8, types = { { "RenewableEnergy.PowerInverter", 1 } } },
        charger = { chance = 0.5, types = { { Specs.charger, 1 } } },
    },
    relay = {
        sprite = "batteryRackMetal",
        batteries = { min = 4, max = 6, wear = "used", types = { { "RenewableEnergy.L16Battery", 1 } } },
        inverter = { chance = 1, types = { { "RenewableEnergy.InverterCharger", 1 } } },
        controller = { chance = 0.5, types = { { Specs.controller, 1 } } },
    },
    powerYard = {
        sprite = "batteryBankMetal",
        batteries = { min = 6, max = 8, wear = "used", types = { { "RenewableEnergy.L16Battery", 1 } } },
        inverter = { chance = 1, types = { { "RenewableEnergy.InverterCharger", 1 } } },
        controller = { chance = 1, types = { { Specs.controller, 1 } } },
        charger = { chance = 0.5, types = { { Specs.charger, 1 } } },
    },
    -- A wind farm's rack, its batteries tired from years on an old wind charger.
    windFarm = {
        sprite = "batteryRackWood",
        batteries = { min = 2, max = 4, wear = "tired", types = { { "RenewableEnergy.DeepCycleBattery", 1 } } },
        inverter = { chance = 0.6, types = { { "RenewableEnergy.PlugInInverter", 2 }, { "RenewableEnergy.PowerInverter", 1 } } },
    },
}

-- How used a crate's batteries are, as a Finds.BATTERY_WEAR profile: crates hold gear put away
-- after use.
WorldSpawns.CRATE_WEAR = "used"

-- What a crate holds, by stock name: lines of { item, min, max, loot rarity option } (count
-- scaled by the option; none: always the count). Modules get a site module's condition, and
-- batteries CRATE_WEAR's.
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

-- Stocking

-- Adds one of `part`'s types with its chance × the Misc rarity, if the bank has a slot for it.
local function maybeAddPart(container, part, slots)
    if part and slots > 0 and Chance.hit(part.chance * SandboxVars.RenewableEnergy.LRMMisc) then
        Finds.add(container, Chance.pickWeighted(part.types))
    end
end

--- Fills a bank's container as BANK_STOCK[stockName] says, scaled by the loot rarity options,
--- its batteries at a part charge.
---@param container ItemContainer
---@param stockName string a BANK_STOCK key
function WorldSpawns.stockBank(container, stockName)
    local stock = WorldSpawns.BANK_STOCK[stockName]
    local spec = PowerBank.bankOfSprite(Sprites[stock.sprite].S).spec
    local batteries = Finds.scaled(Chance.between(stock.batteries.min, stock.batteries.max), "LRMBatteries")
    for _ = 1, math.min(batteries, spec.maxBatteries) do
        Finds.add(container, Chance.pickWeighted(stock.batteries.types), stock.batteries.wear)
    end
    maybeAddPart(container, stock.inverter, spec.maxInverters)
    maybeAddPart(container, stock.controller, spec.maxControllers)
    maybeAddPart(container, stock.charger, spec.maxChargers)
end

--- Fills a crate as CRATE_STOCK[stockName] says.
---@param container ItemContainer
---@param stockName string a CRATE_STOCK key
function WorldSpawns.stockCrate(container, stockName)
    for _, line in ipairs(WorldSpawns.CRATE_STOCK[stockName]) do
        local count = Chance.between(line[2], line[3])
        if line[4] then
            count = Finds.scaled(count, line[4])
        end
        for _ = 1, count do
            Finds.add(container, line[1], WorldSpawns.CRATE_WEAR)
        end
    end
end

--- Places a bank stocked as BANK_STOCK[stockName] says, connected and switched off, its back to a
--- wall (Place.bankFacing). Banks stand only indoors (PowerBank.canPlaceBank), so nothing is
--- placed on another square.
---@param square IsoGridSquare
---@param stockName string a BANK_STOCK key
---@return IsoGenerator?
function WorldSpawns.placeBank(square, stockName)
    if not PowerBank.canPlaceBank(square) then
        print("RenewableEnergy: no bank at " .. square:getX() .. "," .. square:getY() .. "," .. square:getZ() .. ", which is not indoors")
        return nil
    end
    local sprite = Sprites[WorldSpawns.BANK_STOCK[stockName].sprite][Place.bankFacing(square)]
    return BankSystem.place(square, sprite, nil, function(container)
        WorldSpawns.stockBank(container, stockName)
    end)
end

--- Places a crate of solar gear stocked as CRATE_STOCK[stockName] says (Place.crate).
---@param square IsoGridSquare
---@param stockName string a CRATE_STOCK key
---@return IsoObject
function WorldSpawns.placeCrate(square, stockName)
    return Place.crate(square, function(container)
        WorldSpawns.stockCrate(container, stockName)
    end)
end

-- Rooms seen for the first time

local function oneIn(n)
    return Chance.hit(1 / n)
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

--- Lays the modules BANK_STOCK[stockName] puts beside a bank a room spawned on `square`, if its
--- chance comes up: each on the floor of a free square of the bank's room next to it, or at the
--- bank's foot. Returns how many it laid.
---@param square IsoGridSquare
---@param stockName string a BANK_STOCK key
function WorldSpawns.layModulesBeside(square, stockName)
    local spec = WorldSpawns.BANK_STOCK[stockName].modules
    if not (spec and Chance.hit(spec.chance)) then
        return 0
    end
    local room, beside = square:getRoom(), {}
    Squares.eachAround(square:getX(), square:getY(), square:getZ(), 1, function(near)
        if near ~= square and near:getRoom() == room and near:isFree(false) then
            table.insert(beside, near)
        end
    end)
    local count = Finds.scaled(Chance.between(spec.min, spec.max), "LRMSolarPanels")
    for i = 1, count do
        local item = Finds.newModule(Finds.siteModuleCondition())
        local floor = beside[(i - 1) % math.max(1, #beside) + 1] or square
        Items.dropOn(floor, item)
    end
    return count
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
        if square and WorldSpawns.placeBank(square, bank.stock) then
            WorldSpawns.layModulesBeside(square, bank.stock)
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
