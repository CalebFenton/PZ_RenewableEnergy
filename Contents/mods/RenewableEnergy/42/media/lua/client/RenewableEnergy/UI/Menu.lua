-- Right-click menus for battery banks, the panels connected to them, garden lights and vehicles.
-- Each option queues a RenewableEnergyAction, which walks the character over and does the job,
-- except Repair Frame, which walks over and queues vanilla's fixing. Parts go into a bank and come
-- out only through Wire In and Unwire here (see RenewableEnergy/Patches.lua).

require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISInventoryPaneContextMenu"
require "Vehicles/TimedActions/ISPathFindAction"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/Needs"
require "RenewableEnergy/UI/StatusWindow"

RenewableEnergy = RenewableEnergy or {}
local Menu = {}
RenewableEnergy.Menu = Menu

local Action = RenewableEnergyAction
local PowerBank = RenewableEnergy.PowerBank
local SolarGardenLight = RenewableEnergy.SolarGardenLight
local Format = RenewableEnergy.Format
local Needs = RenewableEnergy.Needs
local StatusWindow = RenewableEnergy.StatusWindow

--- The name of the item a placed tile is: its CustomItem, which picking it up gives back.
function Menu.nameOf(isoObject)
    return getItemNameFromFullType(isoObject:getProperties():get("CustomItem"))
end

--- A bank's name: the one a player gave it, else its tier's.
function Menu.bankLabel(bank)
    local summary = PowerBank.summaryOf(bank)
    return summary and Format.bankName(summary) or Menu.nameOf(bank)
end

local function disable(option, description)
    option.notAvailable = true
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip.description = description
end

-- An option whose job takes several things (skill, tools, materials) lists them all with have and
-- need, as vanilla's item repair and build menu do, so the character sees everything they lack at
-- once; greyed out while any is short. A `blocker` (a translation key) that no amount of carrying
-- fixes replaces the list with its plain sentence, as vanilla's generator options do.
local function showNeeds(option, needs, blocker)
    if blocker then
        disable(option, getText(blocker))
        return
    end
    option.notAvailable = RenewableEnergy.firstUnmet(needs) ~= nil
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip.description = Needs.describe(needs)
end

local function queueAt(playerNum, square, mode, object, bank, vehicle, item)
    local character = getSpecificPlayer(playerNum)
    if luautils.walkAdj(character, square, true) then
        ISTimedActionQueue.add(Action:new(character, mode, object, bank, vehicle, item))
    end
end

local function queueSource(playerNum, mode, source, bank)
    queueAt(playerNum, source:getSquare(), mode, source, bank)
end

local function queueBank(playerNum, mode, bank)
    queueAt(playerNum, bank:getSquare(), mode, nil, bank)
end

local function queuePart(playerNum, mode, bank, item)
    queueAt(playerNum, bank:getSquare(), mode, nil, bank, nil, item)
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

local function queueVehicle(playerNum, mode, vehicle, item)
    local character = getSpecificPlayer(playerNum)
    if item then
        ISInventoryPaneContextMenu.transferIfNeeded(character, item)
    end
    local battery = vehicle:getPartById("Battery")
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(character, vehicle, battery:getArea()))
    ISTimedActionQueue.add(Action:new(character, mode, nil, nil, vehicle, item))
end

-- "Car Battery (72%)": a wired part, told apart from its twins by its condition.
local function partLabel(item)
    return getText("ContextMenu_RenewableEnergy_PartCondition", item:getDisplayName(),
        Format.percent(item:getCondition() / item:getConditionMax()))
end

local function isPart(item)
    return PowerBank.partKind(item:getFullType()) ~= nil
end

-- The parts in the bank's container, in its order.
local function wiredParts(bank)
    local parts = {}
    local items = bank:getContainer():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if isPart(item) then
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

local function addSubMenu(context, name)
    local submenu = context:getNew(context)
    context:addSubMenu(context:addOption(name), submenu)
    return submenu
end

