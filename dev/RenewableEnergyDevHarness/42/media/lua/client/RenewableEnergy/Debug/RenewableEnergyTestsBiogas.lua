require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"

-- Biogas: the stink, digesters, propane and the gas heater. The stink is the game's own corpse
-- smell, from ghosts (server/RenewableEnergy/Biogas/Stink.lua) that the authority counts; its
-- moodle is a function of what the authority's character smells on every update, so the tests read
-- it there, and a multiplayer client's moodle follows the rate the server sends every two seconds
-- (PlayerDamagePacket), which stink_outdoors checks once.

local T = RenewableEnergyTest
local test = T.test

local Digester, DigesterJobs, GasHeater = RenewableEnergy.Digester, RenewableEnergy.DigesterJobs, RenewableEnergy.GasHeater
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
-- level in self.moodle[label] for validate. The limit is real time, not frames: a multiplayer
-- client's moodle follows the rate the server sends every two seconds, whatever the frame rate.
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

-- A gas mask keeps the smell out, its filter draining as it does among corpses: no smell comes in,
-- and the moodle rises no higher than it stood before, which an earlier test's smell can leave
-- fading for a while.
test("renewable_energy_biogas_stink_gas_mask", {
    run = function(self)
        local stand = T.square(self, nil, "a free outdoor square to stand on")
        local source = stand and T.square(self, { near = stand, minDistance = 3 }, "a free outdoor square for the source")
        if not source then return end
        standOn(stand)
        T.give(self, "mask", { { type = "Base.Hat_GasMask", worn = true } })
        withLevels(self, source, function(levels)
            T.server(self, "stinkRead", T.at(source))
            T.step(function() self.before = self.server.stinkRead end)
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
    T.waitFor(self, function() return getSquare(x, y, z) == nil end, "the source's chunk unloaded", CHUNK_FRAMES)
    if whileAway then
        whileAway()
    end
    T.step(function() target = { home.x + 0.5, home.y + 0.5, home.z } end)
    T.waitFor(self, function() return getSquare(x, y, z) ~= nil end, "the source's chunk loaded again", CHUNK_FRAMES)
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
-- one item an hour until the tank holds its cap; manure eaten brings its head start.
test("renewable_energy_biogas_digester_hopper_meters", {
    run = function(self)
        local handle = placeDigester(self, "barrel.MetalDrum")
        if not handle then return end
        self.digester = handle
        self.cow = Digester.feedOf(instanceItem("Base.Dung_Cow"))
        self.fits = math.floor(Digester.TIERS.barrel.potentialCap / self.cow.potential + 1e-6)
        -- More than fits, run first for an hour less than eating what fits takes.
        self.count, self.firstHours = self.fits + 2, self.fits - 1
        self.left = self.count - self.fits
        T.batch(function()
            T.fillRecord(self, handle, { hopper = { { type = "Base.Dung_Cow", count = self.count } } })
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
        T.expect(allowed("Base.Dung_Cow") and allowed(RenewableEnergy.Gasifier.WOOD_ASH), "this client's hopper refuses manure or wood ash")
        T.expect(not allowed("Base.Apple") and not allowed("Base.Hammer"), "this client's hopper takes a fresh apple or a hammer")
    end,
})

-- No gas until the startup's warm hours are done: at STARTUP_MIN_TEMP the hours count and a degree
-- below they don't; it starts at exactly the hours needed, and makes gas after. Manure's head start
-- shortens it by at most its share.
test("renewable_energy_biogas_digester_startup_then_gas", {
    run = function(self)
        local handle = placeDigester(self, "barrel.MetalDrum")
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
        local handle = placeDigester(self, "barrel.MetalDrum")
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
                local state = T.matureDigester("barrel")
                state.temp, state.gas = temp, 0
                T.setRecord(self, handle, state)
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
        T.expect(reads.cooled.temp < 5, "three days at 0 °C left the barrel at " .. reads.cooled.temp .. " °C")
    end,
})

-- The Biogas Multiplier scales the gas a digester makes: the same mature barrel run for the same
-- hours makes about twice the gas with the option at 2 as at 1. Catches the option ignored, or
-- applied to something other than the gas.
test("renewable_energy_biogas_multiplier_scales_gas", {
    run = function(self)
        local handle = placeDigester(self, "barrel.MetalDrum")
        if not handle then return end
        local function runAt(multiplier, label)
            T.step(function() T.setSandbox(self, "BiogasMultiplier", multiplier) end)
            T.batch(function()
                local state = T.matureDigester("barrel")
                state.gas = 0
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
        local handle = placeDigester(self, "barrel.MetalDrum")
        if not handle then return end
        local limit = Digester.ACID_LIMIT * Digester.TIERS.barrel.potentialCap
        local function set(share, sour)
            local state = T.matureDigester("barrel")
            state.acid, state.sour = share * limit, sour
            T.setRecord(self, handle, state)
        end
        -- An hour's decay takes well under 1 % of the acid, so 1 % either side stays on its side.
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

-- Take Sludge refuses without a bag to fill; it fills an empty sandbag into a compost bag, a use per
-- share of sludge as vanilla's composter does, up to a full bag; less sludge than a bag holds goes
-- into a part-filled bag.
test("renewable_energy_biogas_digester_sludge_into_bags", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "barrel.MetalDrum")
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
            T.server(self, "carried", { types = { DigesterJobs.COMPOST_BAG, DigesterJobs.SANDBAG } })
        end)
    end,
    validate = function(self)
        T.expect(self.noBag == "Tooltip_RenewableEnergy_NeedsSandbag", "Take Sludge with no bag: " .. tostring(self.noBag))
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
-- torn; Replace Bags takes new bags and mends them.
test("renewable_energy_biogas_digester_holder", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "barrel.MetalDrum")
        if not handle then return end
        local bags = Digester.HOLDERS.bags
        local overfull = T.matureDigester("barrel")
        overfull.gas = bags.capacity + 0.1
        T.batch(function()
            T.setRecord(self, handle, overfull)
            T.runDigester(self, handle, 1, 30)
            T.readRecord(self, handle, "full")
            -- Half a day's wear left.
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

-- How strongly a digester stinks, as corpses: a mature barrel at the first smell level, a sour one
-- at the second; an unfed one not at all; the Brick Dome never past the first, at its worst.
test("renewable_energy_biogas_digester_stink_levels", {
    run = function(self)
        local barrel = placeDigester(self, "barrel.MetalDrum")
        local dome = barrel and placeDigester(self, "dome")
        if not dome then return end
        -- Mid-startup, when the startup stinks most, full, its sludge at the top and sour.
        local worst = T.sourDigester("dome")
        worst.started, worst.startupHours, worst.seedHours, worst.sludge = false, getSandboxOptions():getCompostHours() / 2, 0, 100
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

-- Upgrading a barrel builds the insulated digester around it in place: the tile, the floating drum,
-- the bigger hopper on this client too; what it held stays, and the job takes its materials.
test("renewable_energy_biogas_digester_upgrade", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "barrel.MetalDrum")
        if not handle then return end
        self.digester = handle
        self.capacity = tonumber(getSprite(Sprites.digester.insulated):getProperties():get("ContainerCapacity"))
        self.upgrade = DigesterJobs.materials(DigesterJobs.UPGRADE)
        self.dung = 2
        -- At its cap, so it eats nothing from the hopper meanwhile.
        T.batch(function()
            T.setRecord(self, handle, T.matureDigester("barrel"))
            T.fillRecord(self, handle, { hopper = { { type = "Base.Dung_Cow", count = self.dung } } })
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
        T.count(self, "ash", { RenewableEnergy.Gasifier.WOOD_ASH })
    end,
    validate = function(self)
        local ash = self.counts.ash[RenewableEnergy.Gasifier.WOOD_ASH]
        T.expect(ash == 1, "clearing ashes gave " .. tostring(ash) .. " wood ash")
    end,
})

-- The build menu entry of `entity` (a game entity script's full name), or nil.
local function buildEntry(entity)
    local script = getScriptManager():getGameEntityScript(entity)
    local spriteConfig = script and script:getComponentScriptFor(ComponentType.SpriteConfig)
    local infos = SpriteConfigManager.GetObjectInfoList()
    for i = 0, infos:size() - 1 do
        if spriteConfig and infos:get(i):getScript() == spriteConfig then
            return infos:get(i)
        end
    end
    return nil
end

-- The build menu's own path builds a working digester from the barrel `barrel` (an item type): the
-- entity's recipe takes its materials, keeps its tools, and its OnCreate makes the tile a digester
-- that looks like that barrel on the authority (ISBuildIsoEntity, ISBuildAction), as this client
-- sees it.
local function buildsBarrelDigester(barrel)
    return {
        instant = true,
        run = function(self)
            -- Bare: grass and the like block placing anything built (BlocksPlacement), as for vanilla's.
            local square = T.square(self, { bare = true }, "a bare outdoor square for a digester")
            if not square then return end
            local info = T.need(self, buildEntry("Base.RenewableEnergy_BarrelDigester"), "the barrel digester's build menu entry")
            local recipe = info and info:getRecipe() and info:getRecipe():getCraftRecipe()
            if not T.need(self, recipe, "the barrel digester's build recipe") then return end
            local handle = T.at(square)
            handle.square, handle.kind = square, "digester"
            for i = 0, recipe:getRequiredSkillCount() - 1 do
                local skill = recipe:getRequiredSkill(i)
                T.setPerk(self, skill:getPerk(), skill:getLevel())
            end
            local inputs, unmatched = T.recipeInputs(recipe, { "Base." .. barrel })
            if not T.need(self, #unmatched == 0, "an item for " .. table.concat(unmatched, "; ")) then return end
            -- What a build should leave carried: its kept tools, and none of the items it takes whole.
            -- A drainable it takes uses of stays part-used, so isn't counted.
            self.expected, self.types = {}, {}
            for i, entry in ipairs(inputs) do
                local input = recipe:getInputs():get(i - 1)
                if input:isKeep() then
                    self.expected[entry.type] = entry.count
                elseif input:isItemCount() or not getScriptManager():FindItem(entry.type):isItemType(ItemType.DRAINABLE) then
                    self.expected[entry.type] = 0
                end
                table.insert(self.types, entry.type)
            end
            T.give(self, "materials", inputs)
            T.server(self, "recordTrack", T.recordArgs(handle))
            T.step(function()
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
            local tile = Sprites.digester.barrel[barrel]
            T.waitFor(self, function() return T.objectWithSprite(square, tile) ~= nil end,
                "this client's copy of the " .. tostring(tile) .. " digester")
            T.batch(function()
                T.readRecord(self, handle, "built")
                T.count(self, "left", self.types)
            end)
        end,
        validate = function(self)
            local built = self.reads.built
            T.expect(self.canBuild and self.validSquare, "the build menu can't build a barrel digester from its materials on a bare square")
            T.expect(built.tier == "barrel", "the build menu built " .. tostring(built.tier))
            T.expect(built.sprite == Sprites.digester.barrel[barrel], "the built tile is " .. tostring(built.sprite))
            for fullType, count in pairs(self.expected) do
                local left = self.counts.left[fullType] or 0
                T.expect(left == count, "building left " .. left .. " " .. fullType .. ", not " .. count)
            end
        end,
    }
end

test("renewable_energy_biogas_build_menu_builds_digester", buildsBarrelDigester("MetalDrum"))
-- The game's barrels are steel drums too; the digester shows the one it took.
test("renewable_energy_biogas_build_from_orange_barrel_shows_orange", buildsBarrelDigester("Mov_OrangeBarrel"))

-- Right-clicking a barrel digester shows its submenu through vanilla's menu builder: its status,
-- and its jobs greyed out with the reason while the digester or the character can't do them. The
-- status window opens on it and shows its state.
test("renewable_energy_biogas_digester_menu", {
    run = function(self)
        self.digester = placeDigester(self, "barrel.MetalDrum")
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
        local handle = stand and placeDigester(self, "barrel.MetalDrum", { near = stand, minDistance = 2 })
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

-- Queues a wait until this client has power where the character stands.
local function waitForPower(self)
    T.waitFor(self, function()
        local here = T.player():getCurrentSquare()
        return here ~= nil and here:haveElectricity()
    end, "power where the character stands")
end

-- A tire pump moves the digester's gas into a propane tank, but no further than PUMP_FILL, which
-- then refuses it, and it is hard work.
test("renewable_energy_biogas_tank_by_pump", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "dome")
        if not handle then return end
        self.digester = handle
        self.gas = 4
        local full = T.matureDigester("dome")
        full.gas = self.gas
        T.batch(function()
            T.setRecord(self, handle, full)
            T.server(self, "setCharacterStatUntilEnd", { stat = "ENDURANCE", value = 1 })
        end)
        T.waitForSummary(self, handle, function(summary) return summary.gas == self.gas end, "this client's summary of the gas")
        -- Two m³ short of the pump's limit, so it stops there with gas left.
        self.pumped = 2
        T.give(self, "tools", { { type = Digester.PUMP }, { type = Digester.TANK, uses = Digester.PUMP_FILL - self.pumped / Digester.M3_PER_TANK } })
        T.gasJob(self, "digester", handle, DigesterJobs.FILL_PUMP, function() return self.items.tools[2] end)
        T.batch(function()
            T.readRecord(self, handle, "after")
            T.server(self, "characterStats", { stats = { "ENDURANCE" } })
        end)
        readTanks(self, "tanks")
        T.waitFor(self, function() return self.items.tools[2]:getCurrentUsesFloat() >= Digester.PUMP_FILL - 0.001 end,
            "this client's copy of the pumped tank")
    end,
    validate = function(self)
        local tank = self.reads.tanks[1]
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
test("renewable_energy_biogas_scrubber_and_compressor", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "dome")
        if not handle then return end
        self.gas = 4
        local full = T.matureDigester("dome")
        full.gas = self.gas
        T.setRecord(self, handle, full)
        -- A running generator powers the squares around it, outdoors too.
        if not T.generator(self, { near = handle.square, fuel = 10, running = true }) then return end
        T.give(self, "fill", { { type = Digester.COMPRESSOR }, { type = Digester.TANK, uses = Digester.PUMP_FILL } })
        waitForPower(self)
        T.waitForSummary(self, handle, function(summary) return summary.gas == self.gas end, "this client's summary of the gas")
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
        readTanks(self, "tanks")
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
        T.expectNear("tank after compressing " .. self.gas .. " m³", self.reads.tanks[1].uses, Digester.PUMP_FILL + self.gas / Digester.M3_PER_TANK, 0.002)
        T.expectNear("scrubber charge left", filled.scrubCO2, Digester.SCRUB_M3.lime - self.gas, 0.02)
        T.expectNear("steel wool left", filled.scrubWool, Digester.WOOL_M3 - self.gas, 0.02)
    end,
})

-- The sprite this client shows of the gas heater on `square`, or nil.
local function heaterSprite(square)
    local heater = RenewableEnergy.findObjectOn(square, GasHeater.isHeater)
    return heater and heater:getSprite():getName()
end

-- A lit gas heater keeps one digester beside it warm on that digester's gas, the other beside it
-- neither warmed nor paying, and goes out when the gas does.
test("renewable_energy_biogas_heater_warms_digester", {
    instant = true,
    run = function(self)
        local first = placeDigester(self, "barrel.MetalDrum")
        local square = first and T.square(self, { near = first.square }, "a square beside the digester for a heater")
        local second = square and placeDigester(self, "barrel.MetalDrum", { near = square })
        if not second then return end
        self.digesters = { first, second }
        self.temp, self.gas = 5, Digester.HOLDERS.bags.capacity
        local cold = T.matureDigester("barrel")
        cold.temp, cold.gas = self.temp, self.gas
        for _, handle in ipairs(self.digesters) do
            T.setRecord(self, handle, cold)
            T.waitForSummary(self, handle, function(summary) return summary.gas == self.gas end, "this client's summary of the gas")
        end
        local heater = T.placeTile(self, square, Sprites.gasHeater.off)
        T.giveMaterials(self, "light", GasHeater.materials(GasHeater.LIGHT))
        T.gasJob(self, "heater", heater, GasHeater.LIGHT)
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
        T.waitFor(self, function() return heaterSprite(square) == Sprites.gasHeater.off end,
            "the heater going out on this client once its gas ran out")
    end,
    validate = function(self)
        local reads = self.reads
        local warmed = reads.warming1.heaterLit and 1 or reads.warming2.heaterLit and 2
        if not T.expect(warmed, "a lit heater warmed neither digester beside it") then return end
        local other = 3 - warmed
        local warming, idle = reads["warming" .. warmed], reads["warming" .. other]
        T.expect(warming.temp > self.temp, "a lit heater didn't warm its digester: " .. tostring(warming.temp) .. " °C")
        T.expectNear("gas after 3 hours of heating", warming.gas, self.gas - 3 * GasHeater.M3_PER_HOUR, 0.02)
        T.expect(not idle.heaterLit and idle.temp < self.temp, "the heater warmed both digesters beside it")
        T.expectNear("gas of the digester it doesn't warm", idle.gas, self.gas, 0.02)
        T.expect(not reads["out" .. warmed].heaterLit, "the heater kept burning with no gas")
    end,
})

-- A lit gas heater goes out, on this client too, when the digester it burns from is taken away.
test("renewable_energy_biogas_heater_out_when_digester_gone", {
    instant = true,
    run = function(self)
        local digester = placeDigester(self, "barrel.MetalDrum")
        local square = digester and T.square(self, { near = digester.square }, "a square beside the digester for a heater")
        if not square then return end
        local fed = T.matureDigester("barrel")
        fed.gas = Digester.HOLDERS.bags.capacity
        T.setRecord(self, digester, fed)
        T.waitForSummary(self, digester, function(summary) return summary.gas == fed.gas end, "this client's summary of the gas")
        local heater = T.placeTile(self, square, Sprites.gasHeater.off)
        T.giveMaterials(self, "light", GasHeater.materials(GasHeater.LIGHT))
        T.gasJob(self, "heater", heater, GasHeater.LIGHT)
        T.waitFor(self, function() return heaterSprite(square) == Sprites.gasHeater.lit end, "this client's copy of the heater lit")
        T.removeRecord(self, digester)
        T.waitFor(self, function() return heaterSprite(square) == Sprites.gasHeater.off end,
            "the heater going out on this client once its digester was gone")
    end,
})

-- Refill Propane Bottle moves propane from a tank into a lantern bottle and makes none: what the
-- bottle gains is what the tank loses. A half bottle from a half tank comes out full; a tank holding
-- less than the bottle's room empties into it; a bottle with room for less than one use of the tank
-- takes nothing.
local REFILLS = {
    refill_propane_bottle = { tank = 0.5, bottle = 0.5, check = function(bottle)
        T.expectNear("bottle refilled from a half tank", bottle, 1, 0.001)
    end },
    refill_propane_bottle_from_low_tank = { tank = 0.01, bottle = 0.5, check = function(_, tank)
        T.expectNear("low tank after refilling", tank, 0, 0.0001)
    end },
    refill_propane_bottle_nearly_full = { tank = 0.5, bottle = 0.999, check = function(bottle, tank)
        T.expectNear("nearly full bottle after refilling", bottle, 0.999, 0.00001)
        T.expectNear("tank after refilling a nearly full bottle", tank, 0.5, 0.0001)
    end },
}
for name, case in pairs(REFILLS) do
    T.craftTest("renewable_energy_biogas_" .. name, {
        recipe = "RenewableEnergy_RefillPropaneBottle",
        from = "Base.Propane_Refill",
        setup = function(self)
            for _, item in ipairs(self.items.inputs or {}) do
                T.changeItem(self, item, { uses = item:getFullType() == Digester.TANK and case.tank or case.bottle })
            end
        end,
        counts = { ["Base.Propane_Refill"] = 1, [Digester.TANK] = 1 },
        after = function(self)
            readTanks(self, "tanks")
            T.server(self, "carried", { types = { "Base.Propane_Refill" } })
        end,
        validate = function(self)
            local bottle = self.server.carried.items["Base.Propane_Refill"][1].uses
            local tank = self.reads.tanks[1].uses
            T.expectNear("propane the bottle gained, in tanks, against what the tank lost",
                (bottle - case.bottle) * RenewableEnergy.Recipes.PROPANE_BOTTLE_SHARE, case.tank - tank, 0.0001)
            case.check(bottle, tank)
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
test("renewable_energy_biogas_refill_propane_bottle_from_floor_tank", {
    instant = true,
    run = function(self)
        local recipe = T.need(self, getScriptManager():getCraftRecipe("RenewableEnergy_RefillPropaneBottle"), "the refill recipe")
        if not recipe then return end
        local here = T.player():getCurrentSquare()
        self.tankUses, self.bottleUses = 0.5, 0.5
        local args = T.at(here)
        args.type, args.uses = Digester.TANK, self.tankUses
        T.batch(function()
            T.give(self, "bottle", { { type = "Base.Propane_Refill", uses = self.bottleUses } })
            T.server(self, "floorItem", args)
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
            self.tankUses - (1 - self.bottleUses) * RenewableEnergy.Recipes.PROPANE_BOTTLE_SHARE, 0.0005)
    end,
})

-- The mechanics window offers Inflate Tire with a compressor only where it can be plugged in.
test("renewable_energy_biogas_compressor_inflates_tires_on_power", {
    run = function(self)
        T.setGrid(self, false)
        T.give(self, "compressor", { { type = Digester.COMPRESSOR } })
        T.step(function() self.unpowered = ISVehicleMechanics:getTirePump(T.player()) end)
        if not T.generator(self, { near = T.player():getCurrentSquare(), fuel = 10, running = true }) then return end
        waitForPower(self)
        T.step(function() self.powered = ISVehicleMechanics:getTirePump(T.player()) end)
    end,
    validate = function(self)
        T.expect(self.unpowered == nil, "a compressor with no power counts as a tire pump")
        T.expect(self.powered and self.powered:getFullType() == Digester.COMPRESSOR, "a powered compressor doesn't count as a tire pump")
    end,
})
