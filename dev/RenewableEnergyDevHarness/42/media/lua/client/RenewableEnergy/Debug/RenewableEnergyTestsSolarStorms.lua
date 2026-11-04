require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local Specs = require "RenewableEnergy/Specs"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local ModuleRepair = require "RenewableEnergy/PowerBank/ModuleRepair"
local Items = require "cf_commonlib/Items"
local StormChance = require "RenewableEnergy/StormChance"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local Sprites = require "RenewableEnergy/Sprites"
local Wind = require "RenewableEnergy/Wind"

-- Solar storms: storms cracking panel modules (PowerBank/PanelSource.lua, StormChance.lua).

local T = RenewableEnergyTest
local test, expect, expectNear, expectEqual = T.test, T.expect, T.expectNear, T.expectEqual
local MODULES_KEY = Panel.MODULES_KEY

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

-- How likely a storm is to crack a module, and what a crack does. By mount: wall panels never,
-- wooden racks most, metal racks least, and the more the longer the storm. At the Storm Damage
-- options (StormChance.stormDamage): a chance an hour compounds over the hours, the rate scales the
-- chance an hour, a chance scaled past certain stays certain, and no hours or Storm Damage off is
-- no chance; those expected chances are worked by hand. A roll under a panel's chance cracks a
-- module by Specs.storm.crack, never below 0, and a roll at it doesn't.
test("renewable_energy_solar_storms_crack_chance", {
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        T.batch(function()
            -- PanelStorms.stormChance for each trial.
            T.read(self, "stormChances", { trials = { stormTrial("wall", 20), stormTrial("woodRack", 20), stormTrial("flat", 20),
                stormTrial("metalRack", 20), stormTrial("flat", 40), stormTrial("flat", 0) } }, "mounts")
            -- The last module has less than a crack left, so a crack would take it below 0.
            T.read(self, "stormCrack", { trials = { stormTrial("flat", 20, 100, "under"), stormTrial("flat", 20, 100, "at"),
                stormTrial("flat", 20, math.floor(Specs.storm.crack / 2), 0) } }, "rolls")
        end)
        local stormDamage = StormChance.stormDamage
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
        local wall, woodRack, flat, metalRack, longer, none = unpack(self.reads.mounts.chances)
        expectEqual("a wall panel's chance of a crack", wall, 0)
        expect(woodRack > flat and flat > metalRack and metalRack > 0,
            string.format("chances of a crack in 20 hours of storm: wooden rack %g, flat %g, metal rack %g", woodRack, flat, metalRack))
        expect(longer > flat, string.format("a flat panel's chance in 40 hours of storm %g, in 20 %g", longer, flat))
        expectEqual("a flat panel's chance in no storm", none, 0)
        expectNear("10% an hour over an hour", self.normal[1], 0.1, 1e-9)
        expectNear("10% an hour over two hours", self.normal[2], 0.19, 1e-9)
        expectEqual("10% an hour over no hours", self.normal[3], 0)
        expectNear("10% an hour over two hours at rate 200", self.doubled[1], 0.36, 1e-9)
        expectNear("60% an hour over an hour at rate 200", self.doubled[2], 1, 1e-9)
        expectEqual("10% an hour over two hours with Storm Damage off", self.off, 0)
        local under, at, floor = unpack(self.reads.rolls.results)
        expect(under.cracked, "a roll just under a flat panel's chance didn't crack it")
        expectEqual("a module at 100 after a crack", under.modules[1].condition, 100 - Specs.storm.crack)
        expect(not at.cracked, "a roll at a flat panel's chance cracked it")
        expectEqual("a module at 100 after a roll at the chance", at.modules[1].condition, 100)
        expectEqual("a module under a crack's worth after a crack", floor.modules[1].condition, 0)
    end,
})

-- Pending damage wins over the older object on reload, even when a repair precedes the next
-- simulation pass. The repair must then become the bank's truth, without removing its snow.
-- The module, sealed once, is left heavily cracked by the storm, so the seal is the one sealing
-- in hand gives it (ModuleRepair.sealed) and its glass still shows cracks.
local STORMED = 20

