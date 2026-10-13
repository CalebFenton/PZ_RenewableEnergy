require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "TimedActions/ISInventoryTransferAction"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/Gadgets/SolarCellCharger"
require "RenewableEnergy/Gadgets/SolarGardenLight"

-- Power tests: the sun model against measured insolation, and banks charging, powering,
-- cutting out, wiring parts in and wearing, and the game's clock driving banks and gadgets.
-- Single player runs the server's bank system in the same Lua state, so the tests drive banks
-- through the same perform() and OnClientCommand a server runs, and check what reaches the
-- client's copy. Server Lua (RenewableEnergy.Loads, RenewableEnergy.Bank) loads after client
-- Lua, so tests look it up when they run. See RenewableEnergyTestLib.lua for the runner and the
-- helpers.

local T = RenewableEnergyTest
local test, expect, expectNear, player = T.test, T.expect, T.expectNear, T.player
local Specs, Sprites, Sun = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun
local Battery, Wear, PowerBank = RenewableEnergy.Battery, RenewableEnergy.Wear, RenewableEnergy.PowerBank
local SolarMaintainer, SolarCellCharger = RenewableEnergy.SolarMaintainer, RenewableEnergy.SolarCellCharger
local SolarGardenLight = RenewableEnergy.SolarGardenLight

local FRIDGE = "appliances_refrigeration_01_0"
local MINI_FRIDGE = "appliances_refrigeration_01_25"
local CLEAR = Sun.CLEAR_WEATHER

-- Sun ------------------------------------------------------------------------------------

-- Light on each mount summed over a year at latitude 38, with a mix of clear, broken and
-- overcast days standing in for Kentucky's weather.
local function yearTotals(months)
    local mix = { { 0.4, 0 }, { 0.3, 0.5 }, { 0.3, 1 } }
    local mounts = { flat = { "flat" }, rack = { "rack", "S" }, wall = { "wall", "S" } }
    local totals = { flat = 0, rack = 0, wall = 0 }
    local step = 0.25
    for day = 1, 365 do
        local month = math.min(12, math.floor((day - 1) / 30.42) + 1)
        if not months or months[month] then
            for hour = -12, 12 - step, step do
                local sun = Sun.position(day, hour, 38)
                for name, mount in pairs(mounts) do
                    for _, part in ipairs(mix) do
                        local weather = { cloud = part[2], fog = 0, rain = 0, snowing = false, groundSnow = 0 }
                        totals[name] = totals[name] + part[1] * Sun.planeIrradiance(sun, mount[1], mount[2], weather) * step
                    end
                end
            end
        end
    end
    return totals
end

-- Over a year, a flat panel and a south wall make what Louisville's measured insolation says
-- they make against a 38° rack, and the wall beats the flat panel in December. The measurements
-- are the 1961-1990 NSRDB monthly averages of Sandia/NREL station 93821 (latitude 38.18°): 4.11
-- kWh/m²/day flat and 2.96 on a south wall, against 4.59 at a 38° tilt.
test("renewable_energy_power_sun_year_matches_measured_insolation", {
    run = function(self)
        self.year = yearTotals(nil)
        self.december = yearTotals({ [12] = true })
    end,
    validate = function(self)
        local year, december = self.year, self.december
        expectNear("flat / rack over a year", year.flat / year.rack, 0.90, 0.04)
        expectNear("south wall / rack over a year", year.wall / year.rack, 0.64, 0.04)
        expectNear("rack kWh/m² a day in clear-to-overcast weather", year.rack / 365 / 1000, 4.6, 0.8)
        expect(december.wall > december.flat, "a south wall makes less than a flat panel in December")
    end,
})

-- The sun stands at 90 - 38 + 23.44 degrees at noon on the June solstice, sits on the horizon
-- at the end of the half day, and makes nothing at night. The game's own dawn is sunrise.
test("renewable_energy_power_sun_noon_dawn_night", {
    run = function(self)
        local solstice = 172
        self.noon = math.deg(math.asin(Sun.position(solstice, 0, 38).up))
        local halfDay = Sun.halfDayHours(solstice, 38)
        self.sunset = Sun.position(solstice, halfDay, 38).up
        self.night = Sun.planeIrradiance(Sun.position(solstice, 12, 38), "flat", nil, CLEAR)
        local season = getClimateManager():getSeason()
        local hoursSinceDawn = getGameTime():getTimeOfDay() - season:getDawn()
        self.dawn = Sun.positionNow(hoursSinceDawn).up
        self.noonWatts = Sun.planeIrradiance(Sun.position(solstice, 0, 38), "flat", nil, CLEAR)
    end,
    validate = function(self)
        expectNear("noon elevation on the solstice", self.noon, 75.44, 0.1)
        expectNear("sun height at sunset", self.sunset, 0, 0.001)
        expectNear("light at midnight", self.night, 0, 0)
        expectNear("sun height at the game's dawn", self.dawn, 0, 0.01)
        expect(self.noonWatts > 900 and self.noonWatts < 1000, "noon light on a flat panel is " .. self.noonWatts .. " W/m²")
    end,
})

-- Overcast leaves a quarter of the light, all of it diffuse, so it costs a tilted rack less.
test("renewable_energy_power_sun_clouds", {
    run = function(self)
        local sun = Sun.position(172, 0, 38)
        local overcast = { cloud = 1, fog = 0, rain = 0, snowing = false, groundSnow = 0 }
        self.flat = Sun.planeIrradiance(sun, "flat", nil, overcast) / Sun.planeIrradiance(sun, "flat", nil, CLEAR)
        self.rack = Sun.planeIrradiance(sun, "rack", "S", overcast) / Sun.planeIrradiance(sun, "rack", "S", CLEAR)
    end,
    validate = function(self)
        expectNear("overcast / clear on a flat panel", self.flat, 0.25, 0.005)
        expect(self.rack < self.flat, "clouds cost a rack less than a flat panel")
    end,
})

