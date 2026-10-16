require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Biogas and wood gas. The stink is the game's own corpse smell, from ghosts
-- (server/RenewableEnergy/Biogas/Stink.lua) that the authority counts; on a multiplayer client the
-- moodle follows the rate the server sends every two seconds (PlayerDamagePacket).

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

-- How far the character goes for a chunk to unload, and the longest that and its loading again
-- may take, in ticks.
local AWAY = 600
local CHUNK_FRAMES = 6000

--- Queues a trip that unloads the chunk of the square at x, y, z and loads it again: the
--- character goes AWAY squares east of `home` ({ x, y, z }) and back. `whileAway()`, if given, is
--- queued while the chunk is unloaded. Leaves in self.unloaded whether it did unload and in
--- self.loads how often LoadChunk fired for it, which a chunk that came back from a cache with its
--- state wouldn't.
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
    self.loads = 0
    local function onLoadChunk(chunk)
        local origin = chunk:getGridSquare(0, 0, 0)
        local dx, dy = origin and x - origin:getX(), origin and y - origin:getY()
        if origin and dx >= 0 and dx < 8 and dy >= 0 and dy < 8 then
            self.loads = self.loads + 1
        end
    end
    Events.LoadChunk.Add(onLoadChunk)
    T.defer(self, function() Events.LoadChunk.Remove(onLoadChunk) end)
    T.step(function() target = { home.x + AWAY + 0.5, home.y + 0.5, 0 } end)
    T.waitUntil(function() return getSquare(x, y, z) == nil end, CHUNK_FRAMES, "the chunk to unload")
    T.step(function() self.unloaded = getSquare(x, y, z) == nil end)
    if whileAway then
        whileAway()
    end
    T.step(function() target = { home.x + 0.5, home.y + 0.5, home.z } end)
    T.waitUntil(function() return getSquare(x, y, z) ~= nil end, CHUNK_FRAMES, "the chunk to load")
end

-- A chunk zeroes its corpse count when it unloads and loads; the ghosts are counted again when it
-- loads, and can be taken away after without the count going wrong. Single player only: a
-- multiplayer server keeps the chunk loaded long after the character leaves.
test("renewable_energy_biogas_stink_chunk_reload", {
    spOnly = "the server keeps chunks loaded after the character leaves",
    timeoutSeconds = 120,
    run = function(self)
        local stand = (T.need(self, T.squares(self, 1), "a free outdoor square to stand on") or {})[1]
        if not stand then return end
        local source = (T.need(self, T.squares(self, 1, { near = stand, minDistance = 3 }), "a free outdoor square for the source") or {})[1]
        if not source then return end
        standOn(stand)
        stink(self, source, 25)
        waitForSmell(self, 3, "before")
        awayAndBack(self, at(stand), source:getX(), source:getY(), source:getZ())
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

-- Digesters --------------------------------------------------------------------------------------

local Digester = RenewableEnergy.Digester
local DigesterJobs = RenewableEnergy.DigesterJobs

-- The longest a digester or its summary takes to reach this client, in ticks (see COPY_FRAMES in
-- RenewableEnergyTestLib.lua).
local COPY_FRAMES = 3000

local function digesterOn(handle)
    return RenewableEnergy.findObjectOn(getSquare(handle.x, handle.y, handle.z), Digester.isDigester)
end

--- Queues a digester of tile `tile` ("barrel.steel", "insulated", "dome"...) built on a free
--- square, outdoors unless `opts.indoors`, near `opts.near`. Returns its handle { x, y, z, square };
--- `object` is this client's copy once it has its summary.
local function placeDigester(self, tile, opts)
    opts = opts or {}
    local square = (T.need(self, T.squares(self, 1, { indoors = opts.indoors, near = opts.near, minDistance = opts.minDistance }),
        "a free square for a digester") or {})[1]
    if not square then return nil end
    local handle = at(square)
    handle.square = square
    local args = at(square)
    args.tile = tile
    T.server(self, "digesterPlace", args)
    T.waitUntil(function()
        local object = digesterOn(handle)
        handle.object = object and Digester.summaryOf(object) and object or nil
        return handle.object ~= nil
    end, COPY_FRAMES, "this client's copy of the digester")
    T.step(function() T.need(self, handle.object, "this client's copy of the digester") end)
    return handle
end

local function setDigester(self, handle, fields)
    T.server(self, "digesterSet", { x = handle.x, y = handle.y, z = handle.z, fields = fields })
end

local function fillDigester(self, handle, items)
    T.server(self, "digesterFill", { x = handle.x, y = handle.y, z = handle.z, items = items })
end

local function runDigester(self, handle, hours, air)
    T.server(self, "digesterRun", { x = handle.x, y = handle.y, z = handle.z, hours = hours, air = air })
end

-- Queues a read of the digester's record into self.reads[label].
local function readDigester(self, handle, label)
    T.server(self, "digesterRead", { x = handle.x, y = handle.y, z = handle.z })
    T.step(function()
        self.reads = self.reads or {}
        self.reads[label] = self.server.digesterRead
    end)
end

-- Queues a wait until this client's summary of the digester satisfies `check(summary)`.
local function waitForSummary(handle, check, what)
    T.waitUntil(function()
        local summary = handle.object and Digester.summaryOf(handle.object)
        return summary ~= nil and check(summary)
    end, COPY_FRAMES, what)
end

-- `item`, if a function, is called when the job is queued, for an item given earlier in the queue.
local function queueJob(self, handle, job, item)
    T.goNextTo(self, handle.square)
    T.step(function()
        if type(item) == "function" then
            item = item()
        end
        ISTimedActionQueue.add(RenewableEnergyDigesterAction:new(T.player(), job, handle.object, item))
    end)
end

-- A started, mature digester: past its startup and settled down, holding `potential`.
local function mature(potential)
    return { fed = true, started = true, gasHours = 1000, potential = potential, temp = 30, acid = 0, sour = false, sludge = 0 }
end

-- The hopper takes feed and alkalis only, and feeds one item an hour while the tank has room;
-- manure fed during startup shortens it.
test("renewable_energy_biogas_digester_hopper_meters", {
    run = function(self)
        local handle = placeDigester(self, "barrel.steel")
        if not handle then return end
        fillDigester(self, handle, { { type = "Base.Dung_Cow", count = 8 } })
        runDigester(self, handle, 8, 25)
        readDigester(self, handle, "after")
        waitForSummary(handle, function(summary) return summary.hopper == 3 end, "the summary's hopper")
        T.step(function()
            self.summary = Digester.summaryOf(handle.object)
            self.accepts = {
                dung = Digester.acceptItem(nil, instanceItem("Base.Dung_Cow")),
                ash = Digester.acceptItem(nil, instanceItem("RenewableEnergy.WoodAsh")),
                apple = Digester.acceptItem(nil, instanceItem("Base.Apple")),
                hammer = Digester.acceptItem(nil, instanceItem("Base.Hammer")),
            }
        end)
    end,
    validate = function(self)
        local after = self.reads.after
        T.expectNear("undigested potential", after.potential, Digester.TIERS.barrel.potentialCap, 0.001)
        T.expect(after.hopperItems == 3, "the hopper holds " .. after.hopperItems .. " items, not 3")
        T.expect(after.seedHours == 5 * 24, "five cow manures seeded " .. after.seedHours .. " hours")
        T.expect(not after.started, "the digester started in 8 hours")
        T.expect(self.summary.hopper == 3, "this client's summary shows " .. tostring(self.summary.hopper) .. " in the hopper")
        T.expect(self.accepts.dung and self.accepts.ash, "the hopper refuses manure or wood ash")
        T.expect(not self.accepts.apple and not self.accepts.hammer, "the hopper takes a fresh apple or a hammer")
    end,
})

-- No gas until the startup's warm hours are done; then gas.
test("renewable_energy_biogas_digester_startup_then_gas", {
    run = function(self)
        local handle = placeDigester(self, "barrel.steel")
        if not handle then return end
        local hours = getSandboxOptions():getCompostHours()
        setDigester(self, handle, { fed = true, potential = 4, temp = 30 })
        runDigester(self, handle, hours - 1, 30)
        readDigester(self, handle, "before")
        runDigester(self, handle, 3, 30)
        readDigester(self, handle, "after")
    end,
    validate = function(self)
        T.expect(not self.reads.before.started and self.reads.before.gas == 0, "gas before the startup ended")
        T.expect(self.reads.after.started and self.reads.after.gas > 0, "no gas after the startup")
    end,
})

-- Digestion follows temperature: fastest at 35 °C, about a seventh of that at 15, none in the cold.
test("renewable_energy_biogas_digester_temperature", {
    run = function(self)
        local handle = placeDigester(self, "barrel.steel")
        if not handle then return end
        local warm = mature(4)
        warm.temp, warm.gas = 35, 0
        setDigester(self, handle, warm)
        runDigester(self, handle, 1, 35)
        readDigester(self, handle, "warm")
        local cool = mature(4)
        cool.temp, cool.gas = 15, 0
        setDigester(self, handle, cool)
        runDigester(self, handle, 1, 15)
        readDigester(self, handle, "cool")
        local cold = mature(4)
        cold.temp, cold.gas = 30, 0
        setDigester(self, handle, cold)
        runDigester(self, handle, 72, 0)
        setDigester(self, handle, { gas = 0 })
        runDigester(self, handle, 24, 0)
        readDigester(self, handle, "cold")
    end,
    validate = function(self)
        local ratio = self.reads.warm.gas / math.max(1e-9, self.reads.cool.gas)
        T.expectNear("gas at 35 °C over gas at 15 °C", ratio, (1 / 15) / 0.01, 0.2)
        T.expect(self.reads.cold.temp < 5, "three days at 0 °C left the digester at " .. self.reads.cold.temp .. " °C")
        T.expectNear("gas made in a day near 0 °C", self.reads.cold.gas, 0, 0.001)
    end,
})

-- Too much acid sours it; wood ash fixes it whole, baking soda a use at a time.
test("renewable_energy_biogas_digester_sour_and_fix", {
    run = function(self)
        local handle = placeDigester(self, "barrel.steel")
        if not handle then return end
        local sour = mature(4)
        sour.acid = 4.5
        setDigester(self, handle, sour)
        runDigester(self, handle, 1, 30)
        readDigester(self, handle, "sour")
        fillDigester(self, handle, { { type = "RenewableEnergy.WoodAsh" } })
        runDigester(self, handle, 1, 30)
        readDigester(self, handle, "ash")
        setDigester(self, handle, { acid = 4.5, sour = true })
        fillDigester(self, handle, { { type = "Base.BakingSoda" } })
        runDigester(self, handle, 1, 30)
        readDigester(self, handle, "soda")
    end,
    validate = function(self)
        T.expect(self.reads.sour.sour, "acid over the limit didn't sour it")
        T.expect(not self.reads.ash.sour and self.reads.ash.hopperItems == 0, "wood ash didn't fix it, or stayed in the hopper")
        T.expect(not self.reads.soda.sour, "baking soda didn't fix it")
        T.expect(self.reads.soda.hopperItems == 1, "a used box of baking soda left the hopper")
    end,
})

-- Take Sludge fills an empty sandbag into a compost bag, a use per 2.5 % of sludge as vanilla's
-- composter does, up to a full bag.
test("renewable_energy_biogas_digester_sludge_into_bags", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "barrel.steel")
        if not handle then return end
        setDigester(self, handle, { sludge = 35 })
        waitForSummary(handle, function(summary) return summary.sludge == 35 end, "the summary's sludge")
        T.give(self, "bag", { { type = DigesterJobs.SANDBAG } })
        queueJob(self, handle, DigesterJobs.TAKE_SLUDGE, function() return self.items.bag[1] end)
        readDigester(self, handle, "after")
        T.count(self, "bags", { DigesterJobs.COMPOST_BAG, DigesterJobs.SANDBAG })
    end,
    validate = function(self)
        T.expectNear("sludge left", self.reads.after.sludge, 25, 0.001)
        T.expect(self.counts.bags[DigesterJobs.COMPOST_BAG] == 1 and self.counts.bags[DigesterJobs.SANDBAG] == 0,
            "the sandbag didn't become a compost bag")
    end,
})

