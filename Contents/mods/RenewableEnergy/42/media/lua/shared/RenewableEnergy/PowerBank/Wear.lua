-- Condition lost a little at a time: batteries to deep discharges, inverters and controllers to
-- use. An item's condition is an integer, so wear smaller than one point is kept in its modData
-- until it adds up to one.

RenewableEnergy = RenewableEnergy or {}

local Wear = {}
RenewableEnergy.Wear = Wear

-- Item modData: condition lost but not yet taken off the integer condition.
local PENDING_KEY = "RenewableEnergy_wear"

--- Take `points` of condition off an item. Returns whether its condition changed, so the
--- caller knows to sync it.
function Wear.take(item, points)
    if points <= 0 or item:getCondition() <= 0 then
        return false
    end
    local data = item:getModData()
    local total = (data[PENDING_KEY] or 0) + points
    local whole = math.floor(total)
    data[PENDING_KEY] = total - whole
    if whole <= 0 then
        return false
    end
    item:setCondition(math.max(0, item:getCondition() - whole))
    return true
end

--- Set an item's condition, within 0 and its ConditionMax, and forget its pending wear: a
--- repaired part starts afresh.
function Wear.setCondition(item, condition)
    item:getModData()[PENDING_KEY] = nil
    item:setCondition(math.max(0, math.min(item:getConditionMax(), math.floor(condition))))
end

-- Item modData: the inverter or controller has a condition of its own (found and worn, or
-- crafted), so a container refill such as loot respawn must not wear it as if just found.
local OWN_CONDITION_KEY = "RenewableEnergy_ownCondition"

function Wear.markOwnCondition(item)
    item:getModData()[OWN_CONDITION_KEY] = true
end

function Wear.hasOwnCondition(item)
    return item:getModData()[OWN_CONDITION_KEY] == true
end

return Wear
