if isClient() then
    return
end

-- Stink through the game's own corpse smell. The game smells corpses by counting them per chunk
-- (CorpseCount, which Lua can't reach); each player's update turns the count around them into the
-- noxious smell moodle and food sickness, through gas masks, traits and the corpse sandbox option,
-- and a multiplayer server sends the result to its client. The count goes up only when an
-- IsoDeadBody is added to the world and down when one is removed, and neither needs the body on a
-- square. So a source of stink keeps "ghosts": bodies made from the cell alone, placed at the
-- source's square and added to the world but never to the square. Nothing draws, loots, burns,
-- saves or rots them (IsoDeadBody.updateBodies skips a body with no visual), and no flies buzz,
-- since their sound needs a body on a square.
--
-- The count is per chunk level, split by building: ghosts outdoors count for players outdoors on
-- the same level within a chunk or so, and ghosts in a building only for players in that building.
-- The first five corpses near a player do nothing; at the default corpse option the moodle reaches
-- level 2 at 15 and level 3 at 25, the game's cap, which real corpses share.
--
-- A chunk zeroes its counts when it unloads, with no event, and again when it loads, before
-- LoadChunk, so the ghosts of a source in a chunk that loads are added again then. Removing a
-- ghost from a count that was zeroed would take a real corpse's place (an outdoor count goes
-- below zero), so a ghost is only removed while its chunk is loaded, when LoadChunk has made the
-- record right. The ghosts last the session; whoever owns a source sets it again after a load.

RenewableEnergy = RenewableEnergy or {}
local Stink = {}
RenewableEnergy.Stink = Stink

-- The corpses at which each smell level starts at the default corpse option: nothing below the
-- first, the game's cap at the last (BodyDamage and MoodleStat).
Stink.LEVEL_CORPSES = { 6, 15, 25 }

-- Source key -> { x, y, z, want = ghosts asked for, ghosts = { IsoDeadBody, ... }, live = how many
-- of them the chunk counts now }.
local sources = {}

local CHUNK_SIZE = 8

local function newGhost(source)
    local ghost = IsoDeadBody.new(getCell())
    ghost:setX(source.x + 0.5)
    ghost:setY(source.y + 0.5)
    ghost:setZ(source.z)
    return ghost
end

-- Brings the counted ghosts to what the source wants, if its square is loaded.
local function settle(source)
    if not getSquare(source.x, source.y, source.z) then
        return
    end
    local ghosts = source.ghosts
    while source.live < source.want do
        local ghost = ghosts[source.live + 1]
        if not ghost then
            ghost = newGhost(source)
            ghosts[source.live + 1] = ghost
        end
        ghost:addToWorld()
        source.live = source.live + 1
    end
    while source.live > source.want do
        ghosts[source.live]:removeFromWorld()
        ghosts[source.live] = nil
        source.live = source.live - 1
    end
end

-- Settles the source `key` and forgets it once it has nothing left.
local function settleKey(key, source)
    settle(source)
    if source.want == 0 and source.live == 0 then
        sources[key] = nil
    end
end

--- Makes the source `key` at square x, y, z smell like `count` corpses. Takes effect now if the
--- square is loaded, else when its chunk loads.
function Stink.set(key, x, y, z, count)
    local source = sources[key]
    if not source then
        if count <= 0 then
            return
        end
        source = { x = x, y = y, z = z, want = 0, ghosts = {}, live = 0 }
        sources[key] = source
    end
    source.want = math.max(0, math.floor(count))
    settleKey(key, source)
end

-- Sources cleared since the last minute.
local clearing = {}

--- Takes the source `key`'s stink away for good, at the next game minute or when its chunk next
--- loads. Not at once: a source whose record goes as its chunk loads (SGlobalObjectSystem's
--- OnChunkLoaded) is cleared after the chunk zeroed its counts and before LoadChunk counts its
--- ghosts again, when taking one out would take a real corpse's place.
function Stink.clear(key)
    local source = sources[key]
    if source then
        source.want = 0
        clearing[key] = true
    end
end

Events.EveryOneMinute.Add(function()
    for key in pairs(clearing) do
        local source = sources[key]
        if source then
            settleKey(key, source)
        end
    end
    clearing = {}
end)

--- The corpses the source `key` smells like in its chunk's count now.
function Stink.counted(key)
    local source = sources[key]
    return source and source.live or 0
end

-- Every ghost the source still has is counted again, even one it no longer wants (lowered while
-- unloaded), so that settle takes that one out the proper way, which also lets the game forget it.
local function onLoadChunk(chunk)
    local origin = chunk:getGridSquare(0, 0, 0)
    if not origin then
        return
    end
    local x0, y0 = origin:getX(), origin:getY()
    for key, source in pairs(sources) do
        if source.x >= x0 and source.x < x0 + CHUNK_SIZE and source.y >= y0 and source.y < y0 + CHUNK_SIZE then
            for _, ghost in ipairs(source.ghosts) do
                ghost:addToWorld()
            end
            source.live = #source.ghosts
            settleKey(key, source)
        end
    end
end

Events.LoadChunk.Add(onLoadChunk)

return Stink
