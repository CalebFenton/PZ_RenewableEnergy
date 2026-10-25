-- Every hands-on job at a digester, gas heater, gasifier or a generator's Gas Conversion Kit
-- (cf_commonlib's JobAction.forFeatures); the authority's complete() does the job. A global, as the
-- server finds the class by its Type (NetTimedAction.parse).

require "Util/BuildingHelper"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/DigesterJobs"
require "RenewableEnergy/Biogas/GasHeater"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/WoodGas/GasifierJobs"
require "RenewableEnergy/GasLine/GasKit"
local JobAction = require "cf_commonlib/JobAction"

-- Kept across a reload of this file, so the actions already queued stay of this class.
RenewableEnergyGasAction = RenewableEnergyGasAction or JobAction:derive("RenewableEnergyGasAction")

local Action = RenewableEnergyGasAction

-- How far from the middle of the object's square, on each axis in squares, the character may work
-- at it: what luautils.walkAdj counts as there, and a little for drift and a client's lag.
Action.REACH = 2.6
Action.TOO_DARK = "Tooltip_RenewableEnergy_TooDark"

-- Each feature's job module (cf_commonlib's Jobs.define) and its side of the jobs on the
-- authority. A job's `with` is what it works with, if anything: the inventory item it fills or
-- uses (a bag, a tank, a drain container), or a second world object (Connect Gas Line's source).
JobAction.forFeatures(Action, {
    digester = {
        isTarget = RenewableEnergy.Digester.isDigester,
        jobs = RenewableEnergy.DigesterJobs,
        site = function() return RenewableEnergy.DigesterSystem.jobSite end,
    },
    heater = {
        isTarget = RenewableEnergy.GasHeater.isHeater,
        jobs = RenewableEnergy.GasHeater,
        site = function() return RenewableEnergy.DigesterSystem.heaterSite end,
    },
    gasifier = {
        isTarget = RenewableEnergy.Gasifier.isGasifier,
        jobs = RenewableEnergy.GasifierJobs,
        site = function() return RenewableEnergy.GasifierSystem.jobSite end,
    },
    kit = {
        isTarget = RenewableEnergy.isGenerator,
        jobs = RenewableEnergy.GasKit,
        site = function() return RenewableEnergy.GasLines.jobSite end,
    },
})

--- The translation key of `job`'s name in a menu.
function Action.labelKey(job)
    return "ContextMenu_RenewableEnergy_" .. job
end

-- A row with `shovel` digs with the shovel its `equip` put in hand, as vanilla's Clear Ashes does;
-- without one it reaches in as "Loot".
function Action:startJob()
    local shovel = self:row().shovel and self.character:getPrimaryHandItem()
    if shovel then
        self:setActionAnim(BuildingHelper.getShovelAnim(shovel))
        return
    end
    JobAction.startJob(self)
end