-- The Sunlight Multiplier scales what a panel makes, snow on it blocks it, and a roof over a
-- square leaves a garden light's cell nothing.
test("renewable_energy_power_sunlight_multiplier_and_snow", {
    sandbox = { SunlightMultiplier = 1 },
    run = function(self)
        self.real = Sun.wattsFrom(50, 1000, 0)
        T.setSandbox(self, "SunlightMultiplier", 3)
        self.boosted = Sun.wattsFrom(50, 1000, 0)
        self.snowed = Sun.wattsFrom(50, 1000, 1)
        self.indoors = Sun.squareWatts(nil, 50)
    end,
    validate = function(self)
        -- 50 W at full sun less 20% system losses.
        expectNear("a 50 W module at 1000 W/m² and x1", self.real, 40, 0.01)
        expectNear("the same at x3", self.boosted, 120, 0.01)
        expectNear("the same under snow", self.snowed, 0, 0)
        expectNear("a cell with no square", self.indoors, 0, 0)
    end,
})

-- Batteries ------------------------------------------------------------------------------

test("renewable_energy_power_battery_wear", {
    sandbox = { BatteryWear = 100 },
    run = function(self)
        local deepCycle = Specs.batteries["RenewableEnergy.DeepCycleBattery"]
        self.deepAt80 = 1 / Battery.cycleWear(deepCycle, 0.8)
        local battery = T.need(self, instanceItem("Base.CarBattery1"), "a Base.CarBattery1")
        if not battery then return end
        local car = Specs.batteries["Base.CarBattery1"]
        -- Four days at 50%: 1.25 points a day for a car battery's 80 cycles.
        for _ = 1, 4 do
            Battery.wear(battery, Battery.cycleWear(car, 0.5))
        end
        self.condition = battery:getCondition()
        -- A repair starts afresh: the quarter point still pending is forgotten.
        Battery.wear(battery, Battery.cycleWear(car, 0.5) * 0.6)
        Wear.setCondition(battery, 60)
        Battery.wear(battery, Battery.cycleWear(car, 0.5) * 0.6)
        self.repaired = battery:getCondition()
    end,
    validate = function(self)
        expect(self.deepAt80 > 300 and self.deepAt80 < 450, "a deep-cycle battery lasts " .. tostring(self.deepAt80) .. " cycles at 80%")
        expectNear("car battery condition after four 50% days", self.condition, 95, 0)
        expectNear("condition after a repair and less than a point of wear", self.repaired, 60, 0)
    end,
})

-- Banks in the world ---------------------------------------------------------------------

local function switchOn(bank)
    return PowerBank.perform(player(), "setBankOn", { bank = PowerBank.positionOf(bank), on = true })
end

-- Wh stored in the bank.
local function storedWh(record)
    return record.charge * record.nominalWh
end

local function loadOf(names)
    local Loads = RenewableEnergy.Loads
    local load = Loads.new()
    for _, name in ipairs(names) do
        Loads.add(load, name)
    end
    return load
end

-- A placed bank is a registered generator, off until switched on, whose container refuses every
-- transfer in and out: parts go in and come out only by being wired. Other transfers still work.
test("renewable_energy_power_bank_container_refuses_transfers", {
    instant = true,
    run = function(self)
        local p = player()
        self.bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" })
        if not self.bank then return end
        local container = self.bank:getContainer()
        self.allowsBattery = container:isItemAllowed(instanceItem("Base.CarBattery2"))
        self.battery = container:getFirstType("Base.CarBattery1")
        local dragOut = ISInventoryTransferAction:new(p, self.battery, container, p:getInventory())
        self.dragValid = dragOut:isValid()
        ISTimedActionQueue.add(dragOut)
    end,
    validate = function(self)
        local p = player()
        expect(PowerBank.isBank(self.bank), "the placed bank is not a bank")
        expect(not self.bank:isActivated(), "a bank that was never switched on powers its area")
        expect(not self.allowsBattery, "a battery can be dropped into a bank without wiring it in")
        expect(not self.dragValid, "moving a wired battery out of the bank is a valid transfer")
        expect(self.bank:getContainer():contains(self.battery) and not p:getInventory():contains(self.battery),
            "a wired battery was dragged out of the bank")
        local bag = p:getInventory():AddItem("Base.Bag_Schoolbag")
        local hammer = p:getInventory():AddItem("Base.Hammer")
        expect(ISInventoryTransferAction:new(p, hammer, p:getInventory(), bag:getInventory()):isValid(),
            "moving a hammer into a bag is refused too")
    end,
})

-- Banks stand indoors only: placement is refused outdoors, and a bank found outdoors won't
-- switch on.
test("renewable_energy_power_bank_refused_outdoors", {
    run = function(self)
        T.setGrid(self, false)
        local indoor = T.need(self, T.squares(self, 1, { indoors = true }), "a free indoor square")
        local outdoor = T.need(self, T.squares(self, 1), "a free outdoor square")
        if not (indoor and outdoor) then return end
        self.indoorOk = PowerBank.canPlaceBank(indoor[1])
        self.outdoorOk, self.reason = PowerBank.canPlaceBank(outdoor[1])
        local bank, record = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" },
            { square = outdoor[1] })
        if not bank then return end
        switchOn(bank)
        self.outdoorPowered = bank:isActivated()
        self.state = record.status.state
    end,
    validate = function(self)
        expect(self.indoorOk, "a bank is refused inside a building")
        expect(not self.outdoorOk and self.reason == "Tooltip_RenewableEnergy_BankIndoorsOnly",
            "a bank may stand outdoors (reason " .. tostring(self.reason) .. ")")
        expect(not self.outdoorPowered and self.state == "outdoors", "a bank outdoors switched on (state " .. tostring(self.state) .. ")")
    end,
})

