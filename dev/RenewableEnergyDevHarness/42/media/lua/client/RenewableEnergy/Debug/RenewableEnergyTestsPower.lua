require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "TimedActions/ISInventoryTransferAction"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/Wear"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/Gadgets/SolarGardenLight"

-- Power tests: the sun model against measured insolation, and banks charging, powering,
-- cutting out, wiring parts in and wearing, and the game's clock driving banks and gadgets.
-- Banks live on the authority: the fixtures build them there and the bank helpers drive and read
-- the server's record through T.server (RenewableEnergyTestServer.lua), in this game in single
-- player and on the server in multiplayer. What a client does goes through the bank system's
-- commands, and what players see is checked on this client's copies. See
-- RenewableEnergyTestLib.lua for the runner and the helpers.

local T = RenewableEnergyTest
local test, expect, expectNear, player, stateItem = T.test, T.expect, T.expectNear, T.player, T.stateItem
local Specs, Sprites, Sun = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun
local Battery, Wear, PowerBank = RenewableEnergy.Battery, RenewableEnergy.Wear, RenewableEnergy.PowerBank
local SolarGardenLight = RenewableEnergy.SolarGardenLight

local FRIDGE = "appliances_refrigeration_01_0"
local MINI_FRIDGE = "appliances_refrigeration_01_25"
local CLEAR = Sun.CLEAR_WEATHER
local PLUG_IN_INVERTER = "RenewableEnergy.PlugInInverter"

-- Weather with no fog, rain or snow, and `cloud` cover from 0 to 1.
local function cloudy(cloud)
    return { cloud = cloud, fog = 0, rain = 0, snowing = false, groundSnow = 0 }
end

-- Sun ------------------------------------------------------------------------------------

-- Light on each mount summed over a year at latitude 38, with a mix of clear, broken and
-- overcast days standing in for Kentucky's weather. One day a week at half-hour steps, each
-- standing for its week, moves the ratios by well under the tolerances below at a fraction of the
-- cost of every day at quarter hours.
local function yearTotals(months)
    local mix = { { 0.4, cloudy(0) }, { 0.3, cloudy(0.5) }, { 0.3, cloudy(1) } }
    local mounts = { flat = { "flat" }, rack = { "rack", "S" }, wall = { "wall", "S" } }
    local totals = { flat = 0, rack = 0, wall = 0 }
    local dayStep, step = 7, 0.5
    for day = 1, 365, dayStep do
        local month = math.min(12, math.floor((day - 1) / 30.42) + 1)
        if not months or months[month] then
            for hour = -12, 12 - step, step do
                local sun = Sun.position(day, hour, 38)
                for name, mount in pairs(mounts) do
                    for _, part in ipairs(mix) do
                        totals[name] = totals[name] + part[1] * Sun.planeIrradiance(sun, mount[1], mount[2], part[2]) * step * dayStep
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
        local overcast = cloudy(1)
        self.flat = Sun.planeIrradiance(sun, "flat", nil, overcast) / Sun.planeIrradiance(sun, "flat", nil, CLEAR)
        self.rack = Sun.planeIrradiance(sun, "rack", "S", overcast) / Sun.planeIrradiance(sun, "rack", "S", CLEAR)
    end,
    validate = function(self)
        expectNear("overcast / clear on a flat panel", self.flat, 0.25, 0.005)
        expect(self.rack < self.flat, "clouds cost a rack less than a flat panel")
    end,
})

-- The Sunlight Multiplier scales what a panel makes, snow on it blocks it, and a roof over a
-- square leaves a garden light's cell nothing, while out in the open at noon it makes what a flat
-- panel does: something, and no more than its rating gives in full sun. Catches the option read
-- once or not at all, and a roof check that lets light through.
test("renewable_energy_power_sunlight_multiplier_and_snow", {
    hour = 12,
    sandbox = { SunlightMultiplier = 1 },
    run = function(self)
        self.real = Sun.wattsFrom(50, 1000, 0)
        T.setSandbox(self, "SunlightMultiplier", 3)
        self.boosted = Sun.wattsFrom(50, 1000, 0)
        self.snowed = Sun.wattsFrom(50, 1000, 1)
        self.noSquare = Sun.squareWatts(nil, 50)
        local indoor = T.square(self, { indoors = true }, "a free indoor square")
        local outdoor = T.square(self, {}, "a free outdoor square")
        if not (indoor and outdoor) then return end
        self.indoors = Sun.squareWatts(indoor, 50)
        self.outdoors = Sun.squareWatts(outdoor, 50)
        self.flatWatts = Sun.panelWatts(50, "flat")
        self.fullSun = Sun.wattsFrom(50, Sun.FULL_SUN, 0)
    end,
    validate = function(self)
        expect(self.real > 0 and self.real <= 50, "a 50 W module at 1000 W/m² makes " .. self.real .. " W")
        expectNear("a module at x3 over x1", self.boosted / self.real, 3, 0.0001)
        expectNear("the same under snow", self.snowed, 0, 0)
        expectNear("a cell with no square", self.noSquare, 0, 0)
        expectNear("a cell under a roof at noon", self.indoors, 0, 0)
        expectNear("a cell in the open at noon", self.outdoors, self.flatWatts, 0.0001)
        expect(self.outdoors > 0 and self.outdoors <= self.fullSun, string.format(
            "a cell in the open at noon makes %.3f W, more than nothing and at most %.3f expected", self.outdoors, self.fullSun))
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

local INVERTER = "RenewableEnergy.InverterCharger"

-- Queues T.perform and leaves its answer in self[key].
local function perform(self, key, command, args, item)
    T.perform(self, command, args, item)
    T.step(function() self[key] = self.server.perform end)
end

-- The charge of the first `fullType` in this client's copy of the bank, or -1.
local function copyUses(bank, fullType)
    local item = T.copyItem(bank, fullType)
    return item and item:getCurrentUsesFloat() or -1
end

-- Checks that the panel fixture `panel` connected, saying why not.
local function expectConnected(panel)
    return expect(panel.connected, "connecting the panel failed (" .. tostring(panel.reason) .. ")")
end

-- The refusal reason in the command answer self[key], as a string.
local function reason(self, key)
    return tostring(self[key].reason)
end

-- A placed bank is a registered generator, off until switched on, whose container refuses every
-- transfer in and out: parts go in and come out only by being wired. Other transfers still work.
-- The filter must hold on this client's copy, where the player drags.
test("renewable_energy_power_bank_container_refuses_transfers", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" })
        if not self.bank then return end
        T.give(self, "carried", { { type = "Base.Bag_Schoolbag" }, { type = "Base.Hammer" } })
        T.bankState(self, self.bank)
        -- Last: the queue drops everything after an action that turns out invalid when it starts.
        T.step(function()
            local p, container = player(), self.bank.object:getContainer()
            self.allowsBattery = container:isItemAllowed(instanceItem("Base.CarBattery2"))
            self.battery = container:getFirstType("Base.CarBattery1")
            local dragOut = ISInventoryTransferAction:new(p, self.battery, container, p:getInventory())
            self.dragValid = dragOut:isValid()
            ISTimedActionQueue.add(dragOut)
        end)
    end,
    validate = function(self)
        local p, bank, state = player(), self.bank.object, self.bank.state
        expect(PowerBank.isBank(bank), "the placed bank is not a bank")
        expect(not bank:isActivated() and not state.activated, "a bank that was never switched on powers its area")
        expect(not self.allowsBattery, "a battery can be dropped into a bank without wiring it in")
        expect(not self.dragValid, "moving a wired battery out of the bank is a valid transfer")
        expect(stateItem(state, "Base.CarBattery1") ~= nil and bank:getContainer():contains(self.battery)
            and not p:getInventory():contains(self.battery), "a wired battery was dragged out of the bank")
        local bag, hammer = self.items.carried[1], self.items.carried[2]
        expect(ISInventoryTransferAction:new(p, hammer, p:getInventory(), bag:getInventory()):isValid(),
            "moving a hammer into a bag is refused too")
    end,
})

-- Banks stand indoors only: placement is refused outdoors, and a bank found outdoors won't
-- switch on.
test("renewable_energy_power_bank_refused_outdoors", {
    run = function(self)
        T.setGrid(self, false)
        local indoor = T.square(self, { indoors = true }, "a free indoor square")
        local outdoor = T.square(self, {}, "a free outdoor square")
        if not (indoor and outdoor) then return end
        self.indoorOk = PowerBank.canPlaceBank(indoor)
        self.outdoorOk, self.reason = PowerBank.canPlaceBank(outdoor)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER }, { square = outdoor })
        if not bank then return end
        self.bank = bank
        T.watch(self, bank)
        T.perform(self, "setBankOn", { bank = bank.position, on = true })
        T.bankState(self, bank)
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return status ~= nil and status.state == "outdoors"
        end, "this client's status of the outdoor bank saying it must go inside")
    end,
    validate = function(self)
        local state = self.bank.state
        expect(self.indoorOk, "a bank is refused inside a building")
        expect(not self.outdoorOk and self.reason == "Tooltip_RenewableEnergy_BankIndoorsOnly",
            "a bank may stand outdoors (reason " .. tostring(self.reason) .. ")")
        expect(not state.activated and state.status.state == "outdoors",
            "a bank outdoors switched on (state " .. tostring(state.status.state) .. ")")
    end,
})

