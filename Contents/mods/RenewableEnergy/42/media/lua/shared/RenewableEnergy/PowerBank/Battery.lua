-- Batteries, the mod's and vanilla's car batteries: capacity, charge and wear (design §5.1).
--
-- A battery's charge is its drainable uses, 0 to 1, so that a battery carries its charge
-- in and out of banks and the inventory shows it. Its condition is its health: capacity
-- scales with it, and deep discharges wear it down.

require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/Wear"

local Battery = {}
RenewableEnergy.Battery = Battery

--- The Specs.batteries row for an item, or nil if it is no battery.
function Battery.spec(item)
    if not instanceof(item, "InventoryItem") then
        return nil
    end
    return RenewableEnergy.Specs.batteries[item:getFullType()]
end

function Battery.isBattery(item)
    return Battery.spec(item) ~= nil
end

local function health(item)
    return item:getCondition() / item:getConditionMax()
end

--- Watt-hours the battery holds when full, after wear.
function Battery.nominalWh(item)
    local spec = Battery.spec(item)
    return spec and spec.wh * health(item) or 0
end

function Battery.getCharge(item)
    return item:getCurrentUsesFloat()
end

function Battery.setCharge(item, charge)
    item:setCurrentUsesFloat(math.max(0, math.min(1, charge)))
end

--- Give a battery found in the world a random part charge, and send it to the clients that
--- see it. Authority only.
function Battery.setFoundCharge(item)
    local range = RenewableEnergy.Specs.foundCharge
    Battery.setCharge(item, range.min + (range.max - range.min) * ZombRandFloat(0, 1))
    sendItemStats(item)
end

--- Fraction of its life a battery loses to one discharge `depth` deep (0 to 1).
---
--- Cycle life falls with the square of the depth (SAND2004-3149), anchored at the
--- type's cycles at 50%: a deep-cycle battery then lasts about 400 cycles at 80%.
function Battery.cycleWear(spec, depth)
    return (depth / 0.5) ^ 2 / spec.cyclesAt50
end

--- Take `fraction` of a full life off a battery's condition. Returns whether the condition
--- changed, so the caller knows to sync the item.
function Battery.wear(item, fraction)
    return RenewableEnergy.Wear.take(item, fraction * item:getConditionMax())
end

return Battery
