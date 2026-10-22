-- Right-click menus for battery banks, their sources, garden lights and vehicles. Options are
-- greyed out by the same refusal functions the job's action and the authority ask, so the menu
-- refuses exactly what they would. Parts enter and leave a bank only through Wire In and Unwire
-- (see RenewableEnergy/Patches.lua).

require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISTextBox"
require "Vehicles/TimedActions/ISPathFindAction"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Wind"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/PowerBank/Treadmill"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/Gadgets/VehicleBattery"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/TimedActions/RenewableEnergyTreadmillAction"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/Needs"
require "RenewableEnergy/UI/StatusWindow"

RenewableEnergy = RenewableEnergy or {}
local Menu = {}
RenewableEnergy.Menu = Menu

local Action = RenewableEnergyAction
local PowerBank, Sources, Treadmill = RenewableEnergy.PowerBank, RenewableEnergy.Sources, RenewableEnergy.Treadmill
local Wind = RenewableEnergy.Wind
local SolarGardenLight, SolarMaintainer = RenewableEnergy.SolarGardenLight, RenewableEnergy.SolarMaintainer
local Format = RenewableEnergy.Format
local Needs = RenewableEnergy.Needs
local StatusWindow = RenewableEnergy.StatusWindow

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
local function lightOr(character, mode, blocker)
    if Action.needsLight(mode) and character:tooDarkToRead() then
        return "Tooltip_RenewableEnergy_TooDark"
    end
    return blocker
end

local function queueAt(playerNum, square, mode, object, bank, item, bankName)
    local character = getSpecificPlayer(playerNum)
    if luautils.walkAdj(character, square, true) then
        ISTimedActionQueue.add(Action:new(character, mode, object, bank, nil, item, bankName))
    end
end

local function queueSource(playerNum, mode, source, bank)
    queueAt(playerNum, source:getSquare(), mode, source, bank)
end

--- Walks a local player over to `bank` and queues the job `mode` there; `bankName` is Rename's new
--- name. The status window's buttons queue through here too.
function Menu.queueBank(playerNum, mode, bank, bankName)
    queueAt(playerNum, bank:getSquare(), mode, nil, bank, nil, bankName)
end

local function queuePart(playerNum, mode, bank, item)
    queueAt(playerNum, bank:getSquare(), mode, nil, bank, item)
end

local function queueConnectAll(playerNum, bank, sources)
    for _, source in ipairs(sources) do
        queueSource(playerNum, Action.CONNECT_SOURCE, source, bank)
    end
end

local function queueClearSnow(playerNum, source)
    local character = getSpecificPlayer(playerNum)
    if not luautils.walkAdj(character, source:getSquare(), true) then
        return
    end
    local tool = ISWorldObjectContextMenu.equip(character, character:getPrimaryHandItem(), Action.isSnowTool, true)
    ISTimedActionQueue.add(Action:new(character, Action.CLEAR_SNOW, source, nil, nil, tool))
end

local function queueBlades(playerNum, source, blades)
    queueAt(playerNum, source:getSquare(), Action.REPLACE_BLADES, source, nil, blades)
end

local function queueBulb(playerNum, mode, light, bulb)
    local character = getSpecificPlayer(playerNum)
    if not luautils.walkAdj(character, light:getSquare(), true) then
        return
    end
    if bulb then
        ISInventoryPaneContextMenu.transferIfNeeded(character, bulb)
    end
    ISTimedActionQueue.add(Action:new(character, mode, light, nil, nil, bulb))
end

-- Walks to the vehicle's battery, where a maintainer clips on.
local function queueVehicle(playerNum, mode, vehicle, item)
    local character = getSpecificPlayer(playerNum)
    if item then
        ISInventoryPaneContextMenu.transferIfNeeded(character, item)
    end
    local battery = vehicle:getPartById(RenewableEnergy.VehicleBattery.PART)
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(character, vehicle, battery:getArea()))
    ISTimedActionQueue.add(Action:new(character, mode, nil, nil, vehicle, item))
end

