require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"

-- Biogas: the stink, digesters, propane and the gas heater. The stink is the game's own corpse
-- smell, from ghosts (server/RenewableEnergy/Biogas/Stink.lua) that the authority counts; its
-- moodle is a function of what the authority's character smells on every update, so the tests read
-- it there, and a multiplayer client's moodle follows the rate the server sends every two seconds
-- (PlayerDamagePacket), which stink_outdoors checks once.

local T = RenewableEnergyTest
local test = T.test

local Digester, DigesterJobs = RenewableEnergy.Digester, RenewableEnergy.DigesterJobs
local Sprites = RenewableEnergy.Sprites

-- How long the smell may take to settle, in real milliseconds: a server sync and then some. Only a
-- failing test waits this long.
local SMELL_MS = 8000

local function standOn(square)
    PZHarness.Fixtures.teleportToMiddle(T.player(), square:getX(), square:getY(), square:getZ())
end

-- Queues setting the stink of a source on `square` to `count` corpses.
local function stink(self, square, count)
    local args = T.at(square)
    args.key, args.count = "test", count
    T.server(self, "stinkSet", args)
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
-- level in self.moodle[label].
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
        local stand = T.square(self, nil, "a free outdoor square to stand on")
        local source = stand and T.square(self, { near = stand, minDistance = 3 }, "a free outdoor square for the source")
        if not source then return end
        standOn(stand)
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

