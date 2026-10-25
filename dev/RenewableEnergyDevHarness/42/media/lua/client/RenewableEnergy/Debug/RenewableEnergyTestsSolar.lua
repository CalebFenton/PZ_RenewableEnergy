require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"

-- Solar: the sun model (Sun.lua) and panels feeding a bank (PowerBank/PanelSource.lua, Sources.lua):
-- module condition, panel slots, reconnecting, snow and roofs.

local T = RenewableEnergyTest
local test, expect, expectNear = T.test, T.expect, T.expectNear
local Specs, Sprites, Sun = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun
local CAR_BATTERY = "Base.CarBattery1"
local HOMEMADE = "RenewableEnergy.HomemadeSolarModule"

-- Sun -----------------------------------------------------------------------------------------

local LATITUDE = 38
local SOLSTICE = 172
local CLEAR = Sun.CLEAR_WEATHER

-- Weather with no fog, rain or snow, and `cloud` cover from 0 to 1.
local function cloudy(cloud)
    return { cloud = cloud, fog = 0, rain = 0, snowing = false, groundSnow = 0 }
end

-- Light on each mount summed over a year (or the given months), under the yardsticks' guessed mix
-- of clear, broken and overcast days (Loot.WEATHER_MIX). One day a week at half-hour steps keeps
-- it cheap.
local function yearTotals(months)
    local Loot = RenewableEnergy.Loot
    local totals = { flat = 0, rack = 0, wall = 0 }
    local dayStep, step = 7, 0.5
    for day = 1, 365, dayStep do
        local month = math.min(12, math.floor((day - 1) / 30.42) + 1)
        if not months or months[month] then
            for hour = -12, 12 - step, step do
                local sun = Sun.position(day, hour, LATITUDE)
                for name, mount in pairs(Loot.SOUTH_MOUNTS) do
                    for _, part in ipairs(Loot.WEATHER_MIX) do
                        totals[name] = totals[name] + part[1] * Sun.planeIrradiance(sun, mount[1], mount[2], part[2]) * step * dayStep
                    end
                end
            end
        end
    end
    return totals
end

-- Louisville's measured insolation, kWh/m²/day: NSRDB 1961-1990 monthly averages, station 93821
-- (latitude 38.18°). The Sunlight Multiplier's 1 is anchored to it.
local MEASURED = { flat = 4.11, wall = 2.96, rack = 4.59 }

-- Over a year, flat and south-wall panels make against a 38° rack what Louisville's measurements
-- say, and a south wall beats a flat panel in December. The weather mix is a guess, so the
-- absolute total gets a wide margin; the ratios depend on it far less.
test("renewable_energy_solar_sun_year_matches_measured_insolation", {
    run = function(self)
        self.year = yearTotals(nil)
        self.december = yearTotals({ [12] = true })
    end,
    validate = function(self)
        local year, december = self.year, self.december
        expectNear("flat / rack over a year", year.flat / year.rack, MEASURED.flat / MEASURED.rack, 0.04)
        expectNear("south wall / rack over a year", year.wall / year.rack, MEASURED.wall / MEASURED.rack, 0.04)
        expectNear("rack kWh/m² a day", year.rack / 365 / 1000, MEASURED.rack, 0.8)
        expect(december.wall > december.flat, "a south wall makes less than a flat panel in December")
    end,
})

-- The sun at noon on the June solstice stands at 90° less the latitude plus the axial tilt, sits
-- on the horizon at the end of the half day and makes nothing at night; the game's dawn is sunrise.
test("renewable_energy_solar_sun_noon_dawn_night", {
    run = function(self)
        self.noon = math.deg(math.asin(Sun.position(SOLSTICE, 0, LATITUDE).up))
        local halfDay = Sun.halfDayHours(SOLSTICE, LATITUDE)
        self.sunset = Sun.position(SOLSTICE, halfDay, LATITUDE).up
        self.night = Sun.planeIrradiance(Sun.position(SOLSTICE, 12, LATITUDE), "flat", nil, CLEAR)
        local season = getClimateManager():getSeason()
        local hoursSinceDawn = getGameTime():getTimeOfDay() - season:getDawn()
        self.dawn = Sun.positionNow(hoursSinceDawn).up
        self.noonWatts = Sun.planeIrradiance(Sun.position(SOLSTICE, 0, LATITUDE), "flat", nil, CLEAR)
        self.morningWatts = Sun.planeIrradiance(Sun.position(SOLSTICE, -2, LATITUDE), "flat", nil, CLEAR)
    end,
    validate = function(self)
        expectNear("noon elevation on the solstice", self.noon, 90 - LATITUDE + 23.44, 0.1)
        expectNear("sun height at sunset", self.sunset, 0, 0.001)
        expectNear("light at midnight", self.night, 0, 0)
        expectNear("sun height at the game's dawn", self.dawn, 0, 0.01)
        expect(self.noonWatts > self.morningWatts and self.noonWatts < Sun.FULL_SUN, string.format(
            "noon light on a flat panel is %.1f W/m², two hours earlier %.1f", self.noonWatts, self.morningWatts))
    end,
})

