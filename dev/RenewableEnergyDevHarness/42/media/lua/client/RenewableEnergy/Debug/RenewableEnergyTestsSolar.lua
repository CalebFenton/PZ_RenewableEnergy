require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/Recipes"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/Menu"
require "RenewableEnergy/UI/StatusWindow"

-- Solar: the sun model (Sun.lua), panels feeding a bank and storms on them (PowerBank/PanelSource.lua,
-- Sources.lua), the panel menus and highlight (UI/Menu.lua, UI/StatusWindow.lua), and mount and
-- module crafting (Recipes.lua).

local T = RenewableEnergyTest
local test, craftTest, expect, expectNear, player = T.test, T.craftTest, T.expect, T.expectNear, T.player
local Action = RenewableEnergyAction
local Specs, Sprites, Sun = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun
local PowerBank, Sources, Recipes = RenewableEnergy.PowerBank, RenewableEnergy.Sources, RenewableEnergy.Recipes
local Format, Menu = RenewableEnergy.Format, RenewableEnergy.Menu
local MODULES_KEY = PowerBank.MODULES_KEY
local CAR_BATTERY = "Base.CarBattery1"
local FACTORY, HOMEMADE = "RenewableEnergy.SolarModule", "RenewableEnergy.HomemadeSolarModule"
local function craftName(recipe, behavior) return T.craftName("solar", recipe, behavior) end

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

-- The condition the panel object `panel` records for its first module, or nil.
local function recordedCondition(panel)
    local modules = panel and panel:getModData()[MODULES_KEY]
    return modules and modules[1] and modules[1].condition
end

local STORM_MOUNTS = {
    flat = { kind = "flat" }, wall = { kind = "wall", material = "wood" },
    woodRack = { kind = "rack", material = "wood" }, metalRack = { kind = "rack", material = "metal" },
}

-- A storm trial on a panel of `mount` (STORM_MOUNTS) with one module at `condition`.
local function stormTrial(mount, hours, condition, roll)
    local source = STORM_MOUNTS[mount]
    return { source = { kind = source.kind, material = source.material, modules = T.factoryModules(condition or 100) },
        hours = hours, roll = roll }
end

-- Queues PanelSource.stormChance for `trials` on the server, keeping the chances in self.chances[name].
local function stormChances(self, name, trials)
    T.server(self, "stormChances", { trials = trials })
    T.step(function() self.chances[name] = self.server.stormChances.chances end)
end

-- Storms crack modules by mount: wall panels never, wooden racks most, metal racks least, the
-- more the longer the storm and the higher the Storm Damage Rate, and never with Storm Damage off.
test("renewable_energy_solar_storms_crack_by_mount", {
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        self.chances = {}
        stormChances(self, "mounts", { stormTrial("wall", 20), stormTrial("woodRack", 20), stormTrial("flat", 20),
            stormTrial("metalRack", 20), stormTrial("flat", 40), stormTrial("flat", 0) })
        T.step(function() T.setSandbox(self, "StormDamageRate", 200) end)
        stormChances(self, "doubled", { stormTrial("flat", 20) })
        T.step(function() T.setSandbox(self, "StormDamageRate", 0) end)
        stormChances(self, "rateZero", { stormTrial("flat", 20) })
        T.step(function()
            T.setSandbox(self, "StormDamageRate", 100)
            T.setSandbox(self, "StormDamage", false)
        end)
        stormChances(self, "off", { stormTrial("flat", 20) })
    end,
    validate = function(self)
        local mounts = self.chances.mounts
        local wall, woodRack, flat, metalRack, longer, none = mounts[1], mounts[2], mounts[3], mounts[4], mounts[5], mounts[6]
        expectNear("a wall panel's chance of a crack", wall, 0, 0)
        expect(woodRack > flat and flat > metalRack and metalRack > 0,
            string.format("chances of a crack in 20 hours of storm: wooden rack %g, flat %g, metal rack %g", woodRack, flat, metalRack))
        expect(longer > flat, string.format("a flat panel's chance in 40 hours of storm %g, in 20 %g", longer, flat))
        expectNear("a flat panel's chance in no storm", none, 0, 0)
        local doubled = self.chances.doubled[1]
        expect(doubled > flat, string.format("a flat panel's chance at Storm Damage Rate 200 %g, at 100 %g", doubled, flat))
        expectNear("a flat panel's chance at Storm Damage Rate 0", self.chances.rateZero[1], 0, 0)
        expectNear("a flat panel's chance with Storm Damage off", self.chances.off[1], 0, 0)
    end,
})

-- A storm cracks a module on a roll under its chance and not on one at it, taking Specs.storm.crack
-- condition, never below 0; with Storm Damage off not even the lowest roll cracks one.
test("renewable_energy_solar_storms_crack_under_the_chance", {
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local under, at = stormTrial("flat", 20, 100, "under"), stormTrial("flat", 20, 100, "at")
        -- Less than a crack left, so a crack would take it below 0.
        T.server(self, "stormCrack", { trials = { under, at, stormTrial("flat", 20, math.floor(Specs.storm.crack / 2), 0),
            stormTrial("wall", 20, 100, 0) } })
        T.step(function()
            self.results = self.server.stormCrack.results
            T.setSandbox(self, "StormDamage", false)
        end)
        T.server(self, "stormCrack", { trials = { stormTrial("flat", 20, 100, 0) } })
        T.step(function() self.off = self.server.stormCrack.results[1] end)
    end,
    validate = function(self)
        local under, at, floor, wall = self.results[1], self.results[2], self.results[3], self.results[4]
        expect(under.cracked, "a roll just under a flat panel's chance didn't crack it")
        expectNear("a module at 100 after a crack", under.modules[1].condition, 100 - Specs.storm.crack, 0)
        expect(not at.cracked, "a roll at a flat panel's chance cracked it")
        expectNear("a module at 100 after a roll at the chance", at.modules[1].condition, 100, 0)
        expectNear("a module under a crack's worth after a crack", floor.modules[1].condition, 0, 0)
        expect(not wall.cracked, "the lowest roll cracked a wall panel")
        expect(not self.off.cracked, "the lowest roll cracked a module with Storm Damage off")
    end,
})

-- A crack reaches the panel's own record and its tile in the same bank pass: a new panel's first
-- crack shows light cracks, on this client too.
test("renewable_energy_solar_storms_crack_shows_on_the_panel", {
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY }, { charge = 0.5 })
        local whole = RenewableEnergy.conditionMaxOf(FACTORY)
        self.crackedTo = whole - Specs.storm.crack
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, modules = T.factoryModules(whole), connect = true })
        if not panel then return end
        self.panel = panel
        T.step(function() self.before = T.overlays(panel.object) end)
        T.forceRoll(self, 0)
        T.bankPass(self, bank, 1000, { stormHours = 1 })
        T.server(self, "panelState", panel.position)
        T.waitFor(self, function()
            return recordedCondition(panel.object) == self.crackedTo
                and T.overlays(panel.object) == table.concat(self.server.panelState.overlays, ",")
        end, "this client's copy of the storm-cracked panel")
        T.step(function() self.copyOverlays = T.overlays(panel.object) end)
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        expect(self.before == "", "the whole panel showed '" .. tostring(self.before) .. "' before the storm")
        local modules = self.server.panelState.modules
        expectNear("the panel's recorded condition after a crack", modules and modules[1] and modules[1].condition, self.crackedTo, 0)
        expectNear("this client's copy of the panel's recorded condition", recordedCondition(self.panel.object), self.crackedTo, 0)
        local after = table.concat(self.server.panelState.overlays, ",")
        expect(after == Sprites.cracks.light.flat, "the storm-cracked panel shows '" .. after .. "'")
        expect(self.copyOverlays == after, "this client's copy of the storm-cracked panel shows '" .. tostring(self.copyOverlays) .. "'")
    end,
})

