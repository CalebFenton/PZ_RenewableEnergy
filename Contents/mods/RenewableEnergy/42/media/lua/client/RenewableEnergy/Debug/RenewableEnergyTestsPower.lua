require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/PowerBank/PowerBank"

-- Server Lua loads after client Lua, so a server file can only be required once the game
-- runs, when require hands back the loaded file's table.
local function Loads()
    return require "RenewableEnergy/PowerBank/Loads"
end

-- Power tests: the sun model against measured insolation, and banks charging, powering,
-- tripping, wearing and freezing. Single player runs the server's bank system in the same Lua
-- state, so the tests drive banks through the same perform() and OnClientCommand a server
-- runs, and check what reaches the client's copy. See RenewableEnergyTestLib.lua for how the
-- runner works.

local test, expect, expectNear, player = RenewableEnergyTest.test, RenewableEnergyTest.expect,
    RenewableEnergyTest.expectNear, RenewableEnergyTest.player
local Specs, Sprites, Sun = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun
local Battery, PowerBank = RenewableEnergy.Battery, RenewableEnergy.PowerBank

local FRIDGE = "appliances_refrigeration_01_0"
local CLEAR = { cloud = 0, fog = 0, rain = 0, snowing = false, groundSnow = 0 }

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
-- they make against a 38° rack (design §2.2: 4.11 and 2.96 against 4.59 kWh/m²/day), and the
-- wall beats the flat panel in December.
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

-- Overcast leaves a quarter of the light, all of it diffuse; heat costs output and cold
-- adds a little.
test("renewable_energy_power_sun_clouds_and_heat", {
    run = function(self)
        local sun = Sun.position(172, 0, 38)
        local overcast = { cloud = 1, fog = 0, rain = 0, snowing = false, groundSnow = 0 }
        self.flat = Sun.planeIrradiance(sun, "flat", nil, overcast) / Sun.planeIrradiance(sun, "flat", nil, CLEAR)
        self.rack = Sun.planeIrradiance(sun, "rack", "S", overcast) / Sun.planeIrradiance(sun, "rack", "S", CLEAR)
        self.hot = Sun.temperatureFactor(35, 1000)
        self.cold = Sun.temperatureFactor(-10, 300)
    end,
    validate = function(self)
        expectNear("overcast / clear on a flat panel", self.flat, 0.25, 0.005)
        expect(self.rack < self.flat, "clouds cost a rack less than a flat panel")
        expectNear("cell temperature factor on a 35 °C noon", self.hot, 0.86, 0.001)
        expect(self.cold > 1, "a cold sunny panel makes no more than its rating")
    end,
})

-- The Sunlight Multiplier scales what a panel makes, and snow on it blocks it.
test("renewable_energy_power_sunlight_multiplier_and_snow", {
    sandbox = { SunlightMultiplier = 1 },
    run = function(self)
        self.real = Sun.wattsFrom(50, 1000, 25, 0)
        SandboxVars.RenewableEnergy.SunlightMultiplier = 3
        self.boosted = Sun.wattsFrom(50, 1000, 25, 0)
        self.snowed = Sun.wattsFrom(50, 1000, 25, 1)
    end,
    validate = function(self)
        -- 50 W, 10% heat loss at 25 °C air in full sun, 80% system losses.
        expectNear("a 50 W module at 1000 W/m² and x1", self.real, 36, 0.01)
        expectNear("the same at x3", self.boosted, 108, 0.01)
        expectNear("the same under snow", self.snowed, 0, 0)
    end,
})

-- Batteries ------------------------------------------------------------------------------

