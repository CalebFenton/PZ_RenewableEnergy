-- Right-click menus for battery banks, their sources, treadmills and garden lights. Each job's
-- option is cf_commonlib's JobOptions', greyed out by the job module the action and the authority
-- ask, so the menu refuses exactly what they would. Parts enter and leave a bank only through Wire
-- In and Unwire (see RenewableEnergy/PowerBank/WiredPartsGuard.lua).

require "ISUI/ISTextBox"
local RenewableEnergy = require "RenewableEnergy/Utilities"
local Specs = require "RenewableEnergy/Specs"
local Wind = require "RenewableEnergy/Wind"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLight"
local Action = require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local TreadmillAction = require "RenewableEnergy/TimedActions/RenewableEnergyTreadmillAction"
local Format = require "RenewableEnergy/UI/Format"
local ObjectWindow = require "RenewableEnergy/UI/ObjectWindow"
local StatusWindow = require "RenewableEnergy/UI/StatusWindow"
local Recipes = require "RenewableEnergy/Recipes"
local Items = require "cf_commonlib/Items"
local JobOptions = require "cf_commonlib/JobOptions"
local Materials = require "cf_commonlib/Materials"
local Needs = require "cf_commonlib/Needs"
local Squares = require "cf_commonlib/Squares"
local Tables = require "cf_commonlib/Tables"

local Menu = {}
RenewableEnergy.Menu = Menu

--- The name of a placed tile: the item it is (CustomItem), which picking it up gives back, else
--- its moveable's name (CustomName, Moveables.json), as a wind charger has. A vanilla treadmill's
--- moveable name is "Hamster Wheel", so it gets its own.
function Menu.nameOf(isoObject)
    if Treadmill.isTreadmill(isoObject) then
        return getText("IGUI_RenewableEnergy_Treadmill")
    end
    local properties = isoObject:getProperties()
    local item = properties:get("CustomItem")
    if item then
        return getItemNameFromFullType(item)
    end
    return Translator.getMoveableDisplayName(properties:get("CustomName"))
end

--- A bank's name: the one a player gave it, else its tier's.
function Menu.bankLabel(bank)
    local summary = PowerBank.summaryOf(bank)
    return summary and Format.bankName(summary) or Menu.nameOf(bank)
end

-- "Too dark" while the character stands in the dark, for an option that queues several of a job
-- that needs light.
local function tooDark(character, jobs, job)
    return Needs.tooDark(character, jobs.needsLight(job), Action.TOO_DARK)
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

local function queueRun(playerNum, treadmill)
    local character = Squares.walkTo(playerNum, treadmill:getSquare())
    if character then
        ISTimedActionQueue.add(TreadmillAction:new(character, treadmill))
    end
end

local function onNameEntered(target, button, playerNum, bank)
    if button.internal == "OK" then
        Action.queue(playerNum, "bank", BankJobs.RENAME, bank, button.parent.entry:getText())
    end
end

--- Asks a local player for a new name for `bank` and queues the renaming. An empty name gives
--- the bank back its tier's name.
function Menu.askName(playerNum, bank)
    local summary = PowerBank.summaryOf(bank)
    local modal = ISTextBox:new(0, 0, 280, 180, getText("IGUI_RenewableEnergy_NameThisBank"), summary and summary.name or "",
        nil, onNameEntered, playerNum, playerNum, bank)
    modal:initialise()
    modal.entry:setMaxTextLength(PowerBank.NAME_LENGTH)
    modal:addToUIManager()
    if JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, modal)
    end
    return modal
end

local function conditionOf(item)
    return item:getCondition() / item:getConditionMax()
end

-- "Car Battery (72%)": a wired part, told apart from its twins by its condition.
local function partLabel(item)
    return getText("ContextMenu_RenewableEnergy_PartCondition", item:getDisplayName(), Format.percent(conditionOf(item)))
end

local function isPart(item)
    return PowerBank.partKind(item:getFullType()) ~= nil
end

-- The parts in the bank's container for which `matches(fullType)` holds, in its order.
local function wiredParts(bank, matches)
    return Tables.fromList(bank:getContainer():getItems(), function(item) return matches(item:getFullType()) end)
end