-- Walks to the panel's side of the trailer and mends it there.
local function queueRepairPanel(playerNum, vehicle, partId)
    local character = getSpecificPlayer(playerNum)
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(character, vehicle, vehicle:getPartById(partId):getArea()))
    ISTimedActionQueue.add(Action:new(character, Action.REPAIR_PANEL, nil, nil, vehicle, nil, nil, partId))
end

-- Walks to the frame part's end of the trailer, then fixes it as the mechanics window's Repair
-- menu does (ISInventoryPaneContextMenu.onFix), which walks nowhere.
local function queueFixFrame(item, playerNum, fixingNum, fixerNum, part)
    local character = getSpecificPlayer(playerNum)
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(character, part:getVehicle(), part:getArea()))
    ISInventoryPaneContextMenu.onFix(item, playerNum, fixingNum, fixerNum, part)
end

local function queueRun(playerNum, treadmill)
    local character = getSpecificPlayer(playerNum)
    if luautils.walkAdj(character, treadmill:getSquare(), true) then
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

-- "Car Battery (72%)": a wired part, told apart from its twins by its condition.
local function partLabel(item)
    return getText("ContextMenu_RenewableEnergy_PartCondition", item:getDisplayName(),
        Format.percent(item:getCondition() / item:getConditionMax()))
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

-- One item of each type the character carries for which `matches(item)` holds, bags included, in
-- inventory order.
local function oneOfEachType(character, matches)
    local found, seen = {}, {}
    local items = character:getInventory():getAllEvalRecurse(matches)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local fullType = item:getFullType()
        if not seen[fullType] then
            seen[fullType] = true
            table.insert(found, item)
        end
    end
    return found
end

--- Wire In: one option for each type of part the character carries, listing what wiring it in
--- takes and greyed out while it can't go in. Returns the submenu, or the unavailable option when
--- the character carries no part.
function Menu.addWireInOptions(playerNum, menu, bank)
    local character = getSpecificPlayer(playerNum)
    local parts = oneOfEachType(character, isPart)
    if #parts == 0 then
        local option = menu:addOption(getText("ContextMenu_RenewableEnergy_WireIn"))
        Needs.refuse(option, "Tooltip_RenewableEnergy_NothingToWire")
        return option
    end
    local submenu = Needs.addSubMenu(menu, getText("ContextMenu_RenewableEnergy_WireIn"))
    for _, item in ipairs(parts) do
        local option = submenu:addOption(item:getDisplayName(), playerNum, queuePart, Action.WIRE_IN, bank, item)
        Needs.show(option, PowerBank.wiringNeeds(character, item:getFullType()),
            lightOr(character, Action.WIRE_IN, PowerBank.wiringBlocker(bank, item)))
    end
    return submenu
end

--- Unwire: one option for each part in the bank. Returns the submenu, or nil for an empty bank.
function Menu.addUnwireOptions(playerNum, menu, bank)
    local parts = wiredParts(bank, PowerBank.partKind)
    if #parts == 0 then
        return nil
    end
    local character = getSpecificPlayer(playerNum)
    local submenu = Needs.addSubMenu(menu, getText("ContextMenu_RenewableEnergy_Unwire"))
    for _, item in ipairs(parts) do
        local option = submenu:addOption(partLabel(item), playerNum, queuePart, Action.UNWIRE, bank, item)
        Needs.refuse(option, lightOr(character, Action.UNWIRE, PowerBank.unwireBlocker(bank, item)))
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

-- The sources in the bank's reach that could be connected to it now (Sources.connectRefusal),
-- those connected to another bank included.
local function unconnectedSources(bank)
    local here = PowerBank.positionOf(bank)
    local reach = RenewableEnergy.Specs.sourceReach
    local found = {}
    for z = here.z - reach.levels, here.z + reach.levels do
        for x = here.x - reach.tiles, here.x + reach.tiles do
            for y = here.y - reach.tiles, here.y + reach.tiles do
                local source = Sources.on(getSquare(x, y, z))
                if source and not Sources.connectRefusal(source, here) then
                    table.insert(found, source)
                end
            end
        end
    end
    return found
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

