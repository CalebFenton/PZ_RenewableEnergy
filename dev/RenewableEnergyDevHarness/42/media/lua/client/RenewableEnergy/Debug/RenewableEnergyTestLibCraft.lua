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

--- The condition at `share` of `fullType`'s ConditionMax, such as a Specs.crackLooks threshold.
function T.conditionAt(fullType, share)
    return math.floor(share * Items.conditionMaxOf(fullType) + 0.5)
end

return T
