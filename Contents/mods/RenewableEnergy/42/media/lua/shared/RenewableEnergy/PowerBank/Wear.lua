-- Condition lost a little at a time: batteries to deep discharges, inverters and controllers to
-- use. An item's condition is an integer, so wear smaller than one point is kept in its modData
-- until it adds up to one.

RenewableEnergy = RenewableEnergy or {}

local Wear = {}
RenewableEnergy.Wear = Wear

-- Item modData: condition lost but not yet taken off the integer condition.
local PENDING = "RenewableEnergy_wear"

--- Take `points` of condition off an item. Returns whether its condition changed, so the
--- caller knows to sync it.
function Wear.take(item, points)
    if points <= 0 or item:getCondition() <= 0 then
        return false
    end
    local data = item:getModData()
    local total = (data[PENDING] or 0) + points
    local whole = math.floor(total)
    data[PENDING] = total - whole
    if whole <= 0 then
        return false
    end
    item:setCondition(math.max(0, item:getCondition() - whole))
    return true
end

--- Set an item's condition, within 0 and its ConditionMax, and forget its pending wear: a
--- repaired part starts afresh.
function Wear.setCondition(item, condition)
    item:getModData()[PENDING] = nil
    item:setCondition(math.max(0, math.min(item:getConditionMax(), math.floor(condition))))
end

return Wear