-- Noon on a connected panel charges the bank by what the panel makes, and the batteries carry
-- the charge.
test("renewable_energy_power_panel_charges_bank", {
    run = function(self)
        local bank, record = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" }, { charge = 0.5 })
        if not bank then return end
        local panel
        panel, self.connected = T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not panel then return end
        local before = storedWh(record)
        record:update(1, T.passContext(1000))
        self.gained = storedWh(record) - before
        self.solarW = record.status.solarW
        self.fullSun = record.status.sources[1] and record.status.sources[1].fullSunPct
        local battery = bank:getContainer():getFirstType("Base.CarBattery1")
        self.batteryCharge = battery and Battery.getCharge(battery)
        self.bankCharge = record.charge
        self.source = PowerBank.bankOfSource(panel:getX(), panel:getY(), panel:getZ())
    end,
    validate = function(self)
        if not expect(self.connected, "connecting the panel failed") then return end
        -- One whole 50 W module at x3 (the default) in full sun, less 20% system losses.
        expectNear("solar watts", self.solarW, 120, 0.5)
        expectNear("Wh gained in an hour", self.gained, self.solarW, 0.5)
        expectNear("percent of full sun", self.fullSun, 100, 0)
        expectNear("the battery's charge", self.batteryCharge, self.bankCharge, 0.001)
        expect(self.source ~= nil, "bankOfSource doesn't know the panel")
    end,
})

-- A module makes its rating times its condition: a cracked module less, a homemade one at its
-- best 60%, a rack the sum of its two. The cracked panel says why it is low.
test("renewable_energy_power_module_condition_sets_watts", {
    run = function(self)
        local bank, record = T.bank(self, "batteryRackMetal", { "Base.CarBattery1", "RenewableEnergy.ChargeController" }, { charge = 0.1 })
        if not bank then return end
        local modules = {
            { { type = "RenewableEnergy.SolarModule", condition = 50 } },
            { { type = "RenewableEnergy.HomemadeSolarModule", condition = 60 } },
            { { type = "RenewableEnergy.SolarModule", condition = 100 }, { type = "RenewableEnergy.SolarModule", condition = 0 } },
        }
        local sprites = { Sprites.flat, Sprites.flat, Sprites.rack.metal.S }
        self.connected = true
        for i, sprite in ipairs(sprites) do
            local panel, connected = T.panel(self, sprite, { near = bank, modules = modules[i], connect = true })
            if not panel then return end
            self.connected = self.connected and connected
        end
        record:update(1, T.passContext(1000))
        local sources = record.status.sources
        self.cracked, self.homemade, self.rack = sources[1], sources[2], sources[3]
    end,
    validate = function(self)
        if not expect(self.connected, "connecting the panels failed") then return end
        if not expect(self.cracked and self.homemade and self.rack, "the status lists fewer than three panels") then return end
        -- 50 W modules at x3 less 20% system losses: 120 W at condition 100.
        expectNear("a module at condition 50", self.cracked.watts, 60, 0.5)
        expectNear("a homemade module at 60", self.homemade.watts, 72, 0.5)
        expectNear("a rack with a whole and a shattered module", self.rack.watts, 120, 0.5)
        expect(self.cracked.reason == "cracked", "the half-cracked panel's reason is " .. tostring(self.cracked.reason))
        expect(self.cracked.modules[1] and self.cracked.modules[1].condition == 50, "the status lost the module's condition")
    end,
})

-- A bank takes two panels with no controller and seven more per controller; a third panel is
-- refused, and panels past the slots of a controller taken out stay connected but make nothing.
test("renewable_energy_power_panel_slots", {
    run = function(self)
        local box = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" }, { charge = 0.1 })
        local batteryRack, record = T.bank(self, "batteryRackWood", { "Base.CarBattery1", "RenewableEnergy.ChargeController" },
            { charge = 0.1 })
        if not (box and batteryRack) then return end
        self.box = {}
        for i = 1, 3 do
            local panel, connected, reason = T.panel(self, Sprites.flat, { near = box, connect = true })
            if not panel then return end
            self.box[i], self.boxReason = connected, reason
        end
        local connected = 0
        for _ = 1, 3 do
            local panel, ok = T.panel(self, Sprites.flat, { near = batteryRack, connect = true })
            if not panel then return end
            connected = connected + (ok and 1 or 0)
        end
        self.rackConnected = connected
        local container = batteryRack:getContainer()
        container:Remove(container:getFirstType(Specs.controller))
        record:update(1, T.passContext(1000))
        local sources = record.status.sources
        self.slots = record.status.panelSlots
        self.third = sources[3]
        self.second = sources[2]
    end,
    validate = function(self)
        expect(self.box[1] and self.box[2], "a battery box refused its first two panels")
        expect(not self.box[3] and self.boxReason == "Tooltip_RenewableEnergy_NoPanelSlot",
            "a battery box took a third panel without a controller (" .. tostring(self.boxReason) .. ")")
        expectNear("panels a battery rack with a controller took", self.rackConnected, 3, 0)
        if not expect(self.third ~= nil, "the third panel was disconnected when the controller left") then return end
        expect(self.slots.used == 3 and self.slots.total == 2, "panel slots read " .. self.slots.used .. " of " .. self.slots.total)
        expect(self.third.watts == 0 and self.third.reason == "noController",
            "a panel past the slots makes " .. self.third.watts .. " W, reason " .. tostring(self.third.reason))
        expect(self.second.watts > 0, "a panel within the free slots stopped making power")
    end,
})

-- The bank's limit is its working inverters' ratings together. A Plug-in Inverter runs a TV and
-- a lamp, or a mini fridge, but not a full fridge.
test("renewable_energy_power_inverter_limits", {
    run = function(self)
        local _, box = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" })
        local bank, record = T.bank(self, "batteryBankWood",
            { "Base.CarBattery1", "RenewableEnergy.PowerInverter", "RenewableEnergy.PowerInverter" })
        if not (box and bank) then return end
        local limit = box:limitW()
        local function fits(names)
            return loadOf(names).watts <= limit
        end
        self.tvAndLamp = fits({ "television", "light" })
        self.miniFridge = fits({ "miniFridge" })
        self.fridge = fits({ "fridge" })
        self.fridgeFreezer = fits({ "fridgeFreezer" })
        self.twoInverters = record:limitW()
        Wear.setCondition(bank:getContainer():getFirstType("RenewableEnergy.PowerInverter"), 0)
        record:recount()
        self.oneWorking = record:limitW()
    end,
    validate = function(self)
        expect(self.tvAndLamp, "a Plug-in Inverter can't run a TV and a lamp")
        expect(self.miniFridge, "a Plug-in Inverter can't run a mini fridge")
        expect(not self.fridge and not self.fridgeFreezer, "a Plug-in Inverter runs a full fridge")
        expectNear("limit of two 600 W inverters", self.twoInverters, 1200, 0)
        expectNear("limit with one of them broken", self.oneWorking, 600, 0)
    end,
})