-- The bags hold what they can and vent the rest; worn through they tear, hold nothing and show
-- torn; new bags fix them.
test("renewable_energy_biogas_digester_holder", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "barrel.steel")
        if not handle then return end
        local full = mature(5)
        full.gas, full.temp = 0.55, 35
        setDigester(self, handle, full)
        runDigester(self, handle, 6, 35)
        readDigester(self, handle, "full")
        setDigester(self, handle, { holderCondition = 0.5 })
        runDigester(self, handle, 24, 35)
        readDigester(self, handle, "torn")
        waitForSummary(handle, function(summary) return summary.torn end, "the summary's torn bags")
        T.give(self, "bags", { { type = "Base.Garbagebag", count = 3 } })
        queueJob(self, handle, DigesterJobs.REPLACE_BAGS)
        readDigester(self, handle, "mended")
    end,
    validate = function(self)
        local Sprites = RenewableEnergy.Sprites
        T.expectNear("gas in full bags", self.reads.full.gas, Digester.HOLDERS.bags.capacity, 0.001)
        T.expect(self.reads.full.overlays[1] == Sprites.digesterHolder.bags[3], "full bags show " .. tostring(self.reads.full.overlays[1]))
        T.expect(self.reads.torn.torn and self.reads.torn.gas == 0, "worn-out bags still hold gas")
        T.expect(self.reads.torn.overlays[1] == Sprites.digesterHolder.bagsTorn, "torn bags show " .. tostring(self.reads.torn.overlays[1]))
        T.expect(self.reads.mended.holderCondition == 100 and not self.reads.mended.torn, "new bags didn't mend it")
        T.expect(self.reads.mended.overlays[1] == Sprites.digesterHolder.bags[1], "new bags show " .. tostring(self.reads.mended.overlays[1]))
    end,
})

