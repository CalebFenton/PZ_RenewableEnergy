if isClient() then
    return
end

-- Stink through the game's own corpse smell. The game counts corpses per chunk (CorpseCount, out of
-- Lua's reach) and each player's update turns the count around them into the noxious smell moodle
-- and food sickness, honouring gas masks, traits and the corpse sandbox option. The count changes
-- only when an IsoDeadBody is added to or removed from the world, neither needing the body on a
-- square. So a stink source keeps "ghosts": bodies added to the world but never to a square, which
-- nothing draws, loots, burns, saves or rots (IsoDeadBody.updateBodies skips a body with no visual),
-- and which draw no flies.
--
-- Counts are per chunk level, split by building: outdoor ghosts reach players outdoors nearby, ghosts
-- in a building only players in it.
--
-- A chunk zeroes its counts on unload (no event) and again on load before LoadChunk, which re-adds
-- its ghosts. Removing a ghost from a zeroed count would cancel a real corpse, so ghosts are only
-- removed while their chunk is loaded. Ghosts last the session; owners set them again after a load.

RenewableEnergy = RenewableEnergy or {}
local Stink = {}
RenewableEnergy.Stink = Stink

-- The corpses at which each smell level starts at the default corpse option: nothing below the
-- first, the game's cap at the last (BodyDamage and MoodleStat).
Stink.LEVEL_CORPSES = { 6, 15, 25 }

-- Source key -> { x, y, z, want = ghosts asked for, ghosts = { IsoDeadBody, ... }, live = how many
-- of them the chunk counts now }.
local sources = {}

local CHUNK_SIZE = getChunkSizeInSquares()

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

--- The corpses the source `key` smells like in its chunk's count now. The tests' probe: the
--- game's own count (CorpseCount) is out of Lua's reach.
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