-- Overcast lets some light through, all of it diffuse, so a rack loses its edge from facing the sun.
test("renewable_energy_solar_sun_clouds", {
    run = function(self)
        local sun = Sun.position(SOLSTICE, 0, LATITUDE)
        local overcast = cloudy(1)
        local function ratio(kind, facing)
            return Sun.planeIrradiance(sun, kind, facing, overcast) / Sun.planeIrradiance(sun, kind, facing, CLEAR)
        end
        self.flat, self.rack = ratio("flat"), ratio("rack", "S")
        self.south = Sun.planeIrradiance(sun, "rack", "S", overcast)
        self.north = Sun.planeIrradiance(sun, "rack", "N", overcast)
    end,
    validate = function(self)
        expect(self.flat > 0 and self.flat < 1, "overcast leaves a flat panel " .. self.flat .. " of clear-sky light")
        expect(self.rack < self.flat, "clouds cost a rack less than a flat panel")
        expectNear("overcast on a south rack against a north one", self.south, self.north, 0.0001)
    end,
})

-- The Sunlight Multiplier scales what a panel makes and snow blocks it; a garden light's cell
-- under a roof makes nothing, and in the open at noon what a flat panel does.
test("renewable_energy_solar_sun_watts_multiplier_snow_roof", {
    hour = 12,
    sandbox = { SunlightMultiplier = 1 },
    run = function(self)
        self.real = Sun.wattsFrom(50, Sun.FULL_SUN, 0)
        T.setSandbox(self, "SunlightMultiplier", 3)
        self.boosted = Sun.wattsFrom(50, Sun.FULL_SUN, 0)
        self.snowed = Sun.wattsFrom(50, Sun.FULL_SUN, 1)
        self.noSquare = Sun.squareWatts(nil, 50)
        local indoor = T.square(self, { indoors = true }, "a free indoor square")
        local outdoor = T.square(self, {}, "a free outdoor square")
        if not (indoor and outdoor) then return end
        self.indoors = Sun.squareWatts(indoor, 50)
        self.outdoors = Sun.squareWatts(outdoor, 50)
        self.flatWatts = Sun.wattsFrom(50, Sun.skyNow().flat)
    end,
    validate = function(self)
        expect(self.real > 0 and self.real <= 50, "a 50 W module in full sun makes " .. self.real .. " W")
        expectNear("a module at x3 over x1", self.boosted / self.real, 3, 0.0001)
        expectNear("the same under snow", self.snowed, 0, 0)
        expectNear("a cell with no square", self.noSquare, 0, 0)
        expectNear("a cell under a roof at noon", self.indoors, 0, 0)
        expectNear("a cell in the open at noon", self.outdoors, self.flatWatts, 0.0001)
        expect(self.outdoors > 0, "a cell in the open at noon makes nothing")
    end,
})

-- Panels on a bank ----------------------------------------------------------------------------