-- What a flat panel shows of a module through its life (Sprites.crackOverlays): whole when new,
-- light cracks from the first storm crack until under half its ConditionMax, heavy cracks below,
-- light once sealed (where Seal Cracked Module takes it) and whole once reglazed; a homemade
-- module the same by its own max. Each row: the module, how many storm cracks it took from new,
-- and what it shows then.
local LIFE_LOOKS = {
    { FACTORY, 0, nil },
    { FACTORY, 1, "light" },
    { FACTORY, 2, "light" },
    { FACTORY, 3, "heavy" },
    { HOMEMADE, 0, nil },
    { HOMEMADE, 1, "light" },
    { HOMEMADE, 2, "heavy" },
}
test("renewable_energy_solar_crack_looks_follow_the_module", {
    run = function(self)
        local function shows(record)
            return table.concat(Sprites.crackOverlays("flat", nil, nil, { record }), ",")
        end
        self.rows = {}
        local function reglazed(record)
            local glass = Recipes.reglazedCondition(record.type, record.condition, record.repaired)
            return shows({ type = record.type, condition = math.max(record.condition, glass) })
        end
        for _, row in ipairs(LIFE_LOOKS) do
            local module, cracks = row[1], row[2]
            local condition = RenewableEnergy.conditionMaxOf(module) - cracks * Specs.storm.crack
            local record = { type = module, condition = condition, repaired = 0 }
            local sealed, sealedReglazed = nil, nil
            if Recipes.canSealRecord(record) then
                local copy = { type = module, condition = condition, repaired = 0 }
                Recipes.sealRecord(copy)
                sealed, sealedReglazed = shows(copy), reglazed(copy)
            end
            table.insert(self.rows, { row = row, condition = condition, cracked = shows(record), sealed = sealed,
                reglazed = reglazed(record), sealedReglazed = sealedReglazed })
        end
    end,
    validate = function(self)
        for _, result in ipairs(self.rows) do
            local module, cracks, look = result.row[1], result.row[2], result.row[3]
            local what = module .. " at " .. result.condition .. " after " .. cracks .. " cracks"
            local expected = look and Sprites.cracks[look].flat or ""
            expect(result.cracked == expected, what .. " shows '" .. result.cracked .. "', expected '" .. expected .. "'")
            if result.sealed then
                expect(result.sealed == Sprites.cracks.light.flat, what .. ", sealed once, shows '" .. result.sealed .. "'")
            end
            expect(result.reglazed == "", what .. ", reglazed, shows '" .. result.reglazed .. "'")
            if result.sealedReglazed then
                expect(result.sealedReglazed == "", what .. ", sealed then reglazed, shows '" .. result.sealedReglazed .. "'")
            end
        end
        -- Rows whose modules Seal Cracked Module takes, so the sealed look above was tested.
        local sealedRows = 0
        for _, result in ipairs(self.rows) do
            sealedRows = sealedRows + (result.sealed and 1 or 0)
        end
        expect(sealedRows >= 2, "only " .. sealedRows .. " rows could be sealed")
    end,
})

-- A storm cracks a panel out in the weather whether or not it feeds a bank: a loose panel outdoors
-- cracks, one indoors doesn't, and a connected one is its bank's to crack until it is
-- disconnected, after which the next storm cracks it too.
test("renewable_energy_solar_storms_crack_loose_panels", {
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY }, { charge = 0.5 })
        local connected = bank and T.panel(self, Sprites.flat, { near = bank, modules = T.factoryModules(100), connect = true })
        local outdoors = connected and T.panel(self, Sprites.flat, { near = bank, modules = T.factoryModules(100) })
        local indoorSquare = outdoors and T.square(self, { indoors = true, near = bank }, "a free indoor square for a panel")
        local indoors = indoorSquare and T.panel(self, Sprites.flat, { square = indoorSquare, modules = T.factoryModules(100) })
        if not indoors then return end
        self.connected = connected
        local panels = { connected.position, outdoors.position, indoors.position }
        -- Every roll the lowest: each panel at risk cracks.
        T.forceRoll(self, 0)
        T.server(self, "panelStorm", { hours = 1, panels = panels })
        T.step(function() self.first = self.server.panelStorm.modules end)
        T.performInto(self, "disconnected", "disconnectSource", { bank = bank.position, source = connected.position })
        T.server(self, "panelStorm", { hours = 1, panels = panels })
        T.step(function() self.second = self.server.panelStorm.modules end)
    end,
    validate = function(self)
        if not T.expectConnected(self.connected) then return end
        local crack = Specs.storm.crack
        local function condition(modules, i) return modules[i] and modules[i][1] and modules[i][1].condition end
        expectNear("the connected panel after a storm its bank didn't run", condition(self.first, 1), 100, 0)
        expectNear("the loose outdoor panel after a storm", condition(self.first, 2), 100 - crack, 0)
        expectNear("the loose indoor panel after a storm", condition(self.first, 3), 100, 0)
        expect(self.disconnected and self.disconnected.ok, "disconnecting the panel failed ("
            .. tostring(self.disconnected and self.disconnected.reason) .. ")")
        expectNear("the disconnected panel after the next storm", condition(self.second, 1), 100 - crack, 0)
        expectNear("the loose outdoor panel after a second storm", condition(self.second, 2), 100 - 2 * crack, 0)
        expectNear("the loose indoor panel after a second storm", condition(self.second, 3), 100, 0)
    end,
})

