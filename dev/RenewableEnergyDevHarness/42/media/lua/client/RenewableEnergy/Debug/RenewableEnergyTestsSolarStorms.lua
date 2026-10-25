require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"

-- Solar storms: storms cracking panel modules (PowerBank/PanelSource.lua, Chance.lua).

local T = RenewableEnergyTest
local test, expect, expectNear = T.test, T.expect, T.expectNear
local Specs, Sprites, PowerBank = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.PowerBank
local MODULES_KEY = PowerBank.MODULES_KEY
local CAR_BATTERY = "Base.CarBattery1"
local FACTORY = "RenewableEnergy.SolarModule"

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
        T.step(function() self.before = table.concat(T.overlaysOf(panel.object), ",") end)
        T.forceRoll(self, 0)
        T.bankPass(self, bank, 1000, { stormHours = 1 })
        T.server(self, "panelState", panel.position)
        T.waitFor(self, function()
            return recordedCondition(panel.object) == self.crackedTo
                and table.concat(T.overlaysOf(panel.object), ",") == table.concat(self.server.panelState.overlays, ",")
        end, "this client's copy of the storm-cracked panel")
        T.step(function() self.copyOverlays = table.concat(T.overlaysOf(panel.object), ",") end)
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
        T.expectOk(self.disconnected, "disconnecting the panel")
        expectNear("the disconnected panel after the next storm", condition(self.second, 1), 100 - crack, 0)
        expectNear("the loose outdoor panel after a second storm", condition(self.second, 2), 100 - 2 * crack, 0)
        expectNear("the loose indoor panel after a second storm", condition(self.second, 3), 100, 0)
    end,
})

-- Storm damage over hours at the Storm Damage options (Chance.stormDamage): a chance an hour
-- compounds over the hours, the rate scales the chance an hour, and a chance scaled past certain
-- stays certain; no hours, or Storm Damage off, is no chance. The expected chances are worked by hand.
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
