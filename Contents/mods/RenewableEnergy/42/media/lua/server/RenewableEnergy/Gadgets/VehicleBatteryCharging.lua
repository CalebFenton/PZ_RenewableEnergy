require "Vehicles/Vehicles"
require "RenewableEnergy/Gadgets/VehicleBattery"

-- Scales vanilla's vehicle battery charging and draining by the installed battery's capacity
-- (RenewableEnergy.VehicleBattery.chargeScale), so a deep cycle battery's charge moves at half a
-- car battery's pace for the same watts: the lights and radio run twice as long with the engine
-- off, and the alternator takes twice as long to fill it.
--
-- Vanilla drains through VehicleUtils.chargeBattery (headlights, radio, lightbar, heater) and
-- charges from the alternator in Vehicles.Update.Battery; parts call their update functions by
-- name each time (VehiclePart.getLuaFunction), so the wrapped ones are the ones that run. The
-- 2.5% a start takes is Java's (BaseVehicle.tryStartEngine) and stays as it is.

local VehicleBattery = RenewableEnergy.VehicleBattery

local function batteryItem(vehicle)
    local part = vehicle and vehicle:getBattery()
    return part and part:getInventoryItem()
end

local vanillaChargeBattery = VehicleUtils.chargeBattery

function VehicleUtils.chargeBattery(vehicle, delta)
    local item = batteryItem(vehicle)
    vanillaChargeBattery(vehicle, delta * VehicleBattery.chargeScale(item))
end

local vanillaUpdateBattery = Vehicles.Update.Battery

-- Scales only what the alternator added; the lightbar drain this update also runs went through
-- chargeBattery, scaled already.
function Vehicles.Update.Battery(vehicle, part, elapsedMinutes)
    local item = part:getInventoryItem()
    local before = item and item:getCurrentUsesFloat()
    vanillaUpdateBattery(vehicle, part, elapsedMinutes)
    if not before then
        return
    end
    local scale = VehicleBattery.chargeScale(item)
    local after = item:getCurrentUsesFloat()
    if scale == 1 or after <= before then
        return
    end
    local scaled = before + (after - before) * scale
    item:setUsedDelta(scaled)
    -- Vanilla sent the unscaled charge to clients if it showed a change at two decimals.
    if VehicleUtils.compareFloats(after, scaled, 2) then
        vehicle:transmitPartUsedDelta(part)
    end
end