-- Connecting a panel gives Electricity XP once per module, the first time that module is ever
-- connected: a rack holding one module connected before gives the other one's share and marks
-- both, and connecting it again after disconnecting gives nothing.
test("renewable_energy_solar_connect_xp_once_per_module", {
    run = function(self)
        T.setPerk(self, Perks.Electricity, 3)
        local module = Specs.factoryModule
        local bank = T.bank(self, "batteryBoxWood", {})
        local panel = bank and T.panel(self, Sprites.rack.wood.S, { near = bank,
            modules = { { type = module, condition = 90, connected = true }, { type = module, condition = 90 } } })
        if not panel then return end
        local args = { bank = bank.position, source = panel.position }
        T.batch(function()
            T.performInto(self, "connected", "connectSource", args)
            T.performInto(self, "disconnected", "disconnectSource", args)
            T.performInto(self, "reconnected", "connectSource", args)
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

-- Panel menus and actions ---------------------------------------------------------------------

local function hasEnabledOption(menu)
    for _, option in ipairs(menu and menu.options or {}) do
        if option.onSelect and not option.notAvailable then
            return true
        end
    end
    return false
end

-- A panel offers to connect only to a bank in reach: with none, the option is there but
-- unavailable and says why; with one, the option connects to it.
test("renewable_energy_solar_menu_panel_connect", {
    run = function(self)
        self.panel = T.panel(self, Sprites.rack.wood.S)
        if not self.panel then return end
        T.step(function()
            local panel = self.panel.object
            self.banksBefore = #Sources.banksInReach(panel:getX(), panel:getY(), panel:getZ(), Sources.kindOf(panel))
            local context = T.newContext()
            local submenu = Menu.addSourceOptions(0, context, panel)
            local option = T.optionNamed(submenu, getText("ContextMenu_RenewableEnergy_ConnectToBank"))
            self.alone = T.optionState(option)
            self.alone.enabled = hasEnabledOption(submenu)
            context:hideAndChildren()
        end)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true, near = self.panel })
    end,
    validate = function(self)
        local panel, alone = self.panel.object, self.alone
        if expect(self.banksBefore == 0, "a bank left by an earlier test is in reach of the panel") then
            expect(alone.shown and alone.greyed, "a panel with no bank in reach shows no unavailable connect option")
            expect(alone.reason == getText("Tooltip_RenewableEnergy_NoBankInReach"),
                "the unavailable connect option says " .. tostring(alone.reason))
            expect(not alone.enabled, "a panel with no bank in reach offers something to do")
        end
        local context = T.newContext()
        local submenu = Menu.addSourceOptions(0, context, panel)
        local connect = T.optionNamed(submenu, getText("ContextMenu_RenewableEnergy_ConnectSource", Menu.bankLabel(self.bank.object),
            Format.away(self.panel.position, self.bank.position)))
        expect(connect ~= nil and not connect.notAvailable, "a panel next to a bank offers no connection to it")
        expect(T.optionNamed(submenu, getText("ContextMenu_RenewableEnergy_DisconnectSource")) == nil,
            "a panel that isn't connected offers to disconnect")
        context:hideAndChildren()
    end,
})

-- A connected panel names its bank, by the name a player gave it, and how far away it stands.
test("renewable_energy_solar_menu_panel_wired_to", {
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        self.panel = self.bank and T.panel(self, Sprites.flat, { near = self.bank, connect = true })
        if not self.panel then return end
        T.perform(self, "rename", { bank = self.bank.position, name = "Shed Bank" })
        T.waitFor(self, function()
            local summary = T.clientSummary(self.bank)
            return summary ~= nil and summary.name == "Shed Bank"
        end, "this client's summary of the renamed bank")
    end,
    validate = function(self)
        local context = T.newContext()
        local submenu = Menu.addSourceOptions(0, context, self.panel.object)
        local wiredTo
        for _, option in ipairs(submenu.options) do
            if option.name:find("Shed Bank", 1, true) then
                wiredTo = option.name
            end
        end
        local bank, panel = self.bank.position, self.panel.position
        local dx, dy = bank.x - panel.x, bank.y - panel.y
        local tiles = round(math.sqrt(dx * dx + dy * dy))
        expect(wiredTo ~= nil, "a connected panel's menu doesn't name its renamed bank")
        expect(wiredTo == nil or wiredTo:find(tostring(tiles), 1, true) ~= nil,
            "the panel menu says " .. tostring(wiredTo) .. ", but the bank is " .. tiles .. " tiles away")
        context:hideAndChildren()
    end,
})

-- The option's minimum; the timing's tolerance still dwarfs a round trip to a local server.
local CONNECT_MINUTES = 1
-- A multiplayer server times actions in real milliseconds whatever the game speed
-- (NetTimedAction.getDuration); in single player the action and the clock speed up alike.
local function connectSpeed()
    return isClient() and 1 or 10
end

local INSTANT_OFF = "the debug option Cheats > Timed Action > Instant off, which makes every action instant"

local function worldMinutes()
    return getGameTime():getWorldAgeHours() * 60
end

-- Connecting a panel takes the ConnectPanelMin sandbox option's in-game minutes, from the action's
-- start to its end, and leaves the bank listing the panel, on the server and in this client's status.
test("renewable_energy_solar_connect_panel", {
    sandbox = { ConnectPanelMin = CONNECT_MINUTES },
    run = function(self)
        local p = player()
        if not T.need(self, not p:isTimedActionInstant(), INSTANT_OFF) then return end
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        self.panel = self.bank and T.panel(self, Sprites.flat, { near = self.bank })
        if not self.panel then return end
        -- At this level the option's minutes are taken as they are; skill shortens or lengthens them.
        T.setPerk(self, Perks.Electricity, 3)
        T.step(function()
            T.setMultiplier(self, connectSpeed())
            local action = Action:new(p, Action.CONNECT_SOURCE, self.panel.object, self.bank.object)
            self.action, self.valid = action, action:canPerform()
            T.onTick(self, function()
                if not self.started and action:isStarted() then
                    self.started = worldMinutes()
                elseif self.started and not self.ended and ISTimedActionQueue.getTimedActionQueue(p).queue[1] ~= action then
                    self.ended = worldMinutes()
                end
            end)
            if not T.walkTo(self, self.panel.square, "the panel") then return end
            ISTimedActionQueue.add(action)
            T.waitFor(self, function()
                return PowerBank.samePosition(PowerBank.connectedBank(self.panel.object), self.bank.position)
            end, "this client's copy of the connection")
            T.bankState(self, self.bank)
        end)
    end,
    validate = function(self)
        expect(self.valid, "connecting a panel next to a bank is refused")
        expect(self.bank.state.sources == 1, "the server's bank lists " .. self.bank.state.sources .. " panels")
        expect(PowerBank.samePosition(PowerBank.connectedBank(self.panel.object), self.bank.position),
            "this client's status of the bank does not list the connected panel")
        expect(not self.action:canPerform(), "a panel already on this bank can be connected again")
        if not expect(self.started ~= nil and self.ended ~= nil, "the connect action never started or ended") then return end
        local elapsed = self.ended - self.started
        expect(elapsed >= CONNECT_MINUTES * 0.95 and elapsed <= CONNECT_MINUTES * 1.05,
            string.format("connecting took %.2f in-game minutes, expected %d", elapsed, CONNECT_MINUTES))
    end,
})

-- Disconnect, chosen from a connected panel's menu, takes the panel off the bank on the server and
-- in this client's copy.
test("renewable_energy_solar_disconnect_panel", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        self.panel = self.bank and T.panel(self, Sprites.wall.wood.S, { near = self.bank, connect = true })
        if not self.panel then return end
        T.step(function()
            local context = T.newContext()
            local option = T.optionNamed(Menu.addSourceOptions(0, context, self.panel.object),
                getText("ContextMenu_RenewableEnergy_DisconnectSource"))
            context:hideAndChildren()
            self.offered = option ~= nil and not option.notAvailable
            if not self.offered then return end
            T.standNextTo(self.panel.square)
            T.choose(option)
            T.waitFor(self, function() return PowerBank.connectedBank(self.panel.object) == nil end, "this client's copy of the disconnection")
            T.bankState(self, self.bank)
        end)
    end,
    validate = function(self)
        expect(self.panel.connected, "the bank refused to connect a wall panel next to it (" .. tostring(self.panel.reason) .. ")")
        if not expect(self.offered, "a connected panel's menu offers no Disconnect") then return end
        expect(self.bank.state.sources == 0, "the server's bank still lists the panel after disconnecting it")
        expect(PowerBank.connectedBank(self.panel.object) == nil, "this client still sees the panel connected after disconnecting it")
    end,
})

