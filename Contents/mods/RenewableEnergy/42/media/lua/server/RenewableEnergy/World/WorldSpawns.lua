if isClient() then
    return
end

require "Moveables/ISMoveableSpriteProps"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/BankSystem"
require "RenewableEnergy/PowerBank/Commands"

-- Battery banks and crates of solar gear that the mod places in the world: in sheds, garages and
-- storage rooms the first time someone sees them (design §7), and at the fixed spots of
-- FixedSpawns.lua. Each is stocked once, when it appears, and is explored, so neither the room's
-- loot nor loot respawn ever fills it.

local WorldSpawns = {}
RenewableEnergy.WorldSpawns = WorldSpawns

local Sprites = RenewableEnergy.Sprites

-- Rooms that may hold a bank, and one in how many of them does at the Uncommon setting. A garage
-- or shed holds a homemade battery box; a farm or a store room, a rack.
WorldSpawns.BANK_ROOMS = {
    shed = { odds = 12, sprite = "batteryBox" },
    garagestorage = { odds = 12, sprite = "batteryBox" },
    storageunit = { odds = 12, sprite = "batteryBox" },
    farmstorage = { odds = 8, sprite = "batteryBank" },
    electronicsstorage = { odds = 3, sprite = "batteryBank" },
}
WorldSpawns.CRATE_ROOMS = { garagestorage = 33, storageunit = 16 }
-- The odds above are multiplied by these for each Battery Bank Spawn setting (None, Very rare,
-- Rare, Uncommon). Crates follow the same setting.
WorldSpawns.RARITY = { nil, 10, 3, 1 }

-- What a bank holds when it appears. Batteries: a count from min to max, of types picked by
-- weight, era batteries of the kind someone in 1993 would have wired to that bank. Inverter and
-- controllers: the chance of one, and its type by weight.
WorldSpawns.BANK_STOCK = {
    batteryBox = {
        batteries = { min = 1, max = 2, types = {
            { "Base.CarBattery1", 4 }, { "Base.CarBattery2", 3 }, { "Base.CarBattery3", 2 },
            { "RenewableEnergy.DeepCycleBattery", 2 },
        } },
        inverter = { chance = 0.4, types = { { "RenewableEnergy.PlugInInverter", 1 } } },
    },
    batteryBank = {
        batteries = { min = 2, max = 6, types = {
            { "RenewableEnergy.DeepCycleBattery", 7 }, { "Base.CarBattery1", 2 }, { "Base.CarBattery2", 2 },
            { "RenewableEnergy.L16Battery", 2 },
        } },
        inverter = { chance = 0.5, types = {
            { "RenewableEnergy.PowerInverter", 4 }, { "RenewableEnergy.InverterCharger", 1 },
        } },
        controller = { chance = 0.3, types = { { "RenewableEnergy.ChargeController", 1 } } },
    },
}

-- What a crate holds: an RV or cabin solar kit. A count from min to max of each, scaled by the
-- loot rarity option (none: always the count).
WorldSpawns.CRATE_STOCK = {
    { "RenewableEnergy.SolarModule", 2, 4, "LRMSolarPanels" },
    { "RenewableEnergy.DeepCycleBattery", 1, 2, "LRMBatteries" },
    { "RenewableEnergy.ChargeController", 0, 1, "LRMMisc" },
    { "RenewableEnergy.PowerInverter", 0, 1, "LRMMisc" },
    { "RenewableEnergy.HomesteadPowerMag1", 0, 1, "LRMMisc" },
    { "Base.ElectricWire", 4, 8 },
    { "Base.Screws", 1, 2 },
}

-- Stocking -----------------------------------------------------------------------------------------

-- `count` × `multiplier`, rounded up or down at random so that the average scales exactly: a
-- rarity of 0.5 halves the items on average, even where the count is 1.
local function scaled(count, multiplier)
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
    local item = container:AddItem(fullType)
    if item and RenewableEnergy.Battery.isBattery(item) then
        RenewableEnergy.Battery.setFoundCharge(item)
    end
    return item
end

-- Adds one of `part`'s types with its chance × `multiplier`.
local function maybeAddPart(container, part, multiplier)
    if part and ZombRandFloat(0, 1) < part.chance * multiplier then
        addFound(container, pickByWeight(part.types))
    end
end

local function bankSpecFor(spriteKey)
    for _, spec in pairs(RenewableEnergy.Specs.banks) do
        if spec.sprite == spriteKey then
            return spec
        end
    end
    return nil
end

