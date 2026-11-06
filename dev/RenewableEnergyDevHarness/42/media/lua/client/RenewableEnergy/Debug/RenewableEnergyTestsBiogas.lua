require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"
local Fixtures = require "RenewableEnergy/Debug/RenewableEnergyFixtures"
local Digester = require "RenewableEnergy/Biogas/Digester"
local DigesterJobs = require "RenewableEnergy/Biogas/DigesterJobs"
local DigesterWindow = require "RenewableEnergy/UI/DigesterWindow"
local GasKit = require "RenewableEnergy/GasLine/GasKit"
local Gasifier = require "RenewableEnergy/WoodGas/Gasifier"
local Sprites = require "RenewableEnergy/Sprites"

-- Biogas (Contents/.../RenewableEnergy/Biogas/*, UI/Digester*): digestion, the hopper's feed, the
-- gas holder, the digester's jobs and build, and campfire wood ash. The stink is in
-- RenewableEnergyTestsBiogasStink.lua; the gas heater, pump, compressor and propane in
-- RenewableEnergyTestsBiogasUses.lua.

local T = RenewableEnergyTest
local test = T.test


local FEED = "Base.Dung_Cow"
-- What a cow pat puts in the tank (Digester's FEEDS): its potential, in m³, and the startup hours
-- its manure saves.
local COW_POTENTIAL, COW_SEED_HOURS = 1.0, 24

-- The stink score of each state of a digester, and the corpses each score smells like.
T.serverCheck("renewable_energy_biogas_digester_stink_score", "digesterStink")

-- How strongly a digester stinks, as the smell moodle of the character standing at it: a mature
-- barrel at the first smell level, a sour one at the second; an unfed one not at all; the Brick
-- Dome at its worst at the first and no further. A sour barrel picked up stops smelling at once,
-- before the clock moves on.
test("renewable_energy_biogas_digester_stink_levels", {
    instant = true,
    run = function(self)
        local barrel = T.placeRecord(self, "digester", "barrel.MetalDrum")
        local dome = barrel and T.placeRecord(self, "digester", "dome")
        if not dome then return end
        -- Mid-startup, when the startup stinks most, full, its sludge at the top and sour.
        local worst = T.sourDigester("dome", { started = false, startupHours = getSandboxOptions():getCompostHours() / 2, seedHours = 0,
            sludge = 100 })
        T.standOn(barrel)
        T.setRecord(self, barrel, Fixtures.matureDigester("barrel"))
        T.waitForAuthoritySmell(self, barrel, 1, "mature")
        T.setRecord(self, barrel, { fed = false })
        T.waitForAuthoritySmell(self, barrel, 0, "unfed")
        T.setRecord(self, barrel, T.sourDigester("barrel"))
        T.waitForAuthoritySmell(self, barrel, 2, "sour")
        -- Frozen, the clock can't bring a later clear in while the smell settles.
        T.server(self, "freezeClock", { frozen = true })
        T.pickUpAsPlayer(self, barrel, Sprites.digester.barrel.MetalDrum)
        T.waitForAuthoritySmell(self, barrel, 0, "picked up")
        T.server(self, "freezeClock", { frozen = false })
        T.step(function() T.standOn(dome) end)
        T.setRecord(self, dome, worst)
        T.waitForAuthoritySmell(self, dome, 1, "dome")
    end,
    validate = function(self)
        local reads = self.reads
        for label, level in pairs({ mature = 1, sour = 2, unfed = 0, ["picked up"] = 0, dome = 1 }) do
            T.expectEqual("the smell level at the " .. label .. " digester", reads[label] and reads[label].level, level)
        end
    end,
})

-- Digestion --------------------------------------------------------------------------------------

-- No gas until the startup's warm hours are done: at STARTUP_MIN_TEMP the hours count and a degree
-- below they don't; it starts at exactly the hours needed, and digests from the next hour: at
-- 35 °C (k = 1/15 a day) its 5 m³ of potential give 5 × (1 − e^(−1/360)) m³ in that hour. Manure's
-- head start shortens it by at most its share.
test("renewable_energy_biogas_digester_startup_then_gas", {
    sandbox = { BiogasMultiplier = 1 },
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
            T.setRecord(self, handle, { temp = 35 })
            T.runDigester(self, handle, 1, 35)
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
        T.expectNear("m³ of gas in the first hour after the startup", reads.after.gas, 5 * (1 - math.exp(-1 / 360)), 1e-8)
        T.expect(not reads.seededBefore.started, "manure's head start covered more than its share")
        T.expect(reads.seededAfter.started, "manure's head start didn't shorten the startup")
    end,
})

-- An hour's gas from a mature barrel, its 5 m³ of potential digesting at the rate k a day that
-- Digester.K_BY_TEMP gives its temperature, in straight lines between its rows {10, 0}, {15, 0.01},
-- {25, 1/30}, {35, 1/15}, {40, 1/15} and {50, 0}: 5 × (1 − e^(−k/24)) m³. Sour, it digests at 0.15
-- of that (DigesterObject's SOUR_K); past SLUDGE_SLOW (80 %) of sludge, at SLUDGE_K, and at exactly
-- 80 % at the full rate. Each case's temperature is the air's too, so it holds through the hour.
local K_BEST = 1 / 15
local GAS_HOURS = {
    { what = "at 10 °C, the cold end", temp = 10, k = 0 },
    { what = "at 11 °C, a fifth of the way from 10 °C to 15 °C", temp = 11, k = 0.01 / 5 },
    { what = "at 20 °C, halfway from 15 °C to 25 °C", temp = 20, k = (0.01 + 1 / 30) / 2 },
    { what = "at 35 °C", temp = 35, k = K_BEST },
    { what = "at 40 °C", temp = 40, k = K_BEST },
    { what = "at 49 °C, a tenth of the way back from 50 °C", temp = 49, k = K_BEST / 10 },
    { what = "at 50 °C, the hot end", temp = 50, k = 0 },
    { what = "sour, at 35 °C", temp = 35, sour = true, k = K_BEST * 0.15 },
    { what = "with 80 % sludge, at 35 °C", temp = 35, sludge = 80, k = K_BEST },
    { what = "with 81 % sludge, at 35 °C", temp = 35, sludge = 81, k = K_BEST * Digester.SLUDGE_K },
}

local function barrelHour(k)
    return Digester.TIERS.barrel.potentialCap * (1 - math.exp(-k / 24))
end

-- The gas of GAS_HOURS; the Biogas Multiplier scales it in proportion. The barrel follows the air
-- with a time constant of its tier's `days` (1): three days from 30 °C in 0 °C air leave 30·e^−3.
test("renewable_energy_biogas_digester_gas_rate", {
    sandbox = { BiogasMultiplier = 1 },
    run = function(self)
        local handle = T.placeRecord(self, "digester", "barrel.MetalDrum")
        if not handle then return end
        T.batch(function()
            for i, case in ipairs(GAS_HOURS) do
                local fields = { temp = case.temp, gas = 0, sludge = case.sludge or 0 }
                T.setRecord(self, handle, case.sour and T.sourDigester("barrel", fields) or Fixtures.matureDigester("barrel", fields))
                T.runDigester(self, handle, 1, case.temp)
                T.readRecord(self, handle, "hour" .. i)
            end
            T.setRecord(self, handle, Fixtures.matureDigester("barrel", { temp = 30 }))
            T.runDigester(self, handle, 72, 0)
            T.readRecord(self, handle, "cooled")
        end)
        T.step(function() T.setSandbox(self, "BiogasMultiplier", 2) end)
        T.batch(function()
            T.setRecord(self, handle, Fixtures.matureDigester("barrel", { temp = 35, gas = 0 }))
            T.runDigester(self, handle, 1, 35)
            T.readRecord(self, handle, "doubled")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        for i, case in ipairs(GAS_HOURS) do
            T.expectNear("m³ of gas a mature barrel made in an hour " .. case.what, reads["hour" .. i].gas, barrelHour(case.k), 1e-8)
        end
        T.expectNear("m³ of gas in an hour at 35 °C at a Biogas Multiplier of 2", reads.doubled.gas, 2 * barrelHour(K_BEST), 1e-8)
        T.expectNear("°C three days at 0 °C left the barrel at", reads.cooled.temp, 30 * math.exp(-3), 1e-6)
    end,
})

-- The Brick Dome, started and holding gas, burns a gas heater's rate to keep at its warmTo (20 °C)
-- in freezing air, and the hour its gas runs short it burns the rest and still keeps warm. With
-- none left it cools, buried, toward the ground's 12 °C, not the air's, with its tier's time
-- constant (days = 8): 12 + 8·e^(−23/192) after the 23 hours past that. Nothing to digest
-- (potential 0), so all the gas it loses is what it burned.
test("renewable_energy_biogas_dome_burns_gas_to_keep_warm", {
    sandbox = { GeneratorFuelConsumption = 1 },
    run = function(self)
        local handle = T.placeRecord(self, "digester", "dome")
        if not handle then return end
        -- A heater burns an idling generator's bill: IDLE_FUEL litres an hour at the option's 1,
        -- M3_PER_LITRE m³ of gas each.
        self.rate = GasKit.IDLE_FUEL * 1 * GasKit.M3_PER_LITRE
        T.batch(function()
            T.setRecord(self, handle, Fixtures.matureDigester("dome", { temp = 20, gas = 2.5 * self.rate, potential = 0 }))
            T.runDigester(self, handle, 2, -5)
            T.readRecord(self, handle, "warm")
            T.runDigester(self, handle, 24, -5)
            T.readRecord(self, handle, "cold")
        end)
    end,
    validate = function(self)
        local warm, cold = self.reads.warm, self.reads.cold
        T.expectNear("°C of the dome after two hours in −5 °C air with gas to burn", warm.temp, 20, 1e-6)
        T.expectNear("m³ of gas the dome kept after burning two hours' worth", warm.gas, 0.5 * self.rate, 1e-8)
        T.expectEqual("m³ of gas left once the dome burned it all", cold.gas, 0)
        T.expectNear("°C of the dome 23 hours after its gas ran out", cold.temp, 12 + 8 * math.exp(-23 / 192), 1e-6)
    end,
})

-- Acid just over the limit sours it and just under doesn't; once sour it stays sour until just
-- below the share of the limit it recovers at. Wood ash fixes it whole, baking soda a use at a time.
test("renewable_energy_biogas_digester_sour_and_fix", {
    run = function(self)
        local handle = T.placeRecord(self, "digester", "barrel.MetalDrum")
        if not handle then return end
        local limit = Digester.ACID_LIMIT * Digester.TIERS.barrel.potentialCap
        -- Each with a fresh day's intake, so the alkali goes in at the first hour.
        local function set(share, sour)
            T.setRecord(self, handle, Fixtures.matureDigester("barrel", { acid = share * limit, sour = sour, intakeKg = 0 }))
        end
        -- An hour's decay takes far less acid than the step, so each side stays on its side.
        local step = 0.01
        local soda = instanceItem("Base.BakingSoda")
        local usesLeft = soda:getCurrentUses() - 3
        local recover = Digester.ACID_RECOVER
        T.batch(function()
            for _, case in ipairs({ { "over", 1 + step, false }, { "under", 1 - step, false },
                { "sourAbove", recover + step, true }, { "sourBelow", recover - step, true } }) do
                set(case[2], case[3])
                T.runDigester(self, handle, 1, 30)
                T.readRecord(self, handle, case[1])
            end
            set(1 + step, true)
            T.fillRecord(self, handle, { hopper = { { type = Gasifier.WOOD_ASH } } })
            T.runDigester(self, handle, 1, 30)
            T.readRecord(self, handle, "ash")
            set(1 + step, true)
            T.fillRecord(self, handle, { hopper = { { type = "Base.BakingSoda" } } })
            T.runDigester(self, handle, 1, 30)
            T.readRecord(self, handle, "soda")
            T.setRecord(self, handle, { acid = 1 - 2 * Digester.feedOf(soda).acid, intakeKg = 0 })
            T.runDigester(self, handle, 2, 30)
        end)
        T.waitFor(self, function()
            local item = handle.object:getContainer():getFirstType("Base.BakingSoda")
            return item ~= nil and item:getCurrentUses() == usesLeft
        end, "three uses taken from this client's box of baking soda")
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

-- The hopper takes manure, alkalis and food however fresh, but not a worm, on this client's copy as
-- in the loot window. Feed goes into the tank by weight: a dome takes its kgPerDay of cow pats in a
-- day, and a barrel half a pat short of its cap takes that one pat and no more, ending half a pat
-- past its cap. Manure eaten brings its head start.
test("renewable_energy_biogas_digester_hopper_meters", {
    run = function(self)
        local barrel = T.placeRecord(self, "digester", "barrel.MetalDrum")
        local dome = barrel and T.placeRecord(self, "digester", "dome")
        if not dome then return end
        self.barrel = barrel
        -- Pats by the game's weight of one.
        self.domeDay = Digester.TIERS.dome.kgPerDay / instanceItem(FEED):getActualWeight()
        self.domeCount = self.domeDay + 3
        self.barrelCount = 3
        T.batch(function()
            -- Cold, so it never starts and nothing in the tank digests.
            T.setRecord(self, barrel, { fed = true, started = false, startupHours = 0, seedHours = 0, temp = 0,
                potential = Digester.TIERS.barrel.potentialCap - COW_POTENTIAL / 2 })
            T.fillRecord(self, barrel, { hopper = { { type = FEED, count = self.barrelCount } } })
            T.runDigester(self, barrel, 48, 0)
            T.readRecord(self, barrel, "barrel")
            T.fillRecord(self, dome, { hopper = { { type = FEED, count = self.domeCount } } })
            T.runDigester(self, dome, 24, 0)
            T.readRecord(self, dome, "dome")
        end)
        T.waitForSummary(self, barrel, function(summary) return summary.hopper == self.barrelCount - 1 end,
            "this client's count of the barrel's hopper")
    end,
    validate = function(self)
        local barrel, dome = self.reads.barrel, self.reads.dome
        T.expectEqual("cow pats the dome took in a day", self.domeCount - dome.hopperItems, self.domeDay)
        T.expectEqual("cow pats the barrel took a pat short of its cap", self.barrelCount - barrel.hopperItems, 1)
        T.expectNear("m³ of potential in the barrel's tank", barrel.potential, Digester.TIERS.barrel.potentialCap + COW_POTENTIAL / 2,
            1e-9)
        T.expectNear("startup the manure seeded", barrel.seedHours, COW_SEED_HOURS, 1e-9)
        local container = self.barrel.object:getContainer()
        local function allowed(fullType)
            return container:isItemAllowed(instanceItem(fullType))
        end
        T.expect(allowed(FEED) and allowed(Gasifier.WOOD_ASH), "this client's hopper refuses manure or wood ash")
        T.expect(allowed("Base.Turnip"), "this client's hopper refuses a fresh turnip")
        T.expect(not allowed("Base.Worm") and not allowed("Base.Hammer"), "this client's hopper takes a live worm or a hammer")
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

-- Holder -----------------------------------------------------------------------------------------

-- The bags hold what they can and vent the rest; worn through they tear, hold nothing and show
-- torn; Fit Garbage Bags takes new bags and mends them.
test("renewable_energy_biogas_digester_holder", {
    instant = true,
    run = function(self)
        local handle = T.placeRecord(self, "digester", "barrel.MetalDrum")
        if not handle then return end
        local bags = Digester.HOLDERS.bags
        local overfull = Fixtures.matureDigester("barrel", { gas = bags.capacity + 0.1 })
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
        T.actionJob(self, "digester", handle, DigesterJobs.FIT_BAGS)
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
-- wear its condition again, leaving the barrel with nothing to hold gas. A worn-out one won't go on.
test("renewable_energy_biogas_digester_tarp_gas_bag", {
    instant = true,
    run = function(self)
        local handle = T.placeRecord(self, "digester", "barrel.MetalDrum")
        if not handle then return end
        self.tarp = Digester.HOLDERS.tarp.item
        T.setRecord(self, handle, Fixtures.matureDigester("barrel", { gas = 0.3 }))
        T.give(self, "tarp", { { type = self.tarp, condition = 6 }, { type = self.tarp, condition = 0 } })
        T.waitForGas(self, handle, 0.3)
        T.step(function()
            self.gassy = DigesterJobs.refusal(T.player(), DigesterJobs.FIT_TARP, handle.object, self.items.tarp[1])
        end)
        T.actionJob(self, "digester", handle, DigesterJobs.VENT)
        T.waitForGas(self, handle, 0)
        T.step(function()
            self.broken = DigesterJobs.refusal(T.player(), DigesterJobs.FIT_TARP, handle.object, self.items.tarp[2])
        end)
        T.actionJob(self, "digester", handle, DigesterJobs.FIT_TARP, function() return self.items.tarp[1] end)
        T.batch(function()
            T.readRecord(self, handle, "fitted")
            T.readCarried(self, { self.tarp }, nil, "fittedCarried")
        end)
        T.waitForSummary(self, handle, function(summary) return summary.holder == "tarp" end, "this client's summary of the tarp")
        T.actionJob(self, "digester", handle, DigesterJobs.TAKE_OFF_BAG)
        T.batch(function()
            T.readRecord(self, handle, "off")
            T.readCarried(self, { self.tarp }, nil, "offCarried")
        end)
    end,
    validate = function(self)
        local fitted, off = self.reads.fitted, self.reads.off
        T.expectEqual("Fit Tarp Gas Bag's refusal with gas in the bags", self.gassy, "Tooltip_RenewableEnergy_VentFirst")
        T.expectEqual("Fit Tarp Gas Bag's refusal of a worn-out bag", self.broken, "Tooltip_RenewableEnergy_NeedsTarpGasBag")
        T.expectEqual("the fitted holder", fitted.holder, "tarp")
        T.expectNear("the fitted tarp's wear left, in percent", fitted.holderCondition,
            100 * 6 / instanceItem(self.tarp):getConditionMax(), 0.5)
        T.expectEqual("Tarp Gas Bags left carried after fitting one", #T.carriedItems(self, self.tarp, "fittedCarried"), 1)
        T.expectEqual("the holder after taking it off", off.holder, "none")
        local conditions = {}
        for _, back in ipairs(T.carriedItems(self, self.tarp, "offCarried")) do
            conditions[back.condition] = true
        end
        T.expect(conditions[6], "the Tarp Gas Bag didn't come back at condition 6")
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
        T.actionJob(self, "digester", handle, DigesterJobs.TAKE_SLUDGE, function() return self.items.bags[1] end)
        T.batch(function()
            T.readRecord(self, handle, "first")
            T.setRecord(self, handle, { sludge = part })
        end)
        T.waitForSummary(self, handle, function(summary) return summary.sludge == part end, "this client's summary of the sludge")
        T.actionJob(self, "digester", handle, DigesterJobs.TAKE_SLUDGE, function() return self.items.bags[2] end)
        T.batch(function()
            T.readRecord(self, handle, "second")
            T.readCarried(self, { DigesterJobs.COMPOST_BAG, "Base.EmptySandbag", "Base.Bag_DeadRats" })
        end)
    end,
    validate = function(self)
        T.expectEqual("Take Sludge's refusal with no bag", self.noBag, "Tooltip_RenewableEnergy_NeedsSack")
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
            T.setRecord(self, handle, Fixtures.matureDigester("barrel"))
            T.fillRecord(self, handle, { hopper = { { type = FEED, count = self.dung } } })
            T.readCharacter(self, "xpBefore", { perks = { "Woodwork" } })
        end)
        T.giveMaterials(self, "materials", self.upgrade)
        T.actionJob(self, "digester", handle, DigesterJobs.UPGRADE)
        T.batch(function()
            T.readRecord(self, handle, "after")
            T.countMaterials(self, "left", self.upgrade)
            T.readCharacter(self, "xpAfter", { perks = { "Woodwork" } })
            -- What the job's award gives at this level, read after: it adds to the character's XP.
            T.xpAward(self, "Woodwork", DigesterJobs.JOBS[DigesterJobs.UPGRADE].xp.amount, "award")
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
        T.expectEqual("the tier", after.tier, "insulated")
        T.expectEqual("the holder", after.holder, "drum")
        T.expectEqual("the tile", after.sprite, Sprites.digester.insulated)
        T.expectEqual("the hopper's capacity", after.containerCapacity, self.capacity)
        T.expectEqual("manures in the hopper", after.hopperItems, self.dung)
        T.expectNear("potential kept", after.potential, Digester.TIERS.barrel.potentialCap, 0.01)
        T.expectMaterialsUsed(self, "left", self.upgrade, "Upgrade")
        local gained = self.reads.xpAfter.xp.Woodwork - self.reads.xpBefore.xp.Woodwork
        T.expect(self.reads.award.gained > 0, "the Upgrade's award gives no Woodwork XP, so the XP check proves nothing")
        T.expectNear("Woodwork XP from upgrading", gained, self.reads.award.gained, 0.01)
    end,
})

-- Queues, on this client's copy of the barrel digester `handle` showing the tile `tile`, what a
-- player does with it, into self.views[label]: whether its status window shows rows, and whether
-- its hopper, holding `held` dung already, took the cow dung they dragged in (the record's count,
-- in self.reads[label]). Also whether its SpriteConfig took the tile: the game logs "Invalid
-- SpriteConfig object!" wherever an object loads with one that didn't, and vanilla's menus get no
-- master object for it.
local function useBarrelDigester(self, handle, tile, label, held)
    T.waitFor(self, function()
        handle.object = PZHarness.Fixtures.objectWithSprite(getSquare(handle.x, handle.y, handle.z), tile)
        return handle.object ~= nil and Digester.summaryOf(handle.object) ~= nil
    end, "this client's copy of the " .. tile .. " digester")
    T.give(self, label, { { type = FEED, count = 1 } })
    T.step(function()
        local object, p = handle.object, T.player()
        if not object then return end
        local config = object:getSpriteConfig()
        -- Where the menu's Status walks them: the window closes once they are out of reach.
        T.standNextTo(getSquare(handle.x, handle.y, handle.z))
        local window = DigesterWindow:openOn(0, object)
        window:prerender()
        self.views[label] = { rows = #(window.rowsToDraw or {}), configValid = config ~= nil and config:isValid(),
            master = object:getMasterObject() == object }
        window:close()
        ISTimedActionQueue.add(ISInventoryTransferAction:new(p, self.items[label][1], p:getInventory(), object:getContainer()))
    end)
    T.waitFor(self, function() return handle.object and handle.object:getContainer():getCountType(FEED) > held end,
        "this client's hopper holding the dung")
    T.readRecord(self, handle, label)
end

-- Expects useBarrelDigester's `label` to have found a whole barrel digester, its hopper holding the
-- `held` dung it held before and the one dragged in.
local function expectBarrelDigester(self, label, held)
    local view, read = self.views[label], self.reads[label]
    if not T.expect(view ~= nil and read ~= nil, label .. ": never saw the digester") then return end
    T.expect(view.rows > 0, label .. ": its status window shows nothing")
    T.expect(view.configValid and view.master, label .. ": its SpriteConfig refused its tile")
    T.expectEqual(label .. ": items in the hopper, with the dung dragged in", read.hopperItems, held + 1)
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
        useBarrelDigester(self, handle, self.tile, "fed", 0)
    end,
    validate = function(self)
        local built = self.reads.built or {}
        T.expectEqual("the built tier", built.tier, "barrel")
        T.expectEqual("the built tile", built.sprite, self.tile)
        expectBarrelDigester(self, "fed", 0)
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
            if name and luautils.stringStarts(name, "blends_natural") then
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
        T.expectEqual("the cursor taking natural ground", self.onGround, true)
        T.expectEqual("the cursor taking a building's floor", self.indoors, false)
    end,
})

-- A digester built from a barrel loads whole from the save: its chunk unloaded and loaded again, it
-- still opens and takes feed. While unloaded it kept eating from what its hopper held, by weight
-- as when loaded, and what it ate has left the hopper. Single player only, as the chunk reload
-- test.
test("renewable_energy_biogas_barrel_digester_reloads_whole", {
    spOnly = T.CHUNK_RELOAD_SP_ONLY,
    timeoutSeconds = T.CHUNK_RELOAD_SECONDS,
    instant = true,
    run = function(self)
        self.views = {}
        local tile = Sprites.digester.barrel.Mov_LightGreenBarrel
        local handle = T.buildRecord(self, "digester", "Base.RenewableEnergy_BarrelDigester", tile, { "Base.Mov_LightGreenBarrel" })
        if not handle then return end
        T.fillRecord(self, handle, { hopper = { { type = FEED, count = 4 } } })
        -- Half an hour takes the first pat, a kilogram; a day away takes two more, its 2 kg a day.
        T.runDigester(self, handle, 0.5, 25)
        T.reloadChunk(self, handle, function()
            T.ageRecord(self, handle, 24, "away")
        end)
        useBarrelDigester(self, handle, tile, "reloaded", 1)
    end,
    validate = function(self)
        local away = self.reads.away
        T.expect(not away.loaded, "the digester's tile stayed loaded")
        T.expectEqual("items eaten while unloaded", away.eaten, 2)
        T.expectEqual("items left in the unloaded hopper's snapshot", away.snapshot, 1)
        T.expectNear("potential in the tank", away.potential, 3 * COW_POTENTIAL, 0.001)
        expectBarrelDigester(self, "reloaded", 1)
    end,
})

-- What a working barrel holds survives the world saved and loaded again, which keeps only its saved
-- fields: its holder and its wear, the gas, the tank, the startup and the souring, the scrubber and
-- the compressor; loading shows them again, the holder's fill, the foam and the scrubber.
local SAVED_DIGESTER = {
    holder = "tarp", holderCondition = 60, gas = 0.4, potential = 3, temp = 17, fed = true, started = true,
    startupHours = 100, seedHours = 12, gasHours = 50, sludge = 30, acid = 4.5, sour = true, intakeKg = 0.05,
    madePerDay = 0.3, scrubber = true, scrubCO2 = 12, scrubWool = 7, scrubSponge = 3, compressor = true,
}

test("renewable_energy_biogas_digester_kept_through_save", {
    run = function(self)
        local handle = T.placeRecord(self, "digester", "barrel.MetalDrum")
        if not handle then return end
        T.saveAndLoad(self, handle, SAVED_DIGESTER, "saved")
    end,
    validate = function(self)
        T.expectKeptThroughSave(self, "saved", SAVED_DIGESTER)
    end,
})

-- Right-clicking a barrel digester shows its submenu through vanilla's menu builder: its status,
-- and its jobs, greyed out with the reason while the digester or the character can't do them; the
-- gas bag's jobs in a submenu of their own. The status window opens on it and shows its state.
test("renewable_energy_biogas_digester_menu", {
    run = function(self)
        self.digester = T.placeRecord(self, "digester", "barrel.MetalDrum")
    end,
    validate = function(self)
        local object = self.digester.object
        local function job(name, share)
            local label = getText("ContextMenu_RenewableEnergy_" .. name)
            return share and getText("ContextMenu_RenewableEnergy_WithShare", label, share) or label
        end
        local options = T.worldOptions(object, getText("IGUI_RenewableEnergy_Digester_barrel"), { status = job("Status"),
            sludge = job(DigesterJobs.TAKE_SLUDGE, "0%"), vent = job(DigesterJobs.VENT, "0%"), bag = job("GasBag"),
            upgrade = job(DigesterJobs.UPGRADE) })
        if T.expect(options ~= nil, "right-clicking a digester shows no digester submenu") then
            T.expect(options.status ~= nil, "no Status option")
            T.expect(options.sludge and options.sludge.notAvailable
                and T.tooltipOf(options.sludge):find(getText("Tooltip_RenewableEnergy_NoSludge"), 1, true),
                "Take Sludge isn't greyed out saying an empty digester has no sludge")
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
        local window = DigesterWindow:openOn(0, object)
        window:prerender()
        T.expect(window.rowsToDraw and #window.rowsToDraw > 0, "the status window shows nothing of the digester")
        window:close()
    end,
})
