-- The hands-on jobs at a gasifier: what each takes of the character and what refuses it
-- (cf_commonlib's Jobs). GasifierSystem does them. Loading wood and changing the filter's
-- packing are the loot window's.

local GasHeater = require "RenewableEnergy/Biogas/GasHeater"
local Gasifier = require "RenewableEnergy/WoodGas/Gasifier"
local Items = require "cf_commonlib/Items"
local Jobs = require "cf_commonlib/Jobs"
local Tables = require "cf_commonlib/Tables"

local GasifierJobs = {}

GasifierJobs.LIGHT = "LightGasifier"
GasifierJobs.PUT_OUT = "PutOutGasifier"
GasifierJobs.CLEAN_ASH = "CleanOutAsh"
GasifierJobs.DRAIN = "DrainCondensate"

-- Less than this in the drain isn't worth draining.
local MIN_CONDENSATE = 0.1
-- Minutes to light, and to light from cold with the bellows.
local LIGHT_MINUTES, COLD_LIGHT_MINUTES = 2, 10

local BELLOWS = { item = Gasifier.BELLOWS[1], types = Gasifier.BELLOWS, keep = true }

-- A tool Clean Out Ash works with: what vanilla's Clear Ashes takes, a shovel, spade, trowel or
-- broom.
local function isAshTool(tool)
    return tool:hasTag(ItemTag.CLEAR_ASHES) and Items.notBroken(tool)
end

--- The Clean Out Ash row of a feature whose subject holds `ashItems(subject)` Wood Ash: it works
--- with the tool in hand, as vanilla's Clear Ashes does.
function GasifierJobs.cleanAshRow(ashItems)
    return {
        minutes = 10, clearsAsh = true,
        equip = function() return isAshTool end,
        blocker = function(character, subject)
            return ashItems(subject) < 1 and "Tooltip_RenewableEnergy_LittleAsh" or nil
        end,
        materials = { { tool = "CLEAR_ASHES", item = "Base.Shovel", labelKey = "IGUI_RenewableEnergy_AshTool" } },
    }
end

-- Every job, by name (Jobs.define), read against the gasifier's summary
-- (Gasifier.currentSummary); `with` is the container Drain Condensate fills, or nil to drain it
-- onto the ground.
GasifierJobs.JOBS = {
    [GasifierJobs.LIGHT] = {
        minutes = function(gasifier)
            local summary = Gasifier.currentSummary(gasifier)
            return summary and summary.cold and COLD_LIGHT_MINUTES or LIGHT_MINUTES
        end,
        doneSound = "CampfireLight",
        blocker = function(character, summary)
            if summary.lit then
                return "Tooltip_RenewableEnergy_AlreadyLit"
            end
            return summary.hopperKg <= 0 and "Tooltip_RenewableEnergy_NoWood" or nil
        end,
        -- A cold one also takes bellows.
        materials = function(character, summary)
            if summary and summary.cold then
                return { GasHeater.FIRE_STARTER, BELLOWS }
            end
            return { GasHeater.FIRE_STARTER }
        end,
    },
    [GasifierJobs.PUT_OUT] = {
        minutes = 1,
        blocker = function(character, summary)
            return not summary.lit and "Tooltip_RenewableEnergy_NotLit" or nil
        end,
    },
    [GasifierJobs.CLEAN_ASH] = GasifierJobs.cleanAshRow(Gasifier.ashItems),
    -- Into the carried container `item`, or onto the ground without one.
    [GasifierJobs.DRAIN] = {
        minutes = 2,
        blocker = function(character, summary)
            return summary.condensate < MIN_CONDENSATE and "Tooltip_RenewableEnergy_NoCondensate" or nil
        end,
        with = function(item) return item:getFluidContainer() ~= nil end, withOptional = true,
        withMissing = "Tooltip_RenewableEnergy_WontTakeCondensate",
        withRefusal = function(character, summary, item)
            return item and not Gasifier.takesCondensate(item, summary.lit) and "Tooltip_RenewableEnergy_WontTakeCondensate"
                or nil
        end,
    },
}

Jobs.define(GasifierJobs, {
    subjectOf = Gasifier.currentSummary, missing = "Tooltip_RenewableEnergy_NoGasifier",
})

--- The carried containers Drain Condensate can fill now, from a gasifier `lit` or not, by name.
function GasifierJobs.drainContainers(character, lit)
    local found = Tables.fromList(character:getInventory():getAllEvalRecurse(function(item)
        return Gasifier.takesCondensate(item, lit)
    end))
    table.sort(found, function(a, b) return a:getDisplayName() < b:getDisplayName() end)
    return found
end

return GasifierJobs