-- The stink reaches a character outdoors nearby through the vanilla moodle: a mature barrel the
-- first level, a sour one the second; the Brick Dome never past the first, at its worst.
test("renewable_energy_biogas_digester_stink_levels", {
    run = function(self)
        local stand = (T.need(self, T.squares(self, 1), "a free outdoor square to stand on") or {})[1]
        if not stand then return end
        local barrel = placeDigester(self, "barrel.steel", { near = stand, minDistance = 3 })
        if not barrel then return end
        T.step(function() standOn(stand) end)
        setDigester(self, barrel, mature(5))
        waitForSmell(self, 1, "mature")
        local sour = mature(5)
        sour.sour, sour.acid = true, 5
        setDigester(self, barrel, sour)
        waitForSmell(self, 2, "sour")
        setDigester(self, barrel, { fed = false })
        waitForSmell(self, 0, "none")
        local dome = placeDigester(self, "dome", { near = stand, minDistance = 3 })
        if not dome then return end
        setDigester(self, dome, { fed = true, started = false, startupHours = 160, potential = 45, sludge = 100, sour = true, acid = 50 })
        holdSmell(self, "dome")
        readDigester(self, dome, "dome")
    end,
    validate = function(self)
        T.expect(self.smell.mature == 1, "a mature barrel smells at level " .. tostring(self.smell.mature))
        T.expect(self.smell.sour == 2, "a sour barrel smells at level " .. tostring(self.smell.sour))
        T.expect(self.smell.none == 0, "an unfed barrel smells at level " .. tostring(self.smell.none))
        T.expect(self.smell.dome == 1, "the dome at its worst smells at level " .. tostring(self.smell.dome))
        T.expect(self.reads.dome.ghosts < 15, "the dome counts as " .. self.reads.dome.ghosts .. " corpses")
    end,
})

-- A sour digester indoors fills its building with fumes, which clear once it's fixed.
test("renewable_energy_biogas_digester_fumes_indoors", {
    run = function(self)
        local handle = placeDigester(self, "barrel.steel", { indoors = true })
        if not handle then return end
        local sour = mature(5)
        sour.sour, sour.acid = true, 5
        setDigester(self, handle, sour)
        readDigester(self, handle, "sour")
        setDigester(self, handle, { sour = false, acid = 0 })
        readDigester(self, handle, "fixed")
    end,
    validate = function(self)
        T.expect(self.reads.sour.toxic, "a sour digester indoors left the building clear")
        T.expect(not self.reads.fixed.toxic, "the building stayed toxic once the digester was fixed")
    end,
})

-- Upgrading a barrel builds the insulated digester around it in place: the tile, the floating drum,
-- a bigger hopper; what it held stays.
test("renewable_energy_biogas_digester_upgrade", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "barrel.steel")
        if not handle then return end
        setDigester(self, handle, mature(3))
        T.setPerk(self, Perks.Woodwork, 4)
        T.setPerk(self, Perks.Mechanics, 2)
        T.give(self, "materials", {
            { type = "Base.Hammer" }, { type = "Base.Saw" }, { type = "Base.MetalDrum" },
            { type = "Base.Plank", count = 6 }, { type = "Base.Nails", count = 12 }, { type = "Base.Tarp" },
            { type = "Base.HayTuft", count = 10 },
        })
        queueJob(self, handle, DigesterJobs.UPGRADE)
        readDigester(self, handle, "after")
        T.count(self, "left", { "Base.MetalDrum", "Base.Plank", "Base.Hammer" })
    end,
    validate = function(self)
        local after = self.reads.after
        T.expect(after.tier == "insulated" and after.holder == "drum", "the tier is " .. tostring(after.tier) .. " with " .. tostring(after.holder))
        T.expect(after.sprite == RenewableEnergy.Sprites.digester.insulated, "the tile is " .. tostring(after.sprite))
        T.expect(after.containerCapacity == 50, "the hopper holds " .. tostring(after.containerCapacity))
        T.expectNear("potential kept", after.potential, 3, 0.01)
        T.expect(self.counts.left["Base.MetalDrum"] == 0 and self.counts.left["Base.Plank"] == 0, "the materials weren't used")
        T.expect(self.counts.left["Base.Hammer"] == 1, "the hammer was used up")
    end,
})

-- Clearing a campfire's ashes gives wood ash.
test("renewable_energy_biogas_clear_ashes_gives_wood_ash", {
    instant = true,
    run = function(self)
        local square = (T.need(self, T.squares(self, 1), "a free outdoor square for ashes") or {})[1]
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
        local square = (T.need(self, T.squares(self, 1, { bare = true }), "a bare outdoor square for a digester") or {})[1]
        if not square then return end
        local handle = at(square)
        handle.square = square
        T.setPerk(self, Perks.Mechanics, 1)
        -- The scenario teaches them on this side only (RenewableEnergy.Debug.setupPlayer).
        T.server(self, "PZHarness.learnRecipes", { names = RenewableEnergy.Debug.ENTITY_RECIPES })
        T.give(self, "materials", {
            { type = "Base.HandDrill" }, { type = "Base.MetalDrum" }, { type = "Base.RubberHose" }, { type = "Base.Funnel" },
            { type = "Base.DuctTape" }, { type = "Base.Glue" }, { type = "Base.Garbagebag", count = 3 },
        })
        T.server(self, "trackDigester", at(square))
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
        readDigester(self, handle, "built")
        T.count(self, "left", { "Base.MetalDrum", "Base.Garbagebag", "Base.HandDrill" })
    end,
    validate = function(self)
        local built = self.reads.built
        T.expect(self.canBuild and self.validSquare, "the build menu can't build a barrel digester from its materials on a bare square")
        T.expect(built.tier == "barrel" and built.material == "steel", "the build menu built " .. tostring(built.tier))
        T.expect(built.sprite == RenewableEnergy.Sprites.digester.barrel.steel, "the built tile is " .. tostring(built.sprite))
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
        local context = ISWorldObjectContextMenu.createMenu(0, { object }, 0, 0)
        if not T.expect(type(context) == "table", "right-clicking a digester built no menu") then return end
        local entry = context:getOptionFromName(getText("IGUI_RenewableEnergy_Digester_barrel"))
        local submenu = entry and entry.subOption and context:getSubMenu(entry.subOption)
        if not T.expect(submenu ~= nil, "right-clicking a digester shows no digester submenu") then
            context:hideAndChildren()
            return
        end
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
        context:hideAndChildren()
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
        local stand = (T.need(self, T.squares(self, 1), "a free outdoor square to stand on") or {})[1]
        if not stand then return end
        local handle = placeDigester(self, "barrel.steel", { near = stand, minDistance = 2 })
        if not handle then return end
        fillDigester(self, handle, { { type = "Base.Dung_Cow", count = 4 } })
        runDigester(self, handle, 0.5, 25)
        local position = { x = handle.x, y = handle.y, z = handle.z }
        awayAndBack(self, at(stand), handle.x, handle.y, handle.z, function()
            T.server(self, "digesterCatchUp", { x = position.x, y = position.y, z = position.z, hours = 3 })
            T.step(function() self.away = self.server.digesterCatchUp end)
        end)
        readDigester(self, handle, "back")
    end,
    validate = function(self)
        T.expect(self.unloaded and not self.away.loaded, "the digester's chunk never unloaded")
        T.expect(self.away.eaten == 3 and self.away.hopper == 1, "unloaded, it ate " .. self.away.eaten .. " and left " .. self.away.hopper)
        T.expectNear("potential eaten while unloaded", self.away.potential, 3, 0.001)
        T.expect(self.reads.back.hopperItems == 1, "back, the hopper holds " .. self.reads.back.hopperItems .. " items, not 1")
    end,
})

