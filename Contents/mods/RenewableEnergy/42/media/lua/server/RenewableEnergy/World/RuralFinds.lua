if isClient() then
    return
end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Wind"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/Biogas/DigesterSystem"
require "RenewableEnergy/WoodGas/GasifierSystem"
require "RenewableEnergy/World/WorldSpawns"
require "RandomizedWorldContent/StoryTable_Initialization"

-- Worn homestead installations left by rural buildings: an old wind charger by a barn, a barrel
-- digester by livestock buildings, a primitive gasifier by a hunting shack. Each is built the way
-- the build menu builds it, then put in worn states the mod already has, so the player repairs it
-- with the existing jobs. Each qualifying building is rolled once, as GardenLights rolls houses:
-- the first time its chunk loads, once the squares around it are loaded, kept in global ModData.
-- The odds follow the Solar Sites option (0 turns them off).
--
-- Also adds RE's books and gadgets to vanilla's barn and survivalist camp story clutter.

RenewableEnergy = RenewableEnergy or {}
local RuralFinds = {}
RenewableEnergy.RuralFinds = RuralFinds

local Sprites, Wind, Gasifier = RenewableEnergy.Sprites, RenewableEnergy.Wind, RenewableEnergy.Gasifier

-- Global ModData: by building key, the finds each rolled building got ({ [kind] = true }).
RuralFinds.MOD_DATA = "RenewableEnergyRuralFinds"
-- The Solar Sites percentage at which each find's odds are 1 in `odds`.
local SITES_DEFAULT = 75
-- Chance the hunting shack also holds a FEMA pamphlet.
RuralFinds.PAMPHLET_CHANCE = 0.5
local PAMPHLET = "RenewableEnergy.FemaPamphlet"
-- Squares out from a building's bounds a find may stand on, and that must be loaded first.
RuralFinds.REACH = 4
-- The highest level looked at for a building's rooms: a deer stand's one room is on level 1.
local HIGHEST = 1

-- Building key -> the building waiting for its surroundings to load.
local pending = {}

local function store()
    return ModData.getOrCreate(RuralFinds.MOD_DATA)
end

function RuralFinds.buildingKey(def)
    return def:getX() .. "," .. def:getY()
end

--- The finds a building has, or nil if it was never rolled.
function RuralFinds.rolled(def)
    return store()[RuralFinds.buildingKey(def)]
end

local function hasRoom(def, names)
    local rooms = def:getRooms()
    for i = 0, rooms:size() - 1 do
        if names[rooms:get(i):getName()] then
            return true
        end
    end
    return false
end

-- Squares

local function isStreet(square)
    local name = Sprites.nameOf(square:getFloor()) or ""
    return string.find(name, "^floors_exterior_street") ~= nil or string.find(name, "^blends_street") ~= nil
end

-- Open ground outdoors with nothing on it: off the road, not in water or a tree.
local function canStand(square)
    return square ~= nil and square:getZ() == 0 and square:getBuilding() == nil and square:isOutside()
        and square:hasFloor() and square:isFree(false) and not square:HasTree()
        and not square:getProperties():has(IsoFlagType.water) and not isStreet(square)
        and square:getSpecialObjects():size() == 0
end

-- Nothing stands within a square of it but open ground: no wall, building or tree, as a turbine
-- wants.
local function inTheOpen(square)
    for dx = -1, 1 do
        for dy = -1, 1 do
            local near = getSquare(square:getX() + dx, square:getY() + dy, 0)
            if not near or near:getBuilding() or near:HasTree() or near:getWall(true) or near:getWall(false) then
                return false
            end
        end
    end
    return true
end

-- A random square within `reach` of the building's bounds that `fits`, or nil.
local function squareBy(def, reach, fits)
    local found = {}
    for x = def:getX() - reach, def:getX2() + reach - 1 do
        for y = def:getY() - reach, def:getY2() + reach - 1 do
            local square = getSquare(x, y, 0)
            if canStand(square) and (not fits or fits(square)) then
                table.insert(found, square)
            end
        end
    end
    return #found > 0 and found[ZombRand(#found) + 1] or nil
end

-- Building

-- Builds the entity of the tile `sprite` (RenewableEnergy.tileEntity) as ISBuildIsoEntity:create
-- does: a thumpable with its entity's components on the square, then the entity's OnCreate.
-- `wear(thumpable)` sets its worn state before the clients get it.
local function build(square, sprite, onCreate, wear)
    local thumpable = IsoThumpable.new(square:getCell(), square, sprite, false, nil)
    GameEntityFactory.CreateIsoObjectEntity(thumpable, RenewableEnergy.tileEntity(sprite), true)
    square:AddSpecialObject(thumpable)
    thumpable:setExplored(true)
    onCreate({ thumpable = thumpable })
    wear(thumpable)
    square:RecalcAllWithNeighbours(true)
    thumpable:transmitCompleteItemToClients()
    return thumpable
