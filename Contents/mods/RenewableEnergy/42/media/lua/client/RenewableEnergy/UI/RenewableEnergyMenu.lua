require "ISUI/ISWorldObjectContextMenu"
require "Vehicles/TimedActions/ISPathFindAction"
---@class RenewableEnergy
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/RenewableEnergyFormat"
require "RenewableEnergy/UI/RenewableEnergyStatusWindow"

-- Right-click menus for battery banks, the panels wired to them and vehicles. Each option queues
-- a RenewableEnergyAction, which walks the character over and does the job.
local Menu = {}

local Action = RenewableEnergyAction
local PowerBank = RenewableEnergy.PowerBank
local Format = RenewableEnergy.Format

-- The item each placed kind is, for its name in the menu.
local ITEMS = {
    flat = "RenewableEnergy.SolarFlat",
    wall = "RenewableEnergy.SolarWall",
    rack = "RenewableEnergy.SolarRack",
    batteryBox = "RenewableEnergy.BatteryBox",
    batteryBank = "RenewableEnergy.BatteryBank",
}

function Menu.nameOf(isoObject)
    local kind = RenewableEnergy.Sprites.kindOf(isoObject:getSprite():getName())
    return getItemNameFromFullType(ITEMS[kind])
end

local function position(object)
    return { x = object:getX(), y = object:getY(), z = object:getZ() }
end

local function disable(option, description)
    option.notAvailable = true
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip.description = description
end

-- As vanilla names a vehicle in its own menus.
function Menu.vehicleName(vehicle)
    local script = vehicle:getScript()
    return Format.vehicleName(script:getCarModelName() or script:getName())
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

local function queueBank(playerNum, mode, bank, vehicle)
    queueAt(playerNum, bank:getSquare(), mode, nil, bank, vehicle)
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

local function openStatus(playerNum, bank)
    RenewableEnergy.StatusWindow.open(playerNum, bank)
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

--- Panels in the bank's reach that are not wired to it yet.
function Menu.unconnectedSources(bank)
    local here = position(bank)
    local reach = RenewableEnergy.Specs.sourceReach
    local found = {}
    forSquaresAround(here, reach.tiles, reach.levels, function(square)
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            if PowerBank.sourceKind(object) and Action.bankInReach(object, bank) then
                local connected = Action.connectedBank(object)
                if not (connected and connected.x == here.x and connected.y == here.y and connected.z == here.z) then
                    table.insert(found, object)
                end
            end
        end
    end)
    return found
end

--- Vehicles close enough to the bank to wire up.
function Menu.vehiclesInReach(bank)
    local here = position(bank)
    local vehicles, seen = {}, {}
    -- A vehicle spans several squares, and any of them can be the one in reach.
    forSquaresAround(here, RenewableEnergy.Specs.vehicleReach + 3, 0, function(square)
        local vehicle = square:getVehicleContainer()
        if vehicle and not seen[vehicle] then
            seen[vehicle] = true
            if PowerBank.vehicleInReach(here, vehicle) then
                table.insert(vehicles, vehicle)
            end
        end
    end)
    return vehicles
end

local function addVehicleOptions(playerNum, menu, bank, status)
    if status.vehicle then
        menu:addOption(getText("ContextMenu_RenewableEnergy_DisconnectVehicle", Format.vehicleName(status.vehicle.name)), playerNum,
            queueBank, Action.DISCONNECT_VEHICLE, bank)
        return
    end
    local hasWire = Action.hasVehicleWire(getSpecificPlayer(playerNum))
    for _, vehicle in ipairs(Menu.vehiclesInReach(bank)) do
        local option = menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectVehicle", Menu.vehicleName(vehicle)),
            playerNum, queueBank, Action.CONNECT_VEHICLE, bank, vehicle)
        if not hasWire then
            disable(option, getText("Tooltip_RenewableEnergy_NeedVehicleWire", PowerBank.VEHICLE_WIRE_COUNT,
                getItemNameFromFullType(PowerBank.VEHICLE_WIRE)))
        end
    end
end

