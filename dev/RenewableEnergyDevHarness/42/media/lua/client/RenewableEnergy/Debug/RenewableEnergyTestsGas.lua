require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"

-- Gas lines and wood gas: the Gas Conversion Kit on a vanilla generator, the line from a digester or
-- a gasifier that feeds it, and the gasifier itself. Tests take fuel from a generator through
-- burnFuel, as vanilla's bill does, and set its load through gasLoad, so each test drives the line
-- at a known bill and a known number of watts.

local T = RenewableEnergyTest
local test = T.test

local Digester, GasKit, Materials = RenewableEnergy.Digester, RenewableEnergy.GasKit, RenewableEnergy.Materials
local Gasifier, GasifierJobs = RenewableEnergy.Gasifier, RenewableEnergy.GasifierJobs
local Sprites = RenewableEnergy.Sprites

-- What this client's copy of a generator's kit state shows once each job is done. The next job's
-- action checks this client's copy, so it waits for it.
local KIT_DONE = {
    [GasKit.INSTALL] = function(state) return state ~= nil end,
    [GasKit.REMOVE] = function(state) return state == nil end,
    [GasKit.CONNECT] = function(state) return state ~= nil and state.source ~= nil end,
    [GasKit.DISCONNECT] = function(state) return state ~= nil and state.source == nil end,
    [GasKit.TO_PETROL] = function(state) return state ~= nil and state.mode == "petrol" end,
    [GasKit.TO_GAS] = function(state) return state ~= nil and state.mode == "gas" end,
}

-- Queues the kit job `job` at `generator` (to the record `source` for Connect Gas Line), and a wait
-- until this client's copy shows it done.
local function kitJob(self, generator, job, source)
    T.gasJob(self, "kit", generator, job, source)
    T.waitFor(self, function() return KIT_DONE[job](GasKit.stateOf(generator.object)) end,
        "this client's copy of the generator after " .. job)
end

-- Queues fitting the kit to `generator`, with what that takes given first.
local function fitKit(self, generator)
    T.giveMaterials(self, "kit", GasKit.materials(GasKit.INSTALL))
    kitJob(self, generator, GasKit.INSTALL)
end

-- Queues fitting the kit and connecting the line to the record `source`, with what each takes
-- given first; self.line is what the line took.
local function fitAndConnect(self, generator, source)
    fitKit(self, generator)
    T.step(function()
        self.line = GasKit.materials(GasKit.CONNECT, generator.object, source.object)
        T.giveMaterials(self, "line", self.line)
    end)
    kitJob(self, generator, GasKit.CONNECT, source)
end

-- A free outdoor square at one of `offsets` from `square`, or nil.
local function squareAt(square, offsets)
    for _, offset in ipairs(offsets) do
        local found = getSquare(square:getX() + offset[1], square:getY() + offset[2], square:getZ())
        if RenewableEnergy.Debug.isFreeSquare(found, false) then
            return found
        end
    end
    return nil
end

local SIDES = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
local CORNERS = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }

-- A digester beside the generator's square, holding `gas` and mature.
local function digesterWithGas(self, tile, gas)
    local digester = T.placeRecord(self, "digester", tile)
    if not digester then return nil end
    local state = T.matureDigester(tile:match("^[^.]+"))
    state.gas = gas
    T.setRecord(self, digester, state)
    return digester
end

-- Gas lines ---------------------------------------------------------------------------------------

