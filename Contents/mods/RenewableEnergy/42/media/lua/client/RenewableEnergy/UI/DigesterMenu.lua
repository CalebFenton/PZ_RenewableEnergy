-- The right-click menu of a digester. Feeding is the loot window's: the hopper is its container.
-- Each job queues a RenewableEnergyDigesterAction, which walks the character over and does it; an
-- option the character can't do yet stays in the menu, greyed out, saying what it needs.

require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/DigesterJobs"
require "RenewableEnergy/TimedActions/RenewableEnergyDigesterAction"
require "RenewableEnergy/UI/Needs"
require "RenewableEnergy/UI/DigesterWindow"

RenewableEnergy = RenewableEnergy or {}
local DigesterMenu = {}
RenewableEnergy.DigesterMenu = DigesterMenu

local Digester, DigesterJobs = RenewableEnergy.Digester, RenewableEnergy.DigesterJobs
local Needs, DigesterWindow = RenewableEnergy.Needs, RenewableEnergy.DigesterWindow
local Action = RenewableEnergyDigesterAction

local function queue(playerNum, job, digester, item)
    local character = getSpecificPlayer(playerNum)
    if luautils.walkAdj(character, digester:getSquare(), true) then
        ISTimedActionQueue.add(Action:new(character, job, digester, item))
    end
end

local function disable(option, description)
    option.notAvailable = true
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip.description = description
end

-- Adds the option for `job`: greyed out with the digester's reason when its state refuses it, or
-- with the needs listed when the character lacks any.
local function addJob(menu, character, playerNum, job, digester, summary, item)
    local option = menu:addOption(getText("ContextMenu_RenewableEnergy_" .. job), playerNum, queue, job, digester, item)
    local blocker = DigesterJobs.blocker(job, summary)
    if blocker then
        disable(option, getText(blocker))
        return option
    end
    local needs = DigesterJobs.needs(character, job)
    if #needs > 0 then
        option.notAvailable = RenewableEnergy.firstUnmet(needs) ~= nil
        option.toolTip = ISWorldObjectContextMenu.addToolTip()
        option.toolTip.description = Needs.describe(needs)
    end
    return option
end

--- Adds the digester's submenu to `context`. Returns the submenu, or nil before this client has
--- the digester's summary.
function DigesterMenu.addOptions(playerNum, context, digester)
    local summary = Digester.summaryOf(digester)
    if not summary then return end
    local character = getSpecificPlayer(playerNum)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(context:addOption(getText("IGUI_RenewableEnergy_Digester_" .. summary.tier)), menu)
    menu:addOption(getText("ContextMenu_RenewableEnergy_DigesterStatus"), playerNum, DigesterWindow.open, digester)

    local bag = DigesterJobs.sludgeBag(character)
    local sludge = addJob(menu, character, playerNum, DigesterJobs.TAKE_SLUDGE, digester, summary, bag)
    if not sludge.notAvailable and not bag then
        disable(sludge, getText("Tooltip_RenewableEnergy_NeedsSandbag"))
    end
    addJob(menu, character, playerNum, DigesterJobs.VENT, digester, summary)
    if summary.holder == "bags" then
        addJob(menu, character, playerNum, DigesterJobs.REPLACE_BAGS, digester, summary)
    end
    if summary.holder == "bags" or summary.torn then
        addJob(menu, character, playerNum, DigesterJobs.SEW_TARP, digester, summary)
    end
    if summary.tier == "barrel" then
        addJob(menu, character, playerNum, DigesterJobs.UPGRADE, digester, summary)
    end
    return menu
end

local function findDigester(worldobjects)
    local seen = {}
    for _, clicked in ipairs(worldobjects) do
        local square = clicked:getSquare()
        if square and not seen[square] then
            seen[square] = true
            local found = RenewableEnergy.findObjectOn(square, Digester.isDigester)
            if found then
                return found
            end
        end
    end
    return nil
end

function DigesterMenu.onFill(playerNum, context, worldobjects, test)
    local digester = findDigester(worldobjects)
    if not digester then
        return
    end
    if test then
        return ISWorldObjectContextMenu.setTest()
    end
    DigesterMenu.addOptions(playerNum, context, digester)
end

Events.OnFillWorldObjectContextMenu.Add(DigesterMenu.onFill)

return DigesterMenu
