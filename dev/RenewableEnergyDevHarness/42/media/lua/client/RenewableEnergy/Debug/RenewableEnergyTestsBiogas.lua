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

local function queueJob(self, handle, job, item)
    T.step(function()
        T.standNextTo(handle.square)
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
        T.step(function() queueJob(self, handle, DigesterJobs.TAKE_SLUDGE, self.items.bag[1]) end)
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