-- Noon on a connected panel charges the bank by what the panel makes, the batteries carry the
-- charge, and the charge, the status and the tile's battery overlays reach this client's copies.
test("renewable_energy_power_panel_charges_bank", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" }, { charge = 0.5 })
        self.panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not self.panel then return end
        self.bank = bank
        T.watch(self, bank)
        T.bankState(self, bank)
        T.step(function() self.before = bank.state end)
        T.bankPass(self, bank, 1000)
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return math.abs(copyUses(bank, "Base.CarBattery1") - bank.state.charge) < 0.001
                and status ~= nil and status.solarW == bank.state.status.solarW
                and T.overlays(bank.object) == table.concat(bank.state.overlays, ",")
        end, "this client's copies of the charged battery, the status and the overlays")
    end,
    validate = function(self)
        if not expectConnected(self.panel) then return end
        local after = self.bank.state
        local status, here = after.status, self.panel.position
        expectNear("solar watts", status.solarW, Sun.wattsFrom(Specs.modules[Specs.factoryModule].watts, 1000, 0), 0.5)
        expectNear("Wh gained in an hour", after.storedWh - self.before.storedWh, status.solarW, 0.5)
        expectNear("percent of full sun", status.sources[1] and status.sources[1].fullSunPct, 100, 0)
        local battery = stateItem(after, "Base.CarBattery1")
        expectNear("the battery's charge", battery and battery.uses, after.charge, 0.001)
        expectNear("this client's copy of the battery's charge", copyUses(self.bank, "Base.CarBattery1"), after.charge, 0.001)
        local copy = T.clientStatus(self.bank)
        expectNear("solar watts in this client's status", copy and copy.solarW, status.solarW, 0)
        expect(PowerBank.samePosition(PowerBank.bankOfSource(here.x, here.y, here.z), self.bank.position),
            "bankOfSource doesn't name the bank the panel was connected to")
        local overlays = table.concat(after.overlays, ",")
        expect(overlays ~= "", "the charged bank's tile shows no batteries")
        expect(T.overlays(self.bank.object) == overlays, "this client's copy of the bank shows " .. T.overlays(self.bank.object)
            .. ", the server's " .. overlays)
    end,
})

-- A module makes its rating times its condition: a module at 50 half what a whole one does, a
-- homemade one at its best 60% of its rating, and a rack with a whole and a shattered module what
-- the whole one makes alone. The cracked panel says why it is low. Catches condition ignored, or
-- a shattered module still counted.
test("renewable_energy_power_module_condition_sets_watts", {
    run = function(self)
        local bank = T.bank(self, "batteryRackMetal", { "Base.CarBattery1", "RenewableEnergy.ChargeController" }, { charge = 0.1 })
        if not bank then return end
        self.bank = bank
        local modules = {
            { { type = "RenewableEnergy.SolarModule", condition = 50 } },
            { { type = "RenewableEnergy.HomemadeSolarModule", condition = 60 } },
            { { type = "RenewableEnergy.SolarModule", condition = 100 }, { type = "RenewableEnergy.SolarModule", condition = 0 } },
        }
        local sprites = { Sprites.flat, Sprites.flat, Sprites.rack.metal.S }
        self.panels = {}
        T.batch(function()
            for i, sprite in ipairs(sprites) do
                self.panels[i] = T.panel(self, sprite, { near = bank, modules = modules[i], connect = true })
                if not self.panels[i] then return end
            end
            T.bankPass(self, bank, 1000)
        end)
    end,
    validate = function(self)
        for _, panel in ipairs(self.panels) do
            if not expectConnected(panel) then return end
        end
        local sources = self.bank.state.status.sources
        local cracked, homemade, rack = sources[1], sources[2], sources[3]
        if not expect(cracked and homemade and rack, "the status lists fewer than three panels") then return end
        -- The rack's whole module is the measure: same type, condition 100, same sun.
        local whole = rack.watts
        expect(whole > 0, "a rack with a whole module made nothing at 1000 W/m²")
        expectNear("a module at condition 50 over a whole one", cracked.watts / whole, 0.5, 0.01)
        local homemadeShare = Specs.modules["RenewableEnergy.HomemadeSolarModule"].watts
            / Specs.modules["RenewableEnergy.SolarModule"].watts
        expectNear("a homemade module at 60 over a whole factory one", homemade.watts / whole, homemadeShare * 0.6, 0.01)
        expect(cracked.reason == "cracked", "the half-cracked panel's reason is " .. tostring(cracked.reason))
        expect(cracked.modules[1] and cracked.modules[1].condition == 50, "the status lost the module's condition")
    end,
})

-- A bank takes Specs.freeSlots panels with no controller and Specs.slotsPerController more per
-- controller, each up to exactly its slots and refusing one more; panels past the slots of a
-- controller taken out stay connected but make nothing. Catches an off-by-one in the slot count
-- and a controller's slots not counted.
test("renewable_energy_power_panel_slots", {
    run = function(self)
        local box = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" }, { charge = 0.1 })
        local batteryRack = box and T.bank(self, "batteryRackWood", { "Base.CarBattery1", Specs.controller }, { charge = 0.1 })
        if not batteryRack then return end
        self.rack = batteryRack
        self.boxPanels, self.rackPanels = {}, {}
        local function connect(list, bank, count)
            for i = 1, count do
                list[i] = T.panel(self, Sprites.flat, { near = bank, connect = true })
                if not list[i] then return false end
            end
            return true
        end
        -- The banks stay out: the rack's copy waits for both its parts, and the controller leaves.
        T.batch(function()
            if not (connect(self.boxPanels, box, Specs.freeSlots + 1)
                and connect(self.rackPanels, batteryRack, Specs.freeSlots + Specs.slotsPerController + 1)) then return end
            T.server(self, "removePart", { bank = batteryRack.position, type = Specs.controller })
            T.bankPass(self, batteryRack, 1000)
        end)
    end,
    validate = function(self)
        local function expectSlots(panels, slots, what)
            for i = 1, slots do
                expect(panels[i].connected, what .. " refused panel " .. i .. " of its " .. slots .. " slots ("
                    .. tostring(panels[i].reason) .. ")")
            end
            local extra = panels[slots + 1]
            expect(not extra.connected and extra.reason == "Tooltip_RenewableEnergy_NoInputSlot",
                what .. " took a panel past its " .. slots .. " slots (" .. tostring(extra.reason) .. ")")
        end
        expectSlots(self.boxPanels, Specs.freeSlots, "a battery box without a controller")
        local withController = Specs.freeSlots + Specs.slotsPerController
        expectSlots(self.rackPanels, withController, "a battery rack with a controller")
        local status = self.rack.state.status
        local slots, last, past = status.inputSlots, status.sources[Specs.freeSlots], status.sources[Specs.freeSlots + 1]
        if not expect(#status.sources == withController, #status.sources .. " panels stayed connected when the controller left, expected "
            .. withController) then return end
        expect(slots.used == withController and slots.total == Specs.freeSlots,
            "panel slots read " .. slots.used .. " of " .. slots.total)
        expect(past.watts == 0 and past.reason == "noController",
            "a panel past the slots makes " .. past.watts .. " W, reason " .. tostring(past.reason))
        expect(last.watts > 0, "the last panel within the free slots stopped making power")
    end,
})

-- The bank's limit is its working inverters' ratings together. A Plug-in Inverter runs a TV and
-- a lamp, or a mini fridge, but not a full fridge. A broken inverter's loss shows in this client's
-- summary.
test("renewable_energy_power_inverter_limits", {
    run = function(self)
        self.box = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER })
        self.bank = self.box and T.bank(self, "batteryBankWood",
            { "Base.CarBattery1", "RenewableEnergy.PowerInverter", "RenewableEnergy.PowerInverter" })
        if not self.bank then return end
        T.batch(function()
            T.server(self, "loadWatts", { sets = { { "television", "light" }, { "miniFridge" }, { "fridge" }, { "fridgeFreezer" } } })
            T.bankState(self, self.box)
            T.bankState(self, self.bank)
            T.step(function() self.twoInverters = self.bank.state.limitW end)
            T.setPartCondition(self, self.bank, "RenewableEnergy.PowerInverter", 0, true)
        end)
        T.waitFor(self, function()
            local summary = T.clientSummary(self.bank)
            return summary ~= nil and summary.limitW == self.bank.state.limitW
        end, "this client's summary with the broken inverter's limit")
    end,
    validate = function(self)
        local limit, watts = self.box.state.limitW, self.server.loadWatts.watts
        expect(watts[1] <= limit, "a Plug-in Inverter can't run a TV and a lamp")
        expect(watts[2] <= limit, "a Plug-in Inverter can't run a mini fridge")
        expect(watts[3] > limit and watts[4] > limit, "a Plug-in Inverter runs a full fridge")
        local inverterW = Specs.inverters["RenewableEnergy.PowerInverter"].watts
        expectNear("limit of two Power Inverters", self.twoInverters, 2 * inverterW, 0)
        expectNear("limit with one of them broken", self.bank.state.limitW, inverterW, 0)
        local summary = T.clientSummary(self.bank)
        expectNear("limit in this client's summary", summary and summary.limitW, inverterW, 0)
    end,
})

