if isClient() then
    return
end

require "RenewableEnergy/Sprites"
local WorldSpawns = require "RenewableEnergy/World/WorldSpawns"
local LOCATIONS = require "RenewableEnergy/World/FixedSpawnLocations"

-- Crates and panels at fixed spots of the map (FixedSpawnLocations.lua). A new world rolls each
-- spot once against the Solar Panel / Crate World Spawns option and keeps the winners as global
-- objects, which the game saves and hands back when their chunk first loads (SGlobalObjects
-- .chunkLoaded); the object goes down then and the spot is forgotten.

local FixedSpawns = {}
RenewableEnergy.FixedSpawns = FixedSpawns

FixedSpawns.SYSTEM_NAME = "RenewableEnergyFixedSpawns"

---@type SGlobalObjectSystem?
local system

--- Puts the object of a spot on its square.
---@param square IsoGridSquare
---@param kind string "crate" or "flat", "wall", "rack"
---@param facing string? for walls and racks
function FixedSpawns.place(square, kind, facing)
    if kind == "crate" then
        WorldSpawns.placeCrate(square)
    else
        local sprite = RenewableEnergy.Sprites[kind]
        WorldSpawns.placePanel(square, facing and sprite[facing] or sprite)
    end
end

--- The spots of every map the world is made of.
function FixedSpawns.spots()
    local spots = {}
    for map in string.gmatch(getWorld():getMap(), "[^;]+") do
        for _, spot in ipairs(LOCATIONS[map] or {}) do
            table.insert(spots, spot)
        end
    end
    return spots
end

local function rollSpots()
    local chance = SandboxVars.RenewableEnergy.solarPanelWorldSpawns
    for _, spot in ipairs(FixedSpawns.spots()) do
        local x, y, z = spot[1], spot[2], spot[3]
        if ZombRand(100) < chance and not system:getObjectAt(x, y, z) then
            local modData = system:newObject(x, y, z):getModData()
            modData.kind = spot[4]
            modData.facing = spot[5]
        end
    end
end

-- Called by SGlobalObjectSystem.chunkLoaded for a chunk that holds spots, with the system's modData
-- as self.
local function onChunkLoaded(_self, wx, wy)
    local objects = system:getObjectsInChunk(wx, wy)
    for i = objects:size() - 1, 0, -1 do
        local spot = objects:get(i)
        local square = getSquare(spot:getX(), spot:getY(), spot:getZ())
        local modData = spot:getModData()
        if square then
            FixedSpawns.place(square, modData.kind, modData.facing)
        end
        system:removeObject(spot)
    end
    system:finishedWithList(objects)
end

-- The game asks every system for a table to send to clients; the spots concern only the server.
local function getInitialStateForClient()
    return nil
end

local function onSGlobalObjectSystemInit()
    system = SGlobalObjects.registerSystem(FixedSpawns.SYSTEM_NAME)
    system:setModDataKeys({ "rolled" })
    system:setObjectModDataKeys({ "kind", "facing" })
    local modData = system:getModData()
    modData.OnChunkLoaded = onChunkLoaded
    modData.getInitialStateForClient = getInitialStateForClient
    if not modData.rolled then
        modData.rolled = true
        rollSpots()
    end
end

Events.OnSGlobalObjectSystemInit.Add(onSGlobalObjectSystemInit)

return FixedSpawns
