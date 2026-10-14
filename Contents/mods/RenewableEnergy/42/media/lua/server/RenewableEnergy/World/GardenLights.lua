if isClient() then
    return
end

require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/World/WorldSpawns"

-- Solar garden lights along the front paths of houses. Each house is rolled once, the first
-- time its chunk loads, so the lights differ between playthroughs and a house never gets them
-- twice. How likely a house is to have them depends on its neighbourhood: the map zones that
-- vanilla's loot reads (ItemPickerJava forceForZones matches a zone's type or name).
--
-- A house is rolled once the squares around it are loaded, which the chunk that brought it in
-- doesn't promise, so the houses its chunks bring in wait in `pending` until then.

RenewableEnergy = RenewableEnergy or {}
local GardenLights = {}
RenewableEnergy.GardenLights = GardenLights

local SolarGardenLight = RenewableEnergy.SolarGardenLight

-- Global ModData: the lights each rolled house got, by building key.
GardenLights.MOD_DATA = "RenewableEnergyGardenLights"

-- Chance a house has lights, by neighbourhood, before the Garden Lights option. Farms count as
-- ordinary: B42's map marks most farmhouses as town, so a farm zone can't pick them out.
GardenLights.CHANCE = { rich = 0.4, ordinary = 0.15, poor = 0.04 }
GardenLights.COUNT = { min = 2, max = 6 }

-- Zone types and names of each neighbourhood. A rich zone outranks a poor one.
local RICH = { Rich = true, StreetRich = true }
local POOR = { Poor = true, StreetPoor = true, TrailerPark = true }

-- Squares out from a house's bounds that a light may stand on, and that must be loaded first.
local REACH = 4
-- How far down the path from a door the lights go.
local PATH_LENGTH = 4

-- Building key -> BuildingDef of houses waiting for their surroundings to load.
local pending = {}

local function store()
    return ModData.getOrCreate(GardenLights.MOD_DATA)
end

function GardenLights.buildingKey(def)
    return def:getX() .. "," .. def:getY()
end

--- Whether the house was rolled already.
function GardenLights.isRolled(def)
    return store()[GardenLights.buildingKey(def)] ~= nil
end

--- The neighbourhood at a square: "rich", "poor" or "ordinary".
function GardenLights.neighbourhood(x, y)
    local zones = getWorld():getMetaGrid():getZonesAt(x, y, 0)
    local found = "ordinary"
    for i = 0, zones:size() - 1 do
        local zone = zones:get(i)
        local zoneType, name = zone:getType(), zone:getName()
        if RICH[zoneType] or RICH[name] then
            return "rich"
        elseif POOR[zoneType] or POOR[name] then
            found = "poor"
        end
    end
    return found
end

--- The chance that this house has lights, with the Garden Lights option.
function GardenLights.chanceFor(def)
    local x = math.floor((def:getX() + def:getX2()) / 2)
    local y = math.floor((def:getY() + def:getY2()) / 2)
    return GardenLights.CHANCE[GardenLights.neighbourhood(x, y)] * SandboxVars.RenewableEnergy.GardenLights / 100
end

-- Finding squares ------------------------------------------------------------------------------

local SIDES = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function isStreet(square)
    local name = RenewableEnergy.Sprites.nameOf(square:getFloor()) or ""
    return string.find(name, "^floors_exterior_street") ~= nil or string.find(name, "^blends_street") ~= nil
end

-- Where a light may stand: open ground outdoors, off the road, not in water or a tree.
local function canStand(square)
    return square ~= nil and SolarGardenLight.canPlaceOn(square) and square:getRoom() == nil
        and square:hasFloor() and square:isFree(false) and not square:HasTree()
        and not square:getProperties():has(IsoFlagType.water) and not isStreet(square)
        and SolarGardenLight.findOn(square) == nil
end

local function inHouse(square, def)
    local building = square and square:getBuilding()
    return building ~= nil and building:getDef() == def
end

-- Outdoor squares just outside the house's doors, each with the direction leading away.
local function doorsteps(def)
    local found = {}
    for x = def:getX() - 1, def:getX2() do
        for y = def:getY() - 1, def:getY2() do
            local square = getSquare(x, y, 0)
            if square and square:getRoom() == nil then
                for _, side in ipairs(SIDES) do
                    local inside = getSquare(x - side[1], y - side[2], 0)
                    if inHouse(inside, def) and square:getDoorTo(inside) then
                        table.insert(found, { x = x, y = y, dx = side[1], dy = side[2] })
                    end
                end
            end
        end
    end
    return found
end