-- A load beyond the inverters cuts the bank's power, which this client's status shows, and the
-- power comes back by itself once the load fits again.
test("renewable_energy_power_overload_cuts_and_returns", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER })
        if not bank then return end
        self.bank = bank
        T.watch(self, bank)
        T.switchOn(self, bank)
        T.applyLoad(self, bank, { "television", "light" })
        T.step(function() self.fitting = bank.state.activated end)
        T.applyLoad(self, bank, { "television", "light", "fridge" })
        T.step(function() self.cut = not bank.state.activated and bank.state.status end)
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return status ~= nil and status.overloaded == true
        end, "this client's status of the overloaded bank")
        T.step(function() self.copyCut = T.clientStatus(bank).state end)
        T.applyLoad(self, bank, { "television" })
    end,
    validate = function(self)
        expect(self.fitting, "a TV and a lamp didn't run on a charged bank with a Plug-in Inverter")
        if not expect(self.cut, "a fridge on top of them didn't cut the power") then return end
        local status = self.cut
        expect(status.overloaded and status.state == "overloaded", "the status doesn't read overloaded (state " .. tostring(status.state) .. ")")
        expectNear("load in the status", status.loadW, Specs.loads.television.watts + Specs.loads.light.watts + Specs.loads.fridge.watts, 0)
        expectNear("limit in the status", status.limitW, Specs.inverters[PLUG_IN_INVERTER].watts, 0)
        expect(self.copyCut == "overloaded", "this client's status of the cut bank reads " .. tostring(self.copyCut))
        local state = self.bank.state
        expect(state.activated and not state.overloaded, "the power didn't come back once the load fit")
    end,
})

-- The scan sees what is switched on whether or not the bank powers it, so a cut bank knows when
-- the load fits again; and it tells a mini fridge from a full one.
test("renewable_energy_power_scan_sees_load_while_cut", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER })
        if not bank then return end
        self.bank = bank
        local squares = T.need(self, T.squares(self, 2, { indoors = true, near = bank.square }), "two free indoor squares for fridges")
        if not squares then return end
        T.server(self, "scanLoad", bank.position)
        T.step(function()
            self.without = self.server.scanLoad
            T.placeTile(self, squares[1], FRIDGE)
            T.placeTile(self, squares[2], MINI_FRIDGE)
            T.bankState(self, bank)
            T.server(self, "scanLoad", bank.position)
        end)
    end,
    validate = function(self)
        local with, without = self.server.scanLoad, self.without
        expect(not self.bank.state.activated, "the bank was on while scanning")
        local function count(load, kind)
            return load.counts[kind] or 0
        end
        expectNear("fridge-freezers found", count(with, "fridgeFreezer") - count(without, "fridgeFreezer"), 1, 0)
        expectNear("mini fridges found", count(with, "miniFridge") - count(without, "miniFridge"), 1, 0)
        expectNear("watts added", with.watts - without.watts, Specs.loads.fridgeFreezer.watts + Specs.loads.miniFridge.watts, 0)
    end,
})

-- A free square within `reach` tiles of `near` for a backup generator: outdoors if there is one,
-- since a running generator makes a building toxic.
local function backupSquare(self, near, reach)
    local square
    for _, indoors in ipairs({ false, true }) do
        local candidate = not square and (T.squares(self, 1, { indoors = indoors, near = near }) or {})[1]
        if candidate and IsoUtils.DistanceToSquared(candidate:getX(), candidate:getY(), near:getX(), near:getY()) <= reach * reach then
            square = candidate
        end
    end
    return T.need(self, square, "a free square for a generator within " .. reach .. " tiles of the bank")
end

-- Queues reading the backup generator on `square` into self[key]: { running, fuel, ... }
-- (RenewableEnergyTestServerGas.lua).
local function generatorState(self, square, key)
    T.server(self, "generatorRead", T.at(square))
    T.step(function() self[key] = self.server.generatorRead end)
end

local CHARGED_BATTERY = "Base.CarBattery1"

-- With the grid off, a rack bank with two batteries, two car battery chargers and an
-- Inverter/Charger, and a square for a backup generator in reach of it; nil if either can't be had.
local function chargerBank(self, opts)
    T.setGrid(self, false)
    local bank = T.bank(self, "batteryRackWood",
        { CHARGED_BATTERY, CHARGED_BATTERY, Specs.charger, Specs.charger, INVERTER }, opts)
    local backup = bank and backupSquare(self, bank.square, SandboxVars.GeneratorTileRange - 1)
    if backup then return bank, backup end
end

-- The watts chargerBank's chargers make together.
local function chargerBankWatts()
    return 2 * Specs.chargerWatts + Specs.inverters[INVERTER].chargerWatts
end

-- Chargers charge only from the grid or a running generator other than a bank, never from the
-- bank's own power, and burn no generator fuel on the grid (generator_fuel_follows_battery_room
-- checks what they burn on the generator). The generator's pass is short enough that all the
-- chargers make fits in the batteries, so they run at their full watts.
test("renewable_energy_power_charger_sources", {
    sandbox = { GeneratorFuelConsumption = 0.1 },
    run = function(self)
        local charge = 0.2
        local bank, backup = chargerBank(self, { charge = charge })
        if not bank then return end
        -- For half the time the room left in the two batteries takes to fill.
        self.chargersW = chargerBankWatts()
        local roomWh = (1 - charge) * 2 * Specs.batteries[CHARGED_BATTERY].wh
        self.hours = roomWh / 2 / self.chargersW
        T.switchOn(self, bank)
        T.batch(function()
            T.bankPass(self, bank, 0)
            T.step(function() self.alone, self.ownPower = bank.state.status.chargerW, bank.state.activated end)
            T.generator(self, { square = backup, running = true })
            T.bankSet(self, bank, { charge = charge })
            T.bankPass(self, bank, 0, { hours = self.hours })
            T.step(function()
                local status = bank.state.status
                self.fromGenerator = status.chargerW
                self.generatorSource = status.chargers[1] and status.chargers[1].charging
            end)
            generatorState(self, backup, "fuelAfter")
        end)
        T.step(function() T.setGrid(self, true) end)
        T.batch(function()
            T.bankPass(self, bank, 0)
            T.step(function() self.fromGrid, self.gridPowered = bank.state.status.chargeSource, bank.state.activated end)
            generatorState(self, backup, "fuelOnGrid")
        end)
    end,
    validate = function(self)
        expectNear("charger watts with no grid or generator" .. (self.ownPower and " while the bank powers itself" or ""), self.alone, 0, 0)
        expect(self.chargersW > 0, "the bank's chargers are rated for no watts")
        expectNear("charger watts from a running generator", self.fromGenerator, self.chargersW, 0)
        expect(self.generatorSource == "generator", "a charger says it charges from " .. tostring(self.generatorSource))
        expect(self.fromGrid == "grid", "with the grid on the chargers charge from " .. tostring(self.fromGrid))
        expectNear("fuel the chargers burned on grid power", self.fuelAfter.fuel - self.fuelOnGrid.fuel, 0, 0)
        expect(not self.gridPowered, "the bank ran its own generator while the grid powered its square")
    end,
})

-- At night a bank that is on powers its squares, on this client too, and pays its load through
-- the inverter: its own idle draw with nothing on, and more than the appliances take with them
-- on; the pass takes what it draws from the batteries, and the status says it is draining.
-- Catches idle draw or inverter losses dropped, and a pass billing other than its draw.
test("renewable_energy_power_bank_powers_at_night", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { "RenewableEnergy.L16Battery", "RenewableEnergy.L16Battery", INVERTER })
        if not bank then return end
        self.bank = bank
        T.switchOn(self, bank)
        T.bankState(self, bank)
        T.waitFor(self, function() return bank.square:haveElectricity() end, "power on the switched-on bank's square here")
        T.step(function() self.powered = bank.state.activated and bank.state.powered end)
        T.batch(function()
            T.applyLoad(self, bank, {})
            T.step(function() self.idleW = bank.state.drawW end)
            T.applyLoad(self, bank, { "fridge", "television", "light" })
            T.step(function() self.drawW, self.before = bank.state.drawW, bank.state.storedWh end)
            -- The pass measures the house's real load again.
            T.bankPass(self, bank, 0)
        end)
    end,
    validate = function(self)
        local after = self.bank.state
        expect(self.powered, "switching on a charged bank with an inverter did not power its square")
        -- A compressor draws its watts for its duty's share of the time.
        local loadW = 0
        for _, name in ipairs({ "fridge", "television", "light" }) do
            loadW = loadW + Specs.loads[name].watts * (Specs.loads[name].duty or 1)
        end
        expect(self.idleW > 0, "a bank that is on with nothing switched on draws nothing for its inverter")
        expect(self.drawW - self.idleW > loadW, string.format(
            "a fridge, a TV and a lamp averaging %.1f W add %.1f W to the draw, no inverter losses", loadW, self.drawW - self.idleW))
        expect(after.status.drawW > 0, "the night's pass drew nothing from a bank that is on")
        expectNear("Wh used in an hour", self.before - after.storedWh, after.status.drawW, 0.5)
        local charging = after.status.charging
        expect(charging.watts < 0 and charging.hours ~= nil, "the status doesn't say the bank is draining")
    end,
})