test("renewable_energy_power_battery_cold_and_wear", {
    sandbox = { BatteryWear = 100 },
    run = function(self)
        self.warm = Battery.coldFactor(25)
        self.freezing = Battery.coldFactor(0)
        self.deepFreeze = Battery.coldFactor(-18)
        local deepCycle = Specs.batteries["RenewableEnergy.DeepCycleBattery"]
        self.deepAt80 = 1 / Battery.cycleWear(deepCycle, 0.8)
        local battery = instanceItem("Base.CarBattery1")
        if not battery then return end
        local car = Specs.batteries["Base.CarBattery1"]
        -- Four days at 50%: 1.25 points a day for a car battery's 80 cycles.
        for _ = 1, 4 do
            Battery.wear(battery, Battery.cycleWear(car, 0.5))
        end
        self.condition = battery:getCondition()
    end,
    validate = function(self)
        expectNear("capacity at 25 °C", self.warm, 1, 0)
        expectNear("capacity at 0 °C", self.freezing, 0.8, 0.0001)
        expectNear("capacity at -18 °C", self.deepFreeze, 0.6, 0.0001)
        expect(self.deepAt80 > 300 and self.deepAt80 < 450, "a deep-cycle battery lasts " .. tostring(self.deepAt80) .. " cycles at 80%")
        expectNear("car battery condition after four 50% days", self.condition, 95, 0)
    end,
})

-- Banks in the world ---------------------------------------------------------------------

local function system()
    return PowerBank.serverSystem
end

local function position(object)
    return { x = object:getX(), y = object:getY(), z = object:getZ() }
end

local function squareNear(dx, dy)
    local here = player():getCurrentSquare()
    return here and getCell():getGridSquare(here:getX() + dx, here:getY() + dy, here:getZ())
end

-- Free outdoor squares near the player with nothing but the floor, other than `avoid`.
local function outdoorSquares(count, avoid)
    local found, here = {}, player():getCurrentSquare()
    if not here then return found end
    for radius = 2, 12 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local square = getCell():getGridSquare(here:getX() + dx, here:getY() + dy, here:getZ())
                if #found < count and square and not avoid[square] and square:isOutside() and square:isFree(false)
                    and square:getObjects():size() == 1 then
                    avoid[square] = true
                    table.insert(found, square)
                end
            end
        end
    end
    return found
end

-- Removes everything but the floor the way the game does, so the mod's removal handler runs.
local function clearSquare(square)
    if not square then return end
    local objects = square:getObjects()
    for i = objects:size() - 1, 1, -1 do
        local object = objects:get(i)
        if instanceof(object, "IsoGenerator") and object:isActivated() then
            object:setActivated(false)
        end
        square:transmitRemoveItemFromSquare(object)
    end
end

-- The scenario starts with the grid on, which powers squares without a generator.
local function gridOff(self)
    local option = getSandboxOptions():getOptionByName("ElecShutModifier")
    self.savedGrid = { hydro = getWorld():isHydroPowerOn(), shut = option and option:getValue() }
    if option then option:setValue(-1) end
    getWorld():setHydroPowerOn(false)
end

local function restoreGrid(self)
    local saved = self.savedGrid
    if not saved then return end
    local option = getSandboxOptions():getOptionByName("ElecShutModifier")
    if option and saved.shut then option:setValue(saved.shut) end
    getWorld():setHydroPowerOn(saved.hydro)
end

--- A bank of `sprite` on a free outdoor square holding `items` (full types), its batteries
--- charged to `charge`. Returns the generator and the bank's global object.
local function newBank(self, sprite, items, charge)
    self.squares = self.squares or {}
    self.used = self.used or {}
    local square = outdoorSquares(1, self.used)[1]
    if not square then return nil end
    table.insert(self.squares, square)
    local generator = PowerBank.place(square, sprite, -1)
    local container = generator and generator:getContainer()
    if not container then return generator, nil end
    for _, fullType in ipairs(items) do
        local item = container:AddItem(fullType)
        if item and Battery.isBattery(item) then
            Battery.setCharge(item, charge or 1)
        end
    end
    PowerBank.perform(nil, "refresh", { bank = position(generator) })
    return generator, system():getLuaObjectOnSquare(square)
end

--- A placed panel tile on a free outdoor square.
local function newPanel(self, spriteName)
    local square = outdoorSquares(1, self.used)[1]
    if not square then return nil end
    table.insert(self.squares, square)
    local panel = IsoObject.new(square, spriteName, "Solar", false)
    square:AddTileObject(panel)
    return panel
end

local function cleanup(self)
    for _, square in ipairs(self.squares or {}) do
        clearSquare(square)
    end
    restoreGrid(self)