test("renewable_energy_solar_storms_unloaded_damage_then_immediate_seal", {
    spOnly = T.CHUNK_RELOAD_SP_ONLY,
    timeoutSeconds = T.CHUNK_RELOAD_SECONDS,
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true,
            modules = { { type = T.FACTORY_MODULE, condition = STORMED + Specs.storm.crack, repaired = 1, mounted = true } } })
        if not panel then return end
        self.bank, self.panel = bank, panel
        T.trackSquare(self, panel)
        T.setRecipeSkills(self, getScriptManager():getCraftRecipe(ModuleRepair.SEAL_RECIPE))
        T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.Epoxy" } })
        T.snowfall(self, bank, 2)
        T.forceRoll(self, 0)
        T.reloadChunk(self, bank, function()
            T.step(function()
                expect(getSquare(panel.x, panel.y, panel.z) == nil,
                    "the panel's square stayed loaded during the storm")
            end)
            T.bankPass(self, bank, 0, { stormHours = 1, airC = -10, label = "away" })
        end)
        T.batch(function()
            T.readRecord(self, bank, nil, 0)
            T.job(self, "source", SourceJobs.SEAL_MODULE, panel, 1, "sealed")
            T.read(self, "panelState", T.at(panel), "panel")
            T.readRecord(self, bank, "sealedBank")
            T.bankPass(self, bank, 1000, { airC = -10, label = "later" })
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) or not T.expectOk(self.reads.sealed, "sealing after the unloaded storm") then return end
        local away = self.reads.away
        expectEqual("bank items while its chunk was unloaded", #away.items, 0)
        expectEqual("module condition after the unloaded storm", away.status.sources[1].modules[1].condition, STORMED)
        expect(away.status.sources[1].snow > 0.5, "the panel lost its snow cover before the repair")
        local condition, seals = ModuleRepair.sealed(T.FACTORY_MODULE, STORMED, 1)
        local module = self.reads.panel.modules[1]
        expectEqual("sealed module condition", module.condition, condition)
        expectEqual("seals after repairing the storm damage", module.repaired, seals)
        expect(module.mounted and module.connected, "the repair lost the module's earned-XP markers")
        expectEqual("bank's module immediately after repair", self.reads.sealedBank.status.sources[1].modules[1].condition, condition)
        expectEqual("bank's module after another pass", self.reads.later.status.sources[1].modules[1].condition, condition)
        local look = ModuleRepair.crackLookOf(T.FACTORY_MODULE, condition)
        expectEqual("cracks below the snow after repair", table.concat(self.reads.panel.overlays, ","),
            tostring(look and Sprites.cracks[look].flat[1]) .. "," .. Sprites.snow.flat)
    end,
})

