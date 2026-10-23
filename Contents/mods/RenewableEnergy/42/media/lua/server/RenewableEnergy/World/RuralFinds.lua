if isClient() then
    return
end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Chance"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Wind"
require "RenewableEnergy/PowerBank/WindSource"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/Biogas/DigesterSystem"
require "RenewableEnergy/WoodGas/GasifierSystem"
require "RenewableEnergy/World/WorldSpawns"
require "RenewableEnergy/World/BuildingWatch"
require "RandomizedWorldContent/StoryTable_Initialization"

-- Worn homestead installations left by rural buildings: an old wind charger by a barn, a barrel
-- digester by livestock buildings, a primitive gasifier by a hunting shack. Each is built the way
-- the build menu builds it, then put in worn states the mod already has, so the player repairs it
-- with the existing jobs. Each qualifying building is rolled once, as GardenLights rolls houses:
-- when its chunk first loads and the squares around it with it (BuildingWatch), kept in global
-- ModData. The odds follow the Solar Sites option (0 turns them off). A solar site's find counts
-- as the find of the buildings it stands by, so they aren't rolled for a second one.
--
-- Also adds RE's books and gadgets to vanilla's barn and survivalist camp story clutter.

RenewableEnergy = RenewableEnergy or {}
local RuralFinds = {}
RenewableEnergy.RuralFinds = RuralFinds

local Sprites, Wind, Gasifier = RenewableEnergy.Sprites, RenewableEnergy.Wind, RenewableEnergy.Gasifier
local Digester = RenewableEnergy.Digester
local BuildingWatch, Chance = RenewableEnergy.BuildingWatch, RenewableEnergy.Chance

-- Global ModData: by building key, the finds each rolled building got ({ [kind] = true }).
RuralFinds.MOD_DATA = "RenewableEnergyRuralFinds"
-- The Solar Sites percentage at which each find's odds are 1 in `odds`.
local SITES_DEFAULT = 75
-- Chance the hunting shack also holds a FEMA pamphlet.
local PAMPHLET_CHANCE = 0.5
local PAMPHLET = "RenewableEnergy.FemaPamphlet"

local function store()
    return ModData.getOrCreate(RuralFinds.MOD_DATA)
end

--- The finds a building has, or nil if it was never rolled.
function RuralFinds.rolled(def)
    return store()[BuildingWatch.key(def)]
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

--- Open ground (BuildingWatch.isOpenGround) with nothing standing on it.
function RuralFinds.canStand(square)
    return BuildingWatch.isOpenGround(square) and square:getSpecialObjects():size() == 0
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

-- Building

--- Builds the entity of the tile `sprite` (RenewableEnergy.tileEntity) as ISBuildIsoEntity:create
--- does: a thumpable with its entity's components on the square, then the entity's OnCreate, and
--- sends it to the clients. `wear(thumpable)`, if given, sets its worn state before they get it.
function RuralFinds.build(square, sprite, onCreate, wear)
    local thumpable = IsoThumpable.new(square:getCell(), square, sprite, false, nil)
    GameEntityFactory.CreateIsoObjectEntity(thumpable, RenewableEnergy.tileEntity(sprite), true)
    square:AddSpecialObject(thumpable)
    thumpable:setExplored(true)
    onCreate({ thumpable = thumpable })
    if wear then
        wear(thumpable)
    end
    square:RecalcAllWithNeighbours(true)
    thumpable:transmitCompleteItemToClients()
    return thumpable
end
local build = RuralFinds.build

local function randomOf(entries)
    local list = {}
    for _, value in pairs(entries) do
        table.insert(list, value)
    end
    table.sort(list)
    return Chance.pick(list)
end

--- Leaves a pamphlet in a container of the building, if it has one; returns whether it did. An
--- unexplored container keeps it: its loot is rolled on first look (ItemPickerJava.fillContainer,
--- RequestItemsForContainerPacket), which only adds items.
function RuralFinds.leavePamphlet(def)
    for z = 0, BuildingWatch.HIGHEST_LEVEL do
        for x = def:getX(), def:getX2() - 1 do
            for y = def:getY(), def:getY2() - 1 do
                local square = getSquare(x, y, z)
                local objects = square and square:getObjects()
                for i = 0, (objects and objects:size() or 0) - 1 do
                    local container = objects:get(i):getContainer()
                    if container then
                        return RenewableEnergy.addItem(container, PAMPHLET) ~= nil
                    end
                end
            end
        end
    end
    return false
end

-- Finds

-- Farm outbuildings a wind charger would have powered: barns, and the hay and farm storage
-- sheds that stand without one.
local FARM = { barn = true, farmstorage = true, haystorage = true }
-- "stable" is the map's name; vanilla's RBBarn checks "stables". The map has no cattle pen
-- rooms: its cattle stand at the sale barn.
local LIVESTOCK = {
    barn = true, stable = true, stables = true, chickencoop = true, pigsty = true, cattleauction = true,
}

