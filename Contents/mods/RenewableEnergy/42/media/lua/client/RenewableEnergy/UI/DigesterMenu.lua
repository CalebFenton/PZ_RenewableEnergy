-- The right-click menus of a digester and of a gas heater.
-- Feeding is the loot window's: the hopper is its container. The jobs' options are cf_commonlib's
-- JobOptions'.

local Digester = require "RenewableEnergy/Biogas/Digester"
local DigesterJobs = require "RenewableEnergy/Biogas/DigesterJobs"
local GasHeater = require "RenewableEnergy/Biogas/GasHeater"
local Action = require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local Format = require "RenewableEnergy/UI/Format"
local ObjectWindow = require "RenewableEnergy/UI/ObjectWindow"
local DigesterWindow = require "RenewableEnergy/UI/DigesterWindow"
local JobOptions = require "cf_commonlib/JobOptions"

local DigesterMenu = {}

-- The job's name, with what it has to go on as an eyeball share, as vanilla's Get Compost (45%).
local function label(job, share)
    local name = getText(Action.labelKey(job))
    return share and name .. " (" .. Format.percent(share) .. ")" or name
end

-- Take Sludge, into each bag that takes it, as vanilla's Get Compost lists them with the share of
-- the digester each would take.
local function addSludge(menu, playerNum, digester, summary)
    local perUse = DigesterJobs.sludgePerUse()
    JobOptions.addEach(menu, playerNum, DigesterJobs, DigesterJobs.TAKE_SLUDGE, digester,
        DigesterJobs.sludgeBags(getSpecificPlayer(playerNum)), label(DigesterJobs.TAKE_SLUDGE, summary.sludge / 100),
        function(bag)
            return bag:getDisplayName() .. " (" .. Format.percent(DigesterJobs.sludgeUses(bag, summary.sludge) * perUse / 100) .. ")"
        end)
end

-- A barrel's gas bag: new garbage bags, each Tarp Gas Bag carried at its condition, and taking off
-- the one there.
local function addGasBag(menu, playerNum, digester, summary)
    local bagMenu = JobOptions.addSubMenu(menu, getText("ContextMenu_RenewableEnergy_GasBag"))
    JobOptions.add(bagMenu, playerNum, DigesterJobs, DigesterJobs.FIT_BAGS, digester)
    local tarps = DigesterJobs.tarpBags(getSpecificPlayer(playerNum))
    if #tarps == 0 then
        JobOptions.add(bagMenu, playerNum, DigesterJobs, DigesterJobs.FIT_TARP, digester)
    end
    for _, tarp in ipairs(tarps) do
        local option = JobOptions.add(bagMenu, playerNum, DigesterJobs, DigesterJobs.FIT_TARP, digester, tarp,
            label(DigesterJobs.FIT_TARP, tarp:getCondition() / tarp:getConditionMax()))
        option.itemForTexture = tarp
    end
    if summary.holder ~= "none" then
        JobOptions.add(bagMenu, playerNum, DigesterJobs, DigesterJobs.TAKE_OFF_BAG, digester)
    end
end

--- Adds the digester's submenu to `context`. Returns the submenu, or nil while this side can't
--- read the digester (DigesterJobs.subjectOf).
function DigesterMenu.addOptions(playerNum, context, digester)
    local summary = DigesterJobs.subjectOf(digester)
    if not summary then return end
    local character = getSpecificPlayer(playerNum)
    local menu = JobOptions.addSubMenu(context, getText(Digester.nameKey(summary.tier)))
    menu:addOption(getText("ContextMenu_RenewableEnergy_Status"), playerNum, ObjectWindow.queueOpen, digester,
        DigesterWindow)

    addSludge(menu, playerNum, digester, summary)
    JobOptions.add(menu, playerNum, DigesterJobs, DigesterJobs.VENT, digester, nil,
        label(DigesterJobs.VENT, summary.capacity > 0 and summary.gas / summary.capacity or nil))
    if Digester.TIERS[summary.tier].gasBag then
        addGasBag(menu, playerNum, digester, summary)
    end
    JobOptions.add(menu, playerNum, DigesterJobs, DigesterJobs.UPGRADE, digester)

    -- Each way of filling, then what to fill: the emptiest tank, torch and bottle carried, each
    -- with how full it is.
    local vessels = DigesterJobs.toFill(character)
    for _, job in ipairs({ DigesterJobs.FILL_PUMP, DigesterJobs.FILL_COMPRESSOR }) do
        JobOptions.addEach(menu, playerNum, DigesterJobs, job, digester, vessels, label(job), function(vessel)
            return vessel:getDisplayName() .. " (" .. Format.percent(vessel:getCurrentUsesFloat()) .. ")"
        end)
    end
    if not summary.scrubber then
        JobOptions.add(menu, playerNum, DigesterJobs, DigesterJobs.FIT_SCRUBBER, digester)
        return menu
    end
    local refillMenu = JobOptions.addSubMenu(menu, getText("ContextMenu_RenewableEnergy_RefillScrubber"))
    for _, job in ipairs({ DigesterJobs.REFILL_WATER, DigesterJobs.REFILL_ASH, DigesterJobs.REFILL_LIME, DigesterJobs.REFILL_WOOL }) do
        JobOptions.add(refillMenu, playerNum, DigesterJobs, job, digester)
    end
    JobOptions.add(refillMenu, playerNum, DigesterJobs, DigesterJobs.REFILL_SPONGE, digester,
        DigesterJobs.spongeToPack(character))
    return menu
end

--- Adds a gas heater's option to `context`: light it, or put it out. Returns the option.
function DigesterMenu.addHeaterOptions(playerNum, context, heater)
    local job = GasHeater.isLit(heater) and GasHeater.OFF or GasHeater.LIGHT
    return JobOptions.add(context, playerNum, GasHeater, job, heater)
end

JobOptions.onWorldMenu(JobOptions.clicked(Digester.isDigester), function(context, playerNum, character, digester)
    DigesterMenu.addOptions(playerNum, context, digester)
end)

JobOptions.onWorldMenu(JobOptions.clicked(GasHeater.isHeater), function(context, playerNum, character, heater)
    DigesterMenu.addHeaterOptions(playerNum, context, heater)
end)

return DigesterMenu
