-- How a solar module's cracked glass looks and is mended: Seal Cracked Module and Reglaze Module, in
-- hand, on a placed panel's mount or on the arrow board trailer. One rule for all three places, so
-- the crafting window and the jobs in place can't disagree.

local Specs = require "RenewableEnergy/Specs"
local Wear = require "RenewableEnergy/PowerBank/Wear"
local Items = require "cf_commonlib/Items"

local ModuleRepair = {}

-- Seal Cracked Module: condition it adds, and the most a first seal brings a module to. The cap
-- stays below Specs.crackLooks.lightBelow of a module's ConditionMax, and a first seal's at or
-- above heavyBelow: sealed glass is still cracked glass, and at best shows light cracks.
ModuleRepair.SEAL_ADDS = 20
ModuleRepair.SEAL_CAP = 55

--- How the glass of a module of `fullType` at `condition` looks (Specs.crackLooks): nil whole,
--- "light" or "heavy" cracks. Every look of a module, a mount's tile or the arrow board's, asks
--- this, so they agree. The share is taken by division, which rounds a share that is exactly a
--- threshold to the threshold's own literal, as a product of the max wouldn't.
function ModuleRepair.crackLookOf(fullType, condition)
    local looks = Specs.crackLooks
    local share = condition / Items.conditionMaxOf(fullType)
    if share < looks.heavyBelow then
        return "heavy"
    elseif share < looks.lightBelow then
        return "light"
    end
    return nil
end

--- Whether Reglaze Module takes a module of `fullType` at `condition`: any damage at all, since
--- new glass brings it back to new (its ConditionMax), seals or not.
function ModuleRepair.reglazable(fullType, condition)
    return Specs.modules[fullType] ~= nil and condition < Items.conditionMaxOf(fullType)
end

-- The most a seal can bring a module of `fullType`, sealed `repaired` times, to; nil for a type
-- that is no module.
local function sealCap(fullType, repaired)
    return Specs.modules[fullType] and Wear.repairLimit(ModuleRepair.SEAL_CAP, repaired)
end

--- Whether a seal can help a module of `fullType` at `condition`, sealed `repaired` times: its
--- glass shows cracks and it is below what the seal brings it to.
function ModuleRepair.sealable(fullType, condition, repaired)
    local cap = sealCap(fullType, repaired)
    return cap ~= nil and condition < cap and ModuleRepair.crackLookOf(fullType, condition) ~= nil
end

--- The condition and repair count a seal leaves a sealable module (ModuleRepair.sealable) with.
function ModuleRepair.sealed(fullType, condition, repaired)
    return math.min(sealCap(fullType, repaired), condition + ModuleRepair.SEAL_ADDS), (repaired or 0) + 1
end

-- Seal Cracked Module, whose skill, time and XP the jobs in place take, and Reglaze Module.
ModuleRepair.SEAL_RECIPE = "RenewableEnergy_RepairCrackedModule"
ModuleRepair.REGLAZE_RECIPE = "RenewableEnergy_ReglazeModule"

-- The module itself is the job's target, not something carried.
local function isModuleInput(input)
    return input:containsItem(getScriptManager():getItem(Specs.factoryModule))
end

--- What sealing or reglazing a module in place takes, as a material (cf_commonlib's Materials
--- craft): the recipe's inputs but the module, paid and taught as the crafting window would.
ModuleRepair.SEAL = { craft = ModuleRepair.SEAL_RECIPE, except = isModuleInput }
ModuleRepair.REGLAZE = { craft = ModuleRepair.REGLAZE_RECIPE, except = isModuleInput }

--- Seal Cracked Module's CraftRecipe.
function ModuleRepair.sealRecipe()
    return getScriptManager():getCraftRecipe(ModuleRepair.SEAL_RECIPE)
end

--- Reglaze Module's CraftRecipe.
function ModuleRepair.reglazeRecipe()
    return getScriptManager():getCraftRecipe(ModuleRepair.REGLAZE_RECIPE)
end

--- The job row (cf_commonlib's Jobs) of mending a module in place with the craft `material`
--- (ModuleRepair.SEAL or REGLAZE): `allowed(subject, with)` says whether the module the job means
--- can take it, else `refusal` refuses it; `extra` adds the place's own fields, such as where a
--- character stands. It takes as long as the crafting window takes for the craft
--- (ISHandcraftAction).
function ModuleRepair.jobRow(material, allowed, refusal, extra)
    local row = {
        units = function(subject, with, character)
            return getScriptManager():getCraftRecipe(material.craft):getTime(character) * 5
        end,
        light = true, sound = "GeneratorRepair",
        materials = { material },
        blocker = function(character, subject, with) return not allowed(subject, with) and refusal or nil end,
    }
    for key, value in pairs(extra or {}) do
        row[key] = value
    end
    return row
end

return ModuleRepair
