-- A gasifier's right-click menu. Loading wood and changing the filter's packing are the loot
-- window's: the hopper and the filter are its containers. The jobs' options are cf_commonlib's
-- JobOptions'.

local Gasifier = require "RenewableEnergy/WoodGas/Gasifier"
local GasifierJobs = require "RenewableEnergy/WoodGas/GasifierJobs"
local ObjectWindow = require "RenewableEnergy/UI/ObjectWindow"
local GasifierWindow = require "RenewableEnergy/UI/GasifierWindow"
local JobOptions = require "cf_commonlib/JobOptions"
local Needs = require "cf_commonlib/Needs"

local GasifierMenu = {}

-- Drain Condensate: a choice of the containers that take it, and the ground.
local function addDrain(menu, character, playerNum, gasifier, summary)
    local job = GasifierJobs.DRAIN
    local blocker = GasifierJobs.verdict(character, job, summary).blocker
    if blocker then
        Needs.refuse(menu:addOption(JobOptions.jobName(GasifierJobs, job)), blocker)
        return
    end
    local submenu = JobOptions.addSubMenu(menu, JobOptions.jobName(GasifierJobs, job))
    for _, item in ipairs(GasifierJobs.drainContainers(character, summary.lit)) do
        JobOptions.add(submenu, playerNum, GasifierJobs, job, gasifier, item, item:getDisplayName())
    end
    JobOptions.add(submenu, playerNum, GasifierJobs, job, gasifier, nil, getText("ContextMenu_RenewableEnergy_OntoGround"))
end

--- Adds the gasifier's submenu to `context`. Returns the submenu, or nil while this side can't
--- read the gasifier (GasifierJobs.subjectOf).
function GasifierMenu.addOptions(playerNum, context, gasifier)
    local summary = GasifierJobs.subjectOf(gasifier)
    if not summary then return end
    local character = getSpecificPlayer(playerNum)
    local menu = JobOptions.addSubMenu(context, getText(Gasifier.nameKey(summary.tier)))
    menu:addOption(getText("ContextMenu_RenewableEnergy_Status"), playerNum, ObjectWindow.queueOpen, gasifier,
        GasifierWindow)
    local fire = summary.lit and GasifierJobs.PUT_OUT or GasifierJobs.LIGHT
    JobOptions.add(menu, playerNum, GasifierJobs, fire, gasifier)
    JobOptions.add(menu, playerNum, GasifierJobs, GasifierJobs.CLEAN_ASH, gasifier)
    addDrain(menu, character, playerNum, gasifier, summary)
    return menu
end

JobOptions.onWorldMenu(JobOptions.clicked(Gasifier.isGasifier), function(context, playerNum, character, gasifier)
    GasifierMenu.addOptions(playerNum, context, gasifier)
end)

return GasifierMenu
