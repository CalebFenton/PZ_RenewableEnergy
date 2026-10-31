-- Worn homestead installations left by rural buildings: an old wind charger by a barn, a barrel
-- digester by livestock buildings, a primitive gasifier by a hunting shack. Each is built the way
-- the build menu builds it, then put in worn states the mod already has, so the player repairs it
-- with the existing jobs. Each qualifying building is rolled once, as GardenLights rolls houses:
-- when its chunk first loads and the squares around it with it (BuildingWatch), kept in global
-- ModData. The odds follow the Solar Sites option (0 turns them off). A solar site's find counts
-- as the find of the buildings it stands by, so they aren't rolled for a second one.
--
-- Also adds RE's books and gadgets to vanilla's barn and survivalist camp story clutter.

if isClient() then return end

require "RandomizedWorldContent/StoryTable_Initialization"
local Utilities = require "RenewableEnergy/Utilities"
local Sprites = require "RenewableEnergy/Sprites"
local Wind = require "RenewableEnergy/Wind"
local WindSource = require "RenewableEnergy/PowerBank/WindSource"
local Gasifier = require "RenewableEnergy/WoodGas/Gasifier"
local DigesterSystem = require "RenewableEnergy/Biogas/DigesterSystem"
local GasifierSystem = require "RenewableEnergy/WoodGas/GasifierSystem"
local Place = require "RenewableEnergy/World/Place"
local BuildingWatch = require "RenewableEnergy/World/BuildingWatch"
local Chance = require "cf_commonlib/Chance"
local Items = require "cf_commonlib/Items"
local Squares = require "cf_commonlib/Squares"
local Tables = require "cf_commonlib/Tables"

local RuralFinds = {}

-- Global ModData: by building key, the finds each rolled building got ({ [kind] = true }).
RuralFinds.MOD_DATA = "RenewableEnergyRuralFinds"
-- The Solar Sites percentage at which each find's odds are 1 in `odds`.
local SITES_DEFAULT = 75
-- Chance a find's building also holds the reading that built it: the hunting shack's gasifier the
-- FEMA plans, the livestock building's digester Homestead Power #3.
local READING_CHANCE = 0.5
RuralFinds.PAMPHLET = "RenewableEnergy.FemaPamphlet"
RuralFinds.BIOGAS_MAGAZINE = "RenewableEnergy.HomesteadPowerMag3"
-- Containers no one leaves reading in: most of a barn's are feed troughs.
local NOT_FOR_READING = { trough = true, composter = true }

local function keepsReading(object)
    local container = object:getContainer()
    return container ~= nil and not NOT_FOR_READING[container:getType()]
end

local function store()
    return ModData.getOrCreate(RuralFinds.MOD_DATA)
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

local function randomOf(entries)
    local list = {}
    for _, value in pairs(entries) do
        table.insert(list, value)
    end
    table.sort(list)
    return Chance.pick(list)
end

--- Leaves `fullType` in a container of the building, or on the floor of one of its rooms if it
--- has none to keep it in, as most barns don't; returns whether it did. An unexplored container
--- keeps it: its loot is rolled on first look (ItemPickerJava.fillContainer,
--- RequestItemsForContainerPacket), which only adds items.
function RuralFinds.leaveReading(def, fullType)
    local floors = {}
    for z = 0, BuildingWatch.HIGHEST_LEVEL do
        local holder = BuildingWatch.eachSquare(def, 0, z, function(square)
            local found = Squares.findObjectOn(square, keepsReading)
            if found then
                return found
            end
            if square and square:getRoom() and square:isFree(false) then
                table.insert(floors, square)
            end
        end)
        if holder then
            return Items.addItem(holder:getContainer(), fullType) ~= nil
        end
    end
    if #floors == 0 then
        return false
    end
    return Items.dropOn(Chance.pick(floors), fullType) ~= nil
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

