-- Take Out Alternator and Put Back Alternator in the vehicle mechanics window's menu for a car's
-- engine, beside vanilla's Take Engine Parts, the other job inside the engine bay. Picking one
-- goes about it as vanilla's engine jobs do (ISVehicleMechanics.onTakeEngineParts): out of the
-- car, to the engine, the hood unlocked and opened if shut and closed again after, the wrench in
-- hand as a part's uninstall holds it (ISVehiclePartMenu.equipRequiredItems).

require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISInventoryPaneContextMenu"
require "Vehicles/ISUI/ISVehicleMechanics"
require "Vehicles/ISUI/ISVehicleMenu"
require "Vehicles/TimedActions/ISPathFindAction"
require "Vehicles/TimedActions/ISOpenVehicleDoor"
require "Vehicles/TimedActions/ISCloseVehicleDoor"
require "Vehicles/TimedActions/ISUnlockVehicleDoor"
require "RenewableEnergy/Gadgets/CarAlternator"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/Needs"

RenewableEnergy = RenewableEnergy or {}
local CarAlternatorMenu = {}
RenewableEnergy.CarAlternatorMenu = CarAlternatorMenu

local Action = RenewableEnergyAction
local CarAlternator, Needs = RenewableEnergy.CarAlternator, RenewableEnergy.Needs

local function isWrench(item)
    return item:hasTag(ItemTag.WRENCH) and RenewableEnergy.notBroken(item)
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
    ISTimedActionQueue.add(Action:new(character, item and Action.PUT_BACK_ALTERNATOR or Action.TAKE_OUT_ALTERNATOR, nil, nil,
        vehicle, item))
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
    Needs.show(option, CarAlternator.needs(character, putBack), CarAlternator.blocker(character, vehicle, putBack))
    return option
end

local vanillaDoPartContextMenu = ISVehicleMechanics.doPartContextMenu

function ISVehicleMechanics:doPartContextMenu(part, x, y)
    vanillaDoPartContextMenu(self, part, x, y)
    -- Vanilla returns before building a menu while the game is paused or the character sits in
    -- the vehicle (unless debug or an admin); self.context is then the last menu, closed.
    if part:getId() == CarAlternator.ENGINE and self.context and self.context:getIsVisible() then
        CarAlternatorMenu.addOption(self.context, self.chr, part:getVehicle())
    end
end

return CarAlternatorMenu
