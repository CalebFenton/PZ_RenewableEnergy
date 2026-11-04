require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"

-- The stink (Contents/.../RenewableEnergy/Biogas/Stink.lua): ghosts that smell like corpses. The
-- smell moodle is the authority character's, so the tests read it there; a multiplayer client's
-- follows the rate the server sends.

local T = RenewableEnergyTest
local test = T.test

local CHUNK_SIZE = getChunkSizeInSquares()

local function chunkOf(square)
    return math.floor(square:getX() / CHUNK_SIZE), math.floor(square:getY() / CHUNK_SIZE)
end

-- Stands the character on a free outdoor square and answers it and another a few squares off in
-- the same chunk for a source, or nil: in the source's own chunk a character smells all of an
-- outdoor source's ghosts, its own and the ring's around it (Stink.spread).
local function standNearSource(self)
    local candidates = T.squares(self, 60, {})
    if not T.need(self, candidates, "free outdoor squares") then return nil end
    for _, stand in ipairs(candidates) do
        local sx, sy = chunkOf(stand)
        for _, source in ipairs(candidates) do
            local x, y = chunkOf(source)
            local apart = math.max(math.abs(source:getX() - stand:getX()), math.abs(source:getY() - stand:getY()))
            if x == sx and y == sy and source:getZ() == stand:getZ() and apart >= 3 then
                T.standOn(stand)
                return stand, source
            end
        end
    end
    T.need(self, nil, "two free outdoor squares three apart in one chunk")
    return nil
end

-- Queues setting the stink of a source on `square` to `count` corpses.
local function stink(self, square, count)
    T.server(self, "stinkSet", T.at(square, { key = "test", count = count }))
end

-- Queues reading the corpse counts at which the game's smell levels start (Stink.LEVEL_CORPSES,
-- server only), into self.reads.levels, then `fn(levels)` in a step, which queues what uses them.
local function withLevels(self, square, fn)
    T.read(self, "stinkRead", T.at(square), "levels")
    T.step(function()
        self.levels = T.need(self, self.reads.levels.levels, "the corpse counts of the smell levels")
        if self.levels then
            fn(self.levels)
        end
    end)
end

-- Queues a wait until this client's smell moodle is at `level`, or T.SMELL_MS pass, then records the
-- level in self.moodle[label] for validate.
local function waitForClientSmell(self, level, label)
    T.waitUntil(function()
        return T.player():getMoodles():getMoodleLevel(MoodleType.NOXIOUS_SMELL) == level
    end, T.SMELL_MS, "the smell moodle at " .. level)
    T.step(function() self.moodle[label] = T.player():getMoodles():getMoodleLevel(MoodleType.NOXIOUS_SMELL) end)
end

-- Stink ------------------------------------------------------------------------------------------

