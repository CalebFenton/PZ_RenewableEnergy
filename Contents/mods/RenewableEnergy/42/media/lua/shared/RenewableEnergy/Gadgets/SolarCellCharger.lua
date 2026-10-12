require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"

-- The Solar Battery Charger: a small panel over a tray of four vanilla batteries (Base.Battery),
-- the only cell that lamps, radios and flashlights take. Placed outdoors, it charges them in
-- daylight.
--
-- It is a placed tile with a container. The container's filter is not saved with it, so it is
-- set again whenever the tile loads or is placed, on every side; the authority also keeps the
-- places of the chargers it has seen, to charge them.
RenewableEnergy = RenewableEnergy or {}
local SolarCellCharger = {}
RenewableEnergy.SolarCellCharger = SolarCellCharger

SolarCellCharger.BATTERY = "Base.Battery"
SolarCellCharger.SLOTS = 4
-- Watt-hours that fill one Base.Battery. A game figure, not a cell's: it makes a set of four
-- take one to two sunny summer days at the default sunlight.
SolarCellCharger.BATTERY_WH = 25

local ACCEPT_FUNCTION = "RenewableEnergy.SolarCellCharger.acceptItem"
-- The charger's watt-hours not yet a whole use of a battery; uses are whole steps.
local STORED_KEY = "RenewableEnergy_storedWh"
-- MapObjects keeps one function per sprite and priority.
local LOAD_PRIORITY = 7

-- Place key -> { x, y, z } of every charger the authority has seen.
local places = {}

local function placeKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

function SolarCellCharger.isCharger(isoObject)
    return isoObject ~= nil and RenewableEnergy.Sprites.kindOf(isoObject:getTextureName()) == "cellCharger"
end

function SolarCellCharger.acceptItem(container, item)
    return item:getFullType() == SolarCellCharger.BATTERY and container:getItems():size() < SolarCellCharger.SLOTS
end

function SolarCellCharger.findOn(square)
    return RenewableEnergy.findObjectOn(square, SolarCellCharger.isCharger)
end

local function adopt(isoObject)
    local container = isoObject:getContainer()
    if container then
        container:setAcceptItemFunction(ACCEPT_FUNCTION)
    end
    if not isClient() then
        places[placeKey(isoObject:getX(), isoObject:getY(), isoObject:getZ())] =
            { x = isoObject:getX(), y = isoObject:getY(), z = isoObject:getZ() }
    end
end

MapObjects.OnLoadWithSprite(RenewableEnergy.Sprites.cellCharger, adopt, LOAD_PRIORITY)

Events.OnObjectAdded.Add(function(isoObject)
    if SolarCellCharger.isCharger(isoObject) then
        adopt(isoObject)
    end
end)

local function emptiestBattery(container)
    local emptiest
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == SolarCellCharger.BATTERY and item:getCurrentUsesFloat() < 1
            and (not emptiest or item:getCurrentUsesFloat() < emptiest:getCurrentUsesFloat()) then
            emptiest = item
        end
    end
    return emptiest
end

-- Adds `hours` of the panel's current output to the batteries in `charger`, one use at a
-- time to the emptiest, so a set fills evenly. Authority only. Returns the uses it added.
function SolarCellCharger.charge(charger, hours)
    local container = charger:getContainer()
    local square = charger:getSquare()
    if not (container and square and square:isOutside()) then
        return 0
    end
    local data = charger:getModData()
    local stored = (data[STORED_KEY] or 0)
        + RenewableEnergy.Sun.panelWatts(RenewableEnergy.Specs.cellChargerWatts, "flat") * hours
    local added = 0
    local battery = emptiestBattery(container)
    while battery do
        local useWh = battery:getUseDelta() * SolarCellCharger.BATTERY_WH
        if stored < useWh then
            break
        end
        battery:setCurrentUsesFloat(battery:getCurrentUsesFloat() + battery:getUseDelta())
        -- syncItemFields reaches only a player's inventory; this reaches a placed container.
        sendItemStats(battery)
        stored = stored - useWh
        added = added + 1
        battery = emptiestBattery(container)
    end
    -- Full batteries take nothing, and a panel stores nothing for later.
    data[STORED_KEY] = battery and stored or 0
    return added
end

-- Charges every charger the authority has seen whose square is loaded. One whose square is
-- unloaded is dropped; MapObjects reports it again when its chunk loads.
function SolarCellCharger.chargeAll(hours)
    for key, place in pairs(places) do
        local square = getCell():getGridSquare(place.x, place.y, place.z)
        local charger = SolarCellCharger.findOn(square)
        if charger then
            SolarCellCharger.charge(charger, hours)
        else
            places[key] = nil
        end
    end
end

return SolarCellCharger
