require "RenewableEnergy/PlaceTracker"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/Battery"

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

function SolarCellCharger.isCharger(isoObject)
    return isoObject ~= nil and RenewableEnergy.Sprites.kindOf(RenewableEnergy.Sprites.nameOf(isoObject)) == "cellCharger"
end

function SolarCellCharger.acceptItem(container, item)
    return item:getFullType() == SolarCellCharger.BATTERY and container:getItems():size() < SolarCellCharger.SLOTS
end

function SolarCellCharger.findOn(square)
    return RenewableEnergy.findObjectOn(square, SolarCellCharger.isCharger)
end

local function setFilter(isoObject)
    local container = isoObject:getContainer()
    if container then
        container:setAcceptItemFunction(ACCEPT_FUNCTION)
    end
end

-- Every side needs the filter, but only the authority charges.
local chargers = RenewableEnergy.PlaceTracker.new({
    sprites = { RenewableEnergy.Sprites.cellCharger },
    matches = SolarCellCharger.isCharger,
    onFound = setFilter,
    keepPlaces = not isClient(),
})

local function isCell(item)
    return item:getFullType() == SolarCellCharger.BATTERY
end

-- Adds `hours` of the panel's output under `sky` (Sun.skyNow, now if nil) to the batteries in
-- `charger`, one use at a time to the emptiest, so a set fills evenly. Authority only. Returns
-- the uses it added.
function SolarCellCharger.charge(charger, hours, sky)
    local container = charger:getContainer()
    if not container then
        return 0
    end
    local Battery = RenewableEnergy.Battery
    local data = charger:getModData()
    local stored = (data[STORED_KEY] or 0)
        + RenewableEnergy.Sun.squareWatts(charger:getSquare(), RenewableEnergy.Specs.cellChargerWatts, sky) * hours
    local added = 0
    local battery = Battery.emptiestIn(container, isCell)
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
        battery = Battery.emptiestIn(container, isCell)
    end
    -- Full batteries take nothing, and a panel stores nothing for later.
    data[STORED_KEY] = battery and stored or 0
    return added
end

-- Charges every loaded charger the authority has seen.
function SolarCellCharger.chargeAll(hours)
    local sky = RenewableEnergy.Sun.skyNow()
    chargers:each(function(charger)
        SolarCellCharger.charge(charger, hours, sky)
    end)
end
