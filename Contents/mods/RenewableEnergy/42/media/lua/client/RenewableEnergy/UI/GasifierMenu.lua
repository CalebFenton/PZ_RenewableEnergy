-- A gasifier's right-click menu. Loading wood and changing the filter's packing are the loot
-- window's: the hopper and the filter are its containers. The jobs' options are GasJobMenu's.

require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/WoodGas/GasifierJobs"
require "RenewableEnergy/UI/Needs"
require "RenewableEnergy/UI/GasJobMenu"
require "RenewableEnergy/UI/GasifierWindow"
require "RenewableEnergy/TimedActions/RenewableEnergyInfoAction"

RenewableEnergy = RenewableEnergy or {}
local GasifierMenu = {}
RenewableEnergy.GasifierMenu = GasifierMenu

local Gasifier, GasifierJobs = RenewableEnergy.Gasifier, RenewableEnergy.GasifierJobs
local Needs, GasifierWindow, GasJobMenu = RenewableEnergy.Needs, RenewableEnergy.GasifierWindow, RenewableEnergy.GasJobMenu

-- The carried containers the condensate can go into now, by name.
local function drainContainers(character, lit)
    local found = {}
    local items = character:getInventory():getAllEvalRecurse(function(item)
        return Gasifier.takesCondensate(item, lit)
    end)
    for i = 0, items:size() - 1 do
        table.insert(found, items:get(i))
    end
    table.sort(found, function(a, b) return a:getDisplayName() < b:getDisplayName() end)
    return found
end

-- Drain Condensate: a choice of the containers that take it, and the ground.
local function addDrain(menu, character, playerNum, gasifier, summary)
    local job = GasifierJobs.DRAIN
    local blocker = GasifierJobs.blocker(job, summary)
    if blocker then
        Needs.refuse(menu:addOption(getText(GasJobMenu.labelKey(job))), blocker)
        return
    end
    local submenu = Needs.addSubMenu(menu, getText(GasJobMenu.labelKey(job)))
    for _, item in ipairs(drainContainers(character, summary.lit)) do
        GasJobMenu.add(submenu, playerNum, "gasifier", job, gasifier, item, item:getDisplayName())
    end
    GasJobMenu.add(submenu, playerNum, "gasifier", job, gasifier, nil, getText("ContextMenu_RenewableEnergy_OntoGround"))
end

--- Adds the gasifier's submenu to `context`. Returns the submenu, or nil while this side can't
--- read the gasifier (GasifierJobs.subjectOf).
function GasifierMenu.addOptions(playerNum, context, gasifier)
    local summary = GasifierJobs.subjectOf(gasifier)
    if not summary then return end
    local character = getSpecificPlayer(playerNum)
    local menu = Needs.addSubMenu(context, getText(Gasifier.nameKey(summary.tier)))
    menu:addOption(getText("ContextMenu_RenewableEnergy_GasifierStatus"), playerNum, RenewableEnergy.InfoAction.queue, gasifier,
        GasifierWindow.open)
    GasJobMenu.add(menu, playerNum, "gasifier", summary.lit and GasifierJobs.PUT_OUT or GasifierJobs.LIGHT, gasifier)
    GasJobMenu.add(menu, playerNum, "gasifier", GasifierJobs.CLEAN_ASH, gasifier)
    addDrain(menu, character, playerNum, gasifier, summary)
    return menu
end

function GasifierMenu.onFill(playerNum, context, worldobjects, test)
    local gasifier = Needs.findClicked(worldobjects, Gasifier.isGasifier)
    if not gasifier then
        return
    end
    if test then
        return ISWorldObjectContextMenu.setTest()
    end
    GasifierMenu.addOptions(playerNum, context, gasifier)
end

Events.OnFillWorldObjectContextMenu.Add(GasifierMenu.onFill)

return GasifierMenu
