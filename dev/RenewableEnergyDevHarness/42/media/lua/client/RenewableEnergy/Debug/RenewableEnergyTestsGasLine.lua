require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"

-- The gas line: the Gas Conversion Kit on a vanilla generator and the line that runs it on a
-- digester's or gasifier's gas (GasLine/GasKit.lua, GasLine/GasLines.lua, UI/GasKitMenu.lua), and
-- the fumes those sources fill a building with (Fumes.lua). Vanilla's own hourly bill takes the
-- fuel, as the clock moves (T.jumpClock).

local T = RenewableEnergyTest
local test = T.test

local Digester, GasKit = RenewableEnergy.Digester, RenewableEnergy.GasKit
local Gasifier, Sprites, Specs = RenewableEnergy.Gasifier, RenewableEnergy.Sprites, RenewableEnergy.Specs

-- A digester holding `gas` and making none, placed as T.placeRecord's `opts` say: not started, so
-- it neither digests nor, a dome, burns any to keep warm, and only the line takes its gas.
local function digesterWithGas(self, tile, gas, opts)
    local digester = T.placeRecord(self, "digester", tile, opts)
    if not digester then return nil end
    T.setRecord(self, digester, { gas = gas })
    return digester
end

-- A generator holding `fuel` litres beside a digesterWithGas, kitted and on a line to it: the
-- generator's handle and the digester's, or nil.
local function generatorOnDigester(self, tile, gas, fuel)
    local digester = digesterWithGas(self, tile, gas)
    local generator = digester and T.generator(self, { near = digester.square, fuel = fuel })
    if not generator then return nil end
    T.fitAndConnect(self, generator, digester)
    return generator, digester
end

-- What the clock tests that run a generator dry have vanilla bill it, in shares of the fuel it shows
-- on gas: past that, so vanilla stops it, and little enough past for a dome's gas to pay.
local DRY_BILL = 1.1

-- The inverter with a charger the banks of the real-load stall test hold, and how many banks: their
-- chargers alone carry a line's whole cap, so beside any appliance the cap limits what they draw.
local BANK_CHARGER = "RenewableEnergy.InverterCharger"
local CHARGING_BANKS = math.ceil(GasKit.CAP_W / Specs.inverters[BANK_CHARGER].chargerWatts)
-- A mini fridge with its ice box, which vanilla bills as a fridge-freezer (Loads).
local MINI_FRIDGE = "appliances_refrigeration_01_25"

-- Queues setting the GeneratorFuelConsumption option so that vanilla bills `generator` (the read
-- `label`, T.readGenerator) DRY_BILL times the fuel it shows on gas over `hours`. The read's bill has
-- the option as it was applied.
local function billDryOver(self, label, hours)
    T.step(function()
        local option = SandboxVars.GeneratorFuelConsumption
        local perHour = self.reads[label].bill / option
        T.setSandbox(self, "GeneratorFuelConsumption", DRY_BILL * GasKit.PHANTOM_FUEL / (hours * perHour))
    end)
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

-- In the dark the kit can't be fitted: the menu greys Install out saying so, and the action, the
-- rule since a server can't tell whether a remote player stands in the dark, won't start.
test("renewable_energy_gasline_kit_refused_in_the_dark", {
    run = function(self)
        local generator = T.generator(self, {})
        if not generator then return end
        self.generator = generator
        T.give(self, "tools", { { type = GasKit.ITEM }, { type = "Base.Wrench" } })
        T.setPerk(self, Perks.Mechanics, 2)
        T.step(function() T.standNextTo(generator.square) end)
        T.makeDark(self)
    end,
    validate = function(self)
        local p = T.player()
        if not T.expect(p:tooDarkToRead(), "midnight with the grid off isn't dark where the character stands") then return end
        local generator = self.generator.object
        local submenu, context = T.worldSubmenu(generator, getText("ContextMenu_Generator"))
        local install = submenu and submenu:getOptionFromName(getText("ContextMenu_RenewableEnergy_InstallKit"))
        local reason = T.tooltipOf(install)
        T.expect(install ~= nil and install.notAvailable and reason == getText("Tooltip_RenewableEnergy_TooDark"),
            "Install isn't offered greyed out saying it's too dark (" .. tostring(reason) .. ")")
        if context then
            context:hideAndChildren()
        end
        T.expect(not RenewableEnergyGasAction:new(p, "kit", GasKit.INSTALL, generator):isValid(), "the Install action runs in the dark")
    end,
})