--- Up to `count` squares for lights: either side of the path from each door, nearest the door
--- first, then any free square around the house.
function GardenLights.frontSquares(def, count)
    local chosen, taken = {}, {}
    local function take(x, y)
        local key = x .. "," .. y
        local square = getSquare(x, y, 0)
        if #chosen < count and not taken[key] and canStand(square) then
            taken[key] = true
            table.insert(chosen, square)
        end
    end
    for _, step in ipairs(doorsteps(def)) do
        taken[step.x .. "," .. step.y] = true
        for along = 0, PATH_LENGTH do
            local x, y = step.x + step.dx * along, step.y + step.dy * along
            taken[x .. "," .. y] = true
            take(x + step.dy, y + step.dx)
            take(x - step.dy, y - step.dx)
        end
    end
    for x = def:getX() - 1, def:getX2() do
        take(x, def:getY2())
        take(x, def:getY() - 1)
    end
    for y = def:getY() - 1, def:getY2() do
        take(def:getX2(), y)
        take(def:getX() - 1, y)
    end
    return chosen
end

-- Rolling ----------------------------------------------------------------------------------------

--- Places GardenLights.COUNT charged lights along the house's front, as many as find room.
--- Returns how many it placed.
function GardenLights.place(def)
    local count = RenewableEnergy.WorldSpawns.rollBetween(GardenLights.COUNT)
    local charged = { [SolarGardenLight.CHARGE_KEY] = RenewableEnergy.Specs.gardenLight.wh }
    local squares = GardenLights.frontSquares(def, count)
    for _, square in ipairs(squares) do
        RenewableEnergy.WorldSpawns.placeMoveable(square, RenewableEnergy.Sprites.gardenLight.off, charged)
    end
    return #squares
end

--- Rolls a house once: with its chance, or for certain when `always`, it gets lights. Returns
--- how many it got; a house rolled before gets none.
function GardenLights.roll(def, always)
    local key = GardenLights.buildingKey(def)
    if store()[key] ~= nil then
        return 0
    end
    local placed = 0
    if always or ZombRandFloat(0, 1) < GardenLights.chanceFor(def) then
        placed = GardenLights.place(def)
    end
    store()[key] = placed
    pending[key] = nil
    return placed
end

-- Squares along a chunk's side (IsoChunkMap.CHUNK_SIZE_IN_SQUARES).
local CHUNK_SIZE = 8

-- Whether every chunk that the house's REACH touches is loaded: one square per chunk tells. The
-- loaded area around several players needn't be a rectangle, so each chunk is checked.
local function surroundingsLoaded(def)
    local fromX, toX = math.floor((def:getX() - REACH) / CHUNK_SIZE), math.floor((def:getX2() + REACH) / CHUNK_SIZE)
    local fromY, toY = math.floor((def:getY() - REACH) / CHUNK_SIZE), math.floor((def:getY2() + REACH) / CHUNK_SIZE)
    for cx = fromX, toX do
        for cy = fromY, toY do
            if not getSquare(cx * CHUNK_SIZE, cy * CHUNK_SIZE, 0) then
                return false
            end
        end
    end
    return true
end

--- Rolls the house once its surroundings load, for certain when `always`. `x`, `y` is a square of
--- the house in the chunk that brought it in: once that chunk unloads, the house leaves the queue
--- until the chunk loads again and brings it back. A house that is certain stays, since nothing
--- would bring back its certainty; there are only as many as there are solar sites.
function GardenLights.queue(def, always, x, y)
    local key = GardenLights.buildingKey(def)
    if store()[key] == nil then
        pending[key] = { def = def, always = always, x = not always and x or nil, y = y }
    end
end

local function onLoadChunk(chunk)
    -- A house covers many of the chunk's squares; each is looked at once.
    local seen = {}
    for x = 0, CHUNK_SIZE - 1 do
        for y = 0, CHUNK_SIZE - 1 do
            local square = chunk:getGridSquare(x, y, 0)
            local building = square and square:getBuilding()
            local def = building and building:getDef()
            if def and not seen[def] then
                seen[def] = true
                if def:isResidential() and not pending[GardenLights.buildingKey(def)] then
                    GardenLights.queue(def, false, square:getX(), square:getY())
                end
            end
        end
    end
end

-- Rolling a house and its chunk unloading both remove it from `pending`, so the houses are
-- collected first.
local function rollLoaded()
    local ready, gone
    for key, entry in pairs(pending) do
        if entry.x and not getSquare(entry.x, entry.y, 0) then
            gone = gone or {}
            table.insert(gone, key)
        elseif surroundingsLoaded(entry.def) then
            ready = ready or {}
            table.insert(ready, entry)
        end
    end
    if gone then
        for _, key in ipairs(gone) do
            pending[key] = nil
        end
    end
    if ready then
        for _, entry in ipairs(ready) do
            GardenLights.roll(entry.def, entry.always)
        end
    end
end

Events.LoadChunk.Add(onLoadChunk)
-- A minute is soon enough: houses load at the edge of the loaded area, out of sight.
Events.EveryOneMinute.Add(rollLoaded)

return GardenLights
