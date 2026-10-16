require "RenewableEnergy/Specs"

-- The deep cycle battery as a vehicle's battery.
--
-- A vehicle's Battery part lists the items it takes in its script (template_battery.txt,
-- itemType = Base.CarBattery, with the vehicle's mechanicType appended to every entry), and the
-- game picks a new vehicle's battery at random from that list. So the deep cycle battery isn't
-- added there, which would put one in half the cars of the world: the mechanics menu offers it
-- beside the car batteries instead (client/RenewableEnergy/UI/VehicleBatteryMenu.lua),
-- and vanilla's install action, which never checks the item's type, fits it.
--
-- Vanilla charges and drains a vehicle battery by a fraction of its charge, sized for a car
-- battery. server/RenewableEnergy/Gadgets/VehicleBatteryCharging.lua scales those fractions by
-- capacity, so the bigger battery holds the same loads for longer and takes longer to fill.
RenewableEnergy = RenewableEnergy or {}
local VehicleBattery = {}
RenewableEnergy.VehicleBattery = VehicleBattery
local Specs = RenewableEnergy.Specs

-- The vehicle part id of the battery slot.
VehicleBattery.PART = "Battery"
-- The L-16 is left out: it is a 6 V battery, and a car's starter and lights need 12 V.
VehicleBattery.ITEM = "RenewableEnergy.DeepCycleBattery"

-- The battery vanilla's charge and drain rates are sized for.
VehicleBattery.CAR_BATTERY = "Base.CarBattery1"

--- Whether `part` is a vehicle's battery slot that the deep cycle battery fits.
function VehicleBattery.isBatteryPart(part)
    return part ~= nil and part:getId() == VehicleBattery.PART
end

--- The share of its own charge that a vanilla change of one unit of a car battery's charge
--- makes in `item`: the car battery's capacity over the item's. 1 for anything the mod has no
--- rating for, so other batteries charge and drain as vanilla has them.
function VehicleBattery.chargeScale(item)
    local spec = item and Specs.batteries[item:getFullType()]
    if not spec then
        return 1
    end
    return Specs.batteries[VehicleBattery.CAR_BATTERY].wh / spec.wh
end

return VehicleBattery
