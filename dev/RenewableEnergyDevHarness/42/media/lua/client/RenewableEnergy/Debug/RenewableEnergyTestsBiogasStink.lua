require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"

-- The stink (Contents/.../RenewableEnergy/Biogas/Stink.lua): ghosts that smell like corpses. The
-- smell moodle is the authority character's, so the tests read it there; a multiplayer client's
-- follows the rate the server sends. The tests run in this order: stink_gas_mask counts on an
-- earlier one's fading smell.

local T = RenewableEnergyTest
local test = T.test

-- How long the smell may take to settle, in real milliseconds: a server sync and then some. Only a
-- failing test waits this long.
local SMELL_MS = 8000

local function standOn(square)
    PZHarness.Fixtures.teleportToMiddle(T.player(), square:getX(), square:getY(), square:getZ())
end

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
                standOn(stand)
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

-- Queues reads of the authority's smell until two in a row, a server update apart, show `level`,
-- or SMELL_MS pass; the last read lands in self.reads[label]. A level that settles elsewhere ends in
-- validate's failure.
local function waitForAuthoritySmell(self, square, level, label)
    local last
    T.readUntil(self, "stinkRead", T.at(square), label, function(read)
        local settled = read.level == last
        last = read.level
        return settled and read.level == level
    end, SMELL_MS)
end

-- Queues a wait until this client's smell moodle is at `level`, or SMELL_MS pass, then records the
-- level in self.moodle[label] for validate.
local function waitForClientSmell(self, level, label)
    T.waitUntil(function()
        return T.player():getMoodles():getMoodleLevel(MoodleType.NOXIOUS_SMELL) == level
    end, SMELL_MS, "the smell moodle at " .. level)
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
                waitForAuthoritySmell(self, source, i - 1, "below" .. i)
                stink(self, source, count)
                waitForAuthoritySmell(self, source, i, "at" .. i)
            end
            waitForClientSmell(self, #levels, "top")
            stink(self, source, 0)
            waitForAuthoritySmell(self, source, 0, "none")
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

-- The smell level `count` corpses make (Stink.LEVEL_CORPSES as `levels`).
local function levelOf(levels, count)
    local level = 0
    for i, start in ipairs(levels) do
        if count >= start then
            level = i
        end
    end
    return level
end

-- An outdoor source at the top smell level smells less the further off a character stands, a
-- chunk at a time, as a pile of corpses with stragglers does: in its own chunk all its corpses,
-- a chunk east its own ghosts and five of the eight chunks' around it (Stink.spread), two east
-- three of those chunks', three east none.
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
            local top = levels[#levels]
            T.read(self, "stinkSpread", { count = top }, "spread")
            T.step(function()
                local own, ring = self.reads.spread.own, self.reads.spread.ring
                self.wanted = { [0] = own + 8 * ring, own + 5 * ring, 3 * ring, 0 }
                stink(self, source, top)
                for dx = 0, 3 do
                    T.step(function() standOn(self.stands[dx]) end)
                    waitForAuthoritySmell(self, source, levelOf(levels, self.wanted[dx]), "east" .. dx)
                end
            end)
        end)
    end,
    validate = function(self)
        local levels = self.levels
        local last
        for dx = 0, 3 do
            local read, wanted = self.reads["east" .. dx], levelOf(levels, self.wanted[dx])
            T.expectEqual("the smell level " .. dx .. " chunks east of the source (" .. self.wanted[dx] .. " corpses)",
                read and read.level, wanted)
            if read and last then
                T.expect(read.level < last, dx .. " chunks east the smell is no weaker than a chunk nearer")
            end
            last = read and read.level
        end
        T.expect(levelOf(levels, self.wanted[0]) == #levels, "beside the source the smell isn't at the top level")
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
        standOn(inside)
        withLevels(self, source, function(levels)
            stink(self, source, levels[#levels])
            waitForAuthoritySmell(self, source, #levels, "inside")
            T.step(function() standOn(outside) end)
            waitForAuthoritySmell(self, source, 0, "outside")
        end)
    end,
    validate = function(self)
        local inside, outside = self.reads.inside, self.reads.outside
        T.expectEqual("the smell level inside, of ghosts in the building", inside and inside.level, #self.levels)
        T.expectEqual("the smell level outside, of ghosts in a building", outside and outside.level, 0)
    end,
})

-- A gas mask keeps the smell out while its filter drains: no smell comes in, and the moodle rises
-- no higher than an earlier test's fading smell left it.
test("renewable_energy_biogas_stink_gas_mask", {
    run = function(self)
        local _, source = standNearSource(self)
        if not source then return end
        T.give(self, "mask", { { type = "Base.Hat_GasMask", worn = true } })
        withLevels(self, source, function(levels)
            stink(self, source, levels[#levels])
            -- The filter drains only while the mask keeps corpse smell out (getCorpseSicknessDefense).
            T.readUntil(self, "stinkRead", T.at(source), "masked", function(read) return read.mask ~= nil and read.mask < 1 end,
                SMELL_MS)
        end)
    end,
    validate = function(self)
        local read, before = self.reads.masked, self.reads.levels
        T.expect(read.mask and read.mask < 1, "the gas mask's filter is at " .. tostring(read.mask))
        T.expectEqual("the smell rate with a gas mask", read.rate, 0)
        T.expect(read.level <= before.level, "with a gas mask, the smell rose to level " .. read.level .. " from " .. before.level)
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