-- Fitting the kit takes the kit, keeps the tank and shows the valve; it can't come off while the
-- generator runs; taking it off gives the kit back with the tank as it was.
test("renewable_energy_gas_kit_install_and_remove", {
    instant = true,
    run = function(self)
        self.fuel = 3
        local generator = T.generator(self, { fuel = self.fuel })
        if not generator then return end
        self.install = GasKit.materials(GasKit.INSTALL)
        fitKit(self, generator)
        T.batch(function()
            T.readGenerator(self, generator, "fitted")
            T.countMaterials(self, "afterFit", self.install)
            T.setGenerator(self, generator, { running = true })
        end)
        T.waitFor(self, function() return generator.object:isActivated() and GasKit.hasKit(generator.object) end,
            "this client's copy of the kitted generator running")
        T.step(function() self.runningRefusal = GasKit.refusal(T.player(), GasKit.REMOVE, generator.object) end)
        T.setGenerator(self, generator, { running = false })
        T.waitFor(self, function() return not generator.object:isActivated() end, "this client's copy of the generator stopped")
        kitJob(self, generator, GasKit.REMOVE)
        T.batch(function()
            T.readGenerator(self, generator, "removed")
            T.count(self, "afterRemove", { GasKit.ITEM })
        end)
    end,
    validate = function(self)
        local fitted, removed = self.reads.fitted, self.reads.removed
        if T.expect(fitted.state ~= nil and fitted.listed, "the kit isn't fitted") then
            T.expectNear("tank with the kit", fitted.state.tank, self.fuel, 0.01)
        end
        -- On the game's own generator the kit sits on its air intake, not on the floor.
        local kit = Sprites.gasKitFor(fitted.sprite)
        T.expect(kit ~= Sprites.gasKit.default and T.hasOverlay(fitted, kit),
            "the fitted kit doesn't show on " .. tostring(fitted.sprite) .. "'s intake")
        T.expectMaterialsUsed(self, "afterFit", self.install, "fitting the kit")
        T.expect(self.runningRefusal == "Tooltip_RenewableEnergy_GeneratorRunning",
            "taking the kit off a running generator: " .. tostring(self.runningRefusal))
        T.expect(removed.state == nil and not removed.listed, "the kit is still fitted")
        T.expect(not T.hasOverlay(removed, kit), "the removed kit still shows")
        T.expectNear("fuel after removing it", removed.fuel, self.fuel, 0.01)
        T.expect(self.counts.afterRemove[GasKit.ITEM] == 1, "removing didn't give the kit back")
    end,
})

-- On a line from a digester with gas, an empty-tanked generator runs: the fuel vanilla bills it is
-- paid in the digester's gas and put back, its tank stays empty, and petrol poured in goes into the
-- tank. Switched to petrol it runs on its tank and leaves the gas; back on gas, when the gas runs
-- out it stops, holding only its tank. The line takes its hoses, which come back when it is cut.
test("renewable_energy_gas_generator_runs_on_gas", {
    instant = true,
    run = function(self)
        self.gas, self.litres, self.poured = Digester.HOLDERS.bags.capacity, 0.25, 3
        local digester = digesterWithGas(self, "barrel.MetalDrum", self.gas)
        local generator = digester and T.generator(self, { near = digester.square, fuel = 0 })
        if not generator then return end
        -- One more hose than the line takes, so the count shows what it took.
        T.give(self, "spare", { { type = GasKit.HOSE } })
        fitAndConnect(self, generator, digester)
        T.batch(function()
            T.readGenerator(self, generator, "connected")
            T.count(self, "connected", { GasKit.HOSE })
            T.setGenerator(self, generator, { running = true })
            T.burnFuel(self, generator, self.litres)
            T.gasPass(self, generator, 0.5)
            T.readGenerator(self, generator, "running")
            T.readRecord(self, digester, "fed")
            T.setGenerator(self, generator, { pour = self.poured })
            T.gasPass(self, generator, 0.1)
            T.readGenerator(self, generator, "poured")
        end)
        kitJob(self, generator, GasKit.TO_PETROL)
        T.batch(function()
            T.readRecord(self, digester, "beforePetrol")
            T.gasPass(self, generator, 0.5)
            T.readGenerator(self, generator, "petrol")
            T.readRecord(self, digester, "afterPetrol")
        end)
        kitJob(self, generator, GasKit.TO_GAS)
        T.batch(function()
            T.setRecord(self, digester, { gas = 0 })
            T.gasPass(self, generator, 0.5)
            T.readGenerator(self, generator, "out")
        end)
        kitJob(self, generator, GasKit.DISCONNECT)
        T.count(self, "cut", { GasKit.HOSE })
    end,
    validate = function(self)
        local reads = self.reads
        local connected, running, poured, petrol, out = reads.connected, reads.running, reads.poured, reads.petrol, reads.out
        local hoses = 0
        for _, material in ipairs(self.line) do
            hoses = material.item == GasKit.HOSE and material.need or hoses
        end
        T.expect(hoses > 0, "the line from a digester takes no hoses")
        T.expect(connected.state and connected.state.connected, "the gas line isn't connected")
        T.expect(connected.fuel >= GasKit.PHANTOM_FUEL - 0.01, "on gas, the generator shows " .. connected.fuel .. " L, too little to start")
        T.expect(self.counts.connected[GasKit.HOSE] == 1,
            "the line left " .. tostring(self.counts.connected[GasKit.HOSE]) .. " of " .. (hoses + 1) .. " hoses, not 1")
        T.expect(running.running, "the generator didn't keep running on gas")
        T.expectNear("fuel shown on gas once the pass paid what vanilla billed", running.fuel, GasKit.PHANTOM_FUEL, 0.01)
        if T.expect(running.state ~= nil, "the running generator lost its kit") then
            T.expectNear("tank while on gas", running.state.tank, 0, 0.001)
        end
        -- The digester's own pass may add a little gas meanwhile.
        T.expectNear("gas paying for " .. self.litres .. " L of fuel", self.gas - reads.fed.gas, self.litres * GasKit.M3_PER_LITRE, 0.02)
        if T.expect(poured.state ~= nil, "the generator lost its kit after pouring") then
            T.expectNear("tank after pouring", poured.state.tank, self.poured, 0.01)
        end
        T.expect(petrol.running and petrol.state ~= nil and not petrol.state.onGas, "switched to petrol, it doesn't run on its tank")
        T.expectNear("fuel on petrol", petrol.fuel, self.poured, 0.05)
        T.expectNear("gas burned on petrol", reads.afterPetrol.gas, reads.beforePetrol.gas, 0.001)
        T.expect(not out.running and out.state ~= nil and out.state.outOfGas, "the generator kept running with no gas")
        T.expectNear("fuel once the gas ran out", out.fuel, self.poured, 0.05)
        T.expect(self.counts.cut[GasKit.HOSE] == hoses + 1, "cutting the line left " .. tostring(self.counts.cut[GasKit.HOSE]) .. " hoses")
    end,
})