-- Running on gas ----------------------------------------------------------------------------------

-- On a digester's line an empty-tanked generator runs: the gas pays for what vanilla bills it as the
-- hours pass and the fuel is put back, and petrol poured in goes into its tank. On petrol it runs on
-- its tank and leaves the gas; back on gas, out of gas it stops, holding only its tank, and switched
-- to petrol it says so rather than that it is out of gas. The line's hoses come back when it is cut.
test("renewable_energy_gasline_generator_runs_on_gas", {
    hour = 12,
    instant = true,
    -- Vanilla's bill follows this option; high, an hour's bill stands out from rounding.
    sandbox = { GeneratorFuelConsumption = 1 },
    run = function(self)
        self.gas, self.poured = Digester.HOLDERS.bags.capacity, 3
        local digester = digesterWithGas(self, "barrel.MetalDrum", self.gas)
        local generator = digester and T.generator(self, { near = digester.square, fuel = 0 })
        if not generator then return end
        self.generator = generator
        -- One more hose than the line takes, so the count shows what it took.
        T.give(self, "spare", { { type = GasKit.HOSE } })
        T.fitAndConnect(self, generator, digester)
        T.batch(function()
            T.readGenerator(self, generator, "connected")
            T.count(self, "connected", { GasKit.HOSE })
            T.setGenerator(self, generator, { running = true })
        end)
        T.readBill(self, generator, digester, "before")
        T.jumpClock(self, 1)
        T.waitForBill(self, generator, "before")
        T.readBill(self, generator, digester, "running")
        T.batch(function()
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
        T.kitJob(self, generator, GasKit.TO_PETROL)
        T.readGenerator(self, generator, "petrolAfterOut")
        T.step(function() self.petrolText = ISGeneratorInfoWindow.getRichText(generator.object, true) end)
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
        local litres, hours = T.vanillaBill(self, "before", "running")
        T.expect(hours >= 1, "the clock moved on " .. hours .. " whole hours, not one")
        T.expectNear("gas paying for vanilla's bill of " .. litres .. " L over " .. hours .. " hours",
            reads.beforeSource.gas - reads.runningSource.gas, litres * GasKit.M3_PER_LITRE, 0.0001)
        if T.expect(poured.state ~= nil, "the generator lost its kit after pouring") then
            T.expectNear("tank after pouring", poured.state.tank, self.poured, 0.01)
        end
        T.expect(petrol.running and petrol.state ~= nil and not petrol.state.onGas, "switched to petrol, it doesn't run on its tank")
        T.expectNear("fuel on petrol", petrol.fuel, self.poured, 0.05)
        T.expectNear("gas burned on petrol", reads.afterPetrol.gas, reads.beforePetrol.gas, 0.001)
        T.expect(not out.running and out.state ~= nil and out.state.outOfGas, "the generator kept running with no gas")
        T.expectNear("fuel once the gas ran out", out.fuel, self.poured, 0.05)
        local afterOut = reads.petrolAfterOut.state
        T.expect(afterOut ~= nil and not afterOut.outOfGas, "switched to petrol, the generator still says it is out of gas")
        local text = self.petrolText or ""
        T.expect(text:find(getText("IGUI_RenewableEnergy_GasPetrol"), 1, true) ~= nil
            and text:find(getText("IGUI_RenewableEnergy_GasOut"), 1, true) == nil,
            "switched to petrol once out of gas, the info window doesn't say it runs on petrol")
        T.expect(self.counts.cut[GasKit.HOSE] == hoses + 1, "cutting the line left " .. tostring(self.counts.cut[GasKit.HOSE]) .. " hoses")
    end,
})

-- Vanilla stops a generator whose hourly bill takes all the fuel it shows on gas, an hour's or many
-- at once; the next gas pass bills those hours to the gas and it runs on.
test("renewable_energy_gasline_generator_runs_on_past_vanilla_stop", {
    hour = 12,
    instant = true,
    run = function(self)
        self.hours = 2
        local generator, digester = generatorOnDigester(self, "dome", Digester.HOLDERS.dome.capacity, 0)
        if not generator then return end
        T.setGenerator(self, generator, { running = true })
        T.readGenerator(self, generator, "bill")
        billDryOver(self, "bill", self.hours)
        T.readBill(self, generator, digester, "before")
        T.jumpClock(self, self.hours)
        T.waitForBill(self, generator, "before")
        T.readGenerator(self, generator, "billed")
        T.readBill(self, generator, digester, "after")
    end,
    validate = function(self)
        local reads = self.reads
        local litres, hours = T.vanillaBill(self, "before", "after")
        T.expect(hours == self.hours, "the clock moved on " .. hours .. " whole hours, not " .. self.hours)
        T.expect(litres > GasKit.PHANTOM_FUEL, "a bill of " .. litres .. " L doesn't run the fuel shown on gas dry")
        T.expect(not reads.billed.running, "vanilla's bill past the fuel shown didn't stop the generator, so this tests nothing")
        local after = reads.after
        T.expect(after.running and after.state ~= nil and not after.state.outOfGas,
            "stopped by vanilla's bill with gas in the line, the generator didn't run on")
        T.expectNear("fuel shown once it runs on", after.fuel, GasKit.PHANTOM_FUEL, 0.01)
        T.expectNear("gas paying for vanilla's bill of " .. litres .. " L over " .. hours .. " hours",
            reads.beforeSource.gas - reads.afterSource.gas, litres * GasKit.M3_PER_LITRE, 0.001)
    end,
})

-- The same while the generator's chunk is unloaded: vanilla bills every hour away at once when it
-- loads, and the gas pays for them. Single player only: a multiplayer server keeps the chunk loaded
-- after the character leaves.
test("renewable_energy_gasline_generator_runs_on_after_absence", {
    spOnly = "the server keeps chunks loaded after the character leaves",
    timeoutSeconds = 120,
    hour = 12,
    instant = true,
    run = function(self)
        self.hours = 2
        local stand = T.square(self, nil, "a free outdoor square to stand on")
        local digester = stand and digesterWithGas(self, "dome", Digester.HOLDERS.dome.capacity, { near = stand, minDistance = 2 })
        local generator = digester and T.generator(self, { near = digester.square, fuel = 0 })
        if not generator then return end
        T.server(self, "generatorTrack", T.at(generator))
        T.fitAndConnect(self, generator, digester)
        T.setGenerator(self, generator, { running = true })
        T.readGenerator(self, generator, "bill")
        billDryOver(self, "bill", self.hours)
        T.readBill(self, generator, digester, "before")
        T.awayAndBack(self, T.at(stand), generator.x, generator.y, generator.z, function()
            T.jumpClock(self, self.hours)
        end)
        T.waitForBill(self, generator, "before")
        T.readBill(self, generator, digester, "after")
    end,
    validate = function(self)
        local reads = self.reads
        local litres, hours = T.vanillaBill(self, "before", "after")
        T.expect(hours == self.hours, "the clock moved on " .. hours .. " whole hours, not " .. self.hours)
        T.expect(litres > GasKit.PHANTOM_FUEL, "a bill of " .. litres .. " L doesn't run the fuel shown on gas dry")
        local after = reads.after
        T.expect(after.running and after.state ~= nil and not after.state.outOfGas,
            "back after its chunk was away, the generator stopped with gas in the line")
        T.expectNear("gas paying for vanilla's bill of " .. litres .. " L over " .. hours .. " hours away",
            reads.beforeSource.gas - reads.afterSource.gas, litres * GasKit.M3_PER_LITRE, 0.001)
    end,
})

-- A job at a kitted generator first bills the fuel burned since the last pass to the fuel it
-- burned on: Run on Petrol bills the gas for what burned on gas, Run on Gas leaves what burned on
-- petrol to the tank. The fuel is taken by hand: the clock moving would also run a gas pass, which
-- could bill it before the job does.
test("renewable_energy_gasline_job_bills_the_fuel_before_it", {
    instant = true,
    run = function(self)
        self.gas, self.tank = Digester.HOLDERS.bags.capacity, 1
        self.litres = self.tank / 5
        local generator, digester = generatorOnDigester(self, "barrel.MetalDrum", self.gas, self.tank)
        if not generator then return end
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
            reads.onGas.gas - reads.onPetrol.gas, self.litres * GasKit.M3_PER_LITRE, 0.001)
        T.expectNear("tank once on petrol", reads.generatorOnPetrol.fuel, self.tank, 0.01)
        T.expectNear("gas billed for the " .. self.litres .. " L burned on petrol", reads.onPetrol.gas - reads.backOnGas.gas, 0, 0.001)
        local backOnGas = reads.generatorBackOnGas
        if T.expect(backOnGas.state ~= nil, "the generator lost its kit") then
            T.expectNear("tank back on gas", backOnGas.state.tank, self.tank - self.litres, 0.01)
        end
    end,
})

