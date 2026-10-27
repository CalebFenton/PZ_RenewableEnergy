-- Scales vanilla's vehicle battery charging and draining by the installed battery's capacity
-- (VehicleBattery.chargeScale), so a deep cycle battery's charge moves slower
-- than a car battery's for the same watts: the lights and radio run longer with the engine off,
-- and the alternator takes longer to fill it.
--
-- Vanilla drains through VehicleUtils.chargeBattery and charges from the alternator in
-- Vehicles.Update.Battery; parts call their update functions by name each time
-- (VehiclePart.getLuaFunction), so the wrapped ones are the ones that run. What a start takes is
-- Java's (BaseVehicle.tryStartEngine) and stays unscaled.

require "Vehicles/Vehicles"
local VehicleBattery = require "RenewableEnergy/Gadgets/VehicleBattery"
local CarAlternator = require "RenewableEnergy/Gadgets/CarAlternator"

local vanillaChargeBattery = VehicleUtils.chargeBattery

function VehicleUtils.chargeBattery(vehicle, delta)
    local part = VehicleBattery.partOf(vehicle)
    local item = part and part:getInventoryItem()
    vanillaChargeBattery(vehicle, delta * VehicleBattery.chargeScale(item))
end

local vanillaUpdateBattery = Vehicles.Update.Battery

-- Scale before native clamping and rounding. Engine-off lightbar drain is already scaled by
-- chargeBattery; running the engine never drains it.
function Vehicles.Update.Battery(vehicle, part, elapsedMinutes)
    if vehicle:isEngineRunning() then
        local scale = CarAlternator.isOut(vehicle) and 0 or VehicleBattery.chargeScale(part:getInventoryItem())
        elapsedMinutes = elapsedMinutes * scale
    end
    vanillaUpdateBattery(vehicle, part, elapsedMinutes)
end
