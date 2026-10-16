if isClient() then
    return
end

require "Vehicles/Vehicles"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/Gadgets/SolarMaintainer"

-- The Solar Battery Maintainer on the authority: attach and detach, from a timed action's
-- complete(), and the charge GadgetCharging's pass gives.
local SolarMaintainer = RenewableEnergy.SolarMaintainer
local Battery, Specs, Sun = RenewableEnergy.Battery, RenewableEnergy.Specs, RenewableEnergy.Sun
local ATTACHED_KEY = SolarMaintainer.ATTACHED_KEY

--- Takes `item` out of its container and clips it to the vehicle. Returns whether it did.
function SolarMaintainer.attach(character, vehicle, item)
    if not (item and item:getFullType() == SolarMaintainer.ITEM and SolarMaintainer.canAttach(vehicle)) then
        return false
    end
    RenewableEnergy.takeItem(character, item)
    local part = SolarMaintainer.batteryPart(vehicle)
    part:getModData()[ATTACHED_KEY] = { condition = item:getCondition() }
    vehicle:transmitPartModData(part)
    return true
end

--- Unclips the maintainer and gives it to the character, with the condition it went on with.
--- Returns whether it did.
function SolarMaintainer.detach(character, vehicle)
    if not SolarMaintainer.isAttached(vehicle) then
        return false
    end
    local part = SolarMaintainer.batteryPart(vehicle)
    local item = instanceItem(SolarMaintainer.ITEM)
    item:setCondition(part:getModData()[ATTACHED_KEY].condition)
    part:getModData()[ATTACHED_KEY] = nil
    vehicle:transmitPartModData(part)
    RenewableEnergy.giveItems(character, item)
    return true
end

--- Adds `hours` of the maintainer's output under `sky` (Sun.skyNow, now if nil) to the vehicle's
--- battery. The panel lies flat on the dashboard or roof, so a vehicle under a roof gets no sun.
--- Returns the watt-hours it added.
function SolarMaintainer.charge(vehicle, hours, sky)
    local part = SolarMaintainer.batteryPart(vehicle)
    local battery = part and part:getModData()[ATTACHED_KEY] ~= nil and part:getInventoryItem()
    if not battery then
        return 0
    end
    local capacityWh = Battery.nominalWh(battery)
    local wh = Sun.squareWatts(vehicle:getSquare(), Specs.maintainerWatts, sky) * hours
    if capacityWh <= 0 or wh <= 0 then
        return 0
    end
    local before = battery:getCurrentUsesFloat()
    battery:setCurrentUsesFloat(math.min(1, before + wh / capacityWh))
    -- Read back: the charge is kept in whole uses.
    local after = battery:getCurrentUsesFloat()
    -- As vanilla's alternator charging does (Vehicles.Update.Battery): the server sends the
    -- charge to clients only when it shows a change at two decimals.
    if VehicleUtils.compareFloats(before, after, 2) then
        vehicle:transmitPartUsedDelta(part)
    end
    return (after - before) * capacityWh
end

return SolarMaintainer