--- Wire In: one option for each type of part the character carries, listing what wiring it in
--- takes and greyed out while it can't go in. Returns the submenu, or the unavailable option when
--- the character carries no part.
function Menu.addWireInOptions(playerNum, menu, bank)
    local character = getSpecificPlayer(playerNum)
    local parts = oneOfEachType(character, isPart)
    if #parts == 0 then
        local option = menu:addOption(getText("ContextMenu_RenewableEnergy_WireIn"))
        disable(option, getText("Tooltip_RenewableEnergy_NothingToWire"))
        return option
    end
    local submenu = addSubMenu(menu, getText("ContextMenu_RenewableEnergy_WireIn"))
    for _, item in ipairs(parts) do
        local option = submenu:addOption(item:getDisplayName(), playerNum, queuePart, Action.WIRE_IN, bank, item)
        showNeeds(option, PowerBank.wiringNeeds(character, item:getFullType()), PowerBank.wiringBlocker(character, bank, item))
    end
    return submenu
end

--- Unwire: one option for each part in the bank. Returns the submenu, or nil for an empty bank.
function Menu.addUnwireOptions(playerNum, menu, bank)
    local parts = wiredParts(bank)
    if #parts == 0 then
        return nil
    end
    local dark = getSpecificPlayer(playerNum):tooDarkToRead()
    local submenu = addSubMenu(menu, getText("ContextMenu_RenewableEnergy_Unwire"))
    for _, item in ipairs(parts) do
        local option = submenu:addOption(partLabel(item), playerNum, queuePart, Action.UNWIRE, bank, item)
        if dark then
            disable(option, getText("Tooltip_RenewableEnergy_TooDark"))
        end
    end
    return submenu
end

--- Repair: one option for each inverter and charge controller in the bank, which Electronics
--- Scrap mends, listing what the repair takes. Returns the submenu, or nil when the bank has none.
function Menu.addRepairOptions(playerNum, menu, bank)
    local parts = {}
    for _, item in ipairs(wiredParts(bank)) do
        local kind = PowerBank.partKind(item:getFullType())
        if kind == "inverter" or kind == "controller" then
            table.insert(parts, item)
        end
    end
    if #parts == 0 then
        return nil
    end
    local character = getSpecificPlayer(playerNum)
    local needs = PowerBank.repairNeeds(character)
    local submenu = addSubMenu(menu, getText("ContextMenu_RenewableEnergy_Repair"))
    for _, item in ipairs(parts) do
        local option = submenu:addOption(partLabel(item), playerNum, queuePart, Action.REPAIR_PART, bank, item)
        showNeeds(option, needs, PowerBank.repairBlocker(character, item))
    end
    return submenu
end

-- Every loaded square within `radius` tiles and `levels` floors of a position.
local function forSquaresAround(center, radius, levels, fn)
    for z = center.z - levels, center.z + levels do
        for x = center.x - radius, center.x + radius do
            for y = center.y - radius, center.y + radius do
                local square = getSquare(x, y, z)
                if square then
                    fn(square)
                end
            end
        end
    end
end

--- Panels and wind chargers in the bank's reach that are not connected to it yet. This bank's
--- summary says which are, rather than asking every bank about every source found.
function Menu.unconnectedSources(bank)
    local here = PowerBank.positionOf(bank)
    local reach = RenewableEnergy.Specs.sourceReach
    local summary = PowerBank.summaryOf(bank)
    local connected = {}
    for _, source in ipairs(summary and summary.sources or {}) do
        connected[source.x .. "," .. source.y .. "," .. source.z] = true
    end
    local found = {}
    forSquaresAround(here, reach.tiles, reach.levels, function(square)
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            if PowerBank.sourceKind(object) and square:isOutside()
                and PowerBank.isInReach(here, square:getX(), square:getY(), square:getZ())
                and not connected[square:getX() .. "," .. square:getY() .. "," .. square:getZ()] then
                table.insert(found, object)
            end
        end
    end)
    return found
end

function Menu.addBankOptions(playerNum, context, bank)
    local menu = addSubMenu(context, Menu.bankLabel(bank))
    menu:addOption(getText("ContextMenu_RenewableEnergy_Status"), playerNum, StatusWindow.open, bank)

    local summary = PowerBank.summaryOf(bank)
    if not summary then
        -- The server has not sent this bank's summary yet; switching it needs to know its state.
        return menu
    end
    if summary.on then
        menu:addOption(getText("ContextMenu_Turn_Off"), playerNum, queueBank, Action.TURN_OFF, bank)
    else
        local option = menu:addOption(getText("ContextMenu_Turn_On"), playerNum, queueBank, Action.TURN_ON, bank)
        if summary.limitW <= 0 then
            disable(option, getText("Tooltip_RenewableEnergy_NoInverter"))
        end
    end

    local sources = Menu.unconnectedSources(bank)
    local option = menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectPanelsInReach", #sources), playerNum, queueConnectAll, bank, sources)
    if #sources == 0 then
        disable(option, getText("Tooltip_RenewableEnergy_NoPanelsInReach"))
    end
    Menu.addWireInOptions(playerNum, menu, bank)
    Menu.addUnwireOptions(playerNum, menu, bank)
    Menu.addRepairOptions(playerNum, menu, bank)
    menu:addOption(getText("ContextMenu_RenewableEnergy_Rename"), playerNum, StatusWindow.askName, bank)
    return menu
