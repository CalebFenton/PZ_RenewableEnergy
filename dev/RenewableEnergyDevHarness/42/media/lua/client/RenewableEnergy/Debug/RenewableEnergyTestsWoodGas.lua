require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"

-- Wood gas: the gasifier, built from the build menu, burning wood for the generator it is piped to
-- or idling, leaving ash, tar and condensate, and the jobs at it (WoodGas/Gasifier.lua,
-- WoodGas/GasifierJobs.lua, WoodGas/GasifierObject.lua, WoodGas/GasifierSystem.lua,
-- UI/GasifierMenu.lua).

local T = RenewableEnergyTest
local test = T.test

local GasKit, Materials, Sprites = RenewableEnergy.GasKit, RenewableEnergy.Materials, RenewableEnergy.Sprites
local Gasifier, GasifierJobs = RenewableEnergy.Gasifier, RenewableEnergy.GasifierJobs

-- A hopper load of wood, and a filter of clean packing.
local WOOD = { { type = "Base.Plank", count = 6 } }
local PACKING = { { type = "Base.HayTuft" } }

-- Building ----------------------------------------------------------------------------------------

-- The build menu's own path builds a gasifier of `tier` from its entity's recipe, taking its
-- materials and keeping its tools, with its hopper and its filter.
local function buildsGasifier(tier, entity, prefer)
    return {
        instant = true,
        run = function(self)
            T.buildRecord(self, "gasifier", entity, Sprites.gasifier[tier], prefer)
        end,
        validate = function(self)
            local built = self.reads.built or {}
            T.expect(built.tier == tier, "the build menu built " .. tostring(built.tier))
            T.expect(built.containers == 2, "the gasifier has " .. tostring(built.containers) .. " containers, not a hopper and a filter")
            T.expectBuilt(self, Sprites.gasifier[tier])
        end,
    }
end

test("renewable_energy_woodgas_build_primitive_gasifier", buildsGasifier("primitive", "Base.RenewableEnergy_PrimitiveGasifier",
    { "Base.Strainer" }))
test("renewable_energy_woodgas_build_standard_gasifier", buildsGasifier("standard", "Base.RenewableEnergy_Gasifier"))
test("renewable_energy_woodgas_build_advanced_gasifier", buildsGasifier("advanced", "Base.RenewableEnergy_AdvancedGasifier"))

-- Feeding a generator -----------------------------------------------------------------------------

