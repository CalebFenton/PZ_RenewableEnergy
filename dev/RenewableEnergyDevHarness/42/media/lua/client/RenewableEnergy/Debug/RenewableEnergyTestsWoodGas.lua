require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"

-- Wood gas: the gasifier, built from the build menu, burning wood for the generator it is piped to
-- or idling, leaving ash, tar and condensate, and the jobs at it (WoodGas/Gasifier.lua,
-- WoodGas/GasifierJobs.lua, WoodGas/GasifierObject.lua, WoodGas/GasifierSystem.lua,
-- UI/GasifierMenu.lua), and the sprays its wood vinegar makes.

local T = RenewableEnergyTest
local test = T.test

local GasKit, Materials, Sprites = RenewableEnergy.GasKit, RenewableEnergy.Materials, RenewableEnergy.Sprites
local Gasifier, GasifierJobs = RenewableEnergy.Gasifier, RenewableEnergy.GasifierJobs

-- An empty-tanked generator and a gasifier of `tier` beside it, or nil.
local function gasifierBeside(self, tier)
    local generator = T.generator(self, { fuel = 0 })
    if not generator then return nil end
    local square = T.need(self, T.squareBeside(generator.square), "a free square beside the generator")
    local gasifier = square and T.placeRecord(self, "gasifier", tier, { square = square })
    return gasifier and generator, gasifier
end

-- Queues lighting the gasifier once this client sees wood in it, with what that takes then given
-- first.
local function light(self, gasifier)
    T.waitForSummary(self, gasifier, function(summary) return summary.hopperKg > 0 end, "this client's summary of the gasifier's wood")
    T.step(function()
        T.giveMaterials(self, "light", GasifierJobs.materials(GasifierJobs.LIGHT, T.recordSummary(gasifier)))
    end)
    T.gasJob(self, "gasifier", gasifier, GasifierJobs.LIGHT)
end

local function stalled(read)
    return not read.running and read.state ~= nil and read.state.stalled