-- Every item the character carries for which `matches(item)` holds, bags included, grouped by
-- type: { { fullType, items }, ... }, types and items in inventory order.
local function carriedByType(character, matches)
    local groups, byType = {}, {}
    local items = character:getInventory():getAllEvalRecurse(matches)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local fullType = item:getFullType()
        if not byType[fullType] then
            byType[fullType] = { fullType = fullType, items = {} }
            table.insert(groups, byType[fullType])
        end
        table.insert(byType[fullType].items, item)
    end
    return groups
end

local function isBattery(fullType)
    return PowerBank.partKind(fullType) == "battery"
end

-- The carried batteries All Batteries wires in: as many as the bank has room for, best condition
-- first; all of them when it has none, for the option to be refused.
local function batteriesToWire(groups, bank)
    local batteries = {}
    for _, group in ipairs(groups) do
        if isBattery(group.fullType) then
            for _, item in ipairs(group.items) do
                table.insert(batteries, item)
            end
        end
    end
    table.sort(batteries, function(a, b) return conditionOf(a) > conditionOf(b) end)
    local free = PowerBank.freePartSlots(bank, "battery")
    while free > 0 and #batteries > free do
        table.remove(batteries)
    end
    return batteries
end

-- What wiring `items` in one after another takes: the wire and scrap of them all, the highest
-- skill, and every tool any of them takes.
local function allWiring(items)
    local wiring, seen = { skill = 0, wire = 0, scrap = 0, tools = {} }, {}
    for _, item in ipairs(items) do
        local each = PowerBank.wiringFor(item:getFullType())
        wiring.wire, wiring.scrap = wiring.wire + each.wire, wiring.scrap + each.scrap
        wiring.skill = math.max(wiring.skill, each.skill or 0)
        for _, tool in ipairs(each.tools) do
            if not seen[tool] then
                seen[tool] = true
                table.insert(wiring.tools, tool)
            end
        end
    end
    return wiring
end

