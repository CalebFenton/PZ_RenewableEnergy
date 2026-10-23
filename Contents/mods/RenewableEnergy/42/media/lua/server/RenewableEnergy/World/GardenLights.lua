if isClient() then
    return
end

require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Chance"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/World/WorldSpawns"
require "RenewableEnergy/World/BuildingWatch"

-- Solar garden lights along the front paths of houses. Each house is rolled once, when its
-- chunk first loads and its surroundings with it (BuildingWatch), so the lights differ between
-- playthroughs and a house never gets them twice. How likely a house is to have them depends on
-- its neighbourhood: the map zones that vanilla's loot reads (ItemPickerJava forceForZones
-- matches a zone's type or name). A solar site promises its house lights, which the house then
-- gets for certain when it is rolled.

RenewableEnergy = RenewableEnergy or {}
local GardenLights = {}
RenewableEnergy.GardenLights = GardenLights

local Sprites = RenewableEnergy.Sprites
local WorldSpawns = RenewableEnergy.WorldSpawns
local SolarGardenLight = RenewableEnergy.SolarGardenLight
local BuildingWatch = RenewableEnergy.BuildingWatch
local Chance = RenewableEnergy.Chance

-- Global ModData, by building key: the number of lights a rolled house got, or PROMISED for a
-- house a solar site promised lights that isn't rolled yet. Saved, so a promise outlives a quit
-- before the house's surroundings load.
GardenLights.MOD_DATA = "RenewableEnergyGardenLights"
GardenLights.PROMISED = true

-- Chance a house has lights, by neighbourhood, before the Garden Lights option. Farms count as
-- ordinary: B42's map marks most farmhouses as town, so a farm zone can't pick them out.
GardenLights.CHANCE = { rich = 0.4, ordinary = 0.15, poor = 0.04 }
GardenLights.COUNT = { min = 2, max = 6 }

-- Zone types and names of each neighbourhood. A rich zone outranks a poor one.
local RICH = { Rich = true, StreetRich = true }
local POOR = { Poor = true, StreetPoor = true, TrailerPark = true }

-- How far down the path from a door the lights go.
local PATH_LENGTH = 4
-- Squares out from a house's bounds that a light may stand on, and that must be loaded before the
-- house is rolled: beside the far end of a path that starts at a doorstep, one square out.
GardenLights.REACH = 1 + PATH_LENGTH

local function store()
    return ModData.getOrCreate(GardenLights.MOD_DATA)
end

function GardenLights.isRolled(def)
    return type(store()[BuildingWatch.key(def)]) == "number"
end

--- Promises the house lights: when it is rolled, it gets them for certain. A house already
--- rolled keeps what its roll gave.
function GardenLights.promise(def)
    local rolled, key = store(), BuildingWatch.key(def)
    if rolled[key] == nil then
        rolled[key] = GardenLights.PROMISED
    end
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

-- Finding squares

local SIDES = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- Where a light may stand: open ground (BuildingWatch.isOpenGround) without a light on it.
local function canStand(square)
    return SolarGardenLight.canPlaceOn(square) and BuildingWatch.isOpenGround(square)
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

-- Up to `count` squares for lights: either side of the path from each door, nearest the door
-- first, then any free square around the house.
local function frontSquares(def, count)
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

-- Rolling

-- Places GardenLights.COUNT charged lights along the house's front, as many as find room.
-- Returns how many it placed.
local function place(def)
    local count = Chance.between(GardenLights.COUNT.min, GardenLights.COUNT.max)
    local charged = { [SolarGardenLight.CHARGE_KEY] = RenewableEnergy.Specs.gardenLight.wh }
    local squares = frontSquares(def, count)
    for _, square in ipairs(squares) do
        WorldSpawns.placeMoveable(square, Sprites.gardenLight.off, charged)
    end
    return #squares
end

--- Rolls a house once: with its chance, or for certain when it was promised lights, it gets them.
--- Returns how many it got; a house rolled before gets none.
function GardenLights.roll(def)
    local key = BuildingWatch.key(def)
    local rolled = store()
    if GardenLights.isRolled(def) then
        return 0
    end
    local placed = 0
    if rolled[key] == GardenLights.PROMISED or Chance.hit(GardenLights.chanceFor(def)) then
        placed = place(def)
    end
    rolled[key] = placed
    return placed
end

-- Houses, and whatever a solar site promised lights, that haven't been rolled.
BuildingWatch.watch(function(def)
    local roll = store()[BuildingWatch.key(def)]
    return roll == GardenLights.PROMISED or (roll == nil and def:isResidential())
end, GardenLights.roll, GardenLights.REACH)

return GardenLights