-- A day's deepest discharge wears the batteries when the day turns, on this client's copies too.
test("renewable_energy_power_depth_of_discharge_wears_batteries", {
    sandbox = { BatteryWear = 100 },
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" })
        if not self.bank then return end
        T.server(self, "cycleDay", { bank = self.bank.position, high = 1, charge = 0.5 })
        T.waitFor(self, function()
            local battery = self.bank.object:getContainer():getFirstType("Base.CarBattery1")
            local served = stateItem(self.server.cycleDay, "Base.CarBattery1")
            return battery ~= nil and served ~= nil and battery:getCondition() == served.condition
        end, "this client's copy of the worn battery")
    end,
    validate = function(self)
        local day = self.server.cycleDay
        local battery = stateItem(day, "Base.CarBattery1")
        local copy = self.bank.object:getContainer():getFirstType("Base.CarBattery1")
        expectNear("cycle depth", day.depthBefore, 0.5, 0.0001)
        expectNear("car battery condition after a 50% day", battery and battery.condition, 99, 0)
        expectNear("this client's copy of the car battery's condition", copy and copy:getCondition(), 99, 0)
        expectNear("cycle depth on the new day", day.cycleDepth, 0, 0)
    end,
})

local function freshModule(condition)
    return { { type = "RenewableEnergy.SolarModule", condition = condition } }
end

-- The condition the panel object `panel` records for its first module, or nil.
local function recordedCondition(panel)
    local modules = panel and panel:getModData()[PowerBank.MODULES]
    return modules and modules[1] and modules[1].condition
end

-- Storms crack modules by mount: wall panels never, wooden racks most, metal racks least. A
-- crack takes Specs.storm.crack condition, never below 0, and reaches the panel's own record and
-- its tile in the same bank pass: a whole-looking panel cracked below Specs.crackedBelow shows
-- cracks, on this client too.
test("renewable_energy_power_storms_crack_by_mount", {
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local names = { "flat", "wall", "woodRack", "metalRack" }
        local mounts = {
            flat = { kind = "flat" }, wall = { kind = "wall", material = "wood" },
            woodRack = { kind = "rack", material = "wood" }, metalRack = { kind = "rack", material = "metal" },
        }
        local trials = {}
        for i, name in ipairs(names) do
            local mount = mounts[name]
            trials[i] = { source = { kind = mount.kind, material = mount.material, modules = freshModule(100) }, hours = 20, runs = 2000 }
        end
        T.server(self, "stormCrack", { trials = trials })
        T.step(function()
            self.cracks = {}
            for i, name in ipairs(names) do
                self.cracks[name] = self.server.stormCrack.results[i].cracks
            end
            T.setSandbox(self, "StormDamageRate", 1000)
        end)
        T.server(self, "stormCrack", { trials = { { source = { kind = "flat", modules = freshModule(10) }, hours = 1000 } } })
        T.step(function()
            self.floor = self.server.stormCrack.results[1].modules[1].condition
            T.setSandbox(self, "StormDamage", false)
        end)
        T.server(self, "stormCrack", { trials = { { source = { kind = "flat", modules = freshModule(100) }, hours = 1000 } } })
        T.step(function()
            self.disabled = self.server.stormCrack.results[1].cracks > 0
            T.setSandbox(self, "StormDamage", true)
        end)

        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" }, { charge = 0.5 })
        -- Half a crack above the cracked look, so a sure crack takes it below.
        local whole = Specs.crackedBelow + math.floor(Specs.storm.crack / 2)
        self.crackedTo = whole - Specs.storm.crack
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, modules = freshModule(whole), connect = true })
        if not panel then return end
        self.panel = panel
        T.step(function() self.before = T.overlays(panel.object) end)
        T.bankPass(self, bank, 1000, { stormHours = 1000 })
        T.server(self, "panelState", panel.position)
        T.waitFor(self, function()
            return recordedCondition(panel.object) == self.crackedTo
                and T.overlays(panel.object) == table.concat(self.server.panelState.overlays, ",")
        end, "this client's copy of the storm-cracked panel")
        T.step(function() self.copyOverlays = T.overlays(panel.object) end)
    end,
    validate = function(self)
        local cracks = self.cracks
        expectNear("wall panels cracked", cracks.wall, 0, 0)
        expect(cracks.woodRack > cracks.flat and cracks.flat > cracks.metalRack and cracks.metalRack > 0,
            string.format("cracks in 2000 storms of 20 hours: wooden rack %d, flat %d, metal rack %d",
                cracks.woodRack, cracks.flat, cracks.metalRack))
        expectNear("a module at 10 after a crack", self.floor, 0, 0)
        expect(not self.disabled, "a storm cracked a module with Storm Damage off")
        if not expectConnected(self.panel) then return end
        expect(self.before == "", "the whole panel showed '" .. tostring(self.before) .. "' before the storm")
        local modules = self.server.panelState.modules
        expectNear("the panel's recorded condition after a sure crack", modules and modules[1] and modules[1].condition, self.crackedTo, 0)
        expectNear("this client's copy of the panel's recorded condition", recordedCondition(self.panel.object), self.crackedTo, 0)
        local after = table.concat(self.server.panelState.overlays, ",")
        expect(after == Sprites.cracks.flat, "the storm-cracked panel shows '" .. after .. "'")
        expect(self.copyOverlays == after, "this client's copy of the storm-cracked panel shows '" .. tostring(self.copyOverlays) .. "'")
    end,
})

-- Wiring a part in takes its tool, wire and skill, and a free slot; Electricity XP comes only
-- the first time an item is ever wired in; unwiring gives back the part and the wire.
test("renewable_energy_power_wiring_parts", {
    run = function(self)
        T.setPerk(self, Perks.Electricity, 2)
        local bank = T.bank(self, "batteryBoxWood", {})
        if not bank then return end
        self.bank = bank
        local function wire(key, fullType)
            perform(self, key, "wireIn", { bank = bank.position }, { type = fullType })
        end
        -- A call with table args goes to the server ahead of T.give's wait for this client's
        -- copies, so a wire-in could use them up before they arrive and the wait never end; the
        -- step holds the calls after it until they have.
        local function give(key, items)
            T.give(self, key, items)
            T.step(function() end)
        end
        give("first", { { type = "Base.CarBattery1" }, { type = "Base.Hammer" } })
        wire("hammer", "Base.Hammer")
        wire("noTool", "Base.CarBattery1")
        give("wrench", { { type = "Base.Wrench" } })
        wire("noWire", "Base.CarBattery1")
        give("wire", { { type = PowerBank.WIRE } })
        wire("wired", "Base.CarBattery1")
        T.count(self, "wired", { PowerBank.WIRE })
        perform(self, "unwired", "unwire", { bank = bank.position }, { type = "Base.CarBattery1", inBank = true })
        T.count(self, "unwired", { PowerBank.WIRE, "Base.CarBattery1" })
        wire("rewired", "Base.CarBattery1")
        give("inverter", { { type = "Base.Screwdriver" }, { type = PowerBank.WIRE, count = 2 }, { type = INVERTER } })
        wire("skill", INVERTER)
        give("batteries", { { type = PowerBank.WIRE }, { type = "Base.CarBattery2" }, { type = "Base.CarBattery3" } })
        wire("second", "Base.CarBattery2")
        wire("full", "Base.CarBattery3")
        T.bankState(self, bank)
    end,
    validate = function(self)
        expect(reason(self, "hammer") == "Tooltip_RenewableEnergy_NotAPart", "a hammer was wired in (" .. reason(self, "hammer") .. ")")
        expect(reason(self, "noTool") == "tool", "a battery was wired in without a wrench (" .. reason(self, "noTool") .. ")")
        expect(reason(self, "noWire") == "wire", "a battery was wired in without wire (" .. reason(self, "noWire") .. ")")
        expect(self.wired.ok, "wiring a battery in with a wrench and wire failed (" .. reason(self, "wired") .. ")")
        expect(self.wired.xpAfter > self.wired.xpBefore, "the first wiring gave no Electricity XP")
        expectNear("wire left after wiring a battery in", self.counts.wired[PowerBank.WIRE], 0, 0)
        expect(self.unwired.ok and self.counts.unwired["Base.CarBattery1"] == 1, "unwiring didn't give the battery back")
        expectNear("wire back after unwiring", self.counts.unwired[PowerBank.WIRE], 1, 0)
        expect(self.rewired.ok, "wiring the battery in again failed (" .. reason(self, "rewired") .. ")")
        expectNear("XP for wiring the same battery again", self.rewired.xpAfter - self.rewired.xpBefore, 0, 0)
        expect(reason(self, "skill") == "skill", "an Inverter/Charger was wired in at Electricity 2 (" .. reason(self, "skill") .. ")")
        expect(self.second.ok, "a battery box refused its second battery (" .. reason(self, "second") .. ")")
        expect(reason(self, "full") == "Tooltip_RenewableEnergy_NoSlot", "a battery box took a third battery (" .. reason(self, "full") .. ")")
        expectNear("batteries in the box", self.bank.state.batteries, 2, 0)
    end,
})

