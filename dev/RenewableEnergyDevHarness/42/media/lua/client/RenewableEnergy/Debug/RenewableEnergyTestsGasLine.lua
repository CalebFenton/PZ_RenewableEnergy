require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"

-- The gas line: the Gas Conversion Kit on a vanilla generator and the line that runs it on a
-- digester's or gasifier's gas (GasLine/GasKit.lua, GasLine/GasLines.lua, UI/GasKitMenu.lua), and
-- the fumes those sources fill a building with (Fumes.lua). Tests take fuel through burnFuel, as
-- vanilla's bill does, and set the load through gasLoad.

local T = RenewableEnergyTest
local test = T.test

local Digester, GasKit = RenewableEnergy.Digester, RenewableEnergy.GasKit
local Gasifier, Sprites = RenewableEnergy.Gasifier, RenewableEnergy.Sprites

-- A mature digester holding `gas`, on a free square.
local function digesterWithGas(self, tile, gas)
    local digester = T.placeRecord(self, "digester", tile)
    if not digester then return nil end
    local state = T.matureDigester(tile:match("^[^.]+"))
    state.gas = gas
    T.setRecord(self, digester, state)
    return digester
end

-- Gas Conversion Kit ------------------------------------------------------------------------------

-- Fitting the kit takes it, keeps the tank and shows it on the generator; it can't come off a
-- running generator; taking it off gives it back with the tank as it was.
test("renewable_energy_gasline_kit_install_and_remove", {
    instant = true,
    run = function(self)
        self.fuel = 3
        local generator = T.generator(self, { fuel = self.fuel })
        if not generator then return end
        self.install = GasKit.materials(GasKit.INSTALL)
        T.fitKit(self, generator)
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
        T.kitJob(self, generator, GasKit.REMOVE)
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

-- A kitted generator's menu has the kit's jobs and refuses Take Generator, as the client's action
-- does; its info window shows the real tank, not the fuel the gas line shows, and that it runs on gas.
test("renewable_energy_gasline_kit_menu", {
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
        T.fitAndConnect(self, generator, digester)
        T.waitFor(self, function()
            local state = GasKit.stateOf(generator.object)
            return state ~= nil and state.onGas == true and generator.object:getFuel() > 0
        end, "this client's copy of the generator on gas")
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
        local shown = getText("IGUI_Generator_FuelAmount", math.ceil(generator:getFuelPercentage()))
        T.expect(text:find(getText("IGUI_Generator_FuelAmount", 0), 1, true) ~= nil, "the info window doesn't show the empty tank")
        T.expect(text:find(shown, 1, true) == nil, "the info window shows the fuel the gas line keeps in it as its tank")
        T.expect(text:find(getText("IGUI_RenewableEnergy_GasOn"), 1, true) ~= nil, "the info window doesn't say it runs on gas")
    end,
})

-- Running on gas ----------------------------------------------------------------------------------

-- On a digester's line an empty-tanked generator runs: the gas pays for what vanilla bills it and
-- the fuel is put back, and petrol poured in goes into its tank. On petrol it runs on its tank and
-- leaves the gas; back on gas, out of gas it stops, holding only its tank. The line's hoses come
-- back when it is cut.
test("renewable_energy_gasline_generator_runs_on_gas", {
    instant = true,
    run = function(self)
        self.gas, self.poured = Digester.HOLDERS.bags.capacity, 3
        -- A bill both the gas and the fuel shown on gas cover several times over.
        self.litres = math.min(GasKit.PHANTOM_FUEL, self.gas / GasKit.M3_PER_LITRE) / 8
        local digester = digesterWithGas(self, "barrel.MetalDrum", self.gas)
        local generator = digester and T.generator(self, { near = digester.square, fuel = 0 })
        if not generator then return end
        -- One more hose than the line takes, so the count shows what it took.
        T.give(self, "spare", { { type = GasKit.HOSE } })
        T.fitAndConnect(self, generator, digester)
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
        T.kitJob(self, generator, GasKit.TO_PETROL)
        T.batch(function()
            T.readRecord(self, digester, "beforePetrol")
            T.gasPass(self, generator, 0.5)
            T.readGenerator(self, generator, "petrol")
            T.readRecord(self, digester, "afterPetrol")
        end)
        T.kitJob(self, generator, GasKit.TO_GAS)
        T.batch(function()
            T.setRecord(self, digester, { gas = 0 })
            T.gasPass(self, generator, 0.5)
            T.readGenerator(self, generator, "out")
        end)
        T.kitJob(self, generator, GasKit.DISCONNECT)
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

-- A job at a kitted generator first bills the fuel burned since the last pass to the fuel it
-- burned on: Run on Petrol bills the gas for what burned on gas, Run on Gas leaves what burned on
-- petrol to the tank.
test("renewable_energy_gasline_job_bills_the_fuel_before_it", {
    instant = true,
    run = function(self)
        self.gas, self.tank = Digester.HOLDERS.bags.capacity, 1
        self.litres = self.tank / 5
        local digester = digesterWithGas(self, "barrel.MetalDrum", self.gas)
        local generator = digester and T.generator(self, { near = digester.square, fuel = self.tank })
        if not generator then return end
        T.fitAndConnect(self, generator, digester)
        T.batch(function()
            T.setGenerator(self, generator, { running = true })
            T.gasPass(self, generator, 0)
            T.readRecord(self, digester, "onGas")
            T.burnFuel(self, generator, self.litres)
        end)
        T.kitJob(self, generator, GasKit.TO_PETROL)
        T.batch(function()
            T.readRecord(self, digester, "onPetrol")
            T.readGenerator(self, generator, "generatorOnPetrol")
            T.burnFuel(self, generator, self.litres)
        end)
        T.kitJob(self, generator, GasKit.TO_GAS)
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

-- A load past what the line carries stalls the generator, at exactly that it runs, and once the
-- load fits again it starts by itself. Cutting the line while stalled forgets the stall, so a new
-- line doesn't start it.
test("renewable_energy_gasline_generator_stalls_over_cap", {
    instant = true,
    run = function(self)
        local digester = digesterWithGas(self, "dome", Digester.HOLDERS.dome.capacity)
        local generator = digester and T.generator(self, { near = digester.square, fuel = 0 })
        if not generator then return end
        T.fitAndConnect(self, generator, digester)
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
        T.expect(not over.running and over.state ~= nil and over.state.stalled, "a watt over its cap didn't stall it")
        T.expect(fits.running and fits.state ~= nil and not fits.state.stalled, "the generator didn't start again once the load fit")
        T.expect(reads.stalled.state ~= nil and reads.stalled.state.stalled, "a watt over its cap didn't stall it again")
        T.expect(reads.cut.state ~= nil and not reads.cut.state.stalled, "cutting the line left the generator stalled")
        T.expect(not reads.reconnected.running, "a new line started a generator stalled on the line before")
    end,
})

-- Gasifier lines ----------------------------------------------------------------------------------

-- A gasifier's line connects only to one right beside the generator, not on a corner.
test("renewable_energy_gasline_gasifier_must_stand_beside", {
    instant = true,
    run = function(self)
        local generator = T.generator(self, { fuel = 0 })
        if not generator then return end
        local side = T.need(self, T.squareBeside(generator.square), "a free square beside the generator")
        local corner = side and T.need(self, T.squareBeside(generator.square, true), "a free square on a corner of the generator")
        local beside = corner and T.placeRecord(self, "gasifier", "primitive", { square = side })
        local diagonal = beside and T.placeRecord(self, "gasifier", "primitive", { square = corner })
        if not diagonal then return end
        T.fitKit(self, generator)
        T.step(function()
            T.giveMaterials(self, "line", GasKit.materials(GasKit.CONNECT, generator.object, beside.object))
        end)
        T.step(function()
            self.beside = GasKit.refusal(T.player(), GasKit.CONNECT, generator.object, beside.object)
            self.corner = GasKit.refusal(T.player(), GasKit.CONNECT, generator.object, diagonal.object)
        end)
    end,
    validate = function(self)
        T.expect(self.beside == nil, "a gasifier beside the generator: " .. tostring(self.beside))
        T.expect(self.corner == "Tooltip_RenewableEnergy_GasifierNotBeside", "a gasifier on a corner: " .. tostring(self.corner))
    end,
})

-- A line whose gasifier is gone is lost with it while the generator runs on petrol too: no line in
-- its state, no pipe on the generator, and on this client a new line can be connected.
test("renewable_energy_gasline_line_lost_with_its_source_on_petrol", {
    instant = true,
    run = function(self)
        local generator = T.generator(self, { fuel = 3 })
        if not generator then return end
        local square = T.need(self, T.squareBeside(generator.square), "a free square beside the generator")
        local gasifier = square and T.placeRecord(self, "gasifier", "primitive", { square = square })
        if not gasifier then return end
        self.side = Gasifier.sideOf(generator.x, generator.y, gasifier.x, gasifier.y)
        T.fitAndConnect(self, generator, gasifier)
        T.kitJob(self, generator, GasKit.TO_PETROL)
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

-- Fumes -------------------------------------------------------------------------------------------

-- A building is toxic while any of the mod's sources in it fumes, a sour digester or a lit gasifier,
-- and clears only once the last stops. A digester overflowing indoors fumes for LEAK_HOURS, no longer.
test("renewable_energy_gasline_fumes_clear_with_the_last_source", {
    run = function(self)
        local digester = T.placeRecord(self, "digester", "barrel.MetalDrum", { indoors = true })
        local square = digester and T.square(self, { indoors = true, near = digester.square, minDistance = 2 }, "another indoor square")
        if not square then return end
        if not T.need(self, square:getBuilding() == digester.square:getBuilding(), "two indoor squares in one building") then return end
        local gasifier = T.placeRecord(self, "gasifier", "primitive", { square = square })
        if not gasifier then return end
        local sour = T.sourDigester("barrel")
        local overflowing = { sour = false, acid = 0, potential = 0, leakHours = 0, gas = Digester.HOLDERS.bags.capacity + 0.1 }
        -- The leak starts at the end of the pass that overflows: a step short of LEAK_HOURS after
        -- that it still leaks, a step past them it has stopped.
        local step = Digester.LEAK_HOURS / 4
        T.batch(function()
            T.setRecord(self, digester, sour)
            T.readRecord(self, digester, "sour")
            T.setRecord(self, gasifier, { lit = true, fireKg = Gasifier.TIERS.primitive.hopperKg })
            T.setRecord(self, digester, T.matureDigester("barrel"))
            T.readRecord(self, gasifier, "gasifierOnly")
            T.setRecord(self, digester, sour)
            T.setRecord(self, gasifier, { lit = false })
            T.readRecord(self, digester, "digesterOnly")
            T.setRecord(self, digester, overflowing)
            T.runDigester(self, digester, step, 30)
            T.runDigester(self, digester, Digester.LEAK_HOURS - step, 30)
            T.readRecord(self, digester, "leaking")
            T.runDigester(self, digester, 2 * step, 30)
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
