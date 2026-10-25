require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"

-- What a gas line carries (GasLine/GasLines.lua): a load past its cap stalls the generator on it,
-- and the banks charging from it share what the cap leaves.

local T = RenewableEnergyTest
local test = T.test

local Digester, GasKit, Specs = RenewableEnergy.Digester, RenewableEnergy.GasKit, RenewableEnergy.Specs

-- The inverter with a charger the banks of the real-load stall test hold, and how many banks: their
-- chargers alone carry a line's whole cap, so beside any appliance the cap limits what they draw.
local BANK_CHARGER = T.INVERTER_CHARGER
local CHARGING_BANKS = math.ceil(GasKit.CAP_W / Specs.inverters[BANK_CHARGER].chargerWatts)
-- A mini fridge with its ice box, which vanilla bills as a fridge-freezer (Loads).
local MINI_FRIDGE = T.MINI_FRIDGE

-- A load past what the line carries stalls the generator, at exactly that it runs, and once the
-- load fits again it starts by itself. Cutting the line while stalled forgets the stall, so a new
-- line doesn't start it. The loads are made up (gasLoad): no set of appliances adds up to exactly
-- the cap; renewable_energy_gasline_generator_stalls_on_real_load measures a real one.
test("renewable_energy_gasline_generator_stalls_over_cap", {
    instant = true,
    run = function(self)
        local generator, digester = T.generatorOnDigester(self, "dome", Digester.HOLDERS.dome.capacity, 0)
        if not generator then return end
        T.batch(function()
            T.setGenerator(self, generator, { running = true })
            for _, case in ipairs({ { "atCap", GasKit.CAP_W }, { "over", GasKit.CAP_W + 1 }, { "fits", GasKit.CAP_W },
                { "stalled", GasKit.CAP_W + 1 } }) do
                T.gasLoad(self, case[2])
                T.gasPass(self, generator, 0.2)
                T.readGenerator(self, generator, case[1])
            end
        end)
        -- Cutting the line gives its hoses back, for the next.
        T.kitJob(self, generator, GasKit.DISCONNECT)
        T.readGenerator(self, generator, "cut")
        T.kitJob(self, generator, GasKit.CONNECT, digester)
        T.batch(function()
            T.gasLoad(self, GasKit.CAP_W)
            T.gasPass(self, generator, 0.2)
            T.readGenerator(self, generator, "reconnected")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        local atCap, over, fits = reads.atCap, reads.over, reads.fits
        T.expect(atCap.running and atCap.state ~= nil and not atCap.state.stalled, "the generator stalled at exactly its cap")
        T.expect(T.isStalled(over), "a watt over its cap didn't stall it")
        T.expect(fits.running and fits.state ~= nil and not fits.state.stalled, "the generator didn't start again once the load fit")
        T.expect(T.isStalled(reads.stalled), "a watt over its cap didn't stall it again")
        T.expect(reads.cut.state ~= nil and not reads.cut.state.stalled, "cutting the line left the generator stalled")
        T.expect(not reads.reconnected.running, "a new line started a generator stalled on the line before")
    end,
})

-- The test's bank handles `banks` in the order a generator on gas shares its cap between them:
-- nearest first, the lower place on a tie (GasLines.lua's chargingBanks).
local function shareOrder(generator, banks)
    local order = {}
    for _, bank in ipairs(banks) do
        local at = bank.position
        local dx, dy, dz = at.x - generator.x, at.y - generator.y, at.z - generator.z
        table.insert(order, { bank = bank, distance = dx * dx + dy * dy + dz * dz,
            key = RenewableEnergy.PlaceTracker.key(at.x, at.y, at.z) })
    end
    table.sort(order, function(a, b)
        return a.distance < b.distance or (a.distance == b.distance and a.key < b.key)
    end)
    local list = {}
    for i, entry in ipairs(order) do
        list[i] = entry.bank
    end
    return list
end

-- What the banks charging from a generator on gas draw: `headroomW`, the cap less what the generator
-- powers, shared in shareOrder, each bank at most what it wants (`wants`, by bank; its chargers'
-- rating if not given). Answers each bank's watts.
local function expectedShares(generator, banks, headroomW, wants)
    local left, shares = math.max(0, headroomW), {}
    for _, bank in ipairs(shareOrder(generator, banks)) do
        shares[bank] = math.min(wants and wants[bank] or Specs.inverters[BANK_CHARGER].chargerWatts, left)
        left = left - shares[bank]
    end
    return shares
end

-- The load a line carries is what the generator's scan finds and what the banks charging from it
-- draw. Beside a fridge, banks whose chargers alone carry the whole cap charge at what the cap leaves,
-- split between them, and the generator runs on through their passes; the nearest bank once full
-- leaves its share to the banks behind it; fridges past the cap stall it, and the banks then draw
-- nothing from it.
test("renewable_energy_gasline_generator_stalls_on_real_load", {
    instant = true,
    run = function(self)
        T.setGrid(self, false)
        local generator = T.generatorOnDigester(self, "dome", Digester.HOLDERS.dome.capacity, 0)
        local fridge = generator and T.square(self, { indoors = true, near = generator.square }, "a free indoor square for a fridge")
        if not fridge then return end
        self.generator = generator
        T.setGenerator(self, generator, { running = true })
        T.step(function() T.placeTile(self, fridge, MINI_FRIDGE) end)
        T.batch(function()
            T.gasPass(self, generator, 0.1)
            T.readGenerator(self, generator, "alone")
        end)
        self.banks = {}
        for i = 1, CHARGING_BANKS do
            self.banks[i] = T.bank(self, "batteryBoxWood", { BANK_CHARGER, "Base.CarBattery1" },
                { charge = 0.5, near = generator.square })
            if not self.banks[i] then return end
        end
        -- Every bank's pass, then the line's, and what each bank's chargers drew. The first round
        -- names the generator as each bank's source; the second shares the cap between all of them.
        self.drawn = {}
        local function passes(label)
            T.batch(function()
                for _, bank in ipairs(self.banks) do
                    T.bankPass(self, bank, 0, { hours = 0.01 })
                end
                T.gasPass(self, generator, 0.1)
                T.readGenerator(self, generator, label)
                T.step(function()
                    local drawn = {}
                    for _, bank in ipairs(self.banks) do
                        local status = bank.state and bank.state.status
                        drawn[bank] = { watts = status and status.chargerW, source = status and status.chargeSource }
                    end
                    self.drawn[label] = drawn
                end)
            end)
        end
        passes("charging")
        passes("shared")
        T.step(function()
            self.nearest = shareOrder(generator, self.banks)[1]
            T.setCharge(self, self.nearest, 1)
        end)
        passes("nearFull")
        -- Fridges whose load alone is past the cap, with the one already there.
        T.step(function()
            local alone = self.reads.alone.state and self.reads.alone.state.watts
            if not T.need(self, alone, "the generator's load with the fridge alone") then return end
            local count = math.floor((GasKit.CAP_W - alone) / T.applianceWatts({ "fridgeFreezer" })) + 1
            local squares = T.need(self, count > 0 and T.squares(self, count, { indoors = true, near = generator.square }),
                count .. " free indoor squares for fridges past the line's cap")
            if not squares then return end
            for _, square in ipairs(squares) do
                T.placeTile(self, square, MINI_FRIDGE)
            end
            passes("overloaded")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        local alone = reads.alone
        T.expect(alone.running and alone.state ~= nil and alone.state.watts ~= nil, "the generator didn't run the fridge alone")
        if not alone.state or not alone.state.watts then return end
        local headroomW = GasKit.CAP_W - alone.state.watts
        T.expect(alone.state.watts > 0 and headroomW > 0,
            "the fridge alone makes a load of " .. alone.state.watts .. " W, not one the line carries")
        T.expect(CHARGING_BANKS * Specs.inverters[BANK_CHARGER].chargerWatts > headroomW,
            "the banks' chargers fit in what the cap leaves, so nothing limits them")
        for _, label in ipairs({ "charging", "shared" }) do
            local read = reads[label]
            T.expect(read.running and read.state ~= nil and not read.state.stalled,
                "after the " .. label .. " passes, the banks charging from the generator stalled it")
        end
        local shares = expectedShares(self.generator, self.banks, headroomW)
        local sum = 0
        for i, bank in ipairs(self.banks) do
            local drawn = self.drawn.shared[bank]
            T.expect(drawn.source == "generator", "bank " .. i .. " charges from " .. tostring(drawn.source))
            T.expectNear("bank " .. i .. "'s share of what the cap leaves", drawn.watts or -1, shares[bank], 0.01)
            sum = sum + (drawn.watts or 0)
        end
        T.expectNear("the banks' charge together", sum, headroomW, 0.01)
        T.expectNear("the generator's load with the banks charging", reads.shared.state and reads.shared.state.watts or 0,
            GasKit.CAP_W, 0.01)
        -- Full, the nearest bank takes next to nothing, and the banks behind it what it leaves.
        local nearFull = self.drawn.nearFull
        local fullW = nearFull[self.nearest].watts or -1
        T.expect(fullW >= 0 and fullW < Specs.inverters[BANK_CHARGER].chargerWatts / 100,
            "the full nearest bank draws " .. fullW .. " W")
        T.expect(reads.nearFull.running and reads.nearFull.state ~= nil and not reads.nearFull.state.stalled,
            "with the nearest bank full, the banks charging from the generator stalled it")
        local nearFullShares = expectedShares(self.generator, self.banks, headroomW, { [self.nearest] = fullW })
        for i, bank in ipairs(self.banks) do
            T.expectNear("bank " .. i .. "'s share with the nearest bank full", nearFull[bank].watts or -1,
                nearFullShares[bank], 0.01)
        end
        local overloaded = reads.overloaded
        if not T.expect(overloaded ~= nil and overloaded.state ~= nil, "no read of the generator past its cap") then return end
        T.expect((overloaded.state.watts or 0) > GasKit.CAP_W,
            "the fridges make a load of " .. tostring(overloaded.state.watts) .. " W, not past the cap")
        T.expect(T.isStalled(overloaded), "fridges past the cap didn't stall the generator")
        for i, bank in ipairs(self.banks) do
            T.expectNear("bank " .. i .. "'s charge with the cap taken", self.drawn.overloaded[bank].watts or -1, 0, 0)
        end
    end,
})
