-- The option for a job of RenewableEnergyGasAction in a right-click menu, the same for every gas
-- feature.

require "RenewableEnergy/TimedActions/RenewableEnergyGasAction"
require "RenewableEnergy/UI/Needs"

RenewableEnergy = RenewableEnergy or {}
local GasJobMenu = {}
RenewableEnergy.GasJobMenu = GasJobMenu

local Needs = RenewableEnergy.Needs

--- The translation key of `job`'s name in a menu.
function GasJobMenu.labelKey(job)
    return "ContextMenu_RenewableEnergy_" .. job
end

--- Adds the option for `feature`'s `job` at `target` to `menu`, with `with` what the job works with
--- (RenewableEnergyGasAction), named `label` or the job's own name: greyed out saying it's too
--- dark for a job that needs light, else with the target's state when that refuses it, else with
--- the needs listed when the character lacks any, else with what is wrong with `with`. A job its
--- target's state refuses that belongs to another state of it (hideBlocked) is left out, as is one
--- at a target this side can't read. Returns the option, or nil when left out.
function GasJobMenu.add(menu, playerNum, feature, job, target, with, label)
    local Jobs = RenewableEnergyGasAction.jobsOf(feature)
    local subject = Jobs.subjectOf(target)
    if not subject then
        return nil
    end
    local blocker = Jobs.blocker(job, subject, with)
    if blocker and Jobs.JOBS[job].hideBlocked then
        return nil
    end
    local character = getSpecificPlayer(playerNum)
    blocker = Needs.tooDark(character, Jobs.needsLight(job)) or blocker
    local option = menu:addOption(label or getText(GasJobMenu.labelKey(job)), playerNum,
        RenewableEnergyGasAction.queue, feature, job, target, with)
    Needs.show(option, Jobs.needs(character, job, subject, with), blocker)
    Needs.refuse(option, not option.notAvailable and Jobs.check(character, job, subject, with))
    return option
end

return GasJobMenu
