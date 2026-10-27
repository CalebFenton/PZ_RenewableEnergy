require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local Squares = require "cf_commonlib/Squares"
local Chance = require "RenewableEnergy/Chance"
local Format = require "RenewableEnergy/UI/Format"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local Specs = require "RenewableEnergy/Specs"
local Sprites = require "RenewableEnergy/Sprites"
local Wind = require "RenewableEnergy/Wind"

-- Wind chargers (Wind.lua, PowerBank/WindSource.lua, client Wind/*): a bank source on the game's
-- wind, with its power curve, brake, storm breakage, blades and model.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect

local CONTROLLER = "RenewableEnergy.ChargeController"
local WOODEN_BLADES = "RenewableEnergy.WoodenBlades"
local PIPE_BLADES = "RenewableEnergy.PipeBlades"
local BROKEN_WOODEN_BLADES = "RenewableEnergy.BrokenWoodenBlades"

-- A battery box and a scoop rotor connected to it, the rotor's handle also in self.rotor; nil
-- when either is missing.
local function scoopOnBank(self)
    local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
    self.rotor = bank and T.panel(self, Sprites.windScoop, { near = bank, connect = true })
    if not self.rotor then return nil end
    return bank, self.rotor
end

-- The status entry of the source `handle` in the bank state read as `label`, failing when the
-- bank's status listed no `what` there.
local function passSource(self, label, handle, what)
    local source = T.stateSource(self.reads[label], handle)
    expect(source ~= nil, "after the " .. label .. " pass the bank's status lists no " .. what)
    return source
end

-- A scoop rotor wired to a bank makes power once the wind is past its cut-in speed, none at it or
-- with its brake on, and the status says why.
test("renewable_energy_wind_scoop_cut_in_and_brake", {
    run = function(self)
        local bank, rotor = scoopOnBank(self)
        if not bank then return end
        local spec = Wind.SPEC.turbines.scoop
        local function pass(label, kph) T.bankPass(self, bank, 0, { windKph = kph, label = label }) end
        T.batch(function()
            pass("windy", spec.ratedKph)
            pass("cut-in", spec.cutInKph)
            pass("past cut-in", spec.cutInKph + 1)
            T.job(self, "source", SourceJobs.BRAKE, rotor)
            pass("braked", spec.ratedKph)
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.rotor) then return end
        local function read(label) return passSource(self, label, self.rotor, "scoop rotor") end
        local windy = read("windy")
        if windy then
            expect(windy.watts > 0, "the scoop rotor made nothing at its rated speed")
            T.expectNear("the bank's wind watts", self.reads.windy.status.windW, windy.watts, 0.01)
        end
        local calm = read("cut-in")
        if calm then
            T.expectEqual("the scoop rotor's watts at its cut-in speed", calm.watts, 0)
            T.expectEqual("the scoop rotor's reason at its cut-in speed", calm.reason, "calm")
        end
        local turning = read("past cut-in")
        if turning then
            expect(turning.watts > 0, "a km/h past its cut-in speed it made nothing")
        end
        local braked = read("braked")
        if braked then
            T.expectEqual("the braked scoop rotor's watts", braked.watts, 0)
            T.expectEqual("the braked scoop rotor's reason", braked.reason, "braked")
        end
    end,
})

-- Solid walls on the scoop rotor's own level, where it turns, shelter it and cut its output, but
-- fences around it don't, low or tall, though vanilla's tiles give both a wall flag
-- (newtiledefinitions.tiles: walls_exterior_house_low_01_1 HoppableN and WallN, fencing_01_8
-- TallHoppableN and WallN).
local WALL = "walls_exterior_wooden_01_24"
local LOW_WALL = "walls_exterior_house_low_01_1"
local TALL_FENCE = "fencing_01_8"

test("renewable_energy_wind_walls_shelter_and_fences_dont", {
    run = function(self)
        local bank, rotor = scoopOnBank(self)
        if not bank then return end
        local function pass(label)
            T.bankPass(self, bank, 0, { windKph = Wind.SPEC.turbines.scoop.ratedKph, label = label })
        end
        local level = rotor.z
        T.batch(function()
            pass("open")
            T.ringOfTiles(self, rotor, level, LOW_WALL)
            T.ringOfTiles(self, rotor, level, TALL_FENCE)
            pass("fenced")
            T.ringOfTiles(self, rotor, level, WALL)
            pass("walled")
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.rotor) then return end
        local function read(label) return passSource(self, label, self.rotor, "scoop rotor") end
        local open, fenced, walled = read("open"), read("fenced"), read("walled")
        if not (open and fenced and walled) then return end
        T.expectEqual("the fenced scoop rotor's shelter %", fenced.shelterPct, open.shelterPct)
        expect(walled.shelterPct > open.shelterPct and walled.watts < open.watts, string.format(
            "walls around it left it at %d%% shelter, %g W (open: %d%%, %g W)",
            walled.shelterPct, walled.watts, open.shelterPct, open.watts))
    end,
})

-- A treadmill charger's blades turn a level above its foot (Wind.SPEC.turbines rotorAbove), and
-- its shelter is counted there: walls around its foot leave it in the open, walls on the level
-- above shelter it.
test("renewable_energy_wind_mast_sheltered_only_at_its_blades", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        self.mast = bank and T.panel(self, Sprites.windCharger.propeller.wood.S, { near = bank, connect = true })
        if not self.mast then return end
        local function pass(label)
            T.bankPass(self, bank, 0, { windKph = Wind.SPEC.turbines.propeller.ratedKph, label = label })
        end
        local foot = self.mast.z
        T.batch(function()
            pass("open")
            T.ringOfTiles(self, self.mast, foot, WALL)
            pass("foot")
            T.ringOfTiles(self, self.mast, foot + 1, WALL)
            pass("blades")
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.mast) then return end
        local function read(label) return passSource(self, label, self.mast, "treadmill charger") end
        local open, foot, blades = read("open"), read("foot"), read("blades")
        if not (open and foot and blades) then return end
        T.expectEqual("the treadmill charger's shelter % with walls around its foot", foot.shelterPct, open.shelterPct)
        expect(blades.shelterPct > open.shelterPct and blades.watts < open.watts, string.format(
            "walls at its blades left it at %d%% shelter, %g W (open: %d%%, %g W)",
            blades.shelterPct, blades.watts, open.shelterPct, open.watts))
    end,
})

-- Two treadmill chargers two squares apart take wind from each other, each its crowdShare of the
-- distance (Wind.SPEC.crowdRadius, crowdLoss), which costs enough for the status to say so; a
-- scoop rotor right beside one turns a level below its blades and takes nothing, nor loses any.
test("renewable_energy_wind_chargers_close_together_crowd_each_other", {
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER, CONTROLLER })
        local squares = bank and T.squares(self, 40, { near = bank.square })
        if not T.need(self, squares, "free outdoor squares by the bank") then return end
        local first = squares[1]
        local function away(square)
            return math.sqrt((square:getX() - first:getX()) ^ 2 + (square:getY() - first:getY()) ^ 2)
        end
        local beside, near
        for i = 2, #squares do
            local square, distance = squares[i], away(squares[i])
            if square:getZ() == first:getZ() then
                beside = beside or (distance == 1 and square or nil)
                near = near or (distance == 2 and square or nil)
            end
        end
        if not T.need(self, beside and near, "squares one and two squares from the first") then return end
        self.distance = away(near)
        T.batch(function()
            self.first = T.panel(self, Sprites.windCharger.propeller.wood.S, { square = first, near = bank, connect = true })
            self.second = T.panel(self, Sprites.windCharger.propeller.pipe.S, { square = near, near = bank, connect = true })
            self.scoop = T.panel(self, Sprites.windScoop, { square = beside, near = bank, connect = true })
            T.bankPass(self, bank, 0, { windKph = Wind.SPEC.turbines.propeller.ratedKph, label = "crowded" })
        end)
    end,
    validate = function(self)
        for _, handle in ipairs({ self.first, self.second, self.scoop }) do
            if not T.expectConnected(handle) then return end
        end
        local spec = Wind.SPEC.turbines.propeller
        local wanted = Wind.crowding({ self.distance })
        for label, handle in pairs({ first = self.first, second = self.second }) do
            local source = T.stateSource(self.reads.crowded, handle)
            if expect(source ~= nil, "the bank's status lists no " .. label .. " treadmill charger") then
                T.expectEqual(string.format("the %s charger's crowding %%, %g squares from the other", label, self.distance),
                    source.crowdingPct, math.floor(100 * wanted + 0.5))
                T.expectNear("the " .. label .. " charger's watts", source.watts,
                    Wind.watts(spec, spec.ratedKph, source.z, source.shelterPct / 100, wanted), spec.watts * 0.01)
                T.expectEqual("the " .. label .. " charger's reason", source.reason, "crowded")
            end
        end
        local scoop = T.stateSource(self.reads.crowded, self.scoop)
        if expect(scoop ~= nil, "the bank's status lists no scoop rotor") then
            T.expectEqual("the crowding % of the scoop rotor below the chargers' blades", scoop.crowdingPct, 0)
        end
    end,
})

-- Each charger's power curve: nothing at its cut-in speed, the cube of the wind on the way up,
-- its rating at its rated speed, more for standing higher only up to the height cap; the turbine
-- furls from its furl speed. Each blade material breaks from above its break speed, and on the
-- furling turbine only from furledBladeKph above that. The chargers rank in every wind: the car
-- alternator's never makes less than the treadmill motor's, nor the turbine, furled or not, less
-- than the car alternator's, from either's cut-in up to the game's strongest wind.
test("renewable_energy_wind_power_curve_rule", {
    validate = function()
        local wind = Wind.SPEC
        for kind, spec in pairs(wind.turbines) do
            local function watts(kph, z)
                return Wind.watts(spec, kph, z or 0, 0)
            end
            T.expectEqual(kind .. "'s watts at its cut-in speed", watts(spec.cutInKph), 0)
            local midway = (spec.cutInKph + spec.ratedKph) / 2
            if not Wind.furled(spec, midway) then
                T.expectNear(kind .. " halfway to its rated speed, as an eighth of its rating",
                    watts(midway), spec.watts / 8, 0.001)
            end
            T.expectEqual(kind .. "'s watts at its rated speed", watts(spec.ratedKph), spec.watts)
            if not spec.furlKph then
                T.expectEqual(kind .. "'s watts at twice its rated speed", watts(spec.ratedKph * 2), spec.watts)
            end
            local top = wind.maxBonusLevel
            expect(watts(spec.ratedKph, top) > watts(spec.ratedKph, 0), kind .. " makes no more standing higher")
            T.expectEqual(kind .. "'s watts above the height cap", watts(spec.ratedKph, top + 2), watts(spec.ratedKph, top))
            if spec.furlKph then
                expect(not Wind.furled(spec, spec.furlKph - 1) and Wind.furled(spec, spec.furlKph),
                    kind .. " doesn't furl from exactly its furl speed")
            end
            local blades = spec.blades or {}
            for _, material in ipairs(blades) do
                local breakKph = wind.blades[material].breakKph + (spec.furlKph and spec.furledBladeKph or 0)
                expect(not Wind.canBreak(spec, material, breakKph) and Wind.canBreak(spec, material, breakKph + 1),
                    kind .. "'s " .. material .. " blades can break at " .. breakKph .. " km/h, or can't just above it")
            end
            if #blades == 0 then
                expect(Wind.bladesOf(kind) == nil and not Wind.canBreak(spec, Wind.bladesOf(kind), 1000), kind .. " can break")
            end
        end
        local ranks = { "propeller", "carAlternator", "alternator" }
        for i = 1, #ranks - 1 do
            local lower, higher = wind.turbines[ranks[i]], wind.turbines[ranks[i + 1]]
            for kph = math.min(lower.cutInKph, higher.cutInKph), Specs.storm.fullKph do
                local low, high = Wind.watts(lower, kph, 0, 0), Wind.watts(higher, kph, 0, 0)
                expect(high >= low, string.format("at %d km/h the %s makes %g W, the %s %g W", kph, ranks[i + 1], high,
                    ranks[i], low))
            end
        end
    end,
})

-- This client draws each wind charger as its turning model, once the charger is added to the map
-- (OnObjectAdded, which the placePanel handler fires as placing does): each bladed kind's by its
-- blades and facing.
local DRAWN = {
    scoop = Sprites.windScoop,
    propellerPipeE = Sprites.windCharger.propeller.pipe.E,
    propellerWoodN = Sprites.windCharger.propeller.wood.N,
    propellerSteelS = Sprites.windCharger.propeller.steel.S,
    carAlternatorWoodE = Sprites.windCharger.carAlternator.wood.E,
    carAlternatorPipeN = Sprites.windCharger.carAlternator.pipe.N,
    carAlternatorSteelW = Sprites.windCharger.carAlternator.steel.W,
    turbineWoodS = Sprites.windCharger.alternator.wood.S,
    turbinePipeE = Sprites.windCharger.alternator.pipe.E,
    turbineSteelW = Sprites.windCharger.alternator.steel.W,
}

test("renewable_energy_wind_charger_drawn_as_model", {
    run = function(self)
        self.chargers = {}
        T.batch(function()
            for label, sprite in pairs(DRAWN) do
                self.chargers[label] = T.panel(self, sprite)
            end
        end)
    end,
    validate = function(self)
        for label, charger in pairs(self.chargers) do
            local object = charger and charger.object
            local model = object and object:getSpriteModel()
            expect(model ~= nil and model:getTextureName() ~= nil, "the " .. label .. " charger has no sprite model on this client")
        end
    end,
})

-- Left unbraked through an hour of the game's strongest wind, a wooden treadmill charger's blades
-- break on a roll under the hour's chance, not on one at it, and it makes nothing until a spare set
-- goes on; while whole in that wind its status says to set the brake. At its blades' break speed or
-- with Storm Damage off, even on the lowest roll, or braked, it comes through whole. The menu offers
-- Replace Blades, greyed until the character carries blades that fit.
test("renewable_energy_wind_propeller_breaks_in_storm_and_blades_mend", {
    instant = true,
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER, CONTROLLER })
        if not bank then return end
        self.left = T.panel(self, Sprites.windCharger.propeller.wood.S, { near = bank, connect = true })
        self.braked = T.panel(self, Sprites.windCharger.propeller.pipe.S, { near = bank, connect = true })
        if not (self.left and self.braked) then return end
        local spec, blades = Wind.SPEC.turbines.propeller, Wind.SPEC.blades.wood
        local gale = Specs.storm.fullKph
        T.job(self, "source", SourceJobs.BRAKE, self.braked)
        T.forceRoll(self, 0)
        T.bankPass(self, bank, 0, { windKph = blades.breakKph, label = "atBreak" })
        T.step(function() T.setSandbox(self, "StormDamage", false) end)
        T.bankPass(self, bank, 0, { windKph = gale, label = "stormOff" })
        T.step(function() T.setSandbox(self, "StormDamage", true) end)
        -- An hour's chance at full strength and a Storm Damage Rate of 100. Each list holds one
        -- roll, for the unbraked propeller: a draw for the braked one fails the pass.
        local chance = Chance.stormDamage(Chance.stormPerHour(blades.stormShare), 1)
        T.batch(function()
            T.forceRoll(self, { chance })
            T.bankPass(self, bank, 0, { windKph = gale, label = "atChance" })
            T.forceRoll(self, { chance - T.UNDER })
            T.bankPass(self, bank, 0, { windKph = gale, label = "storm" })
            -- Every later roll misses, so whatever else draws one while the test goes on neither
            -- runs past the list nor comes up.
            T.forceRoll(self, 1 - T.UNDER)
        end)
        T.waitFor(self, function() return Wind.isBroken(self.left.object) end, "this client's copy of the broken blades")
        T.step(function()
            local options = T.worldOptions(self.left.object, Format.tileName(self.left.object),
                { replace = getText("ContextMenu_RenewableEnergy_ReplaceBlades") })
            self.emptyHanded = T.optionState(options and options.replace).greyed
        end)
        T.give(self, "blades", { { type = WOODEN_BLADES } })
        T.actionJob(self, "source", self.left, SourceJobs.REPLACE_BLADES, function() return self.items.blades[1] end)
        T.waitFor(self, function() return not Wind.isBroken(self.left.object) end, "this client's copy of the new blades")
        T.batch(function()
            T.readCarried(self, { WOODEN_BLADES })
            T.bankPass(self, bank, 0, { windKph = spec.ratedKph, label = "mended" })
        end)
    end,
    validate = function(self)
        if not (T.expectConnected(self.left) and T.expectConnected(self.braked)) then return end
        for key, what in pairs({ atBreak = "at its blades' break speed", stormOff = "with Storm Damage off",
            atChance = "on a roll at the hour's chance" }) do
            local whole = T.stateSource(self.reads[key], self.left)
            if expect(whole ~= nil, "the bank's status lists no propeller") then
                expect(not whole.broken, what .. " it broke")
            end
        end
        local whole = T.stateSource(self.reads.atChance, self.left)
        if whole then
            T.expectEqual("the whole propeller's reason in the strongest wind", whole.reason, "gale")
        end
        local storm = self.reads.storm
        local left, braked = T.stateSource(storm, self.left), T.stateSource(storm, self.braked)
        if not expect(left and braked, "after the storm the bank's status lists no propellers") then return end
        expect(left.broken, "unbraked, a roll under the chance left it whole")
        T.expectEqual("the broken propeller's watts", left.watts, 0)
        T.expectEqual("the broken propeller's reason", left.reason, "broken")
        expect(not braked.broken, "the braked propeller broke")
        T.expectEqual("the braked propeller's reason", braked.reason, "braked")
        T.expectEqual("Replace Blades greyed out with no blades carried", self.emptyHanded, true)
        expect(T.carriedFirst(self, WOODEN_BLADES) == nil, "replacing the blades left them in the inventory")
        local mended = T.stateSource(self.reads.mended, self.left)
        expect(mended ~= nil and not mended.broken and mended.watts > 0, "with new blades it still makes nothing")
    end,
})

-- Input slots: a battery box's free slots take a panel and a scoop rotor and refuse the homebuilt
-- turbine, which takes more. On a rack with a controller the turbine makes its curve's watts a
-- km/h below its furl speed, turns its head aside at it, making its furled share, and breaks,
-- furled, in the strongest wind on a roll under its chance. With the controller worn out the
-- turbine no longer fits the slots left, but a panel connected after it still does.
test("renewable_energy_wind_alternator_slots_and_furling", {
    instant = true,
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local box = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        if not box then return end
        T.batch(function()
            self.panel = T.panel(self, Sprites.flat, { near = box, connect = true })
            self.scoop = T.panel(self, Sprites.windScoop, { near = box, connect = true })
            self.refused = T.panel(self, Sprites.windCharger.alternator.steel.N, { near = box, connect = true })
            T.readRecord(self, box, "box")
        end)
        local rack = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER, CONTROLLER })
        if not rack then return end
        T.batch(function()
            self.alternator = T.panel(self, Sprites.windCharger.alternator.steel.E, { near = rack, connect = true })
            self.after = T.panel(self, Sprites.flat, { near = rack, connect = true })
        end)
        if not (self.panel and self.scoop and self.refused and self.alternator and self.after) then return end
        local spec = Wind.SPEC.turbines.alternator
        local function pass(label, kph, light)
            T.bankPass(self, rack, light or 0, { windKph = kph, label = label })
        end
        T.batch(function()
            pass("below furl", spec.furlKph - 1)
            pass("furled", spec.furlKph)
            -- The one roll the gale draws; the passes after it are below the break speed.
            T.forceRoll(self, { 0 })
            pass("gale", Specs.storm.fullKph)
            T.bankPart(self, rack, CONTROLLER, { condition = 0, recount = true })
            pass("no controller", spec.furlKph - 1, 1000)
        end)
    end,
    validate = function(self)
        expect(self.panel.connected and self.scoop.connected, "a battery box refused a panel or the scoop rotor")
        expect(not self.refused.connected, "a battery box with its slots taken took the turbine")
        T.expectEqual("the refused turbine's reason", self.refused.reason, "Tooltip_RenewableEnergy_NoInputSlot")
        local slots = self.reads.box.status and self.reads.box.status.inputSlots
        if expect(slots ~= nil, "no state of the battery box") then
            T.expectEqual("the battery box's input slots used", slots.used, 2)
            T.expectEqual("the battery box's input slots", slots.total, Specs.freeSlots)
        end
        if not T.expectConnected(self.alternator) then return end
        local function read(label, handle)
            local source = T.stateSource(self.reads[label], handle)
            expect(source ~= nil, "after the " .. label .. " pass the rack's status doesn't list the source")
            return source
        end
        local spec = Wind.SPEC.turbines.alternator
        local below, furled, gale = read("below furl", self.alternator), read("furled", self.alternator), read("gale", self.alternator)
        if below and furled then
            expect(below.reason ~= "furled" and below.watts > furled.watts,
                "a km/h below its furl speed it reads " .. tostring(below.reason) .. ", " .. below.watts .. " W")
            T.expectEqual("the turbine's reason at its furl speed", furled.reason, "furled")
            T.expectNear("furled share of the rating", furled.watts / Wind.watts(spec, spec.ratedKph, furled.z,
                furled.shelterPct / 100, furled.crowdingPct / 100), spec.furledShare, 0.01)
        end
        if gale then
            expect(gale.broken, "furled in the strongest wind it didn't break")
            T.expectEqual("the turbine's watts after the gale", gale.watts, 0)
        end
        local alternator, panel = read("no controller", self.alternator), read("no controller", self.after)
        if alternator and panel then
            T.expectEqual("the turbine's reason without the controller", alternator.reason, "noController")
            expect(panel.reason ~= "noController" and panel.watts > 0,
                "a panel after the turbine lost its slot too: " .. panel.watts .. " W, " .. tostring(panel.reason))
        end
    end,
})

-- Every bladed charger takes any blades (Wind.SPEC.turbines blades): a broken one takes wooden
-- and pipe blades whatever it had, and Replace Blades offers its own material when carried, else
-- the first other blades it takes that are carried.
local OFFERED = {
    { label = "wooden treadmill charger", sprite = Sprites.windCharger.propeller.wood.S },
    { label = "steel car alternator charger", sprite = Sprites.windCharger.carAlternator.steel.S },
    { label = "steel turbine", sprite = Sprites.windCharger.alternator.steel.S },
}

test("renewable_energy_wind_any_charger_takes_any_blades", {
    run = function(self)
        self.chargers = {}
        for i, charger in ipairs(OFFERED) do
            self.chargers[i] = T.panel(self, charger.sprite)
            if not self.chargers[i] then return end
        end
        T.holdLight(self)
        T.give(self, "blades", { { type = PIPE_BLADES }, { type = WOODEN_BLADES } })
        T.step(function()
            -- Broken on this client's copies only: Replace Blades is the menu's to offer.
            for _, charger in ipairs(self.chargers) do
                local modData = charger.object:getModData()
                modData[Wind.BROKEN_KEY] = true
                T.defer(self, function() modData[Wind.BROKEN_KEY] = nil end)
            end
        end)
    end,
    validate = function(self)
        local pipe, wood = self.items.blades[1], self.items.blades[2]
        local carried = { wood = wood, pipe = pipe }
        for i, charger in ipairs(OFFERED) do
            local object = self.chargers[i].object
            for material, blades in pairs(carried) do
                T.expectEqual(material .. " blades' refusal on the " .. charger.label,
                    SourceJobs.refusal(T.player(), SourceJobs.REPLACE_BLADES, object, blades), nil)
            end
            local options = T.worldOptions(object, Format.tileName(object),
                { replace = getText("ContextMenu_RenewableEnergy_ReplaceBlades") })
            local option = options and options.replace
            local kind, _, own = Sprites.kindOf(charger.sprite)
            local wanted = carried[own]
            for _, material in ipairs(Wind.SPEC.turbines[kind].blades) do
                wanted = wanted or carried[material]
            end
            if expect(T.offered(option), "on the " .. charger.label .. " Replace Blades isn't offered") then
                T.expectEqual("the blades Replace Blades takes on the " .. charger.label, option.param4:getFullType(),
                    wanted:getFullType())
            end
        end
    end,
})

-- Replacing a broken charger's blades with another material's makes it that material's tile of
-- its kind facing the same way, its entity and model too, and its bank's record turns those
-- blades; the new blades are used and the broken old ones come back. `bank` is one with room for it.
local function swapTest(name, what, bank, from, to, newBlades, brokenBlades)
    test(name, {
        instant = true,
        run = function(self)
            self.bank = T.bank(self, bank.kind, bank.parts)
            if not self.bank then return end
            self.charger = T.panel(self, from, { near = self.bank, connect = true, built = true, broken = true })
            if not self.charger then return end
            T.waitFor(self, function() return Wind.isBroken(self.charger.object) end, "this client's copy of the broken blades")
            T.holdLight(self)
            T.give(self, "blades", { { type = newBlades } })
            T.actionJob(self, "source", self.charger, SourceJobs.REPLACE_BLADES, function() return self.items.blades[1] end)
            self.texture = getScriptManager():getSpriteModel(Sprites.windModelOf(to) .. "0"):getTextureName()
            -- The new tile's entity, or each load of it logs "Invalid SpriteConfig object!".
            T.waitFor(self, function()
                local object = Sources.findOn(self.charger.square)
                local config = object and object:getSpriteConfig()
                local model = object and object:getSpriteModel()
                self.object = object
                return object ~= nil and not Wind.isBroken(object) and Sprites.nameOf(object) == to
                    and config ~= nil and config:isValid() and model ~= nil and model:getTextureName() == self.texture
            end, "this client's copy of the " .. what .. ", its entity and its model")
            T.batch(function()
                T.readCarried(self, { newBlades, brokenBlades })
                T.readRecord(self, self.bank)
            end)
        end,
        validate = function(self)
            if not T.expectConnected(self.charger) then return end
            local blades
            for _, record in ipairs(self.bank.state and self.bank.state.records or {}) do
                if Squares.samePosition(record, self.charger) then
                    blades = record.blades
                end
            end
            local _, _, material = Sprites.kindOf(to)
            T.expectEqual("the blades in the bank's record of the " .. what, blades, material)
            expect(T.carriedFirst(self, newBlades) == nil, "the new blades stayed in the inventory")
            T.expectEqual("the " .. brokenBlades .. " carried", #T.carriedItems(self, brokenBlades), 1)
        end,
    })
end

swapTest("renewable_energy_wind_blades_swap_material", "pipe treadmill charger",
    { kind = "batteryBoxWood", parts = { T.CAR_BATTERY, T.PLUG_IN_INVERTER } },
    Sprites.windCharger.propeller.wood.E, Sprites.windCharger.propeller.pipe.E, PIPE_BLADES, BROKEN_WOODEN_BLADES)
swapTest("renewable_energy_wind_turbine_blades_swap_material", "wooden turbine",
    { kind = "batteryRackWood", parts = { T.CAR_BATTERY, T.PLUG_IN_INVERTER, CONTROLLER } },
    Sprites.windCharger.alternator.steel.N, Sprites.windCharger.alternator.wood.N, WOODEN_BLADES, "RenewableEnergy.BrokenSteelBlades")

-- Each bladed kind's one build menu entry, and the entity each of its blades makes of it: the
-- entities of the tiles Sprites.windCharger names, since a SpriteConfig takes only its own tiles.
local BUILT = {
    { entry = "Base.RenewableEnergy_PropellerWood", kind = "propeller", entities = { wood = "RenewableEnergy_PropellerWood",
        pipe = "RenewableEnergy_PropellerPipe", steel = "RenewableEnergy_PropellerSteel" } },
    { entry = "Base.RenewableEnergy_CarAlternatorWood", kind = "carAlternator", entities = {
        wood = "RenewableEnergy_CarAlternatorWood", pipe = "RenewableEnergy_CarAlternatorPipe",
        steel = "RenewableEnergy_CarAlternatorSteel" } },
    { entry = "Base.RenewableEnergy_TurbineWood", kind = "alternator", entities = { wood = "RenewableEnergy_TurbineWood",
        pipe = "RenewableEnergy_TurbinePipe", steel = "RenewableEnergy_AlternatorWindCharger" } },
}

-- The build menu's own path builds the bladed kind of `design` from its one entry with `material`
-- blades, and the charger's OnCreate fits the blades the build took: it stands on its kind's tile
-- of those blades, facing the way it was built, as that tile's entity, whose SpriteConfig takes
-- it. The entity is named, not inferred from a valid SpriteConfig: the config finds its tile once,
-- as it is added, so a tile swapped under the old entity still reads valid. One build a test, as
-- each built charger stands in the way of the next one's walk.
local function buildsCharger(design, material)
    local what = material .. " " .. design.kind
    return {
        instant = true,
        run = function(self)
            local square = T.buildSite(self)
            if not square then return end
            self.build = T.build(self, design.entry, square, { Wind.SPEC.blades[material].item }, function()
                self.object = Sources.findOn(square)
                return self.object ~= nil
            end, "this client's copy of the " .. what .. " charger")
            if not self.build then return end
            T.step(function()
                local object = self.object
                if not object then return end
                local config, script = object:getSpriteConfig(), object:getEntityScript()
                self.sprite = Sprites.nameOf(object)
                self.built = script and script:getName()
                self.configValid = config ~= nil and config:isValid() and object:getMasterObject() == object
            end)
        end,
        validate = function(self)
            local build = self.build
            local tile = Sprites.windTileOf(design.kind, build.face, material)
            expect(tile ~= nil, "the " .. what .. " charger has no tile facing " .. tostring(build.face))
            T.expectEqual("the tile of the " .. what .. " charger built facing " .. tostring(build.face), self.sprite, tile)
            T.expectEqual("the " .. what .. " charger's entity", self.built, design.entities[material])
            expect(self.configValid, "the " .. what .. " charger's SpriteConfig refused its tile")
        end,
    }
end

for _, design in ipairs(BUILT) do
    for _, material in ipairs(Wind.SPEC.turbines[design.kind].blades) do
        test("renewable_energy_wind_build_menu_fits_" .. material .. "_blades_" .. design.kind, buildsCharger(design, material))
    end
end

-- A charger losing more than shelteredShare of its unsheltered watts to shelter gives "sheltered"
-- as its reason, and one losing less gives none: a ring of walls beside it costs about 6%, walls
-- filling the squares out to 5 about 43% (WindSource's shelter weights, worked by hand).
test("renewable_energy_wind_sheltered_reason", {
    run = function(self)
        local bank, rotor = scoopOnBank(self)
        if not bank then return end
        local rated = Wind.SPEC.turbines.scoop.ratedKph
        local function wallsOut(from, to)
            T.step(function()
                T.batch(function()
                    for dx = -5, 5 do
                        for dy = -5, 5 do
                            local distance = math.sqrt(dx * dx + dy * dy)
                            local square = getSquare(rotor.x + dx, rotor.y + dy, rotor.z)
                            if distance > from and distance <= to and square then
                                T.placeTile(self, square, WALL)
                            end
                        end
                    end
                end)
            end)
        end
        wallsOut(0, 1.5)
        T.bankPass(self, bank, 0, { windKph = rated, label = "ring" })
        wallsOut(1.5, 5)
        T.bankPass(self, bank, 0, { windKph = rated, label = "walled" })
    end,
    validate = function(self)
        if not T.expectConnected(self.rotor) then return end
        local spec = Wind.SPEC.turbines.scoop
        local function loss(source)
            return 1 - source.watts / Wind.watts(spec, spec.ratedKph, source.z, 0)
        end
        local ring = passSource(self, "ring", self.rotor, "scoop rotor")
        local walled = passSource(self, "walled", self.rotor, "scoop rotor")
        if not (ring and walled) then return end
        local sheltered = Wind.SPEC.shelteredShare
        expect(loss(ring) < sheltered and ring.reason ~= "sheltered", string.format(
            "a ring of walls beside it, losing %.0f%% of its watts to shelter, it reads %s", 100 * loss(ring), tostring(ring.reason)))
        expect(loss(walled) > sheltered, string.format("walled in out to 5 squares, it loses only %.0f%% of its watts to shelter",
            100 * loss(walled)))
        T.expectEqual("the walled-in scoop rotor's reason", walled.reason, "sheltered")
    end,
})
