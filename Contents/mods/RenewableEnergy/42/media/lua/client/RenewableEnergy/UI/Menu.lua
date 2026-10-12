-- Right-click menus for battery banks, the panels connected to them and vehicles. Each option
-- queues a RenewableEnergyAction, which walks the character over and does the job. Parts go into
-- a bank and come out only through Wire In and Unwire here (see RenewableEnergy/Patches.lua).

require "ISUI/ISWorldObjectContextMenu"
require "Vehicles/TimedActions/ISPathFindAction"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/StatusWindow"

RenewableEnergy = RenewableEnergy or {}
local Menu = {}
RenewableEnergy.Menu = Menu

local Action = RenewableEnergyAction
local PowerBank = RenewableEnergy.PowerBank
local Format = RenewableEnergy.Format
local StatusWindow = RenewableEnergy.StatusWindow

-- The item each placed kind is, for its name in the menu.
local ITEMS = {
    flat = "RenewableEnergy.SolarFlat",
    wall = "RenewableEnergy.SolarWall",
    rack = "RenewableEnergy.SolarRack",
}
for fullType, bank in pairs(RenewableEnergy.Specs.banks) do
    ITEMS[bank.sprite] = fullType
end

function Menu.nameOf(isoObject)
    local kind, _, material = RenewableEnergy.Sprites.kindOf(isoObject:getSprite():getName())
    local mount = ITEMS[kind] and (kind == "wall" or kind == "rack") and material
    return getItemNameFromFullType(mount and ITEMS[kind] .. (material == "wood" and "Wood" or "Metal") or ITEMS[kind])
end

--- A bank's name: the one a player gave it, else its tier's.
function Menu.bankLabel(bank)
    local status = PowerBank.statusOf(bank)
    return status and Format.bankName(status) or Menu.nameOf(bank)
end

local function disable(option, description)
    option.notAvailable = true
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip.description = description
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

-- A stand-in for each tool tag, to name in the tooltip.
local TOOL_ITEMS = { WRENCH = "Base.Wrench", SCREWDRIVER = "Base.Screwdriver" }

--- The tooltip for a refusal key from PowerBank.wiringRefusal or repairRefusal, naming what is
--- missing from `needs` ({ skill, tool, wire, scrap }).
function Menu.refusalText(key, needs)
    if key == "Tooltip_RenewableEnergy_NeedSkill" then
        return getText(key, Perks.Electricity:getName(), needs.skill)
    elseif key == "Tooltip_RenewableEnergy_NeedTool" then
        return getText(key, getItemNameFromFullType(TOOL_ITEMS[needs.tool]))
    elseif key == "Tooltip_RenewableEnergy_NeedWire" then
        return getText(key, needs.wire, getItemNameFromFullType(PowerBank.WIRE))
    elseif key == "Tooltip_RenewableEnergy_NeedScrap" then
        return getText(key, needs.scrap, getItemNameFromFullType(PowerBank.SCRAP))
    end
    return getText(key)
end

-- "Car Battery (72%)": a wired part, told apart from its twins by its condition.
local function partLabel(item)
    return getText("ContextMenu_RenewableEnergy_PartCondition", item:getDisplayName(),
        Format.percent(item:getCondition() / item:getConditionMax()))
end

-- The parts in the bank's container, in its order.
local function wiredParts(bank)
    local parts = {}
    local items = bank:getContainer():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if PowerBank.partKind(item:getFullType()) then
            table.insert(parts, item)
        end
    end
    return parts
end

-- One item of each part type the character carries, bags included, in inventory order.
local function carriedParts(character)
    local parts, seen = {}, {}
    local items = character:getInventory():getAllEvalRecurse(function(item)
        return PowerBank.partKind(item:getFullType()) ~= nil
    end)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if not seen[item:getFullType()] then
            seen[item:getFullType()] = true
            table.insert(parts, item)
        end
    end
    return parts
end

local function addSubMenu(context, name)
    local submenu = context:getNew(context)
    context:addSubMenu(context:addOption(name), submenu)
    return submenu
end

--- Wire In: one option for each type of part the character carries, unavailable with the
--- reason while it can't go in. Returns the submenu, or the unavailable option when the
--- character carries no part.
function Menu.addWireInOptions(playerNum, menu, bank)
    local character = getSpecificPlayer(playerNum)
    local parts = carriedParts(character)
    if #parts == 0 then
        local option = menu:addOption(getText("ContextMenu_RenewableEnergy_WireIn"))
        disable(option, getText("Tooltip_RenewableEnergy_NothingToWire"))
        return option
    end
    local submenu = addSubMenu(menu, getText("ContextMenu_RenewableEnergy_WireIn"))
    for _, item in ipairs(parts) do
        local option = submenu:addOption(item:getDisplayName(), playerNum, queuePart, Action.WIRE_IN, bank, item)
        local refusal = PowerBank.wiringRefusal(character, bank, item)
        if refusal then
            disable(option, Menu.refusalText(refusal, PowerBank.wiringFor(item:getFullType())))
        end
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
--- Scrap mends. Returns the submenu, or nil when the bank has none.
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
    local needs = { skill = RenewableEnergy.Specs.partRepair.skill, scrap = 1 }
    local submenu = addSubMenu(menu, getText("ContextMenu_RenewableEnergy_Repair"))
    for _, item in ipairs(parts) do
        local option = submenu:addOption(partLabel(item), playerNum, queuePart, Action.REPAIR_PART, bank, item)
        local refusal = PowerBank.repairRefusal(character, item)
        if refusal then
            disable(option, Menu.refusalText(refusal, needs))
        end
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

