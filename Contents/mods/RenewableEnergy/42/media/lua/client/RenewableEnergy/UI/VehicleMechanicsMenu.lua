-- The vehicle mechanics window's menu for a part. For a car's engine: Take Out Alternator and Put
-- Back Alternator, beside vanilla's Take Engine Parts, the other job inside the engine bay. Picking
-- one goes about it as vanilla's engine jobs do (ISVehicleMechanics.onTakeEngineParts): out of the
-- car, to the engine, the hood unlocked and opened if shut and closed again after, the wrench in
-- hand as a part's uninstall holds it (ISVehiclePartMenu.equipRequiredItems).
-- For an empty battery slot: the deep cycle battery under Install while the character has one,
-- beside the car battery the slot's script lists, which the deep cycle battery isn't (see
-- VehicleBattery). Vanilla greys out the one battery its slot takes, and a second greyed line for a
-- battery few players carry would only read as a slot that takes it instead. Picking one runs
-- vanilla's own install (ISVehiclePartMenu.onInstallPart), with the slot's tools, time and hood.

require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISInventoryPaneContextMenu"
require "Vehicles/ISUI/ISVehicleMechanics"
require "Vehicles/ISUI/ISVehicleMenu"
require "Vehicles/TimedActions/ISPathFindAction"
require "Vehicles/TimedActions/ISOpenVehicleDoor"
require "Vehicles/TimedActions/ISCloseVehicleDoor"
require "Vehicles/TimedActions/ISUnlockVehicleDoor"
local CarAlternator = require "RenewableEnergy/Gadgets/CarAlternator"
local VehicleBattery = require "RenewableEnergy/Gadgets/VehicleBattery"
local VehicleJobs = require "RenewableEnergy/Gadgets/VehicleJobs"
local Action = require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local Format = require "RenewableEnergy/UI/Format"
local Items = require "cf_commonlib/Items"
local Needs = require "cf_commonlib/Needs"

local CarAlternatorMenu = {}

local function jobOf(putBack)
    return putBack and VehicleJobs.PUT_BACK_ALTERNATOR or VehicleJobs.TAKE_OUT_ALTERNATOR
end

local function isWrench(item)
    return item:hasTag(ItemTag.WRENCH) and Items.notBroken(item)
end

--- Queues `character`'s Take Out Alternator (`item` nil) or Put Back Alternator with `item` on
--- `vehicle`, with the walk, the hood and the wrench around it.
function CarAlternatorMenu.queue(character, vehicle, item)
    if character:getVehicle() then
        ISVehicleMenu.onExit(character)
    end
    if item then
        ISInventoryPaneContextMenu.transferIfNeeded(character, item)
    end
    local engine = CarAlternator.enginePart(vehicle)
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(character, vehicle, engine:getArea()))
    ISWorldObjectContextMenu.equip(character, character:getPrimaryHandItem(), isWrench, true)
    local hood = CarAlternator.shutHood(vehicle)
    if hood then
        -- The hood is unlocked when any door or window is (VehicleUtils.RequiredKeyNotFound).
        if hood:getDoor():isLocked() and VehicleUtils.RequiredKeyNotFound(engine, character) then
            ISTimedActionQueue.add(ISUnlockVehicleDoor:new(character, hood))
        end
        ISTimedActionQueue.add(ISOpenVehicleDoor:new(character, vehicle, hood))
    end
    ISTimedActionQueue.add(Action:new(character, "vehicle", jobOf(item ~= nil), vehicle, item))
    if hood then
        ISTimedActionQueue.add(ISCloseVehicleDoor:new(character, vehicle, hood))
    end
end

--- Adds Take Out Alternator, or Put Back Alternator where it is out, to `context` for `vehicle`,
--- listing what it takes and greyed out while `character` can't. Returns the option, or nil for a
--- vehicle whose alternator can't come out (a wreck, a trailer).
function CarAlternatorMenu.addOption(context, character, vehicle)
    if not CarAlternator.isCar(vehicle) then
        return nil
    end
    local putBack = CarAlternator.isOut(vehicle)
    local item = putBack and character:getInventory():getFirstTypeRecurse(CarAlternator.ITEM) or nil
    local option = context:addOption(getText(putBack and "IGUI_RenewableEnergy_PutBackAlternator"
        or "IGUI_RenewableEnergy_TakeOutAlternator"), character, CarAlternatorMenu.queue, vehicle, item)
    Needs.show(option, VehicleJobs.needs(character, jobOf(putBack), vehicle, item),
        CarAlternator.blocker(character, vehicle, putBack))
    return option
end

-- Adds the deep cycle batteries `mechanics.chr` has to the Install submenu that
-- `mechanics:doPartContextMenu` built for `part` in `mechanics.context`. Vanilla builds no submenu
-- when the slot is full or can't be worked on now, and then there is nothing to add to.
local function addInstallOptions(mechanics, part)
    if not VehicleBattery.isBatteryPart(part) or part:getInventoryItem() then
        return
    end
    local install = mechanics.context:getOptionFromName(getText("IGUI_Install"))
    local subMenu = install and install.subOption and mechanics.context:getSubMenu(install.subOption)
    if not subMenu then
        return
    end
    local character = mechanics.chr
    local fullType = VehicleBattery.ITEM
    local items = VehicleUtils.getItems(character:getPlayerNum())[fullType]
    if not items then
        return
    end
    local script = getItem(fullType)
    local option = subMenu:addOption(getItemName(fullType), character, nil)
    option.iconTexture = script and script:getNormalTexture()
    mechanics:doMenuTooltip(part, option, "install", fullType)
    local itemMenu = ISContextMenu:getNew(subMenu)
    mechanics.context:addSubMenu(option, itemMenu)
    for _, item in ipairs(items) do
        local itemOption = itemMenu:addOption(Format.withShare(item:getDisplayName(),
            Format.conditionShare(item:getFullType(), item:getCondition())), character,
            ISVehiclePartMenu.onInstallPart, part, item)
        itemOption.itemForTexture = item
        mechanics:doMenuTooltip(part, itemOption, "install", fullType)
    end
end

local vanillaDoPartContextMenu = ISVehicleMechanics.doPartContextMenu

function ISVehicleMechanics:doPartContextMenu(part, x, y)
    vanillaDoPartContextMenu(self, part, x, y)
    -- Vanilla returns before building a menu while the game is paused or the character sits in
    -- the vehicle (unless debug or an admin); self.context is then the last menu, closed.
    if not (self.context and self.context:getIsVisible()) then
        return
    end
    if part:getId() == CarAlternator.ENGINE then
        CarAlternatorMenu.addOption(self.context, self.chr, part:getVehicle())
    else
        addInstallOptions(self, part)
    end
end

return CarAlternatorMenu
