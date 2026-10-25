-- The hands-on jobs at a gasifier: what each takes of the character and what refuses it
-- (RenewableEnergy.GasJobs). GasifierSystem does them. Loading wood and changing the filter's
-- packing are the loot window's.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Materials"
require "RenewableEnergy/GasJobs"
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
-- Minutes to light, and to light from cold with the bellows.
local LIGHT_MINUTES, COLD_LIGHT_MINUTES = 2, 10

local BELLOWS = { item = Gasifier.BELLOWS[1], types = Gasifier.BELLOWS, keep = true }

-- Every job, by name (GasJobs.define), read against the gasifier's summary
-- (Gasifier.currentSummary); `with` is the container Drain Condensate fills, or nil to drain it
-- onto the ground. Clean Out Ash digs with the shovel in hand, as vanilla's Clear Ashes does.
GasifierJobs.JOBS = {
    [GasifierJobs.LIGHT] = {
        minutes = function(gasifier)
            local summary = Gasifier.currentSummary(gasifier)
            return summary and summary.cold and COLD_LIGHT_MINUTES or LIGHT_MINUTES
        end,
        doneSound = "CampfireLight",
        blocker = function(summary)
            if summary.lit then
                return "Tooltip_RenewableEnergy_AlreadyLit"
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
            return not summary.lit and "Tooltip_RenewableEnergy_NotLit" or nil
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
        withRefusal = function(character, summary, item)
            if item and not (character:getInventory():containsRecursive(item) and Gasifier.takesCondensate(item, summary.lit)) then
                return "Tooltip_RenewableEnergy_WontTakeCondensate"
            end
            return nil
        end,
    },
}

RenewableEnergy.GasJobs.define(GasifierJobs, {
    subjectOf = Gasifier.currentSummary, missing = "Tooltip_RenewableEnergy_NoGasifier",
})

return GasifierJobs
