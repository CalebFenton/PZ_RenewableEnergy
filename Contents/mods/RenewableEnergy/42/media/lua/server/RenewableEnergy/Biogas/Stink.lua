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
-- in a building only players in it. A player smells the corpses of the chunks within one of their own
-- (CorpseCount.getCorpseCount, a 3 by 3 block): a pile in one chunk smells the same anywhere in that
-- block and not at all a step past it. A real pile has stragglers, so the smell grows as it nears.
-- An outdoor source does the same: most of its ghosts on its own square, a few in each chunk around
-- (RING_DIVISOR), so that beside it the count is all of them, a chunk off a smell level less, two
-- off about the first level, and further none.
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

-- Each of the eight chunks around an outdoor source holds this share of its ghosts, rounded down:
-- at the top smell level's count, two each, which leaves a chunk off a level lower and two chunks
-- off at the first (Stink.spread). A faint source's few ghosts all stay on its square.
Stink.RING_DIVISOR = 12

local CHUNK_SIZE = getChunkSizeInSquares()

--- How an outdoor source smelling like `count` corpses spreads them: the ghosts on its own square
--- and those in each of the eight chunks around its own; together `count`.
function Stink.spread(count)
    local ring = math.floor(count / Stink.RING_DIVISOR)
    return count - 8 * ring, ring
end

-- Source key -> { x, y, z, want = corpses asked for, outdoors = whether its square is (nil until
-- it has loaded), groups = { [offset] = group } }. A group is the ghosts in one chunk: { dx, dy =
-- its chunk's offset from the source's, x, y = the square they stand at once picked (nil before,
-- false with none to stand at), want, ghosts = { IsoDeadBody, ... }, live = how many of them the
-- chunk counts now }.
local sources = {}

local function chunkOf(coordinate)
    return math.floor(coordinate / CHUNK_SIZE)
end

local function newGhost(group, z)
    local ghost = IsoDeadBody.new(getCell())
    ghost:setX(group.x + 0.5)
    ghost:setY(group.y + 0.5)
    ghost:setZ(z)
    return ghost
end

-- The square of the chunk `dx`, `dy` chunks from the source's on its level that is outdoors and
-- nearest the source, where that chunk's ghosts count to the outdoor smell; nil while the chunk
-- isn't loaded (its ground has no square, as onLoadChunk tells it), false if none of its squares
-- is outdoors on that level.
local function ringSquare(source, dx, dy)
    local x0, y0 = (chunkOf(source.x) + dx) * CHUNK_SIZE, (chunkOf(source.y) + dy) * CHUNK_SIZE
    if not getSquare(x0, y0, 0) then
        return nil
    end
    local best, bestX, bestY
    for x = x0, x0 + CHUNK_SIZE - 1 do
        for y = y0, y0 + CHUNK_SIZE - 1 do
            local square = getSquare(x, y, source.z)
            if square and not square:getBuilding() then
                local distance = (x - source.x) ^ 2 + (y - source.y) ^ 2
                if not best or distance < best then
                    best, bestX, bestY = distance, x, y
                end
            end
        end
    end
    return best and { bestX, bestY } or false
end

-- Sets the groups `source` wants now: its own square's and, outdoors, the ring's. Waits until its
-- square has loaded once, when its building is known.
local function plan(source)
    local square = getSquare(source.x, source.y, source.z)
    if square then
        source.outdoors = square:getBuilding() == nil
    end
    if source.outdoors == nil then
        return
    end
    local own, ring = source.want, 0
    if source.outdoors then
        own, ring = Stink.spread(source.want)
    end
    for dx = -1, 1 do
        for dy = -1, 1 do
            local key = dx .. "," .. dy
            local group = source.groups[key]
            if not group then
                group = { dx = dx, dy = dy, want = 0, ghosts = {}, live = 0 }
                if dx == 0 and dy == 0 then
                    group.x, group.y = source.x, source.y
                end
                source.groups[key] = group
            end
            group.want = (dx == 0 and dy == 0) and own or ring
        end
    end
end

-- Brings `group`'s counted ghosts to what it wants, if its chunk is loaded.
local function settleGroup(source, group)
    if group.x == nil and group.want > 0 then
        local square = ringSquare(source, group.dx, group.dy)
        if square == nil then
            return
        end
        group.x, group.y = square and square[1] or false, square and square[2]
    end
    if not group.x or not getSquare(group.x, group.y, source.z) then
        return
    end
    local ghosts = group.ghosts
    while group.live < group.want do
        local ghost = ghosts[group.live + 1]
        if not ghost then
            ghost = newGhost(group, source.z)
            ghosts[group.live + 1] = ghost
        end
        ghost:addToWorld()
        group.live = group.live + 1
    end
    while group.live > group.want do
        ghosts[group.live]:removeFromWorld()
        ghosts[group.live] = nil
        group.live = group.live - 1
    end
end

-- Settles every group of the source `key` whose chunk is loaded now, and forgets the source once
-- it has nothing left.
local function settleKey(key, source)
    if source.want > 0 then
        plan(source)
    end
    local left = false
    for _, group in pairs(source.groups) do
        settleGroup(source, group)
        left = left or group.want > 0 or group.live > 0
    end
    if source.want == 0 and not left then
        sources[key] = nil
    end
end

--- Makes the source `key` at square x, y, z smell like `count` corpses to a player beside it.
--- Takes effect in each chunk now if it is loaded, else when it loads.
function Stink.set(key, x, y, z, count)
    local source = sources[key]
    if not source then
        if count <= 0 then
            return
        end
        source = { x = x, y = y, z = z, want = 0, groups = {} }
        sources[key] = source
    end
    source.want = math.max(0, math.floor(count))
    if source.want == 0 then
        for _, group in pairs(source.groups) do
            group.want = 0
        end
    end
    settleKey(key, source)
end

-- Sources cleared since the last minute.
local clearing = {}

--- Takes the source `key`'s stink away for good, at the next game minute or when its chunks next
--- load. Not at once: a source whose record goes as its chunk loads (SGlobalObjectSystem's
--- OnChunkLoaded) is cleared after the chunk zeroed its counts and before LoadChunk counts its
--- ghosts again, when taking one out would take a real corpse's place.
function Stink.clear(key)
    local source = sources[key]
    if source then
        source.want = 0
        for _, group in pairs(source.groups) do
            group.want = 0
        end
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

--- The corpses the source `key` smells like in the chunks' counts now, all its groups together.
--- The tests' probe: the game's own count (CorpseCount) is out of Lua's reach.
function Stink.counted(key)
    local source = sources[key]
    local live = 0
    for _, group in pairs(source and source.groups or {}) do
        live = live + group.live
    end
    return live
end

-- Every ghost a group in the chunk still has is counted again, even one it no longer wants
-- (lowered while unloaded), so that settling takes that one out the proper way, which also lets
-- the game forget it. Groups not yet given a square in it get theirs.
local function onLoadChunk(chunk)
    local origin = chunk:getGridSquare(0, 0, 0)
    if not origin then
        return
    end
    local cx, cy = chunkOf(origin:getX()), chunkOf(origin:getY())
    for key, source in pairs(sources) do
        local group = source.groups[(cx - chunkOf(source.x)) .. "," .. (cy - chunkOf(source.y))]
        if group then
            for _, ghost in ipairs(group.ghosts) do
                ghost:addToWorld()
            end
            group.live = #group.ghosts
            settleKey(key, source)
        elseif cx == chunkOf(source.x) and cy == chunkOf(source.y) then
            settleKey(key, source)
        end
    end
end

Events.LoadChunk.Add(onLoadChunk)

return Stink