-- Lit and piped to a kitted generator beside it, a gasifier runs it with an empty tank, burning
-- KG_PER_LITRE of wood for each litre vanilla bills the generator as the hours pass and none of its
-- own idle burn meanwhile. Out of wood, the generator stops.
test("renewable_energy_woodgas_gasifier_runs_generator", {
    hour = 12,
    instant = true,
    -- Vanilla's bills follow this option; high, both an hour's bill and the idle burn the gasifier
    -- must skip come to well over the wood the check lets pass.
    sandbox = { GeneratorFuelConsumption = 10 },
    run = function(self)
        local generator, gasifier = T.gasifierBeside(self, "standard")
        if not gasifier then return end
        self.generatorSide = Gasifier.sideOf(gasifier.x, gasifier.y, generator.x, generator.y)
        self.gasifierSide = Gasifier.sideOf(generator.x, generator.y, gasifier.x, gasifier.y)
        self.hours = 10
        T.fillRecord(self, gasifier, { hopper = WOOD, filter = PACKING })
        -- Lit first, so gas reaches the generator the moment the line is in.
        T.lightGasifier(self, gasifier)
        T.fitAndConnect(self, generator, gasifier)
        T.batch(function()
            T.readRecord(self, gasifier, "lit")
            T.readGenerator(self, generator, "connected")
            T.setGenerator(self, generator, { running = true })
        end)
        T.readBill(self, generator, gasifier, "before")
        T.jumpClock(self, 1)
        T.waitForBill(self, generator, "before")
        T.readBill(self, generator, gasifier, "billed")
        T.batch(function()
            T.ageRecord(self, gasifier, self.hours, "fed")
            T.readGenerator(self, generator, "running")
            -- More than the hopper and the firebox hold.
            T.burnGasifier(self, gasifier, 2 * Gasifier.TIERS.standard.hopperKg)
            T.gasPass(self, generator, 0.1)
            T.readGenerator(self, generator, "out")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        local lit, fed, connected, running, out = reads.lit, reads.fed, reads.connected, reads.running, reads.out
        T.expect(lit.lit and lit.fireKg > 0, "lighting it didn't start a fire from the hopper")
        T.expect(T.hasOverlay(lit, Sprites.gasifierLit.standard), "the lit gasifier shows no fire")
        T.expect(connected.state and connected.state.sourceKind == "gasifier", "the line doesn't lead to the gasifier")
        T.expect(T.hasOverlay(fed, Sprites.gasifierPipe[self.generatorSide]), "the gasifier shows no pipe toward the generator")
        T.expect(T.hasOverlay(connected, Sprites.gasifierPipeGenFor(connected.sprite, self.gasifierSide)),
            "the generator shows no pipe toward the gasifier")
        T.expect(running.running and running.fuel >= GasKit.PHANTOM_FUEL and running.state ~= nil and running.state.tank == 0,
            "the generator didn't run on wood gas with an empty tank")
        local litres, hours = T.vanillaBill(self, "before", "billed")
        T.expect(hours >= 1, "the clock moved on " .. hours .. " whole hours, not one")
        local kg = litres * Gasifier.KG_PER_LITRE
        local idleKg = connected.idle * Gasifier.KG_PER_LITRE * self.hours
        local tolerance = 0.05
        T.expect(idleKg > 2 * tolerance, "an idle burn of " .. idleKg .. " kg is too small to tell from the bill")
        local before = reads.beforeSource
        local burned = (before.hopperKg + before.fireKg) - (fed.hopperKg + fed.fireKg)
        T.expectNear("wood burned for vanilla's bill of " .. litres .. " L and " .. self.hours .. " hours feeding it",
            burned, kg, tolerance)
        T.expectNear("ash after that wood", fed.ash - before.ash, burned * Gasifier.TIERS.standard.ashPerKg, 0.01)
        T.expect(not out.running and out.state ~= nil and out.state.outOfGas, "out of wood, the generator kept running")
    end,
})

-- A full ash pit, or a filter with no clean packing left, cuts what the generator carries to
-- DIRTY_OUTPUT of the line's cap: a watt over stalls it, exactly that runs it, and a pit one short
-- of full doesn't stall it. The loads are made up (gasLoad): no set of appliances adds up to exactly
-- the cap; renewable_energy_gasline_generator_stalls_on_real_load measures a real one.
test("renewable_energy_woodgas_full_ash_or_spent_filter_cuts_output", {
    instant = true,
    run = function(self)
        local generator, gasifier = T.gasifierBeside(self, "standard")
        if not gasifier then return end
        self.dirtyCap = GasKit.CAP_W * Gasifier.DIRTY_OUTPUT
        T.fillRecord(self, gasifier, { hopper = WOOD, filter = PACKING })
        T.setRecord(self, gasifier, { lit = true })
        T.fitAndConnect(self, generator, gasifier)
        T.batch(function()
            T.setGenerator(self, generator, { running = true })
            T.gasLoad(self, self.dirtyCap + 1)
            for _, case in ipairs({ { "ashNearlyFull", Gasifier.ASH_FULL - 1 }, { "ashFull", Gasifier.ASH_FULL }, { "ashCleared", 0 } }) do
                T.setRecord(self, gasifier, { ash = case[2] })
                T.gasPass(self, generator, 0.1)
                T.readGenerator(self, generator, case[1])
            end
            -- More than one packing item's worth of wood tars the filter's only tuft; its ash is
            -- cleared so only the filter counts.
            T.burnGasifier(self, gasifier, 1.5 * Gasifier.TIERS.standard.tarKgPerItem)
            T.setRecord(self, gasifier, { ash = 0 })
            T.readRecord(self, gasifier, "spent")
            T.gasPass(self, generator, 0.1)
            T.readGenerator(self, generator, "filterSpent")
            T.gasLoad(self, self.dirtyCap)
            T.gasPass(self, generator, 0.1)
            T.readGenerator(self, generator, "dirtyRuns")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        local over = (self.dirtyCap + 1) .. " W"
        T.expect(reads.ashNearlyFull.running, "an ash pit one short of full stalled a generator at " .. over)
        T.expect(T.isStalled(reads.ashFull), "a full ash pit didn't stall a generator at " .. over)
        T.expect(reads.ashCleared.running, "the generator didn't start again once the ash was cleared")
        T.expect(reads.spent.clean == 0, "the filter still has " .. tostring(reads.spent.clean) .. " clean packing")
        T.expect(T.isStalled(reads.filterSpent), "a spent filter didn't stall a generator at " .. over)
        T.expect(reads.dirtyRuns.running, "a spent filter didn't run a generator at " .. self.dirtyCap .. " W")
    end,
})

-- A lit gasifier whose generator isn't running on its gas burns, in its own pass, the wood for what
-- vanilla bills an idling generator (IsoGenerator.getBasePowerConsumption, which follows the
-- GeneratorFuelConsumption option, set high so the hours show): piped to a generator switched off,
-- and to one stalled on its line. It goes out once its wood is gone.
test("renewable_energy_woodgas_gasifier_idles_as_a_generator", {
    instant = true,
    sandbox = { GeneratorFuelConsumption = 1 },
    run = function(self)
        local generator, idling = T.gasifierBeside(self, "standard")
        local burning = idling and T.placeRecord(self, "gasifier", "standard")
        if not burning then return end
        self.hours = 10
        T.fillRecord(self, idling, { hopper = WOOD })
        T.setRecord(self, idling, { lit = true })
        T.fitAndConnect(self, generator, idling)
        T.batch(function()
            T.readGenerator(self, generator, "off")
            T.readRecord(self, idling, "lit")
            T.ageRecord(self, idling, self.hours, "idledOff")
            T.setGenerator(self, generator, { running = true })
            T.stallLine(self, generator, "stalled")
            T.ageRecord(self, idling, self.hours, "idledStalled")
        end)
        T.step(function()
            -- Half what the idle burn takes in those hours, with nothing in the hopper.
            self.fireKg = self.reads.off.idle * Gasifier.KG_PER_LITRE * self.hours / 2
            T.batch(function()
                T.setRecord(self, burning, { lit = true, fireKg = self.fireKg })
                T.ageRecord(self, burning, self.hours, "burnedDown")
            end)
        end)
    end,
    validate = function(self)
        local reads = self.reads
        local lit, idledOff, idledStalled = reads.lit, reads.idledOff, reads.idledStalled
        local function wood(read)
            return read.hopperKg + read.fireKg
        end
        local kg = reads.off.idle * Gasifier.KG_PER_LITRE * self.hours
        T.expect(not reads.off.running and reads.off.state ~= nil and reads.off.state.connected,
            "the gasifier's generator isn't connected and switched off")
        T.expectNear("wood burned idling " .. self.hours .. " hours piped to a generator switched off", wood(lit) - wood(idledOff), kg, 0.01)
        T.expect(T.isStalled(reads.stalled), "a load past the line's cap didn't stall the generator")
        T.expectNear("wood burned idling " .. self.hours .. " hours piped to a stalled generator",
            wood(idledOff) - wood(idledStalled), kg, 0.01)
        T.expect(idledStalled.lit, "the gasifier went out with wood in its hopper")
        T.expect(not reads.burnedDown.lit, "the gasifier stayed lit with its wood gone")
    end,
})

-- Gas through a filter with no clean packing wears the generator it runs beyond vanilla's own wear:
-- each hour, a chance of its wear factor less one times vanilla's chance, which the generator's
-- item script gives (ConditionLowerChanceOneIn, IsoGenerator.update). The rolls are set either side
-- of that chance; clean gas wears nothing extra even on a roll every chance takes.
test("renewable_energy_woodgas_dirty_gas_wears_generator", {
    instant = true,
    run = function(self)
        self.hours = 10
        -- Vanilla's chance, set so the dirty one lies well inside 0 to 1.
        local oneIn = 2 * Gasifier.WEAR_DIRTY
        self.chance = (Gasifier.WEAR_DIRTY - 1) / oneIn
        local dirtyGenerator, dirty = T.gasifierBeside(self, "standard")
        if not dirty then return end
        local cleanGenerator, clean = T.gasifierBeside(self, "standard")
        if not clean then return end
        local lines = { { name = "dirty", generator = dirtyGenerator, gasifier = dirty, filter = {} },
            { name = "clean", generator = cleanGenerator, gasifier = clean, filter = PACKING } }
        for _, line in ipairs(lines) do
            T.fillRecord(self, line.gasifier, { hopper = WOOD, filter = line.filter })
            T.setRecord(self, line.gasifier, { lit = true })
            T.fitAndConnect(self, line.generator, line.gasifier)
        end
        T.server(self, "generatorWearChance", T.at(dirtyGenerator, { oneIn = oneIn }))
        local passes = { { "dirtyHit", dirtyGenerator, self.chance - 0.01 }, { "dirtyMiss", dirtyGenerator, self.chance + 0.01 },
            { "clean", cleanGenerator, 0 } }
        T.batch(function()
            for _, line in ipairs(lines) do
                T.setGenerator(self, line.generator, { running = true })
                T.readRecord(self, line.gasifier, line.name .. "Gasifier")
            end
            for _, pass in ipairs(passes) do
                local label, generator, roll = pass[1], pass[2], pass[3]
                T.forceRoll(self, roll)
                T.readGenerator(self, generator, label .. "Before")
                T.gasPass(self, generator, self.hours)
                T.readGenerator(self, generator, label .. "After")
            end
        end)
    end,
    validate = function(self)
        local reads = self.reads
        local dirtyWear, cleanWear = reads.dirtyGasifier.summary.wear, reads.cleanGasifier.summary.wear
        T.expect(dirtyWear == Gasifier.WEAR_DIRTY and cleanWear == 1,
            "the gasifiers' wear factors are " .. tostring(dirtyWear) .. " and " .. tostring(cleanWear))
        local function lost(label)
            T.expect(reads[label .. "After"].running, "the generator of the " .. label .. " pass stalled or stopped")
            return reads[label .. "Before"].condition - reads[label .. "After"].condition
        end
        -- Each hour that wears takes one or two condition (IsoGenerator.update).
        local hit, miss, clean = lost("dirtyHit"), lost("dirtyMiss"), lost("clean")
        T.expect(hit >= self.hours and hit <= 2 * self.hours, "dirty gas rolling under its chance of " .. self.chance
            .. " wore the generator " .. hit .. " condition over " .. self.hours .. " hours")
        T.expect(miss == 0, "dirty gas rolling over its chance of " .. self.chance .. " wore the generator " .. miss .. " condition")
        T.expect(clean == 0, "clean gas wore the generator " .. clean .. " condition beyond vanilla's own wear")
    end,
})

-- Lighting ----------------------------------------------------------------------------------------

-- A cold gasifier takes bellows to light; one just put out doesn't, nor one out a little less than
-- COLD_HOURS, while one out a little longer is cold again.
test("renewable_energy_woodgas_cold_gasifier_needs_bellows", {
    instant = true,
    run = function(self)
        local gasifier = T.placeRecord(self, "gasifier", "primitive")
        if not gasifier then return end
        T.fillRecord(self, gasifier, { hopper = { { type = "Base.Plank", count = 2 } } })
        T.give(self, "matches", { { type = Materials.FIRE_STARTER.item } })
        T.waitForSummary(self, gasifier, function(summary) return summary.hopperKg > 0 end, "this client's summary of the gasifier's wood")
        T.step(function()
            self.coldNeed = RenewableEnergy.firstUnmet(GasifierJobs.needs(T.player(), GasifierJobs.LIGHT, T.recordSummary(gasifier)))
        end)
        T.give(self, "bellows", { { type = Gasifier.BELLOWS[1] } })
        T.gasJob(self, "gasifier", gasifier, GasifierJobs.LIGHT)
        T.gasJob(self, "gasifier", gasifier, GasifierJobs.PUT_OUT)
        T.server(self, "takeItems", { type = Gasifier.BELLOWS[1] })
        T.waitForSummary(self, gasifier, function(summary) return not summary.lit end, "this client's summary of the gasifier put out")
        T.waitFor(self, function() return not T.player():getInventory():containsTypeRecurse(Gasifier.BELLOWS[1]) end,
            "this client's copy of the bellows gone")
        T.step(function()
            self.outAt = T.recordSummary(gasifier).outSince
            self.refusals = { justOut = GasifierJobs.refusal(T.player(), GasifierJobs.LIGHT, gasifier.object) }
        end)
        local step = Gasifier.COLD_HOURS / 20
        for _, case in ipairs({ { "warm", Gasifier.COLD_HOURS - step }, { "cold", Gasifier.COLD_HOURS + step } }) do
            T.setRecord(self, gasifier, nil, { outSince = case[2] })
            -- Each case puts outSince further back than the one before, by more than `step`.
            T.waitForSummary(self, gasifier, function(summary) return summary.outSince < self.outAt - step end,
                "this client's summary of the gasifier out " .. case[2] .. " hours")
            T.step(function()
                self.refusals[case[1]] = GasifierJobs.refusal(T.player(), GasifierJobs.LIGHT, gasifier.object)
                self.outAt = T.recordSummary(gasifier).outSince
            end)
        end
    end,
    validate = function(self)
        T.expect(self.coldNeed and self.coldNeed.item == Gasifier.BELLOWS[1], "a cold gasifier lit without bellows: "
            .. tostring(self.coldNeed and self.coldNeed.item))
        T.expect(self.refusals.justOut == nil, "just put out, it still wants something to light: " .. tostring(self.refusals.justOut))
        T.expect(self.refusals.warm == nil, "out a little less than it stays warm, it wants something to light: " .. tostring(self.refusals.warm))
        T.expect(self.refusals.cold == "short", "out a little longer than it stays warm, it lit without bellows: " .. tostring(self.refusals.cold))
    end,
})

-- Ash, tar and condensate ---------------------------------------------------------------------------

-- Burning fills the ash pit by the tier's ashPerKg and tars one packing item for each tarKgPerItem
-- burned, leaving the rest clean.
test("renewable_energy_woodgas_burning_fills_ash_and_tars_packing", {
    instant = true,
    run = function(self)
        local gasifier = T.placeRecord(self, "gasifier", "standard")
        if not gasifier then return end
        self.spec, self.packing, self.tarred = Gasifier.TIERS.standard, 3, 2
        -- Half an item's worth past `tarred`, burned half an item at a time with the drain emptied
        -- first, so an undrained filter's faster tar stays out of it.
        self.burns, self.kg = 2 * self.tarred + 1, self.spec.tarKgPerItem / 2
        T.batch(function()
            T.fillRecord(self, gasifier, { hopper = { { type = "Base.Plank", count = 7 } },
                filter = { { type = "Base.HayTuft", count = self.packing } } })
            T.setRecord(self, gasifier, { lit = true })
            for _ = 1, self.burns do
                T.setRecord(self, gasifier, { condensate = 0 })
                T.burnGasifier(self, gasifier, self.kg)
            end
            T.readRecord(self, gasifier, "burned")
        end)
    end,
    validate = function(self)
        local burned, kg = self.reads.burned, self.burns * self.kg
        T.expectNear("ash after burning " .. kg .. " kg", burned.ash, math.min(Gasifier.ASH_FULL, kg * self.spec.ashPerKg), 0.05)
        T.expect(burned.tarry == self.tarred and burned.clean == self.packing - self.tarred, "packing after burning " .. kg .. " kg: "
            .. tostring(burned.clean) .. " clean, " .. tostring(burned.tarry) .. " tarry")
    end,
})

-- Clean Out Ash with a shovel gives a Wood Ash for each ASH_PER_ITEM in the pit and leaves the rest;
-- it refuses one short of an item's worth, not exactly one.
test("renewable_energy_woodgas_clean_out_ash", {
    instant = true,
    run = function(self)
        local gasifier = T.placeRecord(self, "gasifier", "standard")
        if not gasifier then return end
        self.whole = 2
        self.ash = (self.whole + 0.5) * Gasifier.ASH_PER_ITEM
        T.setRecord(self, gasifier, { ash = self.ash })
        T.giveMaterials(self, "shovel", GasifierJobs.materials(GasifierJobs.CLEAN_ASH))
        T.waitForSummary(self, gasifier, function(summary) return summary.ash == math.floor(self.ash) end,
            "this client's summary of the ash pit")
        T.gasJob(self, "gasifier", gasifier, GasifierJobs.CLEAN_ASH)
        T.batch(function()
            T.readRecord(self, gasifier, "cleaned")
            T.count(self, "ash", { Gasifier.WOOD_ASH })
        end)
        self.refusals = {}
        for _, case in ipairs({ { "short", Gasifier.ASH_PER_ITEM - 1 }, { "enough", Gasifier.ASH_PER_ITEM } }) do
            T.setRecord(self, gasifier, { ash = case[2] })
            T.waitForSummary(self, gasifier, function(summary) return summary.ash == case[2] end, "this client's summary of the ash pit")
            T.step(function() self.refusals[case[1]] = GasifierJobs.refusal(T.player(), GasifierJobs.CLEAN_ASH, gasifier.object) end)
        end
    end,
    validate = function(self)
        T.expectNear("ash after cleaning out", self.reads.cleaned.ash, self.ash - self.whole * Gasifier.ASH_PER_ITEM, 0.01)
        T.expect(self.counts.ash[Gasifier.WOOD_ASH] == self.whole,
            "cleaning out gave " .. tostring(self.counts.ash[Gasifier.WOOD_ASH]) .. " wood ash, not " .. self.whole)
        T.expect(self.refusals.short == "Tooltip_RenewableEnergy_LittleAsh", "Clean Out Ash one short of an item: " .. tostring(self.refusals.short))
        T.expect(self.refusals.enough == nil, "Clean Out Ash with an item's worth: " .. tostring(self.refusals.enough))
    end,
})

-- Condensate drained hot goes only into metal, glass or cookware; a pot takes what it holds.
test("renewable_energy_woodgas_drain_condensate", {
    instant = true,
    run = function(self)
        local gasifier = T.placeRecord(self, "gasifier", "primitive")
        if not gasifier then return end
        self.condensate = Gasifier.CONDENSATE_MAX
        T.batch(function()
            T.setRecord(self, gasifier, { lit = true, fireKg = Gasifier.TIERS.primitive.hopperKg, condensate = self.condensate })
            T.give(self, "containers", { { type = "Base.WaterBottle" }, { type = "Base.Pot" } })
            T.server(self, "refillFluid", { type = "Base.WaterBottle" })
            T.server(self, "refillFluid", { type = "Base.Pot" })
        end)
        T.waitForSummary(self, gasifier, function(summary) return summary.condensate >= self.condensate end, "this client's summary of the condensate")
        T.waitFor(self, function() return self.items.containers[1]:getFluidContainer():isEmpty() end, "this client's copy of the emptied bottle")
        T.step(function()
            local bottle, pot = self.items.containers[1], self.items.containers[2]
            self.bottleHot = GasifierJobs.refusal(T.player(), GasifierJobs.DRAIN, gasifier.object, bottle)
            self.potHot = GasifierJobs.refusal(T.player(), GasifierJobs.DRAIN, gasifier.object, pot)
            self.coldBottle = Gasifier.takesCondensate(bottle, false)
        end)
        T.gasJob(self, "gasifier", gasifier, GasifierJobs.DRAIN, function() return self.items.containers[2] end)
        T.batch(function()
            T.readRecord(self, gasifier, "drained")
            T.readCarried(self, {}, { Gasifier.VINEGAR })
        end)
    end,
    validate = function(self)
        T.expect(self.bottleHot == "Tooltip_RenewableEnergy_WontTakeCondensate", "a plastic bottle takes the condensate hot: " .. tostring(self.bottleHot))
        T.expect(self.potHot == nil, "a pot won't take the condensate hot: " .. tostring(self.potHot))
        T.expect(self.coldBottle, "a plastic bottle won't take it cold")
        local poured = math.min(self.condensate, instanceItem("Base.Pot"):getFluidContainer():getCapacity())
        T.expectNear("wood vinegar carried", self.server.carried and self.server.carried.fluids[Gasifier.VINEGAR], poured, 0.01)
        T.expectNear("condensate left", self.reads.drained.condensate, self.condensate - poured, 0.01)
    end,
})
