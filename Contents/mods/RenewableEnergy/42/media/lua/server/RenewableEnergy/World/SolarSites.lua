if isClient() then
    return
end

require "RenewableEnergy/Sprites"
require "RenewableEnergy/Specs"
require "RenewableEnergy/World/WorldSpawns"
require "RenewableEnergy/World/GardenLights"
require "RenewableEnergy/World/ArrowBoard"
local LOCATIONS = require "RenewableEnergy/World/SolarSiteLocations"

-- The named solar sites (SolarSiteLocations.lua). A new world rolls each site once against the
-- Solar Sites option, picks which of its spots the site uses, and keeps each of them as a global
-- object, which the game saves and hands back when its chunk first loads
-- (SGlobalObjects.chunkLoaded). The object goes down then, stocked, and the spot is forgotten,
-- so nothing is ever placed twice.

RenewableEnergy = RenewableEnergy or {}
local SolarSites = {}
RenewableEnergy.SolarSites = SolarSites

SolarSites.SYSTEM_NAME = "RenewableEnergySolarSites"

-- What each kind of site puts at its spots: how many of its panel spots it uses, how many
-- modules each panel holds (a mount's full load if not given), the BANK_STOCK of its bank, the
-- CRATE_STOCK of its crate, and whether its house gets garden lights.
SolarSites.KINDS = {
    stockTank = { panels = { min = 1, max = 1 }, modules = { min = 1, max = 2 } },
    farmRoof = { panels = { min = 2, max = 4 }, bank = "farmHouse", gardenLights = true },
    camper = { panels = { min = 1, max = 2 }, bank = "camper" },
    relay = { panels = { min = 2, max = 2 }, bank = "relay" },
    powerYard = { panels = { min = 2, max = 2 }, bank = "powerYard", crate = "powerYard" },
    ranger = { panels = { min = 2, max = 4 }, bank = "ranger" },
    roadWorks = {},
}

-- A mount of SolarSiteLocations to its tile, its kind and its material.
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

--- The tile of a SolarSiteLocations mount facing `facing`.
function SolarSites.mountSprite(mount, facing)
    local spec = MOUNTS[mount]
    local sprite = RenewableEnergy.Sprites[spec.kind]
    return spec.material and sprite[spec.material][facing] or sprite
end

local function moduleCount(kind, mount)
    local range = SolarSites.KINDS[kind].modules
    if range then
        return RenewableEnergy.WorldSpawns.rollBetween(range)
    end
    return RenewableEnergy.Specs.mounts[MOUNTS[mount].kind].modules
end

-- Placing ------------------------------------------------------------------------------------------

local PLACERS = {
    panel = function(square, spot)
        local modules = RenewableEnergy.WorldSpawns.siteModules(moduleCount(spot.siteKind, spot.mount))
        RenewableEnergy.WorldSpawns.placePanel(square, SolarSites.mountSprite(spot.mount, spot.facing), modules)
    end,
    bank = function(square, spot)
        RenewableEnergy.WorldSpawns.placeBank(square, spot.stock)
    end,
    crate = function(square, spot)
        RenewableEnergy.WorldSpawns.placeCrate(square, spot.stock)
    end,
    gardenLights = function(square)
        local building = square:getBuilding()
        if building then
            RenewableEnergy.GardenLights.queue(building:getDef(), true)
        end
    end,
    arrowBoard = function(square, spot)
        RenewableEnergy.ArrowBoard.spawn(square, spot.facing)
    end,
}

--- Puts down what a site spot holds (its global object's modData: what, siteKind, mount,
--- facing, stock) on its square.
function SolarSites.place(square, spot)
    PLACERS[spot.what](square, spot)
end

-- Rolling ------------------------------------------------------------------------------------------

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
        table.insert(picked, table.remove(left, ZombRand(#left) + 1))
    end
    return picked
end

--- Keeps the spots a site uses as global objects, to be placed when their chunks load.
function SolarSites.addSite(site)
    local kind = SolarSites.KINDS[site.kind]
    if kind.panels then
        local count = RenewableEnergy.WorldSpawns.rollBetween(kind.panels)
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
end

local function rollSites()
    local chance = SandboxVars.RenewableEnergy.SolarSites
    for _, site in ipairs(SolarSites.sites()) do
        if ZombRand(100) < chance then
            SolarSites.addSite(site)
        end
    end
end

-- Vehicles can't safely join the world while their chunk is still loading, so arrow boards wait
-- for the next minute, their spots kept until then.
local waitingArrowBoards = {}

local function placeWaitingArrowBoards()
    for i = #waitingArrowBoards, 1, -1 do
        local entry = table.remove(waitingArrowBoards, i)
        local object = system:getObjectAt(entry.x, entry.y, entry.z)
        local square = getSquare(entry.x, entry.y, entry.z)
        if object and square then
            system:removeObject(object)
            SolarSites.place(square, entry.spot)
        end
    end
end

--- Places and forgets every spot in the chunk. Called by SGlobalObjectSystem.chunkLoaded for a
--- chunk that holds spots.
function SolarSites.placeChunk(wx, wy)
    local objects = system:getObjectsInChunk(wx, wy)
    for i = objects:size() - 1, 0, -1 do
        local object = objects:get(i)
        local x, y, z = object:getX(), object:getY(), object:getZ()
        local spot = {}
        for key, value in pairs(object:getModData()) do
            spot[key] = value
        end
        if spot.what == "arrowBoard" then
            table.insert(waitingArrowBoards, { x = x, y = y, z = z, spot = spot })
        else
            system:removeObject(object)
            local square = getSquare(x, y, z)
            if square then
                SolarSites.place(square, spot)
            end
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
    SolarSites.placeChunk(wx, wy)
end

-- The game asks every system for a table to send to clients; the spots concern only the server.
local function getInitialStateForClient()
    return nil
end

local function onSGlobalObjectSystemInit()
    system = SGlobalObjects.registerSystem(SolarSites.SYSTEM_NAME)
    system:setModDataKeys({ "rolled" })
    system:setObjectModDataKeys({ "what", "siteKind", "mount", "facing", "stock" })
    local modData = system:getModData()
    modData.OnChunkLoaded = onChunkLoaded
    modData.getInitialStateForClient = getInitialStateForClient
    if not modData.rolled then
        modData.rolled = true
        rollSites()
    end
end

Events.OnSGlobalObjectSystemInit.Add(onSGlobalObjectSystemInit)
Events.EveryOneMinute.Add(placeWaitingArrowBoards)

return SolarSites
