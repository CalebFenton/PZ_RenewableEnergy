-- Batteries, the mod's and vanilla's car batteries: capacity, charge and wear.
--
-- A battery's charge is its drainable uses, 0 to 1, so that a battery carries its charge
-- in and out of banks and the inventory shows it. Its condition is its health: capacity
-- scales with it, and deep discharges wear it down.

require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/Wear"

RenewableEnergy = RenewableEnergy or {}
local Battery = {}
RenewableEnergy.Battery = Battery

local Specs, Wear = RenewableEnergy.Specs, RenewableEnergy.Wear

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

-- Item modData key: the battery has a charge of its own (found, crafted, or charged and drained
-- in a bank), so a refill of its container, as loot respawn does, must leave it alone. The key
-- keeps its old name so that batteries in existing saves stay marked.
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
    Battery.setCharge(item, range.min + (range.max - range.min) * ZombRandFloat(0, 1))
    sendItemStats(item)
end

--- The item in `container` with the lowest charge that isn't full, of those `accepts(item)`
--- takes, or nil. Any drainable item will do, a vanilla cell as well as a bank battery.
function Battery.emptiestIn(container, accepts)
    local emptiest, lowest
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if accepts(item) then
            local charge = Battery.getCharge(item)
            if charge < 1 and (not emptiest or charge < lowest) then
                emptiest, lowest = item, charge
            end
        end
    end
    return emptiest
end

--- Fraction of its life a battery loses to one discharge `depth` deep (0 to 1). Cycle life
--- falls with the square of the depth (SAND2004-3149), anchored at the type's cycles at 50%.
function Battery.cycleWear(spec, depth)
    return (depth / 0.5) ^ 2 / spec.cyclesAt50
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

return Battery
