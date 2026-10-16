-- A Fridge Compressor plugged in where there is power inflates tires as a tire pump does: the
-- mechanics window asks getTirePump whether to offer Inflate Tire, and ISInflateTire works with
-- whatever item it is given. A real pump still comes first.

require "Vehicles/ISUI/ISVehicleMechanics"
require "Vehicles/ISUI/ISVehiclePartMenu"
require "RenewableEnergy/Biogas/Digester"

local Digester = RenewableEnergy.Digester

local function poweredCompressor(player, square)
    if square and square:haveElectricity() then
        return player:getInventory():getFirstTypeRecurse(Digester.COMPRESSOR)
    end
    return nil
end

local getTirePump = ISVehicleMechanics.getTirePump
function ISVehicleMechanics:getTirePump(player)
    return getTirePump(self, player) or poweredCompressor(player, player:getCurrentSquare())
end

-- Vanilla's option equips and uses a TirePump only, so with none this queues the same with the
-- compressor.
local onInflateTire = ISVehiclePartMenu.onInflateTire
function ISVehiclePartMenu.onInflateTire(playerObj, part)
    local vehicle = part:getVehicle()
    local compressor = not playerObj:getInventory():contains("TirePump", true)
        and poweredCompressor(playerObj, vehicle:getSquare())
    if not compressor then
        return onInflateTire(playerObj, part)
    end
    if playerObj:getVehicle() then
        ISVehicleMenu.onExit(playerObj)
    end
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, vehicle, part:getArea()))
    ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), compressor, true)
    local psiTarget = part:getContainerCapacity() + 5
    if round(part:getContainerContentAmount(), 2) < part:getContainerCapacity() then
        psiTarget = part:getContainerCapacity()
    end
    ISTimedActionQueue.add(ISInflateTire:new(playerObj, part, compressor, psiTarget))
end
