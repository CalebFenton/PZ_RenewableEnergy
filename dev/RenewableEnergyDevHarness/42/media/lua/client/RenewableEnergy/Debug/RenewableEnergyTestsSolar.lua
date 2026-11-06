require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local Specs = require "RenewableEnergy/Specs"
local Sun = require "RenewableEnergy/Sun"
local Yardsticks = require "RenewableEnergy/Debug/RenewableEnergyYardsticks"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local Sprites = require "RenewableEnergy/Sprites"

-- Solar: the sun model (Sun.lua) and panels feeding a bank (PowerBank/PanelSource.lua, Sources.lua):
-- module condition, panel slots, reconnecting, snow and roofs.

local T = RenewableEnergyTest
local test, expect, expectNear, expectEqual = T.test, T.expect, T.expectNear, T.expectEqual

-- Sun -----------------------------------------------------------------------------------------

local LATITUDE = 38
local SOLSTICE = 172
local CLEAR = Sun.CLEAR_WEATHER

-- Light on each mount summed over a year (or the given months), under the yardsticks' guessed mix
-- of clear, broken and overcast days. One day a week at half-hour steps keeps it cheap.
local function yearTotals(months)
    local totals = { flat = 0, rack = 0, wall = 0 }
    local dayStep, step = 7, 0.5
    for day = 1, 365, dayStep do
        local month = math.min(12, math.floor((day - 1) / 30.42) + 1)
        if not months or months[month] then
            for name, mount in pairs(Yardsticks.SOUTH_MOUNTS) do
                totals[name] = totals[name] + Yardsticks.dayIrradiance(day, mount, Yardsticks.WEATHER_MIX, LATITUDE, step) * dayStep
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
-- on the horizon at the end of the half day and makes nothing at night. Under a clear sky a flat
-- panel's direct, sky and ground shares add back up to the light on open ground, which falls off
-- with the sun's height by the air-mass fit.
test("renewable_energy_solar_sun_noon_night", {
    run = function(self)
        self.noon = math.deg(math.asin(Sun.position(SOLSTICE, 0, LATITUDE).up))
        local halfDay = Sun.halfDayHours(SOLSTICE, LATITUDE)
        self.sunset = Sun.position(SOLSTICE, halfDay, LATITUDE).up
        self.night = Sun.planeIrradiance(Sun.position(SOLSTICE, 12, LATITUDE), "flat", nil, CLEAR)
        self.noonWatts = Sun.planeIrradiance(Sun.position(SOLSTICE, 0, LATITUDE), "flat", nil, CLEAR)
        self.morningWatts = Sun.planeIrradiance(Sun.position(SOLSTICE, -2, LATITUDE), "flat", nil, CLEAR)
    end,
    validate = function(self)
        expectNear("noon elevation on the solstice", self.noon, 90 - LATITUDE + 23.44, 0.1)
        expectNear("sun height at sunset", self.sunset, 0, 0.001)
        expectEqual("light at midnight", self.night, 0)
        -- 1000 W/m² × sin(75.44°)^1.15 = 1000 × 0.96788^1.15 = 963.16 W/m².
        expectNear("noon light on a flat panel on the solstice, W/m²", self.noonWatts, 963.16, 0.05)
        expect(self.noonWatts > self.morningWatts and self.morningWatts > 0, string.format(
            "noon light on a flat panel is %.1f W/m², two hours earlier %.1f", self.noonWatts, self.morningWatts))
    end,
})