function Menu.addBankOptions(playerNum, context, bank)
    local menu = Needs.addSubMenu(context, Menu.bankLabel(bank))
    menu:addOption(getText("ContextMenu_RenewableEnergy_Status"), playerNum, StatusWindow.open, bank)

    local summary = PowerBank.summaryOf(bank)
    if not summary then
        -- The server has not sent this bank's summary yet; switching it needs to know its state.
        return menu
    end
    local on = summary.on == true
    local switch = menu:addOption(getText(on and "ContextMenu_Turn_Off" or "ContextMenu_Turn_On"), playerNum, Menu.queueBank,
        on and Action.TURN_OFF or Action.TURN_ON, bank)
    Needs.refuse(switch, PowerBank.switchRefusal(summary, not on))
    -- As vanilla's generator menu: Disconnect only while switched off.
    local connected = bank:isConnected()
    if not (connected and on) then
        local plug = menu:addOption(getText(connected and "ContextMenu_RenewableEnergy_DisconnectBank" or "ContextMenu_RenewableEnergy_ConnectBank"),
            playerNum, Menu.queueBank, connected and Action.DISCONNECT_BANK or Action.CONNECT_BANK, bank)
        Needs.refuse(plug, PowerBank.connectRefusal(getSpecificPlayer(playerNum), bank, summary, not connected))
    end

    local sources = unconnectedSources(bank)
    local connect = menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectSourcesInReach", #sources), playerNum,
        queueConnectAll, bank, sources)
    Needs.refuse(connect, #sources == 0 and "Tooltip_RenewableEnergy_NoSourcesInReach" or slotsRefusal(sources, summary.freeSlots))
    Menu.addWireInOptions(playerNum, menu, bank)
    Menu.addUnwireOptions(playerNum, menu, bank)
    Menu.addRepairOptions(playerNum, menu, bank)
    menu:addOption(getText("ContextMenu_RenewableEnergy_Rename"), playerNum, Menu.askName, bank)
    return menu
end

-- The entry for the source at `here` in its bank's summary.
local function sourceSummary(bankPosition, here)
    local summary = PowerBank.getSummary(bankPosition.x, bankPosition.y, bankPosition.z)
    for _, entry in ipairs(summary and summary.sources or {}) do
        if PowerBank.samePosition(entry, here) then
            return entry
        end
    end
end

local function bankNameAt(at)
    local summary = PowerBank.getSummary(at.x, at.y, at.z)
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

-- Replace Blades, for a wind charger a storm broke: the first blades carried that fit it, or the
-- option greyed, naming the ones that would.
local function addBladesOption(playerNum, menu, source)
    local fits = Sources.bladesFor(Sources.kindOf(source))
    local blades = getSpecificPlayer(playerNum):getInventory():getFirstEvalRecurse(function(item)
        return fits[item:getFullType()] == true
    end)
    local refusal = Wind.bladesRefusal(source, blades)
    if refusal == "not broken" then
        return
    end
    local option = menu:addOption(getText("ContextMenu_RenewableEnergy_ReplaceBlades"), playerNum, queueBlades, source, blades)
    if refusal then
        local names = {}
        for fullType in pairs(fits) do
            table.insert(names, getItemNameFromFullType(fullType))
        end
        table.sort(names)
        Needs.refuse(option, "Tooltip_RenewableEnergy_NeedBlades", table.concat(names, ", "))
    end
end

function Menu.addSourceOptions(playerNum, context, source)
    local menu = Needs.addSubMenu(context, Menu.nameOf(source))

    local here = PowerBank.positionOf(source)
    local connected = PowerBank.connectedBank(source)
    if connected then
        menu:addOption(getText("ContextMenu_RenewableEnergy_WiredTo", bankNameAt(connected), Format.away(here, connected)))
        menu:addOption(getText("ContextMenu_RenewableEnergy_DisconnectSource"), playerNum, queueSource, Action.DISCONNECT_SOURCE, source)
        addSnowOption(playerNum, menu, source, sourceSummary(connected, here))
    end
    addBrakeOption(playerNum, menu, source)
    addBladesOption(playerNum, menu, source)

    local offered = false
    local kind = Sources.kindOf(source)
    for _, bankPosition in ipairs(Sources.banksInReach(here.x, here.y, here.z, kind)) do
        local bank = PowerBank.bankOn(getSquare(bankPosition.x, bankPosition.y, bankPosition.z))
        if bank and not Sources.connectRefusal(source, bankPosition) then
            local option = menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectSource", Menu.bankLabel(bank),
                Format.away(here, bankPosition)), playerNum, queueSource, Action.CONNECT_SOURCE, source, bank)
            local summary = PowerBank.summaryOf(bank)
            Needs.refuse(option, summary and Sources.slotRefusal(kind, summary.freeSlots))
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