-- Gas lines ---------------------------------------------------------------------------------------

local GasKit = RenewableEnergy.GasKit

--- Queues a vanilla generator, plugged in, holding `fuel` litres, on a free outdoor square near
--- `near`. Returns its handle { x, y, z, square }; `object` is this client's copy.
local function placeGenerator(self, fuel, near)
    local square = (T.need(self, T.squares(self, 1, { near = near, minDistance = 2 }), "a free square for a generator") or {})[1]
    if not square then return nil end
    local handle = at(square)
    handle.square = square
    local args = at(square)
    args.fuel = fuel
    T.server(self, "placeGenerator", args)
    T.step(function()
        T.defer(self, function() RenewableEnergy.Debug.releaseGeneratorPower(handle.x, handle.y, handle.z) end)
    end)
    T.waitUntil(function()
        handle.object = RenewableEnergy.findObjectOn(getSquare(handle.x, handle.y, handle.z), GasKit.isGenerator)
        return handle.object ~= nil
    end, COPY_FRAMES, "this client's copy of the generator")
    T.step(function() T.need(self, handle.object, "this client's copy of the generator") end)
    return handle
end

local function gasJob(self, generator, job, digester)
    T.goNextTo(self, generator.square)
    T.step(function()
        ISTimedActionQueue.add(RenewableEnergyGasAction:new(T.player(), job, generator.object, digester and digester.object))
    end)
end

local function readGas(self, generator, label)
    T.server(self, "gasRead", { x = generator.x, y = generator.y, z = generator.z })
    T.step(function()
        self.gas = self.gas or {}
        self.gas[label] = self.server.gasRead
    end)
end

local function gasPass(self, generator, hours)
    T.server(self, "gasPass", { x = generator.x, y = generator.y, z = generator.z, hours = hours })
end

local function setGenerator(self, generator, fields)
    local args = { x = generator.x, y = generator.y, z = generator.z }
    for key, value in pairs(fields) do
        args[key] = value
    end
    T.server(self, "gasGenerator", args)
end

-- Fitting the kit takes the kit and keeps the tank; taking it off gives the kit back with the tank
-- as it was.
test("renewable_energy_gas_kit_install_and_remove", {
    instant = true,
    run = function(self)
        local generator = placeGenerator(self, 3)
        if not generator then return end
        T.setPerk(self, Perks.Mechanics, 2)
        T.give(self, "tools", { { type = GasKit.ITEM }, { type = "Base.Wrench" } })
        gasJob(self, generator, GasKit.INSTALL)
        readGas(self, generator, "fitted")
        T.count(self, "afterFit", { GasKit.ITEM })
        gasJob(self, generator, GasKit.REMOVE)
        readGas(self, generator, "removed")
        T.count(self, "afterRemove", { GasKit.ITEM })
    end,
    validate = function(self)
        local fitted, removed = self.gas.fitted, self.gas.removed
        T.expect(fitted.state and fitted.state.kit and fitted.listed, "the kit isn't fitted")
        T.expectNear("tank with the kit", fitted.state and fitted.state.tank or -1, 3, 0.01)
        T.expect(self.counts.afterFit[GasKit.ITEM] == 0, "fitting didn't take the kit")
        T.expect(removed.state == nil and not removed.listed, "the kit is still fitted")
        T.expectNear("fuel after removing it", removed.fuel, 3, 0.01)
        T.expect(self.counts.afterRemove[GasKit.ITEM] == 1, "removing didn't give the kit back")
    end,
})

-- On a line from a digester with gas, an empty-tanked generator runs: it burns the digester's gas
-- for what it powers, its tank stays empty, petrol poured in goes into the tank, and when the gas
-- runs out it stops, holding only its tank. The line's hoses come back when it is cut.
test("renewable_energy_gas_generator_runs_on_gas", {
    instant = true,
    run = function(self)
        local digester = placeDigester(self, "barrel.steel")
        if not digester then return end
        local full = mature(5)
        full.gas = 0.6
        setDigester(self, digester, full)
        local generator = placeGenerator(self, 0, digester.square)
        if not generator then return end
        T.setPerk(self, Perks.Mechanics, 2)
        T.give(self, "tools", { { type = GasKit.ITEM }, { type = "Base.Wrench" }, { type = GasKit.HOSE, count = 2 } })
        gasJob(self, generator, GasKit.INSTALL)
        gasJob(self, generator, GasKit.CONNECT, digester)
        readGas(self, generator, "connected")
        setGenerator(self, generator, { running = true })
        gasPass(self, generator, 0.5)
        readGas(self, generator, "running")
        readDigester(self, digester, "fed")
        T.step(function() setGenerator(self, generator, { fuel = self.gas.running.fuel + 3 }) end)
        gasPass(self, generator, 0.1)
        readGas(self, generator, "poured")
        setDigester(self, digester, { gas = 0.001 })
        gasPass(self, generator, 0.5)
        readGas(self, generator, "out")
        gasJob(self, generator, GasKit.DISCONNECT)
        T.count(self, "hoses", { GasKit.HOSE })
    end,
    validate = function(self)
        local connected, running, poured, out = self.gas.connected, self.gas.running, self.gas.poured, self.gas.out
        T.expect(connected.state and connected.state.connected, "the gas line isn't connected")
        T.expect(connected.fuel >= GasKit.PHANTOM_FUEL - 0.01, "on gas, the generator shows " .. connected.fuel .. " L, too little to start")
        T.expect(running.running, "the generator didn't keep running on gas")
        T.expectNear("tank while on gas", running.state.tank, 0, 0.001)
        -- The digester's own pass may add a little gas meanwhile.
        T.expect(self.reads.fed.gas < 0.6 - GasKit.gasFor(0, 0.5) + 0.02, "the generator burned " .. (0.6 - self.reads.fed.gas) .. " m³ in half an hour")
        T.expectNear("tank after pouring 3 L", poured.state.tank, 3, 0.01)
        T.expect(not out.running and out.state.outOfGas, "the generator kept running with no gas")
        T.expectNear("fuel once the gas ran out", out.fuel, 3, 0.01)
        T.expect(self.counts.hoses[GasKit.HOSE] == 2, "cutting the line gave back " .. tostring(self.counts.hoses[GasKit.HOSE]) .. " hoses")
    end,
})

-- More switched on than the generator carries on gas stalls it; once the load fits, it starts
-- again on its own.
test("renewable_energy_gas_generator_stalls_over_cap", {
    instant = true,
    run = function(self)
        local digester = placeDigester(self, "dome")
        if not digester then return end
        local full = mature(45)
        full.gas = 4
        setDigester(self, digester, full)
        local generator = placeGenerator(self, 0, digester.square)
        if not generator then return end
        T.setPerk(self, Perks.Mechanics, 2)
        T.give(self, "tools", { { type = GasKit.ITEM }, { type = "Base.Wrench" }, { type = GasKit.HOSE, count = 1 } })
        gasJob(self, generator, GasKit.INSTALL)
        gasJob(self, generator, GasKit.CONNECT, digester)
        setGenerator(self, generator, { running = true })
        T.server(self, "gasCap", { watts = -1 })
        gasPass(self, generator, 0.2)
        readGas(self, generator, "over")
        T.server(self, "gasCap", { watts = 1000000 })
        gasPass(self, generator, 0.2)
        readGas(self, generator, "fits")
    end,
    validate = function(self)
        T.expect(not self.gas.over.running and self.gas.over.state.stalled, "an overloaded generator didn't stall")
        T.expect(self.gas.fits.running and not self.gas.fits.state.stalled, "the generator didn't start again once the load fit")
    end,
})

