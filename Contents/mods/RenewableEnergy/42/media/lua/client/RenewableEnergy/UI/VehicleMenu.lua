-- Right-click options on vehicles: the arrow board trailer's panel and frame repairs, and
-- attaching or detaching a Solar Maintainer. Greyed out by the same refusals the job's action asks.

require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISInventoryPaneContextMenu"
require "Vehicles/TimedActions/ISPathFindAction"
local SolarMaintainer = require "RenewableEnergy/Gadgets/SolarMaintainer"
local VehicleJobs = require "RenewableEnergy/Gadgets/VehicleJobs"
local ArrowBoard = require "RenewableEnergy/ArrowBoard/Trailer"
local Format = require "RenewableEnergy/UI/Format"
local JobOptions = require "cf_commonlib/JobOptions"

local VehicleMenu = {}

-- Walks to the frame part's end of the trailer, then fixes it as the mechanics window's Repair
-- menu does (ISInventoryPaneContextMenu.onFix), which walks nowhere.
local function queueFixFrame(item, playerNum, fixingNum, fixerNum, part)
    local character = getSpecificPlayer(playerNum)
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(character, part:getVehicle(), part:getArea()))
    ISInventoryPaneContextMenu.onFix(item, playerNum, fixingNum, fixerNum, part)
end

--- Seal Cracked Panel for each cracked panel of an arrow board trailer, listing what the seal
--- takes and greyed out when the character can't do it; a panel sealed as far as sealing goes,
--- greyed out saying to reglaze its module, as a placed panel's Seal Cracked Module.
function VehicleMenu.addSealPanelOptions(playerNum, context, vehicle)
    if not ArrowBoard.isTrailer(vehicle) then
        return
    end
    for _, partId in ipairs(ArrowBoard.PANELS) do
        local part = vehicle:getPartById(partId)
        if part and ArrowBoard.crackLookOf(part) then
            JobOptions.add(context, playerNum, VehicleJobs, VehicleJobs.SEAL_PANEL, vehicle, partId,
                getText("ContextMenu_RenewableEnergy_RepairPanel", getText("IGUI_VehiclePart" .. partId), Format.partCondition(part)))
        end
    end
end

--- Repair Frame for each dented end of an arrow board trailer's frame: vanilla's fixing menu for
--- the part, the one the mechanics window gives a car's body.
function VehicleMenu.addFrameRepairOptions(playerNum, context, vehicle)
    for _, frame in ipairs(ArrowBoard.damagedFrame(vehicle)) do
        local part = frame.part
        local item = part:getInventoryItem()
        local submenu, option = JobOptions.addSubMenu(context,
            getText("ContextMenu_RenewableEnergy_RepairFrame", getText(frame.name), Format.partCondition(part)))
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
    local detach = JobOptions.add(context, playerNum, VehicleJobs, VehicleJobs.DETACH_MAINTAINER, vehicle)
    if detach then
        return detach
    end
    local maintainer = getSpecificPlayer(playerNum):getInventory():getFirstTypeRecurse(SolarMaintainer.ITEM)
    return maintainer and JobOptions.add(context, playerNum, VehicleJobs, VehicleJobs.ATTACH_MAINTAINER, vehicle, maintainer)
        or nil
end

-- The vehicle under the mouse, as vanilla's own vehicle menu picks it, rather than a clicked object.
local function vehicleUnderMouse()
    return IsoObjectPicker.Instance:PickVehicle(getMouseXScaled(), getMouseYScaled())
end

VehicleMenu.onFill = JobOptions.onWorldMenu(vehicleUnderMouse, function(context, playerNum, character, vehicle)
    VehicleMenu.addVehicleOptions(playerNum, context, vehicle)
end)

return VehicleMenu
