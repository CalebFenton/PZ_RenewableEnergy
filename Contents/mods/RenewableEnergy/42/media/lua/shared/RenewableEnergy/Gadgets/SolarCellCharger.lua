-- The Solar Battery Charger: a small panel over a tray of vanilla batteries (Base.Battery), the
-- only cell that lamps, radios and flashlights take. Placed outdoors, it charges them in daylight.
--
-- It is a placed tile with a container. The container's filter is not saved with it, so it is
-- set again whenever the tile loads or is placed, on every side; the authority also keeps the
-- places of the chargers it has seen, and charges them
-- (server/RenewableEnergy/Gadgets/SolarCellChargerServer.lua).

local RenewableEnergy = require "RenewableEnergy/Utilities"
local PlaceTracker = require "RenewableEnergy/PlaceTracker"
local Sprites = require "RenewableEnergy/Sprites"

local SolarCellCharger = {}
RenewableEnergy.SolarCellCharger = SolarCellCharger

SolarCellCharger.ITEM = "RenewableEnergy.SolarCellCharger"
SolarCellCharger.BATTERY = "Base.Battery"
SolarCellCharger.SLOTS = 4
-- Object modData: the charger's watt-hours not yet a whole use of a battery.
SolarCellCharger.STORED_KEY = "RenewableEnergy_storedWh"

-- The container's filter. The game finds it by this path (ItemContainer.getAcceptItemFunction),
-- so acceptItem must stay reachable from the global table.
local ACCEPT_FUNCTION = "RenewableEnergy.SolarCellCharger.acceptItem"

function SolarCellCharger.isCharger(isoObject)
    return Sprites.kindOfObject(isoObject) == "cellCharger"
end

--- Whether `item` is a cell the charger takes.
function SolarCellCharger.isCell(item)
    return item:getFullType() == SolarCellCharger.BATTERY
end

function SolarCellCharger.acceptItem(container, item)
    return SolarCellCharger.isCell(item) and container:getItems():size() < SolarCellCharger.SLOTS
end

local function adoptContainer(isoObject)
    RenewableEnergy.adoptContainer(isoObject:getContainer(), ACCEPT_FUNCTION)
end

-- Every side needs the filter, but only the authority charges, so only it keeps places.
local chargers = PlaceTracker.new({
    sprites = { Sprites.cellCharger },
    matches = SolarCellCharger.isCharger,
    onFound = adoptContainer,
    keepPlaces = not isClient(),
})

--- Calls `fn(charger)` for every loaded charger the authority has seen. Authority only.
function SolarCellCharger.eachLoaded(fn)
    chargers:each(fn)
end

return SolarCellCharger