--- Each find: `odds` (1 in odds per qualifying building at the default Solar Sites), whether a
--- building `qualifies`, how many squares out from the building it stands (`reach`) on open ground
--- that also `fits`, if given, `place(square)`, which builds it worn, and the `reading`, if any, a
--- building's roll may leave with it.
RuralFinds.FINDS = {
    wind = {
        odds = 15,
        qualifies = function(def) return hasRoom(def, FARM) end,
        reach = BuildingWatch.REACH,
        fits = inTheOpen,
        -- The old farm wind charger, its wooden blades long broken and its brake set.
        place = function(square)
            local charger = Place.entity(square, randomOf(Sprites.windCharger.propeller.wood), Wind.OnCreate)
            -- After the clients have the charger: the setters send its modData, which names it by
            -- its index on the square.
            WindSource.setBroken(charger, true)
            WindSource.setBraked(charger, true)
            return charger
        end,
    },
    digester = {
        odds = 20,
        qualifies = function(def) return hasRoom(def, LIVESTOCK) end,
        reach = 1,
        reading = RuralFinds.BIOGAS_MAGAZINE,
        -- Any drum, as the build menu takes any; bags torn, gone cold and sour.
        place = function(square)
            return Place.entity(square, randomOf(Sprites.digester.barrel), DigesterSystem.OnCreate,
                function(thumpable)
                    local digester = DigesterSystem.instance:getLuaObjectOnSquare(square)
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
        reach = 1,
        reading = RuralFinds.PAMPHLET,
        -- Put away dirty: its filter packing all tarred and its ash pit full.
        place = function(square)
            return Place.entity(square, Sprites.gasifier.primitive,
                GasifierSystem.OnCreate, function(thumpable)
                    local filter = Gasifier.filterOf(thumpable)
                    for _ = 1, 100 do
                        local tarry = instanceItem(Gasifier.TARRY)
                        local weight = filter:getContentsWeight() + tarry:getUnequippedWeight()
                        if weight > filter:getCapacity() + Utilities.EPSILON then
                            break
                        end
                        filter:AddItem(tarry)
                    end
                    local gasifier = GasifierSystem.instance:getLuaObjectOnSquare(square)
                    gasifier.ash = Gasifier.ASH_FULL
                    gasifier:afterChange()
                end)
        end,
    },
}
local KINDS = { "wind", "digester", "gasifier" }

--- Whether the find `kind` may stand on the square: open ground that fits it.
function RuralFinds.canPlace(kind, square)
    local find = RuralFinds.FINDS[kind]
    return RuralFinds.canStand(square) and (not find.fits or find.fits(square))
end

--- Why the find `kind` may not stand on the square, or nil if it may (RuralFinds.canPlace).
function RuralFinds.refusal(kind, square)
    if not RuralFinds.canPlace(kind, square) then
        return "no open ground for a " .. kind
    end
end

--- How far outside the building's bounds the square at x, y is, in squares (0 inside).
function RuralFinds.distanceOutside(def, x, y)
    return math.max(def:getX() - x, x - (def:getX2() - 1), def:getY() - y, y - (def:getY2() - 1), 0)
end

-- A random square the find `kind` may stand on within its reach of the building, or nil.
local function squareFor(def, kind)
    local found = {}
    BuildingWatch.eachSquare(def, RuralFinds.FINDS[kind].reach, 0, function(square)
        if RuralFinds.canPlace(kind, square) then
            table.insert(found, square)
        end
    end)
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
                local find = RuralFinds.FINDS[kind]
                placed[kind] = find.place(square)
                if find.reading and Chance.hit(READING_CHANCE) then
                    RuralFinds.leaveReading(def, find.reading)
                end
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
    local buildings = ArrayList.new()
    getWorld():getMetaGrid():getBuildingsIntersecting(x - reach, y - reach, 2 * reach + 1, 2 * reach + 1, buildings)
    return Tables.fromList(buildings, function(def)
        return RuralFinds.distanceOutside(def, x, y) <= reach and qualifies(def)
    end)
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

--- Builds the find `kind` on the square, worn, as a building's roll would. Only where it may
--- stand (RuralFinds.refusal nil). Returns it.
function RuralFinds.placeAt(kind, square)
    return RuralFinds.FINDS[kind].place(square)
end

-- Loading

-- With the option at 0 no building is rolled, so turning it up later still finds them unrolled.
BuildingWatch.watch({
    ledger = RuralFinds.MOD_DATA,
    wants = function(def)
        return SandboxVars.RenewableEnergy.SolarSites > 0 and #RuralFinds.findsFor(def) > 0
    end,
    roll = function(def) RuralFinds.roll(def) end,
})

-- Story clutter

-- Vanilla's barns, farm storerooms and survivalist camps dress themselves from these lists
-- (StoryClutter), refilled by StoryClutter.Init each time its file loads, which is once per game
-- the world loads; added through vanilla's own adder (StoryTables.addItemToClutterTable), which
-- puts each item in twice, vanilla's included. An item listed n times here gets n of those adds, so
-- is picked n times as often as an item added once (RandomizedWorldBase.getBarnClutterItem picks
-- uniformly).
local MAG3, MAG4 = RuralFinds.BIOGAS_MAGAZINE, "RenewableEnergy.HomesteadPowerMag4"
RuralFinds.CLUTTER = {
    getSurvivalistCampsiteClutter = { RuralFinds.PAMPHLET, "RenewableEnergy.SolarCellCharger" },
    getBarnClutter = { MAG3, MAG3, MAG3, MAG4, MAG4 },
    getFarmStorageClutter = { MAG3, MAG3, MAG4 },
}

local function addClutter()
    local base = getWorld():getRandomizedWorldBase()
    for getter, items in pairs(RuralFinds.CLUTTER) do
        local list = base[getter] and base[getter](base)
        if list then
            for _, item in ipairs(items) do
                StoryTables.addItemToClutterTable(list, item)
            end
        else
            print("RenewableEnergy: missing story clutter list " .. getter)
        end
    end
end

-- After vanilla's StoryClutter.Init, which clears the lists, and before any story is dressed.
Events.OnLoadedMapZones.Add(addClutter)

return RuralFinds