-- Seal Cracked Module, chosen from a connected rack's menu, seals the one cracked module still on
-- its mount as the recipe seals one in hand: up to its cap, lowered by the seal it already had,
-- counting the seal and still showing cracked. The whole module isn't offered, and the bank's
-- record takes the sealed module at once. Its tooltip names both adhesives, and with both
-- carried the seal takes the glue twin's uses of glue and leaves the epoxy (Recipes.lua,
-- MODULE_REPAIR_RECIPES).
test("renewable_energy_solar_seal_module_in_place", {
    instant = true,
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", {}, { outdoors = true })
        local cracked = { type = FACTORY, condition = 20, repaired = 1 }
        self.to = math.min(Recipes.MODULE_REPAIR_CAP[FACTORY] - Recipes.REPAIR_LIMIT_STEP, cracked.condition + Recipes.MODULE_REPAIR)
        self.panel = self.bank and T.panel(self, Sprites.rack.wood.S, { near = self.bank, connect = true,
            modules = { { type = FACTORY, condition = 100 }, cracked } })
        if not self.panel then return end
        local bank = self.bank
        T.setRecipeSkills(self, Recipes.moduleRepairRecipe())
        T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.Epoxy" }, { type = "Base.Glue" } })
        T.step(function()
            local context = T.newContext()
            local menu = Menu.addSourceOptions(0, context, self.panel.object)
            local whole = T.optionNamed(menu, getText("ContextMenu_RenewableEnergy_SealModule", 1, 100))
            local option = T.optionNamed(menu, getText("ContextMenu_RenewableEnergy_SealModule", 2, cracked.condition))
            context:hideAndChildren()
            self.wholeOffered, self.offered = whole ~= nil, T.optionState(option)
            if not (option and not option.notAvailable) then return end
            T.standNextTo(self.panel.square)
            T.choose(option)
            T.waitFor(self, function()
                local modules = self.panel.object:getModData()[MODULES_KEY]
                return modules and modules[2] and modules[2].condition ~= cracked.condition
            end, "this client's copy of the sealed module")
            T.server(self, "panelState", self.panel.position)
            T.bankState(self, bank)
            T.readCarried(self, { "Base.Glue", "Base.Epoxy" })
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        expect(not self.wholeOffered, "the whole module is offered a seal")
        if not expect(self.offered.shown and not self.offered.greyed, "the cracked module's seal isn't offered ("
            .. tostring(self.offered.reason) .. ")") then return end
        local modules = self.server.panelState.modules
        expectNear("the whole module", modules[1].condition, 100, 0)
        expectNear("the sealed module", modules[2].condition, self.to, 0)
        expect(modules[2].repaired == 2, "the sealed module reads repaired " .. tostring(modules[2].repaired) .. "x, expected 2")
        expect(#self.server.panelState.overlays > 0, "the sealed module shows whole")
        local listed = self.bank.state.status.sources[1]
        expectNear("the bank's record of the sealed module", listed and listed.modules[2].condition, self.to, 0)
        for _, adhesive in ipairs({ "Base.Glue", "Base.Epoxy" }) do
            expect(tostring(self.offered.reason):find(getItemNameFromFullType(adhesive), 1, true) ~= nil,
                "the seal's tooltip doesn't name " .. adhesive .. ": " .. tostring(self.offered.reason))
        end
        -- One full tube of each was given; "carried" reads the fraction of it left.
        local glue, epoxy = T.carriedFirst(self, "Base.Glue"), T.carriedFirst(self, "Base.Epoxy")
        expectNear("the glue left of a full tube", glue and glue.uses or 0,
            1 - 2 * getScriptManager():FindItem("Base.Glue"):getUseDelta(), 0.001)
        expectNear("the epoxy left of a full tube", epoxy and epoxy.uses or 0, 1, 0.001)
    end,
})

-- The Clear Snow option on `panel`'s menu: whether it shows, whether it is greyed out, and why.
local function clearSnowOption(panel)
    local context = T.newContext()
    local option = T.optionNamed(Menu.addSourceOptions(0, context, panel.object), getText("ContextMenu_RenewableEnergy_ClearSnow"))
    context:hideAndChildren()
    return T.optionState(option)
end

-- A snowy flat panel offers Clear Snow, greyed out saying why until the character carries a broom
-- or snow shovel. The action then needs the tool in hand and unbroken, and only flat panels hold
-- snow.
test("renewable_energy_solar_clear_snow_requirements", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        self.flat = self.bank and T.panel(self, Sprites.flat, { near = self.bank, connect = true })
        self.wall = self.flat and T.panel(self, Sprites.wall.wood.E)
        if not self.wall then return end
        T.snowfall(self, self.bank)
        T.waitFor(self, function()
            local summary = T.clientSummary(self.bank)
            return summary ~= nil and summary.sources[1] ~= nil and summary.sources[1].snowy == true
        end, "this client's summary with the panel snowy")
        T.step(function() self.withoutTool = clearSnowOption(self.flat) end)
        T.give(self, "tools", { { type = "Base.Broom" }, { type = "Base.SnowShovel" }, { type = "Base.Hammer" } })
        T.step(function() self.withTool = clearSnowOption(self.flat) end)
    end,
    validate = function(self)
        expect(self.withoutTool.greyed and self.withoutTool.reason == getText("Tooltip_RenewableEnergy_NeedSnowTool"),
            "with no broom or shovel, Clear Snow on a snowy panel isn't greyed out saying why ("
            .. tostring(self.withoutTool.shown) .. ", " .. tostring(self.withoutTool.reason) .. ")")
        expect(self.withTool.shown and not self.withTool.greyed,
            "carrying a broom, Clear Snow isn't offered on a snowy panel (" .. tostring(self.withTool.reason) .. ")")
        local p = player()
        local broom, shovel, hammer = self.items.tools[1], self.items.tools[2], self.items.tools[3]
        local function canClear(panel, tool)
            return Action:new(p, Action.CLEAR_SNOW, panel.object, nil, nil, tool):canPerform()
        end
        expect(not canClear(self.flat, broom), "snow can be cleared with a broom left in the bag")
        p:setPrimaryHandItem(broom)
        expect(canClear(self.flat, broom), "a broom in hand can't clear a flat panel")
        expect(not canClear(self.wall, broom), "a wall panel, which holds no snow, can be cleared")
        -- A broom broken in hand drops splinters (OnBreak.LongStick); clear them away.
        local feet = p:getSquare()
        local lying, dropped = {}, feet:getWorldObjects()
        for i = 0, dropped:size() - 1 do
            lying[dropped:get(i)] = true
        end
        broom:setCondition(0)
        for i = dropped:size() - 1, 0, -1 do
            local object = dropped:get(i)
            if not lying[object] then
                feet:removeWorldObject(object)
            end
        end
        expect(not canClear(self.flat, broom), "a broken broom can clear snow")
        p:setPrimaryHandItem(shovel)
        expect(canClear(self.flat, shovel), "a snow shovel in hand can't clear a flat panel")
        p:setPrimaryHandItem(hammer)
        expect(not canClear(self.flat, hammer), "a hammer clears snow")
        p:setPrimaryHandItem(nil)
    end,
})

-- Connect options on a bank, with `loose` sources in its reach, and on the loose panel `panel`,
-- read from this client's copies: whether they show greyed, and why.
local function connectOptions(bank, panel, loose)
    local context = T.newContext()
    local bankMenu = Menu.addBankOptions(0, context, bank.object)
    local sourceMenu = Menu.addSourceOptions(0, context, panel.object)
    local options = {
        all = T.optionState(T.optionNamed(bankMenu, getText("ContextMenu_RenewableEnergy_ConnectSourcesInReach", loose))),
        one = T.optionState(T.optionNamed(sourceMenu, getText("ContextMenu_RenewableEnergy_ConnectSource", Menu.bankLabel(bank.object),
            Format.away(panel.position, bank.position)))),
    }
    context:hideAndChildren()
    return options
end

-- A bank with every input slot taken greys out connecting another panel, from the bank's menu and
-- from the panel's, saying there's no slot; one slot freed, both offer it. Read on this client's
-- summary, which carries the free slots. Catches a menu that offers a connection the bank then
-- refuses, or still refuses once a slot is free.
test("renewable_energy_solar_connect_refused_without_free_slot", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if not bank then return end
        self.bank = bank
        local wired = {}
        T.batch(function()
            for i = 1, Specs.freeSlots do
                wired[i] = T.panel(self, Sprites.flat, { near = bank, connect = true })
                if not wired[i] then return end
            end
            self.loose = T.panel(self, Sprites.flat, { near = bank })
        end)
        if not self.loose then return end
        local function freeSlots(count)
            T.waitFor(self, function()
                local summary = T.clientSummary(bank)
                return summary ~= nil and summary.freeSlots == count
            end, "this client's summary with " .. count .. " free input slots")
        end
        freeSlots(0)
        T.step(function() self.full = connectOptions(bank, self.loose, 1) end)
        T.perform(self, "disconnectSource", { bank = bank.position, source = wired[1].position })
        freeSlots(1)
        -- The disconnected panel is loose in reach now too.
        T.step(function() self.freed = connectOptions(bank, self.loose, 2) end)
    end,
    validate = function(self)
        local why = getText("Tooltip_RenewableEnergy_NoInputSlot")
        for name, option in pairs(self.full) do
            expect(option.greyed and option.reason == why, "with every slot taken, the " .. name
                .. " connect option isn't greyed out saying there's no slot (" .. tostring(option.reason) .. ")")
        end
        for name, option in pairs(self.freed) do
            expect(option.shown and not option.greyed, "with a slot free, the " .. name
                .. " connect option isn't offered (" .. tostring(option.reason) .. ")")
        end
    end,
})