end

-- A pass with the weather fixed: `light` W/m² on every mount, 25 °C, no snow.
local function passContext(light)
    return {
        weather = CLEAR, precipitation = 0, airC = 25, elevation = 45,
        irradiance = function() return light end,
    }
end

-- A placed bank is a registered generator whose container takes batteries, one inverter and
-- the controllers it has room for, and nothing else.
test("renewable_energy_power_bank_accepts_parts", {
    run = function(self)
        local box = newBank(self, Sprites.batteryBox, { "Base.CarBattery1", "Base.CarBattery2", "RenewableEnergy.PlugInInverter" })
        local rack = newBank(self, Sprites.batteryBank, { "RenewableEnergy.ChargeController" })
        self.box, self.rack = box, rack
        local function allows(generator, fullType)
            local container = generator and generator:getContainer()
            local item = instanceItem(fullType)
            return container ~= nil and item ~= nil and container:isItemAllowed(item)
        end
        if not (box and rack) then return end
        self.registered = system():getLuaObjectOnSquare(box:getSquare()) ~= nil and PowerBank.isBank(box)
        self.boxThirdBattery = allows(box, "Base.CarBattery3")
        self.boxSecondInverter = allows(box, "RenewableEnergy.PowerInverter")
        self.boxController = allows(box, "RenewableEnergy.ChargeController")
        self.rackBattery = allows(rack, "RenewableEnergy.L16Battery")
        self.rackInverter = allows(rack, "RenewableEnergy.InverterCharger")
        self.rackController = allows(rack, "RenewableEnergy.ChargeController")
        self.rackHammer = allows(rack, "Base.Hammer")
        self.powered = box:isActivated()
    end,
    validate = function(self)
        if not expect(self.box and self.rack, "no free outdoor squares for two banks, or place() made none") then return end
        expect(self.registered, "the bank system did not register the placed bank")
        expect(not self.boxThirdBattery, "a battery box takes a third battery")
        expect(not self.boxSecondInverter, "a battery box takes a second inverter")
        expect(not self.boxController, "a battery box takes a charge controller")
        expect(self.rackBattery and self.rackInverter and self.rackController, "a battery bank refuses a battery, inverter or controller")
        expect(not self.rackHammer, "a battery bank takes a hammer")
        expect(not self.powered, "a bank that was never switched on powers its area")
    end,
    cleanup = cleanup,
})

-- Noon on a connected panel charges the bank by what the panel makes, and the batteries carry
-- the charge.
test("renewable_energy_power_panel_charges_bank", {
    run = function(self)
        local generator, bank = newBank(self, Sprites.batteryBox, { "Base.CarBattery1" }, 0.5)
        local panel = generator and newPanel(self, Sprites.flat)
        if not (bank and panel) then return end
        self.connected = PowerBank.perform(player(), "connectSource", { bank = position(generator), source = position(panel) })
        local before = bank.charge * bank:capacityWh()
        bank:update(1, passContext(1000))
        self.gained = bank.charge * bank:capacityWh() - before
        self.solarW = bank.status.solarW
        local battery = generator:getContainer():getFirstType("Base.CarBattery1")
        self.batteryCharge = battery and Battery.getCharge(battery)
        self.bankCharge = bank.charge
        self.source = PowerBank.bankOfSource(panel:getX(), panel:getY(), panel:getZ())
    end,
    validate = function(self)
        if not expect(self.connected, "connecting the panel failed") then return end
        -- One 50 W module at x3 (the default) in full sun at 25 °C.
        expectNear("solar watts", self.solarW, 108, 0.5)
        expectNear("Wh gained in an hour", self.gained, self.solarW, 0.5)
        expectNear("the battery's charge", self.batteryCharge, self.bankCharge, 0.001)
        expect(self.source ~= nil, "bankOfSource doesn't know the panel")
    end,
    cleanup = cleanup,
})

