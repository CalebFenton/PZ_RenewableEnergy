-- Battery banks and the panels wired to them, as both sides see them: what an object is,
-- what a bank holds, and the bank's status as the server last reported it.
--
-- The server runs the banks (server/RenewableEnergy/PowerBank) and adds perform() and
-- place() to this table; the client adds command() and addStatusListener()
-- (client/RenewableEnergy/PowerBank). Both register a Global Object System under
-- SYSTEM_NAME, which keeps each bank's state while its chunk is unloaded and copies the
-- `status` field to every client.

require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"

local PowerBank = {}
RenewableEnergy.PowerBank = PowerBank

local Specs, Sprites = RenewableEnergy.Specs, RenewableEnergy.Sprites

PowerBank.SYSTEM_NAME = "renewable_energy_powerbank"
-- A running vehicle is hooked to a bank with a few lengths of vanilla wire run from its battery
-- terminals. They are leads, not a build: the bank holds them while the vehicle is connected and
-- gives them back when it is unhooked, so moving the car costs nothing.
PowerBank.VEHICLE_WIRE = "Base.ElectricWire"
PowerBank.VEHICLE_WIRE_COUNT = 4

local SOURCE_KINDS = { flat = true, wall = true, rack = true }

-- Placed bank sprite to its Specs.banks row, and to the item it is.
local BANKS_BY_SPRITE = {}
for fullType, bank in pairs(Specs.banks) do
    BANKS_BY_SPRITE[Sprites[bank.sprite]] = { fullType = fullType, spec = bank }
end

local function spriteName(isoObject)
    if not instanceof(isoObject, "IsoObject") then
        return nil
    end
    local sprite = isoObject:getSprite()
    return sprite and sprite:getName()
end

--- The bank a placed sprite is: { fullType, spec }, or nil.
function PowerBank.bankOfSprite(name)
    return name and BANKS_BY_SPRITE[name]
end

--- Whether an object is a working bank: a bank tile turned into the generator that powers
--- the squares around it.
function PowerBank.isBank(isoObject)
    return instanceof(isoObject, "IsoGenerator") and PowerBank.bankOfSprite(spriteName(isoObject)) ~= nil
end

--- The mount of a placed panel, "flat", "wall" or "rack", and the way it faces; nil for
--- anything else.
function PowerBank.sourceKind(isoObject)
    local kind, facing = Sprites.kindOf(spriteName(isoObject))
    if SOURCE_KINDS[kind] then
        return kind, facing
    end
    return nil
end

-- What goes in a bank's container ---------------------------------------------------------

local function countOf(container, category, except)
    local count = 0
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item ~= except and category[item:getFullType()] then
            count = count + 1
        end
    end
    return count
end

--- The bank container's filter (ItemContainer.isItemAllowed): batteries, one inverter and
--- the controllers the bank has room for.
function PowerBank.acceptItem(container, item)
    local parent = container and container:getParent()
    local bank = PowerBank.bankOfSprite(spriteName(parent))
    if not (bank and instanceof(item, "InventoryItem")) then
        return false
    end
    local fullType = item:getFullType()
    if Specs.batteries[fullType] then
        return countOf(container, Specs.batteries, item) < bank.spec.maxBatteries
    elseif Specs.inverters[fullType] then
        return countOf(container, Specs.inverters, item) < 1
    elseif Specs.controllers[fullType] then
        return countOf(container, Specs.controllers, item) < bank.spec.maxControllers
    end
    return false
end

-- Banks as either side knows them ---------------------------------------------------------

-- The Global Object System of this side: the server's in single player, where both exist
-- and the server's is the live one.
local function system()
    return PowerBank.serverSystem or PowerBank.clientSystem
end

local function eachBank(fn)
    local sys = system()
    if not sys then return end
    local objects = sys.system
    for i = 0, objects:getObjectCount() - 1 do
        local luaObject = objects:getObjectByIndex(i):getModData()
        if fn(luaObject) then return end
    end
end

local function bankAt(x, y, z)
    local sys = system()
    local globalObject = sys and sys.system:getObjectAt(x, y, z)
    return globalObject and globalObject:getModData()
end

--- The bank's status (see the Core API in .agent/release1-spec.md), or nil.
function PowerBank.getStatus(x, y, z)
    local bank = bankAt(x, y, z)
    return bank and bank.status
end

function PowerBank.isInReach(bank, x, y, z)
    local reach = Specs.sourceReach
    return IsoUtils.DistanceToSquared(x, y, bank.x, bank.y) <= reach.tiles * reach.tiles
        and math.abs(z - bank.z) <= reach.levels
end

--- Banks a panel on this square may be wired to.
function PowerBank.banksInReach(x, y, z)
    local found = {}
    local square = getSquare(x, y, z)
    if not (square and square:isOutside()) then
        return found
    end
    eachBank(function(bank)
        if PowerBank.isInReach(bank, x, y, z) then
            table.insert(found, { x = bank.x, y = bank.y, z = bank.z })
        end
    end)
    return found
end

--- The bank the panel on this square is wired to, or nil.
function PowerBank.bankOfSource(x, y, z)
    local found
    eachBank(function(bank)
        for _, source in ipairs(bank.status and bank.status.sources or {}) do
            if source.x == x and source.y == y and source.z == z then
                found = { x = bank.x, y = bank.y, z = bank.z }
                return true
            end
        end
    end)
    return found
end

-- Vehicles ------------------------------------------------------------------------------

function PowerBank.vehicleInReach(bankPos, vehicle)
    if not (vehicle and bankPos) or math.floor(vehicle:getZ()) ~= bankPos.z then
        return false
    end
    local reach = Specs.vehicleReach
    return IsoUtils.DistanceToSquared(vehicle:getX(), vehicle:getY(), bankPos.x + 0.5, bankPos.y + 0.5) <= reach * reach
end

--- The wire connectVehicle would take from the player's inventory, bags included: an
--- ArrayList of VEHICLE_WIRE_COUNT items, or nil if there is less.
function PowerBank.findVehicleWire(player)
    if not player then
        return nil
    end
    local wire = player:getInventory():getSomeTypeRecurse(PowerBank.VEHICLE_WIRE, PowerBank.VEHICLE_WIRE_COUNT)
    return wire:size() >= PowerBank.VEHICLE_WIRE_COUNT and wire or nil
end

return PowerBank