-- Clicking a panel's row highlights the panel in the world, until the window closes.
test("renewable_energy_solar_window_highlights_panel", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY })
        self.panel = self.bank and T.panel(self, Sprites.flat, { near = self.bank, connect = true })
        if self.panel then T.step(function() T.openWindow(self) end) end
    end,
    validate = function(self)
        local window, panel = self.window, self.panel.object
        local row
        for _, r in ipairs(window.right or {}) do
            row = row or (r.source and r)
        end
        if not expect(row ~= nil and row.top ~= nil, "the window drew no panel row") then return end
        window:onMouseDown(window.rightLayout.x + 4, row.top + 2)
        expect(panel:isHighlighted(0), "clicking the panel's row didn't highlight it")
        window:close()
        expect(not panel:isHighlighted(0), "the panel stayed highlighted after the window closed")
    end,
})

-- Panel mounts --------------------------------------------------------------------------------

-- Expects the mount's record of its modules to hold `expected`, each type at its condition and
-- seal count.
local function expectModules(mount, expected)
    local modules = mount and mount.modData[MODULES_KEY]
    if not expect(modules ~= nil and #modules == #expected,
        "the mount holds " .. tostring(modules and #modules) .. " modules, expected " .. #expected) then
        return
    end
    -- Which input the craft lists first is its own business.
    if #modules == 2 and modules[1].type ~= expected[1].type then
        expected = { expected[2], expected[1] }
    end
    for i, want in ipairs(expected) do
        local got, wantRepaired = modules[i], want.repaired or 0
        expect(got.type == want.type and got.condition == want.condition and (got.repaired or 0) == wantRepaired,
            "module " .. i .. " is " .. tostring(got.type) .. " at " .. tostring(got.condition) .. " sealed "
            .. tostring(got.repaired) .. "x, expected " .. want.type .. " at " .. want.condition .. " sealed " .. wantRepaired .. "x")
    end
end

-- Every mount item (Recipes.MOUNTS), the modules its Specs.mounts kind holds, and its name, by
-- which its recipes are RenewableEnergy_Make<name> and RenewableEnergy_Unmount<name>.
local MOUNTS = {}
for mount, row in pairs(Recipes.MOUNTS) do
    table.insert(MOUNTS, { mount = mount, count = Specs.mounts[row.kind].modules, name = mount:match("%.(.+)") })
end

-- Mounting records each module's type, condition and seals, at conditions a new module doesn't
-- have; a two-module rack gets one of each type. A mount that recorded new modules instead, or
-- only the first of two, would unmount as something else than went in.
local FACTORY_MODULE = { type = FACTORY, condition = 72, repaired = 2 }
local HOMEMADE_MODULE = { type = HOMEMADE, condition = 41 }
for _, entry in ipairs(MOUNTS) do
    local mount, count = entry.mount, entry.count
    local recipe = "RenewableEnergy_Make" .. entry.name
    craftTest(craftName(recipe, "keeps_module_condition"), {
        recipe = recipe,
        from = FACTORY,
        prefer = { FACTORY },
        setup = function(self)
            local modules = T.inputsOf(self, FACTORY)
            T.changeItem(self, modules[1], { condition = FACTORY_MODULE.condition })
            T.setRepaired(self, FACTORY, FACTORY_MODULE.repaired)
            if count == 2 then
                -- One of the two a homemade module instead. This client must have lost the
                -- factory one before the craft picks its inputs from its own copy.
                local taken = modules[2]:getID()
                T.server(self, "takeItems", { ids = { taken } })
                T.give(self, "homemade", { { type = HOMEMADE, condition = HOMEMADE_MODULE.condition } })
                T.waitFor(self, function() return player():getInventory():getItemById(taken) == nil end,
                    "this client losing the second factory module")
            end
        end,
        counts = { [FACTORY] = 0, [HOMEMADE] = 0, [mount] = 1 },
        after = function(self) T.readCarried(self, { mount }) end,
        validate = function(self)
            expectModules(T.carriedFirst(self, mount), count == 2 and { FACTORY_MODULE, HOMEMADE_MODULE } or { FACTORY_MODULE })
        end,
    })
end

-- Unmounting gives back each module as the type, at the condition and with the seals it went in,
-- still marked as mounted and connected before if it was, and a module not so marked comes back
-- unmarked.
local MOUNTED_HOMEMADE = { type = HOMEMADE, condition = 41, repaired = 2, mounted = true, connected = true }
local PLAIN_FACTORY = { type = FACTORY, condition = 12 }
for _, entry in ipairs(MOUNTS) do
    local mount, count = entry.mount, entry.count
    local recipe = "RenewableEnergy_Unmount" .. entry.name
    craftTest(craftName(recipe, "returns_modules"), {
        recipe = recipe,
        from = mount,
        setup = function(self)
            local modules = { MOUNTED_HOMEMADE }
            if count == 2 then
                table.insert(modules, PLAIN_FACTORY)
            end
            T.changeItem(self, T.inputsOf(self, mount)[1], { modData = { [MODULES_KEY] = modules } })
        end,
        counts = { [mount] = 0, [HOMEMADE] = 1, [FACTORY] = count == 2 and 1 or 0 },
        after = function(self) T.readCarried(self, { HOMEMADE, FACTORY }) end,
        validate = function(self)
            local homemade = T.carriedFirst(self, HOMEMADE)
            if expect(homemade ~= nil, "no homemade module came back") then
                local data = homemade.modData
                expect(homemade.condition == MOUNTED_HOMEMADE.condition, "the homemade module came back at " .. homemade.condition)
                expect(homemade.repaired == MOUNTED_HOMEMADE.repaired, "the homemade module came back sealed " .. homemade.repaired .. "x")
                expect(data[PowerBank.MOUNTED_ONCE_KEY] == true and data[PowerBank.CONNECTED_ONCE_KEY] == true,
                    "the homemade module came back without its mounted and connected marks")
            end
            local factory = T.carriedFirst(self, FACTORY)
            if count == 2 and expect(factory ~= nil, "no factory module came back") then
                expect(factory.condition == PLAIN_FACTORY.condition, "the factory module came back at " .. factory.condition)
                expect(factory.repaired == 0, "the factory module came back sealed " .. factory.repaired .. "x")
                expect(factory.modData[PowerBank.MOUNTED_ONCE_KEY] ~= true, "the factory module came back marked as mounted before")
            end
        end,
    })
end

-- A mount nobody wrote modules to, as debug spawns make, holds new factory modules.
craftTest(craftName("RenewableEnergy_UnmountSolarRackMetal", "without_record_returns_new_modules"), {
    recipe = "RenewableEnergy_UnmountSolarRackMetal",
    from = "RenewableEnergy.SolarRackMetal",
    counts = { ["RenewableEnergy.SolarRackMetal"] = 0, [FACTORY] = Specs.mounts.rack.modules },
})

-- Mounting teaches only modules never mounted before: a module mounted, unmounted and mounted
-- again teaches nothing the second time, and a rack of that module and a new one teaches the new
-- one's share. The XP is the authority's character's, read before and after each craft.
test("renewable_energy_solar_mount_xp_only_for_new_modules", {
    instant = true,
    run = function(self)
        local manager = getScriptManager()
        local recipes = {}
        for key, name in pairs({ flat = "RenewableEnergy_MakeSolarFlat", unmount = "RenewableEnergy_UnmountSolarFlat",
            rack = "RenewableEnergy_MakeSolarRackWood" }) do
            recipes[key] = T.need(self, manager:getCraftRecipe(name), "the recipe " .. name)
            if not recipes[key] then return end
        end
        local p = player()
        local module, flat = FACTORY, "RenewableEnergy.SolarFlat"
        T.learnRecipes(p)
        T.placeWorkTable(p)
        T.setPerk(self, Perks.Electricity, 3)
        T.setPerk(self, Perks.Woodwork, 4)
        self.xp = {}
        local function readXp(key)
            T.server(self, "perkXp", { perk = "Electricity" })
            T.step(function() self.xp[key] = self.server.perkXp.value end)
        end
        local function craft(recipe, fullType)
            T.waitForCarried(self, fullType, "this client's " .. fullType .. " to craft from")
            T.step(function() T.startCraft(self, recipe, T.carried(fullType)) end)
        end
        -- The flat mount's wire and screws, for each time it is made.
        local fixings = {}
        for _, input in ipairs(T.recipeInputs(recipes.flat, { module })) do
            if input.type ~= module and input.type ~= "Base.Screwdriver" then
                table.insert(fixings, input)
            end
        end
        T.give(self, "flat", T.recipeInputs(recipes.flat, { module }))
        readXp("start")
        craft(recipes.flat, module)
        readXp("mounted")
        craft(recipes.unmount, flat)
        T.give(self, "again", fixings)
        readXp("unmounted")
        craft(recipes.flat, module)
        readXp("remounted")
        craft(recipes.unmount, flat)
        -- The rack's inputs with one new module, beside the one mounted twice.
        local rack = {}
        for _, input in ipairs(T.recipeInputs(recipes.rack, { module })) do
            if input.type == module then
                input.count = input.count - 1
            end
            table.insert(rack, input)
        end
        T.waitForCarried(self, module, "this client's unmounted module")
        T.give(self, "rack", rack)
        readXp("unmountedAgain")
        craft(recipes.rack, module)
        T.batch(function()
            readXp("rack")
            T.count(self, "made", { flat, "RenewableEnergy.SolarRackWood", module })
            -- What the game gives this character for each award, through the call CraftRecipe.addXP
            -- makes.
            local mounts = Recipes.MOUNTS
            T.server(self, "electricityAward", { xp = mounts[flat].xp.Electricity })
            T.step(function() self.flatAward = self.server.electricityAward.gained end)
            T.server(self, "electricityAward", { xp = mounts["RenewableEnergy.SolarRackWood"].xp.Electricity / 2 })
            T.step(function() self.rackShareAward = self.server.electricityAward.gained end)
            -- The rack's own xpAward for building the frame, given whatever the modules.
            local frame = 0
            for i = 0, recipes.rack:getXPAwardCount() - 1 do
                local award = recipes.rack:getXPAward(i)
                if award:getPerk() == Perks.Electricity then frame = frame + award:getAmount() end
            end
            T.server(self, "electricityAward", { xp = frame })
            T.step(function() self.rackFrameAward = self.server.electricityAward.gained end)
        end)
    end,
    validate = function(self)
        local refusal = self.refusal and "; the game refused: " .. self.refusal or ""
        local xp, made = self.xp, self.counts.made or {}
        if not expect(xp.rack ~= nil and made["RenewableEnergy.SolarRackWood"] == 1,
            "the crafts never got to the rack" .. refusal) then return end
        expect(xp.mounted > xp.start, "mounting a new module gave no Electricity XP")
        expectNear("Electricity XP from mounting a new module", xp.mounted - xp.start, self.flatAward, 0.01)
        expectNear("Electricity XP from unmounting", xp.unmounted - xp.mounted, 0, 0)
        expectNear("Electricity XP from mounting the same module again", xp.remounted - xp.unmounted, 0, 0)
        expectNear("Electricity XP from a rack of a used and a new module", xp.rack - xp.unmountedAgain,
            self.rackShareAward + self.rackFrameAward, 0.01)
    end,
})

-- Solar modules -------------------------------------------------------------------------------

-- Seal Cracked Module adds Recipes.MODULE_REPAIR up to the module type's cap, lowered a step for
-- each earlier seal, and is refused at that limit with the module untouched. Each seal counts
-- once, on this client's copy too, and a sealed module still shows cracked.
local function sealLimit(module, seals)
    return Recipes.MODULE_REPAIR_CAP[module] - Recipes.REPAIR_LIMIT_STEP * seals
end
-- Each row: the behaviour, the module, its seal count, and its condition before.
local MODULE_REPAIRS = {
    { "factory_adds_a_step", FACTORY, 0, sealLimit(FACTORY, 0) - Recipes.MODULE_REPAIR - 1 },
    { "factory_below_limit_stops_at_limit", FACTORY, 0, sealLimit(FACTORY, 0) - 1 },
    { "factory_at_limit_refused", FACTORY, 0, sealLimit(FACTORY, 0) },
    { "factory_after_two_seals_stops_at_lower_limit", FACTORY, 2, sealLimit(FACTORY, 2) - 1 },
    { "factory_after_three_seals_at_limit_refused", FACTORY, 3, sealLimit(FACTORY, 3) },
    { "homemade_below_limit_stops_at_limit", HOMEMADE, 0, sealLimit(HOMEMADE, 0) - 1 },
    { "homemade_after_one_seal_stops_at_lower_limit", HOMEMADE, 1, sealLimit(HOMEMADE, 1) - 1 },
}
for _, entry in ipairs(MODULE_REPAIRS) do
    local behavior, module, repaired, before = entry[1], entry[2], entry[3], entry[4]
    local limit = sealLimit(module, repaired)
    local refused = before >= limit
    local after = refused and before or math.min(limit, before + Recipes.MODULE_REPAIR)
    local repairedAfter = refused and repaired or repaired + 1
    craftTest(craftName("RenewableEnergy_RepairCrackedModule", behavior), {
        recipe = "RenewableEnergy_RepairCrackedModule",
        from = module,
        prefer = { module },
        setup = function(self)
            T.changeItem(self, T.inputsOf(self, module)[1], { condition = before })
            T.setRepaired(self, module, repaired)
        end,
        counts = { [module] = 1 },
        after = function(self)
            T.readCarried(self, { module })
            T.waitFor(self, function()
                local item = T.carried(module)
                return item ~= nil and item:getHaveBeenRepaired() == repairedAfter
            end, "this client's module repaired " .. repairedAfter .. "x")
        end,
        validate = function(self)
            local item = T.carriedFirst(self, module)
            if not expect(item ~= nil, "the module is gone") then return end
            expect(item.condition == after, "the module is at " .. item.condition .. ", expected " .. after)
            expect(item.repaired == repairedAfter, "the module reads repaired " .. item.repaired .. "x, expected " .. repairedAfter)
            -- The seal leaves the glass cracked, and the module showing it.
            expect(RenewableEnergy.crackLookOf(module, item.condition) ~= nil, "a sealed module shows whole")
            if refused then
                expect(self.refusal ~= nil, "the game would start the seal")
            end
        end,
    })
end

-- Seal Cracked Module and its glue twin each take exactly their adhesive's uses, which a line
-- scaling one adhesive against the other gets wrong (DEVELOPMENT.md, craftRecipe).
-- Each row: the behaviour, the recipe, its adhesive, and the uses of it a seal takes.
local SEAL_ADHESIVES = {
    { "takes_one_use_of_epoxy", "RenewableEnergy_RepairCrackedModule", "Base.Epoxy", 1 },
    { "takes_two_uses_of_glue", "RenewableEnergy_RepairCrackedModuleWithGlue", "Base.Glue", 2 },
}
for _, entry in ipairs(SEAL_ADHESIVES) do
    local behavior, recipe, adhesive, uses = entry[1], entry[2], entry[3], entry[4]
    craftTest(craftName(recipe, behavior), {
        recipe = recipe,
        from = FACTORY,
        prefer = { FACTORY },
        setup = function(self)
            T.changeItem(self, T.inputsOf(self, FACTORY)[1], { condition = sealLimit(FACTORY, 0) - Recipes.MODULE_REPAIR - 1 })
        end,
        counts = { [FACTORY] = 1 },
        after = function(self) T.readCarried(self, { adhesive }) end,
        validate = function(self)
            -- T.recipeInputs gave one full tube; "carried" reads the fraction of it left.
            local tube = T.carriedFirst(self, adhesive)
            local left = 1 - uses * getScriptManager():FindItem(adhesive):getUseDelta()
            expectNear("the " .. adhesive .. " left of a full tube", tube and tube.uses or 0, left, 0.001)
        end,
    })
end

-- Reglaze Module brings a module below what new glass brings it to, and is refused there with the
-- module and the pane untouched; it teaches Glassmaking, and the new glass clears the old seals.
-- New glass on light cracks brings a module back to new; on heavy cracks, or on a sealed module, to
-- the cells-cracked share of new. Each row: the behaviour, the module, its condition and seal count
-- before, the condition after, and whether the game refuses.
local REGLAZE, LOOKS = Recipes.REGLAZE, Specs.crackLooks
local function share(module, part) return math.floor(RenewableEnergy.conditionMaxOf(module) * part) end
local function heavy(module) return share(module, LOOKS.heavyBelow) - 1 end
local function light(module) return share(module, (LOOKS.heavyBelow + LOOKS.lightBelow) / 2) end
local function new(module) return share(module, REGLAZE.glassOnly) end
local function cellsCracked(module) return share(module, REGLAZE.cellsCracked) end
local REGLAZES = {
    { "factory_heavy_cracks_cells_stay_cracked", FACTORY, heavy(FACTORY), 0, cellsCracked(FACTORY) },
    { "factory_light_cracks_back_to_new", FACTORY, light(FACTORY), 0, new(FACTORY) },
    { "factory_sealed_three_times_clears_seals", FACTORY, light(FACTORY), 3, cellsCracked(FACTORY) },
    { "factory_just_below_new_back_to_new", FACTORY, new(FACTORY) - 1, 0, new(FACTORY) },
    { "factory_at_new_refused", FACTORY, new(FACTORY), 0, new(FACTORY), true },
    { "homemade_heavy_cracks_cells_stay_cracked", HOMEMADE, heavy(HOMEMADE), 0, cellsCracked(HOMEMADE) },
    { "homemade_light_cracks_back_to_new", HOMEMADE, light(HOMEMADE), 0, new(HOMEMADE) },
    { "homemade_at_new_refused", HOMEMADE, new(HOMEMADE), 0, new(HOMEMADE), true },
}
for _, entry in ipairs(REGLAZES) do
    local behavior, module, before, repaired, reglazed, refused = entry[1], entry[2], entry[3], entry[4], entry[5], entry[6]
    local after = refused and before or reglazed
    local repairedAfter = refused and repaired or 0
    craftTest(craftName("RenewableEnergy_ReglazeModule", behavior), {
        recipe = "RenewableEnergy_ReglazeModule",
        from = module,
        prefer = { module },
        setup = function(self)
            T.changeItem(self, T.inputsOf(self, module)[1], { condition = before })
            if repaired > 0 then
                T.setRepaired(self, module, repaired)
            end
            T.server(self, "perkXp", { perk = "Glassmaking" })
            T.step(function() self.glassmakingBefore = self.server.perkXp.value end)
        end,
        counts = { [module] = 1, ["Base.GlassPanel"] = refused and 1 or 0 },
        after = function(self)
            T.readCarried(self, { module })
            T.server(self, "perkXp", { perk = "Glassmaking" })
        end,
        validate = function(self)
            local item = T.carriedFirst(self, module)
            if not expect(item ~= nil, "the module is gone") then return end
            expect(item.condition == after, "the module is at " .. item.condition .. ", expected " .. after)
            expect(item.repaired == repairedAfter, "the module reads repaired " .. item.repaired .. "x, expected " .. repairedAfter)
            if refused then
                expect(self.refusal ~= nil, "the game would start the reglaze")
            else
                expect(RenewableEnergy.crackLookOf(module, item.condition) == nil, "a reglazed module shows cracked")
                local xp = self.server and self.server.perkXp
                expect(xp and self.glassmakingBefore and xp.value > self.glassmakingBefore, "reglazing taught no Glassmaking")
            end
        end,
    })
end

-- Only a module that makes no power comes apart; one that still works is worth more whole.
for _, entry in ipairs({ { nil, 0 }, { "refuses_working_module", 1 } }) do
    local behavior, condition = entry[1], entry[2]
    local refused = condition > 0
    craftTest(craftName("RenewableEnergy_TakeApartShatteredModule", behavior), {
        recipe = "RenewableEnergy_TakeApartShatteredModule",
        from = FACTORY,
        setup = function(self)
            T.changeItem(self, T.inputsOf(self, FACTORY)[1], { condition = condition })
        end,
        counts = refused and { [FACTORY] = 1, ["RenewableEnergy.SolarCells"] = 0 } or { [FACTORY] = 0 },
        validate = function(self)
            if refused then
                expect(self.refusal ~= nil, "the game would take a working module apart")
            end
        end,
    })
end

-- Storm damage over hours at the Storm Damage options (Chance.stormDamage), worked by hand: 10% an
-- hour is 10% in one hour and 1 - 0.9² = 19% in two; at a rate of 200 it is 20% an hour, so 36% in
-- two, and 60% an hour doubles past certain, which stays certain; no hours, or Storm Damage off,
-- is no chance.
test("renewable_energy_solar_storms_chance_by_hours_and_rate", {
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local stormDamage = RenewableEnergy.Chance.stormDamage
        T.step(function()
            self.normal = { stormDamage(0.1, 1), stormDamage(0.1, 2), stormDamage(0.1, 0) }
            T.setSandbox(self, "StormDamageRate", 200)
        end)
        T.step(function()
            self.doubled = { stormDamage(0.1, 2), stormDamage(0.6, 1) }
            T.setSandbox(self, "StormDamage", false)
        end)
        T.step(function() self.off = stormDamage(0.1, 2) end)
    end,
    validate = function(self)
        expectNear("10% an hour over an hour", self.normal[1], 0.1, 1e-9)
        expectNear("10% an hour over two hours", self.normal[2], 0.19, 1e-9)
        expectNear("10% an hour over no hours", self.normal[3], 0, 0)
        expectNear("10% an hour over two hours at rate 200", self.doubled[1], 0.36, 1e-9)
        expectNear("60% an hour over an hour at rate 200", self.doubled[2], 1, 1e-9)
        expectNear("10% an hour over two hours with Storm Damage off", self.off, 0, 0)
    end,
})

-- The longest run of thunderstorms the game makes: a tropical storm of up to 24 hours and the two
-- storms of up to 10 hours each that can follow it (WeatherPeriod.createWeatherPattern).
local LONGEST_THUNDER_HOURS = 24 + 2 * 10

-- Storm strength (Chance.stormStrength) is none up to where the damage starts, the square of the
-- way from there to the game's strongest wind, and all of it from there on. The worst the game
-- blows, Specs.storm worstHours at full strength at the default rate, breaks the weakest blades
-- with worstChance and no others any more often, and in any wind that can break both, weaker
-- blades are likelier to break than stronger ones. The longest run of thunderstorms cracks a
-- module of no panel more often than that either.
test("renewable_energy_solar_storms_worst_case_rule", {
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local Chance, storm = RenewableEnergy.Chance, Specs.storm
        T.step(function()
            local from = storm.fullKph / 2
            self.strengths = { Chance.stormStrength(from, from), Chance.stormStrength(from, (from + storm.fullKph) / 2),
                Chance.stormStrength(from, storm.fullKph), Chance.stormStrength(from, storm.fullKph * 2) }
            self.blades = {}
            for material, spec in pairs(Specs.wind.blades) do
                self.blades[material] = Chance.stormDamage(Chance.stormPerHour(spec.stormShare),
                    storm.worstHours * Chance.stormStrength(spec.breakKph, storm.fullKph))
            end
            self.order = {}
            for kph = Specs.wind.blades.pipe.breakKph + 1, storm.fullKph do
                local hourly = {}
                for material, spec in pairs(Specs.wind.blades) do
                    hourly[material] = Chance.stormPerHour(spec.stormShare) * Chance.stormStrength(spec.breakKph, kph)
                end
                if not (hourly.pipe > hourly.wood or hourly.wood == 0) or not (hourly.wood > hourly.steel or hourly.steel == 0) then
                    table.insert(self.order, string.format("%d km/h: pipe %g, wood %g, steel %g", kph, hourly.pipe, hourly.wood, hourly.steel))
                end
            end
        end)
        self.mounts = { "flat", "wall", "woodRack", "metalRack" }
        local trials = {}
        for i, mount in ipairs(self.mounts) do
            trials[i] = stormTrial(mount, LONGEST_THUNDER_HOURS)
        end
        self.chances = {}
        stormChances(self, "longest", trials)
    end,
    validate = function(self)
        local storm = Specs.storm
        expectNear("storm strength where the damage starts", self.strengths[1], 0, 0)
        expectNear("storm strength halfway to the strongest wind", self.strengths[2], 0.25, 1e-9)
        expectNear("storm strength at the strongest wind", self.strengths[3], 1, 1e-9)
        expectNear("storm strength past the strongest wind", self.strengths[4], 1, 1e-9)
        local highest = 0
        for material, chance in pairs(self.blades) do
            expect(chance <= storm.worstChance + 1e-9,
                string.format("%s blades break in the worst storm with %g, past %g", material, chance, storm.worstChance))
            highest = math.max(highest, chance)
        end
        expectNear("the weakest blades' chance in the worst storm", highest, storm.worstChance, 1e-9)
        expect(#self.order == 0, "stronger blades are as likely to break: " .. table.concat(self.order, "; "))
        for i, mount in ipairs(self.mounts) do
            local chance = self.chances.longest[i]
            expect(chance <= storm.worstChance, string.format("the longest thunderstorms crack a %s panel with %g, past %g",
                mount, chance, storm.worstChance))
        end
    end,
})

-- A connect job takes ConnectPanelMin minutes at Electricity 3, and 9.5% of that less for each
-- level above and more for each below: 12.85 minutes of 10 at level 0, 3.35 at level 10.
test("renewable_energy_solar_connect_time_by_electricity", {
    sandbox = { ConnectPanelMin = 10 },
    run = function(self)
        self.minutes = {}
        T.step(function()
            for _, level in ipairs({ 0, 3, 10 }) do
                T.setPerk(self, Perks.Electricity, level)
                local units = Action:new(player(), Action.CONNECT_SOURCE, nil, nil):units()
                self.minutes[level] = units / RenewableEnergy.unitsPerMinute()
            end
        end)
    end,
    validate = function(self)
        expectNear("connect minutes at Electricity 3", self.minutes[3], 10, 1e-6)
        expectNear("connect minutes at Electricity 0", self.minutes[0], 12.85, 1e-6)
        expectNear("connect minutes at Electricity 10", self.minutes[10], 3.35, 1e-6)
    end,
})
