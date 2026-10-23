-- Batteries, the mod's and vanilla's car batteries: capacity, charge and wear.
--
-- A battery's charge is its drainable uses, 0 to 1, so that a battery carries its charge
-- in and out of banks and the inventory shows it. Its condition is its health: capacity
-- scales with it, and deep discharges wear it down.

require "RenewableEnergy/Chance"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/Wear"

RenewableEnergy = RenewableEnergy or {}
local Battery = {}
RenewableEnergy.Battery = Battery

local Chance, Specs, Sun, Wear = RenewableEnergy.Chance, RenewableEnergy.Specs, RenewableEnergy.Sun, RenewableEnergy.Wear

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

--- Watt-hours the battery holds when full, after wear.
function Battery.nominalWh(item)
    local spec = Battery.spec(item)
    return spec and spec.wh * health(item) or 0
end

-- Item modData key: the battery has a charge of its own (found, crafted, or used in a bank), so a
-- container refill such as loot respawn must leave it alone. The legacy name keeps saves marked.
local HAS_CHARGE = "RenewableEnergy_found"

function Battery.getCharge(item)
    return item:getCurrentUsesFloat()
end

function Battery.setCharge(item, charge)
    item:setCurrentUsesFloat(math.max(0, math.min(1, charge)))
    item:getModData()[HAS_CHARGE] = true
end

--- Whether the battery's charge was ever set (Battery.setCharge), rather than being what the
--- item spawned with.
function Battery.hasCharge(item)
    return item:getModData()[HAS_CHARGE] == true
end

--- Give a battery found in the world a random part charge, and send it to the clients that
--- see it. Authority only.
function Battery.setFoundCharge(item)
    local range = Specs.foundCharge
    Battery.setCharge(item, Chance.within(range.min, range.max))
    sendItemStats(item)
end

--- The item in `container` with the lowest charge that isn't full, of those `accepts(item)`
--- takes, or nil. Any drainable will do, vanilla cells included. Full is counted in whole uses,
--- since float uses of a full drainable can read just under 1.
function Battery.emptiestIn(container, accepts)
    local emptiest, lowest
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if accepts(item) and item:getCurrentUses() < item:getMaxUses() then
            local charge = Battery.getCharge(item)
            if not emptiest or charge < lowest then
                emptiest, lowest = item, charge
            end
        end
    end
    return emptiest
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