-- A job at a kitted generator first settles the fuel burned since the last pass as it ran:
-- switching to petrol pays in gas for the fuel burned on gas until then, and switching back to gas
-- leaves the fuel burned on petrol to the tank.
test("renewable_energy_gas_job_bills_the_fuel_before_it", {
    instant = true,
    run = function(self)
        self.gas, self.tank, self.litres = Digester.HOLDERS.bags.capacity, 1, 0.2
        local digester = digesterWithGas(self, "barrel.MetalDrum", self.gas)
        local generator = digester and T.generator(self, { near = digester.square, fuel = self.tank })
        if not generator then return end
        fitAndConnect(self, generator, digester)
        T.batch(function()
            T.setGenerator(self, generator, { running = true })
            T.gasPass(self, generator, 0)
            T.readRecord(self, digester, "onGas")
            T.burnFuel(self, generator, self.litres)
        end)
        kitJob(self, generator, GasKit.TO_PETROL)
        T.batch(function()
            T.readRecord(self, digester, "onPetrol")
            T.readGenerator(self, generator, "generatorOnPetrol")
            T.burnFuel(self, generator, self.litres)
        end)
        kitJob(self, generator, GasKit.TO_GAS)
        T.batch(function()
            T.gasPass(self, generator, 0)
            T.readRecord(self, digester, "backOnGas")
            T.readGenerator(self, generator, "generatorBackOnGas")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        T.expectNear("gas Run on Petrol billed for the " .. self.litres .. " L burned on gas before it",
            reads.onGas.gas - reads.onPetrol.gas, self.litres * GasKit.M3_PER_LITRE, 0.02)
        T.expectNear("tank once on petrol", reads.generatorOnPetrol.fuel, self.tank, 0.01)
        T.expectNear("gas billed for the " .. self.litres .. " L burned on petrol", reads.onPetrol.gas - reads.backOnGas.gas, 0, 0.02)
        local backOnGas = reads.generatorBackOnGas
        if T.expect(backOnGas.state ~= nil, "the generator lost its kit") then
            T.expectNear("tank back on gas", backOnGas.state.tank, self.tank - self.litres, 0.01)
        end
    end,
})

-- A load past what a generator carries on gas stalls it, at its cap it runs, and once the load fits
-- again it starts on its own. A line cut while it is stalled forgets the stall, so a new line
-- doesn't start it.
test("renewable_energy_gas_generator_stalls_over_cap", {
    instant = true,
    run = function(self)
        local digester = digesterWithGas(self, "dome", Digester.HOLDERS.dome.capacity)
        local generator = digester and T.generator(self, { near = digester.square, fuel = 0 })
        if not generator then return end
        fitAndConnect(self, generator, digester)
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
        kitJob(self, generator, GasKit.DISCONNECT)
        T.readGenerator(self, generator, "cut")
        kitJob(self, generator, GasKit.CONNECT, digester)
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
        T.expect(not over.running and over.state ~= nil and over.state.stalled, "a watt over its cap didn't stall it")
        T.expect(fits.running and fits.state ~= nil and not fits.state.stalled, "the generator didn't start again once the load fit")
        T.expect(reads.stalled.state ~= nil and reads.stalled.state.stalled, "a watt over its cap didn't stall it again")
        T.expect(reads.cut.state ~= nil and not reads.cut.state.stalled, "cutting the line left the generator stalled")
        T.expect(not reads.reconnected.running, "a new line started a generator stalled on the line before")
    end,
})

-- A line whose gasifier is gone is lost with it while the generator runs on petrol too: no line in
-- its state, no pipe on the generator, and on this client a new line can be connected.
test("renewable_energy_gas_line_lost_with_its_source_on_petrol", {
    instant = true,
    run = function(self)
        local generator = T.generator(self, { fuel = 3 })
        if not generator then return end
        local square = T.need(self, squareAt(generator.square, SIDES), "a free square beside the generator")
        local gasifier = square and T.placeRecord(self, "gasifier", "primitive", { square = square })
        if not gasifier then return end
        self.side = Gasifier.sideOf(generator.x, generator.y, gasifier.x, gasifier.y)
        fitAndConnect(self, generator, gasifier)
        kitJob(self, generator, GasKit.TO_PETROL)
        T.batch(function()
            T.setGenerator(self, generator, { running = true })
            T.removeRecord(self, gasifier)
            T.gasPass(self, generator, 0.1)
            T.readGenerator(self, generator, "lost")
        end)
        T.waitFor(self, function()
            local state = GasKit.stateOf(generator.object)
            return state ~= nil and state.source == nil
        end, "this client's copy of the generator without its line")
        T.step(function() self.connect = GasKit.refusal(T.player(), GasKit.CONNECT, generator.object) end)
    end,
    validate = function(self)
        local lost = self.reads.lost
        T.expect(lost.running and lost.state ~= nil and lost.state.mode == "petrol", "the generator stopped running on petrol")
        T.expect(lost.state ~= nil and not lost.state.connected, "the line to a gasifier that is gone is still connected")
        T.expect(not T.hasOverlay(lost, Sprites.gasifierPipeGenFor(lost.sprite, self.side)),
            "the generator still shows a pipe to a gasifier that is gone")
        T.expect(self.connect ~= "Tooltip_RenewableEnergy_HasLine", "this client refuses a new line: the generator still has one")
    end,
})

-- A kitted generator's menu has the kit's jobs and greys out Take Generator; the client refuses the
-- take too, and the info window shows the real tank and that it runs on gas.
test("renewable_energy_gas_kit_menu", {
    instant = true,
    run = function(self)
        local digester = digesterWithGas(self, "barrel.MetalDrum", Digester.HOLDERS.bags.capacity)
        local generator = digester and T.generator(self, { near = digester.square, fuel = 0 })
        if not generator then return end
        self.generator = generator
        T.step(function()
            local submenu, context = T.worldSubmenu(generator.object, getText("ContextMenu_Generator"))
            local install = submenu and submenu:getOptionFromName(getText("ContextMenu_RenewableEnergy_InstallKit"))
            self.installShown = install ~= nil
            self.installGreyed = install ~= nil and install.notAvailable == true
            if context then
                context:hideAndChildren()
            end
        end)
        fitAndConnect(self, generator, digester)
        T.waitFor(self, function()
            local state = GasKit.stateOf(generator.object)
            return state ~= nil and state.onGas == true
        end, "this client's copy of the kit's state")
    end,
    validate = function(self)
        T.expect(self.installShown and self.installGreyed, "without a kit and wrench, Install isn't offered greyed out")
        local generator = self.generator.object
        local submenu, context = T.worldSubmenu(generator, getText("ContextMenu_Generator"))
        if T.expect(submenu ~= nil, "a kitted generator has no generator submenu") then
            T.expect(submenu:getOptionFromName(getText("ContextMenu_RenewableEnergy_DisconnectLine")) ~= nil, "no Disconnect Gas Line")
            T.expect(submenu:getOptionFromName(getText("ContextMenu_RenewableEnergy_RemoveKit")) ~= nil, "no Remove Gas Conversion Kit")
            local take = submenu:getOptionFromName(getText("ContextMenu_GeneratorTake"))
            T.expect(take == nil or take.notAvailable, "Take Generator is offered on a kitted generator")
        end
        if context then
            context:hideAndChildren()
        end
        T.expect(not ISTakeGenerator:new(T.player(), generator):isValid(), "the client lets a kitted generator be taken")
        local text = ISGeneratorInfoWindow.getRichText(generator, true)
        T.expect(text:find(getText("IGUI_Generator_FuelAmount", 0), 1, true) ~= nil, "the info window doesn't show the empty tank")
        T.expect(text:find(getText("IGUI_RenewableEnergy_GasOn"), 1, true) ~= nil, "the info window doesn't say it runs on gas")
    end,
})

-- Fumes -------------------------------------------------------------------------------------------

-- A building is toxic while any of the mod's sources in it fumes: a sour digester and a lit
-- gasifier, either alone, and clear only once the last stops. A digester whose gas overflows
-- indoors leaks fumes for LEAK_HOURS, and no longer.
test("renewable_energy_gas_fumes_last_source_clears", {
    run = function(self)
        local digester = T.placeRecord(self, "digester", "barrel.MetalDrum", { indoors = true })
        local square = digester and T.square(self, { indoors = true, near = digester.square, minDistance = 2 }, "another indoor square")
        if not square then return end
        if not T.need(self, square:getBuilding() == digester.square:getBuilding(), "two indoor squares in one building") then return end
        local gasifier = T.placeRecord(self, "gasifier", "primitive", { square = square })
        if not gasifier then return end
        local sour = T.sourDigester("barrel")
        local overflowing = { sour = false, acid = 0, potential = 0, leakHours = 0, gas = Digester.HOLDERS.bags.capacity + 0.1 }
        -- The pass that overflows starts the leak; half an hour short of LEAK_HOURS after, it still
        -- leaks, and at LEAK_HOURS it has stopped.
        local overflow = 0.5
        T.batch(function()
            T.setRecord(self, digester, sour)
            T.readRecord(self, digester, "sour")
            T.setRecord(self, gasifier, { lit = true, fireKg = 2 })
            T.setRecord(self, digester, T.matureDigester("barrel"))
            T.readRecord(self, gasifier, "gasifierOnly")
            T.setRecord(self, digester, sour)
            T.setRecord(self, gasifier, { lit = false })
            T.readRecord(self, digester, "digesterOnly")
            T.setRecord(self, digester, overflowing)
            T.runDigester(self, digester, overflow, 30)
            T.runDigester(self, digester, Digester.LEAK_HOURS - overflow, 30)
            T.readRecord(self, digester, "leaking")
            T.runDigester(self, digester, overflow, 30)
            T.readRecord(self, digester, "leaked")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        T.expect(reads.sour.toxic, "a sour digester indoors left the building clear")
        T.expect(reads.gasifierOnly.toxic, "a lit gasifier indoors left the building clear once the digester was fixed")
        T.expect(reads.digesterOnly.toxic, "the building cleared when the gasifier went out with the digester still sour")
        T.expect(reads.leaking.toxic, "the building cleared before a leak's " .. Digester.LEAK_HOURS .. " hours were over")
        T.expect(not reads.leaked.toxic, "the building stayed toxic once the leak was over")
    end,
})

-- Wood gas ----------------------------------------------------------------------------------------

-- Queues lighting the gasifier once this client sees wood in it, with what that takes then given
-- first.
local function light(self, gasifier)
    T.waitForSummary(self, gasifier, function(summary) return summary.hopperKg > 0 end, "this client's summary of the gasifier's wood")
    T.step(function()
        T.giveMaterials(self, "light", GasifierJobs.materials(GasifierJobs.LIGHT, T.recordSummary(gasifier)))
    end)
    T.gasJob(self, "gasifier", gasifier, GasifierJobs.LIGHT)
end

-- A gasifier beside a kitted generator, piped to it and lit, runs the generator with an empty tank,
-- burning KG_PER_LITRE of wood for each litre vanilla bills the generator, and nothing more of its
-- own while the generator runs. A full ash pit, or a spent filter, cuts what it carries to
-- DIRTY_OUTPUT of the cap: a watt over that stalls the generator, a pit one short of full doesn't,
-- and at exactly that it runs. Out of wood, the generator stops.
test("renewable_energy_gas_gasifier_runs_generator", {
    instant = true,
    run = function(self)
        local generator = T.generator(self, { fuel = 0 })
        if not generator then return end
        local square = T.need(self, squareAt(generator.square, SIDES), "a free square beside the generator")
        local gasifier = square and T.placeRecord(self, "gasifier", "standard", { square = square })
        if not gasifier then return end
        local spec = Gasifier.TIERS.standard
        self.generatorSide = Gasifier.sideOf(gasifier.x, gasifier.y, generator.x, generator.y)
        self.gasifierSide = Gasifier.sideOf(generator.x, generator.y, gasifier.x, gasifier.y)
        self.litres, self.dirtyCap = 0.5, GasKit.CAP_W * Gasifier.DIRTY_OUTPUT
        -- One tuft in the filter, so burning one item's worth of tar spends it.
        T.fillRecord(self, gasifier, { hopper = { { type = "Base.Plank", count = 6 } }, filter = { { type = "Base.HayTuft" } } })
        -- Lit first, so gas reaches the generator the moment the line is in.
        light(self, gasifier)
        fitAndConnect(self, generator, gasifier)
        T.batch(function()
            T.readRecord(self, gasifier, "lit")
            T.readGenerator(self, generator, "connected")
            T.setGenerator(self, generator, { running = true })
            T.burnFuel(self, generator, self.litres)
            T.gasPass(self, generator, 1)
            T.ageRecord(self, gasifier, 1, "fed")
            T.readGenerator(self, generator, "running")
            T.gasLoad(self, self.dirtyCap + 1)
            for _, case in ipairs({ { "ashNearlyFull", Gasifier.ASH_FULL - 1 }, { "ashFull", Gasifier.ASH_FULL }, { "ashCleared", 0 } }) do
                T.setRecord(self, gasifier, { ash = case[2] })
                T.gasPass(self, generator, 0.1)
                T.readGenerator(self, generator, case[1])
            end
            T.server(self, "gasifierBurn", T.recordArgs(gasifier, { kg = spec.tarKgPerItem }))
            T.gasPass(self, generator, 0.1)
            T.readGenerator(self, generator, "filterSpent")
            T.readRecord(self, gasifier, "spent")
            T.gasLoad(self, self.dirtyCap)
            T.gasPass(self, generator, 0.1)
            T.readGenerator(self, generator, "dirtyRuns")
            -- More than the hopper and the firebox hold.
            T.server(self, "gasifierBurn", T.recordArgs(gasifier, { kg = 2 * spec.hopperKg }))
            T.gasPass(self, generator, 0.1)
            T.readGenerator(self, generator, "out")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        local lit, fed, connected, running = reads.lit, reads.fed, reads.connected, reads.running
        local function stalled(read)
            return not read.running and read.state ~= nil and read.state.stalled
        end
        T.expect(lit.lit and lit.fireKg > 0, "lighting it didn't start a fire from the hopper")
        T.expect(lit.containers == 2, "the gasifier has " .. tostring(lit.containers) .. " containers, not a hopper and a filter")
        T.expect(connected.state and connected.state.sourceKind == "gasifier", "the line doesn't lead to the gasifier")
        T.expect(T.hasOverlay(lit, Sprites.gasifierLit.standard), "the lit gasifier shows no fire")
        T.expect(T.hasOverlay(reads.spent, Sprites.gasifierPipe[self.generatorSide]), "the gasifier shows no pipe toward the generator")
        T.expect(T.hasOverlay(connected, Sprites.gasifierPipeGenFor(connected.sprite, self.gasifierSide)),
            "the generator shows no pipe toward the gasifier")
        T.expect(running.running and running.fuel >= GasKit.PHANTOM_FUEL, "the generator didn't run on wood gas with an empty tank")
        local kg = self.litres * Gasifier.KG_PER_LITRE
        T.expectNear("wood burned for " .. self.litres .. " L of fuel and an hour's own pass", (lit.hopperKg + lit.fireKg) - (fed.hopperKg + fed.fireKg), kg, 0.05)
        T.expectNear("ash after that wood", fed.ash - lit.ash, kg * Gasifier.TIERS.standard.ashPerKg, 0.15)
        local over = (self.dirtyCap + 1) .. " W"
        T.expect(reads.ashNearlyFull.running, "an ash pit one short of full stalled a generator at " .. over)
        T.expect(stalled(reads.ashFull), "a full ash pit didn't stall a generator at " .. over)
        T.expect(reads.ashCleared.running, "the generator didn't start again once the ash was cleared")
        T.expect(reads.spent.clean == 0, "the filter still has " .. tostring(reads.spent.clean) .. " clean packing")
        T.expect(stalled(reads.filterSpent), "a spent filter didn't stall a generator at " .. over)
        T.expect(reads.dirtyRuns.running, "a spent filter didn't run a generator at " .. self.dirtyCap .. " W")
        T.expect(not reads.out.running and reads.out.state and reads.out.state.outOfGas, "out of wood, the generator kept running")
    end,
})

-- A lit gasifier whose generator isn't running burns, in its own pass, the wood for what vanilla
-- bills a generator idling (IsoGenerator.getBasePowerConsumption, which follows the
-- GeneratorFuelConsumption option, set high here so the hours show), and goes out once its wood is
-- gone.
test("renewable_energy_gas_gasifier_idles_as_a_generator", {
    instant = true,
    sandbox = { GeneratorFuelConsumption = 1 },
    run = function(self)
        local generator = T.generator(self, {})
        local idling = generator and T.placeRecord(self, "gasifier", "standard")
        local burning = idling and T.placeRecord(self, "gasifier", "standard")
        if not burning then return end
        self.hours, self.fireKg = 10, 0.1
        T.batch(function()
            T.readGenerator(self, generator, "vanilla")
            T.fillRecord(self, idling, { hopper = { { type = "Base.Plank", count = 6 } } })
            T.setRecord(self, idling, { lit = true })
            T.readRecord(self, idling, "lit")
            T.ageRecord(self, idling, self.hours, "idled")
            T.setRecord(self, burning, { lit = true, fireKg = self.fireKg })
            T.ageRecord(self, burning, self.hours, "burnedDown")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        local lit, idled = reads.lit, reads.idled
        local kg = reads.vanilla.idle * Gasifier.KG_PER_LITRE * self.hours
        T.expect(kg > self.fireKg, "the idle burn of " .. self.hours .. " hours is too small to burn the firebox down")
        T.expectNear("wood burned idling " .. self.hours .. " hours", (lit.hopperKg + lit.fireKg) - (idled.hopperKg + idled.fireKg), kg, 0.01)
        T.expect(idled.lit, "the gasifier went out with wood in its hopper")
        T.expect(not reads.burnedDown.lit, "the gasifier stayed lit with its wood gone")
    end,
})

-- Only a gasifier right beside the generator can be piped to it, not one on a corner.
test("renewable_energy_gas_gasifier_must_stand_beside", {
    instant = true,
    run = function(self)
        local generator = T.generator(self, { fuel = 0 })
        if not generator then return end
        local square = T.need(self, squareAt(generator.square, CORNERS), "a free square on a corner of the generator")
        local gasifier = square and T.placeRecord(self, "gasifier", "primitive", { square = square })
        if not gasifier then return end
        fitKit(self, generator)
        T.step(function() self.refusal = GasKit.refusal(T.player(), GasKit.CONNECT, generator.object, gasifier.object) end)
    end,
    validate = function(self)
        T.expect(self.refusal == "Tooltip_RenewableEnergy_GasifierNotBeside", "a gasifier on a corner: " .. tostring(self.refusal))
    end,
})

-- The ash pit fills as wood burns; Clean Out Ash with a shovel gives Wood Ash for it and leaves the
-- rest, and refuses with one short of an item's worth, not with exactly one. The filter's packing
-- turns tarry.
test("renewable_energy_gas_gasifier_ash_and_tar", {
    instant = true,
    run = function(self)
        local gasifier = T.placeRecord(self, "gasifier", "standard")
        if not gasifier then return end
        local spec = Gasifier.TIERS.standard
        self.burned = 2 * spec.tarKgPerItem + 0.5
        self.ash = 2 * Gasifier.ASH_PER_ITEM + Gasifier.ASH_PER_ITEM / 2
        T.batch(function()
            T.fillRecord(self, gasifier, { hopper = { { type = "Base.Plank", count = 7 } }, filter = { { type = "Base.HayTuft", count = 2 } } })
            T.setRecord(self, gasifier, { lit = true })
            T.server(self, "gasifierBurn", T.recordArgs(gasifier, { kg = self.burned }))
            T.readRecord(self, gasifier, "burned")
            -- Out, so no pass burns more meanwhile.
            T.setRecord(self, gasifier, { ash = self.ash, lit = false })
        end)
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
        local burned, cleaned = self.reads.burned, self.reads.cleaned
        T.expectNear("ash after burning", burned.ash, self.burned * Gasifier.TIERS.standard.ashPerKg, 0.05)
        T.expect(burned.clean == 0 and burned.tarry == 2, "packing after burning: " .. tostring(burned.clean) .. " clean, " .. tostring(burned.tarry) .. " tarry")
        T.expectNear("ash after cleaning out", cleaned.ash, self.ash - 2 * Gasifier.ASH_PER_ITEM, 0.01)
        T.expect(self.counts.ash[Gasifier.WOOD_ASH] == 2, "cleaning out gave " .. tostring(self.counts.ash[Gasifier.WOOD_ASH]) .. " wood ash, not 2")
        T.expect(self.refusals.short == "Tooltip_RenewableEnergy_LittleAsh", "Clean Out Ash one short of an item: " .. tostring(self.refusals.short))
        T.expect(self.refusals.enough == nil, "Clean Out Ash with an item's worth: " .. tostring(self.refusals.enough))
    end,
})

-- A cold gasifier takes bellows to light; one just put out doesn't, nor one out a little less than
-- it stays warm, while one out a little longer is cold again.
test("renewable_energy_gas_gasifier_cold_start", {
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
        local step = 0.05
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

-- Condensate drained hot goes only into metal, glass or cookware; a pot takes what it holds.
test("renewable_energy_gas_gasifier_drain_condensate", {
    instant = true,
    run = function(self)
        local gasifier = T.placeRecord(self, "gasifier", "primitive")
        if not gasifier then return end
        self.condensate = 2
        T.batch(function()
            T.setRecord(self, gasifier, { lit = true, fireKg = 5, condensate = self.condensate })
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
    T.craftTest("renewable_energy_gas_vinegar_" .. T.snake(recipe), {
        recipe = "RenewableEnergy_MakeVinegar" .. recipe,
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
        counts = { [spray] = 1, ["Base.GardeningSprayEmpty"] = 0 },
    })
end

-- The build menu's own path builds a working gasifier of `tier` from its entity's recipe, which
-- takes its materials and keeps its tools: the primitive one from a drilled strainer, its hearth
-- lined with cement; the advanced one with its fired brick lining.
local function buildsGasifier(tier, entity, prefer)
    return {
        instant = true,
        run = function(self)
            T.buildRecord(self, "gasifier", entity, Sprites.gasifier[tier], prefer)
        end,
        validate = function(self)
            local built = self.reads.built or {}
            T.expect(built.tier == tier, "the build menu built " .. tostring(built.tier))
            T.expectBuilt(self, Sprites.gasifier[tier])
        end,
    }
end

test("renewable_energy_gas_build_primitive_gasifier", buildsGasifier("primitive", "Base.RenewableEnergy_PrimitiveGasifier",
    { "Base.Strainer" }))
test("renewable_energy_gas_build_gasifier", buildsGasifier("standard", "Base.RenewableEnergy_Gasifier"))
test("renewable_energy_gas_build_advanced_gasifier", buildsGasifier("advanced", "Base.RenewableEnergy_AdvancedGasifier"))