--- Panels in the bank's reach that are not connected to it yet.
function Menu.unconnectedSources(bank)
    local here = PowerBank.positionOf(bank)
    local reach = RenewableEnergy.Specs.sourceReach
    local found = {}
    forSquaresAround(here, reach.tiles, reach.levels, function(square)
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            if PowerBank.sourceKind(object) and Action.bankInReach(object, bank)
                and not PowerBank.samePosition(Action.connectedBank(object), here) then
                table.insert(found, object)
            end
        end
    end)
    return found
end

function Menu.addBankOptions(playerNum, context, bank)
    local menu = context:getNew(context)
    context:addSubMenu(context:addOption(Menu.bankLabel(bank)), menu)
    menu:addOption(getText("ContextMenu_RenewableEnergy_Status"), playerNum, StatusWindow.open, bank)

    local status = PowerBank.statusOf(bank)
    if not status then
        -- The server has not sent this bank's status yet; switching it needs to know its state.
        return menu
    end
    if status.on then
        menu:addOption(getText("ContextMenu_Turn_Off"), playerNum, queueBank, Action.TURN_OFF, bank)
    else
        local option = menu:addOption(getText("ContextMenu_Turn_On"), playerNum, queueBank, Action.TURN_ON, bank)
        if status.limitW <= 0 then
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

-- A connected source's entry in its bank's status.
local function sourceStatus(bankPosition, source)
    local status = PowerBank.getStatus(bankPosition.x, bankPosition.y, bankPosition.z)
    local here = PowerBank.positionOf(source)
    for _, entry in ipairs(status and status.sources or {}) do
        if PowerBank.samePosition(entry, here) then
            return entry
        end
    end
end

local function bankNameAt(at)
    local status = PowerBank.getStatus(at.x, at.y, at.z)
    return status and Format.bankName(status) or getText("IGUI_RenewableEnergy_StatusTitle")
end

local function addSnowOption(playerNum, menu, source, entry)
    if PowerBank.sourceKind(source) ~= "flat" or not entry or entry.snow <= 0 then
        return
    end
    local option = menu:addOption(getText("ContextMenu_RenewableEnergy_ClearSnow"), playerNum, queueClearSnow, source)
    local character = getSpecificPlayer(playerNum)
    if not character:getInventory():containsEvalRecurse(Action.isSnowTool) then
        disable(option, getText("Tooltip_RenewableEnergy_NeedSnowTool"))
    end
end

function Menu.addSourceOptions(playerNum, context, source)
    local menu = context:getNew(context)
    context:addSubMenu(context:addOption(Menu.nameOf(source)), menu)

    local here = PowerBank.positionOf(source)
    local connected = Action.connectedBank(source)
    if connected then
        menu:addOption(getText("ContextMenu_RenewableEnergy_WiredTo", bankNameAt(connected), Format.away(here, connected)))
        menu:addOption(getText("ContextMenu_RenewableEnergy_DisconnectPanel"), playerNum, queueSource, Action.DISCONNECT_SOURCE, source)
        addSnowOption(playerNum, menu, source, sourceStatus(connected, source))
    end

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

function Menu.addVehicleOptions(playerNum, context, vehicle)
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

-- The bank and the panel among the clicked objects and the squares they stand on.
local function findTargets(worldobjects)
    local bank, source, seen = nil, nil, {}
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
                end
            end
        end
    end
    return bank, source
end

-- The generator vanilla would have offered its menu on had the bank not been there.
--
-- fetchVars.generator is a single slot that the last IsoGenerator walked wins, and a bank is an
-- IsoGenerator. Clearing the slot would also hide the menu of a real generator next to the bank,
-- the very layout a backup generator needs. This walks the objects in the engine's order (each
-- entry, then its square once) so the generator handed back is the one vanilla would have picked.
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
    local bank, source = findTargets(worldobjects)
    local character = getSpecificPlayer(playerNum)
    local vehicle = not character:getVehicle() and IsoObjectPicker.Instance:PickVehicle(getMouseXScaled(), getMouseYScaled())
    if not (bank or source or vehicle) then
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
    if vehicle then
        Menu.addVehicleOptions(playerNum, context, vehicle)
    end
end

Events.OnPreFillWorldObjectContextMenu.Add(Menu.onPreFill)
Events.OnFillWorldObjectContextMenu.Add(Menu.onFill)

return Menu
