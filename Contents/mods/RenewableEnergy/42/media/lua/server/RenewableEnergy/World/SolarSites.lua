if isClient() then
    return
end

require "RenewableEnergy/Chance"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/World/WorldSpawns"
require "RenewableEnergy/World/BuildingWatch"
require "RenewableEnergy/World/GardenLights"
require "RenewableEnergy/World/ArrowBoard"
require "RenewableEnergy/World/RuralFinds"
require "RenewableEnergy/PowerBank/Commands"
require "RenewableEnergy/GasLine/GasLines"
local LOCATIONS = require "RenewableEnergy/World/SolarSiteLocations"

-- The named sites (SolarSiteLocations.lua): solar, and the homestead power of wind farms, dairy
-- farms and preppers. A world rolls each site once, by its name, against the Solar Sites option,
-- picks which of its spots the site uses, and keeps each of them as a global object, which the
-- game saves and hands back when its chunk loads (SGlobalObjects.chunkLoaded). The object goes
-- down then, stocked, and the spot is forgotten, so nothing is ever placed twice. A spot whose
-- square no longer takes what it places, such as a tree grown or a player's things there, is kept
-- and tried again each time its chunk loads. A site added to the list later is rolled the first
-- time a world that lacks it loads.

RenewableEnergy = RenewableEnergy or {}
local SolarSites = {}
RenewableEnergy.SolarSites = SolarSites

local WorldSpawns, RuralFinds = RenewableEnergy.WorldSpawns, RenewableEnergy.RuralFinds
local BuildingWatch, PowerBank = RenewableEnergy.BuildingWatch, RenewableEnergy.PowerBank
local Chance = RenewableEnergy.Chance

SolarSites.SYSTEM_NAME = "RenewableEnergySolarSites"