-- A load beyond the inverters cuts the bank's power, and the power comes back by itself once
-- the load fits again.
test("renewable_energy_power_overload_cuts_and_returns", {
    run = function(self)
        T.setGrid(self, false)
        local bank, record = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" })
        if not bank then return end
        switchOn(bank)
        T.applyLoad(record, { "television", "light" })
        self.fitting = bank:isActivated()
        T.applyLoad(record, { "television", "light", "fridge" })
        self.cut = not bank:isActivated()
        self.status = record.status
        T.applyLoad(record, { "television" })
        self.back = bank:isActivated() and not record.overloaded
    end,
    validate = function(self)
        expect(self.fitting, "a TV and a lamp didn't run on a charged bank with a Plug-in Inverter")
        expect(self.cut, "a fridge on top of them didn't cut the power")
        local status = self.status
        expect(status.overloaded and status.state == "overloaded", "the status doesn't read overloaded (state " .. tostring(status.state) .. ")")
        expectNear("load in the status", status.loadW, Specs.loads.television.watts + Specs.loads.light.watts + Specs.loads.fridge.watts, 0)
        expectNear("limit in the status", status.limitW, Specs.inverters["RenewableEnergy.PlugInInverter"].watts, 0)
        expect(self.back, "the power didn't come back once the load fit")
    end,
})

-- The scan sees what is switched on whether or not the bank powers it, so a cut bank knows when
-- the load fits again; and it tells a mini fridge from a full one.
test("renewable_energy_power_scan_sees_load_while_cut", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" })
        if not bank then return end
        local Loads = RenewableEnergy.Loads
        self.without = Loads.scan(bank:getSquare())
        local squares = T.need(self, T.squares(self, 2, { indoors = true, near = bank }), "two free indoor squares for fridges")
        if not squares then return end
        T.tile(self, squares[1], FRIDGE)
        T.tile(self, squares[2], MINI_FRIDGE)
        self.unpowered = not bank:isActivated()
        self.with = Loads.scan(bank:getSquare())
    end,
    validate = function(self)
        expect(self.unpowered, "the bank was on while scanning")
        local function count(load, kind)
            return load.kinds[kind] and load.kinds[kind].count or 0
        end
        expectNear("fridge-freezers found", count(self.with, "fridgeFreezer") - count(self.without, "fridgeFreezer"), 1, 0)
        expectNear("mini fridges found", count(self.with, "miniFridge") - count(self.without, "miniFridge"), 1, 0)
        expectNear("watts added", self.with.watts - self.without.watts, Specs.loads.fridgeFreezer.watts + Specs.loads.miniFridge.watts, 0)
    end,
})

--- A fuelled backup generator within `reach` tiles of `near`, outdoors if it can be, since a
--- running one makes a building toxic, with a failsafe beside it if asked.
local function newBackup(self, near, running, failsafe, reach)
    local square
    for _, indoors in ipairs({ false, true }) do
        local candidate = not square and (T.squares(self, 1, { indoors = indoors, near = near }) or {})[1]
        if candidate and IsoUtils.DistanceToSquared(candidate:getX(), candidate:getY(), near:getX(), near:getY()) <= reach * reach then
            square = candidate
        end
    end
    if not T.need(self, square, "a free square for a generator within " .. reach .. " tiles of the bank") then return nil end
    local backup = T.track(self, IsoGenerator.new(instanceItem("Base.Generator"), square:getCell(), square))
    backup:setConnected(true)
    backup:setFuel(10)
    backup:setCondition(100)
    if failsafe then
        T.tile(self, square, Sprites.failsafe)
    end
    if running then
        backup:setActivated(true)
    end
    return backup
end

-- Chargers charge only from the grid or a running generator other than a bank, which burns fuel
-- for them; never from the bank's own power.
test("renewable_energy_power_charger_sources", {
    sandbox = { GeneratorFuelConsumption = 0.1 },
    run = function(self)
        T.setGrid(self, false)
        local bank, record = T.bank(self, "batteryRackWood",
            { "Base.CarBattery1", "Base.CarBattery2", Specs.charger, Specs.charger, "RenewableEnergy.InverterCharger" },
            { charge = 0.2 })
        if not bank then return end
        switchOn(bank)
        record:update(1, T.passContext(0))
        self.alone = record.status.chargerW
        self.ownPower = bank:isActivated()
        local backup = newBackup(self, bank:getSquare(), true, false, SandboxVars.GeneratorTileRange - 1)
        if not backup then return end
        local fuel = backup:getFuel()
        record.charge = 0.2
        record:update(1, T.passContext(0))
        self.fromGenerator = record.status.chargerW
        self.generatorSource = record.status.chargers[1] and record.status.chargers[1].charging
        self.fuelUsed = fuel - backup:getFuel()
        T.setGrid(self, true)
        fuel = backup:getFuel()
        record:update(1, T.passContext(0))
        self.fromGrid = record.status.chargeSource
        self.gridFuel = fuel - backup:getFuel()
        self.gridPowered = bank:isActivated()
    end,
    validate = function(self)
        expectNear("charger watts with no grid or generator" .. (self.ownPower and " while the bank powers itself" or ""), self.alone, 0, 0)
        -- Two car battery chargers at 250 W and the Inverter/Charger's 1500 W.
        expectNear("charger watts from a running generator", self.fromGenerator, 2000, 0)
        expect(self.generatorSource == "generator", "a charger says it charges from " .. tostring(self.generatorSource))
        -- Vanilla bills a generator 1 unit of fuel per hour for 600 W of appliances, times the fuel
        -- consumption option: 2000 W at 0.1 burns a third of a unit an hour.
        expectNear("fuel the chargers burned in an hour", self.fuelUsed, 1 / 3, 0.001)
        expect(self.fromGrid == "grid", "with the grid on the chargers charge from " .. tostring(self.fromGrid))
        expectNear("fuel the chargers burned on grid power", self.gridFuel, 0, 0)
        expect(not self.gridPowered, "the bank ran its own generator while the grid powered its square")
    end,
})