-- A storm cracks a panel out in the weather whether or not it feeds a bank: a loose panel outdoors
-- cracks, one indoors doesn't, and a connected one is its bank's to crack, at the bank's next pass,
-- which takes the crack to the panel's own record and tile: a new module's first crack shows light
-- cracks, on this client too. Once disconnected, the next storm cracks it loose. A pass weathers
-- every storm hour since the last at once, so the bank's pass is explicit to keep the count of
-- passes fixed.
test("renewable_energy_solar_storms_crack_loose_panels", {
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local whole = Items.conditionMaxOf(T.FACTORY_MODULE)
        self.whole = whole
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY }, { charge = 0.5 })
        local connected = bank and T.panel(self, Sprites.flat, { near = bank, modules = T.factoryModules(whole), connect = true })
        local outdoors = connected and T.panel(self, Sprites.flat, { near = bank, modules = T.factoryModules(whole) })
        local indoorSquare = outdoors and T.square(self, { indoors = true, near = bank }, "a free indoor square for a panel")
        local indoors = indoorSquare and T.panel(self, Sprites.flat, { square = indoorSquare, modules = T.factoryModules(whole) })
        if not indoors then return end
        self.connected = connected
        local panels = { T.at(connected), T.at(outdoors), T.at(indoors) }
        T.step(function() self.before = table.concat(T.overlaysOf(connected.object), ",") end)
        -- Every roll the lowest: each panel at risk cracks.
        T.forceRoll(self, 0)
        T.batch(function()
            T.read(self, "panelStorm", { hours = 1, panels = panels }, "first")
            T.bankPass(self, bank, 0, { hours = 1, label = "banked" })
            T.read(self, "panelState", T.at(connected), "cracked")
        end)
        T.waitFor(self, function()
            local cracked = self.reads.cracked
            return cracked ~= nil and recordedCondition(connected.object) == whole - Specs.storm.crack
                and table.concat(T.overlaysOf(connected.object), ",") == table.concat(cracked.overlays, ",")
        end, "this client's copy of the storm-cracked panel")
        T.step(function() self.copyOverlays = table.concat(T.overlaysOf(connected.object), ",") end)
        T.batch(function()
            T.job(self, "source", SourceJobs.DISCONNECT, connected, nil, "disconnected")
            T.read(self, "panelStorm", { hours = 1, panels = panels }, "second")
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.connected) then return end
        local whole, crack = self.whole, Specs.storm.crack
        local function condition(label, i)
            local modules = self.reads[label].modules
            return modules[i] and modules[i][1] and modules[i][1].condition
        end
        expectEqual("the connected panel after a storm its bank didn't run", condition("first", 1), whole)
        expectEqual("the loose outdoor panel after a storm", condition("first", 2), whole - crack)
        expectEqual("the loose indoor panel after a storm", condition("first", 3), whole)
        expectEqual("the connected panel after its bank's pass", self.reads.banked.status.sources[1].modules[1].condition,
            whole - crack)
        local cracked = self.reads.cracked
        expectEqual("the connected panel's recorded condition after its bank's pass", cracked.modules[1].condition, whole - crack)
        expectEqual("the whole panel's overlays before the storm", self.before, "")
        expectEqual("the storm-cracked panel's overlays", table.concat(cracked.overlays, ","), Sprites.cracks.light.flat[1])
        expectEqual("this client's copy of the storm-cracked panel's overlays", self.copyOverlays, table.concat(cracked.overlays, ","))
        T.expectOk(self.reads.disconnected, "disconnecting the panel")
        expectEqual("the disconnected panel after the next storm", condition("second", 1), whole - 2 * crack)
        expectEqual("the loose outdoor panel after a second storm", condition("second", 2), whole - 2 * crack)
        expectEqual("the loose indoor panel after a second storm", condition("second", 3), whole)
    end,
})

-- The longest run of thunderstorms the game makes: a tropical storm of up to 24 hours and the two
-- storms of up to 10 hours each that can follow it (WeatherPeriod.createWeatherPattern).
local LONGEST_THUNDER_HOURS = 24 + 2 * 10

-- Storm strength (StormChance.stormStrength) is none up to where the damage starts, the square of the
-- way from there to the game's strongest wind, and all of it from there on. The worst the game
-- blows, Specs.storm worstHours at full strength at the default rate, breaks the weakest blades
-- with worstChance and no others any more often, and in any wind that can break both, weaker
-- blades are likelier to break than stronger ones. The longest run of thunderstorms cracks a
-- module of no panel more often than that either.
test("renewable_energy_solar_storms_worst_case_rule", {
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local storm = Specs.storm
        T.step(function()
            local from = storm.fullKph / 2
            self.strengths = { StormChance.stormStrength(from, from), StormChance.stormStrength(from, (from + storm.fullKph) / 2),
                StormChance.stormStrength(from, storm.fullKph), StormChance.stormStrength(from, storm.fullKph * 2) }
            self.blades = {}
            for material, spec in pairs(Wind.SPEC.blades) do
                self.blades[material] = StormChance.stormDamage(StormChance.stormPerHour(spec.stormShare),
                    storm.worstHours * StormChance.stormStrength(spec.breakKph, storm.fullKph))
            end
            self.order = {}
            for kph = Wind.SPEC.blades.pipe.breakKph + 1, storm.fullKph do
                local hourly = {}
                for material, spec in pairs(Wind.SPEC.blades) do
                    hourly[material] = StormChance.stormPerHour(spec.stormShare) * StormChance.stormStrength(spec.breakKph, kph)
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
        T.read(self, "stormChances", { trials = trials }, "longest")
    end,
    validate = function(self)
        local storm = Specs.storm
        expectEqual("storm strength where the damage starts", self.strengths[1], 0)
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
            local chance = self.reads.longest.chances[i]
            expect(chance <= storm.worstChance, string.format("the longest thunderstorms crack a %s panel with %g, past %g",
                mount, chance, storm.worstChance))
        end
    end,
})
