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

-- Battery part modData: the charge a scaled drain or charge moved that the battery, which keeps
-- whole uses (DrainableComboItem.setCurrentUsesFloat rounds), couldn't show yet. A part update
-- comes about once a game minute and moves a few uses, so rounding each one would skew the scale;
-- the remainder carries to the next. Only the authority runs part updates, so it stays unsent.
local CARRY_KEY = "RenewableEnergy_chargeCarry"

local vanillaChargeBattery = VehicleUtils.chargeBattery
local vanillaUpdateBattery = Vehicles.Update.Battery

local function noop() end

-- The charge vanilla's `run(item)` sets a battery at `charge` to, before the battery rounds it:
-- vanilla's own sum and clamps, run on a stand-in battery `item` that only records the charge.
local function vanillaTarget(charge, run)
    local target = charge
    run({
        getCurrentUsesFloat = function() return charge end,
        setUsedDelta = function(_, value) target = value end,
    })
    return target
end

-- Sets the battery `item` in `part` to `target` plus what earlier moves couldn't show, and keeps
-- what this one can't.
local function moveCharge(vehicle, part, item, target)
    local data = part:getModData()
    local before = item:getCurrentUsesFloat()
    target = math.max(0, math.min(1, target + (data[CARRY_KEY] or 0)))
    item:setCurrentUsesFloat(target)
    local after = item:getCurrentUsesFloat()
    data[CARRY_KEY] = target - after
    if Battery.changedVisibly(before, after) then
        vehicle:transmitPartUsedDelta(part)
    end
end

function VehicleUtils.chargeBattery(vehicle, delta)
    local part = VehicleBattery.partOf(vehicle)
    local item = part and part:getInventoryItem()
    local scale = VehicleBattery.chargeScale(item)
    if scale == 1 then
        vanillaChargeBattery(vehicle, delta)
        return
    end
    moveCharge(vehicle, part, item, vanillaTarget(item:getCurrentUsesFloat(), function(standIn)
        local standInPart = { getInventoryItem = function() return standIn end }
        vanillaChargeBattery({ getBattery = function() return standInPart end, transmitPartUsedDelta = noop }, delta * scale)
    end))
end

-- The alternator charges for the minutes scaled before vanilla's clamp, carried as a drain is.
-- Vanilla's update runs on a stand-in running vehicle without a lightbar, the real part's modData
-- taking what it writes there; then the lightbar's update, which vanilla's calls, runs for the real
-- vehicle: with the engine running it drains nothing (Vehicles.Update.Lightbar).
function Vehicles.Update.Battery(vehicle, part, elapsedMinutes)
    local item = part:getInventoryItem()
    if not (item and vehicle:isEngineRunning()) then
        vanillaUpdateBattery(vehicle, part, elapsedMinutes)
        return
    end
    local scale = CarAlternator.isOut(vehicle) and 0 or VehicleBattery.chargeScale(item)
    if scale == 1 then
        vanillaUpdateBattery(vehicle, part, elapsedMinutes)
        return
    end
    moveCharge(vehicle, part, item, vanillaTarget(item:getCurrentUsesFloat(), function(standIn)
        local standInVehicle = {
            isEngineRunning = function() return true end,
            hasLightbar = function() return false end,
            transmitPartUsedDelta = noop,
        }
        local standInPart = { getInventoryItem = function() return standIn end, getModData = function() return part:getModData() end }
        vanillaUpdateBattery(standInVehicle, standInPart, elapsedMinutes * scale)
    end))
    Vehicles.Update.Lightbar(vehicle, part, elapsedMinutes)
end