-- At night a bank that is on powers its squares and pays its load through the inverter and the
-- inverter's own idle draw, and its status says it is draining.
test("renewable_energy_power_bank_powers_at_night", {
    run = function(self)
        T.setGrid(self, false)
        local bank, record = T.bank(self, "batteryRackWood",
            { "RenewableEnergy.L16Battery", "RenewableEnergy.L16Battery", "RenewableEnergy.InverterCharger" })
        if not bank then return end
        switchOn(bank)
        self.powered = bank:isActivated() and bank:getSquare():haveElectricity()
        T.applyLoad(record, { "fridge", "television", "light" })
        self.drawW = record:drawW()
        local before = storedWh(record)
        -- The pass measures the house's real load again.
        record:update(1, T.passContext(0))
        self.passDrawW = record.status.drawW
        self.used = before - storedWh(record)
        self.charging = record.status.charging
    end,
    validate = function(self)
        expect(self.powered, "switching on a charged bank with an inverter did not power its square")
        -- A fridge's 160 W compressor runs 40% of the time (64 W), a TV takes 65 W and a lamp 60 W:
        -- 189 W through a 90% efficient inverter is 210 W, plus the Inverter/Charger's 15 W idle.
        expectNear("draw of a fridge, a TV and a lamp", self.drawW, 225, 0.01)
        expect(self.passDrawW > 0, "the night's pass drew nothing from a bank that is on")
        expectNear("Wh used in an hour", self.used, self.passDrawW, 0.5)
        expect(self.charging.watts < 0 and self.charging.hours ~= nil, "the status doesn't say the bank is draining")
    end,
})

-- A day's deepest discharge wears the batteries when the day turns.
test("renewable_energy_power_depth_of_discharge_wears_batteries", {
    sandbox = { BatteryWear = 100 },
    run = function(self)
        local bank, record = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" })
        if not bank then return end
        record.cycleHigh = 1
        record.charge = 0.5
        record:trackCycle()
        self.depth = record.cycleDepth
        record.day = record.day and record.day - 1 or 0
        record:newDay(bank:getContainer(), record.day + 1)
        local battery = bank:getContainer():getFirstType("Base.CarBattery1")
        self.condition = battery and battery:getCondition()
        self.depthAfter = record.cycleDepth
    end,
    validate = function(self)
        expectNear("cycle depth", self.depth, 0.5, 0.0001)
        expectNear("car battery condition after a 50% day", self.condition, 99, 0)
        expectNear("cycle depth on the new day", self.depthAfter, 0, 0)
    end,
})

-- Storms crack modules by mount: wall panels never, wooden racks most, metal racks least. A
-- crack takes 30 condition, never below 0, and reaches the panel's own record.
test("renewable_energy_power_storms_crack_by_mount", {
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local Bank = RenewableEnergy.Bank
        local mounts = {
            flat = { kind = "flat" }, wall = { kind = "wall", material = "wood" },
            woodRack = { kind = "rack", material = "wood" }, metalRack = { kind = "rack", material = "metal" },
        }
        self.cracks = {}
        for name, mount in pairs(mounts) do
            local count = 0
            for _ = 1, 2000 do
                local source = { kind = mount.kind, material = mount.material,
                    modules = { { type = "RenewableEnergy.SolarModule", condition = 100 } } }
                if Bank.stormCrack(source, 20) then
                    count = count + 1
                end
            end
            self.cracks[name] = count
        end
        local nearlyGone = { kind = "flat", modules = { { type = "RenewableEnergy.SolarModule", condition = 10 } } }
        T.setSandbox(self, "StormDamageRate", 1000)
        Bank.stormCrack(nearlyGone, 1000)
        self.floor = nearlyGone.modules[1].condition
        T.setSandbox(self, "StormDamage", false)
        local sheltered = { kind = "flat", modules = { { type = "RenewableEnergy.SolarModule", condition = 100 } } }
        self.disabled = Bank.stormCrack(sheltered, 1000)
        T.setSandbox(self, "StormDamage", true)

        local bank, record = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" }, { charge = 0.5 })
        if not bank then return end
        local panel, connected = T.panel(self, Sprites.flat,
            { near = bank, modules = { { type = "RenewableEnergy.SolarModule", condition = 100 } }, connect = true })
        if not T.need(self, connected, "a panel connected to the bank") then return end
        record:update(1, T.passContext(1000, 1000))
        local modules = panel:getModData()[PowerBank.MODULES]
        self.recorded = modules and modules[1] and modules[1].condition
    end,
    validate = function(self)
        local cracks = self.cracks
        expectNear("wall panels cracked", cracks.wall, 0, 0)
        expect(cracks.woodRack > cracks.flat and cracks.flat > cracks.metalRack and cracks.metalRack > 0,
            string.format("cracks in 2000 storms of 20 hours: wooden rack %d, flat %d, metal rack %d",
                cracks.woodRack, cracks.flat, cracks.metalRack))
        expectNear("a module at 10 after a crack", self.floor, 0, 0)
        expect(not self.disabled, "a storm cracked a module with Storm Damage off")
        expectNear("the panel's recorded condition after a sure crack", self.recorded, 70, 0)
    end,
})