-- A kitted generator's menu has the kit's jobs and greys out Take Generator; the client refuses the
-- take too, and the info window shows the real tank and that it runs on gas.
test("renewable_energy_gas_kit_menu", {
    instant = true,
    run = function(self)
        local digester = placeDigester(self, "barrel.steel")
        if not digester then return end
        local full = mature(5)
        full.gas = 0.6
        setDigester(self, digester, full)
        local generator = placeGenerator(self, 0, digester.square)
        if not generator then return end
        self.generator = generator
        T.step(function()
            local context = ISWorldObjectContextMenu.createMenu(0, { generator.object }, 0, 0)
            local entry = context:getOptionFromName(getText("ContextMenu_Generator"))
            local submenu = entry and entry.subOption and context:getSubMenu(entry.subOption)
            local install = submenu and submenu:getOptionFromName(getText("ContextMenu_RenewableEnergy_InstallKit"))
            self.installShown = install ~= nil
            self.installGreyed = install ~= nil and install.notAvailable == true
            context:hideAndChildren()
        end)
        T.setPerk(self, Perks.Mechanics, 2)
        T.give(self, "tools", { { type = GasKit.ITEM }, { type = "Base.Wrench" }, { type = GasKit.HOSE, count = 1 } })
        gasJob(self, generator, GasKit.INSTALL)
        gasJob(self, generator, GasKit.CONNECT, digester)
        T.waitUntil(function()
            local state = GasKit.stateOf(generator.object)
            return state ~= nil and state.onGas == true
        end, COPY_FRAMES, "this client's copy of the kit's state")
    end,
    validate = function(self)
        T.expect(self.installShown and self.installGreyed, "without a kit and wrench, Install isn't offered greyed out")
        local generator = self.generator.object
        local context = ISWorldObjectContextMenu.createMenu(0, { generator }, 0, 0)
        local entry = context:getOptionFromName(getText("ContextMenu_Generator"))
        local submenu = entry and entry.subOption and context:getSubMenu(entry.subOption)
        if T.expect(submenu ~= nil, "a kitted generator has no generator submenu") then
            T.expect(submenu:getOptionFromName(getText("ContextMenu_RenewableEnergy_DisconnectLine")) ~= nil, "no Disconnect Gas Line")
            T.expect(submenu:getOptionFromName(getText("ContextMenu_RenewableEnergy_RemoveKit")) ~= nil, "no Remove Gas Conversion Kit")
            local take = submenu:getOptionFromName(getText("ContextMenu_GeneratorTake"))
            T.expect(take == nil or take.notAvailable, "Take Generator is offered on a kitted generator")
        end
        context:hideAndChildren()
        T.expect(not ISTakeGenerator:new(T.player(), generator):isValid(), "the client lets a kitted generator be taken")
        local text = ISGeneratorInfoWindow.getRichText(generator, true)
        T.expect(text:find(getText("IGUI_Generator_FuelAmount", 0), 1, true) ~= nil, "the info window doesn't show the empty tank")
        T.expect(text:find(getText("IGUI_RenewableEnergy_GasOn"), 1, true) ~= nil, "the info window doesn't say it runs on gas")
    end,
})

-- Propane ---------------------------------------------------------------------------------------

-- Queues a read of the character's propane tanks (their fraction) into self.tanks[label].
local function readTanks(self, label)
    T.server(self, "carried", { types = { Digester.TANK } })
    T.step(function()
        self.tanks = self.tanks or {}
        self.tanks[label] = self.server.carried.items[Digester.TANK]
    end)
end

-- A tire pump moves the digester's gas into a propane tank, but no further than a quarter full,
-- and it is hard work.
test("renewable_energy_biogas_tank_by_pump", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "dome")
        if not handle then return end
        local full = mature(45)
        full.gas = 4
        setDigester(self, handle, full)
        waitForSummary(handle, function(summary) return summary.gas == 4 end, "the summary's gas")
        T.give(self, "tools", { { type = Digester.PUMP }, { type = Digester.TANK, uses = 0 } })
        T.step(function() self.endurance = T.player():getStats():get(CharacterStat.ENDURANCE) end)
        queueJob(self, handle, DigesterJobs.FILL_PUMP, function() return self.items.tools[2] end)
        readDigester(self, handle, "after")
        readTanks(self, "after")
        T.server(self, "characterStat", { stat = "ENDURANCE" })
        T.step(function()
            local tank = self.items.tools[2]
            tank:setUsedDelta(Digester.PUMP_FILL)
            local summary = { gas = 4, scrubCO2 = 0, scrubWool = 0 }
            self.atLimit = DigesterJobs.fillRefusal(T.player(), DigesterJobs.FILL_PUMP, summary, tank)
        end)
    end,
    validate = function(self)
        local tank = self.tanks.after[1]
        T.expectNear("tank after pumping 4 m³", tank.uses, 4 / Digester.M3_PER_TANK, 0.002)
        T.expectNear("gas left", self.reads.after.gas, 0, 0.01)
        T.expect(self.server.characterStat.value < self.endurance - 0.1, "pumping 4 m³ took no endurance")
        T.expect(self.atLimit == "Tooltip_RenewableEnergy_PumpLimit", "a quarter-full tank still takes the pump: " .. tostring(self.atLimit))
    end,
})

-- A scrubber, fitted and charged, lets a powered compressor fill a tank past a quarter; each m³
-- it scrubs uses up its charge and its steel wool.
test("renewable_energy_biogas_scrubber_and_compressor", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "dome")
        if not handle then return end
        local full = mature(45)
        full.gas = 4
        setDigester(self, handle, full)
        -- A running generator powers the squares around it, outdoors too.
        local generator = placeGenerator(self, 10, handle.square)
        if not generator then return end
        setGenerator(self, generator, { running = true })
        T.setPerk(self, Perks.Mechanics, 1)
        T.give(self, "scrubber", { { type = "Base.Bucket" }, { type = "Base.Pipe" }, { type = "Base.RubberHose" }, { type = "Base.SteelWool" } })
        queueJob(self, handle, DigesterJobs.FIT_SCRUBBER)
        T.give(self, "charge", { { type = "Base.Bucket" }, { type = "Base.Quicklime" } })
        T.server(self, "refillFluid", function() return { id = self.items.charge[1]:getID(), liters = 5, fluid = "Water" } end)
        queueJob(self, handle, DigesterJobs.CHARGE_LIME)
        readDigester(self, handle, "charged")
        T.give(self, "fill", { { type = Digester.COMPRESSOR }, { type = Digester.TANK, uses = Digester.PUMP_FILL } })
        T.waitUntil(function()
            local here = T.player():getCurrentSquare()
            return here ~= nil and here:haveElectricity()
        end, COPY_FRAMES, "power where the character stands")
        queueJob(self, handle, DigesterJobs.FILL_COMPRESSOR, function() return self.items.fill[2] end)
        readDigester(self, handle, "filled")
        readTanks(self, "filled")
    end,
    validate = function(self)
        local charged, filled = self.reads.charged, self.reads.filled
        T.expect(charged.scrubber, "the scrubber wasn't fitted")
        T.expectNear("scrubber charge with lime", charged.scrubCO2, Digester.SCRUB_M3.lime, 0.01)
        T.expectNear("steel wool once fitted", charged.scrubWool, Digester.WOOL_M3, 0.01)
        T.expect(charged.overlays[#charged.overlays] == RenewableEnergy.Sprites.digesterScrubber.dome, "the dome doesn't show its scrubber")
        T.expectNear("tank after compressing 4 m³", self.tanks.filled[1].uses, Digester.PUMP_FILL + 4 / Digester.M3_PER_TANK, 0.002)
        T.expectNear("scrubber charge left", filled.scrubCO2, Digester.SCRUB_M3.lime - 4, 0.02)
        T.expectNear("steel wool left", filled.scrubWool, Digester.WOOL_M3 - 4, 0.02)
    end,
})