-- Connecting a panel gives Electricity XP once per module, the first time that module is ever
-- connected: a rack holding one module connected before gives the other one's share and marks
-- both, and connecting it again after disconnecting gives nothing.
test("renewable_energy_power_connect_xp_once_per_module", {
    run = function(self)
        T.setPerk(self, Perks.Electricity, 3)
        local module = Specs.factoryModule
        local bank = T.bank(self, "batteryBoxWood", {})
        local panel = bank and T.panel(self, Sprites.rack.wood.S, { near = bank,
            modules = { { type = module, condition = 90, connected = true }, { type = module, condition = 90 } } })
        if not panel then return end
        local args = { bank = bank.position, source = panel.position }
        T.batch(function()
            perform(self, "connected", "connectSource", args)
            perform(self, "disconnected", "disconnectSource", args)
            perform(self, "reconnected", "connectSource", args)
            T.server(self, "panelState", panel.position)
            -- What the game gives this character for one module's award, through the call
            -- CraftRecipe.addXP makes.
            T.server(self, "electricityAward", { xp = Specs.connectXp })
        end)
    end,
    validate = function(self)
        if not expect(self.connected and self.connected.ok, "connecting the rack failed") then return end
        local award, gained = self.server.electricityAward.gained, self.connected.xpAfter - self.connected.xpBefore
        -- An award retuned to nothing would match a connection that gives nothing.
        expect(Specs.connectXp > 0 and award > 0, "a module's first connection is worth " .. award .. " Electricity XP")
        expectNear("Electricity XP from connecting a rack with one new module", gained, award, 0.01)
        expect(self.disconnected.ok, "disconnecting the rack failed (" .. tostring(self.disconnected.reason) .. ")")
        expect(self.reconnected.ok, "connecting the rack again failed (" .. tostring(self.reconnected.reason) .. ")")
        expectNear("Electricity XP from connecting the rack again", self.reconnected.xpAfter - self.reconnected.xpBefore, 0, 0)
        local modules = self.server.panelState.modules or {}
        expect(#modules == 2 and modules[1].connected == true and modules[2].connected == true,
            "the rack's record doesn't mark both modules connected")
    end,
})

-- Queues repairing the first Inverter/Charger in `bank` as the server's character, leaving the
-- answer in self[key].
local function repair(self, key, bank)
    perform(self, key, "repairPart", { bank = bank.position }, { type = INVERTER, inBank = true })
end

-- The condition the parts start their wear from.
local WORN_FROM = 80

-- Inverters and controllers wear by the hours their bank is on, an overload costs extra, a part at
-- 0 does nothing, and Electronics Scrap repairs Specs.partRepair.condition points at its skill.
-- Catches wear that ignores the hours, an overload that costs nothing, and the repair's gates.
test("renewable_energy_power_part_wear_and_repair", {
    run = function(self)
        T.setGrid(self, false)
        T.setPerk(self, Perks.Electricity, Specs.partRepair.skill - 1)
        local bank = T.bank(self, "batteryRackWood",
            { "RenewableEnergy.L16Battery", "RenewableEnergy.L16Battery", INVERTER, Specs.controller })
        if not bank then return end
        self.bank = bank
        T.switchOn(self, bank)
        local both = { [INVERTER] = WORN_FROM, [Specs.controller] = WORN_FROM }
        T.batch(function()
            T.bankSet(self, bank, { overloaded = false })
            T.server(self, "wearParts", { bank = bank.position, hours = 50, conditions = both })
            T.step(function() self.half = self.server.wearParts.lost end)
            T.server(self, "wearParts", { bank = bank.position, hours = 100, conditions = both })
            T.step(function() self.worn = self.server.wearParts.lost end)
            T.server(self, "wearParts", { bank = bank.position, overloads = 1, conditions = { [INVERTER] = WORN_FROM } })
            T.step(function() self.overloadWorn = self.server.wearParts.lost[INVERTER] end)
            T.setPartCondition(self, bank, INVERTER, 50)
            T.give(self, "scrap", { { type = PowerBank.SCRAP } })
            repair(self, "unskilled", bank)
        end)
        T.step(function() T.setPerk(self, Perks.Electricity, Specs.partRepair.skill) end)
        T.batch(function()
            repair(self, "repaired", bank)
            T.bankState(self, bank)
            T.count(self, "scrap", { PowerBank.SCRAP })
            T.step(function()
                local inverter = stateItem(bank.state, INVERTER)
                self.repairedCondition = inverter and inverter.condition
            end)
            repair(self, "noScrap", bank)
            -- Past ConditionMax, which the setter keeps it to.
            T.setPartCondition(self, bank, INVERTER, 1000)
            T.give(self, "moreScrap", { { type = PowerBank.SCRAP } })
            repair(self, "whole", bank)
            T.setPartCondition(self, bank, INVERTER, 0)
            perform(self, "refreshed", "refresh", { bank = bank.position })
            T.server(self, "powerUp", { bank = bank.position })
            T.step(function() self.broken = self.server.powerUp end)
        end)
    end,
    validate = function(self)
        -- Wear retuned to nothing, or to more than a part holds, would pass the scaling below.
        local function sane(what, lost)
            return expect(type(lost) == "number" and lost > 0 and lost < WORN_FROM,
                string.format("%s took %s of its %d condition", what, tostring(lost), WORN_FROM))
        end
        for _, part in ipairs({ INVERTER, Specs.controller }) do
            if sane(part .. "'s 100 hours on", self.worn[part]) then
                -- Condition is whole points, so the two can differ by one.
                expectNear(part .. "'s wear in 100 hours over twice its wear in 50", self.worn[part], 2 * self.half[part], 1)
            end
        end
        sane("an inverter's overload", self.overloadWorn)
        expect(reason(self, "unskilled") == "skill", "a part was repaired below Electricity "
            .. Specs.partRepair.skill .. " (" .. reason(self, "unskilled") .. ")")
        expect(self.repaired.ok, "repairing a worn inverter with scrap failed (" .. reason(self, "repaired") .. ")")
        expectNear("condition after one scrap", self.repairedCondition, 50 + Specs.partRepair.condition, 0)
        expectNear("scrap left", self.counts.scrap[PowerBank.SCRAP], 0, 0)
        expect(reason(self, "noScrap") == "scrap", "a part was repaired without scrap (" .. reason(self, "noScrap") .. ")")
        expect(reason(self, "whole") == "Tooltip_RenewableEnergy_NoRepairNeeded", "a whole part took a repair (" .. reason(self, "whole") .. ")")
        expectNear("limit with the only inverter at 0", self.broken.limitW, 0, 0)
        expect(not self.broken.activated, "a bank whose only inverter is broken powers its area")
    end,
})

-- A failsafe starts its backup generator once the bank's charge falls below FailsafeStartCharge
-- and stops it once the charge reaches FailsafeStopCharge: off at the start charge, on a percent
-- below it, still on a percent below the stop charge, off at it. Catches the comparisons the wrong
-- way round and a charge read back from battery uses a hair under a whole percent.
test("renewable_energy_power_failsafe_starts_generator", {
    sandbox = { FailsafeStartCharge = 20, FailsafeStopCharge = 80 },
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER })
        local backup = bank and backupSquare(self, bank.square, 3)
        if not backup then return end
        local start, stop = SandboxVars.RenewableEnergy.FailsafeStartCharge / 100, SandboxVars.RenewableEnergy.FailsafeStopCharge / 100
        -- The failsafe acts on the charge before the pass's own drain, which the next bankSet undoes.
        local function at(key, charge)
            T.bankSet(self, bank, { charge = charge }, true)
            T.bankPass(self, bank, 0, { hours = 0.01 })
            T.step(function()
                local generator = bank.state.status.generator
                self.found = self.found or (generator and generator.failsafe)
            end)
            generatorState(self, backup, key)
        end
        T.batch(function()
            T.generator(self, { square = backup, failsafe = true })
            T.bankSet(self, bank, { on = true })
            at("atStart", start)
            at("belowStart", start - 0.01)
            at("belowStop", stop - 0.01)
            at("atStop", stop)
        end)
    end,
    validate = function(self)
        if not expect(self.found, "the bank didn't find the failsafe generator") then return end
        expect(not self.atStart.running, "the failsafe started the generator at exactly its start charge")
        expect(self.belowStart.running, "the failsafe didn't start the generator a percent below its start charge")
        expect(self.belowStop.running, "the failsafe stopped the generator a percent below its stop charge")
        expect(not self.atStop.running, "the failsafe didn't stop the generator at exactly its stop charge")
    end,
})