-- A load past what the line carries stalls the generator, at exactly that it runs, and once the
-- load fits again it starts by itself. Cutting the line while stalled forgets the stall, so a new
-- line doesn't start it. The loads are made up (gasLoad): no set of appliances adds up to exactly
-- the cap; renewable_energy_gasline_generator_stalls_on_real_load measures a real one.
test("renewable_energy_gasline_generator_stalls_over_cap", {
    instant = true,
    run = function(self)
        local generator, digester = generatorOnDigester(self, "dome", Digester.HOLDERS.dome.capacity, 0)
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
        T.expect(not over.running and over.state ~= nil and over.state.stalled, "a watt over its cap didn't stall it")
        T.expect(fits.running and fits.state ~= nil and not fits.state.stalled, "the generator didn't start again once the load fit")
        T.expect(reads.stalled.state ~= nil and reads.stalled.state.stalled, "a watt over its cap didn't stall it again")
        T.expect(reads.cut.state ~= nil and not reads.cut.state.stalled, "cutting the line left the generator stalled")
        T.expect(not reads.reconnected.running, "a new line started a generator stalled on the line before")
    end,
})

-- The test's bank handles `banks` in the order a generator on gas shares its cap between them:
-- nearest first, the lower place on a tie (GasLines.lua's chargingBanks).
local function shareOrder(generator, banks)
    local order = {}
    for _, bank in ipairs(banks) do
        local p = bank.position
        local dx, dy, dz = p.x - generator.x, p.y - generator.y, p.z - generator.z
        table.insert(order, { bank = bank, distance = dx * dx + dy * dy + dz * dz,
            key = RenewableEnergy.PlaceTracker.key(p.x, p.y, p.z) })
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
        local generator = generatorOnDigester(self, "dome", Digester.HOLDERS.dome.capacity, 0)
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
        T.expect(not overloaded.running and overloaded.state.stalled, "fridges past the cap didn't stall the generator")
        for i, bank in ipairs(self.banks) do
            T.expectNear("bank " .. i .. "'s charge with the cap taken", self.drawn.overloaded[bank].watts or -1, 0, 0)
        end
    end,
})

