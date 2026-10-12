require "RenewableEnergy/Specs"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/Battery"

-- The Solar Battery Maintainer: a 10 W panel clipped to a vehicle that keeps its battery
-- topped up in daylight.
--
-- An attached maintainer is a mark in the modData of the vehicle's Battery part. That part
-- stays when its battery is swapped, and vehicle:transmitPartModData sends its modData to
-- multiplayer clients, so the menu there can tell what is attached. attach and detach run on
-- the authority, from a timed action's complete().
RenewableEnergy = RenewableEnergy or {}
local SolarMaintainer = {}
RenewableEnergy.SolarMaintainer = SolarMaintainer

SolarMaintainer.ITEM = "RenewableEnergy.SolarMaintainer"

local PART = "Battery"
local KEY = "RenewableEnergy_SolarMaintainer"

local function batteryPart(vehicle)
    return vehicle and vehicle:getPartById(PART)
end

function SolarMaintainer.isAttached(vehicle)
    local part = batteryPart(vehicle)
    return part ~= nil and part:getModData()[KEY] ~= nil
end

function SolarMaintainer.canAttach(vehicle)
    return batteryPart(vehicle) ~= nil and not SolarMaintainer.isAttached(vehicle)
end

-- Takes `item` out of its container and clips it to the vehicle. Returns whether it did.
function SolarMaintainer.attach(character, vehicle, item)
    if not (item and item:getFullType() == SolarMaintainer.ITEM and SolarMaintainer.canAttach(vehicle)) then
        return false
    end
    local container = item:getContainer()
    if container then
        container:Remove(item)
        sendRemoveItemFromContainer(container, item)
    end
    local part = batteryPart(vehicle)
    part:getModData()[KEY] = { condition = item:getCondition() }
    vehicle:transmitPartModData(part)
    return true
end

-- Unclips the maintainer and gives it to the character, with the condition it went on with.
function SolarMaintainer.detach(character, vehicle)
    if not SolarMaintainer.isAttached(vehicle) then
        return false
    end
    local part = batteryPart(vehicle)
    local item = instanceItem(SolarMaintainer.ITEM)
    item:setCondition(part:getModData()[KEY].condition)
    part:getModData()[KEY] = nil
    vehicle:transmitPartModData(part)
    Actions.addOrDropItem(character, item)
    return true
end

-- Adds `hours` of the maintainer's current output to the vehicle's battery. The panel lies
-- flat on the dashboard or roof, and a vehicle under a roof gets no sun. Authority only.
-- Returns the watt-hours it added.
function SolarMaintainer.charge(vehicle, hours)
    if not SolarMaintainer.isAttached(vehicle) then
        return 0
    end
    local square = vehicle:getSquare()
    local part = batteryPart(vehicle)
    local battery = part:getInventoryItem()
    if not (square and square:isOutside() and battery) then
        return 0
    end
    local capacityWh = RenewableEnergy.Battery.nominalWh(battery)
    local wh = RenewableEnergy.Sun.panelWatts(RenewableEnergy.Specs.maintainerWatts, "flat") * hours
    if not capacityWh or capacityWh <= 0 or wh <= 0 then
        return 0
    end
    -- As vanilla's alternator charging does (Vehicles.Update.Battery): the server sends the
    -- charge to clients only when it shows a change at two decimals.
    local before = battery:getCurrentUsesFloat()
    local after = math.min(1, before + wh / capacityWh)
    battery:setCurrentUsesFloat(after)
    if VehicleUtils.compareFloats(before, after, 2) then
        vehicle:transmitPartUsedDelta(part)
    end
    return (after - before) * capacityWh
end

return SolarMaintainer
