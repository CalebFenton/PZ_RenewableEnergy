require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Biogas. The stink is the game's own corpse smell, from ghosts (server/RenewableEnergy/Biogas/
-- Stink.lua) that the authority counts; on a multiplayer client the moodle follows the rate the
-- server sends every two seconds (PlayerDamagePacket).

local T = RenewableEnergyTest
local test = T.test

-- How long the moodle may take to follow the count, in real milliseconds: a server sync and then
-- some.
local SMELL_MS = 8000

local function smellLevel()
    return T.player():getMoodles():getMoodleLevel(MoodleType.NOXIOUS_SMELL)
end

local function at(square)
    return { x = square:getX(), y = square:getY(), z = square:getZ() }
end

-- Queues setting the stink of a source on `square` to `count` corpses, its answer in
-- self.server.stinkSet.
local function stink(self, square, count, key)
    local args = at(square)
    args.key, args.count = key or "test", count
    T.server(self, "stinkSet", args)
end

-- Queues a wait until this client's smell moodle is at `level`, or SMELL_MS pass, then records the
-- level in self.smell[label].
local function waitForSmell(self, level, label)
    local deadline
    T.waitUntil(function()
        deadline = deadline or getTimestampMs() + SMELL_MS
        return smellLevel() == level or getTimestampMs() > deadline
    end, math.huge, "the smell moodle at " .. level)
    T.step(function()
        self.smell = self.smell or {}
        self.smell[label] = smellLevel()
    end)
end

-- Queues a stretch of SMELL_MS for what should not change, then records the level.
local function holdSmell(self, label)
    local deadline
    T.waitUntil(function()
        deadline = deadline or getTimestampMs() + SMELL_MS
        return getTimestampMs() > deadline
    end, math.huge, "a while")
    T.step(function()
        self.smell = self.smell or {}
        self.smell[label] = smellLevel()
    end)
end

local function standOn(square)
    PZHarness.Fixtures.teleportToMiddle(T.player(), square:getX(), square:getY(), square:getZ())
end

-- Stink ------------------------------------------------------------------------------------------

-- Ghosts outdoors smell like corpses to a character outdoors nearby, through the vanilla moodle at
-- each corpse count's level, and leave nothing on their square; taking them away clears the smell.
test("renewable_energy_biogas_stink_outdoors", {
    run = function(self)
        local stand = (T.need(self, T.squares(self, 1), "a free outdoor square to stand on") or {})[1]
        if not stand then return end
        local source = (T.need(self, T.squares(self, 1, { near = stand, minDistance = 3 }), "a free outdoor square for the source") or {})[1]
        if not source then return end
        self.source = source
        standOn(stand)
        stink(self, source, 25)
        waitForSmell(self, 3, "corpses25")
        T.server(self, "stinkRead", at(source))
        T.step(function() self.read25 = self.server.stinkRead end)
        stink(self, source, 15)
        waitForSmell(self, 2, "corpses15")
        stink(self, source, 6)
        waitForSmell(self, 1, "corpses6")
        stink(self, source, 0)
        waitForSmell(self, 0, "corpses0")
    end,
    validate = function(self)
        T.expect(self.smell.corpses25 == 3, "25 ghosts: smell level " .. tostring(self.smell.corpses25) .. ", not 3")
        T.expect(self.smell.corpses15 == 2, "15 ghosts: smell level " .. tostring(self.smell.corpses15) .. ", not 2")
        T.expect(self.smell.corpses6 == 1, "6 ghosts: smell level " .. tostring(self.smell.corpses6) .. ", not 1")
        T.expect(self.smell.corpses0 == 0, "no ghosts: smell level " .. tostring(self.smell.corpses0) .. ", not 0")
        local read = self.read25
        T.expect(read.rate > 0.002, "25 ghosts: the authority's rate is " .. tostring(read.rate))
        T.expect(read.bodies == 0, "the source's square holds " .. tostring(read.bodies) .. " corpses")
        T.expect(read.objects == 0, "the source's square holds " .. tostring(read.objects) .. " moving objects")
        print("RETest STINK outdoors " .. string.format("rate=%.5f level=%d sickness=%.3f", read.rate, read.level, read.sickness))
    end,
})

-- Ghosts in a building smell only to a character in that building.
test("renewable_energy_biogas_stink_indoors", {
    run = function(self)
        local outside = (T.need(self, T.squares(self, 1), "a free outdoor square to stand on") or {})[1]
        local source = (T.need(self, T.squares(self, 1, { indoors = true }), "a free indoor square for the source") or {})[1]
        if not (outside and source) then return end
        local inside = (T.need(self, T.squares(self, 1, { indoors = true, near = source, minDistance = 2 }), "another indoor square") or {})[1]
        if not inside then return end
        self.sameBuilding = inside:getBuilding() == source:getBuilding()
        standOn(outside)
        stink(self, source, 25)
        holdSmell(self, "outside")
        T.step(function() standOn(inside) end)
        waitForSmell(self, 3, "inside")
    end,
    validate = function(self)
        T.expect(self.sameBuilding, "the two indoor squares are in different buildings")
        T.expect(self.smell.outside == 0, "outside, ghosts in a building smell at level " .. tostring(self.smell.outside))
        T.expect(self.smell.inside == 3, "inside, 25 ghosts smell at level " .. tostring(self.smell.inside) .. ", not 3")
    end,
})