-- Run on Treadmill and Unwire, for a wired treadmill, into its menu.
local function addWiredTreadmillOptions(playerNum, menu, treadmill)
    addRunOption(playerNum, menu, treadmill)
    local unwire = menu:addOption(getText("ContextMenu_RenewableEnergy_UnwireTreadmill"), playerNum, queueSource,
        Action.UNWIRE_TREADMILL, treadmill)
    Needs.refuse(unwire, lightOr(getSpecificPlayer(playerNum), Action.UNWIRE_TREADMILL))
end

-- Run on Treadmill and Wire to Bank, for a treadmill neither of whose tiles is wired yet.
function Menu.addTreadmillOptions(playerNum, context, treadmill)
    local character = getSpecificPlayer(playerNum)
    local menu = Needs.addSubMenu(context, Menu.nameOf(treadmill))
    addRunOption(playerNum, menu, treadmill)
    local option = menu:addOption(getText("ContextMenu_RenewableEnergy_WireTreadmill"), playerNum, queueSource,
        Action.WIRE_TREADMILL, treadmill)
    Needs.show(option, Treadmill.needs(character), lightOr(character, Action.WIRE_TREADMILL))
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
    local bulbs = oneOfEachType(getSpecificPlayer(playerNum), SolarGardenLight.isBulb)
    if #bulbs == 0 then
        Needs.refuse(menu:addOption(getText("ContextMenu_AddLightbulb")), "ContextMenu_AddLightbulb_RequiresBulb")
        return menu
    end
    local submenu = Needs.addSubMenu(menu, getText("ContextMenu_AddLightbulb"))
    for _, bulb in ipairs(bulbs) do
        local option = submenu:addOption(bulb:getDisplayName(), playerNum, queueBulb, Action.ADD_BULB, light, bulb)
        option.iconTexture = bulb:getTex()
        option.color = { r = bulb:getColorRed(), g = bulb:getColorGreen(), b = bulb:getColorBlue() }
    end
    return menu
end

--- Seal Cracked Panel for each cracked panel of an arrow board trailer that the seal can
--- help, listing what the seal takes and greyed out when the character can't do it.
function Menu.addPanelRepairOptions(playerNum, context, vehicle)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    if not ArrowBoard.isTrailer(vehicle) then
        return
    end
    local character = getSpecificPlayer(playerNum)
    local needs = RenewableEnergy.Recipes.panelRepairNeeds(character)
    local blocker = lightOr(character, Action.REPAIR_PANEL)
    for _, partId in ipairs(ArrowBoard.PANELS) do
        local part = ArrowBoard.repairablePanel(vehicle, partId)
        if part then
            local option = context:addOption(getText("ContextMenu_RenewableEnergy_RepairPanel",
                getText("IGUI_VehiclePart" .. partId), part:getCondition()), playerNum, queueRepairPanel, vehicle, partId)
            Needs.show(option, needs, blocker)
        end
    end
end

