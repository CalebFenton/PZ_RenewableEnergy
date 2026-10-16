-- A gasifier's right-click menu. Loading wood and changing the filter's packing are the loot
-- window's: the hopper and the filter are its containers. Each job queues a timed action, which
-- walks the character over and does it; one the character can't do yet stays greyed out, saying
-- what it needs.

require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/WoodGas/GasifierJobs"
require "RenewableEnergy/TimedActions/RenewableEnergyGasifierAction"
require "RenewableEnergy/UI/Needs"
require "RenewableEnergy/UI/GasifierWindow"

RenewableEnergy = RenewableEnergy or {}
local GasifierMenu = {}
RenewableEnergy.GasifierMenu = GasifierMenu

local Gasifier, GasifierJobs = RenewableEnergy.Gasifier, RenewableEnergy.GasifierJobs
local Needs, GasifierWindow = RenewableEnergy.Needs, RenewableEnergy.GasifierWindow

local function notBroken(item)
    return not item:isBroken()
end

local function queue(playerNum, job, gasifier, item)
    local character = getSpecificPlayer(playerNum)
    if not luautils.walkAdj(character, gasifier:getSquare(), true) then
        return
    end
    if job == GasifierJobs.CLEAN_ASH then
        -- In hand, as vanilla's Clear Ashes takes its shovel.
        ISWorldObjectContextMenu.equip(character, character:getPrimaryHandItem(), function(tool)
            return tool:hasTag(ItemTag.TAKE_DIRT) and notBroken(tool)
        end, true)
    end
    ISTimedActionQueue.add(RenewableEnergyGasifierAction:new(character, job, gasifier, item))
end

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
    local option = menu:addOption(getText("ContextMenu_RenewableEnergy_" .. GasifierJobs.DRAIN))
    local blocker = GasifierJobs.blocker(GasifierJobs.DRAIN, summary)
    if blocker then
        option.notAvailable = true
        option.toolTip = ISWorldObjectContextMenu.addToolTip()
        option.toolTip.description = getText(blocker)
        return
    end
    local submenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(option, submenu)
    for _, item in ipairs(drainContainers(character, summary.lit)) do
        submenu:addOption(item:getDisplayName(), playerNum, queue, GasifierJobs.DRAIN, gasifier, item)
    end
    submenu:addOption(getText("ContextMenu_RenewableEnergy_OntoGround"), playerNum, queue, GasifierJobs.DRAIN, gasifier)
end

local function addJob(menu, character, playerNum, job, gasifier, summary)
    local option = menu:addOption(getText("ContextMenu_RenewableEnergy_" .. job), playerNum, queue, job, gasifier)
    local blocker = GasifierJobs.blocker(job, summary)
    if blocker then
        option.notAvailable = true
        option.toolTip = ISWorldObjectContextMenu.addToolTip()
        option.toolTip.description = getText(blocker)
        return option
    end
    local needs = GasifierJobs.needs(character, job, summary)
    if #needs > 0 then
        option.notAvailable = RenewableEnergy.firstUnmet(needs) ~= nil
        option.toolTip = ISWorldObjectContextMenu.addToolTip()
        option.toolTip.description = Needs.describe(needs)
    end
    return option
end

--- Adds the gasifier's submenu to `context`. Returns the submenu, or nil before this client has
--- the gasifier's summary.
function GasifierMenu.addOptions(playerNum, context, gasifier)
    local summary = Gasifier.summaryOf(gasifier)
    if not summary then return end
    local character = getSpecificPlayer(playerNum)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(context:addOption(getText("IGUI_RenewableEnergy_Gasifier_" .. summary.tier)), menu)
    menu:addOption(getText("ContextMenu_RenewableEnergy_GasifierStatus"), playerNum, GasifierWindow.open, gasifier)
    addJob(menu, character, playerNum, summary.lit and GasifierJobs.PUT_OUT or GasifierJobs.LIGHT, gasifier, summary)
    addJob(menu, character, playerNum, GasifierJobs.CLEAN_ASH, gasifier, summary)
    addDrain(menu, character, playerNum, gasifier, summary)
    return menu
end

function GasifierMenu.onFill(playerNum, context, worldobjects, test)
    local seen = {}
    for _, clicked in ipairs(worldobjects) do
        local square = clicked:getSquare()
        if square and not seen[square] then
            seen[square] = true
            local gasifier = RenewableEnergy.findObjectOn(square, Gasifier.isGasifier)
            if gasifier then
                if test then
                    return ISWorldObjectContextMenu.setTest()
                end
                GasifierMenu.addOptions(playerNum, context, gasifier)
                return
            end
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(GasifierMenu.onFill)

return GasifierMenu