-- A gas mask keeps the smell out, its filter draining as it does among corpses.
test("renewable_energy_biogas_stink_gas_mask", {
    run = function(self)
        local stand = T.square(self, nil, "a free outdoor square to stand on")
        local source = stand and T.square(self, { near = stand, minDistance = 3 }, "a free outdoor square for the source")
        if not source then return end
        standOn(stand)
        T.give(self, "mask", { { type = "Base.Hat_GasMask", worn = true } })
        withLevels(self, source, function(levels)
            stink(self, source, levels[#levels])
            -- The filter drains only while the mask keeps corpse smell out (getCorpseSicknessDefense).
            T.serverUntil(self, "stinkRead", T.at(source), function(read) return read.mask ~= nil and read.mask < 1 end, SMELL_MS)
        end)
    end,
    validate = function(self)
        local read = self.server.stinkRead
        T.expect(read.mask and read.mask < 1, "the gas mask's filter is at " .. tostring(read.mask))
        T.expect(read.level == 0 and read.rate == 0, "with a gas mask, the smell is at level " .. tostring(read.level) .. ", rate " .. tostring(read.rate))
    end,
})

-- How far the character goes for a chunk to unload, and the longest that and its loading again
-- may take, in ticks.
local AWAY = 600
local CHUNK_FRAMES = 6000

--- Queues a trip that unloads the chunk of the square at x, y, z and loads it again: the
--- character goes AWAY squares east of `home` ({ x, y, z }) and back. `whileAway()`, if given, is
--- queued while the chunk is unloaded. A trip that doesn't unload the chunk, or brings it back
--- without LoadChunk (from a cache, with its state), misses its fixture.
local function awayAndBack(self, home, x, y, z, whileAway)
    local p = T.player()
    -- A teleport from inside a timed action doesn't stick, so OnTick makes it.
    local target
    T.onTick(self, function()
        if target then
            p:teleportTo(target[1], target[2], target[3])
            target = nil
        end
    end)
    T.defer(self, function() p:teleportTo(home.x + 0.5, home.y + 0.5, home.z) end)
    local loads = 0
    local function onLoadChunk(chunk)
        local origin = chunk:getGridSquare(0, 0, 0)
        local dx, dy = origin and x - origin:getX(), origin and y - origin:getY()
        if origin and dx >= 0 and dx < 8 and dy >= 0 and dy < 8 then
            loads = loads + 1
        end
    end
    Events.LoadChunk.Add(onLoadChunk)
    T.defer(self, function() Events.LoadChunk.Remove(onLoadChunk) end)
    T.step(function() target = { home.x + AWAY + 0.5, home.y + 0.5, 0 } end)
    T.waitUntil(function() return getSquare(x, y, z) == nil end, CHUNK_FRAMES, "the chunk to unload")
    T.step(function() T.need(self, getSquare(x, y, z) == nil, "the source's chunk unloaded") end)
    if whileAway then
        whileAway()
    end
    T.step(function() target = { home.x + 0.5, home.y + 0.5, home.z } end)
    T.waitUntil(function() return getSquare(x, y, z) ~= nil end, CHUNK_FRAMES, "the chunk to load")
    T.step(function() T.need(self, loads > 0, "the source's chunk loaded again through LoadChunk") end)
end

-- A chunk zeroes its corpse count when it unloads and loads; the ghosts are counted again when it
-- loads, and can be taken away after without the count going wrong. Single player only: a
-- multiplayer server keeps the chunk loaded long after the character leaves.
test("renewable_energy_biogas_stink_chunk_reload", {
    spOnly = "the server keeps chunks loaded after the character leaves",
    timeoutSeconds = 120,
    run = function(self)
        self.moodle = {}
        local stand = T.square(self, nil, "a free outdoor square to stand on")
        local source = stand and T.square(self, { near = stand, minDistance = 3 }, "a free outdoor square for the source")
        if not source then return end
        standOn(stand)
        withLevels(self, source, function(levels)
            stink(self, source, levels[#levels])
            waitForSmell(self, #levels, "before")
            awayAndBack(self, T.at(stand), source:getX(), source:getY(), source:getZ())
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

-- Digesters --------------------------------------------------------------------------------------

local function placeDigester(self, tile, opts)
    return T.placeRecord(self, "digester", tile, opts)
end

-- The hopper takes feed and alkalis only, on this client's copy as in the loot window, and feeds
-- one item an hour while the tank has room.
test("renewable_energy_biogas_digester_hopper_meters", {
    run = function(self)
        local handle = placeDigester(self, "barrel.steel")
        if not handle then return end
        self.digester = handle
        T.batch(function()
            T.fillRecord(self, handle, { hopper = { { type = "Base.Dung_Cow", count = 8 } } })
            T.runDigester(self, handle, 8, 25)
            T.readRecord(self, handle, "after")
        end)
        self.cow = Digester.feedOf(instanceItem("Base.Dung_Cow"))
        local fits = math.floor(Digester.TIERS.barrel.potentialCap / self.cow.potential + 1e-6)
        self.left = 8 - fits
        T.waitForSummary(handle, function(summary) return summary.hopper == self.left end, "this client's count of the hopper")
    end,
    validate = function(self)
        local after = self.reads.after
        T.expectNear("undigested potential", after.potential, Digester.TIERS.barrel.potentialCap, 0.001)
        T.expect(after.hopperItems == self.left, "the hopper holds " .. tostring(after.hopperItems) .. " items, not " .. self.left)
        T.expectNear("startup the manure seeded", after.seedHours, (8 - self.left) * self.cow.seedHours, 0.001)
        local summary = T.recordSummary(self.digester)
        T.expect(summary and summary.hopper == self.left, "this client's summary shows " .. tostring(summary and summary.hopper) .. " in the hopper")
        local container = self.digester.object:getContainer()
        local function allowed(fullType)
            return container:isItemAllowed(instanceItem(fullType))
        end
        T.expect(allowed("Base.Dung_Cow") and allowed("RenewableEnergy.WoodAsh"), "this client's hopper refuses manure or wood ash")
        T.expect(not allowed("Base.Apple") and not allowed("Base.Hammer"), "this client's hopper takes a fresh apple or a hammer")
    end,
})

-- No gas until the startup's warm hours are done, then gas; it doesn't start in the cold, and
-- manure's head start shortens it by at most its share.
test("renewable_energy_biogas_digester_startup_then_gas", {
    run = function(self)
        local handle = placeDigester(self, "barrel.steel")
        if not handle then return end
        local needed = getSandboxOptions():getCompostHours()
        local cold = Digester.STARTUP_MIN_TEMP - 5
        local function fresh(fields)
            local state = { fed = true, started = false, startupHours = 0, seedHours = 0, potential = 4, temp = 30, gas = 0 }
            for key, value in pairs(fields) do
                state[key] = value
            end
            T.setRecord(self, handle, state)
        end
        -- Seeded with more than its share can cover, it still waits out the rest.
        local seededWait = needed * (1 - Digester.SEED_SHARE)
        T.batch(function()
            fresh({ temp = cold })
            T.runDigester(self, handle, needed, cold)
            T.readRecord(self, handle, "cold")
            fresh({})
            T.runDigester(self, handle, needed - 1, 30)
            T.readRecord(self, handle, "before")
            T.runDigester(self, handle, 2, 30)
            T.readRecord(self, handle, "after")
            fresh({ seedHours = needed })
            T.runDigester(self, handle, seededWait - 1, 30)
            T.readRecord(self, handle, "seededBefore")
            T.runDigester(self, handle, 2, 30)
            T.readRecord(self, handle, "seededAfter")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        T.expect(not reads.cold.started, "it started below " .. Digester.STARTUP_MIN_TEMP .. " °C")
        T.expect(not reads.before.started and reads.before.gas == 0, "gas before the startup ended")
        T.expect(reads.after.started and reads.after.gas > 0, "no gas after the startup")
        T.expect(not reads.seededBefore.started, "manure's head start covered more than its share")
        T.expect(reads.seededAfter.started, "manure's head start didn't shorten the startup")
    end,
})

-- Digestion follows temperature: none at or below the coldest edge and at the hottest, some just
-- above the cold edge, the same along the best stretch. The barrel follows the air within days.
test("renewable_energy_biogas_digester_temperature", {
    run = function(self)
        local handle = placeDigester(self, "barrel.steel")
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
        self.edges = { coldest = rows[1][1], warmer = rows[1][1] + 1, hottest = rows[#rows][1] }
        local temps = { self.edges.coldest, self.edges.warmer, self.edges.hottest, self.plateau[1], self.plateau[#self.plateau] }
        T.batch(function()
            for _, temp in ipairs(temps) do
                local state = T.matureDigester(4)
                state.temp, state.gas = temp, 0
                T.setRecord(self, handle, state)
                T.runDigester(self, handle, 1, temp)
                T.readRecord(self, handle, "at" .. temp)
            end
            local cooling = T.matureDigester(4)
            cooling.temp = 30
            T.setRecord(self, handle, cooling)
            T.runDigester(self, handle, 72, 0)
            T.readRecord(self, handle, "cooled")
        end)
    end,
    validate = function(self)
        local reads, edges = self.reads, self.edges
        T.expect(reads["at" .. edges.coldest].gas == 0, "it made gas at " .. edges.coldest .. " °C")
        T.expect(reads["at" .. edges.warmer].gas > 0, "it made no gas at " .. edges.warmer .. " °C")
        T.expect(reads["at" .. edges.hottest].gas == 0, "it made gas at " .. edges.hottest .. " °C")
        local first, last = self.plateau[1], self.plateau[#self.plateau]
        T.expectNear("gas at " .. last .. " °C against " .. first, reads["at" .. last].gas, reads["at" .. first].gas, 1e-6)
        T.expect(reads.cooled.temp < 5, "three days at 0 °C left the barrel at " .. reads.cooled.temp .. " °C")
    end,
})

-- Acid over the limit sours it, and it stays sour until well below; wood ash fixes it whole,
-- baking soda a use at a time.
test("renewable_energy_biogas_digester_sour_and_fix", {
    run = function(self)
        local handle = placeDigester(self, "barrel.steel")
        if not handle then return end
        T.readRecord(self, handle, "fresh")
        T.step(function()
            local limit = self.reads.fresh.acidLimit
            local function set(acid, sour)
                local state = T.matureDigester(4)
                state.acid, state.sour = acid * limit, sour
                T.setRecord(self, handle, state)
            end
            T.batch(function()
                for _, case in ipairs({ { "over", 1.05, false }, { "under", 0.95, false }, { "sourAbove", 0.6, true }, { "sourBelow", 0.45, true } }) do
                    set(case[2], case[3])
                    T.runDigester(self, handle, 1, 30)
                    T.readRecord(self, handle, case[1])
                end
                set(1.05, true)
                T.fillRecord(self, handle, { hopper = { { type = "RenewableEnergy.WoodAsh" } } })
                T.runDigester(self, handle, 1, 30)
                T.readRecord(self, handle, "ash")
                set(1.05, true)
                T.fillRecord(self, handle, { hopper = { { type = "Base.BakingSoda" } } })
                T.runDigester(self, handle, 1, 30)
                T.readRecord(self, handle, "soda")
            end)
        end)
    end,
    validate = function(self)
        local reads = self.reads
        T.expect(reads.over.sour, "acid just over the limit didn't sour it")
        T.expect(not reads.under.sour, "acid just under the limit soured it")
        T.expect(reads.sourAbove.sour, "a sour digester recovered above half its limit")
        T.expect(not reads.sourBelow.sour, "a sour digester stayed sour below half its limit")
        T.expect(not reads.ash.sour and reads.ash.hopperItems == 0, "wood ash didn't fix it, or stayed in the hopper")
        T.expect(not reads.soda.sour, "baking soda didn't fix it")
        T.expect(reads.soda.hopperItems == 1, "a used box of baking soda left the hopper")
    end,
})

-- Take Sludge fills an empty sandbag into a compost bag, a use per share of sludge as vanilla's
-- composter does, up to a full bag; less sludge than a bag holds goes into a part-filled bag.
test("renewable_energy_biogas_digester_sludge_into_bags", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "barrel.steel")
        if not handle then return end
        local full, part = 3.5 * Digester.SLUDGE_PER_BAG, Digester.SLUDGE_PER_BAG / 2
        self.full = full
        T.setRecord(self, handle, { sludge = full })
        T.waitForSummary(handle, function(summary) return summary.sludge == full end, "the summary's sludge")
        T.give(self, "bags", { { type = DigesterJobs.SANDBAG, count = 2 } })
        T.gasJob(self, "digester", handle, DigesterJobs.TAKE_SLUDGE, function() return self.items.bags[1] end)
        T.readRecord(self, handle, "first")
        T.setRecord(self, handle, { sludge = part })
        T.waitForSummary(handle, function(summary) return summary.sludge == part end, "the summary's sludge")
        T.gasJob(self, "digester", handle, DigesterJobs.TAKE_SLUDGE, function() return self.items.bags[2] end)
        T.readRecord(self, handle, "second")
        T.server(self, "carried", { types = { DigesterJobs.COMPOST_BAG, DigesterJobs.SANDBAG } })
    end,
    validate = function(self)
        T.expectNear("sludge left after a full bag", self.reads.first.sludge, self.full - Digester.SLUDGE_PER_BAG, 0.001)
        T.expectNear("sludge left after a part bag", self.reads.second.sludge, 0, 0.001)
        local items = self.server.carried.items
        local bags = items[DigesterJobs.COMPOST_BAG]
        T.expect(#items[DigesterJobs.SANDBAG] == 0 and #bags == 2, "the sandbags didn't become compost bags")
        if #bags == 2 then
            local fullest, other = math.max(bags[1].uses, bags[2].uses), math.min(bags[1].uses, bags[2].uses)
            T.expectNear("the first bag", fullest, 1, 0.001)
            T.expectNear("the part bag", other, 0.5, 0.001)
        end
    end,
})

-- The bags hold what they can and vent the rest; worn through they tear, hold nothing and show
-- torn; new bags fix them.
test("renewable_energy_biogas_digester_holder", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "barrel.steel")
        if not handle then return end
        local full = T.matureDigester(5)
        full.gas, full.temp = 0.55, 35
        T.batch(function()
            T.setRecord(self, handle, full)
            T.runDigester(self, handle, 6, 35)
            T.readRecord(self, handle, "full")
            T.setRecord(self, handle, { holderCondition = 0.5 })
            T.runDigester(self, handle, 24, 35)
            T.readRecord(self, handle, "torn")
        end)
        T.waitForSummary(handle, function(summary) return summary.torn end, "the summary's torn bags")
        T.give(self, "bags", { { type = "Base.Garbagebag", count = 3 } })
        T.gasJob(self, "digester", handle, DigesterJobs.REPLACE_BAGS)
        T.readRecord(self, handle, "mended")
    end,
    validate = function(self)
        local reads = self.reads
        T.expectNear("gas in full bags", reads.full.gas, Digester.HOLDERS.bags.capacity, 0.001)
        T.expect(T.hasOverlay(reads.full, Sprites.digesterHolder.bags[3]), "full bags don't show full")
        T.expect(reads.torn.torn and reads.torn.gas == 0, "worn-out bags still hold gas")
        T.expect(T.hasOverlay(reads.torn, Sprites.digesterHolder.bagsTorn), "torn bags don't show torn")
        T.expect(reads.mended.holderCondition == 100 and not reads.mended.torn, "new bags didn't mend it")
        T.expect(T.hasOverlay(reads.mended, Sprites.digesterHolder.bags[1]), "new bags don't show empty")
    end,
})

-- How strongly a digester stinks, as corpses: a mature barrel at the first smell level, a sour one
-- at the second; an unfed one not at all; the Brick Dome never past the first, at its worst.
test("renewable_energy_biogas_digester_stink_levels", {
    run = function(self)
        local barrel = placeDigester(self, "barrel.steel")
        local dome = barrel and placeDigester(self, "dome")
        if not dome then return end
        local sour = T.matureDigester(5)
        sour.sour, sour.acid = true, 5
        T.batch(function()
            T.server(self, "stinkRead", T.at(barrel))
            T.server(self, "digesterCorpsesFor", {})
            T.setRecord(self, barrel, T.matureDigester(5))
            T.readRecord(self, barrel, "mature")
            T.setRecord(self, barrel, sour)
            T.readRecord(self, barrel, "sour")
            T.setRecord(self, barrel, { fed = false })
            T.readRecord(self, barrel, "unfed")
            T.setRecord(self, dome, { fed = true, started = false, startupHours = 160, potential = 45, sludge = 100, sour = true, acid = 50 })
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

-- Upgrading a barrel builds the insulated digester around it in place: the tile, the floating drum,
-- the bigger hopper on this client too; what it held stays.
test("renewable_energy_biogas_digester_upgrade", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "barrel.steel")
        if not handle then return end
        self.digester = handle
        self.capacity = tonumber(getSprite(Sprites.digester.insulated):getProperties():get("ContainerCapacity"))
        -- At its cap, so it eats nothing from the hopper meanwhile.
        T.setRecord(self, handle, T.matureDigester(Digester.TIERS.barrel.potentialCap))
        T.fillRecord(self, handle, { hopper = { { type = "Base.Dung_Cow", count = 2 } } })
        T.setPerk(self, Perks.Woodwork, 4)
        T.setPerk(self, Perks.Mechanics, 2)
        T.give(self, "materials", {
            { type = "Base.Hammer" }, { type = "Base.Saw" }, { type = "Base.MetalDrum" },
            { type = "Base.Plank", count = 6 }, { type = "Base.Nails", count = 12 }, { type = "Base.Tarp" },
            { type = "Base.HayTuft", count = 10 },
        })
        T.gasJob(self, "digester", handle, DigesterJobs.UPGRADE)
        T.readRecord(self, handle, "after")
        T.count(self, "left", { "Base.MetalDrum", "Base.Plank", "Base.Hammer" })
        T.waitForCopy(function()
            local container = handle.object:getContainer()
            return container ~= nil and container:getCapacity() == self.capacity
        end, "this client's copy of the bigger hopper")
    end,
    validate = function(self)
        local after = self.reads.after
        T.expect(after.tier == "insulated" and after.holder == "drum", "the tier is " .. tostring(after.tier) .. " with " .. tostring(after.holder))
        T.expect(after.sprite == Sprites.digester.insulated, "the tile is " .. tostring(after.sprite))
        T.expect(after.containerCapacity == self.capacity, "the hopper holds " .. tostring(after.containerCapacity) .. ", not " .. tostring(self.capacity))
        local container = self.digester.object:getContainer()
        T.expect(container and container:getCapacity() == self.capacity,
            "this client's hopper holds " .. tostring(container and container:getCapacity()))
        T.expect(after.hopperItems == 2, "the hopper holds " .. tostring(after.hopperItems) .. " of its 2 manures")
        T.expectNear("potential kept", after.potential, Digester.TIERS.barrel.potentialCap, 0.01)
        T.expect(self.counts.left["Base.MetalDrum"] == 0 and self.counts.left["Base.Plank"] == 0, "the materials weren't used")
        T.expect(self.counts.left["Base.Hammer"] == 1, "the hammer was used up")
    end,
})

-- Clearing a campfire's ashes gives wood ash.
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
        T.count(self, "ash", { "RenewableEnergy.WoodAsh" })
    end,
    validate = function(self)
        T.expect(self.counts.ash["RenewableEnergy.WoodAsh"] == 1, "clearing ashes gave " .. tostring(self.counts.ash["RenewableEnergy.WoodAsh"]) .. " wood ash")
    end,
})

-- The build menu's own path builds a working digester: the entity's recipe takes its materials
-- and its OnCreate makes the tile a digester on the authority (ISBuildIsoEntity, ISBuildAction).
test("renewable_energy_biogas_build_menu_builds_digester", {
    instant = true,
    run = function(self)
        -- Bare: grass and the like block placing anything built (BlocksPlacement), as for vanilla's.
        local square = T.square(self, { bare = true }, "a bare outdoor square for a digester")
        if not square then return end
        local handle = T.at(square)
        handle.square, handle.kind = square, "digester"
        T.setPerk(self, Perks.Mechanics, 1)
        T.give(self, "materials", {
            { type = "Base.HandDrill" }, { type = "Base.MetalDrum" }, { type = "Base.RubberHose" }, { type = "Base.Funnel" },
            { type = "Base.DuctTape" }, { type = "Base.Glue" }, { type = "Base.Garbagebag", count = 3 },
        })
        T.server(self, "recordTrack", T.recordArgs(handle))
        T.step(function()
            local script = getScriptManager():getGameEntityScript("Base.RenewableEnergy_BarrelDigesterSteel")
            local spriteConfig = script and script:getComponentScriptFor(ComponentType.SpriteConfig)
            local infos = SpriteConfigManager.GetObjectInfoList()
            local info
            for i = 0, infos:size() - 1 do
                if spriteConfig and infos:get(i):getScript() == spriteConfig then
                    info = infos:get(i)
                end
            end
            if not T.need(self, info, "the barrel digester's build menu entry") then return end
            local player = T.player()
            T.standNextTo(square)
            local build = ISBuildIsoEntity:new(player, info, 1, ISInventoryPaneContextMenu.getContainers(player))
            -- What the build panel does before the cursor can build (ISBuildPanel): the player
            -- number the drag sets (IsoCell.setDrag), and the recipe's inputs picked from what is carried.
            build.player = player:getPlayerNum()
            build.buildPanelLogic:refresh()
            build.buildPanelLogic:autoPopulateInputs()
            self.canBuild = build.buildPanelLogic:canPerformCurrentRecipe()
            self.validSquare = build:isValid(square)
            build:tryBuild(handle.x, handle.y, handle.z)
        end)
        T.readRecord(self, handle, "built")
        T.count(self, "left", { "Base.MetalDrum", "Base.Garbagebag", "Base.HandDrill" })
    end,
    validate = function(self)
        local built = self.reads.built
        T.expect(self.canBuild and self.validSquare, "the build menu can't build a barrel digester from its materials on a bare square")
        T.expect(built.tier == "barrel" and built.material == "steel", "the build menu built " .. tostring(built.tier))
        T.expect(built.sprite == Sprites.digester.barrel.steel, "the built tile is " .. tostring(built.sprite))
        T.expect(self.counts.left["Base.MetalDrum"] == 0 and self.counts.left["Base.Garbagebag"] == 0, "building didn't use the drum and bags")
        T.expect(self.counts.left["Base.HandDrill"] == 1, "building used up the drill")
    end,
})

-- Right-clicking a barrel digester shows its submenu through vanilla's menu builder: its status,
-- and its jobs greyed out with the reason while the digester or the character can't do them. The
-- status window opens on it and shows its state.
test("renewable_energy_biogas_digester_menu", {
    run = function(self)
        self.digester = placeDigester(self, "barrel.steel")
    end,
    validate = function(self)
        local object = self.digester.object
        local submenu, context = T.worldSubmenu(object, getText("IGUI_RenewableEnergy_Digester_barrel"))
        if T.expect(submenu ~= nil, "right-clicking a digester shows no digester submenu") then
            local function option(job)
                return submenu:getOptionFromName(getText("ContextMenu_RenewableEnergy_" .. job))
            end
            T.expect(submenu:getOptionFromName(getText("ContextMenu_RenewableEnergy_DigesterStatus")) ~= nil, "no Status option")
            local sludge = option(DigesterJobs.TAKE_SLUDGE)
            T.expect(sludge and sludge.notAvailable and sludge.toolTip.description == getText("Tooltip_RenewableEnergy_NoSludge"),
                "Take Sludge isn't greyed out for an empty digester")
            T.expect(option(DigesterJobs.VENT) and option(DigesterJobs.VENT).notAvailable, "Vent Gas isn't greyed out with no gas")
            T.expect(option(DigesterJobs.REPLACE_BAGS) ~= nil and option(DigesterJobs.SEW_TARP) ~= nil, "no holder options on a barrel")
            local upgrade = option(DigesterJobs.UPGRADE)
            T.expect(upgrade and upgrade.notAvailable and upgrade.toolTip.description:find(getItemNameFromFullType("Base.Plank"), 1, true),
                "Upgrade isn't greyed out listing its planks")
        end
        if context then
            context:hideAndChildren()
        end
        local window = RenewableEnergy.DigesterWindow.open(0, object)
        window:prerender()
        T.expect(window.title == getText("IGUI_RenewableEnergy_Digester_barrel"), "the status window's title is " .. tostring(window.title))
        T.expect(window.rowsToDraw and window.rowsToDraw[1].value == getText("IGUI_RenewableEnergy_DigesterEmpty"),
            "the status window doesn't say the digester is empty")
        window:close()
    end,
})

-- While its chunk is unloaded a digester keeps eating from what its hopper held, an item an hour;
-- when the chunk loads, what it ate has left the hopper. Single player only, as the chunk reload
-- test.
test("renewable_energy_biogas_digester_eats_while_unloaded", {
    spOnly = "the server keeps chunks loaded after the character leaves",
    timeoutSeconds = 120,
    run = function(self)
        local stand = T.square(self, nil, "a free outdoor square to stand on")
        local handle = stand and placeDigester(self, "barrel.steel", { near = stand, minDistance = 2 })
        if not handle then return end
        T.fillRecord(self, handle, { hopper = { { type = "Base.Dung_Cow", count = 4 } } })
        -- Half an hour on the meter, so three more hours eat three.
        T.runDigester(self, handle, 0.5, 25)
        awayAndBack(self, T.at(stand), handle.x, handle.y, handle.z, function()
            T.ageRecord(self, handle, 3, "away")
        end)
        T.readRecord(self, handle, "back")
    end,
    validate = function(self)
        local away, back = self.reads.away, self.reads.back
        local cow = Digester.feedOf(instanceItem("Base.Dung_Cow"))
        T.expect(not away.loaded, "the digester's tile stayed loaded")
        T.expect(away.eaten == 3 and away.snapshot == 1, "unloaded, it ate " .. away.eaten .. " and left " .. away.snapshot)
        T.expectNear("potential eaten while unloaded", away.potential, 3 * cow.potential, 0.001)
        T.expect(back.hopperItems == 1, "back, the hopper holds " .. back.hopperItems .. " items, not 1")
    end,
})

-- Propane ----------------------------------------------------------------------------------------

-- Queues a read of the character's propane tanks (their fraction) into self.reads[label].
local function readTanks(self, label)
    T.server(self, "carried", { types = { Digester.TANK } })
    T.step(function()
        self.reads = self.reads or {}
        self.reads[label] = self.server.carried.items[Digester.TANK]
    end)
end

-- A tire pump moves the digester's gas into a propane tank, but no further than a quarter full,
-- and it is hard work.
test("renewable_energy_biogas_tank_by_pump", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "dome")
        if not handle then return end
        self.digester = handle
        local full = T.matureDigester(Digester.TIERS.dome.potentialCap)
        full.gas = 4
        T.setRecord(self, handle, full)
        T.server(self, "setCharacterStatUntilEnd", { stat = "ENDURANCE", value = 1 })
        T.waitForSummary(handle, function(summary) return summary.gas == 4 end, "the summary's gas")
        -- Two m³ short of the pump's limit, so it stops there with gas left.
        self.start = Digester.PUMP_FILL - 2 / Digester.M3_PER_TANK
        T.give(self, "tools", { { type = Digester.PUMP }, { type = Digester.TANK, uses = self.start } })
        T.gasJob(self, "digester", handle, DigesterJobs.FILL_PUMP, function() return self.items.tools[2] end)
        T.readRecord(self, handle, "after")
        readTanks(self, "tanks")
        T.server(self, "characterStats", { stats = { "ENDURANCE" } })
        T.waitForCopy(function() return self.items.tools[2]:getCurrentUsesFloat() >= Digester.PUMP_FILL - 0.001 end,
            "this client's copy of the pumped tank")
    end,
    validate = function(self)
        local tank = self.reads.tanks[1]
        if T.expect(tank ~= nil, "the tank is gone") then
            T.expectNear("tank after pumping", tank.uses, Digester.PUMP_FILL, 0.001)
        end
        T.expectNear("gas left", self.reads.after.gas, 2, 0.02)
        T.expectNear("endurance after pumping 2 m³", self.server.characterStats.values.ENDURANCE, 1 - 2 * Digester.PUMP_ENDURANCE_PER_M3, 0.02)
        local refusal = DigesterJobs.refusal(T.player(), DigesterJobs.FILL_PUMP, self.digester.object, self.items.tools[2])
        T.expect(refusal == "Tooltip_RenewableEnergy_PumpLimit", "a tank at the pump's limit still takes the pump: " .. tostring(refusal))
    end,
})

-- A scrubber, fitted and charged, lets a powered compressor fill a tank past a quarter; each m³
-- it scrubs uses up its charge and its steel wool.
test("renewable_energy_biogas_scrubber_and_compressor", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "dome")
        if not handle then return end
        local full = T.matureDigester(Digester.TIERS.dome.potentialCap)
        full.gas = 4
        T.setRecord(self, handle, full)
        -- A running generator powers the squares around it, outdoors too.
        if not T.generator(self, { near = handle.square, fuel = 10, running = true }) then return end
        T.setPerk(self, Perks.Mechanics, 1)
        T.give(self, "scrubber", { { type = "Base.Bucket" }, { type = "Base.Pipe" }, { type = "Base.RubberHose" }, { type = "Base.SteelWool" } })
        T.gasJob(self, "digester", handle, DigesterJobs.FIT_SCRUBBER)
        T.give(self, "charge", { { type = "Base.Bucket" }, { type = "Base.Quicklime" } })
        T.server(self, "refillFluid", function() return { id = self.items.charge[1]:getID(), liters = 5, fluid = "Water" } end)
        T.gasJob(self, "digester", handle, DigesterJobs.CHARGE_LIME)
        T.readRecord(self, handle, "charged")
        T.give(self, "fill", { { type = Digester.COMPRESSOR }, { type = Digester.TANK, uses = Digester.PUMP_FILL } })
        T.waitForCopy(function()
            local here = T.player():getCurrentSquare()
            return here ~= nil and here:haveElectricity()
        end, "power where the character stands")
        T.gasJob(self, "digester", handle, DigesterJobs.FILL_COMPRESSOR, function() return self.items.fill[2] end)
        T.readRecord(self, handle, "filled")
        readTanks(self, "tanks")
    end,
    validate = function(self)
        local charged, filled = self.reads.charged, self.reads.filled
        T.expect(charged.scrubber, "the scrubber wasn't fitted")
        T.expectNear("scrubber charge with lime", charged.scrubCO2, Digester.SCRUB_M3.lime, 0.01)
        T.expectNear("steel wool once fitted", charged.scrubWool, Digester.WOOL_M3, 0.01)
        T.expect(T.hasOverlay(charged, Sprites.digesterScrubber.dome), "the dome doesn't show its scrubber")
        T.expectNear("tank after compressing 4 m³", self.reads.tanks[1].uses, Digester.PUMP_FILL + 4 / Digester.M3_PER_TANK, 0.002)
        T.expectNear("scrubber charge left", filled.scrubCO2, Digester.SCRUB_M3.lime - 4, 0.02)
        T.expectNear("steel wool left", filled.scrubWool, Digester.WOOL_M3 - 4, 0.02)
    end,
})

-- A lit gas heater keeps one digester beside it warm on that digester's gas, the other beside it
-- neither warmed nor paying, and goes out when the gas does.
test("renewable_energy_biogas_heater_warms_digester", {
    instant = true,
    run = function(self)
        local first = placeDigester(self, "barrel.steel")
        local square = first and T.square(self, { near = first.square }, "a square beside the digester for a heater")
        local second = square and placeDigester(self, "barrel.steel", { near = square })
        if not second then return end
        self.digesters = { first, second }
        local cold = T.matureDigester(5)
        cold.temp, cold.gas = 5, 0.6
        for _, handle in ipairs(self.digesters) do
            T.setRecord(self, handle, cold)
            T.waitForSummary(handle, function(summary) return summary.gas == 0.6 end, "the summary's gas")
        end
        local heater = T.placeTile(self, square, Sprites.gasHeater.off)
        T.give(self, "lighter", { { type = "Base.Lighter" } })
        T.gasJob(self, "heater", heater, RenewableEnergy.GasHeater.LIGHT)
        T.batch(function()
            for i, handle in ipairs(self.digesters) do
                T.runDigester(self, handle, 3, 0)
                T.readRecord(self, handle, "warming" .. i)
            end
            for i, handle in ipairs(self.digesters) do
                T.runDigester(self, handle, 6, 0)
                T.readRecord(self, handle, "out" .. i)
            end
        end)
        T.waitForCopy(function()
            local object = RenewableEnergy.findObjectOn(square, RenewableEnergy.GasHeater.isHeater)
            self.heaterSprite = object and object:getSprite():getName()
            return self.heaterSprite == Sprites.gasHeater.off
        end, "this client's copy of the heater going out")
    end,
    validate = function(self)
        local reads = self.reads
        local warmed = reads.warming1.heaterLit and 1 or reads.warming2.heaterLit and 2
        if not T.expect(warmed, "a lit heater warmed neither digester beside it") then return end
        local other = 3 - warmed
        local warming, idle = reads["warming" .. warmed], reads["warming" .. other]
        T.expect(warming.temp > 5, "a lit heater didn't warm its digester: " .. tostring(warming.temp) .. " °C")
        T.expectNear("gas after 3 hours of heating", warming.gas, 0.6 - 3 * RenewableEnergy.GasHeater.M3_PER_HOUR, 0.02)
        T.expect(not idle.heaterLit and idle.temp < 5, "the heater warmed both digesters beside it")
        T.expectNear("gas of the digester it doesn't warm", idle.gas, 0.6, 0.02)
        T.expect(not reads["out" .. warmed].heaterLit, "the heater kept burning with no gas")
        T.expect(self.heaterSprite == Sprites.gasHeater.off, "the heater still shows lit: " .. tostring(self.heaterSprite))
    end,
})

-- Refilling a half-empty lantern bottle from a propane tank fills the bottle and takes its share
-- of the tank; a tank holding less than that share empties into the bottle.
for name, tankUses in pairs({ refill_propane_bottle = 0.5, refill_propane_bottle_from_low_tank = 0.01 }) do
    T.craftTest("renewable_energy_biogas_" .. name, {
        recipe = "RenewableEnergy_RefillPropaneBottle",
        from = "Base.Propane_Refill",
        setup = function(self)
            for _, item in ipairs(self.items.inputs or {}) do
                T.changeItem(self, item, { uses = item:getFullType() == Digester.TANK and tankUses or 0.5 })
            end
        end,
        counts = { ["Base.Propane_Refill"] = 1, [Digester.TANK] = 1 },
        after = function(self)
            readTanks(self, "tanks")
            T.server(self, "carried", { types = { "Base.Propane_Refill" } })
        end,
        validate = function(self)
            local share = RenewableEnergy.Recipes.PROPANE_BOTTLE_SHARE
            local taken = math.min(0.5 * share, tankUses)
            T.expectNear("bottle after refilling", self.server.carried.items["Base.Propane_Refill"][1].uses, 0.5 + taken / share, 0.01)
            T.expectNear("tank after refilling", self.reads.tanks[1].uses, tankUses - taken, 0.002)
        end,
    })
end

-- The mechanics window offers Inflate Tire with a compressor only where it can be plugged in.
test("renewable_energy_biogas_compressor_inflates_tires_on_power", {
    run = function(self)
        T.setGrid(self, false)
        T.give(self, "compressor", { { type = Digester.COMPRESSOR } })
        T.step(function() self.unpowered = ISVehicleMechanics:getTirePump(T.player()) end)
        if not T.generator(self, { near = T.player():getCurrentSquare(), fuel = 10, running = true }) then return end
        T.waitForCopy(function()
            local here = T.player():getCurrentSquare()
            return here ~= nil and here:haveElectricity()
        end, "power where the character stands")
        T.step(function() self.powered = ISVehicleMechanics:getTirePump(T.player()) end)
    end,
    validate = function(self)
        T.expect(self.unpowered == nil, "a compressor with no power counts as a tire pump")
        T.expect(self.powered and self.powered:getFullType() == Digester.COMPRESSOR, "a powered compressor doesn't count as a tire pump")
    end,
})
