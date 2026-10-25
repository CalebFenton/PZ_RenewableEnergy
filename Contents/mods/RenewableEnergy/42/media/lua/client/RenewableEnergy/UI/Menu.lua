-- Right-click menus for battery banks, their sources, treadmills and garden lights. Options are
-- greyed out by the same refusal functions the job's action and the authority ask, so the menu
-- refuses exactly what they would. Parts enter and leave a bank only through Wire In and Unwire
-- (see RenewableEnergy/PowerBank/WiredPartsGuard.lua).

require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISTextBox"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Wind"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/PowerBank/Treadmill"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/TimedActions/RenewableEnergyTreadmillAction"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/ObjectWindow"
require "RenewableEnergy/UI/StatusWindow"
local Needs = require "cf_commonlib/Needs"
local Squares = require "cf_commonlib/Squares"

RenewableEnergy = RenewableEnergy or {}
local Menu = {}
RenewableEnergy.Menu = Menu

local Action = RenewableEnergyAction
local PowerBank, Sources, Treadmill = RenewableEnergy.PowerBank, RenewableEnergy.Sources, RenewableEnergy.Treadmill
local Specs, Wind = RenewableEnergy.Specs, RenewableEnergy.Wind
local SolarGardenLight = RenewableEnergy.SolarGardenLight
local Format = RenewableEnergy.Format
local ObjectWindow, StatusWindow = RenewableEnergy.ObjectWindow, RenewableEnergy.StatusWindow

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

-- "Too dark" for a job that needs light to see by (RenewableEnergyAction.needsLight) while the
-- character stands in the dark, else `blocker`.
local function lightOr(character, job, blocker)
    return Needs.tooDark(character, Action.needsLight(job), Action.TOO_DARK) or blocker
end

local function queueAt(playerNum, square, job, object, bank, item, bankName, slot)
    local character = Squares.walkTo(playerNum, square)
    if character then
        ISTimedActionQueue.add(Action:new(character, job, object, bank, nil, item, bankName, nil, slot))
    end
end

local function queueSource(playerNum, job, source, bank)
    queueAt(playerNum, source:getSquare(), job, source, bank)
end

--- Walks a local player over to `bank` and queues the job `job` there; `bankName` is Rename's new
--- name.
function Menu.queueBank(playerNum, job, bank, bankName)
    queueAt(playerNum, bank:getSquare(), job, nil, bank, nil, bankName)
end

local function queuePart(playerNum, job, bank, item)
    queueAt(playerNum, bank:getSquare(), job, nil, bank, item)
end

-- One job per item, queued in order: each is refused or not on its own.
local function queueParts(playerNum, job, bank, items)
    for _, item in ipairs(items) do
        queuePart(playerNum, job, bank, item)
    end
end

local function queueConnectAll(playerNum, bank, sources)
    for _, source in ipairs(sources) do
        queueSource(playerNum, Action.CONNECT_SOURCE, source, bank)
    end
end

local function queueClearSnow(playerNum, source)
    local character = Squares.walkTo(playerNum, source:getSquare())
    if not character then
        return
    end
    local tool = ISWorldObjectContextMenu.equip(character, character:getPrimaryHandItem(), Action.isSnowTool, true)
    ISTimedActionQueue.add(Action:new(character, Action.CLEAR_SNOW, source, nil, nil, tool))
end

local function queueBlades(playerNum, source, blades)
    queueAt(playerNum, source:getSquare(), Action.REPLACE_BLADES, source, nil, blades)
end

local function queueSeal(playerNum, source, slot)
    queueAt(playerNum, source:getSquare(), Action.SEAL_MODULE, source, nil, nil, nil, slot)
end

local function queueBulb(playerNum, job, light, bulb)
    local character = Squares.walkTo(playerNum, light:getSquare())
    if not character then
        return
    end
    if bulb then
        ISInventoryPaneContextMenu.transferIfNeeded(character, bulb)
    end
    ISTimedActionQueue.add(Action:new(character, job, light, nil, nil, bulb))
end

local function queueRun(playerNum, treadmill)
    local character = Squares.walkTo(playerNum, treadmill:getSquare())
    if character then
        ISTimedActionQueue.add(RenewableEnergyTreadmillAction:new(character, treadmill))
    end
