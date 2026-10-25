-- The right-click menus of a digester and of a gas heater.
-- Feeding is the loot window's: the hopper is its container. The jobs' options are cf_commonlib's
-- JobOptions'.

require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/DigesterJobs"
require "RenewableEnergy/Biogas/GasHeater"
require "RenewableEnergy/TimedActions/RenewableEnergyGasAction"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/ObjectWindow"
require "RenewableEnergy/UI/DigesterWindow"
local JobOptions = require "cf_commonlib/JobOptions"
local Needs = require "cf_commonlib/Needs"

RenewableEnergy = RenewableEnergy or {}
local DigesterMenu = {}
RenewableEnergy.DigesterMenu = DigesterMenu

local Digester, DigesterJobs, GasHeater = RenewableEnergy.Digester, RenewableEnergy.DigesterJobs, RenewableEnergy.GasHeater
local ObjectWindow, DigesterWindow, Format = RenewableEnergy.ObjectWindow, RenewableEnergy.DigesterWindow, RenewableEnergy.Format
local Action = RenewableEnergyGasAction

-- The job's name, with what it has to go on as an eyeball share, as vanilla's Get Compost (45%).
local function label(job, share)
    local name = getText(Action.labelKey(job))
    return share and name .. " (" .. Format.percent(share) .. ")" or name
end

-- Adds the option for `feature`'s `job`, with `item` the item it works with.
local function addJob(menu, playerNum, feature, job, target, item, text)
    return JobOptions.add(menu, playerNum, Action, feature, job, target, item, text or label(job))
end

-- Take Sludge, into each bag that takes it, as vanilla's Get Compost lists them with the share of
-- the digester each would take.
local function addSludge(menu, playerNum, digester, summary)
    local perUse = DigesterJobs.sludgePerUse()
    JobOptions.addEach(menu, playerNum, Action, "digester", DigesterJobs.TAKE_SLUDGE, digester,
        DigesterJobs.sludgeBags(getSpecificPlayer(playerNum)), label(DigesterJobs.TAKE_SLUDGE, summary.sludge / 100),
        function(bag)
            return bag:getDisplayName() .. " (" .. Format.percent(DigesterJobs.sludgeUses(bag, summary.sludge) * perUse / 100) .. ")"
        end)
end

-- A barrel's gas bag: new garbage bags, each Tarp Gas Bag carried at its condition, and taking off
-- the one there.
local function addGasBag(menu, playerNum, digester, summary)
    local bagMenu = Needs.addSubMenu(menu, getText("ContextMenu_RenewableEnergy_GasBag"))
    addJob(bagMenu, playerNum, "digester", DigesterJobs.FIT_BAGS, digester)
    local tarps = DigesterJobs.tarpBags(getSpecificPlayer(playerNum))
    if #tarps == 0 then
        addJob(bagMenu, playerNum, "digester", DigesterJobs.FIT_TARP, digester)
    end
    for _, tarp in ipairs(tarps) do
        local option = addJob(bagMenu, playerNum, "digester", DigesterJobs.FIT_TARP, digester, tarp,
            label(DigesterJobs.FIT_TARP, tarp:getCondition() / tarp:getConditionMax()))
        option.itemForTexture = tarp
    end
    if summary.holder ~= "none" then
        addJob(bagMenu, playerNum, "digester", DigesterJobs.TAKE_OFF_BAG, digester)
    end
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

    addSludge(menu, playerNum, digester, summary)
    addJob(menu, playerNum, "digester", DigesterJobs.VENT, digester, nil,
        label(DigesterJobs.VENT, summary.capacity > 0 and summary.gas / summary.capacity or nil))
    if Digester.TIERS[summary.tier].gasBag then
        addGasBag(menu, playerNum, digester, summary)
    end
    addJob(menu, playerNum, "digester", DigesterJobs.UPGRADE, digester)

    -- Each way of filling, then what to fill: the emptiest tank, torch and bottle carried, each
    -- with how full it is.
    local vessels = DigesterJobs.toFill(character)
    for _, job in ipairs({ DigesterJobs.FILL_PUMP, DigesterJobs.FILL_COMPRESSOR }) do
        JobOptions.addEach(menu, playerNum, Action, "digester", job, digester, vessels, label(job), function(vessel)
            return vessel:getDisplayName() .. " (" .. Format.percent(vessel:getCurrentUsesFloat()) .. ")"
        end)
    end
    if not summary.scrubber then
        addJob(menu, playerNum, "digester", DigesterJobs.FIT_SCRUBBER, digester)
        return menu
    end
    local refillMenu = Needs.addSubMenu(menu, getText("ContextMenu_RenewableEnergy_RefillScrubber"))
    for _, job in ipairs({ DigesterJobs.REFILL_WATER, DigesterJobs.REFILL_ASH, DigesterJobs.REFILL_LIME, DigesterJobs.REFILL_WOOL }) do
        addJob(refillMenu, playerNum, "digester", job, digester)
    end
    addJob(refillMenu, playerNum, "digester", DigesterJobs.REFILL_SPONGE, digester, DigesterJobs.spongeToPack(character))
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