-- A module makes its rating times its condition: a half-worn module half what a whole one does,
-- a homemade one at its best less than a whole factory one, and a rack with a whole and a
-- shattered module what the whole one makes alone. The cracked panel says why it is low.
test("renewable_energy_solar_module_condition_sets_watts", {
    run = function(self)
        local bank = T.bank(self, "batteryRackMetal", { CAR_BATTERY, Specs.controller }, { charge = 0.1 })
        if not bank then return end
        self.bank = bank
        local modules = {
            T.factoryModules(50),
            { { type = HOMEMADE, condition = getScriptManager():getItem(HOMEMADE):getConditionMax() } },
            T.factoryModules(100, 0),
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
            if not T.expectConnected(panel) then return end
        end
        local sources = self.bank.state.status.sources
        local cracked, homemade, rack = sources[1], sources[2], sources[3]
        if not expect(cracked and homemade and rack, "the status lists fewer than three panels") then return end
        -- The rack's whole module is the measure: same type, same sun.
        local whole = rack.watts
        expect(whole > 0, "a rack with a whole module made nothing at 1000 W/m²")
        expectNear("a module at condition 50 over a whole one", cracked.watts / whole, 0.5, 0.01)
        local made = homemade.watts / whole
        expect(made > 0 and made < 1, "a homemade module at its best makes " .. made .. " of a whole factory one")
        expect(cracked.reason == "cracked", "the half-cracked panel's reason is " .. tostring(cracked.reason))
        expect(cracked.modules[1] and cracked.modules[1].condition == 50, "the status lost the module's condition")
    end,
})

-- A bank takes Specs.freeSlots panels with no controller and Specs.slotsPerController more per
-- controller, each up to exactly its slots and refusing one more; panels past the slots of a
-- controller taken out stay connected but make nothing. Catches an off-by-one in the slot count
-- and a controller's slots not counted.
test("renewable_energy_solar_panel_slots", {
    run = function(self)
        local box = T.bank(self, "batteryBoxWood", { CAR_BATTERY }, { charge = 0.1 })
        local batteryRack = box and T.bank(self, "batteryRackWood", { CAR_BATTERY, Specs.controller }, { charge = 0.1 })
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

-- The status entry of the panel handle `panel` in a bank state, or an empty one when the status
-- doesn't list it.
local function entryOf(state, panel)
    return T.stateSource(state, panel.position) or {}
end

-- Connecting a panel again to the bank it feeds leaves it as it was, snow included, and a bank
-- whose panel slots are all taken doesn't turn its own panel away as if there were no room.
test("renewable_energy_solar_reconnecting_a_panel_keeps_it", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", {})
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not panel then return end
        self.panel = panel
        local args = { bank = bank.position, source = panel.position }
        -- A refresh after each try builds the status from the record again, whatever the try sent.
        local function tryAgain(key)
            T.performInto(self, key, "connectSource", args)
            T.perform(self, "refresh", { bank = bank.position })
            T.bankState(self, bank)
            T.step(function() self[key].state = bank.state end)
        end
        T.batch(function()
            T.snowfall(self, bank)
            T.step(function() self.snowed = entryOf(bank.state, panel).snow end)
            tryAgain("again")
            self.second = T.panel(self, Sprites.flat, { near = bank, connect = true })
            if not self.second then return end
            tryAgain("full")
        end)
    end,
    validate = function(self)
        if not expect(self.panel.connected and self.second.connected, "connecting the panels failed ("
            .. tostring(self.panel.reason) .. ", " .. tostring(self.second.reason) .. ")") then return end
        if not expect((self.snowed or 0) > 0, "a night of snowfall left no snow on the panel") then return end
        for _, case in ipairs({ { self.again, 1, "a bank" }, { self.full, 2, "a full bank" } }) do
            local reply, panels, what = case[1], case[2], case[3]
            expect(reply.state.sources == panels, "connecting a panel to " .. what .. " it feeds left "
                .. reply.state.sources .. " panels")
            -- Connecting brings the bank up to now first, which may melt a trace of it.
            expectNear("snow on a panel connected again to " .. what .. " it feeds", entryOf(reply.state, self.panel).snow or -1,
                self.snowed, 0.01)
        end
        expect(self.full.reason ~= "Tooltip_RenewableEnergy_NoInputSlot",
            "a full bank turned its own panel away for want of a slot")
    end,
})

-- Whether this client's copy of the panel handle `panel` draws snow on its tile.
local function showsSnow(panel)
    local attached = panel.object:getAttachedAnimSprite()
    for i = 0, (attached and attached:size() or 0) - 1 do
        if Sprites.isSnow(attached:get(i):getName()) then
            return true
        end
    end
    return false
end

-- Snow falling on a frosty night settles on a flat panel and a rack, and this client's copies of
-- them show it. In the sun it takes its share of what a panel makes, beside a panel swept clean;
-- the sun melts it, the rack's tilt sheds it faster, and mild air takes the rest.
test("renewable_energy_solar_snow_settles_dims_and_melts", {
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { CAR_BATTERY, Specs.controller }, { charge = 0.2 })
        self.flat = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        self.rack = self.flat and T.panel(self, Sprites.rack.wood.S, { near = bank, connect = true })
        self.clean = self.rack and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not self.clean then return end
        self.bank = bank
        T.batch(function()
            T.snowfall(self, bank, 2)
            T.step(function() self.night = bank.state end)
            T.perform(self, "clearSnow", { source = self.clean.position })
        end)
        T.waitFor(self, function() return showsSnow(self.flat) and showsSnow(self.rack) end,
            "this client's copies of the snowy panels showing snow")
        T.step(function() self.cleanShowed = showsSnow(self.clean) end)
        T.bankPass(self, bank, Sun.FULL_SUN, { airC = -10 })
        T.step(function() self.sunny = bank.state end)
        T.waitFor(self, function() return showsSnow(self.flat) and not showsSnow(self.rack) end,
            "this client's copy of the rack showing its snow shed")
        T.bankPass(self, bank, Sun.FULL_SUN, { hours = 10 })
        T.waitFor(self, function() return not showsSnow(self.flat) end, "this client's copy of the flat panel thawed")
    end,
    validate = function(self)
        local connected = self.flat.connected and self.rack.connected and self.clean.connected
        if not expect(connected, "connecting the panels failed") then return end
        local flat, rack = entryOf(self.night, self.flat), entryOf(self.night, self.rack)
        expect((flat.snow or 0) > 0 and rack.snow == flat.snow, string.format(
            "a frosty night of snowfall left %s on the flat panel and %s on the rack", tostring(flat.snow), tostring(rack.snow)))
        expect(not self.cleanShowed, "this client's copy of the swept panel still shows snow")
        flat, rack = entryOf(self.sunny, self.flat), entryOf(self.sunny, self.rack)
        local clean = entryOf(self.sunny, self.clean)
        if not expect((clean.watts or 0) > 0, "the swept panel made nothing in full sun") then return end
        -- Snow covers its share of the panel, and that share of the sun goes nowhere.
        expectNear("the snowy flat panel's watts against the swept one's", flat.watts / clean.watts, 1 - flat.snow, 1e-6)
        expectNear("the snowy flat panel's share of full sun", flat.fullSunPct, round(100 * (1 - flat.snow)), 0)
        expect(flat.snow > 0 and flat.snow < entryOf(self.night, self.flat).snow,
            "an hour of full sun took the flat panel's snow from " .. entryOf(self.night, self.flat).snow .. " to " .. flat.snow)
        expect(rack.snow < flat.snow, "the rack, which sheds snow, kept " .. rack.snow .. " against the flat panel's " .. flat.snow)
        local thawed = entryOf(self.bank.state, self.flat)
        expectNear("snow on the flat panel after a mild sunny day", thawed.snow, 0, 0)
        expectNear("the thawed panel's share of full sun", thawed.fullSunPct, 100, 0)
    end,
})

-- A panel roofed over after it was connected, by a floor built above it, is no longer outdoors:
-- the next pass drops it and it makes nothing, as connecting it there would be refused. Catches a
-- panel checked for being outdoors only when it is connected.
test("renewable_energy_solar_roofed_panel_makes_nothing", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY }, { charge = 0.5 })
        self.panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not self.panel then return end
        T.batch(function()
            T.bankPass(self, bank, 1000)
            T.bankState(self, bank)
            T.step(function() self.open = bank.state end)
            T.server(self, "roofOver", self.panel.position)
            T.bankPass(self, bank, 1000)
            T.bankState(self, bank)
            T.step(function() self.roofed = bank.state end)
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        expect(self.open.status.solarW > 0, "the panel in the open made nothing at 1000 W/m²")
        expect(self.server.roofOver.outside == false, "a floor built above the panel left its square outdoors")
        expect(self.roofed.sources == 0, "the roofed panel still feeds the bank")
        expectNear("solar watts under the roof", self.roofed.status.solarW, 0, 0)
        expect(self.roofed.storedWh <= self.open.storedWh, string.format(
            "the bank gained %.2f Wh in the hour after its panel was roofed over", self.roofed.storedWh - self.open.storedWh))
    end,
})