-- Wiring a part in takes its tool, wire and skill, and a free slot; Electricity XP comes only
-- the first time an item is ever wired in; unwiring gives back the part and the wire.
test("renewable_energy_power_wiring_parts", {
    run = function(self)
        local p = player()
        T.setPerk(self, Perks.Electricity, 2)
        local bank, record = T.bank(self, "batteryBoxWood", {})
        if not bank then return end
        local bankPosition = PowerBank.positionOf(bank)
        local inventory = p:getInventory()
        local function wire(item)
            return PowerBank.perform(p, "wireIn", { bank = bankPosition, itemId = item:getID() })
        end
        local battery = inventory:AddItem("Base.CarBattery1")
        local hammer = inventory:AddItem("Base.Hammer")
        self.hammer = select(2, wire(hammer))
        self.noTool = select(2, wire(battery))
        inventory:AddItem("Base.Wrench")
        self.noWire = select(2, wire(battery))
        inventory:AddItem(PowerBank.WIRE)
        local xp = p:getXp():getXP(Perks.Electricity)
        self.wired = wire(battery)
        self.firstXp = p:getXp():getXP(Perks.Electricity) - xp
        self.wireLeft = inventory:getCountTypeRecurse(PowerBank.WIRE)
        self.unwired = PowerBank.perform(p, "unwire", { bank = bankPosition, itemId = battery:getID() })
        self.batteryBack = inventory:contains(battery)
        self.wireBack = inventory:getCountTypeRecurse(PowerBank.WIRE)
        xp = p:getXp():getXP(Perks.Electricity)
        self.rewired = wire(battery)
        self.secondXp = p:getXp():getXP(Perks.Electricity) - xp
        inventory:AddItem("Base.Screwdriver")
        inventory:AddItems(PowerBank.WIRE, 2)
        self.skill = select(2, wire(inventory:AddItem("RenewableEnergy.InverterCharger")))
        inventory:AddItem(PowerBank.WIRE)
        self.full = select(2, wire(inventory:AddItem("Base.CarBattery2"))) == nil
            and select(2, wire(inventory:AddItem("Base.CarBattery3")))
        self.batteries = #record.batteries
    end,
    validate = function(self)
        expect(self.hammer == "Tooltip_RenewableEnergy_NotAPart", "a hammer was wired in (" .. tostring(self.hammer) .. ")")
        expect(self.noTool == "Tooltip_RenewableEnergy_NeedTool", "a battery was wired in without a wrench (" .. tostring(self.noTool) .. ")")
        expect(self.noWire == "Tooltip_RenewableEnergy_NeedWire", "a battery was wired in without wire (" .. tostring(self.noWire) .. ")")
        expect(self.wired, "wiring a battery in with a wrench and wire failed")
        expect(self.firstXp > 0, "the first wiring gave no Electricity XP")
        expectNear("wire left after wiring a battery in", self.wireLeft, 0, 0)
        expect(self.unwired and self.batteryBack, "unwiring didn't give the battery back")
        expectNear("wire back after unwiring", self.wireBack, 1, 0)
        expect(self.rewired, "wiring the battery in again failed")
        expectNear("XP for wiring the same battery again", self.secondXp, 0, 0)
        expect(self.skill == "Tooltip_RenewableEnergy_NeedSkill", "an Inverter/Charger was wired in at Electricity 2 (" .. tostring(self.skill) .. ")")
        expect(self.full == "Tooltip_RenewableEnergy_NoSlot", "a battery box took a third battery (" .. tostring(self.full) .. ")")
        expectNear("batteries in the box", self.batteries, 2, 0)
    end,
})

-- Inverters and controllers wear while the bank runs, an overload costs extra, a part at 0
-- does nothing, and Electronics Scrap repairs 10 points at Electricity 2.
test("renewable_energy_power_part_wear_and_repair", {
    run = function(self)
        T.setGrid(self, false)
        local p = player()
        local bank, record = T.bank(self, "batteryRackWood",
            { "RenewableEnergy.L16Battery", "RenewableEnergy.L16Battery", "RenewableEnergy.InverterCharger", Specs.controller })
        if not bank then return end
        local container = bank:getContainer()
        local inverter = container:getFirstType("RenewableEnergy.InverterCharger")
        local controller = container:getFirstType(Specs.controller)
        Wear.setCondition(inverter, 80)
        Wear.setCondition(controller, 80)
        switchOn(bank)
        record.overloaded = false
        record:wearParts(container, 100, 0)
        self.inverterWorn = 80 - inverter:getCondition()
        self.controllerWorn = 80 - controller:getCondition()
        Wear.setCondition(inverter, 80)
        record:wearParts(container, 0, 1)
        self.overloadWorn = 80 - inverter:getCondition()

        local bankPosition = PowerBank.positionOf(bank)
        local function repair(item)
            return select(2, PowerBank.perform(p, "repairPart", { bank = bankPosition, itemId = item:getID() }))
        end
        Wear.setCondition(inverter, 50)
        p:getInventory():AddItem(PowerBank.SCRAP)
        T.setPerk(self, Perks.Electricity, 1)
        self.unskilled = repair(inverter)
        T.setPerk(self, Perks.Electricity, 2)
        self.repaired = repair(inverter) == nil and inverter:getCondition()
        self.scrapLeft = p:getInventory():getCountTypeRecurse(PowerBank.SCRAP)
        self.noScrap = repair(inverter)
        Wear.setCondition(inverter, inverter:getConditionMax())
        p:getInventory():AddItem(PowerBank.SCRAP)
        self.whole = repair(inverter)

        Wear.setCondition(inverter, 0)
        PowerBank.perform(p, "refresh", { bank = bankPosition })
        record:powerUp()
        self.brokenLimit = record:limitW()
        self.brokenPowered = bank:isActivated()
    end,
    validate = function(self)
        expectNear("inverter condition lost in 100 hours on", self.inverterWorn, math.floor(Specs.partWear.inverterPerHour * 100), 0)
        expectNear("controller condition lost in 100 hours on", self.controllerWorn, math.floor(Specs.partWear.controllerPerHour * 100), 0)
        expectNear("inverter condition lost to one overload", self.overloadWorn, Specs.partWear.overload, 0)
        expect(self.unskilled == "Tooltip_RenewableEnergy_NeedSkill", "a part was repaired at Electricity 1 (" .. tostring(self.unskilled) .. ")")
        expectNear("condition after one scrap", self.repaired, 60, 0)
        expectNear("scrap left", self.scrapLeft, 0, 0)
        expect(self.noScrap == "Tooltip_RenewableEnergy_NeedScrap", "a part was repaired without scrap (" .. tostring(self.noScrap) .. ")")
        expect(self.whole == "Tooltip_RenewableEnergy_NoRepairNeeded", "a whole part took a repair (" .. tostring(self.whole) .. ")")
        expectNear("limit with the only inverter at 0", self.brokenLimit, 0, 0)
        expect(not self.brokenPowered, "a bank whose only inverter is broken powers its area")
    end,
})

