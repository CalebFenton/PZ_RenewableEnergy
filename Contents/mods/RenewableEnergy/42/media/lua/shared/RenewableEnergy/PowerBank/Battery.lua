-- Batteries, the mod's and vanilla's car batteries: capacity, charge and wear (design §5.1).
--
-- A battery's charge is its drainable uses, 0 to 1, so that a battery carries its charge
-- in and out of banks and the inventory shows it. Its condition is its health: capacity
-- scales with it, and deep discharges, overcharging and freezing wear it down.

require "RenewableEnergy/Specs"

local Battery = {}
RenewableEnergy.Battery = Battery

-- Item modData: condition lost but not yet taken off the integer condition.
local WEAR = "RenewableEnergy_wear"

-- Usable capacity by air temperature, °C to fraction; linear between the points
-- (design §5.1: about 80% at 0 °C and 60% at -18 °C).
local COLD_CURVE = { { -30, 0.5 }, { -18, 0.6 }, { 0, 0.8 }, { 25, 1.0 } }

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

--- Watt-hours the battery holds when full at 25 °C, after wear.
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

--- Fraction of its capacity a battery delivers at an air temperature.
function Battery.coldFactor(tempC)
    if tempC <= COLD_CURVE[1][1] then
        return COLD_CURVE[1][2]
    end
    for i = 2, #COLD_CURVE do
        local high = COLD_CURVE[i]
        if tempC < high[1] then
            local low = COLD_CURVE[i - 1]
            return low[2] + (high[2] - low[2]) * (tempC - low[1]) / (high[1] - low[1])
        end
    end
    return COLD_CURVE[#COLD_CURVE][2]
end

--- Fraction of its life a battery loses to one discharge `depth` deep (0 to 1).
---
--- Cycle life falls with the square of the depth (SAND2004-3149), anchored at the
--- type's cycles at 50%: a deep-cycle battery then lasts about 400 cycles at 80%.
function Battery.cycleWear(spec, depth)
    return (depth / 0.5) ^ 2 / spec.cyclesAt50
end

--- Take `fraction` of a full life off a battery's condition. Wear smaller than one point of
--- condition is kept in its modData until it adds up to one. Returns whether the
--- condition changed, so the caller knows to sync the item.
function Battery.wear(item, fraction)
    if fraction <= 0 or item:getCondition() <= 0 then
        return false
    end
    local data = item:getModData()
    local points = (data[WEAR] or 0) + fraction * item:getConditionMax()
    local whole = math.floor(points)
    data[WEAR] = points - whole
    if whole <= 0 then
        return false
    end
    item:setCondition(math.max(0, item:getCondition() - whole))
    return true
end

--- A frozen battery's case cracks: it is dead.
function Battery.crack(item)
    item:setCondition(0)
    Battery.setCharge(item, 0)
end

return Battery
