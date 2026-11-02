-- How a solar module's cracked glass looks and is mended: Seal Cracked Module, in hand, on a placed
-- panel's mount or on the arrow board trailer, and Reglaze Module. One rule for all three places,
-- so the crafting window and the jobs in place can't disagree.

local Specs = require "RenewableEnergy/Specs"
local Wear = require "RenewableEnergy/PowerBank/Wear"
local Items = require "cf_commonlib/Items"

local ModuleRepair = {}

-- Seal Cracked Module: condition it adds, and the most a first seal brings each module type to.
-- The caps stay below Specs.crackLooks.lightBelow of the type's ConditionMax, and a first seal's
-- at or above heavyBelow: sealed glass is still cracked glass, and at best shows light cracks.
ModuleRepair.SEAL_ADDS = 20
ModuleRepair.SEAL_CAP = {
    [Specs.factoryModule] = 55,
    ["RenewableEnergy.HomemadeSolarModule"] = 40,
}

-- Reglaze Module's new glass, as shares of the module's ConditionMax: a module whose cracks stayed
-- in the glass comes back as new; one cracked heavily, or sealed, since a crack that needed sealing
-- ran deep enough to let the weather in, keeps the cells cracked under it. Both shares stay at or
-- above Specs.crackLooks.lightBelow, so new glass shows whole.
ModuleRepair.REGLAZE = { glassOnly = 1, cellsCracked = 0.9 }

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

--- The condition Reglaze Module brings a module of `fullType` at `condition`, sealed `repaired`
--- times, to; nil for a type that is no module.
function ModuleRepair.reglazedCondition(fullType, condition, repaired)
    if not Specs.modules[fullType] then
        return nil
    end
    local deep = (repaired or 0) > 0 or ModuleRepair.crackLookOf(fullType, condition) == "heavy"
    local share = deep and ModuleRepair.REGLAZE.cellsCracked or ModuleRepair.REGLAZE.glassOnly
    return math.floor(Items.conditionMaxOf(fullType) * share)
end

-- The most a seal can bring a module of `fullType`, sealed `repaired` times, to; nil for a type
-- that is no module.
local function sealCap(fullType, repaired)
    local cap = ModuleRepair.SEAL_CAP[fullType]
    return cap and Wear.repairLimit(cap, repaired)
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

-- Seal Cracked Module, whose skill, time and XP the jobs in place take, and its glue twin
-- (Recipes.txt says why there are two), in the order the jobs in place try their inputs: glue
-- first, the commoner tube, keeping epoxy for what only it does, such as vanilla's Fix With Epoxy
-- (recipes_fixing.txt). MetaRecipe makes the twin known with it.
ModuleRepair.SEAL_RECIPE = "RenewableEnergy_RepairCrackedModule"
local SEAL_TWINS = { "RenewableEnergy_RepairCrackedModuleWithGlue", ModuleRepair.SEAL_RECIPE }

-- The module itself is the job's target, not something carried.
local function isModuleInput(input)
    return input:containsItem(getScriptManager():getItem(Specs.factoryModule))
end

--- What sealing a module in place takes, as a material (cf_commonlib's Materials craft): the
--- recipe's inputs but the module, paid and taught as the crafting window would.
ModuleRepair.SEAL = { craft = ModuleRepair.SEAL_RECIPE, twins = SEAL_TWINS, except = isModuleInput }

--- Seal Cracked Module's CraftRecipe.
function ModuleRepair.sealRecipe()
    return getScriptManager():getCraftRecipe(ModuleRepair.SEAL_RECIPE)
end

--- The job row (cf_commonlib's Jobs) of sealing a module in place: `sealable(subject, with)` says
--- whether the module the job means can be sealed, else `refusal` refuses it; `extra` adds the
--- place's own fields, such as where a character stands. It takes as long as the crafting window
--- takes for Seal Cracked Module (ISHandcraftAction).
function ModuleRepair.sealRow(sealable, refusal, extra)
    local row = {
        units = function(subject, with, character) return ModuleRepair.sealRecipe():getTime(character) * 5 end,
        light = true, sound = "GeneratorRepair",
        materials = { ModuleRepair.SEAL },
        blocker = function(character, subject, with) return not sealable(subject, with) and refusal or nil end,
    }
    for key, value in pairs(extra or {}) do
        row[key] = value
    end
    return row
end

return ModuleRepair
