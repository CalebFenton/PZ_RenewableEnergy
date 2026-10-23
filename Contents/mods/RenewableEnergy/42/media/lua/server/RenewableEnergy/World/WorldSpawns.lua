if isClient() then
    return
end

require "Moveables/ISMoveableSpriteProps"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Chance"
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
local Chance = RenewableEnergy.Chance
local MODULE = Specs.factoryModule

-- Module conditions. A cracked module lies in a garage with a broken cover glass; a weathered
-- one has stood on a roof since the late 1980s. Site panels and crates hold a mix of both.
WorldSpawns.CRACKED = { min = 20, max = 50 }
WorldSpawns.WEATHERED = { min = 60, max = 100 }
WorldSpawns.SITE_CRACKED_SHARE = 0.35
-- How used the batteries of a found bank or crate are, by profile: a condition about `mean`, give
-- or take a third of `halfWidth`, never further off than `halfWidth` and no better than new; and
-- the chance `dud` of a dud (DUD). Batteries where the danger is come better than the quiet
-- countryside's (docs/design.md, risk buys reward). Repairs stop at Recipes.REPAIR_LIMIT, so a
-- worn battery is worth reconditioning, a used one hardly, and store stock needs none.
WorldSpawns.BATTERY_WEAR = {
    -- Years on an old wind charger.
    tired = { mean = 50, halfWidth = 15 },
    -- Sheds, garages and farm storerooms: never as good as new.
    worn = { mean = 65, halfWidth = 30, dud = 0.08 },
    -- Homesteads, storage units and utility sites: a few as good as new.
    used = { mean = 80, halfWidth = 35, dud = 0.04 },
    -- An electronics store's backstock: nearly new.
    stock = { mean = 95, halfWidth = 15 },
}
-- A dud: nearly dead, condition from min to max, and nursed along with `repairs` repairs, which
-- leave its repair limit too low for reconditioning to pay. Stripped, it still gives a whole
-- battery's case, plates and acid for a rebuild.
WorldSpawns.DUD = { min = 5, max = 20, repairs = 5 }

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
-- would have wired to it, worn as their `wear` (a BATTERY_WEAR profile) says; and for each other
-- part the chance of one and its type by weight. `modules`, for a bank a room spawns, is the
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

-- How used a crate's batteries are, as a BATTERY_WEAR profile: crates hold gear put away after use.
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

-- Module conditions

function WorldSpawns.crackedCondition()
    return Chance.between(WorldSpawns.CRACKED.min, WorldSpawns.CRACKED.max)
end

function WorldSpawns.weatheredCondition()
    return Chance.between(WorldSpawns.WEATHERED.min, WorldSpawns.WEATHERED.max)
end

-- A site module's condition: cracked or weathered.
local function siteModuleCondition()
    if Chance.hit(WorldSpawns.SITE_CRACKED_SHARE) then
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
    return Chance.hit(expected - whole) and whole + 1 or whole
end

local function pickByWeight(types)
    local total = 0
    for _, entry in ipairs(types) do
        total = total + entry[2]
    end
    local roll = Chance.roll() * total
    for _, entry in ipairs(types) do
        roll = roll - entry[2]
        if roll < 0 then
            return entry[1]
        end
    end
    return types[#types][1]
end

--- The condition, in percent of new, that the BATTERY_WEAR profile `wear` gives a found battery
--- that isn't a dud, from three rolls (each 0 up to 1): their mean bunches it around the profile's
--- mean like a bell curve with no tails past halfWidth, and it is no better than new.
function WorldSpawns.foundBatteryPercent(wear, roll1, roll2, roll3)
    local spread = (roll1 + roll2 + roll3) / 3 * 2 - 1
    return math.min(100, wear.mean + wear.halfWidth * spread)
end

--- Wears the found battery `item` as the BATTERY_WEAR profile `wearName` says: a dud at DUD's
--- condition with its repairs, or at WorldSpawns.foundBatteryPercent. Sends nothing.
function WorldSpawns.wearFoundBattery(item, wearName)
    local wear = WorldSpawns.BATTERY_WEAR[wearName]
    local percent
    if wear.dud and Chance.hit(wear.dud) then
        local dud = WorldSpawns.DUD
        percent = Chance.between(dud.min, dud.max)
        item:setHaveBeenRepaired(dud.repairs)
    else
        percent = WorldSpawns.foundBatteryPercent(wear, Chance.roll(), Chance.roll(), Chance.roll())
    end
    RenewableEnergy.Wear.setCondition(item, math.floor(item:getConditionMax() * percent / 100 + 0.5))
end

-- Adds a found `fullType` to the container; a battery is worn as the BATTERY_WEAR profile
-- `wearName` says and given a part charge.
local function addFound(container, fullType, wearName)
    if fullType == MODULE then
        return WorldSpawns.addModule(container, siteModuleCondition())
    end
    local item = container:AddItem(fullType)
    if item and Battery.isBattery(item) then
        WorldSpawns.wearFoundBattery(item, wearName)
        Battery.setFoundCharge(item)
    end
    return item
end

-- Adds one of `part`'s types with its chance × `multiplier`, if the bank has a slot for it.
local function maybeAddPart(container, part, multiplier, slots)
    if part and slots > 0 and Chance.hit(part.chance * multiplier) then
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
    local batteries = WorldSpawns.scaled(Chance.between(stock.batteries.min, stock.batteries.max), options.LRMBatteries)
    for _ = 1, math.min(batteries, spec.maxBatteries) do
        addFound(container, pickByWeight(stock.batteries.types), stock.batteries.wear)
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
        local count = Chance.between(line[2], line[3])
        if line[4] then
            count = WorldSpawns.scaled(count, SandboxVars.RenewableEnergy[line[4]])
        end
        for _ = 1, count do
            addFound(container, line[1], WorldSpawns.CRATE_WEAR)
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
    return WorldSpawns.placeBankWith(square, Sprites[WorldSpawns.BANK_STOCK[stockName].sprite], function(container)
        WorldSpawns.stockBank(container, stockName)
    end)
end

--- Places a connected, switched-off bank of tile `spriteName` (a bank's Sprites field value) on
--- `square`, its container filled by `fill(container)` and sent to the clients, wherever the
--- square is: placeBank decides where a world bank may stand.
---@return IsoGenerator
function WorldSpawns.placeBankWith(square, spriteName, fill)
    local bank = PowerBank.place(square, spriteName, -1)
    local container = bank:getContainer()
    fill(container)
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
    RenewableEnergy.eachSquareAround(square:getX(), square:getY(), square:getZ(), 1, function(near)
        if near ~= square and near:getRoom() == room and near:isFree(false) then
            table.insert(beside, near)
        end
    end)
    local count = WorldSpawns.scaled(Chance.between(spec.min, spec.max), SandboxVars.RenewableEnergy.LRMSolarPanels)
    for i = 1, count do
        local item = instanceItem(MODULE)
        RenewableEnergy.Wear.setCondition(item, siteModuleCondition())
        local floor = beside[(i - 1) % math.max(1, #beside) + 1] or square
        floor:AddWorldInventoryItem(item, ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8), 0)
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
