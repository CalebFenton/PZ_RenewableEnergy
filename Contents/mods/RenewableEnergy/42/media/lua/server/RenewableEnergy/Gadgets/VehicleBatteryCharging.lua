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
local Battery = require "RenewableEnergy/PowerBank/Battery"

-- Battery part modData: the charge a scaled drain moved that the battery, which keeps whole uses
-- (DrainableComboItem.setCurrentUsesFloat rounds), couldn't show yet. A part update comes about
-- once a game minute and moves a few uses, so rounding each one would skew the scale; the
-- remainder carries to the next. Only the authority runs part updates, so it stays unsent.
local CARRY_KEY = "RenewableEnergy_chargeCarry"

local vanillaChargeBattery = VehicleUtils.chargeBattery

-- The charge vanilla's chargeBattery sets a battery at `charge` to for `delta`, before the battery
-- rounds it: vanilla's own sum and clamps, run on a stand-in battery that only records the charge.
local function vanillaTarget(charge, delta)
    local target = charge
    local item = {
        getCurrentUsesFloat = function() return charge end,
        setUsedDelta = function(_, value) target = value end,
    }
    local part = { getInventoryItem = function() return item end }
    vanillaChargeBattery({ getBattery = function() return part end, transmitPartUsedDelta = function() end }, delta)
    return target
end

function VehicleUtils.chargeBattery(vehicle, delta)
    local part = VehicleBattery.partOf(vehicle)
    local item = part and part:getInventoryItem()
    local scale = VehicleBattery.chargeScale(item)
    if scale == 1 then
        vanillaChargeBattery(vehicle, delta)
        return
    end
    local data = part:getModData()
    local before = item:getCurrentUsesFloat()
    local target = math.max(0, math.min(1, vanillaTarget(before, delta * scale) + (data[CARRY_KEY] or 0)))
    item:setCurrentUsesFloat(target)
    local after = item:getCurrentUsesFloat()
    data[CARRY_KEY] = target - after
    if Battery.changedVisibly(before, after) then
        vehicle:transmitPartUsedDelta(part)
    end
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
