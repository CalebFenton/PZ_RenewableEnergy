require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"
require "RenewableEnergy/Debug/RenewableEnergyTestLibCraft"
local Fixtures = require "RenewableEnergy/Debug/RenewableEnergyFixtures"
local Squares = require "cf_commonlib/Squares"
local Digester = require "RenewableEnergy/Biogas/Digester"
local DigesterJobs = require "RenewableEnergy/Biogas/DigesterJobs"
local GasHeater = require "RenewableEnergy/Biogas/GasHeater"
local Sprites = require "RenewableEnergy/Sprites"

-- What the digester's gas is used for (Contents/.../RenewableEnergy/Biogas/*, the propane bottle
-- refill in Recipes.lua): the gas heater, the tire pump, the compressor and propane.

local T = RenewableEnergyTest
local test = T.test


T.serverCheck("renewable_energy_biogas_water_in_nested_bags", "baggedWaterMaterials")

-- Heater -----------------------------------------------------------------------------------------

-- The sprite this client shows of the gas heater on `square`, or nil.
local function heaterSprite(square)
    local heater = Squares.findObjectOn(square, GasHeater.isHeater)
    return heater and heater:getSprite():getName()
end

-- A barrel digester with full bags and an unlit gas heater facing `facing` (S if nil) beside it,
-- with what lighting takes given: the digester's handle, the heater's and the heater's square, or
-- nil.
local function fedDigesterAndHeater(self, facing)
    local digester = T.placeRecord(self, "digester", "barrel.MetalDrum")
    local square = digester and T.square(self, { near = digester.square }, "a square beside the digester for a heater")
    if not square then return nil end
    local fed = Fixtures.matureDigester("barrel", { gas = Digester.HOLDERS.bags.capacity })
    T.setRecord(self, digester, fed)
    T.waitForGas(self, digester, fed.gas)
    local heater = T.placeTile(self, square, Sprites.gasHeater.off[facing or "S"])
    T.giveMaterials(self, "light", GasHeater.materials(T.player(), GasHeater.LIGHT))
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
        local cold = Fixtures.matureDigester("barrel", { temp = self.temp, gas = self.gas })
        for _, handle in ipairs(self.digesters) do
            T.setRecord(self, handle, cold)
            T.waitForGas(self, handle, self.gas)
        end
        local heater = T.placeTile(self, square, Sprites.gasHeater.off.S)
        T.giveMaterials(self, "light", GasHeater.materials(T.player(), GasHeater.LIGHT))
        T.actionJob(self, "heater", heater, GasHeater.LIGHT)
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
        local aged, agedOther = reads["aged" .. warmed], reads["aged" .. other]
        T.expect(aged.heaterLit and not agedOther.heaterLit, "the digesters' own passes didn't find the heater its tile shows lit")
        T.expect(aged.temp > warming.temp, "the heated digester's own pass took it from " .. warming.temp .. " to " .. aged.temp .. " °C")
        -- The other closes on its square's air without passing it.
        local from, to, air = idle.temp, agedOther.temp, agedOther.air
        T.expect((to - from) * (air - from) > 0 and math.abs(to - from) <= math.abs(air - from),
            "the other digester's own pass took it from " .. from .. " to " .. to .. " °C in air at " .. air .. " °C")
    end,
})