-- All Batteries: `job` with each of `batteries`, listing what they take together.
local function addAllBatteries(playerNum, menu, job, bank, batteries, materials, blocker)
    local character = getSpecificPlayer(playerNum)
    local all = menu:addOption(getText("ContextMenu_RenewableEnergy_AllBatteries", #batteries), playerNum, queueEach, job,
        bank, batteries)
    Needs.show(all, Materials.needs(character, materials), tooDark(character, BankJobs, job) or blocker)
end

--- Wire In, as vanilla's mechanics menu offers parts to install: a submenu for each type of part
--- the character carries, listing every one they carry with its condition, each greyed out while
--- it can't go in with what that takes listed. All Batteries leads when they carry more than one
--- battery. Returns the submenu, or the unavailable option when the character carries no part.
function Menu.addWireInOptions(playerNum, menu, bank)
    local character = getSpecificPlayer(playerNum)
    local groups = carriedByType(character, isPart)
    if #groups == 0 then
        local option = menu:addOption(getText("ContextMenu_RenewableEnergy_WireIn"))
        Needs.refuse(option, "Tooltip_RenewableEnergy_NothingToWire")
        return option
    end
    local submenu = Needs.addSubMenu(menu, getText("ContextMenu_RenewableEnergy_WireIn"))
    local batteries = batteriesToWire(groups, bank)
    if #batteries > 1 then
        addAllBatteries(playerNum, submenu, BankJobs.WIRE_IN, bank, batteries, PowerBank.wiringMaterials(allWiring(batteries)),
            BankJobs.blocker(character, BankJobs.WIRE_IN, bank, batteries[1]))
    end
    for _, group in ipairs(groups) do
        local script = getScriptManager():FindItem(group.fullType)
        local itemsMenu, typeOption = Needs.addSubMenu(submenu, getItemNameFromFullType(group.fullType))
        typeOption.iconTexture = script and script:getNormalTexture()
        for _, item in ipairs(group.items) do
            local option = JobOptions.add(itemsMenu, playerNum, Action, "bank", BankJobs.WIRE_IN, bank, item, partLabel(item))
            if option then
                option.itemForTexture = item
            end
        end
    end
    return submenu
end

--- Unwire: one option for each part in the bank, led by All Batteries when it holds more than
--- one, each greyed out while it can't come out with the tools that takes listed. What doesn't fit
--- in the character's inventory lands at their feet (Items.giveItems). Returns the
--- submenu, or nil for an empty bank.
function Menu.addUnwireOptions(playerNum, menu, bank)
    local parts = wiredParts(bank, PowerBank.partKind)
    if #parts == 0 then
        return nil
    end
    local submenu = Needs.addSubMenu(menu, getText("ContextMenu_RenewableEnergy_Unwire"))
    local batteries = wiredParts(bank, isBattery)
    if #batteries > 1 then
        addAllBatteries(playerNum, submenu, BankJobs.UNWIRE, bank, batteries, allWiring(batteries).tools)
    end
    for _, item in ipairs(parts) do
        JobOptions.add(submenu, playerNum, Action, "bank", BankJobs.UNWIRE, bank, item, partLabel(item))
    end
    return submenu
end

--- Repair: one option for each part in the bank that Electronics Scrap mends, listing what the
--- repair takes. Returns the submenu, or nil when the bank has none.
function Menu.addRepairOptions(playerNum, menu, bank)
    local parts = wiredParts(bank, PowerBank.isRepairable)
    if #parts == 0 then
        return nil
    end
    local submenu = Needs.addSubMenu(menu, getText("ContextMenu_RenewableEnergy_Repair"))
    for _, item in ipairs(parts) do
        JobOptions.add(submenu, playerNum, Action, "bank", BankJobs.REPAIR, bank, item, partLabel(item))
    end
    return submenu
end

-- Why none of `sources` fits in `freeSlots` input slots, or nil when one does.
local function slotsRefusal(sources, freeSlots)
    local refusal
    for _, source in ipairs(sources) do
        refusal = Sources.slotRefusal(Sources.kindOf(source), freeSlots)
        if not refusal then
            return nil
        end
    end
    return refusal
end

--- Turn On or Turn Off for a bank in `summary`'s state: its label key, its job, and why it is
--- refused (nil when it isn't). The menu and the status window both offer it.
function Menu.switchOf(summary)
    local on = summary.on == true
    return on and "ContextMenu_Turn_Off" or "ContextMenu_Turn_On", on and BankJobs.TURN_OFF or BankJobs.TURN_ON,
        PowerBank.switchRefusal(summary, not on)
end

function Menu.addBankOptions(playerNum, context, bank)
    local character = getSpecificPlayer(playerNum)
    local menu = Needs.addSubMenu(context, Menu.bankLabel(bank))
    menu:addOption(getText("ContextMenu_RenewableEnergy_Status"), playerNum, ObjectWindow.queueOpen, bank, StatusWindow)

    local summary = PowerBank.summaryOf(bank)
    if not summary then
        -- The server has not sent this bank's summary yet; switching it needs to know its state.
        return menu
    end
    local switchKey, switchJob = Menu.switchOf(summary)
    JobOptions.add(menu, playerNum, Action, "bank", switchJob, bank, nil, getText(switchKey))
    -- As vanilla's generator menu: Disconnect only while switched off.
    local connected = bank:isConnected()
    if not (connected and summary.on) then
        JobOptions.add(menu, playerNum, Action, "bank", connected and BankJobs.DISCONNECT or BankJobs.CONNECT, bank)
    end

    -- Sources go only on a connected bank. The generator's flag, which Connect Bank above reads
    -- too, rather than the summary, so the two options never disagree (Sources.bankRefusal).
    local sources = Sources.sourcesInReach(PowerBank.positionOf(bank))
    local connect = menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectSourcesInReach", #sources), playerNum,
        queueConnectAll, bank, sources)
    Needs.refuse(connect, #sources == 0 and "Tooltip_RenewableEnergy_NoSourcesInReach"
        or tooDark(character, SourceJobs, SourceJobs.CONNECT) or Sources.bankRefusal(connected)
        or slotsRefusal(sources, summary.freeSlots))
    Menu.addWireInOptions(playerNum, menu, bank)
    Menu.addUnwireOptions(playerNum, menu, bank)
    Menu.addRepairOptions(playerNum, menu, bank)
    menu:addOption(getText("ContextMenu_RenewableEnergy_Rename"), playerNum, Menu.askName, bank)
    return menu
end

-- The entry for the source at `here` in its bank's summary.
local function sourceSummary(bankPosition, here)
    local summary = PowerBank.summaryAt(bankPosition.x, bankPosition.y, bankPosition.z)
    for _, entry in ipairs(summary and summary.sources or {}) do
        if PowerBank.samePosition(entry, here) then
            return entry
        end
    end
end

local function bankNameAt(at)
    local summary = PowerBank.summaryAt(at.x, at.y, at.z)
    return summary and Format.bankName(summary) or getText("IGUI_RenewableEnergy_StatusTitle")
end

-- Clear Snow on a source whose summary entry says it is snowy, with the broom or snow shovel the
-- character would use.
local function addSnowOption(playerNum, menu, source, entry)
    if entry and entry.snowy and Sources.sweepable(Sources.kindOf(source)) then
        JobOptions.add(menu, playerNum, Action, "source", SourceJobs.CLEAR_SNOW, source,
            Items.toolFor(getSpecificPlayer(playerNum), SourceJobs.isSnowTool))
    end
end

-- Replace Blades, for a wind charger a storm broke: blades of its own material if carried, else the
-- first other blades it takes that are carried, or the option greyed, naming all it takes.
local function addBladesOption(playerNum, menu, source)
    local own = Wind.bladesOfObject(source)
    if not (own and Wind.isBroken(source)) then
        return
    end
    local inventory = getSpecificPlayer(playerNum):getInventory()
    local blades = inventory:getFirstTypeRecurse(Specs.wind.blades[own].item)
    local names = {}
    for _, material in ipairs(Specs.wind.turbines[Sources.kindOf(source)].blades) do
        local item = Specs.wind.blades[material].item
        blades = blades or inventory:getFirstTypeRecurse(item)
        table.insert(names, getItemNameFromFullType(item))
    end
    if blades then
        JobOptions.add(menu, playerNum, Action, "source", SourceJobs.REPLACE_BLADES, source, blades)
    else
        Needs.refuse(menu:addOption(getText(Action.labelKey(SourceJobs.REPLACE_BLADES))), "Tooltip_RenewableEnergy_NeedBlades",
            table.concat(names, ", "))
    end
end

-- Seal Cracked Module for each cracked module of a placed panel, listing what the seal takes, as a
-- trailer's Seal Cracked Panel. A module sealed as far as sealing goes still looks cracked, so it
-- keeps its option, greyed out saying to reglaze it, rather than vanishing from the menu.
local function addSealOptions(playerNum, menu, source)
    for slot, module in ipairs(Recipes.panelModules(source) or {}) do
        if RenewableEnergy.crackLookOf(module.type, module.condition) then
            JobOptions.add(menu, playerNum, Action, "source", SourceJobs.SEAL_MODULE, source, slot,
                getText("ContextMenu_RenewableEnergy_SealModule", slot, math.floor(module.condition)))
        end
    end
end

function Menu.addSourceOptions(playerNum, context, source)
    local menu = Needs.addSubMenu(context, Menu.nameOf(source))
    local here = PowerBank.positionOf(source)
    local connected = PowerBank.connectedBank(source)
    if connected then
        menu:addOption(getText("ContextMenu_RenewableEnergy_WiredTo", bankNameAt(connected), Format.away(here, connected)))
        JobOptions.add(menu, playerNum, Action, "source", SourceJobs.DISCONNECT, source)
        addSnowOption(playerNum, menu, source, sourceSummary(connected, here))
    end
    -- A wind charger's brake, set or let go, connected or not.
    if Wind.isCharger(source) then
        JobOptions.add(menu, playerNum, Action, "source", Wind.isBraked(source) and SourceJobs.RELEASE_BRAKE or SourceJobs.BRAKE,
            source)
    end
    addBladesOption(playerNum, menu, source)
    addSealOptions(playerNum, menu, source)

    local offered = false
    local kind = Sources.kindOf(source)
    for _, bankPosition in ipairs(Sources.banksInReach(here.x, here.y, here.z, kind)) do
        local bank = PowerBank.findOn(getSquare(bankPosition.x, bankPosition.y, bankPosition.z))
        if bank and not Sources.connectRefusal(source, bankPosition) then
            JobOptions.add(menu, playerNum, Action, "source", SourceJobs.CONNECT, source, bank,
                getText("ContextMenu_RenewableEnergy_ConnectSource", Menu.bankLabel(bank), Format.away(here, bankPosition)))
            offered = true
        end
    end
    if not (offered or connected) then
        local option = menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectToBank"))
        local placed = Sources.squareOk(source:getSquare(), kind)
        Needs.refuse(option, placed and "Tooltip_RenewableEnergy_NoBankInReach" or "Tooltip_RenewableEnergy_SourceIndoors")
    end
    return menu
end

-- Run on Treadmill, greyed saying why while it can't go (Treadmill.runRefusal), then Unwire for a
-- wired treadmill or Wire the Motor for one neither of whose tiles is wired yet.
local function addTreadmillJobs(playerNum, menu, treadmill, wired)
    local run = menu:addOption(getText("ContextMenu_RenewableEnergy_RunOnTreadmill"), playerNum, queueRun, treadmill)
    Needs.refuse(run, Treadmill.runRefusal(treadmill))
    JobOptions.add(menu, playerNum, Action, "treadmill", wired and Treadmill.UNWIRE or Treadmill.WIRE, treadmill)
end

--- Remove Light Bulb for a light that has one, else Add Light Bulb with one option for each type
--- of bulb the character carries, shown in its colour as vanilla shows a lamp's. Returns the
--- light's submenu.
function Menu.addGardenLightOptions(playerNum, context, light)
    local menu = Needs.addSubMenu(context, Menu.nameOf(light))
    if SolarGardenLight.getBulb(light) then
        JobOptions.add(menu, playerNum, Action, "light", SolarGardenLight.REMOVE_BULB, light, nil,
            getText("ContextMenu_RemoveLightbulb"))
        return menu
    end
    local bulbTypes = carriedByType(getSpecificPlayer(playerNum), SolarGardenLight.isBulb)
    if #bulbTypes == 0 then
        JobOptions.add(menu, playerNum, Action, "light", SolarGardenLight.ADD_BULB, light, nil, getText("ContextMenu_AddLightbulb"))
        return menu
    end
    local submenu = Needs.addSubMenu(menu, getText("ContextMenu_AddLightbulb"))
    for _, group in ipairs(bulbTypes) do
        local bulb = group.items[1]
        local option = JobOptions.add(submenu, playerNum, Action, "light", SolarGardenLight.ADD_BULB, light, bulb,
            bulb:getDisplayName())
        option.iconTexture = bulb:getTex()
        option.color = { r = bulb:getColorRed(), g = bulb:getColorGreen(), b = bulb:getColorBlue() }
    end
    return menu
end

local function isPowerObject(object)
    return PowerBank.isBank(object) or Sources.kindOf(object) ~= nil or SolarGardenLight.isLight(object)
        or Treadmill.isTreadmill(object)
end

-- A click may land on several of them at once, and on either tile of a treadmill, whose wired half
-- is the source.
Menu.onFill = JobOptions.onWorldMenu(isPowerObject, function(context, playerNum, character, object, worldobjects)
    local bank = Needs.findClicked(worldobjects, PowerBank.isBank)
    local source = Needs.findClicked(worldobjects, Sources.kindOf)
    local light = Needs.findClicked(worldobjects, SolarGardenLight.isLight)
    local treadmill = Needs.findClicked(worldobjects, Treadmill.isTreadmill)
    if treadmill and not source then
        source = Treadmill.wiredHalf(treadmill)
    end
    if bank then
        Menu.addBankOptions(playerNum, context, bank)
    end
    local wiredTreadmill = source ~= nil and Treadmill.isWiredTile(source)
    if source then
        local menu = Menu.addSourceOptions(playerNum, context, source)
        if wiredTreadmill then
            addTreadmillJobs(playerNum, menu, source, true)
        end
    end
    if treadmill and not wiredTreadmill then
        addTreadmillJobs(playerNum, Needs.addSubMenu(context, Menu.nameOf(treadmill)), treadmill, false)
    end
    if light then
        Menu.addGardenLightOptions(playerNum, context, light)
    end
end)

return Menu
