require "Vehicles/Vehicles"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/Gadgets/VehicleBattery"
require "RenewableEnergy/Gadgets/CarAlternator"

-- Scales vanilla's vehicle battery charging and draining by the installed battery's capacity
-- (RenewableEnergy.VehicleBattery.chargeScale), so a deep cycle battery's charge moves slower
-- than a car battery's for the same watts: the lights and radio run longer with the engine off,
-- and the alternator takes longer to fill it.
--
-- Vanilla drains through VehicleUtils.chargeBattery and charges from the alternator in
-- Vehicles.Update.Battery; parts call their update functions by name each time
-- (VehiclePart.getLuaFunction), so the wrapped ones are the ones that run. What a start takes is
-- Java's (BaseVehicle.tryStartEngine) and stays unscaled.

local Battery, VehicleBattery = RenewableEnergy.Battery, RenewableEnergy.VehicleBattery
local CarAlternator = RenewableEnergy.CarAlternator

local vanillaChargeBattery = VehicleUtils.chargeBattery

function VehicleUtils.chargeBattery(vehicle, delta)
    local part = VehicleBattery.partOf(vehicle)
    local item = part and part:getInventoryItem()
    vanillaChargeBattery(vehicle, delta * VehicleBattery.chargeScale(item))
end

local vanillaUpdateBattery = Vehicles.Update.Battery

-- Scales only a rise, which is the alternator's alone: the lightbar drain this update also runs
-- comes only with the engine off (Vehicles.Update.Lightbar), when the alternator adds nothing, and
-- went through chargeBattery, scaled already. A car whose alternator was taken out
-- (RenewableEnergy.CarAlternator) has nothing to make the rise, so it keeps none of it.
function Vehicles.Update.Battery(vehicle, part, elapsedMinutes)
    local item = part:getInventoryItem()
    local before = item and Battery.getCharge(item)
    vanillaUpdateBattery(vehicle, part, elapsedMinutes)
    if not before then
        return
    end
    local scale = CarAlternator.isOut(vehicle) and 0 or VehicleBattery.chargeScale(item)
    local after = Battery.getCharge(item)
    if scale == 1 or after <= before then
        return
    end
    local scaled = before + (after - before) * scale
    Battery.setCharge(item, scaled)
    -- Vanilla may already have sent the unscaled charge; resend if the scaled one shows differently.
    if VehicleUtils.compareFloats(after, scaled, 2) then
        vehicle:transmitPartUsedDelta(part)
    end
end