-- A lit gas heater beside a digester keeps it warm on its gas, and goes out when the gas does.
test("renewable_energy_biogas_heater_warms_digester", {
    instant = true,
    run = function(self)
        local handle = placeDigester(self, "barrel.steel")
        if not handle then return end
        local cold = mature(5)
        cold.temp, cold.gas = 5, 0.6
        setDigester(self, handle, cold)
        waitForSummary(handle, function(summary) return summary.gas == 0.6 end, "the summary's gas")
        local square = (T.need(self, T.squares(self, 1, { near = handle.square }), "a square beside the digester for a heater") or {})[1]
        if not square then return end
        local heater = T.placeTile(self, square, RenewableEnergy.Sprites.gasHeater.off)
        T.give(self, "lighter", { { type = "Base.Lighter" } })
        T.goNextTo(self, square)
        T.step(function()
            ISTimedActionQueue.add(RenewableEnergyHeaterAction:new(T.player(), RenewableEnergy.GasHeater.LIGHT, heater.object))
        end)
        runDigester(self, handle, 3, 0)
        readDigester(self, handle, "warming")
        runDigester(self, handle, 6, 0)
        readDigester(self, handle, "out")
        T.step(function() self.heaterSprite = heater.object:getSprite():getName() end)
        T.waitUntil(function()
            local object = RenewableEnergy.findObjectOn(square, RenewableEnergy.GasHeater.isHeater)
            self.heaterSprite = object and object:getSprite():getName()
            return self.heaterSprite == RenewableEnergy.Sprites.gasHeater.off
        end, COPY_FRAMES, "this client's copy of the heater going out")
    end,
    validate = function(self)
        local warming, out = self.reads.warming, self.reads.out
        T.expect(warming.heaterLit and warming.temp > 5, "a lit heater didn't warm the digester: " .. tostring(warming.temp) .. " °C")
        T.expectNear("gas after 3 hours of heating", warming.gas, 0.6 - 3 * RenewableEnergy.GasHeater.M3_PER_HOUR, 0.02)
        T.expect(not out.heaterLit, "the heater kept burning with no gas")
        T.expect(self.heaterSprite == RenewableEnergy.Sprites.gasHeater.off, "the heater still shows lit: " .. tostring(self.heaterSprite))
    end,
})

-- Refilling a half-empty lantern bottle from a half-full tank fills the bottle and takes its share
-- of the tank.
T.craftTest("renewable_energy_biogas_refill_propane_bottle", {
    recipe = "RenewableEnergy_RefillPropaneBottle",
    from = "Base.Propane_Refill",
    setup = function(self)
        for _, item in ipairs(self.items.inputs or {}) do
            T.changeItem(self, item, { uses = 0.5 })
        end
    end,
    counts = { ["Base.Propane_Refill"] = 1, [Digester.TANK] = 1 },
    after = function(self)
        readTanks(self, "refilled")
        T.server(self, "carried", { types = { "Base.Propane_Refill" } })
    end,
    validate = function(self)
        local share = RenewableEnergy.Recipes.PROPANE_BOTTLE_SHARE
        T.expectNear("bottle after refilling", self.server.carried.items["Base.Propane_Refill"][1].uses, 1, 0.01)
        T.expectNear("tank after refilling", self.tanks.refilled[1].uses, 0.5 - 0.5 * share, 0.002)
    end,
})

-- The mechanics window offers Inflate Tire with a compressor only where it can be plugged in.
test("renewable_energy_biogas_compressor_inflates_tires_on_power", {
    run = function(self)
        T.setGrid(self, false)
        T.give(self, "compressor", { { type = Digester.COMPRESSOR } })
        T.step(function() self.unpowered = ISVehicleMechanics:getTirePump(T.player()) end)
        local generator = placeGenerator(self, 10, T.player():getCurrentSquare())
        if not generator then return end
        setGenerator(self, generator, { running = true })
        T.waitUntil(function()
            local here = T.player():getCurrentSquare()
            return here ~= nil and here:haveElectricity()
        end, COPY_FRAMES, "power where the character stands")
        T.step(function() self.powered = ISVehicleMechanics:getTirePump(T.player()) end)
    end,
    validate = function(self)
        T.expect(self.unpowered == nil, "a compressor with no power counts as a tire pump")
        T.expect(self.powered and self.powered:getFullType() == Digester.COMPRESSOR, "a powered compressor doesn't count as a tire pump")
    end,
})

-- Wood gas ---------------------------------------------------------------------------------------

local Gasifier, GasifierJobs = RenewableEnergy.Gasifier, RenewableEnergy.GasifierJobs

local function gasifierOn(handle)
    return RenewableEnergy.findObjectOn(getSquare(handle.x, handle.y, handle.z), Gasifier.isGasifier)
end

--- Queues a gasifier of `tier` built on `square`. Returns its handle { x, y, z, square }; `object`
--- is this client's copy once it has its summary.
local function placeGasifier(self, tier, square)
    local handle = at(square)
    handle.square = square
    local args = at(square)
    args.tier = tier
    T.server(self, "gasifierPlace", args)
    T.waitUntil(function()
        local object = gasifierOn(handle)
        handle.object = object and Gasifier.summaryOf(object) and object or nil
        return handle.object ~= nil
    end, COPY_FRAMES, "this client's copy of the gasifier")
    T.step(function() T.need(self, handle.object, "this client's copy of the gasifier") end)
    return handle
end

-- A free outdoor square on one of the four sides of `square`, or nil.
local function besideSquare(square)
    for _, offset in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
        local beside = getSquare(square:getX() + offset[1], square:getY() + offset[2], square:getZ())
        if RenewableEnergy.Debug.isFreeSquare(beside, false) then
            return beside
        end
    end
    return nil
end

local function gasifierCall(self, name, handle, args)
    args = args or {}
    args.x, args.y, args.z = handle.x, handle.y, handle.z
    T.server(self, name, args)
end

local function readGasifier(self, handle, label)
    gasifierCall(self, "gasifierRead", handle)
    T.step(function()
        self.reads = self.reads or {}
        self.reads[label] = self.server.gasifierRead
    end)
end

local function gasifierJob(self, handle, job)
    T.goNextTo(self, handle.square)
    T.step(function()
        ISTimedActionQueue.add(RenewableEnergyGasifierAction:new(T.player(), job, handle.object))
    end)