-- The game draws its own dawn and dusk (ErosionSeason: dawn and dusk half the day's daylight either
-- side of the day's high noon), and the sun the panels see rises at the game's dawn, stands at
-- solar noon at the game's high noon and sets at its dusk, today, whatever the hour now. Catches a
-- sun that makes power in the game's dark or none in its light. The day of the year counts from
-- January 1st as 1, which the declination needs.
test("renewable_energy_solar_sun_rises_and_sets_with_the_game", {
    run = function(self)
        local season, time = getClimateManager():getSeason(), getGameTime()
        local now = time:getTimeOfDay()
        local noon, halfDay = season:getDayHighNoon(), season:getDaylight() / 2
        self.halfDay = halfDay
        self.dayOfYear = Sun.dayOfYear(time:getMonth(), time:getDay())
        self.latitude = season:getLat()
        self.dawn = Sun.positionNow(now - (noon - halfDay)).up
        self.noon = Sun.positionNow(now - noon).up
        self.dusk = Sun.positionNow(now - (noon + halfDay)).up
        self.beforeDawn = Sun.positionNow(now - (noon - halfDay) + 0.5).up
        self.afterDusk = Sun.positionNow(now - (noon + halfDay) - 0.5).up
        self.days = { Sun.dayOfYear(0, 0), Sun.dayOfYear(1, 27), Sun.dayOfYear(5, 20), Sun.dayOfYear(11, 30) }
    end,
    validate = function(self)
        if not expect(self.halfDay > 0 and self.halfDay < 12, "the game's day lasts " .. 2 * self.halfDay .. " hours") then return end
        expectNear("the sun's height at the game's dawn", self.dawn, 0, 1e-4)
        expectNear("the sun's height at the game's dusk", self.dusk, 0, 1e-4)
        expectNear("the sun's height at the game's high noon", self.noon, Sun.position(self.dayOfYear, 0, self.latitude).up, 1e-6)
        expect(self.beforeDawn < 0 and self.afterDusk < 0, string.format(
            "half an hour before the game's dawn the sun stands at %g, half an hour after its dusk at %g", self.beforeDawn, self.afterDusk))
        -- January 1st, February 28th, June 21st (151 days before June, + 21), December 31st.
        expectEqual("days of the year", table.concat(self.days, ","), "1,59,172,365")
    end,
})

-- A catch-up pass samples the sun up to a week back (BankSystem.passContext): a sample whole days
-- ago stands where the sun stands that hour today.
test("renewable_energy_solar_sun_whole_days_ago_same_hour", {
    hour = 12,
    run = function(self)
        self.differ = {}
        for _, offset in ipairs({ 0, 3, 15 }) do
            local today = Sun.positionNow(offset)
            for days = 1, 7 do
                local back = Sun.positionNow(offset + 24 * days)
                local apart = math.max(math.abs(back.up - today.up), math.abs(back.east - today.east),
                    math.abs(back.north - today.north))
                if apart > 1e-6 then
                    table.insert(self.differ, string.format("%d h + %d days", offset, days))
                end
            end
        end
    end,
    validate = function(self)
        expectEqual("samples whole days back that stand elsewhere than today's", table.concat(self.differ, ", "), "")
    end,
})

-- Overcast lets a quarter of the light through, all of it diffuse, so a rack loses its edge from
-- facing the sun: it sees the sky its tilt leaves it and some ground, whichever way it faces.
test("renewable_energy_solar_sun_clouds", {
    run = function(self)
        local sun = Sun.position(SOLSTICE, 0, LATITUDE)
        local overcast = Yardsticks.cloudy(1)
        local function ratio(kind, facing)
            return Sun.planeIrradiance(sun, kind, facing, overcast) / Sun.planeIrradiance(sun, kind, facing, CLEAR)
        end
        self.flat, self.rack = ratio("flat"), ratio("rack", "S")
        self.overcastFlat = Sun.planeIrradiance(sun, "flat", nil, overcast)
        self.south = Sun.planeIrradiance(sun, "rack", "S", overcast)
        self.north = Sun.planeIrradiance(sun, "rack", "N", overcast)
    end,
    validate = function(self)
        -- Full cloud stops 75% of the light (Sun.lua's cloud loss): 1 - 0.75.
        expectNear("overcast against clear sky on a flat panel", self.flat, 0.25, 1e-9)
        expect(self.rack < self.flat, "clouds cost a rack less than a flat panel")
        -- All diffuse: the sky a 38° tilt sees, (1 + cos 38°) / 2 = 0.89401, plus ground at albedo
        -- 0.2, 0.2 × (1 - cos 38°) / 2 = 0.02120: 0.91520 of what a flat panel gets.
        expectNear("overcast on a south rack against a flat panel", self.south / self.overcastFlat, 0.91520, 1e-5)
        expectNear("overcast on a south rack against a north one", self.south, self.north, 0.0001)
    end,
})

-- A tilted panel takes the sun on the side it faces: at noon a south rack beats a north one, in
-- the morning an east rack beats a west one, and a north wall, which the noon sun never reaches
-- here, sees only sky and ground. Catches a facing turned the wrong way.
test("renewable_energy_solar_sun_mounts_face_the_sun", {
    run = function(self)
        local december = 355
        local noon, morning = Sun.position(december, 0, LATITUDE), Sun.position(SOLSTICE, -3, LATITUDE)
        local function light(sun, kind, facing) return Sun.planeIrradiance(sun, kind, facing, CLEAR) end
        self.south, self.north = light(noon, "rack", "S"), light(noon, "rack", "N")
        self.east, self.west = light(morning, "rack", "E"), light(morning, "rack", "W")
        self.northWall, self.flat = light(noon, "wall", "N"), light(noon, "flat")
    end,
    validate = function(self)
        expect(self.south > self.north, string.format("at noon a south rack gets %.1f W/m², a north one %.1f", self.south, self.north))
        expect(self.east > self.west, string.format("in the morning an east rack gets %.1f W/m², a west one %.1f", self.east, self.west))
        -- Clear sky: the sky's 0.15 share over half a wall's view, 0.15 × (1 + cos 90°) / 2 = 0.075,
        -- plus ground at albedo 0.2 over the other half, 0.2 × (1 - cos 90°) / 2 = 0.1.
        expectNear("a north wall at noon in December against a flat panel", self.northWall / self.flat, 0.175, 1e-9)
    end,
})

-- A module makes its rating times the system efficiency and the share of full sun, the Sunlight
-- Multiplier scales that and snow blocks its share; a garden light's cell under a roof makes
-- nothing, and one in the open makes what open flat ground's light gives it.
test("renewable_energy_solar_sun_watts_multiplier_snow_roof", {
    hour = 12,
    sandbox = { SunlightMultiplier = 1 },
    run = function(self)
        self.real = Sun.wattsFrom(50, Sun.FULL_SUN, 0)
        T.setSandbox(self, "SunlightMultiplier", 3)
        self.boosted = Sun.wattsFrom(50, Sun.FULL_SUN, 0)
        self.snowed = Sun.wattsFrom(50, Sun.FULL_SUN, 1)
        self.partly = Sun.wattsFrom(50, Sun.FULL_SUN / 2, 0.25)
        local sky = Sun.skyNow()
        self.sky = sky
        self.noSquare = Sun.squareWatts(nil, 50, sky)
        local indoor = T.square(self, { indoors = true }, "a free indoor square")
        local outdoor = T.square(self, {}, "a free outdoor square")
        if not (indoor and outdoor) then return end
        self.indoors = Sun.squareWatts(indoor, 50, sky)
        self.outdoors = Sun.squareWatts(outdoor, 50, sky)
    end,
    validate = function(self)
        expectNear("a 50 W module in full sun", self.real, 50 * T.SOLAR_EFFICIENCY, 1e-9)
        expectNear("a 50 W module in full sun at x3", self.boosted, 3 * 50 * T.SOLAR_EFFICIENCY, 1e-9)
        expectEqual("the same under snow", self.snowed, 0)
        -- 50 W × half sun 0.5 × 0.8 × 3 × a quarter snowed over (1 - 0.25) = 45 W.
        expectNear("a 50 W module in half sun, a quarter snowed over, at x3", self.partly, 45, 1e-9)
        expectEqual("a cell with no square", self.noSquare, 0)
        expectEqual("a cell under a roof at noon", self.indoors, 0)
        if not expect(self.sky.flat > 0, "no light on open ground at noon") then return end
        expectNear("a 50 W cell in the open at noon at x3", self.outdoors,
            50 * self.sky.flat / Sun.FULL_SUN * T.SOLAR_EFFICIENCY * 3, 1e-9)
    end,
})

-- Panels on a bank ----------------------------------------------------------------------------

-- A module makes its rating times its condition: a half-worn module half what a whole one does,
-- and a homemade one at its best its type's rating against a factory one's. The cracked panel says
-- why it is low.
test("renewable_energy_solar_module_condition_sets_watts", {
    run = function(self)
        local bank = T.bank(self, "batteryRackMetal", { T.CAR_BATTERY, Specs.controller }, { charge = 0.1 })
        if not bank then return end
        self.bank = bank
        local modules = {
            T.factoryModules(50),
            { { type = T.HOMEMADE_MODULE, condition = getScriptManager():getItem(T.HOMEMADE_MODULE):getConditionMax() } },
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
        expectNear("a rack with one whole module at 1000 W/m²", whole,
            T.fullSunW(Specs.modules[T.FACTORY_MODULE].watts), 1e-9)
        expectNear("a module at condition 50 over a whole one", cracked.watts / whole, 0.5, 1e-9)
        expectNear("a homemade module at its best over a whole factory one", homemade.watts / whole,
            Specs.modules[T.HOMEMADE_MODULE].watts / Specs.modules[T.FACTORY_MODULE].watts, 1e-9)
        expectEqual("the half-cracked panel's reason", cracked.reason, "cracked")
        expectEqual("the half-cracked panel's module condition", cracked.modules[1] and cracked.modules[1].condition, 50)
    end,
})

-- A bank takes Specs.freeSlots panels with no controller and Specs.slotsPerController more per
-- controller, each up to exactly its slots and refusing one more; panels past the slots of a
-- controller taken out stay connected but make nothing. Catches an off-by-one in the slot count
-- and a controller's slots not counted.
test("renewable_energy_solar_panel_slots", {
    run = function(self)
        local box = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY }, { charge = 0.1 })
        local batteryRack = box and T.bank(self, "batteryRackWood", { T.CAR_BATTERY, Specs.controller }, { charge = 0.1 })
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
            T.server(self, "bankPart", T.at(batteryRack, { type = Specs.controller, remove = true }))
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
            expect(not extra.connected, what .. " took a panel past its " .. slots .. " slots")
            expectEqual(what .. ": the refusal of a panel past its slots", extra.reason, "Tooltip_RenewableEnergy_NoInputSlot")
        end
        expectSlots(self.boxPanels, Specs.freeSlots, "a battery box without a controller")
        local withController = Specs.freeSlots + Specs.slotsPerController
        expectSlots(self.rackPanels, withController, "a battery rack with a controller")
        local status = self.rack.state.status
        local slots, last, past = status.inputSlots, status.sources[Specs.freeSlots], status.sources[Specs.freeSlots + 1]
        if not expectEqual("panels still connected when the controller left", #status.sources, withController) then return end
        expectEqual("panel slots used", slots.used, withController)
        expectEqual("panel slots in all", slots.total, Specs.freeSlots)
        expectEqual("watts of a panel past the slots", past.watts, 0)
        expectEqual("the reason of a panel past the slots", past.reason, "noController")
        expectNear("watts of the last panel within the free slots at 1000 W/m²", last.watts, T.flatPanelW(), 1e-9)
    end,
})

-- Connecting a panel again to the bank it feeds is refused as already connected and leaves it as
-- it was, snow included, also when the bank's panel slots are all taken: the bank doesn't turn its
-- own panel away as if there were no room.
test("renewable_energy_solar_reconnecting_a_panel_keeps_it", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", {})
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not panel then return end
        self.panel = panel
        -- A refresh after each try builds the status from the record again, whatever the try sent.
        local function tryAgain(label)
            T.job(self, "source", SourceJobs.CONNECT, panel, bank, label)
            T.server(self, "refreshBank", T.at(bank))
            T.readRecord(self, bank, label .. "State")
        end
        T.batch(function()
            T.snowfall(self, bank, nil, "snowed")
            tryAgain("again")
            self.second = T.panel(self, Sprites.flat, { near = bank, connect = true })
            if not self.second then return end
            tryAgain("full")
        end)
    end,
    validate = function(self)
        if not (T.expectConnected(self.panel) and T.expectConnected(self.second)) then return end
        local snowed = (T.stateSource(self.reads.snowed, self.panel) or {}).snow or 0
        if not expect(snowed > 0, "a night of snowfall left no snow on the panel") then return end
        for _, case in ipairs({ { "again", 1, "a bank" }, { "full", 2, "a full bank" } }) do
            local label, panels, what = case[1], case[2], case[3]
            local state = self.reads[label .. "State"]
            T.expectRefused(self.reads[label], "already connected", "connecting a panel again to " .. what .. " it feeds")
            expectEqual("panels after connecting one again to " .. what .. " it feeds", state.sources, panels)
            -- Connecting brings the bank up to now first, which may melt a trace of it.
            expectNear("snow on a panel connected again to " .. what .. " it feeds",
                (T.stateSource(state, self.panel) or {}).snow or -1, snowed, 0.01)
        end
    end,
})

-- Whether this client's copy of the panel handle `panel` draws snow on its tile.
local function showsSnow(panel)
    for _, name in ipairs(T.overlaysOf(panel.object)) do
        if Sprites.isSnow(name) then
            return true
        end
    end
    return false
end

-- Snow falling on a frosty night settles on a flat panel and a rack, not on a wall panel, and this
-- client's copies of them show it. In the sun it takes its share of what a panel makes, beside a
-- panel swept clean, and the status names it as the reason; the sun melts it, the rack's tilt
-- sheds it faster, and mild air takes the rest. PanelSource's rates an hour: snowfall 0.5, sun
-- melt 0.05 in full sun, shedding 0.5, mild-air melt 0.1.
test("renewable_energy_solar_snow_settles_dims_and_melts", {
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, Specs.controller }, { charge = 0.2 })
        self.flat = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        self.rack = self.flat and T.panel(self, Sprites.rack.wood.S, { near = bank, connect = true })
        self.clean = self.rack and T.panel(self, Sprites.flat, { near = bank, connect = true })
        self.wall = self.clean and T.panel(self, Sprites.wall.wood.S, { near = bank, connect = true })
        if not self.wall then return end
        self.bank = bank
        T.give(self, "broom", { { type = "Base.Broom" } })
        T.batch(function()
            T.snowfall(self, bank, 2, "night")
            T.job(self, "source", SourceJobs.CLEAR_SNOW, self.clean, { type = "Base.Broom" })
        end)
        T.waitFor(self, function() return showsSnow(self.flat) and showsSnow(self.rack) end,
            "this client's copies of the snowy panels showing snow")
        T.step(function() self.cleanShowed, self.wallShowed = showsSnow(self.clean), showsSnow(self.wall) end)
        T.bankPass(self, bank, Sun.FULL_SUN, { airC = -10, label = "sunny" })
        T.waitFor(self, function() return showsSnow(self.flat) and not showsSnow(self.rack) end,
            "this client's copy of the rack showing its snow shed")
        T.bankPass(self, bank, Sun.FULL_SUN, { hours = 10 })
        T.waitFor(self, function() return not showsSnow(self.flat) end, "this client's copy of the flat panel thawed")
    end,
    validate = function(self)
        local connected = self.flat.connected and self.rack.connected and self.clean.connected and self.wall.connected
        if not expect(connected, "connecting the panels failed") then return end
        local function entryOf(label, panel) return T.stateSource(self.reads[label], panel) or {} end
        local flat, rack = entryOf("night", self.flat), entryOf("night", self.rack)
        -- Two hours of snowfall at 0.5 an hour cover the panel: 2 × 0.5 = 1.
        expectNear("snow on the flat panel after the night", flat.snow or -1, 1, 1e-9)
        expectEqual("snow on the rack after the night, too cold and dark to shed", rack.snow, flat.snow)
        expectEqual("snow on the wall panel after the night", entryOf("night", self.wall).snow, 0)
        expect(not self.cleanShowed, "this client's copy of the swept panel still shows snow")
        expect(not self.wallShowed, "this client's copy of the wall panel shows snow")
        flat, rack = entryOf("sunny", self.flat), entryOf("sunny", self.rack)
        local clean = entryOf("sunny", self.clean)
        expectEqual("snow on the swept panel after the sunny hour", clean.snow, 0)
        if not expectNear("the swept panel's watts in full sun", clean.watts or 0, T.flatPanelW(), 1e-9) then return end
        -- An hour of full sun at -10 °C: the flat panel 1 - 0.05 = 0.95, the rack sheds as well,
        -- 1 - 0.05 - 0.5 = 0.45. The sweep brought the bank up to now first, which may melt or shed
        -- a trace in the game's own weather.
        expectNear("snow on the flat panel after an hour of full sun", flat.snow, 0.95, 0.005)
        expectNear("snow on the rack after an hour of full sun", rack.snow, 0.45, 0.005)
        -- Snow covers its share of the panel, and that share of the sun goes nowhere.
        expectNear("the snowy flat panel's watts against the swept one's", flat.watts / clean.watts, 1 - flat.snow, 1e-6)
        expectEqual("the snowy flat panel's share of full sun", flat.fullSunPct, 5)
        expectEqual("why the snowy flat panel makes little", flat.reason, "snow")
        expectEqual("why the swept panel makes little", clean.reason, nil)
        -- Ten more hours at 25 °C: 0.95 - 10 × (0.1 + 0.05) is below none.
        local thawed = T.stateSource(self.bank.state, self.flat) or {}
        expectEqual("snow on the flat panel after a mild sunny day", thawed.snow, 0)
        expectEqual("the thawed panel's share of full sun", thawed.fullSunPct, 100)
    end,
})