end

local function onNameEntered(target, button, playerNum, bank)
    if button.internal == "OK" then
        Menu.queueBank(playerNum, Action.RENAME, bank, button.parent.entry:getText())
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
    local parts = {}
    local items = bank:getContainer():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if matches(item:getFullType()) then
            table.insert(parts, item)
        end
    end
    return parts
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
        local all = submenu:addOption(getText("ContextMenu_RenewableEnergy_AllBatteries", #batteries), playerNum,
            queueParts, Action.WIRE_IN, bank, batteries)
        Needs.show(all, PowerBank.wiringNeeds(character, allWiring(batteries)),
            lightOr(character, Action.WIRE_IN, PowerBank.wiringBlocker(bank, batteries[1])))
    end
    for _, group in ipairs(groups) do
        local script = getScriptManager():FindItem(group.fullType)
        local itemsMenu, typeOption = Needs.addSubMenu(submenu, getItemNameFromFullType(group.fullType))
        typeOption.iconTexture = script and script:getNormalTexture()
        local needs = PowerBank.wiringNeeds(character, PowerBank.wiringFor(group.fullType))
        for _, item in ipairs(group.items) do
            local option = itemsMenu:addOption(partLabel(item), playerNum, queuePart, Action.WIRE_IN, bank, item)
            option.itemForTexture = item
            Needs.show(option, needs, lightOr(character, Action.WIRE_IN, PowerBank.wiringBlocker(bank, item)))
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
    local character = getSpecificPlayer(playerNum)
    local submenu = Needs.addSubMenu(menu, getText("ContextMenu_RenewableEnergy_Unwire"))
    local batteries = wiredParts(bank, isBattery)
    if #batteries > 1 then
        local all = submenu:addOption(getText("ContextMenu_RenewableEnergy_AllBatteries", #batteries), playerNum,
            queueParts, Action.UNWIRE, bank, batteries)
        Needs.show(all, PowerBank.unwiringNeeds(character, allWiring(batteries)), lightOr(character, Action.UNWIRE))
    end
    for _, item in ipairs(parts) do
        local option = submenu:addOption(partLabel(item), playerNum, queuePart, Action.UNWIRE, bank, item)
        Needs.show(option, PowerBank.unwiringNeeds(character, PowerBank.wiringFor(item:getFullType())),
            lightOr(character, Action.UNWIRE, PowerBank.unwiringBlocker(bank, item)))
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
    local character = getSpecificPlayer(playerNum)
    local needs = PowerBank.repairNeeds(character)
    local submenu = Needs.addSubMenu(menu, getText("ContextMenu_RenewableEnergy_Repair"))
    for _, item in ipairs(parts) do
        local option = submenu:addOption(partLabel(item), playerNum, queuePart, Action.REPAIR_PART, bank, item)
        Needs.show(option, needs, lightOr(character, Action.REPAIR_PART, PowerBank.repairBlocker(item)))
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
    return on and "ContextMenu_Turn_Off" or "ContextMenu_Turn_On", on and Action.TURN_OFF or Action.TURN_ON,
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
    local switchKey, switchJob, refusal = Menu.switchOf(summary)
    Needs.refuse(menu:addOption(getText(switchKey), playerNum, Menu.queueBank, switchJob, bank), refusal)
    local on = summary.on == true
    -- As vanilla's generator menu: Disconnect only while switched off.
    local connected = bank:isConnected()
    if not (connected and on) then
        local plug = menu:addOption(getText(connected and "ContextMenu_RenewableEnergy_DisconnectBank" or "ContextMenu_RenewableEnergy_ConnectBank"),
            playerNum, Menu.queueBank, connected and Action.DISCONNECT_BANK or Action.CONNECT_BANK, bank)
        Needs.refuse(plug, lightOr(character, Action.CONNECT_BANK,
            PowerBank.connectRefusal(character, bank, summary, not connected)))
    end

    -- Sources go only on a connected bank. The generator's flag, which Connect Bank above reads
    -- too, rather than the summary, so the two options never disagree (Sources.bankRefusal).
    local sources = Sources.sourcesInReach(PowerBank.positionOf(bank))
    local connect = menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectSourcesInReach", #sources), playerNum,
        queueConnectAll, bank, sources)
    Needs.refuse(connect, #sources == 0 and "Tooltip_RenewableEnergy_NoSourcesInReach"
        or lightOr(character, Action.CONNECT_SOURCE, Sources.bankRefusal(connected) or slotsRefusal(sources, summary.freeSlots)))
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

local function addSnowOption(playerNum, menu, source, entry)
    if not (entry and entry.snowy and Sources.sweepable(Sources.kindOf(source))) then
        return
    end
    local option = menu:addOption(getText("ContextMenu_RenewableEnergy_ClearSnow"), playerNum, queueClearSnow, source)
    local hasTool = getSpecificPlayer(playerNum):getInventory():containsEvalRecurse(Action.isSnowTool)
    Needs.refuse(option, not hasTool and "Tooltip_RenewableEnergy_NeedSnowTool")
end

-- A wind charger's brake, set or let go, connected or not.
local function addBrakeOption(playerNum, menu, source)
    if not Wind.isCharger(source) then
        return
    end
    local braked = Wind.isBraked(source)
    menu:addOption(getText(braked and "ContextMenu_RenewableEnergy_ReleaseBrake" or "ContextMenu_RenewableEnergy_Brake"),
        playerNum, queueSource, braked and Action.RELEASE_BRAKE or Action.BRAKE, source)
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
    local refusal = Wind.bladesRefusal(source, blades)
    local option = menu:addOption(getText("ContextMenu_RenewableEnergy_ReplaceBlades"), playerNum, queueBlades, source, blades)
    local dark = lightOr(getSpecificPlayer(playerNum), Action.REPLACE_BLADES)
    if dark then
        Needs.refuse(option, dark)
    elseif refusal then
        Needs.refuse(option, "Tooltip_RenewableEnergy_NeedBlades", table.concat(names, ", "))
    end
end

-- Seal Cracked Module for each cracked module of a placed panel, listing what the seal takes and
-- greyed out when the character can't do it, as a trailer's Seal Cracked Panel. A module sealed
-- as far as sealing goes still looks cracked, so it keeps its option, greyed out saying to reglaze
-- it, rather than vanishing from the menu.
local function addSealOptions(playerNum, menu, source)
    local Recipes = RenewableEnergy.Recipes
    local cracked = {}
    for slot, module in ipairs(Recipes.panelModules(source) or {}) do
        if RenewableEnergy.crackLookOf(module.type, module.condition) then
            table.insert(cracked, { slot = slot, module = module })
        end
    end
    if #cracked == 0 then
        return
    end
    local character = getSpecificPlayer(playerNum)
    local needs = Recipes.sealInPlaceNeeds(character)
    local blocker = lightOr(character, Action.SEAL_MODULE)
    for _, entry in ipairs(cracked) do
        local option = menu:addOption(getText("ContextMenu_RenewableEnergy_SealModule", entry.slot, math.floor(entry.module.condition)),
            playerNum, queueSeal, source, entry.slot)
        if Recipes.canSealRecord(entry.module) then
            Needs.show(option, needs, blocker)
        else
            Needs.refuse(option, "Tooltip_RenewableEnergy_ModuleSealedFully")
        end
    end
end

function Menu.addSourceOptions(playerNum, context, source)
    local menu = Needs.addSubMenu(context, Menu.nameOf(source))
    local character = getSpecificPlayer(playerNum)

    local here = PowerBank.positionOf(source)
    local connected = PowerBank.connectedBank(source)
    if connected then
        menu:addOption(getText("ContextMenu_RenewableEnergy_WiredTo", bankNameAt(connected), Format.away(here, connected)))
        local disconnect = menu:addOption(getText("ContextMenu_RenewableEnergy_DisconnectSource"), playerNum, queueSource,
            Action.DISCONNECT_SOURCE, source)
        Needs.refuse(disconnect, lightOr(character, Action.DISCONNECT_SOURCE))
        addSnowOption(playerNum, menu, source, sourceSummary(connected, here))
    end
    addBrakeOption(playerNum, menu, source)
    addBladesOption(playerNum, menu, source)
    addSealOptions(playerNum, menu, source)

    local offered = false
    local kind = Sources.kindOf(source)
    for _, bankPosition in ipairs(Sources.banksInReach(here.x, here.y, here.z, kind)) do
        local bank = PowerBank.findOn(getSquare(bankPosition.x, bankPosition.y, bankPosition.z))
        if bank and not Sources.connectRefusal(source, bankPosition) then
            local option = menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectSource", Menu.bankLabel(bank),
                Format.away(here, bankPosition)), playerNum, queueSource, Action.CONNECT_SOURCE, source, bank)
            local summary = PowerBank.summaryOf(bank)
            Needs.refuse(option, lightOr(character, Action.CONNECT_SOURCE, Sources.bankRefusal(bank:isConnected())
                or summary and Sources.slotRefusal(kind, summary.freeSlots)))
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

