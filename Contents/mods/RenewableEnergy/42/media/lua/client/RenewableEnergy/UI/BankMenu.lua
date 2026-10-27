-- A battery bank's right-click menu. Each job's option is cf_commonlib's JobOptions', greyed out by
-- BankJobs, which the action and the authority ask, so the menu refuses exactly what they would.
-- Parts enter and leave a bank only through Wire In and Unwire (see
-- RenewableEnergy/PowerBank/WiredPartsGuard.lua).

local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local Action = require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local Format = require "RenewableEnergy/UI/Format"
local ObjectWindow = require "RenewableEnergy/UI/ObjectWindow"
local StatusWindow = require "RenewableEnergy/UI/StatusWindow"
local RenameBank = require "RenewableEnergy/UI/RenameBank"
local JobOptions = require "cf_commonlib/JobOptions"
local Needs = require "cf_commonlib/Needs"
local Tables = require "cf_commonlib/Tables"

local BankMenu = {}

--- A bank's name: the one a player gave it, else its tier's.
function BankMenu.bankLabel(bank)
    local summary = PowerBank.summaryOf(bank)
    return summary and Format.bankName(summary) or Format.tileName(bank)
end

-- The bank job `job` with each of `items`, queued in order: each is refused or not on its own.
local function queueEach(playerNum, job, bank, items)
    for _, item in ipairs(items) do
        Action.queue(playerNum, "bank", job, bank, item)
    end
end

local function queueConnectAll(playerNum, bank, sources)
    for _, source in ipairs(sources) do
        Action.queue(playerNum, "source", SourceJobs.CONNECT, source, bank)
    end
end

-- "Car Battery (72%)": a wired part, told apart from its twins by its condition.
local function partLabel(item)
    return Format.withShare(item:getDisplayName(), Format.conditionShare(item:getFullType(), item:getCondition()))
end

local function isPart(item)
    return PowerBank.partKind(item:getFullType()) ~= nil
end

-- The parts in the bank's container for which `matches(fullType)` holds, in its order.
local function wiredParts(bank, matches)
    return Tables.fromList(bank:getContainer():getItems(), function(item) return matches(item:getFullType()) end)
end