-- Ghosts outdoors smell like corpses to a character outdoors nearby: each smell level starts at
-- its corpse count and not one below, the moodle reaches this client, and the ghosts leave nothing
-- on their square; taking them away clears the smell.
test("renewable_energy_biogas_stink_outdoors", {
    run = function(self)
        self.moodle = {}
        local _, source = standNearSource(self)
        if not source then return end
        withLevels(self, source, function(levels)
            for i, count in ipairs(levels) do
                stink(self, source, count - 1)
                T.waitForAuthoritySmell(self, source, i - 1, "below" .. i)
                stink(self, source, count)
                T.waitForAuthoritySmell(self, source, i, "at" .. i)
            end
            waitForClientSmell(self, #levels, "top")
            stink(self, source, 0)
            T.waitForAuthoritySmell(self, source, 0, "none")
            waitForClientSmell(self, 0, "none")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        for i, count in ipairs(self.levels) do
            local below, at = reads["below" .. i], reads["at" .. i]
            T.expectEqual("the smell level of " .. (count - 1) .. " ghosts", below and below.level, i - 1)
            T.expectEqual("the smell level of " .. count .. " ghosts", at and at.level, i)
        end
        local top = reads["at" .. #self.levels]
        if T.expect(top ~= nil, "no read at the top smell level") then
            T.expectEqual("corpses on the source's square", top.bodies, 0)
            T.expectEqual("moving objects on the source's square", top.objects, 0)
        end
        T.expectEqual("this client's moodle level at the top", self.moodle.top, #self.levels)
        T.expectEqual("the smell level with the ghosts gone", reads.none and reads.none.level, 0)
        T.expectEqual("this client's moodle level with the ghosts gone", self.moodle.none, 0)
    end,
})

-- An outdoor square in the chunk `dx` chunks east of `square`'s, on its level, or nil.
local function outdoorsInChunk(square, dx)
    local cx, cy = chunkOf(square)
    local x0, y0 = (cx + dx) * CHUNK_SIZE, cy * CHUNK_SIZE
    for x = x0, x0 + CHUNK_SIZE - 1 do
        for y = y0, y0 + CHUNK_SIZE - 1 do
            local here = getSquare(x, y, square:getZ())
            if here and here:isOutside() and not here:getBuilding() then
                return here
            end
        end
    end
    return nil
end

-- An outdoor source at the top smell level smells a level less for each chunk further off a
-- character stands, as a pile of corpses with stragglers does (Stink.spread's ring), and not at all
-- three chunks off.
test("renewable_energy_biogas_stink_falls_off_with_distance", {
    run = function(self)
        local source = T.square(self, nil, "a free outdoor square for the source")
        if not source then return end
        self.stands = {}
        for dx = 0, 3 do
            self.stands[dx] = outdoorsInChunk(source, dx)
            if not T.need(self, self.stands[dx], "an outdoor square " .. dx .. " chunks east of the source") then return end
        end
        withLevels(self, source, function(levels)
            stink(self, source, levels[#levels])
            for dx = 0, 3 do
                T.step(function() T.standOn(self.stands[dx]) end)
                T.waitForAuthoritySmell(self, source, math.max(0, #levels - dx), "east" .. dx)
            end
        end)
    end,
    validate = function(self)
        for dx = 0, 3 do
            local read = self.reads["east" .. dx]
            T.expectEqual("the smell level " .. dx .. " chunks east of the source", read and read.level, math.max(0, #self.levels - dx))
        end
    end,
})

-- Ghosts in a building smell only to a character in that building.
test("renewable_energy_biogas_stink_indoors", {
    run = function(self)
        local outside = T.square(self, nil, "a free outdoor square to stand on")
        local source = outside and T.square(self, { indoors = true }, "a free indoor square for the source")
        local inside = source and T.square(self, { indoors = true, near = source, minDistance = 2 }, "another indoor square")
        if not inside then return end
        if not T.need(self, inside:getBuilding() == source:getBuilding(), "two indoor squares in one building") then return end
        T.standOn(inside)
        withLevels(self, source, function(levels)
            stink(self, source, levels[#levels])
            T.waitForAuthoritySmell(self, source, #levels, "inside")
            T.step(function() T.standOn(outside) end)
            T.waitForAuthoritySmell(self, source, 0, "outside")
        end)
    end,
    validate = function(self)
        local inside, outside = self.reads.inside, self.reads.outside
        T.expectEqual("the smell level inside, of ghosts in the building", inside and inside.level, #self.levels)
        T.expectEqual("the smell level outside, of ghosts in a building", outside and outside.level, 0)
    end,
})

-- A chunk zeroes its corpse count when it unloads and loads; the ghosts are counted again when it
-- loads, and can be taken away after without the count going wrong. Single player only: a
-- multiplayer server keeps the chunk loaded long after the character leaves.
test("renewable_energy_biogas_stink_chunk_reload", {
    spOnly = T.CHUNK_RELOAD_SP_ONLY,
    timeoutSeconds = T.CHUNK_RELOAD_SECONDS,
    run = function(self)
        self.moodle = {}
        local _, source = standNearSource(self)
        if not source then return end
        withLevels(self, source, function(levels)
            stink(self, source, levels[#levels])
            waitForClientSmell(self, #levels, "before")
            T.reloadChunk(self, T.at(source))
            waitForClientSmell(self, #levels, "reloaded")
            stink(self, source, 0)
            waitForClientSmell(self, 0, "cleared")
            stink(self, source, levels[1])
            waitForClientSmell(self, 1, "again")
        end)
    end,
    validate = function(self)
        local top = #self.levels
        T.expectEqual("the smell level before", self.moodle.before, top)
        T.expectEqual("the smell level after the chunk loaded again", self.moodle.reloaded, top)
        T.expectEqual("the smell level cleared", self.moodle.cleared, 0)
        T.expectEqual("the smell level of the first level's ghosts after", self.moodle.again, 1)
    end,
})
