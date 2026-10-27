-- Batteries, the mod's and vanilla's car batteries: capacity, charge, wear and repair.
--
-- A battery's charge is its drainable uses, 0 to 1, so that a battery carries its charge
-- in and out of banks and the inventory shows it. Its condition is its health: capacity
-- scales with it, and deep discharges wear it down.

local RenewableEnergy = require "RenewableEnergy/Utilities"
local Specs = require "RenewableEnergy/Specs"
local Sun = require "RenewableEnergy/Sun"
local Wear = require "RenewableEnergy/PowerBank/Wear"
local Chance = require "cf_commonlib/Chance"

local Battery = {}
RenewableEnergy.Battery = Battery

--- The Specs.batteries row for an item, or nil if it is no battery.
function Battery.spec(item)
    if not instanceof(item, "InventoryItem") then
        return nil
    end
    return Specs.batteries[item:getFullType()]
end

function Battery.isBattery(item)
    return Battery.spec(item) ~= nil
end

local function health(item)
    return item:getCondition() / item:getConditionMax()
end

-- Service Battery adds a little to a tired battery; Recondition brings it to its repair limit,
-- which falls by Wear.REPAIR_LIMIT_STEP with each repair until only a rebuild helps.
Battery.SERVICE_REPAIR = 10
Battery.REPAIR_LIMIT = 85

--- The most a repair can bring a battery repaired this many times to.
function Battery.repairLimit(timesRepaired)
    return Battery.REPAIR_LIMIT - Wear.REPAIR_LIMIT_STEP * timesRepaired
end

--- The repair that makes the most of one of a battery's limited repairs, as the translation key
--- that names it, or nil for one in perfect shape: Service where its step reaches the repair limit
--- anyway (it keeps the charge), Recondition further below it, and past the limit only a rebuild.
function Battery.bestRepair(condition, repaired)
    local limit = Battery.repairLimit(repaired or 0)
    if condition < limit then
        return condition + Battery.SERVICE_REPAIR >= limit and "IGUI_RenewableEnergy_RepairService"
            or "IGUI_RenewableEnergy_RepairRecondition"
    elseif condition < 100 then
        return "IGUI_RenewableEnergy_RepairRebuild"
    end
    return nil
end

--- Watt-hours the battery holds when full, after wear.
function Battery.nominalWh(item)
    local spec = Battery.spec(item)
    return spec and spec.wh * health(item) or 0
end

-- Item modData key: the battery has a charge of its own (found, crafted, or used in a bank), so a
-- container refill such as loot respawn must leave it alone. The legacy name keeps saves marked.
local HAS_CHARGE_KEY = "RenewableEnergy_found"

function Battery.getCharge(item)
    return item:getCurrentUsesFloat()
end

function Battery.setCharge(item, charge)
    item:setCurrentUsesFloat(math.max(0, math.min(1, charge)))
    item:getModData()[HAS_CHARGE_KEY] = true
end

--- Whether the battery's charge was ever set (Battery.setCharge), rather than being what the
--- item spawned with.
function Battery.hasCharge(item)
    return item:getModData()[HAS_CHARGE_KEY] == true
end

-- Batteries found in the world hold this fraction of a charge.
Battery.FOUND_CHARGE = { min = 0.3, max = 0.8 }

--- Gives a found battery a random part charge. Sends nothing: stocking callers publish the item.
function Battery.setFoundCharge(item)
    local range = Battery.FOUND_CHARGE
    Battery.setCharge(item, Chance.within(range.min, range.max))
end

--- Whether a charge going from `before` to `after` shows in the inventory, at two decimals: the
--- server sends a charge only then, as vanilla's alternator charging does (Vehicles.Update.Battery).
function Battery.changedVisibly(before, after)
    return VehicleUtils.compareFloats(before, after, 2)
end

-- How many whole uses `item` is from the charge `target` on the side `direction` gives (1: below
-- it, -1: above it). The game keeps a charge in uses and rounds a charge it is given to the nearest
-- (InventoryItem.setCurrentUsesFloat), and reads it back as a float a hair off it (0.1 comes back
-- as 0.09999999), so charges are compared in uses. Counted in `wholeUses`, full is the item's
-- most uses, which can lie a use under a charge of 1 (DrainableComboItem.getMaxUses).
local function usesFrom(item, target, direction, wholeUses)
    local targetUses = math.floor(target / item:getUseDelta() + 0.5)
    if wholeUses then
        targetUses = math.min(targetUses, item:getMaxUses())
    end
    return (targetUses - item:getCurrentUses()) * direction
end

-- The item of `container` that `accepts(item)` takes furthest from `target` on the side
-- `direction` gives, as a charge, and how many uses from it (usesFrom); nil if every one is there.
-- The first of equally far ones.
local function furthestFrom(container, target, direction, accepts, wholeUses)
    local furthest, furthestUses, furthestGap
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if accepts(item) then
            local uses = usesFrom(item, target, direction, wholeUses)
            local gap = uses * item:getUseDelta()
            if uses > 0 and (not furthest or gap > furthestGap) then
                furthest, furthestUses, furthestGap = item, uses, gap
            end
        end
    end
    return furthest, furthestUses