-- The server builds a gas action only from a feature and a job there are: a client could send any.
test("renewable_energy_gasline_unknown_job_refused", {
    run = function(self)
        local generator = T.generator(self, { fuel = 0 })
        if not generator then return end
        local function build(label, feature, job)
            local args = T.at(generator)
            args.feature, args.job = feature, job
            T.read(self, "gasActionFrom", args, label)
        end
        build("known", "kit", GasKit.INSTALL)
        build("noFeature", "NoSuchFeature", GasKit.INSTALL)
        build("noJob", "kit", "NoSuchJob")
    end,
    validate = function(self)
        local reads = self.reads
        T.expect(reads.known.built, "the server built no action for Install Kit")
        T.expect(not reads.noFeature.built, "the server built an action for a feature there is none of")
        T.expect(not reads.noJob.built, "the server built an action for a job the kit hasn't")
    end,
})

-- A kit job whose work isn't done on the authority takes nothing and teaches nothing: a job takes
-- what it takes, and gives its XP, only once done. Install Kit takes the kit and gives XP.
test("renewable_energy_gasline_kit_job_not_done_takes_nothing", {
    instant = true,
    run = function(self)
        local generator = T.generator(self, { fuel = 0 })
        if not generator then return end
        self.install = GasKit.materials(GasKit.INSTALL)
        T.giveMaterials(self, "kit", self.install)
        T.batch(function()
            T.server(self, "kitJobNotDone", { job = GasKit.INSTALL })
            T.read(self, "perkXp", { perk = "Mechanics" }, "before")
        end)
        T.goNextTo(self, generator.square)
        local args = T.at(generator)
        args.job = GasKit.INSTALL
        T.read(self, "kitJobComplete", args, "complete")
        T.batch(function()
            T.readGenerator(self, generator, "after")
            T.countMaterials(self, "after", self.install)
            T.read(self, "perkXp", { perk = "Mechanics" }, "afterXp")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        T.expect(reads.complete.done == false, "Install Kit counted as done though its work wasn't")
        T.expect(reads.after.state == nil and not reads.after.listed, "the kit was fitted")
        T.expect(self.counts.after[GasKit.ITEM] == 1, "Install Kit took the kit though it wasn't done")
        T.expect(reads.afterXp.value == reads.before.value, "Install Kit gave Mechanics XP though it wasn't done: "
            .. reads.before.value .. " before, " .. reads.afterXp.value .. " after")
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

-- Vanilla keeps a building with a generator running inside toxic, so the last of the mod's sources
-- going out leaves it toxic; and a generator the gas line stops, which vanilla clears it for, leaves
-- it toxic while one of the mod's sources still fumes there.
test("renewable_energy_gasline_fumes_kept_with_a_running_generator", {
    instant = true,
    run = function(self)
        local digester = digesterWithGas(self, "barrel.MetalDrum", Digester.HOLDERS.bags.capacity, { indoors = true })
        local squares = digester and T.squares(self, 2, { indoors = true, near = digester.square, minDistance = 2 })
        if not T.need(self, squares, "two more indoor squares") then return end
        local building = digester.square:getBuilding()
        if not T.need(self, squares[1]:getBuilding() == building and squares[2]:getBuilding() == building,
            "three indoor squares in one building") then return end
        local gasifier = T.placeRecord(self, "gasifier", "primitive", { square = squares[1] })
        local generator = gasifier and T.generator(self, { square = squares[2], fuel = 0 })
        if not generator then return end
        T.fitAndConnect(self, generator, digester)
        T.batch(function()
            T.setRecord(self, gasifier, { lit = true, fireKg = Gasifier.TIERS.primitive.hopperKg })
            T.setGenerator(self, generator, { running = true })
            T.setRecord(self, gasifier, { lit = false })
            T.readRecord(self, gasifier, "gasifierOut")
            T.setRecord(self, digester, T.sourDigester("barrel"))
            -- Any load the line can't carry stalls it; how much isn't what this is about.
            T.gasLoad(self, GasKit.CAP_W + 1)
            T.gasPass(self, generator, 0.1)
            T.readGenerator(self, generator, "stalled")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        T.expect(reads.gasifierOut.toxic, "the building cleared with a generator running inside once the gasifier went out")
        local stalled = reads.stalled
        T.expect(not stalled.running and stalled.state ~= nil and stalled.state.stalled, "the generator didn't stall, so this tests nothing")
        T.expect(stalled.toxic, "the building cleared as the gas line stopped its generator, with a sour digester inside")
    end,
})
