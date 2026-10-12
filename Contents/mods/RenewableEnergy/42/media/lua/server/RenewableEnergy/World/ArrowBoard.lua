require "Vehicles/VehicleDistributions"
require "VehicleZoneDefinition"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/World/WorldSpawns"

-- The solar arrow board trailer (scripts/RenewableEnergy/Vehicles.txt): a highway work-zone
-- trailer with a lamp board and two panels, its batteries in a lockable box on the tongue. It
-- turns up among junkyard and traffic jam wrecks and with tradesmen's vans, and at the road
-- works of SolarSites.lua. Its battery box is stocked the first time the trailer spawns, from
-- Distributions' OnFillContainer. Its panels charge the batteries in the box in daylight, wherever
-- it stands or is towed (GadgetCharging runs it).

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

-- What its battery box holds: the panels' modules, the second often cracked; deep cycle
-- batteries, charged by Distributions.chargeFoundBatteries; a charge controller.
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
    local batteries = WorldSpawns.rollBetween(stock.batteries)
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

-- The battery in the box with the lowest charge that isn't full, or nil.
local function emptiestBattery(container)
    local Battery = RenewableEnergy.Battery
    local emptiest
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if Battery.nominalWh(item) > 0 and Battery.getCharge(item) < 1
            and (not emptiest or Battery.getCharge(item) < Battery.getCharge(emptiest)) then
            emptiest = item
        end
    end
    return emptiest
end

--- Adds `hours` of its panels' current output to the batteries in its battery box, the emptiest
--- first, so that a mixed set fills evenly. The panels count as flat, since the trailer may face
--- any way, and make nothing under a roof. Authority only. Returns the watt-hours stored.
---@param vehicle BaseVehicle
function ArrowBoard.charge(vehicle, hours)
    if vehicle:getScriptName() ~= ArrowBoard.SCRIPT then
        return 0
    end
    local square = vehicle:getSquare()
    local part = vehicle:getPartById(ArrowBoard.BATTERY_BOX)
    local container = part and part:getItemContainer()
    if not (container and square and square:isOutside()) then
        return 0
    end
    local Battery = RenewableEnergy.Battery
    local wh = RenewableEnergy.Sun.panelWatts(RenewableEnergy.Specs.arrowBoardWatts, "flat") * hours
    local stored = 0
    local battery = wh > 0 and emptiestBattery(container)
    while battery do
        local before = Battery.getCharge(battery)
        local room = (1 - before) * Battery.nominalWh(battery)
        local added = math.min(wh, room)
        -- Exactly full when it fills, so the loop moves on to the next battery.
        Battery.setCharge(battery, added == room and 1 or before + added / Battery.nominalWh(battery))
        -- As the maintainer does: clients hear of the charge once it shows at two decimals.
        if VehicleUtils.compareFloats(before, Battery.getCharge(battery), 2) then
            sendItemStats(battery)
        end
        wh, stored = wh - added, stored + added
        battery = wh > 0 and emptiestBattery(container)
    end
    return stored
end

return ArrowBoard