end

local function hasOverlay(read, name)
    for _, overlay in ipairs(read.overlays or {}) do
        if overlay == name then
            return true
        end
    end
    return false
end

-- A gasifier beside a kitted generator, piped to it and lit, runs the generator with an empty tank;
-- out of wood, the generator stops.
test("renewable_energy_gas_gasifier_runs_generator", {
    instant = true,
    run = function(self)
        local generator = placeGenerator(self, 0)
        if not generator then return end
        local square = T.need(self, besideSquare(generator.square), "a free square beside the generator")
        if not square then return end
        local gasifier = placeGasifier(self, "standard", square)
        self.generatorSide = Gasifier.sideOf(gasifier.x, gasifier.y, generator.x, generator.y)
        self.gasifierSide = Gasifier.sideOf(generator.x, generator.y, gasifier.x, gasifier.y)
        gasifierCall(self, "gasifierFill", gasifier, { hopper = { { type = "Base.Plank", count = 4 } }, filter = { { type = "Base.HayTuft", count = 10 } } })
        T.setPerk(self, Perks.Mechanics, 2)
        T.give(self, "tools", { { type = GasKit.ITEM }, { type = "Base.Wrench" }, { type = GasKit.PIPE }, { type = "Base.Matches" }, { type = "Base.Bellows" } })
        gasJob(self, generator, GasKit.INSTALL)
        -- Lit first, so gas reaches the generator the moment the line is in.
        gasifierJob(self, gasifier, GasifierJobs.LIGHT)
        gasJob(self, generator, GasKit.CONNECT, gasifier)
        readGasifier(self, gasifier, "lit")
        readGas(self, generator, "connected")
        setGenerator(self, generator, { running = true })
        gasPass(self, generator, 1)
        gasifierCall(self, "gasifierPass", gasifier, { hours = 1 })
        readGas(self, generator, "running")
        readGasifier(self, gasifier, "fed")
        gasifierCall(self, "gasifierBurn", gasifier, { kg = 100 })
        gasPass(self, generator, 0.5)
        readGas(self, generator, "out")
    end,
    validate = function(self)
        local lit, fed = self.reads.lit, self.reads.fed
        local connected, running, out = self.gas.connected, self.gas.running, self.gas.out
        T.expect(lit.lit and lit.fireKg > 0, "lighting it didn't start a fire from the hopper")
        T.expect(lit.containers == 2, "the gasifier has " .. tostring(lit.containers) .. " containers, not a hopper and a filter")
        T.expect(connected.state and connected.state.sourceKind == "gasifier", "the line doesn't lead to the gasifier")
        T.expect(hasOverlay(lit, RenewableEnergy.Sprites.gasifierLit.standard), "the lit gasifier shows no fire")
        local Sprites = RenewableEnergy.Sprites
        T.expect(hasOverlay(lit, Sprites.gasifierPipe[self.generatorSide]), "the gasifier shows no pipe toward the generator")
        T.expect(hasOverlay(connected, Sprites.gasifierPipeGen[self.gasifierSide]), "the generator shows no pipe toward the gasifier")
        T.expect(running.running and running.fuel >= GasKit.PHANTOM_FUEL, "the generator didn't run on wood gas with an empty tank")
        local kg = Gasifier.IDLE_KG_PER_HOUR + Gasifier.KG_PER_KWH * (running.state.watts or 0) / 1000
        T.expectNear("ash after an hour's running", fed.ash, kg * Gasifier.TIERS.standard.ashPerKg, 0.05)
        T.expect(not out.running and out.state.outOfGas, "out of wood, the generator kept running")
    end,
})

-- The load the generator carries takes wood on top of the idle burn.
test("renewable_energy_gas_gasifier_wood_scales_with_load", {
    instant = true,
    run = function(self)
        local square = (T.need(self, T.squares(self, 1), "a free square for a gasifier") or {})[1]
        if not square then return end
        local gasifier = placeGasifier(self, "standard", square)
        gasifierCall(self, "gasifierFill", gasifier, { hopper = { { type = "Base.Plank", count = 4 } } })
        gasifierCall(self, "gasifierSet", gasifier, { fields = { lit = true } })
        gasifierCall(self, "gasifierSupply", gasifier, { watts = 2000, hours = 1 })
        T.step(function() self.loaded = self.server.gasifierSupply end)
        gasifierCall(self, "gasifierSupply", gasifier, { watts = 0, hours = 1 })
        T.step(function() self.idle = self.server.gasifierSupply end)
    end,
    validate = function(self)
        T.expectNear("wood for an hour at 2 kW", self.loaded.burned, Gasifier.KG_PER_KWH * 2, 0.01)
        T.expect(self.loaded.kept, "a gasifier with wood didn't keep up")
        T.expectNear("wood for an hour at no load", self.idle.burned, 0, 0.01)
    end,
})

-- Only a gasifier right beside the generator can be piped to it.
test("renewable_energy_gas_gasifier_must_stand_beside", {
    instant = true,
    run = function(self)
        local generator = placeGenerator(self, 0)
        if not generator then return end
        local square = (T.need(self, T.squares(self, 1, { near = generator.square, minDistance = 2 }), "a free square two from the generator") or {})[1]
        if not square then return end
        local gasifier = placeGasifier(self, "primitive", square)
        T.setPerk(self, Perks.Mechanics, 2)
        T.give(self, "tools", { { type = GasKit.ITEM }, { type = "Base.Wrench" }, { type = GasKit.PIPE } })
        gasJob(self, generator, GasKit.INSTALL)
        T.waitUntil(function() return GasKit.hasKit(generator.object) end, COPY_FRAMES, "this client's copy of the kit")
        T.step(function() self.blocker = GasKit.blocker(GasKit.CONNECT, generator.object, gasifier.object) end)
    end,
    validate = function(self)
        T.expect(self.blocker == "Tooltip_RenewableEnergy_GasifierNotBeside", "a gasifier two squares off: " .. tostring(self.blocker))
    end,
})