-- A timed action's complete() hands the bank system a command built from what the client sent,
-- which must survive forged arguments and refuse what the world doesn't allow; the server's record
-- changes, and the summary it sends reaches this client's copy.
test("renewable_energy_power_commands_from_clients", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER })
        local panel = bank and T.panel(self, Sprites.rack.wood.S, { near = bank, connect = true })
        if not panel then return end
        self.bank, self.panel = bank, panel
        local function sourceSnowy()
            local summary = T.clientSummary(bank)
            return summary and summary.sources[1] and summary.sources[1].snowy == true
        end
        T.server(self, "setSnow", { bank = bank.position, source = panel.position, snow = 0.8 })
        T.waitFor(self, sourceSnowy, "this client's summary with the panel snowy")
        local forged = {
            { "noSuchCommand", { bank = bank.position } },
            { "setBankOn", { bank = "nonsense" } },
            { "wireIn", { bank = bank.position, itemId = "nonsense" } },
            { "rename", { bank = bank.position, name = 7 } },
            { "connectSource", { bank = bank.position, source = bank.position } },
            { "connectSource" },
        }
        self.accepted = {}
        -- The forged commands change nothing this client sees, so they and the clear go together.
        T.batch(function()
            for _, call in ipairs(forged) do
                T.perform(self, call[1], call[2])
                T.step(function()
                    if self.server.perform.ok then
                        table.insert(self.accepted, call[1])
                    end
                end)
            end
            T.perform(self, "clearSnow", { source = panel.position })
        end)
        T.waitFor(self, function() return not sourceSnowy() end, "this client's summary with the snow cleared")
        T.bankState(self, bank)
        T.step(function() self.afterForged = bank.state end)
        T.batch(function()
            T.perform(self, "disconnectSource", { source = panel.position })
            T.perform(self, "rename", { bank = bank.position, name = "  Shed bank  " })
            T.perform(self, "setBankOn", { bank = bank.position, on = true })
        end)
        T.waitFor(self, function()
            local summary = T.clientSummary(bank)
            return summary ~= nil and summary.on == true and summary.name == "Shed bank" and #summary.sources == 0
        end, "this client's summary of the renamed bank, switched on with no panel")
        T.bankState(self, bank)
    end,
    validate = function(self)
        local forged, state = self.afterForged, self.bank.state
        expect(#self.accepted == 0, "the bank system accepted forged commands: " .. table.concat(self.accepted, ", "))
        expect(forged.sources == 1 and forged.batteries == 1 and forged.name == "" and not forged.on,
            string.format("forged commands changed the bank: %d panels, %d batteries, name %q, on %s",
                forged.sources, forged.batteries, forged.name, tostring(forged.on)))
        -- The waits already failed the test if this client never saw the snow come and go.
        expect(state.sources == 0, "disconnecting the panel left " .. state.sources .. " panels")
        expect(state.on, "setBankOn didn't switch the server's bank on")
        expect(state.name == "Shed bank", "the server names the bank " .. tostring(state.name))
        -- This client's summary already matched the server's (the last wait).
    end,
})

-- A removed running bank leaves nothing powered, on this client too, and is forgotten.
test("renewable_energy_power_removed_bank_leaves_no_power", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { "RenewableEnergy.L16Battery", INVERTER })
        if not bank then return end
        self.bank = bank
        T.switchOn(self, bank)
        T.bankState(self, bank)
        T.waitFor(self, function() return bank.square:haveElectricity() end, "power on the switched-on bank's square here")
        T.server(self, "removeBank", { bank = bank.position })
        T.waitFor(self, function() return not bank.square:haveElectricity() and PowerBank.bankOn(bank.square) == nil end,
            "the removed bank and its power gone from this client")
    end,
    validate = function(self)
        local removed, square = self.server.removeBank, self.bank.square
        expect(self.bank.state.powered, "the switched-on bank didn't power its square")
        expect(not removed.powered, "the removed bank's square still has power")
        expect(not square:haveElectricity(), "the removed bank's square still has power on this client")
        expect(not removed.registered, "the removed bank is still registered")
        expect(PowerBank.bankOn(square) == nil and PowerBank.summaryOf(square) == nil, "this client still has the removed bank")
    end,
})

-- The clock ------------------------------------------------------------------------------

-- How far the clock jumps. EveryTenMinutes fires on the next tick when the minute of the hour
-- lands in another ten (GameTime.update), which a jump of more than ten minutes past whole hours
-- always does; the gadget pass makes up for at most an hour.
local CLOCK_JUMP_HOURS = 1.25

-- The game's clock runs the banks and the gadgets on the authority: once it moves on at noon, a
-- bank with a connected panel, a car with a maintainer, a solar battery charger holding cells, a
-- garden light and an arrow board's battery box have all charged, each by no more than its rating
-- in full sun gives over the game time its passes covered. The live weather can leave little
-- light, so how much more than nothing goes unchecked.
test("renewable_energy_power_clock_drives_banks_and_gadgets", {
    hour = 12,
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" }, { charge = 0.5 })
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        local squares = T.need(self, T.squares(self, 2, { bare = true }), "two bare outdoor squares for the gadgets")
        if not (panel and squares) then return end
        self.bank = bank
        T.watch(self, bank)
        local car = T.placeVehicle(self, "Base.CarNormal", { battery = "Base.CarBattery1", charge = 0.5 })
        local trailer = T.placeVehicle(self, RenewableEnergy.ArrowBoard.SCRIPT)
        local charger = T.placeAsPlayer(self, squares[1], RenewableEnergy.SolarCellCharger.ITEM, Sprites.cellCharger)
        local light = T.placeAsPlayer(self, squares[2], SolarGardenLight.ITEM, Sprites.gardenLight.off)
        local function fixtures()
            return { bank = bank.position, car = T.vehicleArgs(car), trailer = T.vehicleArgs(trailer),
                charger = { x = charger.x, y = charger.y, z = charger.z },
                light = { x = light.x, y = light.y, z = light.z } }
        end
        T.server(self, "stockGadgets", fixtures)
        T.step(function()
            if not T.need(self, panel.connected, "a panel connected to the bank") then return end
            self.before = self.server.stockGadgets
            T.setTime(self, getGameTime():getTimeOfDay() + CLOCK_JUMP_HOURS)
        end)
        -- The bank's pass and the gadgets' run on the same tick; the bank's status coming back an
        -- hour on from its last pass says both have.
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return status ~= nil and status.hour >= self.before.bankPassAge + 1
        end, "this client's status of the bank's pass an hour on")
        T.server(self, "gadgetCharges", fixtures)
    end,
    validate = function(self)
        local before, after = self.before, self.server.gadgetCharges
        if not expect(before and after, "the clock test's gadgets were never read before and after") then return end
        local function charged(name, what, ratedW, hours)
            local gain, most = after[name] - before[name], Sun.wattsFrom(ratedW, Sun.FULL_SUN, 0) * hours
            expect(gain > 0 and gain <= most, string.format(
                "%s gained %.4f Wh as the clock moved on %.2f hours, expected more than 0 and at most %.4f", what, gain, hours, most))
        end
        local bankHours, gadgetHours = after.bankPassAge - before.bankPassAge, after.age - before.age
        charged("bank", "the bank with a connected panel", Specs.mounts.flat.modules * Specs.modules[Specs.factoryModule].watts, bankHours)
        charged("car", "the car with a maintainer", Specs.maintainerWatts, gadgetHours)
        charged("charger", "the solar battery charger", Specs.cellChargerWatts, gadgetHours)
        charged("light", "the garden light", Specs.gardenLight.watts, gadgetHours)
        -- A storm during the passes may have cracked a panel since.
        charged("trailer", "the arrow board's battery box", math.max(before.trailerWatts, after.trailerWatts), gadgetHours)
    end,
})

-- Who may change a bank -------------------------------------------------------------------

-- The server takes no bank job as a client command, only the status window's watch: a forged
-- packet can't switch, rename or strip a bank, while the watch's refresh still brings its status
-- up to date.
test("renewable_energy_power_client_commands_ignored", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", "Base.CarBattery1", PLUG_IN_INVERTER })
        if not bank then return end
        self.bank = bank
        T.bankState(self, bank)
        T.step(function() self.before = bank.state end)
        -- A battery taken out past the bank's commands shows in the status only once something makes
        -- the bank look again: here the watch sent after the forged commands, which the server
        -- handles in the order they came.
        T.server(self, "removePart", { bank = bank.position, type = "Base.CarBattery1" })
        T.step(function()
            local p, part = player(), stateItem(self.before, PLUG_IN_INVERTER)
            local system = PowerBank.clientSystem
            system:sendCommand(p, "setBankOn", { bank = bank.position, on = true })
            system:sendCommand(p, "rename", { bank = bank.position, name = "Forged" })
            system:sendCommand(p, "unwire", { bank = bank.position, itemId = part and part.id or -1 })
            PowerBank.watchStatus(p, bank.object)
            T.defer(self, function() PowerBank.unwatchStatus(p, bank.object) end)
        end)
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return status ~= nil and #status.batteries == 1
        end, "this client's status after the watch, with the battery taken out")
        T.bankState(self, bank)
    end,
    validate = function(self)
        local before, after = self.before, self.bank.state
        expect(not after.on, "a client command switched the bank on")
        expect(after.name == before.name, "a client command renamed the bank " .. tostring(after.name))
        expect(stateItem(after, PLUG_IN_INVERTER) ~= nil, "a client command unwired the inverter")
    end,
})

