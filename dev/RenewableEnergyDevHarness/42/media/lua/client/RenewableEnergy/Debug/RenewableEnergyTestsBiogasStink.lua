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
-- server only), then `fn(levels)` in a step, which queues what uses them.
local function withLevels(self, square, fn)
    T.server(self, "stinkRead", T.at(square))
    T.step(function()
        self.levels = T.need(self, self.server.stinkRead.levels, "the corpse counts of the smell levels")
        if self.levels then
            fn(self.levels)
        end
    end)
end

-- Queues reads of the authority's smell until two in a row, a server update apart, show `level`,
-- or SMELL_MS pass; the last read lands in self.smell[label]. A level that settles elsewhere ends in
-- validate's failure.
local function waitForAuthoritySmell(self, square, level, label)
    local last
    T.serverUntil(self, "stinkRead", T.at(square), function(read)
        local settled = read.level == last
        last = read.level
        return settled and read.level == level
    end, SMELL_MS)
    T.step(function() self.smell[label] = self.server.stinkRead end)
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
        self.smell, self.moodle = {}, {}
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
        for i, count in ipairs(self.levels) do
            local below, at = self.smell["below" .. i], self.smell["at" .. i]
            T.expect(below and below.level == i - 1, (count - 1) .. " ghosts: smell level " .. tostring(below and below.level) .. ", not " .. (i - 1))
            T.expect(at and at.level == i, count .. " ghosts: smell level " .. tostring(at and at.level) .. ", not " .. i)
        end
        local top = self.smell["at" .. #self.levels]
        if T.expect(top ~= nil, "no read at the top smell level") then
            T.expect(top.bodies == 0, "the source's square holds " .. tostring(top.bodies) .. " corpses")
            T.expect(top.objects == 0, "the source's square holds " .. tostring(top.objects) .. " moving objects")
        end
        T.expect(self.moodle.top == #self.levels, "this client's moodle shows level " .. tostring(self.moodle.top) .. " at the top")
        T.expect(self.smell.none and self.smell.none.level == 0, "with the ghosts gone the smell stayed")
        T.expect(self.moodle.none == 0, "with the ghosts gone this client's moodle shows " .. tostring(self.moodle.none))
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
        self.smell = {}
        local source = T.square(self, nil, "a free outdoor square for the source")
        if not source then return end
        self.stands = {}
        for dx = 0, 3 do
            self.stands[dx] = outdoorsInChunk(source, dx)
            if not T.need(self, self.stands[dx], "an outdoor square " .. dx .. " chunks east of the source") then return end
        end
        withLevels(self, source, function(levels)
            local top = levels[#levels]
            T.server(self, "stinkSpread", { count = top })
            T.step(function()
                local own, ring = self.server.stinkSpread.own, self.server.stinkSpread.ring
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
            local read, wanted = self.smell["east" .. dx], levelOf(levels, self.wanted[dx])
            T.expect(read and read.level == wanted, dx .. " chunks east of the source: smell level "
                .. tostring(read and read.level) .. ", not " .. wanted .. " (" .. self.wanted[dx] .. " corpses)")
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
        self.smell = {}
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
        local top = #self.levels
        T.expect(self.smell.inside and self.smell.inside.level == top,
            "inside, ghosts in the building smell at level " .. tostring(self.smell.inside and self.smell.inside.level) .. ", not " .. top)
        T.expect(self.smell.outside and self.smell.outside.level == 0,
            "outside, ghosts in a building smell at level " .. tostring(self.smell.outside and self.smell.outside.level))
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
            self.before = self.server.stinkRead
            stink(self, source, levels[#levels])
            -- The filter drains only while the mask keeps corpse smell out (getCorpseSicknessDefense).
            T.serverUntil(self, "stinkRead", T.at(source), function(read) return read.mask ~= nil and read.mask < 1 end, SMELL_MS)
        end)
    end,
    validate = function(self)
        local read, before = self.server.stinkRead, self.before
        T.expect(read.mask and read.mask < 1, "the gas mask's filter is at " .. tostring(read.mask))
        T.expect(read.rate == 0 and read.level <= before.level, "with a gas mask, the smell is at level " .. tostring(read.level)
            .. " from " .. tostring(before.level) .. ", rate " .. tostring(read.rate))
    end,
})

-- A chunk zeroes its corpse count when it unloads and loads; the ghosts are counted again when it
-- loads, and can be taken away after without the count going wrong. Single player only: a
-- multiplayer server keeps the chunk loaded long after the character leaves.
test("renewable_energy_biogas_stink_chunk_reload", {
    spOnly = T.CHUNK_RELOAD_SP_ONLY,
    timeoutSeconds = 120,
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
        T.expect(self.moodle.before == top, "before: smell level " .. tostring(self.moodle.before))
        T.expect(self.moodle.reloaded == top, "after the chunk loaded again: smell level " .. tostring(self.moodle.reloaded))
        T.expect(self.moodle.cleared == 0, "cleared: smell level " .. tostring(self.moodle.cleared))
        T.expect(self.moodle.again == 1, "the first level's ghosts after: smell level " .. tostring(self.moodle.again) .. ", not 1")
    end,
})
