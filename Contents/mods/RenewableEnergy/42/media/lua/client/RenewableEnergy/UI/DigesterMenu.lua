-- The right-click menus of a digester and of a gas heater.
-- Feeding is the loot window's: the hopper is its container. The jobs' options are cf_commonlib's
-- JobOptions'.

require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/DigesterJobs"
require "RenewableEnergy/Biogas/GasHeater"
require "RenewableEnergy/TimedActions/RenewableEnergyGasAction"
require "RenewableEnergy/UI/ObjectWindow"
require "RenewableEnergy/UI/DigesterWindow"
local JobOptions = require "cf_commonlib/JobOptions"
local Needs = require "cf_commonlib/Needs"

RenewableEnergy = RenewableEnergy or {}
local DigesterMenu = {}
RenewableEnergy.DigesterMenu = DigesterMenu

local Digester, DigesterJobs, GasHeater = RenewableEnergy.Digester, RenewableEnergy.DigesterJobs, RenewableEnergy.GasHeater
local ObjectWindow, DigesterWindow = RenewableEnergy.ObjectWindow, RenewableEnergy.DigesterWindow
local Action = RenewableEnergyGasAction

-- Adds the option for `feature`'s `job`, with `item` the bag or tank it fills.
local function addJob(menu, playerNum, feature, job, target, item)
    return JobOptions.add(menu, playerNum, Action, feature, job, target, item, getText(Action.labelKey(job)))
end

--- Adds the digester's submenu to `context`. Returns the submenu, or nil while this side can't
--- read the digester (DigesterJobs.subjectOf).
function DigesterMenu.addOptions(playerNum, context, digester)
    local summary = DigesterJobs.subjectOf(digester)
    if not summary then return end
    local character = getSpecificPlayer(playerNum)
    local menu = Needs.addSubMenu(context, getText(Digester.nameKey(summary.tier)))
    menu:addOption(getText("ContextMenu_RenewableEnergy_Status"), playerNum, ObjectWindow.queueOpen, digester,
        DigesterWindow)

    addJob(menu, playerNum, "digester", DigesterJobs.TAKE_SLUDGE, digester, DigesterJobs.sludgeBag(character))
    for _, job in ipairs({ DigesterJobs.VENT, DigesterJobs.REPLACE_BAGS, DigesterJobs.SEW_TARP, DigesterJobs.UPGRADE }) do
        addJob(menu, playerNum, "digester", job, digester)
    end
    local tank = DigesterJobs.tankToFill(character)
    for _, job in ipairs({ DigesterJobs.FILL_PUMP, DigesterJobs.FILL_COMPRESSOR }) do
        addJob(menu, playerNum, "digester", job, digester, tank)
    end
    addJob(menu, playerNum, "digester", DigesterJobs.FIT_SCRUBBER, digester)
    if summary.scrubber then
        local chargeMenu = Needs.addSubMenu(menu, getText("ContextMenu_RenewableEnergy_ChargeScrubber"))
        for _, job in ipairs({ DigesterJobs.CHARGE_WATER, DigesterJobs.CHARGE_ASH, DigesterJobs.CHARGE_LIME }) do
            addJob(chargeMenu, playerNum, "digester", job, digester)
        end
    end
    addJob(menu, playerNum, "digester", DigesterJobs.REPACK_WOOL, digester)
    return menu
end

--- Adds a gas heater's option to `context`: light it, or put it out. Returns the option.
function DigesterMenu.addHeaterOptions(playerNum, context, heater)
    local job = GasHeater.isLit(heater) and GasHeater.OFF or GasHeater.LIGHT
    return addJob(context, playerNum, "heater", job, heater)
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