-- A gas mask keeps the smell out, its filter draining as it does among corpses.
test("renewable_energy_biogas_stink_gas_mask", {
    run = function(self)
        local stand = (T.need(self, T.squares(self, 1), "a free outdoor square to stand on") or {})[1]
        if not stand then return end
        local source = (T.need(self, T.squares(self, 1, { near = stand, minDistance = 3 }), "a free outdoor square for the source") or {})[1]
        if not source then return end
        standOn(stand)
        T.give(self, "mask", { { type = "Base.Hat_GasMask", worn = true } })
        stink(self, source, 25)
        holdSmell(self, "masked")
        T.server(self, "stinkRead", at(source))
    end,
    validate = function(self)
        local read = self.server.stinkRead
        T.expect(self.smell.masked == 0, "with a gas mask, the smell is at level " .. tostring(self.smell.masked))
        T.expect(read.mask and read.mask < 1, "the gas mask's filter is at " .. tostring(read.mask))
    end,
})

-- A chunk zeroes its corpse count when it unloads and loads; the ghosts are counted again when it
-- loads, and can be taken away after without the count going wrong. Single player only: a
-- multiplayer server keeps the chunk loaded long after the character leaves.
local AWAY = 600
local CHUNK_FRAMES = 6000
test("renewable_energy_biogas_stink_chunk_reload", {
    spOnly = "the server keeps chunks loaded after the character leaves",
    timeoutSeconds = 120,
    run = function(self)
        local stand = (T.need(self, T.squares(self, 1), "a free outdoor square to stand on") or {})[1]
        if not stand then return end
        local source = (T.need(self, T.squares(self, 1, { near = stand, minDistance = 3 }), "a free outdoor square for the source") or {})[1]
        if not source then return end
        local p = T.player()
        local home = at(stand)
        local sx, sy, sz = source:getX(), source:getY(), source:getZ()
        -- A teleport from inside a timed action doesn't stick, so OnTick makes it.
        local target
        T.onTick(self, function()
            if target then
                p:teleportTo(target[1], target[2], target[3])
                target = nil
            end
        end)
        T.defer(self, function() p:teleportTo(home.x + 0.5, home.y + 0.5, home.z) end)
        -- That the chunk really loaded again, rather than came back from a cache with its count.
        self.loads = 0
        local function onLoadChunk(chunk)
            local origin = chunk:getGridSquare(0, 0, 0)
            local dx, dy = origin and sx - origin:getX(), origin and sy - origin:getY()
            if origin and dx >= 0 and dx < 8 and dy >= 0 and dy < 8 then
                self.loads = self.loads + 1
            end
        end
        Events.LoadChunk.Add(onLoadChunk)
        T.defer(self, function() Events.LoadChunk.Remove(onLoadChunk) end)
        standOn(stand)
        stink(self, source, 25)
        waitForSmell(self, 3, "before")
        T.step(function() target = { home.x + AWAY + 0.5, home.y + 0.5, 0 } end)
        T.waitUntil(function() return getSquare(sx, sy, sz) == nil end, CHUNK_FRAMES, "the source's chunk to unload")
        T.step(function()
            self.unloaded = getSquare(sx, sy, sz) == nil
            target = { home.x + 0.5, home.y + 0.5, home.z }
        end)
        T.waitUntil(function() return getSquare(sx, sy, sz) ~= nil end, CHUNK_FRAMES, "the source's chunk to load")
        waitForSmell(self, 3, "reloaded")
        stink(self, source, 0)
        waitForSmell(self, 0, "cleared")
        stink(self, source, 6)
        waitForSmell(self, 1, "again6")
    end,
    validate = function(self)
        T.expect(self.smell.before == 3, "before: smell level " .. tostring(self.smell.before))
        T.expect(self.unloaded, "the source's chunk never unloaded")
        T.expect(self.loads > 0, "the source's chunk came back without LoadChunk")
        T.expect(self.smell.reloaded == 3, "after the chunk loaded again: smell level " .. tostring(self.smell.reloaded))
        T.expect(self.smell.cleared == 0, "cleared: smell level " .. tostring(self.smell.cleared))
        T.expect(self.smell.again6 == 1, "6 ghosts after: smell level " .. tostring(self.smell.again6) .. ", not 1")
    end,
})
