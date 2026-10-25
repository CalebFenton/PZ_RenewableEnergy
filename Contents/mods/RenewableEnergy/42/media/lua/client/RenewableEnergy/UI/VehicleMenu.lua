-- Right-click options on vehicles: the arrow board trailer's panel and frame repairs, and
-- attaching or detaching a Solar Maintainer. Greyed out by the same refusals the job's action asks.

require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISInventoryPaneContextMenu"
require "Vehicles/TimedActions/ISPathFindAction"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/Gadgets/VehicleBattery"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local Needs = require "cf_commonlib/Needs"

RenewableEnergy = RenewableEnergy or {}
local VehicleMenu = {}
RenewableEnergy.VehicleMenu = VehicleMenu

local Action = RenewableEnergyAction
local SolarMaintainer = RenewableEnergy.SolarMaintainer

-- Walks to the vehicle's battery, where a maintainer clips on.
local function queueVehicle(playerNum, job, vehicle, item)
    local character = getSpecificPlayer(playerNum)
    if item then
        ISInventoryPaneContextMenu.transferIfNeeded(character, item)
    end
    local battery = RenewableEnergy.VehicleBattery.partOf(vehicle)
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(character, vehicle, battery:getArea()))
    ISTimedActionQueue.add(Action:new(character, job, nil, nil, vehicle, item))
end

-- Walks to the panel's side of the trailer and mends it there.
local function queueSealPanel(playerNum, vehicle, partId)
    local character = getSpecificPlayer(playerNum)
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(character, vehicle, vehicle:getPartById(partId):getArea()))
    ISTimedActionQueue.add(Action:new(character, Action.SEAL_PANEL, nil, nil, vehicle, nil, nil, partId))
end

-- Walks to the frame part's end of the trailer, then fixes it as the mechanics window's Repair
-- menu does (ISInventoryPaneContextMenu.onFix), which walks nowhere.
local function queueFixFrame(item, playerNum, fixingNum, fixerNum, part)
    local character = getSpecificPlayer(playerNum)
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(character, part:getVehicle(), part:getArea()))
    ISInventoryPaneContextMenu.onFix(item, playerNum, fixingNum, fixerNum, part)
end

--- Seal Cracked Panel for each cracked panel of an arrow board trailer that the seal can
--- help, listing what the seal takes and greyed out when the character can't do it.
function VehicleMenu.addSealPanelOptions(playerNum, context, vehicle)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    if not ArrowBoard.isTrailer(vehicle) then
        return
    end
    local character = getSpecificPlayer(playerNum)
    local needs = RenewableEnergy.Recipes.sealInPlaceNeeds(character)
    local blocker = Needs.tooDark(character, Action.needsLight(Action.SEAL_PANEL), Action.TOO_DARK)
    for _, partId in ipairs(ArrowBoard.PANELS) do
        local part = ArrowBoard.sealablePanel(vehicle, partId)
        if part then
            local option = context:addOption(getText("ContextMenu_RenewableEnergy_RepairPanel",
                getText("IGUI_VehiclePart" .. partId), part:getCondition()), playerNum, queueSealPanel, vehicle, partId)
            Needs.show(option, needs, blocker)
        end
    end
end

--- Repair Frame for each dented end of an arrow board trailer's frame: vanilla's fixing menu for
--- the part, the one the mechanics window gives a car's body.
function VehicleMenu.addFrameRepairOptions(playerNum, context, vehicle)
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
function VehicleMenu.addVehicleOptions(playerNum, context, vehicle)
    VehicleMenu.addSealPanelOptions(playerNum, context, vehicle)
    VehicleMenu.addFrameRepairOptions(playerNum, context, vehicle)
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

function VehicleMenu.onFill(playerNum, context, worldobjects, test)
    local character = getSpecificPlayer(playerNum)
    local vehicle = not character:getVehicle() and IsoObjectPicker.Instance:PickVehicle(getMouseXScaled(), getMouseYScaled())
    if not vehicle then
        return
    end
    if test then
        return ISWorldObjectContextMenu.setTest()
    end
    VehicleMenu.addVehicleOptions(playerNum, context, vehicle)
end

Events.OnFillWorldObjectContextMenu.Add(VehicleMenu.onFill)

return VehicleMenu