-- At night only air above freezing melts snow off a flat panel, which sheds none: an hour at 0 °C
-- keeps every bit of it, an hour just above takes its hour's melt. A dark pass says the panel is
-- low for the night. Catches the thaw starting at freezing, and the snowfall or melt rate off.
test("renewable_energy_solar_snow_melts_only_above_freezing", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY }, { charge = 0.5 })
        self.panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not self.panel then return end
        T.batch(function()
            T.snowfall(self, bank, 1, "night")
            T.bankPass(self, bank, 0, { airC = 0, label = "freezing" })
            T.bankPass(self, bank, 0, { airC = 0.1, label = "thawing" })
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        local function entryAt(label) return T.stateSource(self.reads[label], self.panel) or {} end
        -- An hour of snowfall at 0.5 an hour, short of covering the panel, so its rate shows.
        expectNear("snow on the panel after an hour of snowfall", entryAt("night").snow or -1, 0.5, 1e-9)
        expectEqual("snow on the panel after a dark hour at 0 °C", entryAt("freezing").snow, entryAt("night").snow)
        -- 0.5 - 0.1, a mild hour's melt.
        expectNear("snow on the panel after a dark hour at 0.1 °C", entryAt("thawing").snow or -1, 0.4, 1e-9)
        expectEqual("why the panel makes nothing in the dark", entryAt("thawing").reason, "night")
    end,
})