end

-- A connected source's entry in its bank's summary.
local function sourceSummary(bankPosition, source)
    local summary = PowerBank.getSummary(bankPosition.x, bankPosition.y, bankPosition.z)
    local here = PowerBank.positionOf(source)
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
    if PowerBank.sourceKind(source) ~= "flat" or not (entry and entry.snowy) then
        return
    end
    local option = menu:addOption(getText("ContextMenu_RenewableEnergy_ClearSnow"), playerNum, queueClearSnow, source)
    if not getSpecificPlayer(playerNum):getInventory():containsEvalRecurse(Action.isSnowTool) then
        disable(option, getText("Tooltip_RenewableEnergy_NeedSnowTool"))
    end
end

-- A wind charger's brake, set or let go, connected or not.
local function addBrakeOption(playerNum, menu, source)
    if not PowerBank.isWind(PowerBank.sourceKind(source)) then
        return
    end
    local braked = PowerBank.isBraked(source)
    menu:addOption(getText(braked and "ContextMenu_RenewableEnergy_ReleaseBrake" or "ContextMenu_RenewableEnergy_Brake"),
        playerNum, queueSource, braked and Action.RELEASE_BRAKE or Action.BRAKE, source)
end

function Menu.addSourceOptions(playerNum, context, source)
    local menu = addSubMenu(context, Menu.nameOf(source))

    local here = PowerBank.positionOf(source)
    local connected = Action.connectedBank(source)
    if connected then
        menu:addOption(getText("ContextMenu_RenewableEnergy_WiredTo", bankNameAt(connected), Format.away(here, connected)))
        menu:addOption(getText("ContextMenu_RenewableEnergy_DisconnectPanel"), playerNum, queueSource, Action.DISCONNECT_SOURCE, source)
        addSnowOption(playerNum, menu, source, sourceSummary(connected, source))
    end
    addBrakeOption(playerNum, menu, source)

    local offered = 0
    for _, bankPosition in ipairs(PowerBank.banksInReach(source:getX(), source:getY(), source:getZ())) do
        local bank = PowerBank.bankOn(getSquare(bankPosition.x, bankPosition.y, bankPosition.z))
        if bank and not PowerBank.samePosition(connected, bankPosition) then
            menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectPanel", Menu.bankLabel(bank), Format.away(here, bankPosition)),
                playerNum, queueSource, Action.CONNECT_SOURCE, source, bank)
            offered = offered + 1
        end
    end
    if offered == 0 and not connected then
        local option = menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectToBank"))
        local outdoors = source:getSquare():isOutside()
        disable(option, getText(outdoors and "Tooltip_RenewableEnergy_NoBankInReach" or "Tooltip_RenewableEnergy_PanelIndoors"))
    end
    return menu
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

--- Remove Light Bulb for a light that has one, else Add Light Bulb with one option for each type
--- of bulb the character carries, shown in its colour as vanilla shows a lamp's. Returns the
--- light's submenu.
function Menu.addGardenLightOptions(playerNum, context, light)
    local menu = addSubMenu(context, Menu.nameOf(light))
    if SolarGardenLight.getBulb(light) then
        menu:addOption(getText("ContextMenu_RemoveLightbulb"), playerNum, queueBulb, Action.REMOVE_BULB, light)
        return menu
    end
    local bulbs = oneOfEachType(getSpecificPlayer(playerNum), SolarGardenLight.isBulb)
    if #bulbs == 0 then
        disable(menu:addOption(getText("ContextMenu_AddLightbulb")), getText("ContextMenu_AddLightbulb_RequiresBulb"))
        return menu
    end
    local submenu = addSubMenu(menu, getText("ContextMenu_AddLightbulb"))
    for _, bulb in ipairs(bulbs) do
        local option = submenu:addOption(bulb:getDisplayName(), playerNum, queueBulb, Action.ADD_BULB, light, bulb)
        option.iconTexture = bulb:getTex()
        option.color = { r = bulb:getColorRed(), g = bulb:getColorGreen(), b = bulb:getColorBlue() }
    end
    return menu