--- Repair Frame for each dented end of an arrow board trailer's frame: vanilla's fixing menu for
--- the part, the one the mechanics window gives a car's body.
function Menu.addFrameRepairOptions(playerNum, context, vehicle)
    for _, frame in ipairs(RenewableEnergy.ArrowBoard.damagedFrame(vehicle)) do
        local part = frame.part
        local item = part:getInventoryItem()
        local submenu, option = Needs.addSubMenu(context, getText("ContextMenu_RenewableEnergy_RepairFrame", getText(frame.name),
            part:getCondition()))
        local fixes = FixingManager.getFixes(item)
        for i = 0, fixes:size() - 1 do
            ISInventoryPaneContextMenu.buildFixingMenu(item, playerNum, fixes:get(i), i, option, submenu, part)
        end
        for _, fix in ipairs(submenu.options) do
            fix.onSelect = queueFixFrame
        end
    end
end

--- The arrow board's repairs, and Attach or Detach Solar Maintainer. Returns the maintainer's
--- option, or nil when there is none to offer.
function Menu.addVehicleOptions(playerNum, context, vehicle)
    Menu.addPanelRepairOptions(playerNum, context, vehicle)
    Menu.addFrameRepairOptions(playerNum, context, vehicle)
    if SolarMaintainer.isAttached(vehicle) then
        return context:addOption(getText("ContextMenu_RenewableEnergy_DetachMaintainer"), playerNum, queueVehicle,
            Action.DETACH_MAINTAINER, vehicle)
    end
    local maintainer = getSpecificPlayer(playerNum):getInventory():getFirstTypeRecurse(SolarMaintainer.ITEM)
    if maintainer and SolarMaintainer.canAttach(vehicle) then
        return context:addOption(getText("ContextMenu_RenewableEnergy_AttachMaintainer"), playerNum, queueVehicle,
            Action.ATTACH_MAINTAINER, vehicle, maintainer)
    end
end

-- The generator vanilla would have offered its menu on had the bank not been there.
--
-- fetchVars.generator holds only the last IsoGenerator the fetch walked, and a bank is one.
-- Clearing the slot would also hide the menu of a real generator beside the bank, where a backup
-- generator stands. This walks the objects in the fetch's order (each entry, then its square once;
-- ISWorldObjectContextMenuLogic.fetch) so the generator handed back is the one vanilla would pick.
local function otherGenerator(worldobjects)
    local found, seen = nil, {}
    local function consider(object)
        if instanceof(object, "IsoGenerator") and not PowerBank.isBank(object) then
            found = object
        end
    end
    for _, object in ipairs(worldobjects or {}) do
        consider(object)
        local square = object:getSquare()
        if square and not seen[square] then
            seen[square] = true
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do
                consider(objects:get(i))
            end
        end
    end
    return found
end

-- Runs before vanilla reads fetchVars, so vanilla offers no generator options (fuel, plug in) for
-- the bank itself.
function Menu.onPreFill(playerNum, context, worldobjects, test)
    local generator = ISWorldObjectContextMenu.fetchVars.generator
    if generator and PowerBank.isBank(generator) then
        ISWorldObjectContextMenu.fetchVars.generator = otherGenerator(worldobjects)
    end
end

function Menu.onFill(playerNum, context, worldobjects, test)
    local bank = Needs.findClicked(worldobjects, PowerBank.isBank)
    local source = Needs.findClicked(worldobjects, Sources.kindOf)
    local light = Needs.findClicked(worldobjects, SolarGardenLight.isLight)
    local treadmill = Needs.findClicked(worldobjects, Treadmill.isTreadmill)
    if treadmill and not source then
        source = Treadmill.wiredHalf(treadmill)
    end
    local character = getSpecificPlayer(playerNum)
    local vehicle = not character:getVehicle() and IsoObjectPicker.Instance:PickVehicle(getMouseXScaled(), getMouseYScaled())
    if not (bank or source or light or treadmill or vehicle) then
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
            addWiredTreadmillOptions(playerNum, menu, source)
        end
    end
    if treadmill and not wiredTreadmill then
        Menu.addTreadmillOptions(playerNum, context, treadmill)
    end
    if light then
        Menu.addGardenLightOptions(playerNum, context, light)
    end
    if vehicle then
        Menu.addVehicleOptions(playerNum, context, vehicle)
    end
end

Events.OnPreFillWorldObjectContextMenu.Add(Menu.onPreFill)
Events.OnFillWorldObjectContextMenu.Add(Menu.onFill)

return Menu