-- What each kind of site puts at its spots: how many of its panel spots it uses, how many
-- modules each panel holds (a mount's full load if not given), the BANK_STOCK of its bank, the
-- CRATE_STOCK of its crate, and whether its house gets garden lights. A homestead kind has a
-- RuralFinds find, worn as the countryside leaves one: `wind`, a wind charger wired to a bank of
-- that BANK_STOCK; `gas`, a gas source of that find piped to a generator with the Gas Conversion
-- Kit; and `pamphlet`, a FEMA pamphlet in a container of its house.
SolarSites.KINDS = {
    stockTank = { panels = { min = 1, max = 1 }, modules = { min = 1, max = 2 } },
    farmRoof = { panels = { min = 2, max = 4 }, bank = "farmHouse", gardenLights = true },
    camper = { panels = { min = 1, max = 2 }, bank = "camper" },
    relay = { panels = { min = 2, max = 2 }, bank = "relay" },
    powerYard = { panels = { min = 2, max = 2 }, bank = "powerYard", crate = "powerYard" },
    ranger = { panels = { min = 2, max = 4 }, bank = "ranger" },
    roadWorks = {},
    checkpoint = {},
    windFarm = { wind = "windFarm" },
    homestead = { gas = "digester" },
    prepper = { gas = "gasifier", pamphlet = true },
}

-- A homestead's generator: run down, its condition from min to max, and a little petrol left in
-- its tank, in litres.
SolarSites.GENERATOR = { condition = { min = 25, max = 50 }, fuel = { min = 0.5, max = 2 } }

-- The sites a world that saved `rolled` as true stands for: it rolled every site at once. A
-- development save from before the Louisville checkpoints were listed counts them rolled too, and
-- never gets them. Each name must stay a site's name: a renamed site would be rolled again there.
SolarSites.ROLLED_AT_ONCE = {
    "Pasture north of Rosewood", "Pasture south-east of Rosewood", "Pasture west of Muldraugh",
    "Pasture north-west of Muldraugh", "Pasture west of West Point", "Pasture by Valley Station",
    "Pasture by Brandenburg", "Farm south of Riverside", "Farm east of Rosewood", "Barn west of West Point",
    "Scenic Grove Trailer Park", "Dixie Trailer Park", "Bright Valley Trailer Park", "Camp Fitzgerald cabin",
    "Relay shed north of Brandenburg", "Relay shed by Irvington", "Relay hut west of Irvington",
    "Relay station west of Riverside", "Deer Valley Power yard", "Deerhead Lake ranger station",
    "Doe Valley ranger station", "Road works north of Muldraugh", "Road works east of Riverside",
    "Road works in Rosewood", "Checkpoint on the highway south of Louisville",
    "Checkpoint on the road south-east of Louisville", "Checkpoint on the road east of Louisville",
}

-- A mount of SolarSiteLocations to its kind (a Sprites and Specs.mounts key) and its material.
local MOUNTS = {
    flat = { kind = "flat" },
    wallMetal = { kind = "wall", material = "metal" },
    rackMetal = { kind = "rack", material = "metal" },
    rackWood = { kind = "rack", material = "wood" },
}

---@type SGlobalObjectSystem?
local system

--- The sites of every map the world is made of.
function SolarSites.sites()
    local sites = {}
    for map in string.gmatch(getWorld():getMap(), "[^;]+") do
        for _, site in ipairs(LOCATIONS[map] or {}) do
            table.insert(sites, site)
        end
    end
    return sites
end

--- The kind of a SolarSiteLocations mount: a Sprites and Specs.mounts key.
function SolarSites.mountKind(mount)
    return MOUNTS[mount].kind
end

--- The tile of a SolarSiteLocations mount facing `facing`.
function SolarSites.mountSprite(mount, facing)
    local spec = MOUNTS[mount]
    local sprite = RenewableEnergy.Sprites[spec.kind]
    return spec.material and sprite[spec.material][facing] or sprite
end

local function moduleCount(kind, mount)
    local range = SolarSites.KINDS[kind].modules
    if range then
        return Chance.between(range.min, range.max)
    end
    return RenewableEnergy.Specs.mounts[SolarSites.mountKind(mount)].modules
end

-- Placing

-- The square at the far end of a spot's line (`toX`, `toY`, `toZ`), or nil while it isn't loaded.
local function farEnd(spot)
    return getSquare(spot.toX, spot.toY, spot.toZ)
end

-- A homestead's generator on `square`: plugged into the house, run down and nearly dry, off.
local function placeGenerator(square)
    local spec = SolarSites.GENERATOR
    -- On a server the new generator goes to the clients at once, and each setter after that syncs.
    local generator = IsoGenerator.new(instanceItem("Base.Generator"), square:getCell(), square)
    generator:setConnected(true)
    generator:setCondition(Chance.between(spec.condition.min, spec.condition.max))
    generator:setFuel(Chance.within(spec.fuel.min, spec.fuel.max))
    return generator
end

-- A free floor square in a room, where a bank or a crate stands; nil if the square is one, else why
-- not.
local function notFreeIndoors(square)
    if not (PowerBank.canPlaceBank(square) and square:isFree(false)) then
        return "no free floor indoors"
    end
end

-- What a spot (its global object's modData) puts down on its square, by its `what`. A spot that
-- `waits` is placed at the next minute once `ready(square, spot)`, if given, says all it needs is
-- loaded: vehicles can't safely join the world while their chunk is still loading, and a line's
-- two ends may lie in different chunks. `refuses(square, spot)`, if given, says why what stands
-- on its squares now keeps it out, or nil; on open ground that is RuralFinds' rule, indoors a free
-- floor. A mount on a roof or a wall goes where the map gives it. Its `place` returns whether the
-- game took it. A refused spot is kept and retried when its chunk next loads.
local SPOTS = {
    panel = {
        refuses = function(square, spot)
            if MOUNTS[spot.mount].kind == "rack" and not RuralFinds.canStand(square) then
                return "no open ground for a rack"
            end
        end,
        place = function(square, spot)
            local modules = WorldSpawns.siteModules(moduleCount(spot.siteKind, spot.mount))
            WorldSpawns.placePanel(square, SolarSites.mountSprite(spot.mount, spot.facing), modules)
            return true
        end,
    },
    bank = {
        refuses = notFreeIndoors,
        place = function(square, spot) return WorldSpawns.placeBank(square, spot.stock) ~= nil end,
    },
    crate = {
        refuses = notFreeIndoors,
        place = function(square, spot)
            WorldSpawns.placeCrate(square, spot.stock)
            return true
        end,
    },
    -- The promise is saved with the house's garden light rolls, so it outlives a quit before the
    -- house's surroundings load, and the house's one roll keeps it.
    gardenLights = {
        place = function(square)
            local building = square:getBuilding()
            if building then
                RenewableEnergy.GardenLights.promise(building:getDef())
            end
            return true
        end,
    },
    arrowBoard = {
        waits = true,
        place = function(square, spot) return RenewableEnergy.ArrowBoard.spawn(square, spot.facing) ~= nil end,
    },
    -- The wind charger on its square and the bank it is wired to at the far end.
    windCharger = {
        waits = true,
        ready = function(_, spot) return farEnd(spot) ~= nil end,
        refuses = function(square, spot)
            if not RuralFinds.canPlace("wind", square) then
                return "no open ground for a wind charger"
            end
            return notFreeIndoors(farEnd(spot))
        end,
        place = function(square, spot)
            local bankSquare = farEnd(spot)
            RuralFinds.placeAt("wind", square)
            if WorldSpawns.placeBank(bankSquare, spot.stock) then
                local ok, why = RenewableEnergy.Commands.connectSource(nil,
                    { bank = PowerBank.positionOf(bankSquare), source = PowerBank.positionOf(square) })
                if not ok then
                    print("RenewableEnergy: the wind charger at " .. square:getX() .. "," .. square:getY() .. " stays unwired: " .. tostring(why))
                end
            end
            return true
        end,
    },
    -- The gas source (`source`, a RuralFinds find) on its square and its generator at the far end.
    gasLine = {
        waits = true,
        ready = function(_, spot) return farEnd(spot) ~= nil end,
        refuses = function(square, spot)
            if not RuralFinds.canPlace(spot.source, square) then
                return "no open ground for a " .. spot.source
            end
            if not RuralFinds.canStand(farEnd(spot)) then
                return "no open ground for the generator"
            end
        end,
        place = function(square, spot)
            local source = RuralFinds.placeAt(spot.source, square)
            RenewableEnergy.GasLines.fit(placeGenerator(farEnd(spot)), source)
            return true
        end,
    },
    -- Waits for the whole house to load, so that every container is there to choose from.
    pamphlet = {
        waits = true,
        ready = function(square)
            local building = square:getBuilding()
            return building == nil or BuildingWatch.surroundingsLoaded(building:getDef())
        end,
        place = function(square)
            local building = square:getBuilding()
            if building then
                RuralFinds.leavePamphlet(building:getDef())
            end
            return true
        end,
    },
}

-- Places the spot on its square and forgets it, unless what stands there now refuses it or the
-- game doesn't take it; a refused spot says why in the log.
local function placeSpot(object, square, spot)
    local kind = SPOTS[spot.what]
    local why = kind.refuses and kind.refuses(square, spot)
    if why then
        print("RenewableEnergy: the " .. spot.what .. " spot at " .. square:getX() .. "," .. square:getY() .. ","
            .. square:getZ() .. " waits: " .. why)
    elseif kind.place(square, spot) then
        system:removeObject(object)
    end
end

-- Rolling

local function addSpot(x, y, z, fields)
    if system:getObjectAt(x, y, z) then
        return
    end
    local modData = system:newObject(x, y, z):getModData()
    for key, value in pairs(fields) do
        modData[key] = value
    end
end

-- `count` of the list's entries, picked at random.
local function pickSome(list, count)
    local left, picked = {}, {}
    for i, entry in ipairs(list) do
        left[i] = entry
    end
    for _ = 1, math.min(count, #left) do
        table.insert(picked, table.remove(left, Chance.between(1, #left)))
    end
    return picked
end

--- Keeps the spots a site uses as global objects, to be placed when their chunks load. A find
--- counts as the find of the buildings it stands by, and a wind charger also of the building its
--- bank stands in, from now on (RuralFinds.claim), since their own roll can come before the spot
--- is placed.
function SolarSites.addSite(site)
    local kind = SolarSites.KINDS[site.kind]
    if kind.panels then
        local count = Chance.between(kind.panels.min, kind.panels.max)
        for _, panel in ipairs(pickSome(site.panels, count)) do
            addSpot(panel[1], panel[2], panel[3], { what = "panel", siteKind = site.kind, mount = panel[4], facing = panel[5] })
        end
    end
    if kind.bank then
        addSpot(site.bank[1], site.bank[2], site.bank[3], { what = "bank", stock = kind.bank })
    end
    if kind.crate then
        addSpot(site.crate[1], site.crate[2], site.crate[3], { what = "crate", stock = kind.crate })
    end
    if kind.gardenLights then
        addSpot(site.house[1], site.house[2], 0, { what = "gardenLights" })
    end
    if site.arrowBoard then
        local spot = site.arrowBoard
        addSpot(spot[1], spot[2], spot[3], { what = "arrowBoard", facing = spot[4] })
    end
    if kind.wind then
        local at, bank = site.windCharger, site.bank
        addSpot(at[1], at[2], at[3], { what = "windCharger", stock = kind.wind, toX = bank[1], toY = bank[2], toZ = bank[3] })
        RuralFinds.claim("wind", at[1], at[2])
        RuralFinds.claim("wind", bank[1], bank[2])
    end
    if kind.gas then
        local at, generator = site[kind.gas], site.generator
        addSpot(at[1], at[2], at[3],
            { what = "gasLine", source = kind.gas, toX = generator[1], toY = generator[2], toZ = generator[3] })
        RuralFinds.claim(kind.gas, at[1], at[2])
    end
    if kind.pamphlet then
        addSpot(site.house[1], site.house[2], 0, { what = "pamphlet" })
    end
end

-- By site name, the sites the world has rolled: the system's `rolled`.
local function rolledSites()
    local modData = system:getModData()
    if type(modData.rolled) ~= "table" then
        local rolled = {}
        if modData.rolled == true then
            for _, name in ipairs(SolarSites.ROLLED_AT_ONCE) do
                rolled[name] = true
            end
        end
        modData.rolled = rolled
    end
    return modData.rolled
end

--- The chance the world places the site when it rolls it: the Solar Sites option, or certain for
--- an `always` site; the option at 0 leaves out `always` sites too.
function SolarSites.siteChance(site)
    local chance = SandboxVars.RenewableEnergy.SolarSites / 100
    return (chance > 0 and site.always) and 1 or chance
end

--- Rolls each of `sites` (the world's, if not given) that the world hasn't rolled yet, at its
--- SolarSites.siteChance, and keeps it rolled whether or not it came up.
function SolarSites.rollNew(sites)
    local rolled = rolledSites()
    for _, site in ipairs(sites or SolarSites.sites()) do
        if not rolled[site.name] then
            rolled[site.name] = true
            if Chance.hit(SolarSites.siteChance(site)) then
                SolarSites.addSite(site)
            end
        end
    end
end

-- The spots that wait for the next minute, each { x, y, z, spot }.
local waiting = {}

-- Places each waiting spot that is ready. One whose square has unloaded leaves the queue until
-- its chunk loads again.
local function placeWaiting()
    for i = #waiting, 1, -1 do
        local entry = waiting[i]
        local object = system:getObjectAt(entry.x, entry.y, entry.z)
        local square = getSquare(entry.x, entry.y, entry.z)
        local kind = SPOTS[entry.spot.what]
        if not (object and square) then
            table.remove(waiting, i)
        elseif not kind.ready or kind.ready(square, entry.spot) then
            table.remove(waiting, i)
            placeSpot(object, square, entry.spot)
        end
    end
end

-- Places and forgets every spot in the chunk that needn't wait.
local function placeChunk(wx, wy)
    local objects = system:getObjectsInChunk(wx, wy)
    for i = objects:size() - 1, 0, -1 do
        local object = objects:get(i)
        local x, y, z = object:getX(), object:getY(), object:getZ()
        -- A copy: removeObject wipes the object's modData (GlobalObject.Reset).
        local spot = {}
        for key, value in pairs(object:getModData()) do
            spot[key] = value
        end
        local square = getSquare(x, y, z)
        if SPOTS[spot.what].waits then
            table.insert(waiting, { x = x, y = y, z = z, spot = spot })
        elseif square then
            placeSpot(object, square, spot)
        end
    end
    system:finishedWithList(objects)
end

--- The spot waiting at a square, or nil: its global object's modData.
function SolarSites.spotAt(x, y, z)
    local object = system:getObjectAt(x, y, z)
    return object and object:getModData()
end

-- Called by SGlobalObjectSystem.chunkLoaded with the system's modData as self.
local function onChunkLoaded(_self, wx, wy)
    placeChunk(wx, wy)
end

-- SGlobalObjectSystem throws for a system without this; the spots concern only the server.
local function getInitialStateForClient()
    return nil
end

local function onSGlobalObjectSystemInit()
    system = SGlobalObjects.registerSystem(SolarSites.SYSTEM_NAME)
    system:setModDataKeys({ "rolled" })
    system:setObjectModDataKeys({ "what", "siteKind", "mount", "facing", "stock", "source", "toX", "toY", "toZ" })
    local modData = system:getModData()
    modData.OnChunkLoaded = onChunkLoaded
    modData.getInitialStateForClient = getInitialStateForClient
    SolarSites.rollNew()
end

Events.OnSGlobalObjectSystemInit.Add(onSGlobalObjectSystemInit)
Events.EveryOneMinute.Add(placeWaiting)

return SolarSites