-- A failsafe starts its backup generator when the bank runs low and stops it once it's charged.
test("renewable_energy_power_failsafe_starts_generator", {
    sandbox = { FailsafeStartCharge = 20, FailsafeStopCharge = 80 },
    run = function(self)
        T.setGrid(self, false)
        local bank, record = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" }, { charge = 0.1 })
        if not bank then return end
        local backup = newBackup(self, bank:getSquare(), false, true, 3)
        if not backup then return end
        record.on = true
        record:update(0.01, T.passContext(0))
        self.started = backup:isActivated()
        self.failsafe = record.status.generator and record.status.generator.failsafe
        record.charge = 0.9
        record:writeBatteries(bank:getContainer(), false)
        record:update(0.01, T.passContext(0))
        self.stopped = not backup:isActivated()
    end,
    validate = function(self)
        expect(self.failsafe, "the bank didn't find the failsafe generator")
        expect(self.started, "the failsafe didn't start the generator at 10% charge")
        expect(self.stopped, "the failsafe didn't stop the generator at 90% charge")
    end,
})

-- Clients send commands through OnClientCommand, which must survive bad arguments and refuse
-- what the world doesn't allow; the status it sends reaches the client's copy of the bank.
test("renewable_energy_power_commands_from_clients", {
    run = function(self)
        local p = player()
        local bank, record = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" })
        if not bank then return end
        local panel = T.panel(self, Sprites.rack.wood.S, { near = bank, connect = true })
        if not panel then return end
        local system = PowerBank.serverSystem
        self.position = PowerBank.positionOf(bank)
        system:OnClientCommand("noSuchCommand", p, { bank = self.position })
        system:OnClientCommand("setBankOn", p, { bank = "nonsense" })
        system:OnClientCommand("wireIn", p, { bank = self.position, itemId = "nonsense" })
        system:OnClientCommand("rename", p, { bank = self.position, name = 7 })
        self.badSource = PowerBank.perform(p, "connectSource", { bank = self.position, source = self.position })
        self.noArgs = PowerBank.perform(p, "connectSource", nil)
        local source = record:findSource(panel:getX(), panel:getY(), panel:getZ())
        if source then source.snow = 0.8 end
        self.cleared = PowerBank.perform(p, "clearSnow", { source = PowerBank.positionOf(panel) })
        self.snow = source and source.snow
        self.disconnected = PowerBank.perform(p, "disconnectSource", { source = PowerBank.positionOf(panel) })
        self.sourcesLeft = #record.sources
        system:OnClientCommand("rename", p, { bank = self.position, name = "  Shed bank  " })
        system:OnClientCommand("setBankOn", p, { bank = self.position, on = true })
        self.serverOn = record.on
    end,
    validate = function(self)
        expect(not self.badSource, "a bank was connected to itself as a panel")
        expect(not self.noArgs, "a command without arguments succeeded")
        expect(self.cleared and self.snow == 0, "clearing snow left " .. tostring(self.snow))
        expect(self.disconnected and self.sourcesLeft == 0, "disconnecting the panel left " .. tostring(self.sourcesLeft) .. " panels")
        expect(self.serverOn, "setBankOn through OnClientCommand didn't switch the bank on")
        local client = PowerBank.clientSystem
        local copy = client and client.system:getObjectAt(self.position.x, self.position.y, self.position.z)
        local status = copy and copy:getModData().status
        expect(status and status.on == true and status.kind == "batteryBoxWood", "the client's copy of the status doesn't show the bank on")
        expect(status and status.name == "Shed bank", "the client's copy names the bank " .. tostring(status and status.name))
    end,
})

-- The status of the bank at `position` on the client's copy, which the Global Object System syncs.
local function clientStatus(position)
    local client = PowerBank.clientSystem
    local copy = client and position and client.system:getObjectAt(position.x, position.y, position.z)
    return copy and copy:getModData().status
end

