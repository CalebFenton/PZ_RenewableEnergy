-- The right-click menu of a source a bank takes (a solar panel, a wind charger or a wired
-- treadmill) and of a treadmill not yet wired. Each job's option is cf_commonlib's JobOptions',
-- greyed out by SourceJobs or Treadmill, which the action and the authority ask, so the menu
-- refuses exactly what they would.

local Wind = require "RenewableEnergy/Wind"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local ModuleRepair = require "RenewableEnergy/PowerBank/ModuleRepair"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local TreadmillAction = require "RenewableEnergy/TimedActions/RenewableEnergyTreadmillAction"
local Format = require "RenewableEnergy/UI/Format"
local BankMenu = require "RenewableEnergy/UI/BankMenu"
local Items = require "cf_commonlib/Items"
local JobOptions = require "cf_commonlib/JobOptions"
local Needs = require "cf_commonlib/Needs"
local Squares = require "cf_commonlib/Squares"

local SourceMenu = {}

--- The name of a source's or treadmill's tile (Format.tileName). A vanilla treadmill's moveable
--- name is "Hamster Wheel", so it gets its own.
function SourceMenu.nameOf(isoObject)
    if Treadmill.isTreadmill(isoObject) then
        return getText("IGUI_RenewableEnergy_Treadmill")
    end
    return Format.tileName(isoObject)
end

local function queueRun(playerNum, treadmill)
    local character = getSpecificPlayer(playerNum)
    Squares.queueBeside(character, treadmill:getSquare(), function()
        ISTimedActionQueue.add(TreadmillAction:new(character, treadmill))
    end)
end

-- The entry for the source at `here` in its bank's summary.
local function sourceSummary(bankPosition, here)
    local summary = PowerBank.summaryAt(bankPosition.x, bankPosition.y, bankPosition.z)
    for _, entry in ipairs(summary and summary.sources or {}) do
        if Squares.samePosition(entry, here) then
            return entry
        end
    end
end

-- The name of the bank at `at` (BankMenu.bankLabel), or the status window's title while its square
-- isn't loaded here.
local function bankNameAt(at)
    local bank = PowerBank.findOn(getSquare(at.x, at.y, at.z))
    return bank and BankMenu.bankLabel(bank) or getText("IGUI_RenewableEnergy_StatusTitle")
end

-- Clear Snow on a source whose summary entry says it is snowy, with the broom or snow shovel the
-- character would use.
local function addSnowOption(playerNum, menu, source, entry)
    if entry and entry.snowy and Sources.sweepable(Sources.kindOf(source)) then
        JobOptions.add(menu, playerNum, SourceJobs, SourceJobs.CLEAR_SNOW, source,
            Items.toolFor(getSpecificPlayer(playerNum), SourceJobs.isSnowTool))
    end
end

-- Replace Blades, for a wind charger whose blades broke or wore out, with the blades the character would fit
-- (SourceJobs.bladesFor), or the option greyed, naming all it takes.
local function addBladesOption(playerNum, menu, source)
    if not (Wind.bladesOfObject(source) and Wind.isBroken(source)) then
        return
    end
    local blades, names = SourceJobs.bladesFor(getSpecificPlayer(playerNum), source)
    if blades then
        JobOptions.add(menu, playerNum, SourceJobs, SourceJobs.REPLACE_BLADES, source, blades)
    else
        Needs.refuse(menu:addOption(JobOptions.jobName(SourceJobs, SourceJobs.REPLACE_BLADES)), "Tooltip_RenewableEnergy_NeedBlades",
            table.concat(names, ", "))
    end
end

-- Seal Cracked Module for each cracked module of a placed panel, listing what the seal takes, as a
-- trailer's Seal Cracked Panel. A module sealed as far as sealing goes still looks cracked, so it
-- keeps its option, greyed out saying to reglaze it, rather than vanishing from the menu. Reglaze
-- Module for each damaged module, cracked or not, since new glass brings any back to new.
local function addSealOptions(playerNum, menu, source)
    for slot, module in ipairs(Panel.placedModules(source) or {}) do
        local condition = Format.condition(module.type, module.condition)
        if ModuleRepair.crackLookOf(module.type, module.condition) then
            JobOptions.add(menu, playerNum, SourceJobs, SourceJobs.SEAL_MODULE, source, slot,
                getText("ContextMenu_RenewableEnergy_SealModule", slot, condition))
        end
        if ModuleRepair.reglazable(module.type, module.condition) then
            JobOptions.add(menu, playerNum, SourceJobs, SourceJobs.REGLAZE_MODULE, source, slot,
                getText("ContextMenu_RenewableEnergy_ReglazeModule", slot, condition))
        end
    end
end