end

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
-- KG_PER_LITRE of wood for each litre vanilla bills the generator and none of its own idle burn
-- meanwhile. Out of wood, the generator stops.
test("renewable_energy_woodgas_gasifier_runs_generator", {
    instant = true,
    -- Vanilla's idle bill follows this option; high, the idle burn the gasifier must skip shows.
    sandbox = { GeneratorFuelConsumption = 1 },
    run = function(self)
        local generator, gasifier = gasifierBeside(self, "standard")
        if not gasifier then return end
        self.generatorSide = Gasifier.sideOf(gasifier.x, gasifier.y, generator.x, generator.y)
        self.gasifierSide = Gasifier.sideOf(generator.x, generator.y, gasifier.x, gasifier.y)
        self.litres, self.hours = GasKit.PHANTOM_FUEL / 4, 10
        T.fillRecord(self, gasifier, { hopper = { { type = "Base.Plank", count = 6 } }, filter = { { type = "Base.HayTuft" } } })
        -- Lit first, so gas reaches the generator the moment the line is in.
        light(self, gasifier)
        T.fitAndConnect(self, generator, gasifier)
        T.batch(function()
            T.readRecord(self, gasifier, "lit")
            T.readGenerator(self, generator, "connected")
            T.setGenerator(self, generator, { running = true })
            T.burnFuel(self, generator, self.litres)
            T.gasPass(self, generator, 0.1)
            T.ageRecord(self, gasifier, self.hours, "fed")
            T.readGenerator(self, generator, "running")
            -- More than the hopper and the firebox hold.
            T.server(self, "gasifierBurn", T.recordArgs(gasifier, { kg = 2 * Gasifier.TIERS.standard.hopperKg }))
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
        local kg = self.litres * Gasifier.KG_PER_LITRE
        local idleKg = connected.idle * Gasifier.KG_PER_LITRE * self.hours
        local tolerance = 0.05
        T.expect(idleKg > 2 * tolerance, "an idle burn of " .. idleKg .. " kg is too small to tell from the bill")
        local burned = (lit.hopperKg + lit.fireKg) - (fed.hopperKg + fed.fireKg)
        T.expectNear("wood burned for " .. self.litres .. " L of fuel and " .. self.hours .. " hours feeding it", burned, kg, tolerance)
        T.expectNear("ash after that wood", fed.ash - lit.ash, burned * Gasifier.TIERS.standard.ashPerKg, 0.01)
        T.expect(not out.running and out.state ~= nil and out.state.outOfGas, "out of wood, the generator kept running")
    end,
})

-- A full ash pit, or a filter with no clean packing left, cuts what the generator carries to
-- DIRTY_OUTPUT of the line's cap: a watt over stalls it, exactly that runs it, and a pit one short
-- of full doesn't stall it.
test("renewable_energy_woodgas_full_ash_or_spent_filter_cuts_output", {
    instant = true,
    run = function(self)
        local generator, gasifier = gasifierBeside(self, "standard")
        if not gasifier then return end
        self.dirtyCap = GasKit.CAP_W * Gasifier.DIRTY_OUTPUT
        T.fillRecord(self, gasifier, { hopper = { { type = "Base.Plank", count = 6 } }, filter = { { type = "Base.HayTuft" } } })
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
            T.server(self, "gasifierBurn", T.recordArgs(gasifier, { kg = 1.5 * Gasifier.TIERS.standard.tarKgPerItem }))
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
        T.expect(stalled(reads.ashFull), "a full ash pit didn't stall a generator at " .. over)
        T.expect(reads.ashCleared.running, "the generator didn't start again once the ash was cleared")
        T.expect(reads.spent.clean == 0, "the filter still has " .. tostring(reads.spent.clean) .. " clean packing")
        T.expect(stalled(reads.filterSpent), "a spent filter didn't stall a generator at " .. over)
        T.expect(reads.dirtyRuns.running, "a spent filter didn't run a generator at " .. self.dirtyCap .. " W")
    end,
})

-- A lit gasifier whose generator isn't running burns, in its own pass, the wood for what vanilla
-- bills an idling generator (IsoGenerator.getBasePowerConsumption, which follows the
-- GeneratorFuelConsumption option, set high so the hours show), and goes out once its wood is gone.
test("renewable_energy_woodgas_gasifier_idles_as_a_generator", {
    instant = true,
    sandbox = { GeneratorFuelConsumption = 1 },
    run = function(self)
        local generator = T.generator(self, {})
        local idling = generator and T.placeRecord(self, "gasifier", "standard")
        local burning = idling and T.placeRecord(self, "gasifier", "standard")
        if not burning then return end
        self.hours = 10
        T.batch(function()
            T.readGenerator(self, generator, "vanilla")
            T.fillRecord(self, idling, { hopper = { { type = "Base.Plank", count = 6 } } })
            T.setRecord(self, idling, { lit = true })
            T.readRecord(self, idling, "lit")
            T.ageRecord(self, idling, self.hours, "idled")
        end)
        T.step(function()
            -- Half what the idle burn takes in those hours, with nothing in the hopper.
            self.fireKg = self.reads.vanilla.idle * Gasifier.KG_PER_LITRE * self.hours / 2
            T.batch(function()
                T.setRecord(self, burning, { lit = true, fireKg = self.fireKg })
                T.ageRecord(self, burning, self.hours, "burnedDown")
            end)
        end)
    end,
    validate = function(self)
        local reads = self.reads
        local lit, idled = reads.lit, reads.idled
        local kg = reads.vanilla.idle * Gasifier.KG_PER_LITRE * self.hours
        T.expectNear("wood burned idling " .. self.hours .. " hours", (lit.hopperKg + lit.fireKg) - (idled.hopperKg + idled.fireKg), kg, 0.01)
        T.expect(idled.lit, "the gasifier went out with wood in its hopper")
        T.expect(not reads.burnedDown.lit, "the gasifier stayed lit with its wood gone")
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
                T.server(self, "gasifierBurn", T.recordArgs(gasifier, { kg = self.kg }))
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
            T.server(self, "carried", { fluids = { Gasifier.VINEGAR } })
        end)
    end,
    validate = function(self)
        T.expect(self.bottleHot == "Tooltip_RenewableEnergy_WontTakeCondensate", "a plastic bottle takes the condensate hot: " .. tostring(self.bottleHot))
        T.expect(self.potHot == nil, "a pot won't take the condensate hot: " .. tostring(self.potHot))
        T.expect(self.coldBottle, "a plastic bottle won't take it cold")
        local poured = math.min(self.condensate, instanceItem("Base.Pot"):getFluidContainer():getCapacity())
        T.expectNear("wood vinegar carried", self.server.carried.fluids[Gasifier.VINEGAR], poured, 0.01)
        T.expectNear("condensate left", self.reads.drained.condensate, self.condensate - poured, 0.01)
    end,
})

-- Wood vinegar cut with water makes the game's own mildew and aphid sprays.
for recipe, spray in pairs({ MildewSpray = "Base.GardeningSprayMilk", AphidSpray = "Base.GardeningSprayAphids" }) do
    T.craftTest("renewable_energy_woodgas_vinegar_" .. T.snake(recipe), {
        recipe = "RenewableEnergy_MakeVinegar" .. recipe,
        from = "Base.GardeningSprayEmpty",
        -- The fluid inputs' containers, in order, full of vinegar and water.
        setup = function(self)
            local fluids = { Gasifier.VINEGAR, "Water" }
            local index = 1
            for _, item in ipairs(self.items.inputs or {}) do
                local container = item:getFluidContainer()
                if container and fluids[index] then
                    T.server(self, "refillFluid", { id = item:getID(), fluid = fluids[index], liters = container:getCapacity() })
                    index = index + 1
                end
            end
        end,
        counts = { [spray] = 1, ["Base.GardeningSprayEmpty"] = 0 },
    })
end