-- A lit gas heater goes out, on this client too, when the digester it burns from is taken away;
-- turned to face W, it stays facing W as it lights and goes out.
test("renewable_energy_biogas_heater_out_when_digester_gone", {
    instant = true,
    run = function(self)
        local digester, heater, square = fedDigesterAndHeater(self, "W")
        if not digester then return end
        T.actionJob(self, "heater", heater, GasHeater.LIGHT)
        T.waitFor(self, function() return heaterSprite(square) == Sprites.gasHeater.lit.W end, "this client's copy of the heater lit")
        T.server(self, "removeAt", T.at(digester, { kind = digester.kind }))
        T.waitFor(self, function() return heaterSprite(square) == Sprites.gasHeater.off.W end,
            "the heater going out on this client once its digester was gone")
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
        local full = Fixtures.matureDigester("dome", { gas = self.gas })
        T.batch(function()
            T.setRecord(self, handle, full)
            T.setStat(self, "ENDURANCE", 1)
        end)
        T.waitForGas(self, handle, self.gas)
        -- Room for half the gas under the pump's limit, so it stops there with gas left.
        self.pumped = math.min(self.gas, Digester.PUMP_FILL * Digester.M3_PER_TANK) / 2
        T.give(self, "tools", { { type = Digester.PUMP }, { type = Digester.TANK, uses = Digester.PUMP_FILL - self.pumped / Digester.M3_PER_TANK } })
        T.actionJob(self, "digester", handle, DigesterJobs.FILL_PUMP, function() return self.items.tools[2] end)
        T.batch(function()
            T.readRecord(self, handle, "after")
            T.readCharacter(self, "endurance", { stats = { "ENDURANCE" } })
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
        T.expectNear("endurance after pumping " .. self.pumped .. " m³", self.reads.endurance.stats.ENDURANCE,
            1 - self.pumped * Digester.PUMP_ENDURANCE_PER_M3, 0.02)
        local refusal = DigesterJobs.refusal(T.player(), DigesterJobs.FILL_PUMP, self.digester.object, self.items.tools[2])
        T.expectEqual("the pump's refusal for a tank at its limit", refusal, "Tooltip_RenewableEnergy_PumpLimit")
    end,
})

-- Fill With Compressor runs the compressor fitted to the digester, which takes the carried one in,
-- on power at the digester: refused with none fitted, and with one fitted while the digester has
-- no power. A powered compressor won't fill a tank past the pump's share with unscrubbed gas. A
-- scrubber, fitted with a sound bucket (a broken one doesn't count) and charged from a bucket of
-- tainted water, which drains it, lets it; each m³ it scrubs uses up its charge and its steel wool.
-- Removing the compressor gives it back.
test("renewable_energy_biogas_compressor_fills_past_pump_with_scrubber", {
    instant = true,
    run = function(self)
        T.setGrid(self, false)
        local handle = T.placeRecord(self, "digester", "dome")
        if not handle then return end
        -- Less than the dome, the charge, the wool or the tank's room above the pump's share holds.
        self.gas = math.min(Digester.HOLDERS.dome.capacity, Digester.SCRUB_M3.lime, Digester.WOOL_M3,
            (1 - Digester.PUMP_FILL) * Digester.M3_PER_TANK) / 2
        T.setRecord(self, handle, Fixtures.matureDigester("dome", { gas = self.gas }))
        T.give(self, "fill", { { type = Digester.TANK, uses = Digester.PUMP_FILL } })
        T.waitForGas(self, handle, self.gas)
        local function fillRefusal()
            return DigesterJobs.refusal(T.player(), DigesterJobs.FILL_COMPRESSOR, handle.object, self.items.fill[1])
        end
        T.step(function() self.notFitted = fillRefusal() end)
        T.giveMaterials(self, "compressor", DigesterJobs.materials(T.player(), DigesterJobs.FIT_COMPRESSOR))
        T.actionJob(self, "digester", handle, DigesterJobs.FIT_COMPRESSOR)
        T.count(self, "fitted", { Digester.COMPRESSOR })
        T.waitForSummary(self, handle, function(summary) return summary.compressor end, "this client's summary of the fitted compressor")
        T.step(function()
            self.unpowered = fillRefusal()
            self.unpoweredSummary = T.recordSummary(handle)
        end)
        -- A running generator powers the squares around it, outdoors too.
        if not T.generator(self, { near = handle.square, fuel = 10, running = true }) then return end
        T.waitForSummary(self, handle, function(summary) return summary.powered end, "power at the digester")
        T.step(function() self.unscrubbed = fillRefusal() end)
        local scrubber = DigesterJobs.materials(T.player(), DigesterJobs.FIT_SCRUBBER)
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
        T.takeItems(self, nil, bucket)
        T.giveMaterials(self, "scrubber", scrubber)
        T.actionJob(self, "digester", handle, DigesterJobs.FIT_SCRUBBER)
        T.readRecord(self, handle, "fitted")
        -- Fitting took the bucket; the charge's water comes in another, tainted.
        T.batch(function()
            T.giveMaterials(self, "charge", DigesterJobs.materials(T.player(), DigesterJobs.REFILL_LIME))
            T.give(self, "water", { { type = "Base.Bucket" } })
            T.fillCarried(self, "Base.Bucket", "TaintedWater", Digester.SCRUB_WATER)
        end)
        -- Each job's action checks this client's copies, of the digester and the water.
        T.waitFor(self, function()
            local summary = T.recordSummary(handle)
            return summary ~= nil and summary.scrubber and self.items.water[1]:getFluidContainer():getAmount() >= Digester.SCRUB_WATER
        end, "this client's copies of the fitted scrubber and the water")
        T.actionJob(self, "digester", handle, DigesterJobs.REFILL_LIME)
        T.readRecord(self, handle, "charged")
        T.waitForSummary(self, handle, function(summary) return summary.scrubCO2 > 0 end, "this client's summary of the charged scrubber")
        T.actionJob(self, "digester", handle, DigesterJobs.FILL_COMPRESSOR, function() return self.items.fill[1] end)
        T.readRecord(self, handle, "filled")
        T.readCarried(self, { Digester.TANK, "Base.Bucket" })
        T.actionJob(self, "digester", handle, DigesterJobs.REMOVE_COMPRESSOR)
        T.readRecord(self, handle, "removed")
        T.count(self, "removed", { Digester.COMPRESSOR })
    end,
    validate = function(self)
        local charged, filled = self.reads.charged, self.reads.filled
        T.expectEqual("broken buckets counted as the scrubber's", self.brokenBucket, 0)
        T.expectEqual("the compressor's refusal with none fitted", self.notFitted, "Tooltip_RenewableEnergy_NoCompressor")
        T.expectEqual("compressors carried once one is fitted", self.counts.fitted[Digester.COMPRESSOR] or 0, 0)
        T.expectEqual("the fitted compressor's refusal without power at the digester", self.unpowered,
            "Tooltip_RenewableEnergy_NoPower")
        T.expect(self.unpoweredSummary and self.unpoweredSummary.compressor and not self.unpoweredSummary.powered,
            "the status doesn't read the compressor as fitted with no power")
        T.expectEqual("the compressor's refusal without a scrubber, at the pump's share", self.unscrubbed,
            "Tooltip_RenewableEnergy_NeedsScrubbed")
        T.expect(charged.scrubber, "the scrubber wasn't fitted")
        T.expectNear("scrubber charge with lime", charged.scrubCO2, Digester.SCRUB_M3.lime, 0.01)
        T.expectNear("steel wool once fitted", charged.scrubWool, Digester.WOOL_M3, 0.01)
        T.expect(T.hasOverlay(self.reads.fitted, Sprites.digesterScrubberSpent.dome), "the dome's uncharged scrubber doesn't show dry")
        T.expect(T.hasOverlay(charged, Sprites.digesterScrubber.dome) and not T.hasOverlay(charged, Sprites.digesterScrubberSpent.dome),
            "the dome doesn't show its charged scrubber")
        local tank = T.carriedFirst(self, Digester.TANK)
        if T.expect(tank ~= nil, "the tank is gone") then
            T.expectNear("tank after compressing " .. self.gas .. " m³", tank.uses, Digester.PUMP_FILL + self.gas / Digester.M3_PER_TANK, 0.002)
        end
        local bucket = T.carriedFirst(self, "Base.Bucket")
        T.expectNear("tainted water left after charging the scrubber", bucket and bucket.litres, 0, 0.01)
        T.expectNear("scrubber charge left", filled.scrubCO2, Digester.SCRUB_M3.lime - self.gas, 0.02)
        T.expectNear("steel wool left", filled.scrubWool, Digester.WOOL_M3 - self.gas, 0.02)
        T.expect(not self.reads.removed.compressor, "the compressor is still fitted after removing it")
        T.expectEqual("compressors carried after removing it", self.counts.removed[Digester.COMPRESSOR] or 0, 1)
    end,
})

-- A tire pump fills a welding torch straight from the digester, as close to the pump's share of
-- the torch as its whole uses come without passing it, taking the torch's fill share of a tank's
-- gas for each use. The torch's few uses put the share between two of them.
test("renewable_energy_biogas_pump_fills_torch", {
    instant = true,
    run = function(self)
        local handle = T.placeRecord(self, "digester", "dome")
        if not handle then return end
        self.gas = Digester.HOLDERS.dome.capacity
        T.setRecord(self, handle, Fixtures.matureDigester("dome", { gas = self.gas }))
        T.waitForGas(self, handle, self.gas)
        T.give(self, "tools", { { type = Digester.PUMP }, { type = "Base.BlowTorch", uses = 0 } })
        T.actionJob(self, "digester", handle, DigesterJobs.FILL_PUMP, function() return self.items.tools[2] end)
        T.batch(function()
            T.readRecord(self, handle, "after")
            T.readCarried(self, { "Base.BlowTorch" })
        end)
    end,
    validate = function(self)
        local torch = T.carriedFirst(self, "Base.BlowTorch")
        if not T.expect(torch ~= nil, "the torch is gone") then return end
        local delta = getScriptManager():FindItem("Base.BlowTorch"):getUseDelta()
        T.expect(torch.uses <= Digester.PUMP_FILL + 0.001 and torch.uses > Digester.PUMP_FILL - delta,
            "the pump filled the torch to " .. torch.uses .. ", not the last use up to its share")
        local m3 = torch.uses * Digester.FILL_SHARES[Digester.TORCH] * Digester.M3_PER_TANK
        T.expectNear("gas the torch took", self.gas - self.reads.after.gas, m3, 0.02)
    end,
})

-- An Iron Sponge packs the scrubber, taken whole; the next packing gives it back spent with the
-- packings it had left, and one packed on its last crumbles to nothing.
test("renewable_energy_biogas_iron_sponge_packing", {
    instant = true,
    run = function(self)
        local handle = T.placeRecord(self, "digester", "dome")
        if not handle then return end
        T.setRecord(self, handle, Fixtures.matureDigester("dome", { scrubber = true, scrubWool = 0, scrubSponge = 0 }))
        T.waitForSummary(self, handle, function(summary) return summary.scrubber end, "this client's summary of the scrubber")
        -- Short of a fresh sponge's packings, so they can only come from the sponge.
        T.give(self, "sponges", { { type = Digester.IRON_SPONGE, condition = 2 }, { type = Digester.IRON_SPONGE, condition = 1 } })
        T.actionJob(self, "digester", handle, DigesterJobs.REFILL_SPONGE, function() return self.items.sponges[1] end)
        T.readRecord(self, handle, "first")
        T.actionJob(self, "digester", handle, DigesterJobs.REFILL_SPONGE, function() return self.items.sponges[2] end)
        T.readCarried(self, { Digester.SPENT_SPONGE, Digester.IRON_SPONGE }, nil, "second")
        T.giveMaterials(self, "wool", DigesterJobs.materials(T.player(), DigesterJobs.REFILL_WOOL))
        T.actionJob(self, "digester", handle, DigesterJobs.REFILL_WOOL)
        T.batch(function()
            T.readRecord(self, handle, "wool")
            T.readCarried(self, { Digester.SPENT_SPONGE }, nil, "third")
        end)
    end,
    validate = function(self)
        local first, wool = self.reads.first, self.reads.wool
        T.expectEqual("the packed sponge's packings", first.scrubSponge, 2)
        T.expectNear("packing from a sponge", first.scrubWool, Digester.WOOL_M3, 0.01)
        local spent = T.carriedItems(self, Digester.SPENT_SPONGE, "second")
        T.expectEqual("spent sponges repacking gave back", #spent, 1)
        T.expectEqual("the spent sponge's packings", spent[1] and spent[1].condition, 2)
        T.expect(#T.carriedItems(self, Digester.IRON_SPONGE, "second") == 0, "packing left an Iron Sponge in the inventory")
        T.expect(#T.carriedItems(self, Digester.SPENT_SPONGE, "third") == 1 and wool.scrubSponge == 0,
            "a sponge on its last packing didn't crumble")
    end,
})

-- Refill Propane Bottle moves propane from a tank into a lantern bottle in whole uses of the tank
-- and makes none: what the bottle gains is what the tank loses. Each row's `start(use)` gives the
-- tank's and the bottle's uses from a tank use; a half tank filling a half bottle is
-- renewable_energy_biogas_propane_refill_from_floor_tank.
local SHARE = Digester.BOTTLE_SHARE
local REFILLS = {
    { what = "a tank holding less than the bottle's room", start = function(use)
        return math.max(1, math.floor(0.5 * SHARE / use / 2)) * use, 0.5
    end, check = function(what, _, tank)
        T.expectNear(what .. ": the tank after refilling", tank, 0, 0.0001)
    end },
    { what = "a bottle with less room than a tank use", start = function(use) return 0.5, 1 - 3 * use / SHARE / 4 end,
        check = function(what, bottle, tank, row)
            T.expectNear(what .. ": the bottle after refilling", bottle, row.bottleStart, 0.00001)
            T.expectNear(what .. ": the tank after refilling", tank, row.tankStart, 0.0001)
        end },
    { what = "a bottle with room for exactly one tank use", start = function(use) return 0.5, 1 - use / SHARE end,
        check = function(what, bottle)
            T.expectNear(what .. ": the bottle after refilling", bottle, 1, 0.00001)
        end },
}

test("renewable_energy_biogas_propane_refill_moves_whole_tank_uses", {
    instant = true,
    run = function(self)
        local name = "RenewableEnergy_RefillPropaneBottle"
        local recipe = (T.readyToCraft(self, { name }) or {})[name]
        if not recipe then return end
        local use = instanceItem(Digester.TANK):getUseDelta()
        self.rows = {}
        for i, row in ipairs(REFILLS) do
            local tankStart, bottleStart = row.start(use)
            local result = T.craftFrom(self, recipe, { type = Digester.BOTTLE, uses = bottleStart }, {
                inputs = function(items)
                    for _, item in ipairs(items) do
                        if item.type == Digester.TANK then
                            item.uses = tankStart
                        end
                    end
                end,
                read = { Digester.TANK },
            })
            self.rows[i] = { result = result, tankStart = tankStart, bottleStart = bottleStart }
            -- The bottle made and the tank kept go, so the next row's craft takes its own.
            T.takeItems(self, nil, Digester.BOTTLE)
            T.takeItems(self, nil, Digester.TANK)
        end
    end,
    validate = function(self)
        for i, row in ipairs(REFILLS) do
            local state, what = self.rows[i], row.what
            if state and T.expectCrafted(state.result, what) then
                local bottles = T.carriedItems(self, Digester.BOTTLE, state.result.label)
                local tanks = T.carriedItems(self, Digester.TANK, state.result.label)
                if T.expect(#bottles == 1 and #tanks == 1, what .. ": " .. #bottles .. " bottles and " .. #tanks
                    .. " tanks after the craft, not one of each") then
                    local bottle, tank = bottles[1].uses, tanks[1].uses
                    T.expectNear(what .. ": propane the bottle gained, in tanks, against what the tank lost",
                        (bottle - state.bottleStart) * SHARE, state.tankStart - tank, 0.0000001)
                    row.check(what, bottle, tank, state)
                end
            end
        end
    end,
})

-- Airing out a spent Iron Sponge gives an Iron Sponge with one packing fewer left than the spent
-- one had, short of a fresh sponge's, so the packings can only come from the spent one.
T.craftTest("renewable_energy_biogas_air_out_iron_sponge", {
    recipe = "RenewableEnergy_AirOutIronSponge",
    from = Digester.SPENT_SPONGE,
    -- The water's any-item input takes the bottle, which the setup fills with tainted water.
    prefer = { "Base.PopBottle" },
    setup = function(self)
        T.changeItem(self, T.inputsOf(self, Digester.SPENT_SPONGE)[1], { condition = 2 })
        T.fillCarried(self, "Base.PopBottle", "TaintedWater", 1)
    end,
    counts = { [Digester.IRON_SPONGE] = 1 },
    after = function(self)
        T.readCarried(self, { Digester.IRON_SPONGE })
    end,
    validate = function(self)
        local sponge = T.carriedFirst(self, Digester.IRON_SPONGE)
        T.expectEqual("the aired sponge's packings", sponge and sponge.condition, 1)
    end,
})

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

-- Refilling a half bottle from a half tank on the floor beside the character fills the bottle and
-- draws the tank down by what the bottle took, on this client too, as the loot window shows it.
test("renewable_energy_biogas_propane_refill_from_floor_tank", {
    instant = true,
    run = function(self)
        local recipe = T.need(self, getScriptManager():getCraftRecipe("RenewableEnergy_RefillPropaneBottle"), "the refill recipe")
        if not recipe then return end
        local here = T.player():getCurrentSquare()
        self.tankUses, self.bottleUses = 0.5, 0.5
        T.batch(function()
            T.give(self, "bottle", { { type = Digester.BOTTLE, uses = self.bottleUses } })
            T.floorItem(self, here, Digester.TANK, self.tankUses)
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
        T.readCarried(self, { Digester.BOTTLE })
    end,
    validate = function(self)
        local bottle = T.carriedFirst(self, Digester.BOTTLE)
        T.expectNear("bottle refilled from a half tank", bottle and bottle.uses or -1, 1, 0.001)
        T.expectNear("this client's floor tank after refilling", self.tank and self.tank:getCurrentUsesFloat() or -1,
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
        T.expectEqual("the tire pump a powered compressor counts as", self.offered and self.offered:getFullType(), Digester.COMPRESSOR)
        T.expectEqual("the item Inflate Tire queued inflating with", self.inflate and self.inflate:getFullType(), Digester.COMPRESSOR)
    end,
})