-- Adds Connect to each bank in reach that `target` (a source of `kind`, or a treadmill not yet
-- wired) doesn't feed yet, by `job` of `Module`. Returns whether it added any.
local function addConnectOptions(playerNum, menu, target, kind, Module, job)
    local here = Squares.positionOf(target)
    local offered = false
    for _, bankPosition in ipairs(Sources.banksInReach(here.x, here.y, here.z, kind)) do
        local bank = PowerBank.findOn(getSquare(bankPosition.x, bankPosition.y, bankPosition.z))
        if bank and not Squares.samePosition(PowerBank.connectedBank(target), bankPosition) then
            JobOptions.add(menu, playerNum, Module, job, target, bank,
                getText("ContextMenu_RenewableEnergy_ConnectSource", BankMenu.bankLabel(bank), Format.away(here, bankPosition)))
            offered = true
        end
    end
    return offered
end

function SourceMenu.addSourceOptions(playerNum, context, source)
    local menu = JobOptions.addSubMenu(context, SourceMenu.nameOf(source))
    local here = Squares.positionOf(source)
    local connected = PowerBank.connectedBank(source)
    local treadmill = Treadmill.isWiredTile(source)
    if connected then
        menu:addOption(getText("ContextMenu_RenewableEnergy_WiredTo", bankNameAt(connected), Format.away(here, connected)))
        -- A treadmill's motor is unwired as it comes out of its bank.
        if treadmill then
            JobOptions.add(menu, playerNum, Treadmill, Treadmill.UNWIRE, source, nil, getText("ContextMenu_RenewableEnergy_DisconnectSource"))
        else
            JobOptions.add(menu, playerNum, SourceJobs, SourceJobs.DISCONNECT, source)
        end
        addSnowOption(playerNum, menu, source, sourceSummary(connected, here))
    end
    -- A wind charger's brake, set or let go, connected or not, and the life its blades have left.
    if Wind.isCharger(source) then
        JobOptions.add(menu, playerNum, SourceJobs, Wind.isBraked(source) and SourceJobs.RELEASE_BRAKE or SourceJobs.BRAKE,
            source)
        local blades = Wind.bladesOfObject(source)
        if blades and not Wind.isBroken(source) then
            menu:addOption(getText("ContextMenu_RenewableEnergy_BladesLeft", Wind.bladesLeftPct(blades, Wind.bladeHours(source))))
        end
    end
    addBladesOption(playerNum, menu, source)
    addSealOptions(playerNum, menu, source)

    local kind = Sources.kindOf(source)
    local offered = addConnectOptions(playerNum, menu, source, kind, SourceJobs, SourceJobs.CONNECT)
    if not (offered or connected) then
        local option = menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectToBank"))
        local placed = Sources.squareOk(source:getSquare(), kind)
        Needs.refuse(option, placed and "Tooltip_RenewableEnergy_NoBankInReach" or "Tooltip_RenewableEnergy_SourceIndoors")
    end
    -- A treadmill left wired without a bank (its bank gone or out of reach) can still be unwired.
    if treadmill and not connected then
        JobOptions.add(menu, playerNum, Treadmill, Treadmill.UNWIRE, source)
    end
    return menu
end

-- Run on Treadmill, greyed saying why while it can't go (Treadmill.runRefusal); for a treadmill
-- neither of whose tiles is wired, Connect to each bank in reach, which wires its motor.
local function addTreadmillJobs(playerNum, menu, treadmill, wired)
    local run = menu:addOption(getText("ContextMenu_RenewableEnergy_RunOnTreadmill"), playerNum, queueRun, treadmill)
    Needs.describe(run, "Tooltip_RenewableEnergy_RunOnTreadmill")
    Needs.refuse(run, Treadmill.runRefusal(treadmill))
    if not wired and not addConnectOptions(playerNum, menu, treadmill, "treadmill", Treadmill, Treadmill.CONNECT) then
        Needs.refuse(menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectToBank")), "Tooltip_RenewableEnergy_NoBankInReach")
    end
end

local sourceOrTreadmill = JobOptions.clicked(function(object)
    return Sources.kindOf(object) ~= nil or Treadmill.isTreadmill(object)
end)

-- A click may land on either tile of a treadmill, whose wired half is the source.
SourceMenu.onFill = JobOptions.onWorldMenu(sourceOrTreadmill, function(context, playerNum, character, object, worldobjects)
    local source = JobOptions.findClicked(worldobjects, Sources.kindOf)
    local treadmill = JobOptions.findClicked(worldobjects, Treadmill.isTreadmill)
    if treadmill and not source then
        source = Treadmill.wiredHalf(treadmill)
    end
    local wiredTreadmill = source ~= nil and Treadmill.isWiredTile(source)
    if source then
        local menu = SourceMenu.addSourceOptions(playerNum, context, source)
        if wiredTreadmill then
            addTreadmillJobs(playerNum, menu, source, true)
        end
    end
    if treadmill and not wiredTreadmill then
        addTreadmillJobs(playerNum, JobOptions.addSubMenu(context, SourceMenu.nameOf(treadmill)), treadmill, false)
    end
end)

return SourceMenu
