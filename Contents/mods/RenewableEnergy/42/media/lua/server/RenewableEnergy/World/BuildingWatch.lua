if isClient() then
    return
end

require "RenewableEnergy/Sprites"

-- Rolls buildings once their surroundings load: the one way GardenLights and RuralFinds roll the
-- buildings a chunk brings in, and SolarSites' house spots wait for a whole house. A chunk that
-- loads brings in parts of buildings, not their surroundings, so a building waits until every
-- chunk within REACH of it is loaded. The rules:
--
-- - Each chunk that loads offers its buildings, on its lowest levels, to every watcher once; a
--   building the watcher `wants` waits in that watcher's queue, with a square of it in that chunk.
-- - Each game minute, a building whose square has unloaded leaves the queue: its chunk brings it
--   back when it loads again. A building whose surroundings are loaded leaves the queue and is
--   rolled. It leaves before its roll, so a building the roll finds already rolled isn't kept.
-- - The queue lives only in memory. Whatever must outlive a quit, such as a building promised
--   for certain, is the watcher's own saved state, which `wants` and the roll read.

RenewableEnergy = RenewableEnergy or {}
local BuildingWatch = {}
RenewableEnergy.BuildingWatch = BuildingWatch

local Sprites = RenewableEnergy.Sprites

-- Squares out from a building's bounds that a roll may place on, and that must be loaded first.
BuildingWatch.REACH = 4
-- The highest level a chunk is scanned for buildings at: a deer stand's one room is on level 1.
local HIGHEST = 1

local CHUNK_SIZE = getChunkSizeInSquares()

-- Each { wants, roll, pending }, pending a building key -> { def, x, y, z }.
local watchers = {}

--- The key a building's saved rolls are filed under.
function BuildingWatch.key(def)
    return def:getX() .. "," .. def:getY()
end

--- Whether the square's floor is a street's.
function BuildingWatch.isStreet(square)
    local name = Sprites.nameOf(square:getFloor()) or ""
    return string.find(name, "^floors_exterior_street") ~= nil or string.find(name, "^blends_street") ~= nil
end

--- Whether every chunk within REACH of the building is loaded: one square per chunk tells. The
--- loaded area around several players needn't be a rectangle, so each chunk is checked.
function BuildingWatch.surroundingsLoaded(def)
    local reach = BuildingWatch.REACH
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

--- Rolls, with `roll(def)`, each building a loading chunk brings in that `wants(def)`, once its
--- surroundings are loaded.
function BuildingWatch.watch(wants, roll)
    table.insert(watchers, { wants = wants, roll = roll, pending = {} })
end

local function onLoadChunk(chunk)
    -- A building covers many of the chunk's squares; each is offered once.
    local seen = {}
    for z = 0, HIGHEST do
        for x = 0, CHUNK_SIZE - 1 do
            for y = 0, CHUNK_SIZE - 1 do
                local square = chunk:getGridSquare(x, y, z)
                local building = square and square:getBuilding()
                local def = building and building:getDef()
                if def and not seen[def] then
                    seen[def] = true
                    local key = BuildingWatch.key(def)
                    for _, watcher in ipairs(watchers) do
                        if not watcher.pending[key] and watcher.wants(def) then
                            watcher.pending[key] = { def = def, x = square:getX(), y = square:getY(), z = z }
                        end
                    end
                end
            end
        end
    end
end

-- Rolling a building and its chunk unloading both take it off the queue, so the buildings are
-- collected first.
local function rollLoaded()
    for _, watcher in ipairs(watchers) do
        local ready, gone
        for key, entry in pairs(watcher.pending) do
            if not getSquare(entry.x, entry.y, entry.z) then
                gone = gone or {}
                table.insert(gone, key)
            elseif BuildingWatch.surroundingsLoaded(entry.def) then
                ready = ready or {}
                table.insert(ready, key)
            end
        end
        for _, key in ipairs(gone or {}) do
            watcher.pending[key] = nil
        end
        for _, key in ipairs(ready or {}) do
            local def = watcher.pending[key].def
            watcher.pending[key] = nil
            watcher.roll(def)
        end
    end
end

Events.LoadChunk.Add(onLoadChunk)
-- A minute is soon enough: buildings load at the edge of the loaded area, out of sight.
Events.EveryOneMinute.Add(rollLoaded)

return BuildingWatch