-- A panel roofed over after it was connected, by a floor built above it, is no longer outdoors:
-- the next pass drops it, even the one a Disconnect catches up with first, which then refuses
-- the connection gone and publishes the bank's sources, and a roofed panel makes nothing. Catches
-- a panel checked for being outdoors only when it is connected.
test("renewable_energy_solar_roofed_panel_dropped_at_the_next_pass", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY }, { charge = 0.5 })
        self.panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not self.panel then return end
        T.batch(function()
            T.bankPass(self, bank, 1000, { label = "open" })
            T.floorAbove(self, self.panel, "roof")
            -- An hour back, so the Disconnect catches up with a pass of its own.
            T.readRecord(self, bank, "before", 1)
            T.job(self, "source", SourceJobs.DISCONNECT, self.panel, nil, "disconnect")
            T.readRecord(self, bank, "after")
            T.bankPass(self, bank, 1000, { label = "roofed" })
        end)
        T.waitForSummary(self, bank, function(summary) return #summary.sources == 0 end,
            "this client's summary after the catch-up dropped the roofed panel")
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        local reads = self.reads
        expectNear("solar watts of the panel in the open at 1000 W/m²", reads.open.status.solarW, T.flatPanelW(), 1e-9)
        expectEqual("whether the roofed panel's square is outdoors", reads.roof.outside, false)
        expectEqual("sources before the Disconnect catches up", reads.before.sources, 1)
        T.expectRefused(reads.disconnect, "not connected", "Disconnect acted on the connection the catch-up dropped")
        expectEqual("sources after the Disconnect caught up", reads.after.sources, 0)
        expectEqual("solar watts under the roof", reads.roofed.status.solarW, 0)
        expect(reads.roofed.storedWh <= reads.open.storedWh, string.format(
            "the bank gained %.2f Wh in the hour after its panel was roofed over", reads.roofed.storedWh - reads.open.storedWh))
    end,
})