-- The ash pit fills as wood burns; Clean Out Ash with a shovel gives Wood Ash for it. The filter's
-- packing turns tarry, and with none clean the gas halves and wears the generator.
test("renewable_energy_gas_gasifier_ash_and_tar", {
    instant = true,
    run = function(self)
        local square = (T.need(self, T.squares(self, 1), "a free square for a gasifier") or {})[1]
        if not square then return end
        local gasifier = placeGasifier(self, "standard", square)
        local spec = Gasifier.TIERS.standard
        gasifierCall(self, "gasifierFill", gasifier, { hopper = { { type = "Base.Plank", count = 7 } }, filter = { { type = "Base.HayTuft", count = 2 } } })
        gasifierCall(self, "gasifierSet", gasifier, { fields = { lit = true } })
        gasifierCall(self, "gasifierBurn", gasifier, { kg = 2 * spec.tarKgPerItem + 0.5 })
        readGasifier(self, gasifier, "burned")
        -- Out, so no pass burns more meanwhile.
        gasifierCall(self, "gasifierSet", gasifier, { fields = { ash = 60, lit = false } })
        T.give(self, "shovel", { { type = "Base.Shovel" } })
        gasifierJob(self, gasifier, GasifierJobs.CLEAN_ASH)
        readGasifier(self, gasifier, "cleaned")
        T.count(self, "ash", { Gasifier.WOOD_ASH })
    end,
    validate = function(self)
        local burned, cleaned = self.reads.burned, self.reads.cleaned
        local spec = Gasifier.TIERS.standard
        T.expectNear("ash after burning", burned.ash, (2 * spec.tarKgPerItem + 0.5) * spec.ashPerKg, 0.05)
        T.expect(burned.clean == 0 and burned.tarry == 2, "packing after burning: " .. tostring(burned.clean) .. " clean, " .. tostring(burned.tarry) .. " tarry")
        T.expect(burned.summary.output == Gasifier.DIRTY_OUTPUT, "a spent filter gives " .. tostring(burned.summary.output) .. " of the gas")
        T.expect(burned.summary.wear == Gasifier.WEAR_DIRTY, "a spent filter wears the generator " .. tostring(burned.summary.wear) .. " times")
        T.expectNear("ash after cleaning out", cleaned.ash, 60 - 2 * Gasifier.ASH_PER_ITEM, 0.01)
        T.expect(self.counts.ash[Gasifier.WOOD_ASH] == 2, "cleaning out 60% gave " .. tostring(self.counts.ash[Gasifier.WOOD_ASH]) .. " wood ash")
    end,
})

-- A cold gasifier takes bellows to light; one just put out doesn't.
test("renewable_energy_gas_gasifier_cold_start", {
    instant = true,
    run = function(self)
        local square = (T.need(self, T.squares(self, 1), "a free square for a gasifier") or {})[1]
        if not square then return end
        local gasifier = placeGasifier(self, "primitive", square)
        gasifierCall(self, "gasifierFill", gasifier, { hopper = { { type = "Base.Plank", count = 2 } } })
        T.give(self, "matches", { { type = "Base.Matches" } })
        T.waitUntil(function()
            local summary = Gasifier.summaryOf(gasifier.object)
            return summary ~= nil and summary.hopperKg > 0
        end, COPY_FRAMES, "this client's summary of the gasifier's wood")
        T.step(function()
            self.coldRefusal = GasifierJobs.refusal(T.player(), GasifierJobs.LIGHT, Gasifier.summaryOf(gasifier.object))
        end)
        T.give(self, "bellows", { { type = "Base.Bellows" } })
        gasifierJob(self, gasifier, GasifierJobs.LIGHT)
        gasifierJob(self, gasifier, GasifierJobs.PUT_OUT)
        T.waitUntil(function()
            local summary = Gasifier.summaryOf(gasifier.object)
            return summary ~= nil and not summary.lit
        end, COPY_FRAMES, "this client's summary of the gasifier put out")
        T.step(function()
            local summary = Gasifier.summaryOf(gasifier.object)
            self.warm = { cold = summary.cold, needs = #GasifierJobs.needs(T.player(), GasifierJobs.LIGHT, summary) }
        end)
        readGasifier(self, gasifier, "out")
    end,
    validate = function(self)
        T.expect(self.coldRefusal == "short", "a cold gasifier lit without bellows: " .. tostring(self.coldRefusal))
        T.expect(self.reads.out.outSince ~= nil, "lighting and putting it out never lit it")
        T.expect(not self.warm.cold and self.warm.needs == 1, "just put out, it still wants bellows")
    end,
})

-- Lit indoors, a gasifier fills the building with fumes until it goes out.
test("renewable_energy_gas_gasifier_fumes_indoors", {
    instant = true,
    run = function(self)
        local square = (T.need(self, T.squares(self, 1, { indoors = true }), "a free indoor square for a gasifier") or {})[1]
        if not square then return end
        local gasifier = placeGasifier(self, "primitive", square)
        gasifierCall(self, "gasifierSet", gasifier, { fields = { lit = true, fireKg = 2 } })
        readGasifier(self, gasifier, "lit")
        gasifierCall(self, "gasifierSet", gasifier, { fields = { lit = false } })
        readGasifier(self, gasifier, "out")
    end,
    validate = function(self)
        T.expect(self.reads.lit.toxic, "a lit gasifier indoors left the building clean")
        T.expect(not self.reads.out.toxic, "the building stayed toxic once the gasifier went out")
    end,
})

-- Condensate drained hot goes only into metal, glass or cookware; a pot takes what it holds.
test("renewable_energy_gas_gasifier_drain_condensate", {
    instant = true,
    run = function(self)
        local square = (T.need(self, T.squares(self, 1), "a free square for a gasifier") or {})[1]
        if not square then return end
        local gasifier = placeGasifier(self, "primitive", square)
        gasifierCall(self, "gasifierSet", gasifier, { fields = { lit = true, fireKg = 5, condensate = 2 } })
        T.give(self, "containers", { { type = "Base.WaterBottle" }, { type = "Base.Pot" } })
        T.server(self, "refillFluid", function() return { id = self.items.containers[1]:getID() } end)
        T.server(self, "refillFluid", function() return { id = self.items.containers[2]:getID() } end)
        T.step(function()
            self.bottle = Gasifier.takesCondensate(self.items.containers[1], true)
            self.pot = Gasifier.takesCondensate(self.items.containers[2], true)
            self.coldBottle = Gasifier.takesCondensate(self.items.containers[1], false)
        end)
        T.waitUntil(function()
            local summary = Gasifier.summaryOf(gasifier.object)
            return summary ~= nil and summary.condensate >= 2
        end, COPY_FRAMES, "this client's summary of the condensate")
        T.goNextTo(self, gasifier.square)
        T.step(function()
            ISTimedActionQueue.add(RenewableEnergyGasifierAction:new(T.player(), GasifierJobs.DRAIN, gasifier.object, self.items.containers[2]))
        end)
        readGasifier(self, gasifier, "drained")
        T.server(self, "carried", { fluids = { Gasifier.VINEGAR } })
    end,
    validate = function(self)
        T.expect(not self.bottle, "a plastic bottle takes the condensate hot")
        T.expect(self.pot, "a pot won't take the condensate hot")
        T.expect(self.coldBottle, "a plastic bottle won't take it cold")
        local potHolds = instanceItem("Base.Pot"):getFluidContainer():getCapacity()
        local poured = math.min(2, potHolds)
        T.expectNear("wood vinegar carried", self.server.carried.fluids[Gasifier.VINEGAR], poured, 0.01)
        T.expectNear("condensate left", self.reads.drained.condensate, 2 - poured, 0.01)
    end,
})

-- Wood vinegar cut with water makes the game's own mildew spray.
T.craftTest("renewable_energy_gas_vinegar_mildew_spray", {
    recipe = "RenewableEnergy_MakeVinegarMildewSpray",
    from = "Base.GardeningSprayEmpty",
    setup = function(self)
        local fluids = { { Gasifier.VINEGAR, 0.5 }, { "Water", 1 } }
        local index = 1
        for _, item in ipairs(self.items.inputs or {}) do
            if item:getFluidContainer() and fluids[index] then
                T.server(self, "refillFluid", { id = item:getID(), fluid = fluids[index][1], liters = fluids[index][2] })
                index = index + 1
            end
        end
    end,
    counts = { ["Base.GardeningSprayMilk"] = 1, ["Base.GardeningSprayEmpty"] = 0 },
})