function Menu.addBankOptions(playerNum, context, bank)
    local menu = context:getNew(context)
    context:addSubMenu(context:addOption(Menu.nameOf(bank)), menu)
    menu:addOption(getText("ContextMenu_RenewableEnergy_Status"), playerNum, openStatus, bank)

    local status = PowerBank.getStatus(bank:getX(), bank:getY(), bank:getZ())
    if not status then
        -- The server has not sent this bank's status yet; switching it needs to know its state.
        return menu
    end
    if status.on then
        menu:addOption(getText("ContextMenu_Turn_Off"), playerNum, queueBank, Action.TURN_OFF, bank)
    else
        local option = menu:addOption(getText("ContextMenu_Turn_On"), playerNum, queueBank, Action.TURN_ON, bank)
        if status.inverter.state == "none" then
            disable(option, getText("Tooltip_RenewableEnergy_NoInverter"))
        end
    end
    if status.inverter.state == "tripped" then
        menu:addOption(getText("ContextMenu_RenewableEnergy_ResetInverter"), playerNum, queueBank, Action.RESET_INVERTER, bank)
    end

    local sources = Menu.unconnectedSources(bank)
    local option = menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectPanelsInReach", #sources), playerNum, queueConnectAll, bank, sources)
    if #sources == 0 then
        disable(option, getText("Tooltip_RenewableEnergy_NoPanelsInReach"))
    end
    addVehicleOptions(playerNum, menu, bank, status)
    return menu
end

-- Status entry of a wired source, from its bank's status.
local function sourceStatus(bankPosition, source)
    local status = PowerBank.getStatus(bankPosition.x, bankPosition.y, bankPosition.z)
    for _, entry in ipairs(status and status.sources or {}) do
        if entry.x == source:getX() and entry.y == source:getY() and entry.z == source:getZ() then
            return entry
        end
    end
end

-- Compass points clockwise from north, in eighths. +x is east and +y is south in the world.
local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- "north-east, 6 tiles": where a bank is from a panel, to tell several in reach apart.
local function directionLabel(from, to)
    local dx, dy = to.x - from:getX(), to.y - from:getY()
    local tiles = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
    if tiles == 0 then
        return getText("ContextMenu_RenewableEnergy_Here")
    end
    local eighth = math.floor(math.deg(math.atan2(dx, -dy)) / 45 + 0.5) % 8
    return getText("ContextMenu_RenewableEnergy_Away", Format.compass(COMPASS[eighth + 1]), tiles)
end

local function addSnowOption(playerNum, menu, source, entry)
    if RenewableEnergy.PowerBank.sourceKind(source) ~= "flat" or not entry or entry.snow <= 0 then
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

    local connected = Action.connectedBank(source)
    if connected then
        menu:addOption(getText("ContextMenu_RenewableEnergy_DisconnectPanel"), playerNum, queueSource, Action.DISCONNECT_SOURCE, source)
        addSnowOption(playerNum, menu, source, sourceStatus(connected, source))
    end

    local offered = 0
    for _, bankPosition in ipairs(PowerBank.banksInReach(source:getX(), source:getY(), source:getZ())) do
        local square = getSquare(bankPosition.x, bankPosition.y, bankPosition.z)
        local bank = square and Menu.bankOnSquare(square)
        local isConnected = connected and connected.x == bankPosition.x and connected.y == bankPosition.y and connected.z == bankPosition.z
        if bank and not isConnected then
            menu:addOption(getText("ContextMenu_RenewableEnergy_ConnectPanel", Menu.nameOf(bank), directionLabel(source, bankPosition)),
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

function Menu.bankOnSquare(square)
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        if PowerBank.isBank(objects:get(i)) then
            return objects:get(i)
        end
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

--- The generator vanilla would have offered its menu on had the bank not been there.
---
--- fetchVars.generator is a single slot that the last IsoGenerator walked wins, and a bank is an
--- IsoGenerator. Clearing the slot would also hide the menu of a real generator next to the bank,
--- the very layout a backup generator needs. This walks the objects in the engine's order (each
--- entry, then its square once) so the generator handed back is the one vanilla would have picked.
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

RenewableEnergy.Menu = Menu
return Menu