-- Run on Treadmill, greyed saying why while it can't go (Treadmill.runRefusal).
local function addRunOption(playerNum, menu, treadmill)
    local run = menu:addOption(getText("ContextMenu_RenewableEnergy_RunOnTreadmill"), playerNum, queueRun, treadmill)
    Needs.refuse(run, Treadmill.runRefusal(treadmill))
end

-- Run on Treadmill, then Unwire for a wired treadmill or Wire the Motor for one neither of whose
-- tiles is wired yet.
local function addTreadmillJobs(playerNum, menu, treadmill, wired)
    addRunOption(playerNum, menu, treadmill)
    local character = getSpecificPlayer(playerNum)
    local key, job, needs = "ContextMenu_RenewableEnergy_WireTreadmill", Action.WIRE_TREADMILL, Treadmill.wiringNeeds
    if wired then
        key, job, needs = "ContextMenu_RenewableEnergy_UnwireTreadmill", Action.UNWIRE_TREADMILL, Treadmill.unwiringNeeds
    end
    local option = menu:addOption(getText(key), playerNum, queueSource, job, treadmill)
    Needs.show(option, needs(character), lightOr(character, job))
end

--- Remove Light Bulb for a light that has one, else Add Light Bulb with one option for each type
--- of bulb the character carries, shown in its colour as vanilla shows a lamp's. Returns the
--- light's submenu.
function Menu.addGardenLightOptions(playerNum, context, light)
    local menu = Needs.addSubMenu(context, Menu.nameOf(light))
    if SolarGardenLight.getBulb(light) then
        menu:addOption(getText("ContextMenu_RemoveLightbulb"), playerNum, queueBulb, Action.REMOVE_BULB, light)
        return menu
    end
    local bulbTypes = carriedByType(getSpecificPlayer(playerNum), SolarGardenLight.isBulb)
    if #bulbTypes == 0 then
        Needs.refuse(menu:addOption(getText("ContextMenu_AddLightbulb")), "ContextMenu_AddLightbulb_RequiresBulb")
        return menu
    end
    local submenu = Needs.addSubMenu(menu, getText("ContextMenu_AddLightbulb"))
    for _, group in ipairs(bulbTypes) do
        local bulb = group.items[1]
        local option = submenu:addOption(bulb:getDisplayName(), playerNum, queueBulb, Action.ADD_BULB, light, bulb)
        option.iconTexture = bulb:getTex()
        option.color = { r = bulb:getColorRed(), g = bulb:getColorGreen(), b = bulb:getColorBlue() }
    end
    return menu
end

function Menu.onFill(playerNum, context, worldobjects, test)
    local bank = Needs.findClicked(worldobjects, PowerBank.isBank)
    local source = Needs.findClicked(worldobjects, Sources.kindOf)
    local light = Needs.findClicked(worldobjects, SolarGardenLight.isLight)
    local treadmill = Needs.findClicked(worldobjects, Treadmill.isTreadmill)
    if treadmill and not source then
        source = Treadmill.wiredHalf(treadmill)
    end
    if not (bank or source or light or treadmill) then
        return
    end
    if test then
        return ISWorldObjectContextMenu.setTest()
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
end

Events.OnFillWorldObjectContextMenu.Add(Menu.onFill)

return Menu