-- Rendering and queueing only; the jobs select the batch and derive its combined requirements.
local function addAllBatteries(playerNum, menu, job, bank, parts)
    local character = getSpecificPlayer(playerNum)
    local batteries, batch = BankJobs.batteryBatch(character, job, bank, parts)
    if not batteries then return end
    local all = menu:addOption(getText("ContextMenu_RenewableEnergy_AllBatteries", #batteries), playerNum, queueEach, job,
        bank, batteries)
    JobOptions.showVerdict(all, character, BankJobs, job, batch)
end

--- Wire In, as vanilla's mechanics menu offers parts to install: a submenu for each type of part
--- the character carries, listing every one they carry with its condition, each greyed out while
--- it can't go in with what that takes listed. All Batteries leads when they carry more than one
--- battery. Returns the submenu, or the unavailable option when the character carries no part.
function BankMenu.addWireInOptions(playerNum, menu, bank)
    local character = getSpecificPlayer(playerNum)
    local parts = Tables.fromList(character:getInventory():getAllEvalRecurse(isPart))
    if #parts == 0 then
        local option = menu:addOption(getText("ContextMenu_RenewableEnergy_WireIn"))
        Needs.refuse(option, "Tooltip_RenewableEnergy_NothingToWire")
        return option
    end
    local submenu = JobOptions.addSubMenu(menu, getText("ContextMenu_RenewableEnergy_WireIn"))
    addAllBatteries(playerNum, submenu, BankJobs.WIRE_IN, bank, parts)
    local byType = {}
    for _, item in ipairs(parts) do
        local fullType = item:getFullType()
        local itemsMenu = byType[fullType]
        if not itemsMenu then
            local script = getScriptManager():FindItem(fullType)
            local typeOption
            itemsMenu, typeOption = JobOptions.addSubMenu(submenu, getItemNameFromFullType(fullType))
            typeOption.iconTexture = script and script:getNormalTexture()
            byType[fullType] = itemsMenu
        end
        local option = JobOptions.add(itemsMenu, playerNum, BankJobs, BankJobs.WIRE_IN, bank, item, partLabel(item))
        if option then
            option.itemForTexture = item
        end
    end
    return submenu
end

--- Unwire: one option for each part in the bank, led by All Batteries when it holds more than
--- one, each greyed out while it can't come out with the tools that takes listed. What doesn't fit
--- in the character's inventory lands at their feet (Items.giveItems). Returns the
--- submenu, or nil for an empty bank.
function BankMenu.addUnwireOptions(playerNum, menu, bank)
    local parts = wiredParts(bank, PowerBank.partKind)
    if #parts == 0 then
        return nil
    end
    local submenu = JobOptions.addSubMenu(menu, getText("ContextMenu_RenewableEnergy_Unwire"))
    addAllBatteries(playerNum, submenu, BankJobs.UNWIRE, bank, parts)
    for _, item in ipairs(parts) do
        JobOptions.add(submenu, playerNum, BankJobs, BankJobs.UNWIRE, bank, item, partLabel(item))
    end
    return submenu
end

--- Repair: one option for each part in the bank that Electronics Scrap mends, listing what the
--- repair takes. Returns the submenu, or nil when the bank has none.
function BankMenu.addRepairOptions(playerNum, menu, bank)
    local parts = wiredParts(bank, PowerBank.isRepairable)
    if #parts == 0 then
        return nil
    end
    local submenu = JobOptions.addSubMenu(menu, getText("ContextMenu_RenewableEnergy_Repair"))
    for _, item in ipairs(parts) do
        JobOptions.add(submenu, playerNum, BankJobs, BankJobs.REPAIR, bank, item, partLabel(item))
    end
    return submenu
end

function BankMenu.addBankOptions(playerNum, context, bank)
    local character = getSpecificPlayer(playerNum)
    local menu = JobOptions.addSubMenu(context, BankMenu.bankLabel(bank))
    menu:addOption(getText("ContextMenu_RenewableEnergy_Status"), playerNum, ObjectWindow.queueOpen, bank, StatusWindow)

    local summary = PowerBank.summaryOf(bank)
    if not summary then
        -- The server has not sent this bank's summary yet; switching it needs to know its state.
        return menu
    end
    local switchKey, switchJob = BankJobs.switchOf(summary)
    JobOptions.add(menu, playerNum, BankJobs, switchJob, bank, nil, getText(switchKey))
    -- As vanilla's generator menu: Disconnect only while switched off.
    local connected = bank:isConnected()
    if not (connected and summary.on) then
        JobOptions.add(menu, playerNum, BankJobs, connected and BankJobs.DISCONNECT or BankJobs.CONNECT, bank)
    end

    local sources, refusal, count = SourceJobs.connectBatch(character, bank)
    local connect = menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectSourcesInReach", count), playerNum,
        queueConnectAll, bank, sources)
    local dark = Needs.tooDark(character, SourceJobs.needsLight(SourceJobs.CONNECT), Action.TOO_DARK)
    Needs.refuse(connect, (count > 0 and dark) or refusal)
    BankMenu.addWireInOptions(playerNum, menu, bank)
    BankMenu.addUnwireOptions(playerNum, menu, bank)
    BankMenu.addRepairOptions(playerNum, menu, bank)
    menu:addOption(getText("ContextMenu_RenewableEnergy_Rename"), playerNum, RenameBank.ask, bank)
    return menu
end

BankMenu.onFill = JobOptions.onWorldMenu(JobOptions.clicked(PowerBank.isBank), function(context, playerNum, character, bank)
    BankMenu.addBankOptions(playerNum, context, bank)
end)

return BankMenu
