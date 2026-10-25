require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"

-- Biogas (Contents/.../RenewableEnergy/Biogas/*, UI/Digester*, the propane bottle refill in
-- Recipes.lua): the stink, digestion, the hopper's feed, the gas holder, the digester's jobs, the gas
-- heater, propane, and campfire wood ash. The smell moodle is the authority character's, so the
-- stink tests read it there; a multiplayer client's follows the rate the server sends.

local T = RenewableEnergyTest
local test = T.test

local Digester, DigesterJobs, GasHeater = RenewableEnergy.Digester, RenewableEnergy.DigesterJobs, RenewableEnergy.GasHeater
local Sprites = RenewableEnergy.Sprites

local FEED = "Base.Dung_Cow"

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
local function smellOnAuthority(self, square, level, label)
    local last
    T.serverUntil(self, "stinkRead", T.at(square), function(read)
        local settled = read.level == last
        last = read.level
        return settled and read.level == level
    end, SMELL_MS)
    T.step(function() self.smell[label] = self.server.stinkRead end)
end

-- Queues a wait until this client's smell moodle is at `level`, or SMELL_MS pass, then records the
-- level in self.moodle[label] for validate. The limit is real time, not frames: a multiplayer
-- client's moodle follows the rate the server sends, whatever the frame rate.
local function waitForSmell(self, level, label)
    local deadline
    T.waitUntil(function()
        deadline = deadline or getTimestampMs() + SMELL_MS
        local now = T.player():getMoodles():getMoodleLevel(MoodleType.NOXIOUS_SMELL)
        return now == level or getTimestampMs() > deadline
    end, math.huge, "the smell moodle at " .. level)
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
                smellOnAuthority(self, source, i - 1, "below" .. i)
                stink(self, source, count)
                smellOnAuthority(self, source, i, "at" .. i)
            end
            waitForSmell(self, #levels, "top")
            stink(self, source, 0)
            smellOnAuthority(self, source, 0, "none")
            waitForSmell(self, 0, "none")
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
                    smellOnAuthority(self, source, levelOf(levels, self.wanted[dx]), "east" .. dx)
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
            smellOnAuthority(self, source, #levels, "inside")
            T.step(function() standOn(outside) end)
            smellOnAuthority(self, source, 0, "outside")
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
        local stand, source = standNearSource(self)
        if not source then return end
        withLevels(self, source, function(levels)
            stink(self, source, levels[#levels])
            waitForSmell(self, #levels, "before")
            T.awayAndBack(self, T.at(stand), source:getX(), source:getY(), source:getZ())
            waitForSmell(self, #levels, "reloaded")
            stink(self, source, 0)
            waitForSmell(self, 0, "cleared")
            stink(self, source, levels[1])
            waitForSmell(self, 1, "again")
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

-- How strongly a digester stinks, as corpses: a mature barrel at the first smell level, a sour one
-- at the second; an unfed one not at all; the Brick Dome never past the first, at its worst.
test("renewable_energy_biogas_digester_stink_levels", {
    run = function(self)
        local barrel = T.placeRecord(self, "digester", "barrel.MetalDrum")
        local dome = barrel and T.placeRecord(self, "digester", "dome")
        if not dome then return end
        -- Mid-startup, when the startup stinks most, full, its sludge at the top and sour.
        local worst = T.sourDigester("dome", { started = false, startupHours = getSandboxOptions():getCompostHours() / 2, seedHours = 0,
            sludge = 100 })
        T.batch(function()
            T.server(self, "stinkRead", T.at(barrel))
            T.server(self, "digesterCorpsesFor", {})
            T.setRecord(self, barrel, T.matureDigester("barrel"))
            T.readRecord(self, barrel, "mature")
            T.setRecord(self, barrel, T.sourDigester("barrel"))
            T.readRecord(self, barrel, "sour")
            T.setRecord(self, barrel, { fed = false })
            T.readRecord(self, barrel, "unfed")
            T.setRecord(self, dome, worst)
            T.readRecord(self, dome, "dome")
        end)
    end,
    validate = function(self)
        T.expectNoFailures(self.server.digesterCorpsesFor)
        local levels = self.server.stinkRead.levels
        local reads = self.reads
        local function within(label, lowest, below)
            local ghosts = reads[label].ghosts
            T.expect(ghosts >= lowest and (not below or ghosts < below), "the " .. label .. " digester counts as " .. ghosts .. " corpses")
        end
        within("mature", levels[1], levels[2])
        within("sour", levels[2], levels[3])
        within("unfed", 0, 1)
        within("dome", 0, levels[2])
    end,
})

-- Digestion --------------------------------------------------------------------------------------

-- No gas until the startup's warm hours are done: at STARTUP_MIN_TEMP the hours count and a degree
-- below they don't; it starts at exactly the hours needed, and makes gas after. Manure's head start
-- shortens it by at most its share.
test("renewable_energy_biogas_digester_startup_then_gas", {
    run = function(self)
        local handle = T.placeRecord(self, "digester", "barrel.MetalDrum")
        if not handle then return end
        local needed = getSandboxOptions():getCompostHours()
        local edge, below = Digester.STARTUP_MIN_TEMP, Digester.STARTUP_MIN_TEMP - 1
        local function fresh(fields)
            local state = { fed = true, started = false, startupHours = 0, seedHours = 0, gas = 0,
                potential = Digester.TIERS.barrel.potentialCap }
            for key, value in pairs(fields) do
                state[key] = value
            end
            T.setRecord(self, handle, state)
        end
        -- Seeded with more than its share can cover, it still waits out the rest.
        local seededWait = needed * (1 - Digester.SEED_SHARE)
        T.batch(function()
            fresh({ temp = below })
            T.runDigester(self, handle, needed, below)
            T.readRecord(self, handle, "cold")
            fresh({ temp = edge })
            T.runDigester(self, handle, needed - 1, edge)
            T.readRecord(self, handle, "before")
            T.runDigester(self, handle, 1, edge)
            T.readRecord(self, handle, "at")
            T.runDigester(self, handle, 1, 30)
            T.readRecord(self, handle, "after")
            fresh({ temp = 30, seedHours = needed })
            T.runDigester(self, handle, seededWait - 1, 30)
            T.readRecord(self, handle, "seededBefore")
            T.runDigester(self, handle, 2, 30)
            T.readRecord(self, handle, "seededAfter")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        T.expect(not reads.cold.started, "it started below " .. Digester.STARTUP_MIN_TEMP .. " °C")
        T.expect(not reads.before.started and reads.before.gas == 0, "it started, or made gas, an hour before the startup ended")
        T.expect(reads.at.started, "it didn't start once the startup's hours were done at " .. Digester.STARTUP_MIN_TEMP .. " °C")
        T.expect(reads.after.gas > 0, "no gas after the startup")
        T.expect(not reads.seededBefore.started, "manure's head start covered more than its share")
        T.expect(reads.seededAfter.started, "manure's head start didn't shorten the startup")
    end,
})

-- Digestion follows temperature: none at the coldest and hottest edges, some a degree inside each,
-- the same along the best stretch. The barrel follows the air within days.
test("renewable_energy_biogas_digester_temperature", {
    run = function(self)
        local handle = T.placeRecord(self, "digester", "barrel.MetalDrum")
        if not handle then return end
        local rows = Digester.K_BY_TEMP
        local best = 0
        for _, row in ipairs(rows) do
            best = math.max(best, row[2])
        end
        self.plateau = {}
        for _, row in ipairs(rows) do
            if row[2] == best then
                table.insert(self.plateau, row[1])
            end
        end
        local coldest, hottest = rows[1][1], rows[#rows][1]
        self.none = { coldest, hottest }
        self.some = { coldest + 1, hottest - 1 }
        local temps = { coldest, coldest + 1, hottest - 1, hottest, self.plateau[1], self.plateau[#self.plateau] }
        T.batch(function()
            for _, temp in ipairs(temps) do
                T.setRecord(self, handle, T.matureDigester("barrel", { temp = temp, gas = 0 }))
                T.runDigester(self, handle, 1, temp)
                T.readRecord(self, handle, "at" .. temp)
            end
            T.setRecord(self, handle, T.matureDigester("barrel"))
            T.runDigester(self, handle, 72, 0)
            T.readRecord(self, handle, "cooled")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        for _, temp in ipairs(self.none) do
            T.expect(reads["at" .. temp].gas == 0, "it made gas at " .. temp .. " °C")
        end
        for _, temp in ipairs(self.some) do
            T.expect(reads["at" .. temp].gas > 0, "it made no gas at " .. temp .. " °C")
        end
        local first, last = self.plateau[1], self.plateau[#self.plateau]
        T.expectNear("gas at " .. last .. " °C against " .. first, reads["at" .. last].gas, reads["at" .. first].gas, 1e-6)
        local start = T.matureDigester("barrel").temp
        T.expect(reads.cooled.temp < start / 2, "three days at 0 °C left the barrel at " .. reads.cooled.temp .. " °C from " .. start)
    end,
})

-- The Biogas Multiplier scales the gas a digester makes in proportion.
test("renewable_energy_biogas_digester_multiplier_scales_gas", {
    run = function(self)
        local handle = T.placeRecord(self, "digester", "barrel.MetalDrum")
        if not handle then return end
        local function runAt(multiplier, label)
            T.step(function() T.setSandbox(self, "BiogasMultiplier", multiplier) end)
            T.batch(function()
                local state = T.matureDigester("barrel", { gas = 0 })
                T.setRecord(self, handle, state)
                T.runDigester(self, handle, 2, state.temp)
                T.readRecord(self, handle, label)
            end)
        end
        runAt(1, "single")
        runAt(2, "double")
    end,
    validate = function(self)
        local single, double = self.reads.single.gas, self.reads.double.gas
        if not T.expect(single > 0, "a mature digester made no gas in two hours") then return end
        T.expectNear("gas at a Biogas Multiplier of 2 over the same run at 1", double / single, 2, 0.01)
    end,
})

-- Acid just over the limit sours it and just under doesn't; once sour it stays sour until just
-- below the share of the limit it recovers at. Wood ash fixes it whole, baking soda a use at a time.
test("renewable_energy_biogas_digester_sour_and_fix", {
    run = function(self)
        local handle = T.placeRecord(self, "digester", "barrel.MetalDrum")
        if not handle then return end
        local limit = Digester.ACID_LIMIT * Digester.TIERS.barrel.potentialCap
        local function set(share, sour)
            T.setRecord(self, handle, T.matureDigester("barrel", { acid = share * limit, sour = sour }))
        end
        -- An hour's decay takes far less acid than the step, so each side stays on its side.
        local step = 0.01
        local recover = Digester.ACID_RECOVER
        T.batch(function()
            for _, case in ipairs({ { "over", 1 + step, false }, { "under", 1 - step, false },
                { "sourAbove", recover + step, true }, { "sourBelow", recover - step, true } }) do
                set(case[2], case[3])
                T.runDigester(self, handle, 1, 30)
                T.readRecord(self, handle, case[1])
            end
            set(1 + step, true)
            T.fillRecord(self, handle, { hopper = { { type = RenewableEnergy.Gasifier.WOOD_ASH } } })
            T.runDigester(self, handle, 1, 30)
            T.readRecord(self, handle, "ash")
            set(1 + step, true)
            T.fillRecord(self, handle, { hopper = { { type = "Base.BakingSoda" } } })
            T.runDigester(self, handle, 1, 30)
            T.readRecord(self, handle, "soda")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        T.expect(reads.over.sour, "acid just over the limit didn't sour it")
        T.expect(not reads.under.sour, "acid just under the limit soured it")
        T.expect(reads.sourAbove.sour, "a sour digester recovered just above its recovery share of the limit")
        T.expect(not reads.sourBelow.sour, "a sour digester stayed sour just below its recovery share of the limit")
        T.expect(not reads.ash.sour and reads.ash.hopperItems == 0, "wood ash didn't fix it, or stayed in the hopper")
        T.expect(not reads.soda.sour, "baking soda didn't fix it")
        T.expect(reads.soda.hopperItems == 1, "a used box of baking soda left the hopper")
    end,
})

-- Feed -------------------------------------------------------------------------------------------

-- The hopper takes feed and alkalis only, on this client's copy as in the loot window, and feeds
-- one item an hour until the tank holds its cap; manure eaten brings its head start.
test("renewable_energy_biogas_digester_hopper_meters", {
    run = function(self)
        local handle = T.placeRecord(self, "digester", "barrel.MetalDrum")
        if not handle then return end
        self.digester = handle
        self.cow = Digester.feedOf(instanceItem(FEED))
        self.fits = math.floor(Digester.TIERS.barrel.potentialCap / self.cow.potential + 1e-6)
        -- More than fits, run first for an hour less than eating what fits takes.
        self.count, self.firstHours = self.fits + 2, self.fits - 1
        self.left = self.count - self.fits
        T.batch(function()
            T.fillRecord(self, handle, { hopper = { { type = FEED, count = self.count } } })
            T.runDigester(self, handle, self.firstHours, 25)
            T.readRecord(self, handle, "metered")
            T.runDigester(self, handle, self.count, 25)
            T.readRecord(self, handle, "after")
        end)
        T.waitForSummary(self, handle, function(summary) return summary.hopper == self.left end, "this client's count of the hopper")
    end,
    validate = function(self)
        local metered, after = self.reads.metered, self.reads.after
        T.expect(metered.hopperItems == self.count - self.firstHours,
            "in " .. self.firstHours .. " hours it ate " .. (self.count - metered.hopperItems) .. " items, not one an hour")
        T.expectNear("undigested potential", after.potential, Digester.TIERS.barrel.potentialCap, 0.001)
        T.expect(after.hopperItems == self.left, "the hopper holds " .. tostring(after.hopperItems) .. " items, not " .. self.left)
        T.expectNear("startup the manure seeded", after.seedHours, self.fits * self.cow.seedHours, 0.001)
        local container = self.digester.object:getContainer()
        local function allowed(fullType)
            return container:isItemAllowed(instanceItem(fullType))
        end
        T.expect(allowed(FEED) and allowed(RenewableEnergy.Gasifier.WOOD_ASH), "this client's hopper refuses manure or wood ash")
        T.expect(not allowed("Base.Apple") and not allowed("Base.Hammer"), "this client's hopper takes a fresh apple or a hammer")
        -- Every animal's dung, not only the farm animals the feed table names.
        local dung, refused = 0, {}
        local scripts = getScriptManager():getAllItems()
        for i = 0, scripts:size() - 1 do
            local fullType = scripts:get(i):getFullName()
            if fullType:find("^Base%.Dung_") then
                dung = dung + 1
                if not allowed(fullType) then table.insert(refused, fullType) end
            end
        end
        T.expect(dung > 0 and #refused == 0, "of " .. dung .. " kinds of dung, this client's hopper refuses "
            .. table.concat(refused, ", "))
    end,
})

-- While its chunk is unloaded a digester keeps eating from what its hopper held, an item an hour;
-- when the chunk loads, what it ate has left the hopper. Single player only, as the chunk reload
-- test.
test("renewable_energy_biogas_digester_eats_while_unloaded", {
    spOnly = T.CHUNK_RELOAD_SP_ONLY,
    timeoutSeconds = 120,
    run = function(self)
        local stand = T.square(self, nil, "a free outdoor square to stand on")
        local handle = stand and T.placeRecord(self, "digester", "barrel.MetalDrum", { near = stand, minDistance = 2 })
        if not handle then return end
        T.fillRecord(self, handle, { hopper = { { type = FEED, count = 4 } } })
        -- Part of an hour already on the meter, so each whole hour away eats one item.
        T.runDigester(self, handle, 0.5, 25)
        T.awayAndBack(self, T.at(stand), handle.x, handle.y, handle.z, function()
            T.ageRecord(self, handle, 3, "away")
        end)
        T.readRecord(self, handle, "back")
    end,
    validate = function(self)
        local away, back = self.reads.away, self.reads.back
        local cow = Digester.feedOf(instanceItem(FEED))
        T.expect(not away.loaded, "the digester's tile stayed loaded")
        T.expect(away.eaten == 3 and away.snapshot == 1, "unloaded, it ate " .. away.eaten .. " and left " .. away.snapshot)
        T.expectNear("potential eaten while unloaded", away.potential, 3 * cow.potential, 0.001)
        T.expect(back.hopperItems == 1, "back, the hopper holds " .. back.hopperItems .. " items, not 1")
    end,
})

-- Holder -----------------------------------------------------------------------------------------

-- The bags hold what they can and vent the rest; worn through they tear, hold nothing and show
-- torn; Replace Bags takes new bags and mends them.
test("renewable_energy_biogas_digester_holder", {
    instant = true,
    run = function(self)
        local handle = T.placeRecord(self, "digester", "barrel.MetalDrum")
        if not handle then return end
        local bags = Digester.HOLDERS.bags
        local overfull = T.matureDigester("barrel", { gas = bags.capacity + 0.1 })
        T.batch(function()
            T.setRecord(self, handle, overfull)
            T.runDigester(self, handle, 1, 30)
            T.readRecord(self, handle, "full")
            -- Less wear left than the run takes, so it tears them.
            T.setRecord(self, handle, { holderCondition = bags.wearPerDay / 2 })
            T.runDigester(self, handle, 24, 30)
            T.readRecord(self, handle, "torn")
        end)
        T.waitForSummary(self, handle, function(summary) return summary.torn end, "this client's summary of the torn bags")
        self.replace = DigesterJobs.materials(DigesterJobs.REPLACE_BAGS)
        T.giveMaterials(self, "bags", self.replace)
        T.gasJob(self, "digester", handle, DigesterJobs.REPLACE_BAGS)
        T.batch(function()
            T.readRecord(self, handle, "mended")
            T.countMaterials(self, "left", self.replace)
        end)
    end,
    validate = function(self)
        local reads, levels = self.reads, Sprites.digesterHolder.bags
        T.expectNear("gas in full bags", reads.full.gas, Digester.HOLDERS.bags.capacity, 0.001)
        T.expect(T.hasOverlay(reads.full, levels[#levels]), "full bags don't show full")
        T.expect(reads.torn.torn and reads.torn.gas == 0, "worn-out bags still hold gas")
        T.expect(T.hasOverlay(reads.torn, Sprites.digesterHolder.bagsTorn), "torn bags don't show torn")
        T.expect(reads.mended.holderCondition == 100 and not reads.mended.torn, "new bags didn't mend it")
        T.expect(T.hasOverlay(reads.mended, levels[1]), "new bags don't show empty")
        T.expectMaterialsUsed(self, "left", self.replace, "Replace Bags")
    end,
})

-- Jobs -------------------------------------------------------------------------------------------

-- Take Sludge refuses without a bag to fill; it fills an empty sandbag into a compost bag, a use per
-- share of sludge as vanilla's composter does, up to a full bag; less sludge than a bag holds goes
-- into a part-filled bag.
test("renewable_energy_biogas_digester_sludge_into_bags", {
    instant = true,
    run = function(self)
        local handle = T.placeRecord(self, "digester", "barrel.MetalDrum")
        if not handle then return end
        local full, part = 3.5 * Digester.SLUDGE_PER_BAG, Digester.SLUDGE_PER_BAG / 2
        self.full = full
        T.setRecord(self, handle, { sludge = full })
        T.waitForSummary(self, handle, function(summary) return summary.sludge == full end, "this client's summary of the sludge")
        T.step(function() self.noBag = DigesterJobs.refusal(T.player(), DigesterJobs.TAKE_SLUDGE, handle.object) end)
        T.give(self, "bags", { { type = DigesterJobs.SANDBAG, count = 2 } })
        T.gasJob(self, "digester", handle, DigesterJobs.TAKE_SLUDGE, function() return self.items.bags[1] end)
        T.batch(function()
            T.readRecord(self, handle, "first")
            T.setRecord(self, handle, { sludge = part })
        end)
        T.waitForSummary(self, handle, function(summary) return summary.sludge == part end, "this client's summary of the sludge")
        T.gasJob(self, "digester", handle, DigesterJobs.TAKE_SLUDGE, function() return self.items.bags[2] end)
        T.batch(function()
            T.readRecord(self, handle, "second")
            T.readCarried(self, { DigesterJobs.COMPOST_BAG, DigesterJobs.SANDBAG })
        end)
    end,
    validate = function(self)
        T.expect(self.noBag == "Tooltip_RenewableEnergy_NeedsSandbag", "Take Sludge with no bag: " .. tostring(self.noBag))
        T.expectNear("sludge left after a full bag", self.reads.first.sludge, self.full - Digester.SLUDGE_PER_BAG, 0.001)
        T.expectNear("sludge left after a part bag", self.reads.second.sludge, 0, 0.001)
        local bags = T.carriedItems(self, DigesterJobs.COMPOST_BAG)
        T.expect(#T.carriedItems(self, DigesterJobs.SANDBAG) == 0 and #bags == 2, "the sandbags didn't become compost bags")
        if #bags == 2 then
            local fullest, other = math.max(bags[1].uses, bags[2].uses), math.min(bags[1].uses, bags[2].uses)
            T.expectNear("the first bag", fullest, 1, 0.001)
            T.expectNear("the part bag", other, 0.5, 0.001)
        end
    end,
})

-- Upgrading a barrel builds the insulated digester around it in place: the tile, the floating drum,
-- the bigger hopper on this client too; what it held stays, and the job takes its materials.
test("renewable_energy_biogas_digester_upgrade", {
    instant = true,
    run = function(self)
        local handle = T.placeRecord(self, "digester", "barrel.MetalDrum")
        if not handle then return end
        self.digester = handle
        self.capacity = tonumber(getSprite(Sprites.digester.insulated):getProperties():get("ContainerCapacity"))
        self.upgrade = DigesterJobs.materials(DigesterJobs.UPGRADE)
        self.dung = 2
        -- At its cap, so it eats nothing from the hopper meanwhile.
        T.batch(function()
            T.setRecord(self, handle, T.matureDigester("barrel"))
            T.fillRecord(self, handle, { hopper = { { type = FEED, count = self.dung } } })
        end)
        T.giveMaterials(self, "materials", self.upgrade)
        T.gasJob(self, "digester", handle, DigesterJobs.UPGRADE)
        T.batch(function()
            T.readRecord(self, handle, "after")
            T.countMaterials(self, "left", self.upgrade)
        end)
        T.waitFor(self, function()
            local container = handle.object:getContainer()
            return container ~= nil and container:getCapacity() == self.capacity
        end, "this client's copy of the bigger hopper")
        -- The insulated digester's entity, or each load of it logs "Invalid SpriteConfig object!".
        T.waitFor(self, function()
            local config = handle.object:getSpriteConfig()
            return config ~= nil and config:isValid()
        end, "this client's copy being the insulated digester's entity")
    end,
    validate = function(self)
        local after = self.reads.after
        T.expect(after.tier == "insulated" and after.holder == "drum", "the tier is " .. tostring(after.tier) .. " with " .. tostring(after.holder))
        T.expect(after.sprite == Sprites.digester.insulated, "the tile is " .. tostring(after.sprite))
        T.expect(after.containerCapacity == self.capacity, "the hopper holds " .. tostring(after.containerCapacity) .. ", not " .. tostring(self.capacity))
        T.expect(after.hopperItems == self.dung, "the hopper holds " .. tostring(after.hopperItems) .. " of its " .. self.dung .. " manures")
        T.expectNear("potential kept", after.potential, Digester.TIERS.barrel.potentialCap, 0.01)
        T.expectMaterialsUsed(self, "left", self.upgrade, "Upgrade")
    end,
})

-- Queues, on this client's copy of the barrel digester `handle` showing the tile `tile`, what a
-- player does with it, into self.views[label]: its status window's title, and whether its hopper
-- took the cow dung they dragged in (the record's count, in self.reads[label]). Also whether its
-- SpriteConfig took the tile: the game logs "Invalid SpriteConfig object!" wherever an object
-- loads with one that didn't, and vanilla's menus get no master object for it.
local function useDrumDigester(self, handle, tile, label)
    T.waitFor(self, function()
        handle.object = T.objectWithSprite(getSquare(handle.x, handle.y, handle.z), tile)
        return handle.object ~= nil and Digester.summaryOf(handle.object) ~= nil
    end, "this client's copy of the " .. tile .. " digester")
    T.give(self, label, { { type = FEED, count = 1 } })
    T.step(function()
        local object, p = handle.object, T.player()
        if not object then return end
        local config = object:getSpriteConfig()
        -- Where the menu's Status walks them: the window closes once they are out of reach.
        T.standNextTo(getSquare(handle.x, handle.y, handle.z))
        local window = RenewableEnergy.DigesterWindow:openOn(0, object)
        window:prerender()
        self.views[label] = { title = window.title, configValid = config ~= nil and config:isValid(),
            master = object:getMasterObject() == object }
        window:close()
        ISTimedActionQueue.add(ISInventoryTransferAction:new(p, self.items[label][1], p:getInventory(), object:getContainer()))
    end)
    T.waitFor(self, function() return handle.object and handle.object:getContainer():containsType(FEED) end,
        "this client's hopper holding the dung")
    T.readRecord(self, handle, label)
end

-- Expects useDrumDigester's `label` to have found a whole barrel digester.
local function expectDrumDigester(self, label)
    local view, read = self.views[label], self.reads[label]
    if not T.expect(view ~= nil and read ~= nil, label .. ": never saw the digester") then return end
    T.expect(view.title == getText("IGUI_RenewableEnergy_Digester_barrel"), label .. ": the status window's title is " .. tostring(view.title))
    T.expect(view.configValid and view.master, label .. ": its SpriteConfig refused its tile")
    T.expect(read.hopperItems == 1, label .. ": the hopper holds " .. tostring(read.hopperItems) .. " items, not the dung dragged in")
end

-- The build menu's own path builds a working digester from the barrel `barrel` (an item type): the
-- entity's recipe takes its materials, keeps its tools, and its OnCreate makes the tile the
-- digester of that barrel on the authority, which this client sees, opens and feeds.
local function buildsBarrelDigester(barrel)
    local tile = Sprites.digester.barrel[barrel]
    return {
        instant = true,
        run = function(self)
            self.views = {}
            local handle = T.buildRecord(self, "digester", "Base.RenewableEnergy_BarrelDigester", tile, { "Base." .. barrel })
            if not handle then return end
            useDrumDigester(self, handle, tile, "fed")
        end,
        validate = function(self)
            local built = self.reads.built or {}
            T.expect(built.tier == "barrel", "the build menu built " .. tostring(built.tier))
            T.expectBuilt(self, tile)
            expectDrumDigester(self, "fed")
        end,
    }
end

test("renewable_energy_biogas_build_menu_builds_digester", buildsBarrelDigester("MetalDrum"))
-- The game's barrels are steel drums too; the digester shows the one it took, and is that drum's
-- entity.
test("renewable_energy_biogas_build_from_orange_barrel_shows_orange", buildsBarrelDigester("Mov_OrangeBarrel"))
test("renewable_energy_biogas_build_from_dark_green_barrel_shows_dark_green", buildsBarrelDigester("Mov_DarkGreenBarrel"))
test("renewable_energy_biogas_build_from_light_green_barrel_shows_light_green", buildsBarrelDigester("Mov_LightGreenBarrel"))

-- The brick dome's pit is dug, so its build cursor takes the ground, as vanilla's grave does, and
-- refuses a building's floor.
test("renewable_energy_biogas_brick_dome_builds_only_on_ground", {
    instant = true,
    run = function(self)
        local ground
        for _, square in ipairs(T.squares(self, 24, { bare = true }) or {}) do
            local name = Sprites.nameOf(square:getFloor())
            if name and PZHarness.startsWith(name, "blends_natural") then
                ground = square
                break
            end
        end
        local indoors = T.square(self, { indoors = true }, "a free indoor square")
        if not (T.need(self, ground, "a bare square of natural ground") and indoors) then return end
        self.onGround = T.placeable("Base.RenewableEnergy_BrickDome", ground)
        self.indoors = T.placeable("Base.RenewableEnergy_BrickDome", indoors)
    end,
    validate = function(self)
        T.expect(self.onGround == true, "the cursor refuses natural ground: " .. tostring(self.onGround))
        T.expect(self.indoors == false, "the cursor takes a building's floor: " .. tostring(self.indoors))
    end,
})

-- A digester built from a barrel loads whole from the save: its chunk unloaded and loaded again, it
-- still opens and takes feed. Single player only, as the chunk reload test.
test("renewable_energy_biogas_barrel_digester_reloads_whole", {
    spOnly = T.CHUNK_RELOAD_SP_ONLY,
    timeoutSeconds = 120,
    instant = true,
    run = function(self)
        self.views = {}
        local tile = Sprites.digester.barrel.Mov_LightGreenBarrel
        local handle = T.buildRecord(self, "digester", "Base.RenewableEnergy_BarrelDigester", tile, { "Base.Mov_LightGreenBarrel" })
        if not handle then return end
        -- Where the build left the character, filled in once it stands there.
        local home = {}
        T.step(function()
            local square = T.player():getCurrentSquare()
            home.x, home.y, home.z = square:getX(), square:getY(), square:getZ()
        end)
        T.awayAndBack(self, home, handle.x, handle.y, handle.z)
        useDrumDigester(self, handle, tile, "reloaded")
    end,
    validate = function(self)
        expectDrumDigester(self, "reloaded")
    end,
})

-- Right-clicking a barrel digester shows its submenu through vanilla's menu builder: its status,
-- and its jobs greyed out with the reason while the digester or the character can't do them. The
-- status window opens on it and shows its state.
test("renewable_energy_biogas_digester_menu", {
    run = function(self)
        self.digester = T.placeRecord(self, "digester", "barrel.MetalDrum")
    end,
    validate = function(self)
        local object = self.digester.object
        local function job(name)
            return getText("ContextMenu_RenewableEnergy_" .. name)
        end
        local options = T.worldOptions(object, getText("IGUI_RenewableEnergy_Digester_barrel"), { status = job("Status"),
            sludge = job(DigesterJobs.TAKE_SLUDGE), vent = job(DigesterJobs.VENT), bags = job(DigesterJobs.REPLACE_BAGS),
            tarp = job(DigesterJobs.SEW_TARP), upgrade = job(DigesterJobs.UPGRADE) })
        if T.expect(options ~= nil, "right-clicking a digester shows no digester submenu") then
            T.expect(options.status ~= nil, "no Status option")
            local sludge = options.sludge
            T.expect(sludge and sludge.notAvailable and sludge.toolTip.description == getText("Tooltip_RenewableEnergy_NoSludge"),
                "Take Sludge isn't greyed out for an empty digester")
            T.expect(options.vent and options.vent.notAvailable, "Vent Gas isn't greyed out with no gas")
            T.expect(options.bags ~= nil and options.tarp ~= nil, "no holder options on a barrel")
            local upgrade = options.upgrade
            T.expect(upgrade and upgrade.notAvailable and upgrade.toolTip.description:find(getItemNameFromFullType("Base.Plank"), 1, true),
                "Upgrade isn't greyed out listing its planks")
        end
        T.standNextTo(object:getSquare())
        local window = RenewableEnergy.DigesterWindow:openOn(0, object)
        window:prerender()
        T.expect(window.title == getText("IGUI_RenewableEnergy_Digester_barrel"), "the status window's title is " .. tostring(window.title))
        T.expect(window.rowsToDraw and window.rowsToDraw[1].value == getText("IGUI_RenewableEnergy_DigesterEmpty"),
            "the status window doesn't say the digester is empty")
        window:close()
    end,
})

-- Heater -----------------------------------------------------------------------------------------

-- The sprite this client shows of the gas heater on `square`, or nil.
local function heaterSprite(square)
    local heater = RenewableEnergy.findObjectOn(square, GasHeater.isHeater)
    return heater and heater:getSprite():getName()
end

-- A barrel digester with full bags and an unlit gas heater facing `facing` (S if nil) beside it,
-- with what lighting takes given: the digester's handle, the heater's and the heater's square, or
-- nil.
local function fedDigesterAndHeater(self, facing)
    local digester = T.placeRecord(self, "digester", "barrel.MetalDrum")
    local square = digester and T.square(self, { near = digester.square }, "a square beside the digester for a heater")
    if not square then return nil end
    local fed = T.matureDigester("barrel", { gas = Digester.HOLDERS.bags.capacity })
    T.setRecord(self, digester, fed)
    T.waitForGas(self, digester, fed.gas)
    local heater = T.placeTile(self, square, Sprites.gasHeater.off[facing or "S"])
    T.giveMaterials(self, "light", GasHeater.materials(GasHeater.LIGHT))
    return digester, heater, square
end

-- A lit gas heater keeps one digester beside it warm on that digester's gas, the other beside it
-- neither warmed nor paying, and goes out when the gas does. Each digester's own pass finds the
-- heater as its tile shows and the air as its square has it.
test("renewable_energy_biogas_heater_warms_digester", {
    instant = true,
    -- A heavier burn, so hours of it stand out from the digester's own gas.
    sandbox = { GeneratorFuelConsumption = 1 },
    run = function(self)
        local first = T.placeRecord(self, "digester", "barrel.MetalDrum")
        local square = first and T.square(self, { near = first.square }, "a square beside the digester for a heater")
        local second = square and T.placeRecord(self, "digester", "barrel.MetalDrum", { near = square })
        if not second then return end
        self.digesters = { first, second }
        self.rate = GasHeater.m3PerHour()
        -- Gas for more than the warming hours and less than the whole run.
        self.temp, self.gas = 5, 4.5 * self.rate
        if not T.need(self, self.gas < Digester.HOLDERS.bags.capacity, "bags that hold four and a half hours of the heater's gas") then return end
        local cold = T.matureDigester("barrel", { temp = self.temp, gas = self.gas })
        for _, handle in ipairs(self.digesters) do
            T.setRecord(self, handle, cold)
            T.waitForGas(self, handle, self.gas)
        end
        local heater = T.placeTile(self, square, Sprites.gasHeater.off.S)
        T.giveMaterials(self, "light", GasHeater.materials(GasHeater.LIGHT))
        T.gasJob(self, "heater", heater, GasHeater.LIGHT)
        T.batch(function()
            for i, handle in ipairs(self.digesters) do
                T.runDigester(self, handle, 3, 0)
                T.readRecord(self, handle, "warming" .. i)
            end
            for i, handle in ipairs(self.digesters) do
                T.ageRecord(self, handle, 1, "aged" .. i)
            end
            for i, handle in ipairs(self.digesters) do
                T.runDigester(self, handle, 6, 0)
                T.readRecord(self, handle, "out" .. i)
            end
        end)
        T.waitFor(self, function() return heaterSprite(square) == Sprites.gasHeater.off.S end,
            "the heater going out on this client once its gas ran out")
    end,
    validate = function(self)
        local reads = self.reads
        local warmed = reads.warming1.heaterLit and 1 or reads.warming2.heaterLit and 2
        if not T.expect(warmed, "a lit heater warmed neither digester beside it") then return end
        local other = 3 - warmed
        local warming, idle = reads["warming" .. warmed], reads["warming" .. other]
        T.expect(warming.temp > self.temp, "a lit heater didn't warm its digester: " .. tostring(warming.temp) .. " °C")
        T.expectNear("gas after 3 hours of heating", warming.gas, self.gas - 3 * self.rate, self.rate)
        T.expect(not idle.heaterLit and idle.temp < self.temp, "the heater warmed both digesters beside it")
        T.expectNear("gas of the digester it doesn't warm", idle.gas, self.gas, self.rate)
        T.expect(not reads["out" .. warmed].heaterLit, "the heater kept burning with no gas")
        -- Over an hour's pass a digester's temperature closes on its target by the share its tier's
        -- days give (DigesterObject:step).
        local function expectPass(i, target, what)
            local before, aged = reads["warming" .. i], reads["aged" .. i]
            local share = 1 - math.exp(-1 / (Digester.TIERS.barrel.days * 24))
            T.expectNear(what, aged.temp, before.temp + (target - before.temp) * share, 0.001)
        end
        local aged, agedOther = reads["aged" .. warmed], reads["aged" .. other]
        T.expect(aged.heaterLit and not agedOther.heaterLit, "the digesters' own passes didn't find the heater its tile shows lit")
        expectPass(warmed, math.max(aged.air, GasHeater.TEMP), "temperature of the heated digester after its own pass")
        expectPass(other, agedOther.air, "temperature of the other digester after its own pass, in its square's air")
    end,
})

-- A lit gas heater goes out, on this client too, when the digester it burns from is taken away;
-- turned to face W, it stays facing W as it lights and goes out.
test("renewable_energy_biogas_heater_out_when_digester_gone", {
    instant = true,
    run = function(self)
        local digester, heater, square = fedDigesterAndHeater(self, "W")
        if not digester then return end
        T.gasJob(self, "heater", heater, GasHeater.LIGHT)
        T.waitFor(self, function() return heaterSprite(square) == Sprites.gasHeater.lit.W end, "this client's copy of the heater lit")
        T.removeRecord(self, digester)
        T.waitFor(self, function() return heaterSprite(square) == Sprites.gasHeater.off.W end,
            "the heater going out on this client once its digester was gone")
    end,
})

-- A heater's job gives the XP its row names, once done, through the gas jobs' shared XP path. No
-- heater row names any, so the test gives Light Heater some.
test("renewable_energy_biogas_heater_job_gives_its_xp", {
    instant = true,
    run = function(self)
        local digester, heater, square = fedDigesterAndHeater(self)
        if not digester then return end
        T.batch(function()
            T.server(self, "gasJobXp", { module = "GasHeater", job = GasHeater.LIGHT, perk = "Electricity", amount = 10 })
            T.read(self, "perkXp", { perk = "Electricity" }, "before")
        end)
        T.gasJob(self, "heater", heater, GasHeater.LIGHT)
        T.waitFor(self, function() return heaterSprite(square) == Sprites.gasHeater.lit.S end, "this client's copy of the heater lit")
        T.read(self, "perkXp", { perk = "Electricity" }, "after")
    end,
    validate = function(self)
        local before, after = self.reads.before.value, self.reads.after.value
        T.expect(after > before, "lighting the heater gave no Electricity XP, though its row names some: " .. before .. " before, " .. after .. " after")
    end,
})

-- Propane ----------------------------------------------------------------------------------------

-- Queues a wait until this client has power where the character stands.
local function waitForPower(self)
    T.waitFor(self, function()
        local here = T.player():getCurrentSquare()
        return here ~= nil and here:haveElectricity()
    end, "power where the character stands")
end

-- A tire pump moves the digester's gas into a propane tank up to PUMP_FILL and no further, then
-- refuses it; the work costs endurance by the m³.
test("renewable_energy_biogas_pump_fills_tank_to_limit", {
    instant = true,
    run = function(self)
        local handle = T.placeRecord(self, "digester", "dome")
        if not handle then return end
        self.digester = handle
        self.gas = Digester.HOLDERS.dome.capacity
        local full = T.matureDigester("dome", { gas = self.gas })
        T.batch(function()
            T.setRecord(self, handle, full)
            T.server(self, "setCharacterStatUntilEnd", { stat = "ENDURANCE", value = 1 })
        end)
        T.waitForGas(self, handle, self.gas)
        -- Room for half the gas under the pump's limit, so it stops there with gas left.
        self.pumped = math.min(self.gas, Digester.PUMP_FILL * Digester.M3_PER_TANK) / 2
        T.give(self, "tools", { { type = Digester.PUMP }, { type = Digester.TANK, uses = Digester.PUMP_FILL - self.pumped / Digester.M3_PER_TANK } })
        T.gasJob(self, "digester", handle, DigesterJobs.FILL_PUMP, function() return self.items.tools[2] end)
        T.batch(function()
            T.readRecord(self, handle, "after")
            T.server(self, "characterStats", { stats = { "ENDURANCE" } })
        end)
        T.readCarried(self, { Digester.TANK })
        T.waitFor(self, function() return self.items.tools[2]:getCurrentUsesFloat() >= Digester.PUMP_FILL - 0.001 end,
            "this client's copy of the pumped tank")
    end,
    validate = function(self)
        local tank = T.carriedFirst(self, Digester.TANK)
        if T.expect(tank ~= nil, "the tank is gone") then
            T.expectNear("tank after pumping", tank.uses, Digester.PUMP_FILL, 0.001)
        end
        T.expectNear("gas left", self.reads.after.gas, self.gas - self.pumped, 0.02)
        T.expectNear("endurance after pumping " .. self.pumped .. " m³", self.server.characterStats.values.ENDURANCE,
            1 - self.pumped * Digester.PUMP_ENDURANCE_PER_M3, 0.02)
        local refusal = DigesterJobs.refusal(T.player(), DigesterJobs.FILL_PUMP, self.digester.object, self.items.tools[2])
        T.expect(refusal == "Tooltip_RenewableEnergy_PumpLimit", "a tank at the pump's limit still takes the pump: " .. tostring(refusal))
    end,
})

-- A powered compressor won't fill a tank past the pump's share with unscrubbed gas. A scrubber,
-- fitted with a sound bucket (a broken one doesn't count) and charged, lets it; each m³ it scrubs
-- uses up its charge and its steel wool.
test("renewable_energy_biogas_compressor_fills_past_pump_with_scrubber", {
    instant = true,
    run = function(self)
        local handle = T.placeRecord(self, "digester", "dome")
        if not handle then return end
        -- Less than the dome, the charge, the wool or the tank's room above the pump's share holds.
        self.gas = math.min(Digester.HOLDERS.dome.capacity, Digester.SCRUB_M3.lime, Digester.WOOL_M3,
            (1 - Digester.PUMP_FILL) * Digester.M3_PER_TANK) / 2
        T.setRecord(self, handle, T.matureDigester("dome", { gas = self.gas }))
        -- A running generator powers the squares around it, outdoors too.
        if not T.generator(self, { near = handle.square, fuel = 10, running = true }) then return end
        T.give(self, "fill", { { type = Digester.COMPRESSOR }, { type = Digester.TANK, uses = Digester.PUMP_FILL } })
        waitForPower(self)
        T.waitForGas(self, handle, self.gas)
        T.step(function()
            self.unscrubbed = DigesterJobs.refusal(T.player(), DigesterJobs.FILL_COMPRESSOR, handle.object, self.items.fill[2])
        end)
        local scrubber = DigesterJobs.materials(DigesterJobs.FIT_SCRUBBER)
        local bucket
        for _, material in ipairs(scrubber) do
            bucket = material.tag and material.item or bucket
        end
        T.give(self, "broken", { { type = bucket, condition = 0 } })
        T.step(function()
            for _, need in ipairs(DigesterJobs.needs(T.player(), DigesterJobs.FIT_SCRUBBER)) do
                if need.item == bucket then
                    self.brokenBucket = need.have
                end
            end
        end)
        T.server(self, "takeItems", { type = bucket })
        T.giveMaterials(self, "scrubber", scrubber)
        T.gasJob(self, "digester", handle, DigesterJobs.FIT_SCRUBBER)
        -- Fitting took the bucket; the charge's water comes in another.
        T.batch(function()
            T.giveMaterials(self, "charge", DigesterJobs.materials(DigesterJobs.CHARGE_LIME))
            T.give(self, "water", { { type = "Base.Bucket" } })
            T.server(self, "refillFluid", { type = "Base.Bucket", fluid = "Water", liters = Digester.SCRUB_WATER })
        end)
        -- Each job's action checks this client's copies, of the digester and the water.
        T.waitFor(self, function()
            local summary = T.recordSummary(handle)
            return summary ~= nil and summary.scrubber and self.items.water[1]:getFluidContainer():getAmount() >= Digester.SCRUB_WATER
        end, "this client's copies of the fitted scrubber and the water")
        T.gasJob(self, "digester", handle, DigesterJobs.CHARGE_LIME)
        T.readRecord(self, handle, "charged")
        T.waitForSummary(self, handle, function(summary) return summary.scrubCO2 > 0 end, "this client's summary of the charged scrubber")
        T.gasJob(self, "digester", handle, DigesterJobs.FILL_COMPRESSOR, function() return self.items.fill[2] end)
        T.readRecord(self, handle, "filled")
        T.readCarried(self, { Digester.TANK })
    end,
    validate = function(self)
        local charged, filled = self.reads.charged, self.reads.filled
        T.expect(self.brokenBucket == 0, "a broken bucket counts as the scrubber's: " .. tostring(self.brokenBucket))
        T.expect(self.unscrubbed == "Tooltip_RenewableEnergy_NeedsScrubbed",
            "the compressor without a scrubber, at the pump's share: " .. tostring(self.unscrubbed))
        T.expect(charged.scrubber, "the scrubber wasn't fitted")
        T.expectNear("scrubber charge with lime", charged.scrubCO2, Digester.SCRUB_M3.lime, 0.01)
        T.expectNear("steel wool once fitted", charged.scrubWool, Digester.WOOL_M3, 0.01)
        T.expect(T.hasOverlay(charged, Sprites.digesterScrubber.dome), "the dome doesn't show its scrubber")
        T.expectNear("tank after compressing " .. self.gas .. " m³", T.carriedFirst(self, Digester.TANK).uses, Digester.PUMP_FILL + self.gas / Digester.M3_PER_TANK, 0.002)
        T.expectNear("scrubber charge left", filled.scrubCO2, Digester.SCRUB_M3.lime - self.gas, 0.02)
        T.expectNear("steel wool left", filled.scrubWool, Digester.WOOL_M3 - self.gas, 0.02)
    end,
})

-- Refill Propane Bottle moves propane from a tank into a lantern bottle and makes none: what the
-- bottle gains is what the tank loses. Each case's start is (tank use) → tank, bottle.
local SHARE = RenewableEnergy.Recipes.PROPANE_BOTTLE_SHARE
local REFILLS = {
    propane_refill_fills_bottle = { start = function() return 0.5, 0.5 end, check = function(bottle)
        T.expectNear("bottle refilled from a half tank", bottle, 1, 0.001)
    end },
    -- A tank holding less than the bottle's room empties into it.
    propane_refill_empties_low_tank = { start = function(use)
        return math.max(1, math.floor(0.5 * SHARE / use / 2)) * use, 0.5
    end, check = function(_, tank)
        T.expectNear("low tank after refilling", tank, 0, 0.0001)
    end },
    -- A bottle with less room than a tank use takes nothing.
    propane_refill_skips_bottle_without_room = { start = function(use) return 0.5, 1 - use / SHARE / 4 end,
        check = function(bottle, tank, self)
            T.expectNear("nearly full bottle after refilling", bottle, self.bottleStart, 0.00001)
            T.expectNear("tank after refilling a nearly full bottle", tank, self.tankStart, 0.0001)
        end },
}
for name, case in pairs(REFILLS) do
    T.craftTest("renewable_energy_biogas_" .. name, {
        recipe = "RenewableEnergy_RefillPropaneBottle",
        from = "Base.Propane_Refill",
        setup = function(self)
            local use
            for _, item in ipairs(self.items.inputs or {}) do
                use = item:getFullType() == Digester.TANK and item:getUseDelta() or use
            end
            if not T.need(self, use, "the propane tank among the inputs") then return end
            self.tankStart, self.bottleStart = case.start(use)
            for _, item in ipairs(self.items.inputs or {}) do
                T.changeItem(self, item, { uses = item:getFullType() == Digester.TANK and self.tankStart or self.bottleStart })
            end
        end,
        counts = { ["Base.Propane_Refill"] = 1, [Digester.TANK] = 1 },
        after = function(self)
            T.readCarried(self, { Digester.TANK, "Base.Propane_Refill" })
        end,
        validate = function(self)
            local bottle = T.carriedFirst(self, "Base.Propane_Refill").uses
            local tank = T.carriedFirst(self, Digester.TANK).uses
            T.expectNear("propane the bottle gained, in tanks, against what the tank lost",
                (bottle - self.bottleStart) * SHARE, self.tankStart - tank, 0.0001)
            case.check(bottle, tank, self)
        end,
    })
end

-- The propane tank on the character's square, this client's copy, or nil.
local function floorTank(square)
    local objects = square:getWorldObjects()
    for i = 0, objects:size() - 1 do
        local item = objects:get(i):getItem()
        if item and item:getFullType() == Digester.TANK then
            return item
        end
    end
    return nil
end

-- Refilling a bottle from a tank on the floor beside the character draws the tank down on this
-- client too, as the loot window shows it.
test("renewable_energy_biogas_propane_refill_from_floor_tank", {
    instant = true,
    run = function(self)
        local recipe = T.need(self, getScriptManager():getCraftRecipe("RenewableEnergy_RefillPropaneBottle"), "the refill recipe")
        if not recipe then return end
        local here = T.player():getCurrentSquare()
        self.tankUses, self.bottleUses = 0.5, 0.5
        T.batch(function()
            T.give(self, "bottle", { { type = "Base.Propane_Refill", uses = self.bottleUses } })
            T.server(self, "floorItem", T.at(here, { type = Digester.TANK, uses = self.tankUses }))
        end)
        T.waitFor(self, function()
            self.tank = floorTank(here)
            return self.tank ~= nil
        end, "this client's copy of the tank on the floor")
        T.step(function() T.startCraft(self, recipe, self.items.bottle[1]) end)
        -- Found again each frame: the craft takes the tank off the floor and puts it back, which
        -- can send this client a new copy.
        T.waitFor(self, function()
            self.tank = floorTank(here)
            return self.tank ~= nil and self.tank:getCurrentUsesFloat() < self.tankUses - 0.0001
        end, "this client's copy of the floor tank drawn down")
    end,
    validate = function(self)
        T.expectNear("this client's floor tank after refilling", self.tank:getCurrentUsesFloat(),
            self.tankUses - (1 - self.bottleUses) * SHARE, 0.0005)
    end,
})

-- The mechanics window counts a compressor as a tire pump only where the character stands with
-- power, as its offer of Inflate Tire does; plugged in within a generator's reach, the character
-- inflates a car standing out of it.
test("renewable_energy_biogas_compressor_inflates_tires_where_plugged_in", {
    run = function(self)
        T.setGrid(self, false)
        T.give(self, "compressor", { { type = Digester.COMPRESSOR } })
        T.step(function() self.unpowered = ISVehicleMechanics:getTirePump(T.player()) end)
        local generator = T.generator(self, { near = T.player():getCurrentSquare(), fuel = 10, running = true })
        -- Just out of the generator's reach: a car near the edge of the loaded area can be saved
        -- with its chunk and come back after the test removed it.
        local square = generator and T.square(self, { near = generator.square, minDistance = SandboxVars.GeneratorTileRange + 2,
            bare = true }, "open ground out of the generator's reach for a car")
        local car = square and T.placeVehicle(self, "Base.CarNormal", { square = square })
        if not car then return end
        waitForPower(self)
        T.step(function()
            local player = T.player()
            self.offered = ISVehicleMechanics:getTirePump(player)
            self.carPowered = car.vehicle:getSquare():haveElectricity()
            ISVehiclePartMenu.onInflateTire(player, car.vehicle:getPartById("TireFrontLeft"))
            local queue = ISTimedActionQueue.getTimedActionQueue(player).queue
            for _, action in ipairs(queue) do
                if action.Type == "ISInflateTire" then
                    self.inflate = action.item
                end
            end
            -- Only what the click queued: walking to the car isn't what this is about.
            ISTimedActionQueue.clear(player)
        end)
    end,
    validate = function(self)
        T.expect(self.unpowered == nil, "a compressor with no power counts as a tire pump")
        T.expect(not self.carPowered, "the car stands where the generator reaches, so this tests nothing")
        T.expect(self.offered and self.offered:getFullType() == Digester.COMPRESSOR, "a powered compressor doesn't count as a tire pump")
        T.expect(self.inflate and self.inflate:getFullType() == Digester.COMPRESSOR,
            "Inflate Tire with the compressor offered queued no inflating with it")
    end,
})

-- Wood ash ---------------------------------------------------------------------------------------

test("renewable_energy_biogas_clear_ashes_gives_wood_ash", {
    instant = true,
    run = function(self)
        local square = T.square(self, nil, "a free outdoor square for ashes")
        if not square then return end
        local ashes = T.placeTile(self, square, "floors_burnt_01_1")
        T.step(function()
            T.standNextTo(square)
            ISTimedActionQueue.add(ISClearAshes:new(T.player(), ashes.object))
        end)
        T.count(self, "ash", { RenewableEnergy.Gasifier.WOOD_ASH })
    end,
    validate = function(self)
        local ash = self.counts.ash[RenewableEnergy.Gasifier.WOOD_ASH]
        T.expect(ash == 1, "clearing ashes gave " .. tostring(ash) .. " wood ash")
    end,
})