-- At night a bank that is on powers its squares and pays the inverter's idle draw, and the
-- cold shrinks what it can deliver.
test("renewable_energy_power_bank_powers_and_feels_cold", {
    run = function(self)
        gridOff(self)
        local generator, bank = newBank(self, Sprites.batteryBox, { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" }, 1)
        if not bank then return end
        PowerBank.perform(player(), "setBankOn", { bank = position(generator), on = true })
        self.powered = generator:isActivated() and generator:getSquare():haveElectricity()
        self.trip = bank.trip
        local before = bank.charge * bank:capacityWh()
        bank:update(1, passContext(0))
        self.drawW = bank.status.drawW
        self.used = before - bank.charge * bank:capacityWh()
        bank.tempC = -18
        self.coldCapacity = bank:capacityWh()
        self.nominal = bank.nominalWh
    end,
    validate = function(self)
        if not expect(self.powered ~= nil, "no bank was placed") then return end
        expect(self.powered or self.trip, "switching on a charged bank with an inverter did not power its square")
        if self.trip then
            print("RETest NOTE renewable_energy_power_bank_powers_and_feels_cold: the scenario's appliances tripped the inverter (" .. tostring(self.trip) .. ")")
        else
            expect(self.drawW >= Specs.inverters["RenewableEnergy.PlugInInverter"].idle, "the inverter draws " .. tostring(self.drawW) .. " W")
            expectNear("Wh used in an hour", self.used, self.drawW, 0.5)
        end
        expectNear("capacity at -18 °C", self.coldCapacity, self.nominal * 0.6, 0.01)
    end,
    cleanup = cleanup,
})

-- Loads above the inverter trip it: too many watts, a 240 V appliance, or a start-up surge.
test("renewable_energy_power_inverter_trips", {
    run = function(self)
        local _, bank = newBank(self, Sprites.batteryBox, { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" }, 1)
        if not bank then return end
        local function tripFor(names, starting)
            bank.trip = false
            local load = Loads().new()
            for _, name in ipairs(names) do
                Loads().add(load, name)
            end
            bank:checkInverter(load, starting)
            return bank.trip
        end
        self.light = tripFor({ "light" }, false)
        self.overload = tripFor({ "light", "light", "light" }, false)
        self.volts240 = tripFor({ "range" }, false)
        self.surge = tripFor({ "fridge" }, true)
        bank.inverter = "RenewableEnergy.PowerInverter"
        self.fridgeOn600 = tripFor({ "fridgeFreezer", "light" }, true)
        -- 440 W running leaves the compressor's 520-820 W kick over the 1,200 W surge
        -- rating about one start in five.
        self.busyTrips = 0
        for _ = 1, 100 do
            if tripFor({ "fridgeFreezer", "light", "light", "light", "light", "light", "light" }, false) == "surge" then
                self.busyTrips = self.busyTrips + 1
            end
        end
        bank.trip = false
    end,
    validate = function(self)
        if not expect(self.light ~= nil, "no bank was placed") then return end
        expect(not self.light, "one light trips a 140 W inverter")
        expect(self.overload == "overload", "three lights on a 140 W inverter give " .. tostring(self.overload))
        expect(self.volts240 == "volts240", "a range gives " .. tostring(self.volts240))
        expect(self.surge == "surge", "a fridge starting on a 140 W inverter gives " .. tostring(self.surge))
        expect(not self.fridgeOn600, "a fridge-freezer and a light starting trip a 600 W inverter")
        expect(self.busyTrips > 0 and self.busyTrips < 100, "a fridge-freezer cycling on with 360 W of lights tripped a 600 W inverter "
            .. tostring(self.busyTrips) .. " times in 100, not some of the time")
    end,
    cleanup = cleanup,
})

-- The load scan finds a fridge in the bank's reach and bills it in watts with a start-up
-- surge; switching a plug-in inverter bank on with it trips the inverter, and a reset rolls
-- again.
test("renewable_energy_power_scan_finds_fridge_and_surge_trips", {
    run = function(self)
        gridOff(self)
        local generator, bank = newBank(self, Sprites.batteryBox, { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" }, 1)
        if not bank then return end
        self.without = Loads().scan(generator:getSquare())
        local fridgeSquare = outdoorSquares(1, self.used)[1]
        if not fridgeSquare then return end
        table.insert(self.squares, fridgeSquare)
        fridgeSquare:AddTileObject(IsoObject.new(fridgeSquare, FRIDGE, "Fridge", false))
        self.with = Loads().scan(generator:getSquare())
        PowerBank.perform(player(), "setBankOn", { bank = position(generator), on = true })
        self.trip = bank.status.inverter.trip
        self.state = bank.status.inverter.state
        self.powered = generator:isActivated()
        self.reset = PowerBank.perform(player(), "resetInverter", { bank = position(generator) })
        self.tripAfterReset = bank.trip
    end,
    validate = function(self)
        if not expect(self.with ~= nil, "no bank or free square for the fridge") then return end
        local fridgeW = self.with.watts - self.without.watts
        expect(fridgeW >= Specs.loads.fridge.watts, "the scan bills the fridge " .. fridgeW .. " W")
        expect(#self.with.motors > #self.without.motors, "the scan didn't count the fridge's compressor")
        -- Appliances the scenario left in reach can overload the 140 W inverter first.
        local expected = self.without.watts == 0 and "surge" or self.trip
        expect(self.trip ~= nil and self.trip == expected and self.state == "tripped",
            "switching on gave trip " .. tostring(self.trip) .. ", state " .. tostring(self.state))
        expect(not self.powered, "a tripped bank powers its area")
        expect(self.reset and self.tripAfterReset ~= nil and self.tripAfterReset ~= false, "a reset with the fridge still there didn't trip again")
    end,
    cleanup = cleanup,
})

-- A day's deepest discharge wears the batteries when the day turns.
test("renewable_energy_power_depth_of_discharge_wears_batteries", {
    sandbox = { BatteryWear = 100 },
    run = function(self)
        local generator, bank = newBank(self, Sprites.batteryBox, { "Base.CarBattery1" }, 1)
        if not bank then return end
        bank.cycleHigh = 1
        bank.charge = 0.5
        bank:trackCycle()
        self.depth = bank.cycleDepth
        bank.day = bank.day and bank.day - 1 or 0
        bank:newDay(generator:getContainer(), bank.day + 1)
        local battery = generator:getContainer():getFirstType("Base.CarBattery1")
        self.condition = battery and battery:getCondition()
        self.depthAfter = bank.cycleDepth
    end,
    validate = function(self)
        if not expect(self.depth ~= nil, "no bank was placed") then return end
        expectNear("cycle depth", self.depth, 0.5, 0.0001)
        expectNear("car battery condition after a 50% day", self.condition, 99, 0)
        expectNear("cycle depth on the new day", self.depthAfter, 0, 0)
    end,
    cleanup = cleanup,
})

-- A drained battery in deep cold cracks.
test("renewable_energy_power_drained_batteries_freeze", {
    run = function(self)
        local generator, bank = newBank(self, Sprites.batteryBox, { "Base.CarBattery1" }, 0.1)
        local generator2, warmBank = newBank(self, Sprites.batteryBox, { "Base.CarBattery1" }, 0.9)
        if not (bank and warmBank) then return end
        bank.tempC, warmBank.tempC = -20, -20
        bank:freeze(generator:getContainer(), 1000)
        warmBank:freeze(generator2:getContainer(), 1000)
        local drained = generator:getContainer():getFirstType("Base.CarBattery1")
        local charged = generator2:getContainer():getFirstType("Base.CarBattery1")
        self.drained = drained and drained:getCondition()
        self.charged = charged and charged:getCondition()
    end,
    validate = function(self)
        if not expect(self.drained ~= nil, "no bank was placed") then return end
        expectNear("condition of a drained battery after a deep freeze", self.drained, 0, 0)
        expect(self.charged > 0, "a charged battery cracked in the cold")
    end,
    cleanup = cleanup,
})

-- Four modules on a battery box overcharge it once it's full; a controller in a battery bank
-- takes them.
test("renewable_energy_power_uncontrolled_panels_overcharge", {
    run = function(self)
        local generator, box = newBank(self, Sprites.batteryBox, { "Base.CarBattery1" }, 1)
        local generator2, rack = newBank(self, Sprites.batteryBank, { "Base.CarBattery1", "RenewableEnergy.ChargeController" }, 1)
        if not (box and rack) then return end
        for _ = 1, 4 do
            local panel = newPanel(self, Sprites.flat)
            if panel then
                PowerBank.perform(nil, "connectSource", { bank = position(generator), source = position(panel) })
            end
            panel = newPanel(self, Sprites.flat)
            if panel then
                PowerBank.perform(nil, "connectSource", { bank = position(generator2), source = position(panel) })
            end
        end
        box:update(1, passContext(1000))
        rack:update(1, passContext(1000))
        self.box = box.status.controllers
        self.rack = rack.status.controllers
    end,
    validate = function(self)
        if not expect(self.box and self.rack, "no banks were placed") then return end
        expectNear("panel watts on the box", self.box.panelWatts, 200, 0)
        expectNear("uncontrolled watts on the box", self.box.uncontrolledWatts, 100, 0)
        expect(self.box.overcharging, "a full box with four modules isn't overcharging")
        expectNear("allowance of a bank with one controller", self.rack.allowanceWatts, 460, 0)
        expect(not self.rack.overcharging, "a bank with a controller overcharges")
    end,
    cleanup = cleanup,
})

-- A generator to back a bank up, on a square near it, with `failsafe` beside it.
local function newGenerator(self, near, running, failsafe)
    for dx = -2, 2 do
        for dy = -2, 2 do
            local square = getCell():getGridSquare(near:getX() + dx, near:getY() + dy, near:getZ())
            if square and not self.used[square] and square:isFree(false) and square:getObjects():size() == 1 then
                self.used[square] = true
                table.insert(self.squares, square)
                local item = instanceItem("Base.Generator")
                local generator = item and IsoGenerator.new(item, square:getCell(), square)
                if not generator then return nil end
                generator:setConnected(true)
                generator:setFuel(10)
                generator:setCondition(100)
                if failsafe then
                    square:AddTileObject(IsoObject.new(square, Sprites.failsafe, "Failsafe", false))
                end
                if running then
                    generator:setActivated(true)
                end
                return generator
            end
        end
    end
    return nil
end

-- A running backup generator charges a bank through an inverter/charger, burning more fuel;
-- through a plain inverter it only carries the load.
test("renewable_energy_power_generator_charges_through_inverter_charger", {
    run = function(self)
        gridOff(self)
        -- Three half-charged L-16s have room for an hour of the charger even in the cold.
        local bankGenerator, bank = newBank(self, Sprites.batteryBank,
            { "RenewableEnergy.L16Battery", "RenewableEnergy.L16Battery", "RenewableEnergy.L16Battery", "RenewableEnergy.InverterCharger" }, 0.5)
        if not bank then return end
        local backup = newGenerator(self, bankGenerator:getSquare(), true, false)
        if not backup then return end
        local fuel = backup:getFuel()
        local before = bank.charge * bank:capacityWh()
        bank:update(1, passContext(0))
        self.generatorW = bank.status.generatorW
        self.gained = bank.charge * bank:capacityWh() - before
        self.fuelUsed = fuel - backup:getFuel()
        self.carried = bank.status.drawW
        local container = bankGenerator:getContainer()
        container:Remove(container:getFirstType("RenewableEnergy.InverterCharger"))
        container:AddItem("RenewableEnergy.PowerInverter")
        bank:update(1, passContext(0))
        self.plainW = bank.status.generatorW
    end,
    validate = function(self)
        if not expect(self.generatorW ~= nil, "no bank or generator was placed") then return end
        expectNear("charger watts", self.generatorW, 1500, 0)
        expectNear("Wh gained in an hour", self.gained, 1500, 1)
        expectNear("extra fuel burned in an hour", self.fuelUsed, 1500 / Specs.loads.other.wattsPerConsumption * SandboxVars.GeneratorFuelConsumption, 0.001)
        expectNear("draw on the batteries while the generator runs", self.carried, 0, 0)
        expectNear("charger watts through a plain inverter", self.plainW, 0, 0)
    end,
    cleanup = cleanup,
})

-- A failsafe starts its generator when the bank runs low and stops it once it's charged.
test("renewable_energy_power_failsafe_starts_generator", {
    sandbox = { FailsafeStartCharge = 20, FailsafeStopCharge = 80 },
    run = function(self)
        gridOff(self)
        local bankGenerator, bank = newBank(self, Sprites.batteryBox, { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" }, 0.1)
        if not bank then return end
        local backup = newGenerator(self, bankGenerator:getSquare(), false, true)
        if not backup then return end
        bank.on = true
        bank:update(0.01, passContext(0))
        self.started = backup:isActivated()
        self.failsafe = bank.status.generator and bank.status.generator.failsafe
        bank.charge = 0.9
        bank:writeBatteries(bankGenerator:getContainer(), false)
        bank:update(0.01, passContext(0))
        self.stopped = not backup:isActivated()
    end,
    validate = function(self)
        if not expect(self.started ~= nil, "no bank or generator was placed") then return end
        expect(self.failsafe, "the bank didn't find the failsafe generator")
        expect(self.started, "the failsafe didn't start the generator at 10% charge")
        expect(self.stopped, "the failsafe didn't stop the generator at 90% charge")
    end,
    cleanup = cleanup,
})

-- Stands still for a moment, so the runner validates after the world has run some frames.
local Settle = ISBaseTimedAction:derive("RenewableEnergyTestSettle")

function Settle:new(character)
    local o = ISBaseTimedAction.new(self, character)
    o.maxTime = 60
    return o
end

function Settle:isValid()
    return true
end

-- Wire from a running vehicle charges the bank at the alternator's watts. The car
-- is wired up once it has stood in the world for a moment and has its physics.
test("renewable_energy_power_vehicle_charges_bank", {
    run = function(self)
        -- Two drained car batteries have room for an hour of the alternator even in the cold.
        local generator, bank = newBank(self, Sprites.batteryBox, { "Base.CarBattery1", "Base.CarBattery2" }, 0.2)
        if not bank then return end
        self.generator, self.bank = generator, bank
        local square
        for dx = 2, 3 do
            local candidate = getCell():getGridSquare(generator:getX() + dx, generator:getY(), generator:getZ())
            if candidate and candidate:isFree(false) and not candidate:getVehicleContainer() then
                square = candidate
                break
            end
        end
        if not square then return end
        self.vehicle = addVehicleDebug("Base.CarNormal", IsoDirections.N, nil, square)
        for _ = 1, PowerBank.VEHICLE_WIRE_COUNT do
            player():getInventory():AddItem(PowerBank.VEHICLE_WIRE)
        end
        ISTimedActionQueue.add(Settle:new(player()))
    end,
    validate = function(self)
        local vehicle, generator, bank = self.vehicle, self.generator, self.bank
        if not expect(vehicle ~= nil, "no bank or vehicle was placed") then return end
        local connected, reason = PowerBank.perform(player(), "connectVehicle", { bank = position(generator), vehicle = vehicle:getId() })
        if not expect(connected, "connecting the vehicle failed: " .. tostring(reason) .. "; car at "
            .. vehicle:getX() .. "," .. vehicle:getY() .. "," .. vehicle:getZ() .. ", bank at " .. generator:getX() .. "," .. generator:getY()) then
            return
        end
        expectNear("wire left in the inventory", player():getInventory():getCountTypeRecurse(PowerBank.VEHICLE_WIRE), 0, 0)
        vehicle:engineDoRunning()
        local before = bank.charge * bank:capacityWh()
        bank:update(1, passContext(0))
        local gained = bank.charge * bank:capacityWh() - before
        local name = bank.status.vehicle and bank.status.vehicle.name
        expect(name == "CarNormal", "the status names the vehicle " .. tostring(name))
        if vehicle:isEngineRunning() then
            expectNear("vehicle watts", bank.status.vehicleW, Specs.vehicleWatts, 0)
            expectNear("Wh gained in an hour", gained, Specs.vehicleWatts, 0.5)
        else
            print("RETest NOTE renewable_energy_power_vehicle_charges_bank: the debug car's engine wouldn't run")
            expectNear("watts from a stopped vehicle", bank.status.vehicleW, 0, 0)
        end
        expect(PowerBank.perform(player(), "disconnectVehicle", { bank = position(generator) }), "disconnecting the vehicle failed")
        expectNear("wire back in the inventory", player():getInventory():getCountTypeRecurse(PowerBank.VEHICLE_WIRE),
            PowerBank.VEHICLE_WIRE_COUNT, 0)
    end,
    cleanup = function(self)
        if self.vehicle then
            self.vehicle:shutOff()
            self.vehicle:permanentlyRemove()
        end
        cleanup(self)
    end,
})

-- Clients send commands through OnClientCommand, which must survive bad arguments and refuse
-- what the world doesn't allow; the status it sends reaches the client's copy of the bank.
test("renewable_energy_power_commands_from_clients", {
    run = function(self)
        local generator, bank = newBank(self, Sprites.batteryBox, { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" }, 1)
        if not bank then return end
        local sys = system()
        self.position = position(generator)
        sys:OnClientCommand("noSuchCommand", player(), { bank = self.position })
        sys:OnClientCommand("setBankOn", player(), { bank = "nonsense" })
        self.badSource = PowerBank.perform(player(), "connectSource", { bank = self.position, source = self.position })
        self.noArgs = PowerBank.perform(player(), "connectSource", nil)
        local panel = newPanel(self, Sprites.rack.S)
        if panel then
            PowerBank.perform(player(), "connectSource", { bank = self.position, source = position(panel) })
            local source = bank:findSource(panel:getX(), panel:getY(), panel:getZ())
            if source then source.snow = 0.8 end
            self.cleared = PowerBank.perform(player(), "clearSnow", { source = position(panel) })
            self.snow = source and source.snow
            self.disconnected = PowerBank.perform(player(), "disconnectSource", { source = position(panel) })
            self.sourcesLeft = #bank.sources
        end
        self.noWire = PowerBank.perform(player(), "connectVehicle", { bank = self.position, vehicle = 1 })
        sys:OnClientCommand("setBankOn", player(), { bank = self.position, on = true })
        self.serverOn = bank.on
    end,
    validate = function(self)
        if not expect(self.position ~= nil, "no bank was placed") then return end
        expect(not self.badSource, "a bank was connected to itself as a panel")
        expect(not self.noArgs, "a command without arguments succeeded")
        expect(self.cleared and self.snow == 0, "clearing snow left " .. tostring(self.snow))
        expect(self.disconnected and self.sourcesLeft == 0, "disconnecting the panel left " .. tostring(self.sourcesLeft) .. " sources")
        expect(not self.noWire, "a vehicle was connected without wire or a vehicle")
        expect(self.serverOn, "setBankOn through OnClientCommand didn't switch the bank on")
        local client = PowerBank.clientSystem
        local copy = client and client.system:getObjectAt(self.position.x, self.position.y, self.position.z)
        local status = copy and copy:getModData().status
        expect(status and status.on == true and status.kind == "batteryBox", "the client's copy of the status doesn't show the bank on")
    end,
    cleanup = cleanup,
})

-- A removed running bank leaves nothing powered and is forgotten.
test("renewable_energy_power_removed_bank_leaves_no_power", {
    run = function(self)
        gridOff(self)
        local generator, bank = newBank(self, Sprites.batteryBox, { "Base.CarBattery1", "RenewableEnergy.PlugInInverter" }, 1)
        if not bank then return end
        local square = generator:getSquare()
        PowerBank.perform(player(), "setBankOn", { bank = position(generator), on = true })
        self.wasPowered = square:haveElectricity()
        PowerBank.remove(generator)
        self.powered = square:haveElectricity()
        self.registered = system():getLuaObjectOnSquare(square) ~= nil
    end,
    validate = function(self)
        if not expect(self.wasPowered ~= nil, "no bank was placed") then return end
        expect(not self.powered, "the removed bank's square still has power")
        expect(not self.registered, "the removed bank is still registered")
    end,
    cleanup = cleanup,
})