-- Every client keeps a bank's summary, which the server sends again only when it changes, while
-- the whole status goes only to the players watching the bank: from the watch on, after every
-- change, until they stop.
test("renewable_energy_power_status_only_to_watchers", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER }, { charge = 0.5 })
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not panel then return end
        self.bank = bank
        T.step(function() self.summary = T.clientSummary(bank) end)
        T.bankPass(self, bank, 1000)
        T.step(function()
            self.unwatched = { status = T.clientStatus(bank), watchers = bank.state.watchers,
                resent = T.clientSummary(bank) ~= self.summary }
        end)
        T.watch(self, bank)
        T.bankPass(self, bank, 0)
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return status ~= nil and status.solarW == 0
        end, "this client's status of the watched bank's dark pass")
        T.step(function()
            self.watchers = bank.state.watchers
            PowerBank.unwatchStatus(player(), bank.object)
        end)
        T.waitFor(self, function() return T.clientStatus(bank) == nil end, "this client letting go of the status it stopped watching")
        -- The unwatch and the pass's call are separate packets, which a server may take in either order.
        T.serverUntil(self, "bankState", bank.position, function(state) return state.watchers == 0 end)
        T.bankPass(self, bank, 1000)
        T.step(function() self.stopped = { status = T.clientStatus(bank), watchers = bank.state.watchers } end)
    end,
    validate = function(self)
        local unwatched, stopped = self.unwatched, self.stopped
        if not expect(unwatched and stopped, "the queue stopped before the bank was watched and let go") then return end
        expect(unwatched.status == nil, "this client has the status of a bank nobody here watches")
        expect(unwatched.watchers == 0, unwatched.watchers .. " players watch a bank nobody opened")
        expect(not unwatched.resent, "a pass that changed nothing in the summary sent it again")
        expect(self.watchers == 1, tostring(self.watchers) .. " players watch the bank this client watches, expected 1")
        -- The wait after the unwatch already failed the test if this client kept the status.
        expect(stopped.watchers == 0, stopped.watchers .. " players still watch the bank after this client stopped")
        expect(stopped.status == nil, "a pass sent this client the status of a bank it stopped watching")
    end,
})

-- Squares between the character and the far bank, counted ring by ring: well past where the menu's
-- walk leaves a character, and the slack the server allows on top of it.
local FAR_TILES = 8

-- On a multiplayer server a bank job counts only where the character could have walked to do it:
-- the server finishing a rename for a bank far from the character changes nothing, and the same
-- job on a bank beside the character goes through. The server finishes the actions itself, as it
-- does a client's: a refused action on the client's queue would clear the queue, and the test's
-- steps with it.
test("renewable_energy_power_far_action_refused", {
    mpOnly = "only a multiplayer server checks the reach of a client's action; single player trusts its own character",
    instant = true,
    run = function(self)
        local far = T.square(self, { minDistance = FAR_TILES }, "an outdoor square far from the character")
        self.far = far and T.bank(self, "batteryBoxWood", {}, { square = far, outdoors = true })
        self.near = self.far and T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if not self.near then return end
        T.batch(function()
            for _, bank in ipairs({ self.far, self.near }) do
                T.server(self, "completeRename", { bank = bank.position, name = bank == self.far and "Far" or "Near" })
                T.step(function() bank.done = self.server.completeRename and self.server.completeRename.done end)
                T.bankState(self, bank)
            end
        end)
    end,
    validate = function(self)
        local far, near = self.far and self.far.state, self.near and self.near.state
        if not expect(far ~= nil and near ~= nil, "the server never reported the banks' states") then
            return
        end
        expect(not self.far.done and far.name == "", "an action from " .. FAR_TILES .. " squares away renamed the bank "
            .. tostring(far.name))
        expect(self.near.done and near.name == "Near", "renaming the bank beside the character left it called "
            .. tostring(near.name))
    end,
})

-- Generator charging ----------------------------------------------------------------------

-- A running generator pays only for what the batteries take: nothing for a full bank or for one
-- without batteries, and for a bank with room, the fuel for that room alone. The bank is off and
-- in the dark, so the chargers are all that moves its charge.
test("renewable_energy_power_generator_fuel_follows_battery_room", {
    sandbox = { GeneratorFuelConsumption = 0.1 },
    run = function(self)
        local bank, backup = chargerBank(self)
        if not bank then return end
        self.bank = bank
        self.chargersW = chargerBankWatts()
        self.low = 0.2
        local function pass(key)
            generatorState(self, backup, key .. "Before")
            T.bankPass(self, bank, 0)
            T.step(function() self[key] = bank.state end)
            generatorState(self, backup, key .. "After")
        end
        -- The bank stays out: its copy waits for every part, and the batteries leave.
        T.batch(function()
            T.generator(self, { square = backup, running = true })
            pass("full")
            T.bankSet(self, bank, { charge = self.low }, true)
            pass("room")
            T.server(self, "removePart", { bank = bank.position, type = CHARGED_BATTERY })
            T.server(self, "removePart", { bank = bank.position, type = CHARGED_BATTERY })
            pass("empty")
        end)
    end,
    validate = function(self)
        local function burned(key)
            return self[key .. "Before"].fuel - self[key .. "After"].fuel
        end
        for _, key in ipairs({ "full", "room", "empty" }) do
            local source = self[key].status.chargeSource
            expect(source == "generator", "the " .. key .. " bank's chargers charge from " .. tostring(source))
        end
        expectNear("fuel the chargers burned on a full bank", burned("full"), 0, 0)
        expectNear("charger watts into a full bank", self.full.status.chargerW, 0, 0)
        -- A bank pass lasts an hour unless told otherwise. Vanilla bills a generator a unit of fuel an
        -- hour for each Specs.loads.other.wattsPerConsumption watts, times the fuel consumption option.
        local roomWh = (1 - self.low) * self.room.nominalWh
        local filledWh = math.min(self.chargersW, roomWh)
        local fuel = filledWh / Specs.loads.other.wattsPerConsumption * SandboxVars.GeneratorFuelConsumption
        expect(self.chargersW > 0 and roomWh > 0 and fuel > 0, "the bank with room in its batteries bills no fuel")
        expectNear("fuel the chargers burned filling the room", burned("room"), fuel, fuel * 0.01)
        expectNear("the bank's charge after the chargers filled it", self.room.charge,
            self.low + filledWh / self.room.nominalWh, 0.0001)
        expect(self.empty.batteries == 0, "the bank still holds " .. self.empty.batteries .. " batteries")
        expectNear("fuel the chargers burned on a bank without batteries", burned("empty"), 0, 0)
        expectNear("charger watts into a bank without batteries", self.empty.status.chargerW, 0, 0)
    end,
})

-- Keeping a bank's record --------------------------------------------------------------------

-- A bank tile that loads without its container is rebuilt into a working bank, and the rebuilt bank
-- keeps what the bank's record held: its name and its panels, on the server and in this client's
-- summary.
test("renewable_energy_power_rebuilt_bank_keeps_its_record", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", {})
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not panel then return end
        self.bank, self.panel = bank, panel
        T.batch(function()
            T.perform(self, "rename", { bank = bank.position, name = "Cellar" })
            T.server(self, "rebuildBank", { bank = bank.position })
        end)
        T.waitFor(self, function()
            local rebuilt, summary = PowerBank.bankOn(bank.square), PowerBank.summaryOf(bank.square)
            return rebuilt ~= nil and rebuilt ~= bank.object and summary ~= nil and summary.name == "Cellar"
        end, "this client's copy of the rebuilt bank, named")
    end,
    validate = function(self)
        if not expectConnected(self.panel) then return end
        local state, summary = self.server.rebuildBank, PowerBank.summaryOf(self.bank.square)
        expect(state.name == "Cellar", "the rebuilt bank is named " .. string.format("%q", tostring(state.name)))
        expect(state.sources == 1, "the rebuilt bank has " .. tostring(state.sources) .. " panels")
        expect(summary ~= nil and summary.name == "Cellar" and #summary.sources == 1,
            "this client's summary of the rebuilt bank names it " .. tostring(summary and summary.name)
            .. " with " .. tostring(summary and #summary.sources) .. " panels")
    end,
})

-- The snow on `panel` in a bank state's status, or nil when the status doesn't list it.
local function snowOn(state, panel)
    for _, source in ipairs(state.status.sources) do
        if PowerBank.samePosition(source, panel.position) then
            return source.snow
        end
    end
end

-- Connecting a panel again to the bank it feeds leaves it as it was, snow included, and a bank
-- whose panel slots are all taken doesn't turn its own panel away as if there were no room.
test("renewable_energy_power_reconnecting_a_panel_keeps_it", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", {})
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not panel then return end
        self.panel = panel
        local args = { bank = bank.position, source = panel.position }
        -- A refresh after each try builds the status from the record again, whatever the try sent.
        local function tryAgain(key)
            perform(self, key, "connectSource", args)
            T.perform(self, "refresh", { bank = bank.position })
            T.bankState(self, bank)
            T.step(function() self[key].state = bank.state end)
        end
        T.batch(function()
            T.server(self, "setSnow", { bank = bank.position, source = panel.position, snow = 0.8 })
            tryAgain("again")
            self.second = T.panel(self, Sprites.flat, { near = bank, connect = true })
            if not self.second then return end
            tryAgain("full")
        end)
    end,
    validate = function(self)
        if not expect(self.panel.connected and self.second.connected, "connecting the panels failed ("
            .. tostring(self.panel.reason) .. ", " .. tostring(self.second.reason) .. ")") then return end
        for _, case in ipairs({ { self.again, 1, "a bank" }, { self.full, 2, "a full bank" } }) do
            local reply, panels, what = case[1], case[2], case[3]
            expect(reply.state.sources == panels, "connecting a panel to " .. what .. " it feeds left "
                .. reply.state.sources .. " panels")
            -- Connecting brings the bank up to now first, which may melt a trace of it.
            expectNear("snow on a panel connected again to " .. what .. " it feeds", snowOn(reply.state, self.panel) or -1, 0.8, 0.01)
        end
        expect(self.full.reason ~= "Tooltip_RenewableEnergy_NoInputSlot",
            "a full bank turned its own panel away for want of a slot")
    end,
})

