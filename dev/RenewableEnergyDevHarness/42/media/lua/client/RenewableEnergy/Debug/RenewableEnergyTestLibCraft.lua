require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local Items = require "cf_commonlib/Items"

local T = RenewableEnergyTest

-- `name` in snake case, for test names: "HomesteadPowerMag1" -> "homestead_power_mag1".
local function snake(name)
    return string.lower((name:gsub("(%l)(%u)", "%1_%2"):gsub("(%d)(%u)", "%1_%2")))
end

--- The test name for `recipe` in `system`'s tests: "solar", "RenewableEnergy_TakeApartSolarCellCharger",
--- "returns_x" -> "renewable_energy_solar_craft_take_apart_solar_cell_charger_returns_x".
function T.craftName(system, recipe, behavior)
    return "renewable_energy_" .. system .. "_craft_" .. snake((recipe:gsub("^RenewableEnergy_", "")))
        .. (behavior and "_" .. behavior or "")
end

--- The given inputs (T.craftTest's self.items.inputs) of `fullType`.
function T.inputsOf(self, fullType)
    local found = {}
    for _, item in ipairs(self.items.inputs or {}) do
        if item:getFullType() == fullType then
            table.insert(found, item)
        end
    end
    return found
end

--- Registers the craft test `name` of the repair `recipe` on a carried `fullType` set to
--- condition `row.before`, repaired `row.repaired` times and, when given, charged to `row.uses`.
--- validate expects the authority's at `row.after`, repaired `row.repairedAfter` times, as this
--- client's copy is too (the tooltip reads it), and the game refusing the craft when
--- `row.refused`. `row.prefer` adds to the inputs preferred, `row.counts` replaces the counts
--- (one `fullType`), and `row.setup(self)` and `row.validate(self, item)` add to the test's.
function T.repairCraftTest(name, recipe, fullType, row)
    local prefer = { fullType }
    for _, other in ipairs(row.prefer or {}) do
        table.insert(prefer, other)
    end
    T.craftTest(name, {
        recipe = recipe,
        from = fullType,
        prefer = prefer,
        refused = row.refused,
        setup = function(self)
            T.changeItem(self, T.inputsOf(self, fullType)[1], { condition = row.before, repaired = row.repaired, uses = row.uses })
            if row.setup then
                row.setup(self)
            end
        end,
        counts = row.counts or { [fullType] = 1 },
        after = function(self)
            T.readCarried(self, { fullType })
            T.waitFor(self, function()
                local item = T.carried(fullType)
                return item ~= nil and item:getHaveBeenRepaired() == row.repairedAfter
            end, "this client's " .. fullType .. " repaired " .. row.repairedAfter .. "x")
        end,
        validate = function(self)
            local item = T.carriedFirst(self, fullType)
            if not T.expect(item ~= nil, "the " .. fullType .. " is gone") then return end
            T.expectEqual("its condition", item.condition, row.after)
            T.expectEqual("its repairs", item.repaired, row.repairedAfter)
            if row.validate then
                row.validate(self, item)
            end
        end,
    })
end

--- The condition at `share` of `fullType`'s ConditionMax, such as a Specs.crackLooks threshold.
function T.conditionAt(fullType, share)
    return math.floor(share * Items.conditionMaxOf(fullType) + 0.5)
end

return T
