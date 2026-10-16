-- The hands-on jobs at a gasifier: what each takes of the character and what refuses it. The menu
-- shows the same needs the authority checks (RenewableEnergy.firstUnmet); the authority does them
-- (server/RenewableEnergy/WoodGas/GasifierSystem.lua). Loading wood and changing the filter's
-- packing are the loot window's.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Materials"
require "RenewableEnergy/WoodGas/Gasifier"

RenewableEnergy = RenewableEnergy or {}
local GasifierJobs = {}
RenewableEnergy.GasifierJobs = GasifierJobs

local Gasifier, Materials = RenewableEnergy.Gasifier, RenewableEnergy.Materials

GasifierJobs.LIGHT = "LightGasifier"
GasifierJobs.PUT_OUT = "PutOutGasifier"
GasifierJobs.CLEAN_ASH = "CleanOutAsh"
GasifierJobs.DRAIN = "DrainCondensate"

-- In-game minutes each job takes; a cold start with the bellows takes COLD_LIGHT_MINUTES.
GasifierJobs.MINUTES = {
    [GasifierJobs.LIGHT] = 2,
    [GasifierJobs.PUT_OUT] = 1,
    [GasifierJobs.CLEAN_ASH] = 10,
    [GasifierJobs.DRAIN] = 2,
}
GasifierJobs.COLD_LIGHT_MINUTES = 10
-- Less than this in the drain isn't worth draining.
local MIN_CONDENSATE = 0.1

-- How each job looks (RenewableEnergyGasAction): Clean Out Ash digs with the shovel in hand, as
-- vanilla's Clear Ashes does.
GasifierJobs.LOOK = {
    [GasifierJobs.LIGHT] = { doneSound = "CampfireLight" },
    [GasifierJobs.CLEAN_ASH] = { shovel = true },
}

GasifierJobs.isTarget = Gasifier.isGasifier

local BELLOWS = { item = Gasifier.BELLOWS[1], types = Gasifier.BELLOWS, keep = true }
local SHOVEL = { tool = "TAKE_DIRT", item = "Base.Shovel" }

--- What `job` takes (RenewableEnergy.Materials) at a gasifier whose summary is `summary`: a cold
--- one also takes bellows to light.
function GasifierJobs.materials(job, summary)
    if job == GasifierJobs.LIGHT then
        if summary and summary.cold then
            return { Materials.FIRE_STARTER, BELLOWS }
        end
        return { Materials.FIRE_STARTER }
    elseif job == GasifierJobs.CLEAN_ASH then
        return { SHOVEL }
    end
    return {}
end

--- What `job` takes of `character` (RenewableEnergy.firstUnmet, RenewableEnergy.Needs) at a
--- gasifier whose summary is `summary`.
function GasifierJobs.needs(character, job, summary)
    return Materials.needs(character, GasifierJobs.materials(job, summary))
end

--- In-game minutes `job` takes at `gasifier`.
function GasifierJobs.minutesFor(job, gasifier)
    local summary = Gasifier.currentSummary(gasifier)
    if job == GasifierJobs.LIGHT and summary and summary.cold then
        return GasifierJobs.COLD_LIGHT_MINUTES
    end
    return GasifierJobs.MINUTES[job]
end

--- The state of the gasifier that refuses `job`, as a translation key, or nil.
function GasifierJobs.blocker(job, summary)
    if job == GasifierJobs.LIGHT then
        if summary.lit then
            return "Tooltip_RenewableEnergy_GasifierLit"
        end
        return summary.hopperKg <= 0 and "Tooltip_RenewableEnergy_NoWood" or nil
    elseif job == GasifierJobs.PUT_OUT then
        return not summary.lit and "Tooltip_RenewableEnergy_GasifierOut" or nil
    elseif job == GasifierJobs.CLEAN_ASH then
        return summary.ash < Gasifier.ASH_PER_ITEM and "Tooltip_RenewableEnergy_LittleAsh" or nil
    elseif job == GasifierJobs.DRAIN then
        return summary.condensate < MIN_CONDENSATE and "Tooltip_RenewableEnergy_NoCondensate" or nil
    end
    return nil
end

--- What refuses `character` doing `job` at the gasifier whose summary is `summary`: a blocker
--- key, "short" when they lack a need, or nil. `item` is the container Drain Condensate fills, or
--- nil to drain it onto the ground.
function GasifierJobs.refusalFor(character, job, summary, item)
    if not summary or not GasifierJobs.MINUTES[job] then
        return "Tooltip_RenewableEnergy_NoGasifier"
    end
    local blocker = GasifierJobs.blocker(job, summary)
    if blocker then
        return blocker
    end
    if job == GasifierJobs.DRAIN and item
        and not (character:getInventory():containsRecursive(item) and Gasifier.takesCondensate(item, summary.lit)) then
        return "Tooltip_RenewableEnergy_WontTakeCondensate"
    end
    return RenewableEnergy.firstUnmet(GasifierJobs.needs(character, job, summary)) and "short" or nil
end

--- refusalFor at `gasifier` as this side knows it now.
function GasifierJobs.refusal(character, job, gasifier, item)
    return GasifierJobs.refusalFor(character, job, Gasifier.currentSummary(gasifier), item)
end

return GasifierJobs