end

--- Moves up to `wh` watt-hours into (`direction` 1) or out of (-1) the items of `container` that
--- `accepts(item)` takes, toward the charge `target`, each holding `capacityWhOf(item)` when full:
--- the one furthest from it first, so that a mixed set evens out. Without `usesPerStep`, an item
--- goes all the way to the target, landing on it exactly so that the next pick moves on, and the
--- last step may be part of a use, which the item rounds to. With it, a pick moves at most that
--- many whole uses and never part of one, so a set evens out a use at a time and what is short of
--- a use stays unmoved. Sends an item whose charge shows a change (Battery.changedVisibly).
--- Authority only. Returns the watt-hours moved, the whole uses moved, and whether an item is
--- still short of the target.
function Battery.shift(container, wh, target, direction, accepts, capacityWhOf, usesPerStep)
    local moved, movedUses = 0, 0
    local wholeUses = usesPerStep ~= nil
    local item, uses = furthestFrom(container, target, direction, accepts, wholeUses)
    while item and wh > 0 do
        local before = Battery.getCharge(item)
        local useWh = item:getUseDelta() * capacityWhOf(item)
        local step, stepUses
        if usesPerStep then
            stepUses = math.min(uses, usesPerStep, math.floor(wh / useWh))
            if stepUses <= 0 then
                break
            end
            item:setCurrentUses(item:getCurrentUses() + direction * stepUses)
            step = stepUses * useWh
        else
            local room = uses * useWh
            step = math.min(wh, room)
            stepUses = step == room and uses or 0
            Battery.setCharge(item, step == room and target or before + direction * step / capacityWhOf(item))
        end
        if Battery.changedVisibly(before, Battery.getCharge(item)) then
            sendItemStats(item)
        end
        wh, moved, movedUses = wh - step, moved + step, movedUses + stepUses
        item, uses = furthestFrom(container, target, direction, accepts, wholeUses)
    end
    return moved, movedUses, item ~= nil
end

--- The batteries in `container` taken together, as batteries wired in parallel: their charge, 0
--- to 1 (0 when they hold nothing), and the watt-hours they hold when full, after wear.
function Battery.containerCharge(container)
    local storedWh, nominalWh = 0, 0
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local wh = Battery.nominalWh(item)
        storedWh, nominalWh = storedWh + Battery.getCharge(item) * wh, nominalWh + wh
    end
    return nominalWh > 0 and storedWh / nominalWh or 0, nominalWh
end

--- The calendar day now, as a number that differs from day to day: the day of a discharge cycle.
function Battery.today()
    local time = getGameTime()
    return time:getYear() * 1000 + Sun.dayOfYear(time:getMonth(), time:getDay())
end

--- A day's discharge cycle after a reading of `charge` (0 to 1) on `day` (Battery.today), given the
--- cycle so far: its day `cycleDay`, `high`, the highest charge in it, and `depth`, the deepest draw
--- from that high (each nil before the first reading). Returns the cycle's new high and depth, and,
--- when `day` moves on from `cycleDay`, the finished day's depth, to wear the batteries by
--- (Battery.wearAll); the new day's cycle then starts at `charge`. The caller keeps `day`.
function Battery.trackCycle(cycleDay, high, depth, charge, day)
    high = math.max(high or charge, charge)
    depth = math.max(depth or 0, high - charge)
    if cycleDay == nil or cycleDay == day then
        return high, depth, nil
    end
    return charge, 0, depth
end

--- Fraction of its life `item` loses to one discharge `depth` deep (0 to 1) of what it holds now.
--- Cycle life falls with the square of the depth (SAND2004-3149), anchored at the type's cycles
--- at 50%. The depth counts against the battery's rated capacity, so a worn battery carrying the
--- same load wears no faster than a new one: wear doesn't snowball as its capacity falls.
function Battery.cycleWear(item, depth)
    local spec = Battery.spec(item)
    return (depth * health(item) / 0.5) ^ 2 / spec.cyclesAt50
end

--- The Battery Wear sandbox option as a factor on the wear of every discharge.
function Battery.wearScale()
    return SandboxVars.RenewableEnergy.BatteryWear / 100
end

--- Take `fraction` of a full life off a battery's condition. Returns whether the condition
--- changed, so the caller knows to sync the item.
function Battery.wear(item, fraction)
    return Wear.take(item, fraction * item:getConditionMax())
end

--- Wears every battery in `container` by one discharge `depth` deep (Battery.cycleWear, scaled by
--- the Battery Wear option) and sends those whose condition changed. Returns them as a set, for a
--- caller that sends the same batteries for another change. Authority only.
function Battery.wearAll(container, depth)
    local scale = Battery.wearScale()
    local sent = {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if Battery.isBattery(item) and Battery.wear(item, Battery.cycleWear(item, depth) * scale) then
            sendItemStats(item)
            sent[item] = true
        end
    end
    return sent
end

return Battery
