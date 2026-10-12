require "Vehicles/VehicleDistributions"
require "VehicleZoneDefinition"
require "RenewableEnergy/World/WorldSpawns"

-- The solar arrow board trailer (scripts/RenewableEnergy/Vehicles.txt): a highway work-zone
-- trailer with a lamp board and two panels, its batteries in a lockable box on the tongue. It
-- turns up among junkyard and traffic jam wrecks and with tradesmen's vans, and at the road
-- works of SolarSites.lua. Its battery box is stocked the first time the trailer spawns, from
-- Distributions' OnFillContainer.

RenewableEnergy = RenewableEnergy or {}
local ArrowBoard = {}
RenewableEnergy.ArrowBoard = ArrowBoard

-- Script name without its module, as VehicleDistributions and OnFillContainer name it.
ArrowBoard.VEHICLE = "RenewableEnergyArrowBoardTrailer"
ArrowBoard.SCRIPT = "Base." .. ArrowBoard.VEHICLE
ArrowBoard.BATTERY_BOX = "RenewableEnergyBatteryBox"

-- Its spawn weight among each vehicle zone's vehicles (VehicleZoneDistribution spawnChance).
-- The four traffic jam zones share one vehicle table. About 5 a map, with the road works.
ArrowBoard.ZONE_WEIGHTS = { junkyard = 4, trafficjamn = 4, trades = 2 }

-- What its battery box holds: two modules, the second often cracked; deep cycle batteries,
-- a count from min to max, charged by Distributions.chargeFoundBatteries; a charge controller.
ArrowBoard.STOCK = {
    modules = 2,
    secondCrackedChance = 0.6,
    batteries = { min = 4, max = 6 },
    battery = "RenewableEnergy.DeepCycleBattery",
    controllerChance = 1,
}

for zone, weight in pairs(ArrowBoard.ZONE_WEIGHTS) do
    VehicleZoneDistribution[zone].vehicles[ArrowBoard.SCRIPT] = { index = -1, spawnChance = weight }
end

-- An empty table for the box, so that randomizeContainers fills it and fires OnFillContainer.
VehicleDistributions[1][ArrowBoard.VEHICLE] = {
    Normal = { [ArrowBoard.BATTERY_BOX] = { rolls = 0, items = {} } },
}

--- Stocks the battery box of a freshly spawned arrow board, scaled by the loot rarity options.
--- Authority only.
---@param container ItemContainer
function ArrowBoard.stockBatteryBox(container)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local options = SandboxVars.RenewableEnergy
    local stock = ArrowBoard.STOCK
    for i = 1, WorldSpawns.scaled(stock.modules, options.LRMSolarPanels) do
        local cracked = i == 2 and ZombRandFloat(0, 1) < stock.secondCrackedChance
        WorldSpawns.addModule(container, cracked and WorldSpawns.crackedCondition() or WorldSpawns.weatheredCondition())
    end
    local batteries = ZombRand(stock.batteries.min, stock.batteries.max + 1)
    for _ = 1, WorldSpawns.scaled(batteries, options.LRMBatteries) do
        container:AddItem(stock.battery)
    end
    if ZombRandFloat(0, 1) < stock.controllerChance * options.LRMMisc then
        container:AddItem(RenewableEnergy.Specs.controller)
    end
end

--- OnFillContainer: stocks the container if it is an arrow board's battery box.
function ArrowBoard.stockIfBatteryBox(roomName, container)
    local part = roomName == ArrowBoard.VEHICLE and container:getVehiclePart()
    if part and part:getId() == ArrowBoard.BATTERY_BOX then
        ArrowBoard.stockBatteryBox(container)
    end
end

--- Spawns an arrow board on the square, its tongue pointing `facing` ("N", "E", "S" or "W").
--- Its battery box is stocked as it enters the world. Authority only.
---@return BaseVehicle?
function ArrowBoard.spawn(square, facing)
    return addVehicleDebug(ArrowBoard.SCRIPT, IsoDirections[facing], nil, square)
end

return ArrowBoard