--- Each find: `odds` (1 in odds per qualifying building at the default Solar Sites), `is(object)`,
--- whether an object is one, whether a building `qualifies`, how many squares out from the
--- building it stands (`reach`) on open ground that also `fits`, if given, and `place(square,
--- def)`, which builds it worn.
RuralFinds.FINDS = {
    wind = {
        odds = 15,
        is = Wind.isCharger,
        qualifies = function(def) return hasRoom(def, FARM) end,
        reach = BuildingWatch.REACH,
        fits = inTheOpen,
        -- The old farm wind charger, its wooden blades long broken and its brake set.
        place = function(square)
            local charger = build(square, randomOf(Sprites.windPropeller.wood), Wind.OnCreate)
            -- After the clients have the charger: the setters send its modData, which names it by
            -- its index on the square.
            local WindSource = RenewableEnergy.WindSource
            WindSource.setBroken(charger, true)
            WindSource.setBraked(charger, true)
            return charger
        end,
    },
    digester = {
        odds = 20,
        is = Digester.isDigester,
        qualifies = function(def) return hasRoom(def, LIVESTOCK) end,
        reach = 1,
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
        is = Gasifier.isGasifier,
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
        reach = 1,
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
            if def and Chance.hit(PAMPHLET_CHANCE) then
                RuralFinds.leavePamphlet(def)
            end
            return thumpable
        end,
    },
}
local KINDS = { "wind", "digester", "gasifier" }

--- Whether the find `kind` may stand on the square: open ground that fits it.
function RuralFinds.canPlace(kind, square)
    local find = RuralFinds.FINDS[kind]
    return RuralFinds.canStand(square) and (not find.fits or find.fits(square))
end

--- How far outside the building's bounds the square at x, y is, in squares (0 inside).
function RuralFinds.distanceOutside(def, x, y)
    return math.max(def:getX() - x, x - (def:getX2() - 1), def:getY() - y, y - (def:getY2() - 1), 0)
end

-- A random square the find `kind` may stand on within its reach of the building, or nil.
local function squareFor(def, kind)
    local found, reach = {}, RuralFinds.FINDS[kind].reach
    for x = def:getX() - reach, def:getX2() + reach - 1 do
        for y = def:getY() - reach, def:getY2() + reach - 1 do
            local square = getSquare(x, y, 0)
            if RuralFinds.canPlace(kind, square) then
                table.insert(found, square)
            end
        end
    end
    return #found > 0 and Chance.pick(found) or nil
end

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

--- Rolls a building once for each of `kinds` (default the finds it qualifies for), at its chance.
--- Returns the placed objects by kind; a building rolled before gets none.
function RuralFinds.roll(def, kinds)
    local key = BuildingWatch.key(def)
    local rolled = store()
    if rolled[key] ~= nil then
        return {}
    end
    local found, placed = {}, {}
    for _, kind in ipairs(kinds or RuralFinds.findsFor(def)) do
        if Chance.hit(RuralFinds.chanceFor(kind)) then
            local square = squareFor(def, kind)
            if square then
                placed[kind] = RuralFinds.FINDS[kind].place(square, def)
                found[kind] = true
            end
        end
    end
    rolled[key] = found
    return placed
end

--- The buildings within BuildingWatch.REACH of x, y that could have the find `kind`. Reads the
--- map, so the buildings needn't be loaded.
function RuralFinds.buildingsBy(kind, x, y)
    local qualifies, reach = RuralFinds.FINDS[kind].qualifies, BuildingWatch.REACH
    local buildings, found = ArrayList.new(), {}
    getWorld():getMetaGrid():getBuildingsIntersecting(x - reach, y - reach, 2 * reach + 1, 2 * reach + 1, buildings)
    for i = 0, buildings:size() - 1 do
        local def = buildings:get(i)
        if RuralFinds.distanceOutside(def, x, y) <= reach and qualifies(def) then
            table.insert(found, def)
        end
    end
    return found
end

--- Counts a find of `kind` at x, y as the find of every building it stands by that could have one
--- (RuralFinds.buildingsBy), so none of them is rolled for another. A building rolled before keeps
--- its finds and gains this one.
function RuralFinds.claim(kind, x, y)
    local rolled = store()
    for _, def in ipairs(RuralFinds.buildingsBy(kind, x, y)) do
        local key = BuildingWatch.key(def)
        rolled[key] = rolled[key] or {}
        rolled[key][kind] = true
    end
end

--- Builds the find `kind` on the square, worn, as a building's roll would, if it may stand there.
--- Returns it, or nil and why not.
function RuralFinds.placeAt(kind, square)
    if not RuralFinds.canPlace(kind, square) then
        return nil, "no open ground for a " .. kind
    end
    return RuralFinds.FINDS[kind].place(square)
end

-- Loading

-- With the option at 0 no building is rolled, so turning it up later still finds them unrolled.
BuildingWatch.watch(function(def)
    return SandboxVars.RenewableEnergy.SolarSites > 0 and store()[BuildingWatch.key(def)] == nil
        and #RuralFinds.findsFor(def) > 0
end, function(def) RuralFinds.roll(def) end)

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

-- After vanilla's StoryClutter.Init, which clears the lists, and before any story is dressed.
Events.OnLoadedMapZones.Add(addClutter)

return RuralFinds
