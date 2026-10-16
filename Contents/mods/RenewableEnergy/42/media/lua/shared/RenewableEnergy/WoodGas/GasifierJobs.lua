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

-- Less than this in the drain isn't worth draining.
local MIN_CONDENSATE = 0.1
-- Lighting takes this many minutes, and a cold start, with the bellows, COLD_LIGHT_MINUTES.
local LIGHT_MINUTES, COLD_LIGHT_MINUTES = 2, 10

local BELLOWS = { item = Gasifier.BELLOWS[1], types = Gasifier.BELLOWS, keep = true }

-- Every job, by name, as DigesterJobs.JOBS has them: minutes, or a function(gasifier, item) of
-- them; blocker(summary); check(character, summary, item); materials, or a function(summary) of
-- them; how it looks. Clean Out Ash digs with the shovel in hand (`shovel`), as vanilla's Clear
-- Ashes does.
GasifierJobs.JOBS = {
    [GasifierJobs.LIGHT] = {
        minutes = function(gasifier)
            local summary = Gasifier.currentSummary(gasifier)
            return summary and summary.cold and COLD_LIGHT_MINUTES or LIGHT_MINUTES
        end,
        doneSound = "CampfireLight",
        blocker = function(summary)
            if summary.lit then
                return "Tooltip_RenewableEnergy_GasifierLit"
            end
            return summary.hopperKg <= 0 and "Tooltip_RenewableEnergy_NoWood" or nil
        end,
        -- A cold one also takes bellows.
        materials = function(summary)
            if summary and summary.cold then
                return { Materials.FIRE_STARTER, BELLOWS }
            end
            return { Materials.FIRE_STARTER }
        end,
    },
    [GasifierJobs.PUT_OUT] = {
        minutes = 1,
        blocker = function(summary)
            return not summary.lit and "Tooltip_RenewableEnergy_GasifierOut" or nil
        end,
    },
    [GasifierJobs.CLEAN_ASH] = {
        minutes = 10, shovel = true,
        blocker = function(summary)
            return summary.ash < Gasifier.ASH_PER_ITEM and "Tooltip_RenewableEnergy_LittleAsh" or nil
        end,
        materials = { { tool = "TAKE_DIRT", item = "Base.Shovel" } },
    },
    -- Into the carried container `item`, or onto the ground without one.
    [GasifierJobs.DRAIN] = {
        minutes = 2,
        blocker = function(summary)
            return summary.condensate < MIN_CONDENSATE and "Tooltip_RenewableEnergy_NoCondensate" or nil
        end,
        check = function(character, summary, item)
            if item and not (character:getInventory():containsRecursive(item) and Gasifier.takesCondensate(item, summary.lit)) then
                return "Tooltip_RenewableEnergy_WontTakeCondensate"
            end
            return nil
        end,
    },
}

--- What `job` takes (RenewableEnergy.Materials) at a gasifier whose summary is `summary`.
function GasifierJobs.materials(job, summary)
    local materials = GasifierJobs.JOBS[job].materials
    if type(materials) == "function" then
        return materials(summary)
    end
    return materials or {}
end

--- What `job` takes of `character` (RenewableEnergy.firstUnmet, RenewableEnergy.Needs) at a
--- gasifier whose summary is `summary`.
function GasifierJobs.needs(character, job, summary)
    return Materials.needs(character, GasifierJobs.materials(job, summary))
end

--- The state of the gasifier that refuses `job`, as a translation key, or nil.
function GasifierJobs.blocker(job, summary)
    return GasifierJobs.JOBS[job].blocker(summary)
end

--- What refuses `character` doing `job` at `gasifier` as this side knows it now: a translation
--- key, "short" when they lack a need, or nil. `item` is the container Drain Condensate fills, or
--- nil to drain it onto the ground.
function GasifierJobs.refusal(character, job, gasifier, item)
    local summary = Gasifier.currentSummary(gasifier)
    local row = GasifierJobs.JOBS[job]
    if not (summary and row) then
        return "Tooltip_RenewableEnergy_NoGasifier"
    end
    return row.blocker(summary)
        or (row.check and row.check(character, summary, item))
        or (RenewableEnergy.firstUnmet(GasifierJobs.needs(character, job, summary)) and "short")
        or nil
end

return GasifierJobs
