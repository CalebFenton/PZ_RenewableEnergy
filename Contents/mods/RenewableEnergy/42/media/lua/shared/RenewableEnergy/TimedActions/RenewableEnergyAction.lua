-- Every hands-on job of fixed length the mod has, at a bank, a source, a treadmill, a garden light,
-- a vehicle, a digester, a gas heater, a gasifier, a vanilla wood fire or a generator's Gas
-- Conversion Kit (cf_commonlib's JobAction.forFeatures); the authority's complete() does the job.
-- A global, as the server finds the class by its Type (NetTimedAction.parse).

require "Util/BuildingHelper"
local RenewableEnergy = require "RenewableEnergy/Utilities"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLight"
local VehicleJobs = require "RenewableEnergy/Gadgets/VehicleJobs"
local Digester = require "RenewableEnergy/Biogas/Digester"
local DigesterJobs = require "RenewableEnergy/Biogas/DigesterJobs"
local GasHeater = require "RenewableEnergy/Biogas/GasHeater"
local Gasifier = require "RenewableEnergy/WoodGas/Gasifier"
local GasifierJobs = require "RenewableEnergy/WoodGas/GasifierJobs"
local FireAsh = require "RenewableEnergy/WoodGas/FireAsh"
local GasKit = require "RenewableEnergy/GasLine/GasKit"
local JobAction = require "cf_commonlib/JobAction"

-- Kept across a reload of this file, so the actions already queued stay of this class.
RenewableEnergyAction = RenewableEnergyAction or JobAction:derive("RenewableEnergyAction")

local Action = RenewableEnergyAction
Action.REPORTS_LOOT = true
Action.TOO_DARK = "Tooltip_RenewableEnergy_TooDark"

-- How far from the middle of the target's square, on each axis, a character may work: what
-- luautils.walkAdj and getCorrectSquareForWall leave as "there" for a wall's panel, plus slack for
-- drift and client lag. A vehicle job measures past the vehicle's body
-- (ISPathFindAction.pathToVehicleArea).
Action.REACH = 4.6
-- A gas feature's objects stand on the floor, which luautils.walkAdj walks right up to.
local GAS_REACH = 2.6

-- Server code: it loads after the shared files, so each is looked up when a job completes.
local function sites()
    return RenewableEnergy.JobSites
end

-- Each feature's job module (cf_commonlib's Jobs.define) and its side of the jobs on the
-- authority. A job's `with` is what it works with, if anything: the inventory item it uses (a
-- part, a tool, a bag, a tank), a second world object (the bank Connect Source wires to, the far
-- end of Connect Gas Line), or what a client says (a bank's new name, a panel's module slot, a
-- trailer's panel part).
JobAction.forFeatures(Action, {
    bank = {
        isTarget = PowerBank.isBank,
        jobs = BankJobs,
        site = function() return sites().bank end,
    },
    source = {
        isTarget = Sources.kindOf,
        jobs = SourceJobs,
        site = function() return sites().source end,
    },
    treadmill = {
        isTarget = Treadmill.isTreadmill,
        jobs = Treadmill,
        site = function() return sites().treadmill end,
    },
    light = {
        isTarget = SolarGardenLight.isLight,
        jobs = SolarGardenLight,
        site = function() return sites().light end,
    },
    vehicle = {
        isTarget = VehicleJobs.subjectOf,
        jobs = VehicleJobs,
        site = function() return sites().vehicle end,
    },
    digester = {
        isTarget = Digester.isDigester,
        jobs = DigesterJobs,
        site = function() return RenewableEnergy.DigesterSystem.jobSite end,
        reach = GAS_REACH,
    },
    heater = {
        isTarget = GasHeater.isHeater,
        jobs = GasHeater,
        site = function() return RenewableEnergy.DigesterSystem.heaterSite end,
        reach = GAS_REACH,
    },
    gasifier = {
        isTarget = Gasifier.isGasifier,
        jobs = GasifierJobs,
        site = function() return RenewableEnergy.GasifierSystem.jobSite end,
        reach = GAS_REACH,
    },
    fire = {
        isTarget = FireAsh.isFire,
        jobs = FireAsh,
        site = function() return sites().fire end,
    },
    kit = {
        isTarget = RenewableEnergy.isGenerator,
        jobs = GasKit,
        site = function() return RenewableEnergy.GasLines.jobSite end,
        reach = GAS_REACH,
    },
})

--- The translation key of `job`'s name in a menu.
function Action.labelKey(job)
    return "ContextMenu_RenewableEnergy_" .. job
end

-- A row with `clearsAsh` works with the tool its `equip` put in hand as vanilla's Clear Ashes does:
-- a broom sweeps, anything else digs; without one it reaches in as "Loot".
function Action:startJob()
    local tool = self:row().clearsAsh and self.character:getPrimaryHandItem()
    if tool then
        self:setActionAnim(tool:getType() == "Broom" and "Rake" or BuildingHelper.getShovelAnim(tool))
        return
    end
    JobAction.startJob(self)
end

return Action
