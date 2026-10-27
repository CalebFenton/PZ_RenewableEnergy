-- Waiting for the world around something to load, and rolling buildings once theirs has. A chunk
-- that loads brings in parts of buildings, not their surroundings, so a building waits until every
-- chunk within its watcher's reach of it is loaded. The rules:
--
-- - Whatever waits (BuildingWatch.waitFor) waits in one queue, at a square of it. Each game minute,
--   one whose square has unloaded leaves the queue: what put it there puts it back when its chunk
--   loads again. One that is ready leaves the queue and runs. It leaves before it runs, so what it
--   finds already done isn't kept.
-- - Each chunk that loads offers its buildings, up to HIGHEST_LEVEL, to every watcher once; a
--   building the watcher's ledger doesn't hold as rolled and the watcher `wants` waits, with a
--   square of it in that chunk, until its surroundings are loaded, and is rolled then unless its
--   ledger took it meanwhile.
-- - The queue lives only in memory. Whatever must outlive a quit, such as a building promised
--   for certain, is the watcher's own saved ledger, which `wants` and the roll read.

if isClient() then return end

local RenewableEnergy = require "RenewableEnergy/Utilities"
local Sprites = require "RenewableEnergy/Sprites"

local BuildingWatch = {}
RenewableEnergy.BuildingWatch = BuildingWatch

-- Squares out from a building's bounds that a roll may place on, and that must be loaded first,
-- unless the watcher names its own reach.
BuildingWatch.REACH = 4
-- The highest level a building is looked at on: a deer stand's one room is on level 1.
BuildingWatch.HIGHEST_LEVEL = 1

local CHUNK_SIZE = getChunkSizeInSquares()

--- The key a building's saved rolls are filed under.
function BuildingWatch.key(def)
    return def:getX() .. "," .. def:getY()
end

--- Calls `fn(square, x, y)` for each place on level `z` of the building's bounds and `reach`
--- squares around them (square nil where it isn't loaded), until fn returns something, which it
--- returns.
function BuildingWatch.eachSquare(def, reach, z, fn)
    for x = def:getX() - reach, def:getX2() + reach - 1 do
        for y = def:getY() - reach, def:getY2() + reach - 1 do
            local found = fn(getSquare(x, y, z), x, y)
            if found ~= nil then
                return found
            end
        end
    end
    return nil
end

-- No square flag marks a road; vanilla tells one by its floor tile too (BaseVehicle.isDoingOffroad).
local function isStreet(square)
    local name = Sprites.nameOf(square:getFloor()) or ""
    return string.find(name, "^floors_exterior_street") ~= nil or string.find(name, "^blends_street") ~= nil
end

--- Whether something the mod puts by a building may stand on the square: outdoor ground level
--- with a floor, nothing solid on it, off the road, not in water or a tree.
function BuildingWatch.isOpenGround(square)
    return square ~= nil and square:getZ() == 0 and square:getRoom() == nil and square:isOutside()
        and square:hasFloor() and square:isFree(false) and not square:HasTree()
        and not square:getProperties():has(IsoFlagType.water) and not isStreet(square)
end

--- Whether every chunk within `reach` (default REACH) of the building is loaded: one square per
--- chunk tells. The loaded area around several players needn't be a rectangle, so each chunk is
--- checked.
function BuildingWatch.surroundingsLoaded(def, reach)
    reach = reach or BuildingWatch.REACH
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

-- Waiting

-- What waits, by key: { x, y, z, ready, run }.
local waiting = {}

--- Runs `run(square)` at the next game minute that `ready(square)` holds for the loaded square
--- x, y, z; drops it if that square unloads first. Waiting again under a key that waits already
--- changes nothing.
function BuildingWatch.waitFor(key, x, y, z, ready, run)
    if not waiting[key] then
        waiting[key] = { x = x, y = y, z = z, ready = ready, run = run }
    end
end

-- Running one entry or its square unloading takes it off the queue, so they are collected first.
local function runReady()
    local gone, due
    for key, entry in pairs(waiting) do
        local square = getSquare(entry.x, entry.y, entry.z)
        if not square then
            gone = gone or {}
            table.insert(gone, key)
        elseif entry.ready(square) then
            due = due or {}
            table.insert(due, key)
        end
    end
    for _, key in ipairs(gone or {}) do
        waiting[key] = nil
    end
    for _, key in ipairs(due or {}) do
        local entry = waiting[key]
        waiting[key] = nil
        entry.run(getSquare(entry.x, entry.y, entry.z))
    end
end

-- Buildings

-- Each { ledger, isRolled, wants, roll, reach }.
local watchers = {}

local function rolledIn(watcher, def)
    return watcher.isRolled(ModData.getOrCreate(watcher.ledger)[BuildingWatch.key(def)])
end

local function rolledAtAll(value)
    return value ~= nil
end

--- Rolls, with `spec.roll(def)`, each building a loading chunk brings in that `spec.wants(def)`,
--- once its surroundings out to `spec.reach` (default REACH) are loaded. `spec.ledger` names the
--- global ModData the watcher saves its rolls in, by BuildingWatch.key; a building whose entry
--- there `spec.isRolled(value)` says was rolled (by default, any entry) is never offered.
function BuildingWatch.watch(spec)
    table.insert(watchers, {
        ledger = spec.ledger, isRolled = spec.isRolled or rolledAtAll,
        wants = spec.wants, roll = spec.roll, reach = spec.reach,
    })
end

local function onLoadChunk(chunk)
    -- A building covers many of the chunk's squares; each is offered once.
    local seen = {}
    for z = 0, BuildingWatch.HIGHEST_LEVEL do
        for x = 0, CHUNK_SIZE - 1 do
            for y = 0, CHUNK_SIZE - 1 do
                local square = chunk:getGridSquare(x, y, z)
                local building = square and square:getBuilding()
                local def = building and building:getDef()
                if def and not seen[def] then
                    seen[def] = true
                    local key = BuildingWatch.key(def)
                    for i, watcher in ipairs(watchers) do
                        if not rolledIn(watcher, def) and watcher.wants(def) then
                            BuildingWatch.waitFor(i .. "|" .. key, square:getX(), square:getY(), z, function()
                                return BuildingWatch.surroundingsLoaded(def, watcher.reach)
                            end, function()
                                if not rolledIn(watcher, def) then
                                    watcher.roll(def)
                                end
                            end)
                        end
                    end
                end
            end
        end
    end
end

Events.LoadChunk.Add(onLoadChunk)
-- A minute is soon enough: buildings load at the edge of the loaded area, out of sight.
Events.EveryOneMinute.Add(runReady)

return BuildingWatch
