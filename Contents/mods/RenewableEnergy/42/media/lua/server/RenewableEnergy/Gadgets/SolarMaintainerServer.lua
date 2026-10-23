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
local SolarMaintainer, VehicleBattery = RenewableEnergy.SolarMaintainer, RenewableEnergy.VehicleBattery
local Battery, Specs, Sun = RenewableEnergy.Battery, RenewableEnergy.Specs, RenewableEnergy.Sun
local ATTACHED_KEY = SolarMaintainer.ATTACHED_KEY

--- Takes `item` out of its container and clips it to the vehicle. Returns whether it did.
function SolarMaintainer.attach(character, vehicle, item)
    if not (item and item:getFullType() == SolarMaintainer.ITEM and SolarMaintainer.canAttach(vehicle)) then
        return false
    end
    RenewableEnergy.takeItem(character, item)
    local part = VehicleBattery.partOf(vehicle)
    part:getModData()[ATTACHED_KEY] = true
    vehicle:transmitPartModData(part)
    return true
end

--- Unclips the maintainer and gives it to the character. Returns whether it did. Nothing wears a
--- maintainer, so a new one is the one that went on; any mark counts, older saves' tables too.
function SolarMaintainer.detach(character, vehicle)
    if not SolarMaintainer.isAttached(vehicle) then
        return false
    end
    local part = VehicleBattery.partOf(vehicle)
    part:getModData()[ATTACHED_KEY] = nil
    vehicle:transmitPartModData(part)
    RenewableEnergy.giveItems(character, SolarMaintainer.ITEM)
    return true
end

--- Adds `hours` of the maintainer's output under `sky` (Sun.skyNow, now if nil) to the vehicle's
--- battery. The panel lies flat on the dashboard or roof, so a vehicle under a roof gets no sun.
--- Returns the watt-hours it added.
function SolarMaintainer.charge(vehicle, hours, sky)
    local part = SolarMaintainer.isAttached(vehicle) and VehicleBattery.partOf(vehicle)
    local battery = part and part:getInventoryItem()
    if not battery then
        return 0
    end
    local capacityWh = Battery.nominalWh(battery)
    local wh = Sun.squareWatts(vehicle:getSquare(), Specs.maintainerWatts, sky) * hours
    if capacityWh <= 0 or wh <= 0 then
        return 0
    end
    local before = Battery.getCharge(battery)
    Battery.setCharge(battery, before + wh / capacityWh)
    -- Read back: the charge is kept in whole uses.
    local after = Battery.getCharge(battery)
    -- As vanilla's alternator charging does (Vehicles.Update.Battery): the server sends the
    -- charge to clients only when it shows a change at two decimals.
    if VehicleUtils.compareFloats(before, after, 2) then
        vehicle:transmitPartUsedDelta(part)
    end
    return (after - before) * capacityWh
end

return SolarMaintainer
