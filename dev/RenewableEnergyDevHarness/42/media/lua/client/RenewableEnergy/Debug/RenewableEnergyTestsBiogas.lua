require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"

-- Biogas (Contents/.../RenewableEnergy/Biogas/*, UI/Digester*): digestion, the hopper's feed, the
-- gas holder, the digester's jobs and build, and campfire wood ash. The stink is in
-- RenewableEnergyTestsBiogasStink.lua; the gas heater, pump, compressor and propane in
-- RenewableEnergyTestsBiogasUses.lua.

local T = RenewableEnergyTest
local test = T.test

local Digester, DigesterJobs = RenewableEnergy.Digester, RenewableEnergy.DigesterJobs
local Sprites = RenewableEnergy.Sprites

local FEED = "Base.Dung_Cow"

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
        local foam = Sprites.digesterSour.barrel
        T.expect(reads.over.sour and T.hasOverlay(reads.over, foam), "acid just over the limit didn't sour it, or it shows no foam")
        T.expect(not reads.under.sour and not T.hasOverlay(reads.under, foam), "acid just under the limit soured it, or it shows foam")
        T.expect(reads.sourAbove.sour, "a sour digester recovered just above its recovery share of the limit")
        T.expect(not reads.sourBelow.sour, "a sour digester stayed sour just below its recovery share of the limit")
        T.expect(not reads.ash.sour and reads.ash.hopperItems == 0 and not T.hasOverlay(reads.ash, foam),
            "wood ash didn't fix it, stayed in the hopper, or left the foam showing")
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
        T.reloadChunk(self, handle, function()
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
-- torn; Fit Garbage Bags takes new bags and mends them.
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
        self.replace = DigesterJobs.materials(T.player(), DigesterJobs.FIT_BAGS)
        T.giveMaterials(self, "bags", self.replace)
        T.gasJob(self, "digester", handle, DigesterJobs.FIT_BAGS)
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
        T.expectMaterialsUsed(self, "left", self.replace, "Fit Garbage Bags")
    end,
})

-- A Tarp Gas Bag goes on only once the gas is vented, at its own wear, and comes off whole, its
-- wear its condition again, leaving the barrel with nothing to hold gas.
test("renewable_energy_biogas_digester_tarp_gas_bag", {
    instant = true,
    run = function(self)
        local handle = T.placeRecord(self, "digester", "barrel.MetalDrum")
        if not handle then return end
        self.tarp = Digester.HOLDERS.tarp.item
        T.setRecord(self, handle, T.matureDigester("barrel", { gas = 0.3 }))
        T.give(self, "tarp", { { type = self.tarp, condition = 6 } })
        T.waitForGas(self, handle, 0.3)
        T.step(function()
            self.gassy = DigesterJobs.refusal(T.player(), DigesterJobs.FIT_TARP, handle.object, self.items.tarp[1])
        end)
        T.gasJob(self, "digester", handle, DigesterJobs.VENT)
        T.waitForGas(self, handle, 0)
        T.gasJob(self, "digester", handle, DigesterJobs.FIT_TARP, function() return self.items.tarp[1] end)
        T.batch(function()
            T.readRecord(self, handle, "fitted")
            T.readCarried(self, { self.tarp }, nil, "fittedCarried")
        end)
        T.waitForSummary(self, handle, function(summary) return summary.holder == "tarp" end, "this client's summary of the tarp")
        T.gasJob(self, "digester", handle, DigesterJobs.TAKE_OFF_BAG)
        T.batch(function()
            T.readRecord(self, handle, "off")
            T.readCarried(self, { self.tarp }, nil, "offCarried")
        end)
    end,
    validate = function(self)
        local fitted, off = self.reads.fitted, self.reads.off
        T.expect(self.gassy == "Tooltip_RenewableEnergy_VentFirst", "Fit Tarp Gas Bag with gas in the bags: " .. tostring(self.gassy))
        T.expect(fitted.holder == "tarp", "the fitted holder is " .. tostring(fitted.holder))
        T.expectNear("the fitted tarp's wear left, in percent", fitted.holderCondition,
            100 * 6 / instanceItem(self.tarp):getConditionMax(), 0.5)
        T.expect(#T.carriedItems(self, self.tarp, "fittedCarried") == 0, "fitting left the Tarp Gas Bag in the inventory")
        T.expect(off.holder == "none", "taking it off left " .. tostring(off.holder))
        local back = T.carriedFirst(self, self.tarp, "offCarried")
        T.expect(back ~= nil and back.condition == 6, "the Tarp Gas Bag came back at " .. tostring(back and back.condition))
    end,
})

-- Jobs -------------------------------------------------------------------------------------------

-- Take Sludge refuses without a bag to fill; it fills an empty sack, of any kind vanilla's composter
-- takes, into a compost bag, a use per share of sludge as the composter does, up to a full bag; less
-- sludge than a bag holds goes into a part-filled bag.
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
        T.give(self, "bags", { { type = "Base.EmptySandbag", count = 1 }, { type = "Base.Bag_DeadRats", count = 1 } })
        T.gasJob(self, "digester", handle, DigesterJobs.TAKE_SLUDGE, function() return self.items.bags[1] end)
        T.batch(function()
            T.readRecord(self, handle, "first")
            T.setRecord(self, handle, { sludge = part })
        end)
        T.waitForSummary(self, handle, function(summary) return summary.sludge == part end, "this client's summary of the sludge")
        T.gasJob(self, "digester", handle, DigesterJobs.TAKE_SLUDGE, function() return self.items.bags[2] end)
        T.batch(function()
            T.readRecord(self, handle, "second")
            T.readCarried(self, { DigesterJobs.COMPOST_BAG, "Base.EmptySandbag", "Base.Bag_DeadRats" })
        end)
    end,
    validate = function(self)
        T.expect(self.noBag == "Tooltip_RenewableEnergy_NeedsSack", "Take Sludge with no bag: " .. tostring(self.noBag))
        T.expectNear("sludge left after a full bag", self.reads.first.sludge, self.full - Digester.SLUDGE_PER_BAG, 0.001)
        T.expectNear("sludge left after a part bag", self.reads.second.sludge, 0, 0.001)
        local bags = T.carriedItems(self, DigesterJobs.COMPOST_BAG)
        T.expect(#T.carriedItems(self, "Base.EmptySandbag") + #T.carriedItems(self, "Base.Bag_DeadRats") == 0 and #bags == 2,
            "the sacks didn't become compost bags")
        if #bags == 2 then
            local fullest, other = math.max(bags[1].uses, bags[2].uses), math.min(bags[1].uses, bags[2].uses)
            T.expectNear("the first bag", fullest, 1, 0.001)
            T.expectNear("the part bag", other, 0.5, 0.001)
        end
    end,
})

-- Upgrading a barrel builds the insulated digester around it in place: the tile, the floating drum,
-- the bigger hopper on this client too; what it held stays, and the job takes its materials and
-- teaches Woodwork.
test("renewable_energy_biogas_digester_upgrade", {
    instant = true,
    run = function(self)
        local handle = T.placeRecord(self, "digester", "barrel.MetalDrum")
        if not handle then return end
        self.digester = handle
        self.capacity = tonumber(getSprite(Sprites.digester.insulated):getProperties():get("ContainerCapacity"))
        self.upgrade = DigesterJobs.materials(T.player(), DigesterJobs.UPGRADE)
        self.dung = 2
        -- At its cap, so it eats nothing from the hopper meanwhile.
        T.batch(function()
            T.setRecord(self, handle, T.matureDigester("barrel"))
            T.fillRecord(self, handle, { hopper = { { type = FEED, count = self.dung } } })
            T.read(self, "perkXp", { perk = "Woodwork" }, "xpBefore")
        end)
        T.giveMaterials(self, "materials", self.upgrade)
        T.gasJob(self, "digester", handle, DigesterJobs.UPGRADE)
        T.batch(function()
            T.readRecord(self, handle, "after")
            T.countMaterials(self, "left", self.upgrade)
            T.read(self, "perkXp", { perk = "Woodwork" }, "xpAfter")
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
        local xpBefore, xpAfter = self.reads.xpBefore.value, self.reads.xpAfter.value
        T.expect(xpAfter > xpBefore, "upgrading gave no Woodwork XP: " .. xpBefore .. " before, " .. xpAfter .. " after")
    end,
})

-- Queues, on this client's copy of the barrel digester `handle` showing the tile `tile`, what a
-- player does with it, into self.views[label]: its status window's title, and whether its hopper
-- took the cow dung they dragged in (the record's count, in self.reads[label]). Also whether its
-- SpriteConfig took the tile: the game logs "Invalid SpriteConfig object!" wherever an object
-- loads with one that didn't, and vanilla's menus get no master object for it.
local function useBarrelDigester(self, handle, tile, label)
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

-- Expects useBarrelDigester's `label` to have found a whole barrel digester.
local function expectBarrelDigester(self, label)
    local view, read = self.views[label], self.reads[label]
    if not T.expect(view ~= nil and read ~= nil, label .. ": never saw the digester") then return end
    T.expect(view.title == getText("IGUI_RenewableEnergy_Digester_barrel"), label .. ": the status window's title is " .. tostring(view.title))
    T.expect(view.configValid and view.master, label .. ": its SpriteConfig refused its tile")
    T.expect(read.hopperItems == 1, label .. ": the hopper holds " .. tostring(read.hopperItems) .. " items, not the dung dragged in")
end

-- The build menu builds a barrel digester on the Metal Drum's tile, from any of the game's drums;
-- its OnCreate, on the authority, makes it the digester of the drum the build took, on that drum's
-- tile and as that drum's entity, which this client sees, opens and feeds.
test("renewable_energy_biogas_build_menu_builds_digester", {
    instant = true,
    run = function(self)
        self.views = {}
        self.tile = Sprites.digester.barrel.Mov_OrangeBarrel
        local handle = T.buildRecord(self, "digester", "Base.RenewableEnergy_BarrelDigester", self.tile, { "Base.Mov_OrangeBarrel" })
        if not handle then return end
        useBarrelDigester(self, handle, self.tile, "fed")
    end,
    validate = function(self)
        local built = self.reads.built or {}
        T.expect(built.tier == "barrel" and built.sprite == self.tile, "the build menu built " .. tostring(built.tier)
            .. " on " .. tostring(built.sprite))
        expectBarrelDigester(self, "fed")
    end,
})

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
        T.reloadChunk(self, handle)
        useBarrelDigester(self, handle, tile, "reloaded")
    end,
    validate = function(self)
        expectBarrelDigester(self, "reloaded")
    end,
})

-- Right-clicking a barrel digester shows its submenu through vanilla's menu builder: its status,
-- and its jobs, each tooltip saying what it does, greyed out with the reason under that while the
-- digester or the character can't do them; the gas bag's jobs in a submenu of their own. The
-- status window opens on it and shows its state.
test("renewable_energy_biogas_digester_menu", {
    run = function(self)
        self.digester = T.placeRecord(self, "digester", "barrel.MetalDrum")
    end,
    validate = function(self)
        local object = self.digester.object
        local function job(name, share)
            return getText("ContextMenu_RenewableEnergy_" .. name) .. (share and " (" .. share .. ")" or "")
        end
        local options = T.worldOptions(object, getText("IGUI_RenewableEnergy_Digester_barrel"), { status = job("Status"),
            sludge = job(DigesterJobs.TAKE_SLUDGE, "0%"), vent = job(DigesterJobs.VENT, "0%"), bag = job("GasBag"),
            upgrade = job(DigesterJobs.UPGRADE) })
        if T.expect(options ~= nil, "right-clicking a digester shows no digester submenu") then
            T.expect(options.status ~= nil, "no Status option")
            local sludge = T.tooltipOf(options.sludge)
            T.expect(options.sludge and options.sludge.notAvailable
                and sludge:find(getText("Tooltip_RenewableEnergy_TakeSludge"), 1, true) == 1
                and sludge:find(getText("Tooltip_RenewableEnergy_NoSludge"), 1, true),
                "Take Sludge isn't greyed out for an empty digester under what it does: " .. sludge)
            T.expect(options.vent and options.vent.notAvailable, "Vent Gas isn't greyed out with no gas")
            T.expect(options.bag ~= nil and options.bag.subOption ~= nil, "no Gas Bag submenu on a barrel")
            local upgrade = options.upgrade
            local tooltip, unlisted = T.tooltipOf(upgrade), {}
            for _, need in ipairs(DigesterJobs.needs(T.player(), DigesterJobs.UPGRADE)) do
                local name = need.kind == "item" and not need.label and not need.labelKey and getItemNameFromFullType(need.item)
                if name and not tooltip:find(name, 1, true) then table.insert(unlisted, name) end
            end
            T.expect(upgrade and upgrade.notAvailable and #unlisted == 0,
                "Upgrade isn't greyed out listing what it takes: missing " .. table.concat(unlisted, ", "))
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