end

-- Walks to the panel's side of the trailer and mends it there.
local function queueRepairPanel(playerNum, vehicle, partId)
    local character = getSpecificPlayer(playerNum)
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(character, vehicle, vehicle:getPartById(partId):getArea()))
    ISTimedActionQueue.add(Action:new(character, Action.REPAIR_PANEL, nil, nil, vehicle, nil, nil, partId))
end

--- Repair Cracked Panel for each cracked panel of an arrow board trailer that the repair can
--- mend, listing what the repair takes and greyed out when the character can't do it.
function Menu.addPanelRepairOptions(playerNum, context, vehicle)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    if not ArrowBoard.isTrailer(vehicle) then
        return
    end
    local needs = RenewableEnergy.Recipes.panelRepairNeeds(getSpecificPlayer(playerNum))
    for _, partId in ipairs(ArrowBoard.PANELS) do
        local part = ArrowBoard.repairablePanel(vehicle, partId)
        if part then
            local option = context:addOption(getText("ContextMenu_RenewableEnergy_RepairPanel",
                getText("IGUI_VehiclePart" .. partId), part:getCondition()), playerNum, queueRepairPanel, vehicle, partId)
            showNeeds(option, needs)
        end
    end
end

-- Walks to the frame part's end of the trailer, then fixes it as the mechanics window's Repair
-- menu does (ISInventoryPaneContextMenu.onFix), which walks nowhere.
local function queueFixFrame(item, playerNum, fixingNum, fixerNum, part)
    local character = getSpecificPlayer(playerNum)
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(character, part:getVehicle(), part:getArea()))
    ISInventoryPaneContextMenu.onFix(item, playerNum, fixingNum, fixerNum, part)
end

--- Repair Frame for each dented end of an arrow board trailer's frame: vanilla's fixing menu for
--- the part, the one the mechanics window gives a car's body.
function Menu.addFrameRepairOptions(playerNum, context, vehicle)
    for _, frame in ipairs(RenewableEnergy.ArrowBoard.damagedFrame(vehicle)) do
        local part = frame.part
        local item = part:getInventoryItem()
        local option = context:addOption(getText("ContextMenu_RenewableEnergy_RepairFrame", getText(frame.name),
            part:getCondition()))
        local submenu = context:getNew(context)
        context:addSubMenu(option, submenu)
        local fixes = FixingManager.getFixes(item)
        for i = 0, fixes:size() - 1 do
            ISInventoryPaneContextMenu.buildFixingMenu(item, playerNum, fixes:get(i), i, option, submenu, part)
        end
        for _, fix in ipairs(submenu.options) do
            fix.onSelect = queueFixFrame
        end
    end
end

function Menu.addVehicleOptions(playerNum, context, vehicle)
    Menu.addPanelRepairOptions(playerNum, context, vehicle)
    Menu.addFrameRepairOptions(playerNum, context, vehicle)
    local SolarMaintainer = RenewableEnergy.SolarMaintainer
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

-- The bank, the panel and the garden light among the clicked objects and the squares they stand
-- on.
local function findTargets(worldobjects)
    local bank, source, light, seen = nil, nil, nil, {}
    for _, clicked in ipairs(worldobjects) do
        local square = clicked:getSquare()
        if square and not seen[square] then
            seen[square] = true
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do
                local object = objects:get(i)
                if not bank and PowerBank.isBank(object) then
                    bank = object
                elseif not source and PowerBank.sourceKind(object) then
                    source = object
                elseif not light and SolarGardenLight.isLight(object) then
                    light = object
                end
            end
        end
    end
    return bank, source, light
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
    local bank, source, light = findTargets(worldobjects)
    local character = getSpecificPlayer(playerNum)
    local vehicle = not character:getVehicle() and IsoObjectPicker.Instance:PickVehicle(getMouseXScaled(), getMouseYScaled())
    if not (bank or source or light or vehicle) then
        return
    end
    if test then
        return ISWorldObjectContextMenu.setTest()
    end
    if bank then
        Menu.addBankOptions(playerNum, context, bank)
    end
    if source then
        Menu.addSourceOptions(playerNum, context, source)
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