-- What a bank integrates over time ------------------------------------------------------------

-- A command that changes what a bank makes or draws brings the bank up to now first, so the time
-- since its last pass is billed as things were: a panel connected an hour after the last pass
-- earns nothing for that hour, and the pass after it does earn. Catches a connect that lets the
-- next pass credit the new panel for time before it was connected.
test("renewable_energy_power_connect_credits_from_connection", {
    hour = 12,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1" }, { charge = 0.5 })
        local panel = bank and T.panel(self, Sprites.flat, { near = bank })
        if not panel then return end
        T.batch(function()
            T.server(self, "ageBank", { bank = bank.position, hours = 1 })
            perform(self, "connected", "connectSource", { bank = bank.position, source = panel.position })
            T.bankState(self, bank)
            T.step(function() self.afterConnect = bank.state end)
            T.bankPass(self, bank, 1000)
            T.step(function() self.afterPass = bank.state end)
        end)
    end,
    validate = function(self)
        if not expect(self.connected.ok, "connecting the panel failed (" .. reason(self, "connected") .. ")") then return end
        local connected, passed = self.afterConnect, self.afterPass
        expectNear("hours between the connect and the bank's last pass", connected.age - connected.lastHour, 0, 0.01)
        expectNear("solar Wh today credited for the hour before the connect", connected.solarWhToday, 0, 0)
        expect(passed.solarWhToday > 0, "the pass after the connect credited the panel nothing")
    end,
})

-- Switching a bank on brings it up to now first: the time it stood off bills no load, the pass
-- after the switch does. The fridge beside it is a real load the bank's own scan finds; the
-- house around may switch on more than a plug-in inverter carries, hence the Inverter/Charger,
-- and a short pass, which one battery lasts. Catches a switch that lets the next pass bill the
-- load for time the bank was off.
test("renewable_energy_power_switch_on_bills_from_switch", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { "Base.CarBattery1", INVERTER })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        T.placeTile(self, fridge, MINI_FRIDGE)
        T.batch(function()
            T.server(self, "ageBank", { bank = bank.position, hours = 1 })
            perform(self, "switched", "setBankOn", { bank = bank.position, on = true })
            T.bankState(self, bank)
            T.step(function() self.afterSwitch = bank.state end)
            T.bankPass(self, bank, 0, { hours = 0.1 })
            T.step(function() self.afterPass = bank.state end)
        end)
    end,
    validate = function(self)
        if not expect(self.switched.ok, "switching the bank on failed (" .. reason(self, "switched") .. ")") then return end
        local switched, passed = self.afterSwitch, self.afterPass
        expect(switched.on, "setBankOn left the bank off")
        expectNear("hours between the switch and the bank's last pass", switched.age - switched.lastHour, 0, 0.01)
        expectNear("load Wh today billed for the hour the bank was off", switched.loadWhToday, 0, 0)
        expect(passed.loadWhToday > 0, "the pass after the switch billed the mini fridge nothing")
    end,
})

-- A pass the batteries can't last bills the load for the part of it they carried: more than
-- nothing, and no more than the energy they held less the inverters' losses. The fridge makes
-- sure something draws. Catches a pass that empties the bank billing no load at all, and one
-- billing the whole pass's load the batteries never had.
test("renewable_energy_power_empty_pass_bills_what_it_carried", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { "Base.CarBattery1", INVERTER }, { charge = 0.02 })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        T.placeTile(self, fridge, MINI_FRIDGE)
        T.batch(function()
            perform(self, "switched", "setBankOn", { bank = bank.position, on = true })
            T.bankState(self, bank)
            T.step(function() self.before = bank.state end)
            T.bankPass(self, bank, 0)
            T.step(function() self.after = bank.state end)
        end)
    end,
    validate = function(self)
        if not expect(self.switched.ok, "switching the bank on failed (" .. reason(self, "switched") .. ")") then return end
        local before, after = self.before, self.after
        expect(after.storedWh == 0 and after.status.state == "empty",
            "an hour of load left the bank at " .. after.storedWh .. " Wh, " .. after.status.state)
        local billed, most = after.loadWhToday - before.loadWhToday, before.storedWh * Specs.inverterEfficiency
        expect(billed > 0 and billed <= most + 1e-6, "the pass that emptied the bank billed " .. billed
            .. " Wh of load, expected more than 0 and at most the " .. most .. " Wh the batteries could give")
    end,
})

-- While a backup generator carries the load of a switched-on bank, the bank's own figure for the
-- day stays at what its batteries carried, nothing, and the generator's share is kept apart; the
-- batteries keep their charge. The fridge makes sure something draws. Catches the generator's
-- work counted as the bank's, which makes a bank look as if it keeps up.
test("renewable_energy_power_backup_load_kept_apart", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { "Base.CarBattery1", PLUG_IN_INVERTER })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        local backup = fridge and backupSquare(self, bank.square, 3)
        if not backup then return end
        T.placeTile(self, fridge, MINI_FRIDGE)
        T.generator(self, { square = backup, running = true })
        T.batch(function()
            perform(self, "switched", "setBankOn", { bank = bank.position, on = true })
            T.bankState(self, bank)
            T.step(function() self.before = bank.state end)
            T.bankPass(self, bank, 0)
            T.step(function() self.after = bank.state end)
        end)
    end,
    validate = function(self)
        if not expect(self.switched.ok, "switching the bank on failed (" .. reason(self, "switched") .. ")") then return end
        local before, after = self.before, self.after
        expectNear("load Wh the bank carried while the generator ran", after.loadWhToday - before.loadWhToday, 0, 0)
        local backupWh = (after.status.backupWhToday or 0) - (before.status.backupWhToday or 0)
        expect(backupWh > 0, "an hour of the generator carrying the load counted " .. backupWh .. " Wh")
        expectNear("Wh in the batteries while the generator carried the load", after.storedWh, before.storedWh, 0.01)
    end,
})

-- Taking a sledgehammer to a bank brings it up to now first, so its batteries land on the floor
-- with what the hour since its last pass took: at least its inverter's idle draw. Catches batteries
-- leaving with the last pass's charge, which makes knocking a bank down before its pass free power.
test("renewable_energy_power_sledgehammer_settles_batteries", {
    instant = true,
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { "Base.CarBattery1", INVERTER }, { charge = 0.9 })
        if not bank then return end
        T.give(self, "sledgehammer", { { type = "Base.Sledgehammer", equip = "primary" } })
        T.switchOn(self, bank)
        T.batch(function()
            T.server(self, "ageBank", { bank = bank.position, hours = 1 })
            T.bankState(self, bank)
        end)
        T.step(function() self.before = bank.state end)
        T.doJob(self, bank.square, function() return ISDestroyStuffAction:new(T.player(), bank.object) end)
        T.waitFor(self, function() return PowerBank.bankOn(bank.square) == nil end, "the destroyed bank gone from this client")
        T.server(self, "takeFloorItems", { squares = { T.at(bank.square) } })
    end,
    validate = function(self)
        local battery
        for _, item in ipairs(self.server.takeFloorItems.items) do
            if item.type == "Base.CarBattery1" then
                battery = item
            end
        end
        if not expect(battery, "the destroyed bank left no battery on the floor") then return end
        local most = self.before.charge - Specs.inverters[INVERTER].idle / self.before.nominalWh
        expect(battery.uses <= most + 1e-4, "the battery left the destroyed bank at " .. battery.uses
            .. " after an hour on since its last pass at " .. self.before.charge .. ", expected at most " .. most)
    end,
})