-- A client renames and switches on a bank the server holds the way the bank window does, through
-- the bank system's commands (a client command packet in multiplayer), after a forged one the
-- server must shrug off. The server's record changes, and its status reaches the client's copy.
test("renewable_energy_power_commands_reach_the_server", {
    run = function(self)
        local square = (T.squares(self, 1, { indoors = true }) or {})[1]
        if not T.need(self, square, "a free indoor square for a bank") then return end
        T.server(self, "placeBank", { x = square:getX(), y = square:getY(), z = square:getZ(),
            kind = "batteryBoxWood", items = { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" } })
        T.step(function()
            self.position = self.server.placeBank
            PowerBank.command(player(), "setBankOn", { bank = "nonsense" })
            PowerBank.command(player(), "rename", { bank = self.position, name = "  Network bank  " })
            PowerBank.command(player(), "setBankOn", { bank = self.position, on = true })
        end)
        T.waitUntil(function()
            local status = clientStatus(self.position)
            return status ~= nil and status.on == true and status.name == "Network bank"
        end, 3000)
        T.server(self, "bankState", function() return self.position end)
    end,
    validate = function(self)
        local state, status = self.server.bankState, clientStatus(self.position)
        expect(state.found, "the server has no bank record at the place")
        expect(state.on, "the server's bank isn't on")
        expect(state.name == "Network bank", "the server names the bank " .. tostring(state.name))
        expect(status and status.on == true and status.kind == "batteryBoxWood", "the client's copy doesn't show the bank on")
        expect(status and status.name == "Network bank", "the client's copy names the bank " .. tostring(status and status.name))
    end,
})

-- A removed running bank leaves nothing powered and is forgotten.
test("renewable_energy_power_removed_bank_leaves_no_power", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { "RenewableEnergy.L16Battery", "RenewableEnergy.InverterCharger" })
        if not bank then return end
        local square = bank:getSquare()
        switchOn(bank)
        self.wasPowered = square:haveElectricity()
        PowerBank.remove(bank)
        self.powered = square:haveElectricity()
        self.registered = PowerBank.serverSystem:getLuaObjectOnSquare(square) ~= nil
    end,
    validate = function(self)
        expect(self.wasPowered, "the switched-on bank didn't power its square")
        expect(not self.powered, "the removed bank's square still has power")
        expect(not self.registered, "the removed bank is still registered")
    end,
})

-- The clock ------------------------------------------------------------------------------

-- The solar battery charger's watt-hours not yet a whole use of a battery (its modData key).
local CELL_CHARGER_STORED_KEY = "RenewableEnergy_storedWh"
-- How far the clock jumps. EveryTenMinutes fires on the next tick when the minute of the hour
-- lands in another ten (GameTime.update), which a jump of more than ten minutes past whole hours
-- always does; the gadget pass makes up for at most an hour.
local CLOCK_JUMP_HOURS = 1.25
-- The longest the test waits for the passes the jump sets off.
local PASS_FRAMES = 10

-- What each fixture holds: the bank's Wh, the car battery's charge, the solar battery charger's
-- Wh in its cells and toward the next use, the garden light's Wh, and the charge of the battery
-- in the arrow board's box.
local function charges(self)
    local cellWh = self.charger:getModData()[CELL_CHARGER_STORED_KEY] or 0
    for _, cell in ipairs(self.cells) do
        cellWh = cellWh + cell:getCurrentUsesFloat() * SolarCellCharger.BATTERY_WH
    end
    return {
        bank = storedWh(self.record),
        car = self.carBattery:getCurrentUsesFloat(),
        charger = cellWh,
        light = SolarGardenLight.getCharge(self.light),
        trailer = self.trailerBattery:getCurrentUsesFloat(),
    }
end

local function allCharged(self)
    if not self.before then return false end
    local now = charges(self)
    for name, before in pairs(self.before) do
        if now[name] <= before then return false end
    end
    return true
end

-- The game's clock runs the banks and the gadgets: once it moves on at noon, a bank with a
-- connected panel, a car with a maintainer, a solar battery charger holding cells, a garden
-- light and an arrow board's battery box have all charged. The live weather sets how much, so
-- this checks only that they did.
test("renewable_energy_power_clock_drives_banks_and_gadgets", {
    hour = 12,
    run = function(self)
        local bank, record = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" }, { charge = 0.5 })
        if not bank then return end
        local panel, connected = T.panel(self, Sprites.flat, { near = bank, connect = true })
        local car, carBattery = T.vehicle(self, "Base.CarNormal", { battery = "Base.CarBattery1", charge = 0.5 })
        local trailer = car and T.vehicle(self, RenewableEnergy.ArrowBoard.SCRIPT)
        local squares = T.need(self, T.squares(self, 2, { bare = true }), "two bare outdoor squares for the gadgets")
        if not (panel and T.need(self, connected, "a panel connected to the bank") and trailer and squares) then return end
        -- It may have spawned stocked; one battery, half charged, shows the panels charging.
        local box = trailer:getPartById(RenewableEnergy.ArrowBoard.BATTERY_BOX):getItemContainer()
        box:removeAllItems()
        self.trailerBattery = box:AddItem("RenewableEnergy.DeepCycleBattery")
        self.trailerBattery:setCurrentUsesFloat(0.5)
        local maintainer = player():getInventory():AddItem(SolarMaintainer.ITEM)
        if not T.need(self, SolarMaintainer.attach(player(), car, maintainer), "a maintainer on the car") then return end
        local charger = T.placeMoveable(self, squares[1], "RenewableEnergy.SolarCellCharger", Sprites.cellCharger)
        local light = T.placeMoveable(self, squares[2], SolarGardenLight.ITEM, Sprites.gardenLight.off,
            { [SolarGardenLight.CHARGE_KEY] = 0 })
        if not (charger and light) then return end
        -- An empty battery is used up and leaves its container on its next update
        -- (DrainableComboItem.update), so the cells start half charged.
        self.cells = {}
        for _ = 1, SolarCellCharger.SLOTS do
            local cell = charger:getContainer():AddItem(SolarCellCharger.BATTERY)
            cell:setCurrentUsesFloat(0.5)
            table.insert(self.cells, cell)
        end
        self.record, self.carBattery, self.charger, self.light = record, carBattery, charger, light
        -- Setting the test's hour already set off a pass for the next tick, and the car joins the
        -- cell's vehicles on the next cell update, so the clock moves on once both are done.
        T.wait(2)
        T.step(function()
            self.before = charges(self)
            T.setTime(self, getGameTime():getTimeOfDay() + CLOCK_JUMP_HOURS)
        end)
        T.waitUntil(function() return allCharged(self) end, PASS_FRAMES)
    end,
    validate = function(self)
        local before, after = self.before, charges(self)
        local function charged(name, what)
            expect(after[name] > before[name], string.format("%s didn't charge as the clock moved on (%.4f to %.4f)",
                what, before[name], after[name]))
        end
        charged("bank", "the bank with a connected panel")
        charged("car", "the car with a maintainer")
        charged("charger", "the solar battery charger")
        charged("light", "the garden light")
        charged("trailer", "the arrow board's battery box")
    end,
})