--- Fills a bank's container with batteries at a part charge and maybe an inverter and a
--- controller, as BANK_STOCK says for its tile and the loot rarity options scale.
---@param container ItemContainer
---@param spriteKey string "batteryBox" or "batteryBank"
function WorldSpawns.stockBank(container, spriteKey)
    local stock = WorldSpawns.BANK_STOCK[spriteKey]
    local spec = bankSpecFor(spriteKey)
    local options = SandboxVars.RenewableEnergy
    local batteries = scaled(ZombRand(stock.batteries.min, stock.batteries.max + 1), options.LRMBatteries)
    for _ = 1, math.min(batteries, spec.maxBatteries) do
        addFound(container, pickByWeight(stock.batteries.types))
    end
    maybeAddPart(container, stock.inverter, options.LRMMisc)
    if spec.maxControllers > 0 then
        maybeAddPart(container, stock.controller, options.LRMMisc)
    end
end

--- Fills a crate as CRATE_STOCK says.
---@param container ItemContainer
function WorldSpawns.stockCrate(container)
    for _, line in ipairs(WorldSpawns.CRATE_STOCK) do
        local count = ZombRand(line[2], line[3] + 1)
        if line[4] then
            count = scaled(count, SandboxVars.RenewableEnergy[line[4]])
        end
        for _ = 1, count do
            addFound(container, line[1])
        end
    end
end

-- Placing ----------------------------------------------------------------------------------------

--- Places a stocked battery box or rack, connected and switched off.
---@param square IsoGridSquare
---@param spriteKey string "batteryBox" or "batteryBank"
---@return IsoGenerator
function WorldSpawns.placeBank(square, spriteKey)
    local bank = RenewableEnergy.PowerBank.place(square, Sprites[spriteKey], -1)
    WorldSpawns.stockBank(bank:getContainer(), spriteKey)
    RenewableEnergy.PowerBank.perform(nil, "refresh", { bank = { x = square:getX(), y = square:getY(), z = square:getZ() } })
    return bank
end

--- Places a stocked crate of solar gear. It shows its lid overlay as ItemPickerJava does for a
--- filled container (ContainerOverlays.updateContainerOverlaySprite: closed below 7 items), set
--- here without a transmit, because the clients get the whole object right after.
---@param square IsoGridSquare
---@return IsoObject
function WorldSpawns.placeCrate(square)
    local crate = IsoObject.new(square:getCell(), square, Sprites.crate)
    crate:createContainersFromSpriteProperties()
    local container = crate:getContainer()
    WorldSpawns.stockCrate(container)
    container:setExplored(true)
    square:AddSpecialObject(crate)
    local itemCount = container:getItems():size()
    if itemCount > 0 then
        crate:setOverlaySprite(itemCount < 7 and Sprites.crateOverlays.closed or Sprites.crateOverlays.full, false)
    end
    if isServer() then
        crate:transmitCompleteItemToClients()
    end
    triggerEvent("OnObjectAdded", crate)
    return crate
end

--- Places a panel mount the way a player's placing it would, from the item its tile gives back.
---@param square IsoGridSquare
---@param spriteName string a tile of Sprites.flat, Sprites.wall or Sprites.rack
function WorldSpawns.placePanel(square, spriteName)
    local sprite = getSprite(spriteName)
    local item = instanceItem(sprite:getProperties():get("CustomItem"))
    ISMoveableSpriteProps.new(sprite):placeMoveableInternal(nil, square, item, spriteName)
end

-- Rooms seen for the first time -------------------------------------------------------------------

local function rolls(odds, rarity)
    return ZombRand(odds * rarity) == 0
end

local function onSeeNewRoom(room)
    local rarity = WorldSpawns.RARITY[SandboxVars.RenewableEnergy.BatteryBankSpawn]
    if not rarity then
        return
    end
    local name = room:getName()
    local bank = WorldSpawns.BANK_ROOMS[name]
    if bank and rolls(bank.odds, rarity) then
        local square = room:getRandomFreeSquare()
        if square then
            WorldSpawns.placeBank(square, bank.sprite)
        end
    end
    local crateOdds = WorldSpawns.CRATE_ROOMS[name]
    if crateOdds and rolls(crateOdds, rarity) then
        local square = room:getRandomFreeSquare()
        if square then
            WorldSpawns.placeCrate(square)
        end
    end
end

-- Fires on the server and in single player (IsoCell.ProcessSpottedRooms), once per room.
Events.OnSeeNewRoom.Add(onSeeNewRoom)

return WorldSpawns
