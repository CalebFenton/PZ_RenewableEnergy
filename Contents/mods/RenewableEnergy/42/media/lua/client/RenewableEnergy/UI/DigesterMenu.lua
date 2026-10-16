-- The right-click menus of a digester and of a gas heater, and the client's digester system.
-- Feeding is the loot window's: the hopper is its container. Each job queues a timed action, which
-- walks the character over and does it; an option the character can't do yet stays in the menu,
-- greyed out, saying what it needs.

require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/ClientObjects"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/DigesterJobs"
require "RenewableEnergy/Biogas/GasHeater"
require "RenewableEnergy/TimedActions/RenewableEnergyGasAction"
require "RenewableEnergy/UI/Needs"
require "RenewableEnergy/UI/DigesterWindow"

RenewableEnergy = RenewableEnergy or {}
local DigesterMenu = {}
RenewableEnergy.DigesterMenu = DigesterMenu

local Digester, DigesterJobs, GasHeater = RenewableEnergy.Digester, RenewableEnergy.DigesterJobs, RenewableEnergy.GasHeater
local Needs, DigesterWindow = RenewableEnergy.Needs, RenewableEnergy.DigesterWindow
local queue = RenewableEnergyGasAction.queue

RenewableEnergy.ClientObjects.define({
    name = "Digester", kind = "digester", owner = Digester, isObject = Digester.isDigester,
    adoptCopy = function(isoObject)
        Digester.adoptContainer(isoObject:getContainer())
    end,
    adoptContainer = Digester.adoptContainer,
})

-- Adds the option for `job`: greyed out with the digester's reason when its state refuses it, or
-- with the needs listed when the character lacks any.
local function addJob(menu, character, playerNum, job, digester, summary, item)
    local option = menu:addOption(getText("ContextMenu_RenewableEnergy_" .. job), playerNum, queue, "digester", job, digester, item)
    Needs.show(option, DigesterJobs.needs(character, job), DigesterJobs.blocker(job, summary))
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
        Needs.disable(sludge, getText("Tooltip_RenewableEnergy_NeedsSandbag"))
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

    local tank = DigesterJobs.tankToFill(character)
    for _, job in ipairs({ DigesterJobs.FILL_PUMP, DigesterJobs.FILL_COMPRESSOR }) do
        local option = addJob(menu, character, playerNum, job, digester, summary, tank)
        local refusal = not option.notAvailable and DigesterJobs.fillRefusal(character, job, summary, tank)
        if refusal then
            Needs.disable(option, getText(refusal))
        end
    end

    if not summary.scrubber then
        addJob(menu, character, playerNum, DigesterJobs.FIT_SCRUBBER, digester, summary)
    else
        local charge = menu:addOption(getText("ContextMenu_RenewableEnergy_ChargeScrubber"))
        local chargeMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(charge, chargeMenu)
        for _, job in ipairs({ DigesterJobs.CHARGE_WATER, DigesterJobs.CHARGE_ASH, DigesterJobs.CHARGE_LIME }) do
            addJob(chargeMenu, character, playerNum, job, digester, summary)
        end
        addJob(menu, character, playerNum, DigesterJobs.REPACK_WOOL, digester, summary)
    end
    return menu
end

--- Adds a gas heater's option to `context`: light it, or put it out. Returns the option.
function DigesterMenu.addHeaterOptions(playerNum, context, heater)
    local job = GasHeater.isLit(heater) and GasHeater.OFF or GasHeater.LIGHT
    local option = context:addOption(getText("ContextMenu_RenewableEnergy_" .. job), playerNum, queue, "heater", job, heater)
    Needs.show(option, GasHeater.needs(getSpecificPlayer(playerNum), job), GasHeater.blocker(job, heater))
    return option
end

function DigesterMenu.onFill(playerNum, context, worldobjects, test)
    local digester = Needs.findClicked(worldobjects, Digester.isDigester)
    local heater = Needs.findClicked(worldobjects, GasHeater.isHeater)
    if not (digester or heater) then
        return
    end
    if test then
        return ISWorldObjectContextMenu.setTest()
    end
    if digester then
        DigesterMenu.addOptions(playerNum, context, digester)
    end
    if heater then
        DigesterMenu.addHeaterOptions(playerNum, context, heater)
    end
end

Events.OnFillWorldObjectContextMenu.Add(DigesterMenu.onFill)

return DigesterMenu