end

local function randomOf(entries)
    local list = {}
    for _, value in pairs(entries) do
        table.insert(list, value)
    end
    table.sort(list)
    return list[ZombRand(#list) + 1]
end

-- A pamphlet in a container of the building, if it has one. An unexplored container keeps it: its
-- loot is rolled on first look (ItemPickerJava.fillContainer, RequestItemsForContainerPacket),
-- which only adds items.
local function leavePamphlet(def)
    for z = 0, HIGHEST do
        for x = def:getX(), def:getX2() - 1 do
            for y = def:getY(), def:getY2() - 1 do
                local square = getSquare(x, y, z)
                local objects = square and square:getObjects()
                for i = 0, (objects and objects:size() or 0) - 1 do
                    local container = objects:get(i):getContainer()
                    if container then
                        local item = container:AddItem(PAMPHLET)
                        if item and isServer() then
                            sendAddItemToContainer(container, item)
                        end
                        return item ~= nil
                    end
                end
            end
        end
    end
    return false
end

-- Finds

local BARN = { barn = true }
-- "stable" is the map's name; vanilla's RBBarn checks "stables".
local LIVESTOCK = { barn = true, stable = true, stables = true, chickencoop = true }

--- Each find: `odds` (1 in odds per qualifying building at the default Solar Sites), whether a
--- building `qualifies`, where it stands, and `place(square, def)`, which builds it worn.
RuralFinds.FINDS = {
    wind = {
        odds = 30,
        qualifies = function(def) return hasRoom(def, BARN) end,
        square = function(def) return squareBy(def, RuralFinds.REACH, inTheOpen) end,
        -- The old farm wind charger, its wooden blades long broken and its brake set.
        place = function(square)
            return build(square, randomOf(Sprites.windPropeller.wood),
                Wind.OnCreate, function(thumpable)
                    thumpable:getModData()[Wind.BROKEN] = true
                    thumpable:getModData()[Wind.BRAKED] = true
                end)
        end,
    },
    digester = {
        odds = 30,
        qualifies = function(def) return hasRoom(def, LIVESTOCK) end,
        square = function(def) return squareBy(def, 1) end,
        -- Any drum, as the build menu takes any; bags torn, gone cold and sour.
        place = function(square)
            local System = RenewableEnergy.DigesterSystem
            return build(square, randomOf(Sprites.digester.barrel), System.OnCreate,
                function(thumpable)
                    local digester = System.instance:getLuaObjectOnSquare(square)
                    digester.holderCondition = 0
                    digester.acid = digester:acidLimit()
                    digester.sour = true
                    digester:afterChange()
                end)
        end,
    },
    gasifier = {
        odds = 3,
        -- The map's hunting shacks and raised deer stands are buildings of hunting rooms only.
        qualifies = function(def)
            local rooms = def:getRooms()
            for i = 0, rooms:size() - 1 do
                if rooms:get(i):getName() ~= "hunting" then
                    return false
                end
            end
            return rooms:size() > 0
        end,
        square = function(def) return squareBy(def, 1) end,
        -- Put away dirty: its filter packing all tarred and its ash pit full.
        place = function(square, def)
            local System = RenewableEnergy.GasifierSystem
            local thumpable = build(square, Sprites.gasifier.primitive,
                System.OnCreate, function(thumpable)
                    local filter = Gasifier.filterOf(thumpable)
                    for _ = 1, 100 do
                        local tarry = instanceItem(Gasifier.TARRY)
                        if filter:getContentsWeight() + tarry:getUnequippedWeight() > filter:getCapacity() + 1e-4 then
                            break
                        end
                        filter:AddItem(tarry)
                    end
                    local gasifier = System.instance:getLuaObjectOnSquare(square)
                    gasifier.ash = Gasifier.ASH_FULL
                    gasifier:afterChange()
                end)
            if def and ZombRandFloat(0, 1) < RuralFinds.PAMPHLET_CHANCE then
                leavePamphlet(def)
            end
            return thumpable
        end,
    },
}
local KINDS = { "wind", "digester", "gasifier" }

--- The chance a qualifying building has the find `kind`, with the Solar Sites option.
function RuralFinds.chanceFor(kind)
    return SandboxVars.RenewableEnergy.SolarSites / SITES_DEFAULT / RuralFinds.FINDS[kind].odds
end

--- The finds the building qualifies for, by its rooms.
function RuralFinds.findsFor(def)
    local kinds = {}
    for _, kind in ipairs(KINDS) do
        if RuralFinds.FINDS[kind].qualifies(def) then
            table.insert(kinds, kind)
        end
    end
    return kinds
end

--- Rolls a building once for each find it qualifies for (or for `kinds`, which tests use), at its
--- chance or for certain when `always`. Returns the placed objects by kind; a building rolled
--- before gets none.
function RuralFinds.roll(def, kinds, always)
    local key = RuralFinds.buildingKey(def)
    local rolled = store()
    pending[key] = nil
    if rolled[key] ~= nil then
        return {}
    end
    local found, placed = {}, {}
    for _, kind in ipairs(kinds or RuralFinds.findsFor(def)) do
        local find = RuralFinds.FINDS[kind]
        if always or ZombRandFloat(0, 1) < RuralFinds.chanceFor(kind) then
            local square = find.square(def)
            if square then
                placed[kind] = find.place(square, def)
                found[kind] = true
            end
        end
    end
    rolled[key] = found
    return placed
end

-- Loading

local CHUNK_SIZE = getChunkSizeInSquares()

-- Whether every chunk within REACH of the building is loaded: one square per chunk tells.
function RuralFinds.surroundingsLoaded(def)
    local reach = RuralFinds.REACH
    local fromX, toX = math.floor((def:getX() - reach) / CHUNK_SIZE), math.floor((def:getX2() + reach) / CHUNK_SIZE)
    local fromY, toY = math.floor((def:getY() - reach) / CHUNK_SIZE), math.floor((def:getY2() + reach) / CHUNK_SIZE)
    for cx = fromX, toX do
        for cy = fromY, toY do
            if not getSquare(cx * CHUNK_SIZE, cy * CHUNK_SIZE, 0) then
                return false
            end
        end
    end
    return true
end

local function onLoadChunk(chunk)
    if SandboxVars.RenewableEnergy.SolarSites <= 0 then
        return
    end
    local seen, rolled = {}, store()
    for z = 0, HIGHEST do
        for x = 0, CHUNK_SIZE - 1 do
            for y = 0, CHUNK_SIZE - 1 do
                local square = chunk:getGridSquare(x, y, z)
                local building = square and square:getBuilding()
                local def = building and building:getDef()
                if def and not seen[def] then
                    seen[def] = true
                    local key = RuralFinds.buildingKey(def)
                    if rolled[key] == nil and not pending[key] and #RuralFinds.findsFor(def) > 0 then
                        pending[key] = { def = def, x = square:getX(), y = square:getY() }
                    end
                end
            end
        end
    end
end

-- A building whose chunk unloaded leaves the queue until it loads again.
local function rollLoaded()
    local ready, gone = {}, {}
    for key, entry in pairs(pending) do
        if not getSquare(entry.x, entry.y, 0) then
            table.insert(gone, key)
        elseif RuralFinds.surroundingsLoaded(entry.def) then
            table.insert(ready, entry.def)
        end
    end
    for _, key in ipairs(gone) do
        pending[key] = nil
    end
    for _, def in ipairs(ready) do
        RuralFinds.roll(def)
    end
end

-- Story clutter

-- Vanilla's barns and survivalist camps dress themselves from these lists (StoryClutter), refilled
-- by StoryClutter.Init when its file loads; added through vanilla's own adder
-- (StoryTables.addItemToClutterTable).
RuralFinds.CLUTTER = {
    getSurvivalistCampsiteClutter = { "RenewableEnergy.FemaPamphlet", "RenewableEnergy.SolarCellCharger" },
    getBarnClutter = { "RenewableEnergy.HomesteadPowerMag3", "RenewableEnergy.HomesteadPowerMag4" },
}

local function addClutter()
    local base = getWorld():getRandomizedWorldBase()
    for getter, items in pairs(RuralFinds.CLUTTER) do
        local list = base[getter] and base[getter](base)
        if list then
            for _, item in ipairs(items) do
                if not list:contains(item) then
                    StoryTables.addItemToClutterTable(list, item)
                end
            end
        else
            print("RenewableEnergy: no story clutter list " .. getter)
        end
    end
end

Events.LoadChunk.Add(onLoadChunk)
-- A minute is soon enough: buildings load at the edge of the loaded area, out of sight.
Events.EveryOneMinute.Add(rollLoaded)
-- After vanilla's StoryClutter.Init, which clears the lists, and before any story is dressed.
Events.OnLoadedMapZones.Add(addClutter)

return RuralFinds
