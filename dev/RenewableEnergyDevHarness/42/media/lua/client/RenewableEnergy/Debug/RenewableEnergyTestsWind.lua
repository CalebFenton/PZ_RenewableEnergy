require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local Squares = require "cf_commonlib/Squares"
local Format = require "RenewableEnergy/UI/Format"
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

-- The watts the wind charger whose status entry is `source` makes at `ratedW`, its watts in the
-- open on the ground at the Wind Multiplier the test sets, by hand from Wind.SPEC: 15% more for
-- each level it stands on up to the third, 70% of its shelter lost, then `crowding` (its entry's
-- if nil) lost. The entry gives shelter and crowding in whole percents, so this is good to about a
-- percent of `ratedW`.
local function expectedW(source, ratedW, crowding)
    local height = 1 + 0.15 * math.min(math.max(source.z, 0), 3)
    return ratedW * height * (1 - 0.7 * source.shelterPct / 100) * (1 - (crowding or source.crowdingPct / 100))
end

-- Expects the wind charger whose status entry is `source`, read as `what`, to make `ratedW` as
-- expectedW gives it, to a percent of `ratedW`.
local function expectWatts(what, source, ratedW, crowding)
    T.expectNear(string.format("%s's watts (z %d, %d%% shelter, %d%% crowding)", what, source.z, source.shelterPct,
        source.crowdingPct), source.watts, expectedW(source, ratedW, crowding), ratedW * 0.01)
end

-- A scoop rotor wired to a bank makes its rating at its rated speed, an eighth of it halfway from
-- its cut-in speed (Wind.SPEC.turbines.scoop: 150 W at 45 km/h from 8 km/h; (26.5 - 8) / (45 - 8)
-- = 1/2, cubed 1/8, so 18.75 W), none at its cut-in or with its brake on, and the status says why;
-- with the brake released it makes its rating again. This client's copy, which stops the rotor
-- drawn (WindSpin), has the brake on and off with it.
test("renewable_energy_wind_scoop_cut_in_and_brake", {
    sandbox = { WindMultiplier = 1 },
    run = function(self)
        local bank, rotor = scoopOnBank(self)
        if not bank then return end
        local function pass(label, kph) T.bankPass(self, bank, 0, { windKph = kph, label = label }) end
        T.batch(function()
            pass("windy", 45)
            pass("cut-in", 8)
            pass("midway", 26.5)
            T.job(self, "source", SourceJobs.BRAKE, rotor)
            pass("braked", 45)
        end)
        T.waitFor(self, function() return Wind.isBraked(rotor.object) end, "this client's copy of the braked rotor")
        T.batch(function()
            T.job(self, "source", SourceJobs.RELEASE_BRAKE, rotor)
            pass("released", 45)
        end)
        T.waitFor(self, function() return not Wind.isBraked(rotor.object) end, "this client's copy of the released rotor")
    end,
    validate = function(self)
        if not T.expectConnected(self.rotor) then return end
        local function read(label) return passSource(self, label, self.rotor, "scoop rotor") end
        local windy = read("windy")
        if windy then
            expectWatts("the scoop rotor at its rated speed", windy, 150)
            T.expectNear("the bank's wind watts", self.reads.windy.status.windW, windy.watts, 0.01)
        end
        local calm = read("cut-in")
        if calm then
            T.expectEqual("the scoop rotor's watts at its cut-in speed", calm.watts, 0)
            T.expectEqual("the scoop rotor's reason at its cut-in speed", calm.reason, "calm")
        end
        local midway = read("midway")
        if midway then
            expectWatts("the scoop rotor halfway from its cut-in to its rated speed", midway, 18.75)
        end
        local braked = read("braked")
        if braked then
            T.expectEqual("the braked scoop rotor's watts", braked.watts, 0)
            T.expectEqual("the braked scoop rotor's reason", braked.reason, "braked")
        end
        local released = read("released")
        if released and windy then
            T.expectNear("the released scoop rotor's watts, against before its brake", released.watts, windy.watts, 0.01)
            T.expectEqual("the released scoop rotor's reason, against before its brake", released.reason, windy.reason)
        end
    end,
})

-- Solid walls on the scoop rotor's own level, where it turns, shelter it and cut its output, but
-- fences around it don't, low or tall, though vanilla's tiles give both a wall flag
-- (newtiledefinitions.tiles: walls_exterior_house_low_01_1 HoppableN and WallN, fencing_01_8
-- TallHoppableN and WallN). A charger losing more than shelteredShare (30%) of its unsheltered
-- watts to shelter gives "sheltered" as its reason, and one losing less gives none: a ring of walls
-- beside it costs less than that, walls filling the squares out to 5 more, as WindSource's
-- weights, nearer squares counting for more, make them. Each pass loses 70% of the shelter it
-- reads (Wind.SPEC.shelterLoss); in the open the scoop makes 150 W at its rated 45 km/h.
local WALL = "walls_exterior_wooden_01_24"
local LOW_WALL = "walls_exterior_house_low_01_1"
local TALL_FENCE = "fencing_01_8"

test("renewable_energy_wind_walls_shelter_and_fences_dont", {
    sandbox = { WindMultiplier = 1 },
    run = function(self)
        local bank, rotor = scoopOnBank(self)
        if not bank then return end
        local function pass(label)
            T.bankPass(self, bank, 0, { windKph = 45, label = label })
        end
        local level = rotor.z
        T.batch(function()
            pass("open")
            T.ringOfTiles(self, rotor, level, LOW_WALL)
            T.ringOfTiles(self, rotor, level, TALL_FENCE)
            pass("fenced")
            T.ringOfTiles(self, rotor, level, WALL)
            pass("ring")
        end)
        T.step(function()
            T.batch(function()
                for dx = -5, 5 do
                    for dy = -5, 5 do
                        local distance = math.sqrt(dx * dx + dy * dy)
                        local square = getSquare(rotor.x + dx, rotor.y + dy, level)
                        if distance > 1.5 and distance <= 5 and square then
                            T.placeTile(self, square, WALL)
                        end
                    end
                end
            end)
        end)
        pass("walled")
    end,
    validate = function(self)
        if not T.expectConnected(self.rotor) then return end
        local function read(label) return passSource(self, label, self.rotor, "scoop rotor") end
        local open, fenced, ring, walled = read("open"), read("fenced"), read("ring"), read("walled")
        if not (open and fenced and ring and walled) then return end
        T.expectEqual("the fenced scoop rotor's shelter %", fenced.shelterPct, open.shelterPct)
        expect(ring.shelterPct > open.shelterPct, string.format("a ring of walls around it left it at %d%% shelter (open: %d%%)",
            ring.shelterPct, open.shelterPct))
        for label, source in pairs({ open = open, fenced = fenced, ring = ring, walled = walled }) do
            expectWatts("the " .. label .. " scoop rotor", source, 150)
        end
        -- Its loss to shelter, against its 150 W in the open at its height (expectedW).
        local function loss(source)
            return 1 - source.watts / expectedW({ z = source.z, shelterPct = 0, crowdingPct = source.crowdingPct }, 150)
        end
        expect(loss(ring) < 0.3 and ring.reason ~= "sheltered", string.format(
            "a ring of walls beside it, losing %.0f%% of its watts to shelter, it reads %s", 100 * loss(ring), tostring(ring.reason)))
        expect(loss(walled) > 0.3, string.format("walled in out to 5 squares, it loses only %.0f%% of its watts to shelter",
            100 * loss(walled)))
        T.expectEqual("the walled-in scoop rotor's reason", walled.reason, "sheltered")
    end,
})

-- A treadmill charger's blades turn a level above its foot (Wind.SPEC.turbines rotorAbove), and
-- its shelter is counted there: walls around its foot leave it in the open, walls on the level
-- above shelter it.
test("renewable_energy_wind_mast_sheltered_only_at_its_blades", {
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER, CONTROLLER })
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

-- Two treadmill chargers two squares apart take wind from each other: Wind.SPEC's crowdLoss of a
-- quarter beside it, falling by a third of that each square out to none past 3, so a sixth at two
-- squares (0.25 * 2 / 3), which costs enough for the status to say so (15%); each makes 5/6 of its
-- 300 W at its rated 40 km/h. A scoop rotor right beside one turns a level below its blades and
-- takes nothing, nor loses any.
test("renewable_energy_wind_chargers_close_together_crowd_each_other", {
    sandbox = { WindMultiplier = 1 },
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
        T.batch(function()
            self.first = T.panel(self, Sprites.windCharger.propeller.wood.S, { square = first, near = bank, connect = true })
            self.second = T.panel(self, Sprites.windCharger.propeller.pipe.S, { square = near, near = bank, connect = true })
            self.scoop = T.panel(self, Sprites.windScoop, { square = beside, near = bank, connect = true })
            T.bankPass(self, bank, 0, { windKph = 40, label = "crowded" })
        end)
    end,
    validate = function(self)
        for _, handle in ipairs({ self.first, self.second, self.scoop }) do
            if not T.expectConnected(handle) then return end
        end
        for label, handle in pairs({ first = self.first, second = self.second }) do
            local source = T.stateSource(self.reads.crowded, handle)
            if expect(source ~= nil, "the bank's status lists no " .. label .. " treadmill charger") then
                T.expectEqual("the " .. label .. " charger's crowding %, 2 squares from the other", source.crowdingPct, 17)
                expectWatts("the " .. label .. " charger", source, 300, 1 / 6)
                T.expectEqual("the " .. label .. " charger's reason", source.reason, "crowded")
            end
        end
        local scoop = T.stateSource(self.reads.crowded, self.scoop)
        if expect(scoop ~= nil, "the bank's status lists no scoop rotor") then
            T.expectEqual("the crowding % of the scoop rotor below the chargers' blades", scoop.crowdingPct, 0)
        end
    end,
})

-- Each charger's power curve by hand from Wind.SPEC, at a Wind Multiplier of 3: nothing at its
-- cut-in speed, an eighth of its rating halfway from there to its rated speed (half, cubed), its
-- rating at its rated speed and above, 15% more for each level it stands on up to the third (45%),
-- 70% less hemmed in, less the crowding it is given. The turbine turns aside from 55 km/h, keeping
-- 85% of its rating. Blades break only above their break speed, pipe 60, wood 70 and steel 90 km/h,
-- and 20 km/h more on the turbine; a scoop rotor's never. The chargers rank in every wind: the car
-- alternator's never makes less than the treadmill motor's, nor the turbine, furled or not, less
-- than the car alternator's, from either's cut-in up to the game's strongest wind. A neighbour
-- takes a quarter of a charger's wind right beside it, a sixth two squares away, a twelfth three,
-- none four, and a second takes its share of what the first left.
local CURVES = {
    -- kind = { watts at its rated speed at Wind Multiplier 1, cut-in km/h, rated km/h }
    scoop = { 150, 8, 45 }, timberScoop = { 150, 8, 45 },
    propeller = { 300, 10, 40 }, timberPropeller = { 300, 10, 40 },
    carAlternator = { 400, 10, 40 }, timberCarAlternator = { 400, 10, 40 },
    alternator = { 800, 9, 40 },
}
local BREAK_KPH = { pipe = 60, wood = 70, steel = 90 }

test("renewable_energy_wind_power_curve_rule", {
    sandbox = { WindMultiplier = 3 },
    validate = function()
        for kind, spec in pairs(Wind.SPEC.turbines) do
            local curve = CURVES[kind]
            if expect(curve ~= nil, kind .. " has no curve in the test") then
                local rated, cutIn, ratedKph = 3 * curve[1], curve[2], curve[3]
                local function watts(kph, z, shelter, crowding)
                    return Wind.watts(spec, kph, z or 0, shelter or 0, crowding)
                end
                T.expectEqual(kind .. "'s watts at its cut-in speed", watts(cutIn), 0)
                T.expectNear(kind .. "'s watts halfway to its rated speed", watts((cutIn + ratedKph) / 2), rated / 8, 1e-6)
                T.expectNear(kind .. "'s watts at its rated speed", watts(ratedKph), rated, 1e-6)
                T.expectNear(kind .. "'s watts a level up", watts(ratedKph, 1), rated * 1.15, 1e-6)
                T.expectNear(kind .. "'s watts three levels up", watts(ratedKph, 3), rated * 1.45, 1e-6)
                T.expectNear(kind .. "'s watts five levels up", watts(ratedKph, 5), rated * 1.45, 1e-6)
                T.expectNear(kind .. "'s watts hemmed in", watts(ratedKph, 0, 1), rated * 0.3, 1e-6)
                T.expectNear(kind .. "'s watts a quarter crowded", watts(ratedKph, 0, 0, 0.25), rated * 0.75, 1e-6)
                if spec.blades then
                    for material, breakKph in pairs(BREAK_KPH) do
                        breakKph = breakKph + (kind == "alternator" and 20 or 0)
                        expect(not Wind.canBreak(spec, material, breakKph) and Wind.canBreak(spec, material, breakKph + 1),
                            kind .. "'s " .. material .. " blades can break at " .. breakKph .. " km/h, or can't just above it")
                    end
                else
                    expect(Wind.bladesOf(kind) == nil and not Wind.canBreak(spec, Wind.bladesOf(kind), 1000), kind .. " can break")
                end
                if kind == "alternator" then
                    T.expectNear("the turbine's watts a km/h below its furl speed", watts(54), rated, 1e-6)
                    T.expectNear("the turbine's watts at its furl speed", watts(55), rated * 0.85, 1e-6)
                    T.expectNear("the turbine's watts in the strongest wind", watts(120), rated * 0.85, 1e-6)
                else
                    T.expectNear(kind .. "'s watts in the strongest wind", watts(120), rated, 1e-6)
                end
            end
        end
        local ranks = { "propeller", "carAlternator", "alternator" }
        for i = 1, #ranks - 1 do
            local lower, higher = Wind.SPEC.turbines[ranks[i]], Wind.SPEC.turbines[ranks[i + 1]]
            for kph = math.min(lower.cutInKph, higher.cutInKph), Specs.storm.fullKph do
                local low, high = Wind.watts(lower, kph, 0, 0), Wind.watts(higher, kph, 0, 0)
                expect(high >= low, string.format("at %d km/h the %s makes %g W, the %s %g W", kph, ranks[i + 1], high,
                    ranks[i], low))
            end
        end
        local crowded = { { "one beside", { 1 }, 1 / 4 }, { "one 2 squares away", { 2 }, 1 / 6 },
            { "one 3 squares away", { 3 }, 1 / 12 }, { "one 4 squares away", { 4 }, 0 },
            { "two beside", { 1, 1 }, 1 - 0.75 * 0.75 }, { "one beside and one 2 away", { 1, 2 }, 1 - 0.75 * 5 / 6 } }
        for _, case in ipairs(crowded) do
            T.expectNear("the wind " .. case[1] .. " takes", Wind.crowding(case[2]), case[3], 1e-9)
        end
    end,
})

-- This client draws each wind charger as its turning model, once the charger is added to the map
-- (OnObjectAdded, which the placePanel handler fires as placing does): one of the steps of the
-- sprite model Sprites.windModelOf names for each bladed kind's blades and facing, which
-- SpriteModels.txt must define under that name.
local DRAWN = {
    scoop = Sprites.windScoop,
    timberScoop = Sprites.windTimberScoop,
    propellerPipeE = Sprites.windCharger.propeller.pipe.E,
    propellerWoodN = Sprites.windCharger.propeller.wood.N,
    propellerSteelS = Sprites.windCharger.propeller.steel.S,
    carAlternatorWoodE = Sprites.windCharger.carAlternator.wood.E,
    carAlternatorPipeN = Sprites.windCharger.carAlternator.pipe.N,
    carAlternatorSteelW = Sprites.windCharger.carAlternator.steel.W,
    timberPropellerWoodS = Sprites.windCharger.timberPropeller.wood.S,
    timberPropellerSteelE = Sprites.windCharger.timberPropeller.steel.E,
    timberCarAlternatorPipeW = Sprites.windCharger.timberCarAlternator.pipe.W,
    timberCarAlternatorWoodN = Sprites.windCharger.timberCarAlternator.wood.N,
    turbineWoodS = Sprites.windCharger.alternator.wood.S,
    turbinePipeE = Sprites.windCharger.alternator.pipe.E,
    turbineSteelW = Sprites.windCharger.alternator.steel.W,
}

-- Whether `drawn`, a sprite model, is one of the steps of the model `sprite` is drawn as.
local function isStepOf(drawn, sprite)
    local prefix, model = Sprites.windModelOf(sprite)
    for step = 0, (model and model.steps or 0) - 1 do
        if drawn == getScriptManager():getSpriteModel(prefix .. step) then return true end
    end
    return false
end

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
        for label, sprite in pairs(DRAWN) do
            local charger = self.chargers[label]
            local model = charger and charger.object and charger.object:getSpriteModel()
            expect(model ~= nil and isStepOf(model, sprite),
                "this client doesn't draw the " .. label .. " charger as a step of its kind's model")
        end
    end,
})

-- Left unbraked through an hour of the game's strongest wind, a wooden treadmill charger's blades
-- break on a roll under the hour's chance, not on one at it, and it makes nothing; while whole in
-- that wind its status says to set the brake. At its blades' break speed or with Storm Damage off,
-- even on the lowest roll, or braked, it comes through whole. The menu offers Replace Blades,
-- greyed with no blades carried (the wear test mends blades).
test("renewable_energy_wind_propeller_breaks_in_storm_unless_braked", {
    instant = true,
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER, CONTROLLER })
        if not bank then return end
        self.left = T.panel(self, Sprites.windCharger.propeller.wood.S, { near = bank, connect = true })
        self.braked = T.panel(self, Sprites.windCharger.propeller.pipe.S, { near = bank, connect = true })
        if not (self.left and self.braked) then return end
        local gale = Specs.storm.fullKph
        T.job(self, "source", SourceJobs.BRAKE, self.braked)
        T.forceRoll(self, 0)
        T.bankPass(self, bank, 0, { windKph = 70, label = "atBreak" })
        T.step(function() T.setSandbox(self, "StormDamage", false) end)
        T.bankPass(self, bank, 0, { windKph = gale, label = "stormOff" })
        T.step(function() T.setSandbox(self, "StormDamage", true) end)
        -- An hour's chance at full strength and a Storm Damage Rate of 100 (Specs.storm): the
        -- weakest blades break once in 0.15 through 48 hours of it, wood half as often. Each list
        -- holds one roll, for the unbraked propeller: a draw for the braked one fails the pass.
        local chance = 0.5 * (1 - (1 - 0.15) ^ (1 / 48))
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
    end,
})

-- Plastic pipe blades half an hour short of their lifeHours (1500): an hour at the cut-in wind and
-- the braked charger's hours don't count; a quarter hour turning leaves them 1% left, which this
-- client's copy has for its menu's "Blades: 1% left", and the next wears them out, broken as a gale
-- breaks them, which this client's copy shows with the broken rotor's model. Replace Blades brings
-- them back to 100% and the turning model, and the charger makes its 300 W at 40 km/h again.
test("renewable_energy_wind_blades_wear_out_and_blades_mend", {
    instant = true,
    sandbox = { WindMultiplier = 1 },
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER, CONTROLLER })
        if not bank then return end
        self.charger = T.panel(self, Sprites.windCharger.propeller.pipe.S, { near = bank, connect = true })
        self.braked = T.panel(self, Sprites.windCharger.propeller.pipe.N, { near = bank, connect = true })
        if not (self.charger and self.braked) then return end
        local spec, life = Wind.SPEC.turbines.propeller, Wind.SPEC.blades.pipe.lifeHours
        T.job(self, "source", SourceJobs.BRAKE, self.braked)
        for _, charger in ipairs({ self.charger, self.braked }) do
            T.onRecord(self, bank, "setBladeHours", { source = { x = charger.x, y = charger.y, z = charger.z }, hours = life - 0.5 })
        end
        T.bankPass(self, bank, 0, { hours = 1, windKph = spec.cutInKph, label = "calm" })
        T.waitFor(self, function()
            return Wind.bladesLeftPct("pipe", Wind.bladeHours(self.charger.object)) == 1
        end, "this client's copy of the blades with 1% left")
        T.bankPass(self, bank, 0, { hours = 0.25, windKph = spec.ratedKph, label = "worn" })
        T.bankPass(self, bank, 0, { hours = 0.25, windKph = spec.ratedKph, label = "wornOut" })
        local prefix = Sprites.windModelOf(Sprites.windCharger.propeller.pipe.S)
        local brokenModel = getScriptManager():getSpriteModel(prefix .. "Broken")
        T.waitFor(self, function()
            local object = self.charger.object
            return Wind.isBroken(object) and object:getSpriteModel() == brokenModel
        end, "this client's copy of the worn-out blades, drawn broken")
        T.give(self, "blades", { { type = PIPE_BLADES } })
        T.actionJob(self, "source", self.charger, SourceJobs.REPLACE_BLADES, function() return self.items.blades[1] end)
        T.waitFor(self, function()
            local object = self.charger.object
            return not Wind.isBroken(object) and Wind.bladeHours(object) == 0
                and isStepOf(object:getSpriteModel(), Sprites.windCharger.propeller.pipe.S)
        end, "this client's copy of the new blades, drawn turning")
        T.bankPass(self, bank, 0, { hours = 0.25, windKph = spec.ratedKph, label = "mended" })
    end,
    validate = function(self)
        if not (T.expectConnected(self.charger) and T.expectConnected(self.braked)) then return end
        for label, pct in pairs({ calm = 1, worn = 1 }) do
            local source = T.stateSource(self.reads[label], self.charger)
            if expect(source ~= nil and not source.broken, label .. ", the charger is missing or broken") then
                T.expectEqual("the charger's blades left " .. label, source.bladesLeftPct, pct)
            end
        end
        local wornOut = T.stateSource(self.reads.wornOut, self.charger)
        if expect(wornOut ~= nil, "the bank's status lists no charger once worn out") then
            expect(wornOut.broken, "at its lifeHours of turning the blades are still whole")
            T.expectEqual("the worn-out charger's reason", wornOut.reason, "broken")
            T.expectEqual("the worn-out charger's watts", wornOut.watts, 0)
        end
        local braked = T.stateSource(self.reads.wornOut, self.braked)
        if expect(braked ~= nil, "the bank's status lists no braked charger") then
            expect(not braked.broken, "braked, its blades wore out")
            T.expectEqual("the braked charger's blades left", braked.bladesLeftPct, 1)
        end
        local mended = T.stateSource(self.reads.mended, self.charger)
        if expect(mended ~= nil and not mended.broken, "with new blades the charger is missing or broken") then
            T.expectEqual("the new blades left", mended.bladesLeftPct, 100)
            expectWatts("the charger with new blades", mended, 300)
        end
    end,
})

-- Blades a gale breaks while the charger's chunk is unloaded are broken in its bank's record alone;
-- loaded again, the bank's next pass shows them broken on the charger, which still makes nothing.
-- Catches a pass that takes the object's whole blades over the record's broken ones: a charger
-- making nothing that looks whole. Single player only, as the chunk reload test.
test("renewable_energy_wind_blades_broken_while_unloaded_show_once_loaded", {
    spOnly = T.CHUNK_RELOAD_SP_ONLY,
    timeoutSeconds = T.CHUNK_RELOAD_SECONDS,
    instant = true,
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER, CONTROLLER })
        self.charger = bank and T.panel(self, Sprites.windCharger.propeller.wood.S, { near = bank, connect = true })
        if not self.charger then return end
        local charger = self.charger
        T.forceRoll(self, 0)
        T.reloadChunk(self, bank, function()
            T.step(function()
                expect(getSquare(charger.x, charger.y, charger.z) == nil, "the charger's square stayed loaded during the gale")
            end)
            T.bankPass(self, bank, 0, { windKph = Specs.storm.fullKph, label = "away" })
            T.forceRoll(self, 1 - T.UNDER)
        end)
        T.bankPass(self, bank, 0, { windKph = Wind.SPEC.turbines.propeller.ratedKph, label = "back" })
        T.waitFor(self, function()
            local object = Squares.findObjectOn(getSquare(charger.x, charger.y, charger.z), Wind.isCharger)
            return object ~= nil and Wind.isBroken(object)
        end, "the reloaded charger showing its broken blades")
    end,
    validate = function(self)
        if not T.expectConnected(self.charger) then return end
        for _, label in ipairs({ "away", "back" }) do
            local source = T.stateSource(self.reads[label], self.charger)
            if expect(source ~= nil, "the bank's " .. label .. " status lists no propeller") then
                expect(source.broken, label .. ", the propeller's blades aren't broken")
                T.expectEqual("the propeller's watts " .. label, source.watts, 0)
                T.expectEqual("the propeller's reason " .. label, source.reason, "broken")
            end
        end
    end,
})

-- Input slots: a battery box's 2 free slots take a panel and a scoop rotor and refuse the
-- homebuilt turbine, which takes 3. On a rack with a controller the turbine makes its 800 W a km/h
-- below its 55 km/h furl speed, turns its head aside at it, making 85% of that (680 W), and breaks,
-- furled, in the strongest wind on a roll under its chance. With the controller worn out the
-- turbine no longer fits the slots left, but a panel connected after it still does.
test("renewable_energy_wind_alternator_slots_and_furling", {
    instant = true,
    sandbox = { StormDamage = true, StormDamageRate = 100, WindMultiplier = 1 },
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
        local function pass(label, kph, light)
            T.bankPass(self, rack, light or 0, { windKph = kph, label = label })
        end
        T.batch(function()
            pass("below furl", 54)
            pass("furled", 55)
            -- The one roll the gale draws; the passes after it are below the break speed.
            T.forceRoll(self, { 0 })
            pass("gale", Specs.storm.fullKph)
            T.bankPart(self, rack, CONTROLLER, { condition = 0, recount = true })
            pass("no controller", 54, 1000)
        end)
    end,
    validate = function(self)
        expect(self.panel.connected and self.scoop.connected, "a battery box refused a panel or the scoop rotor")
        expect(not self.refused.connected, "a battery box with its slots taken took the turbine")
        T.expectEqual("the refused turbine's reason", self.refused.reason, "Tooltip_RenewableEnergy_NoInputSlot")
        local slots = self.reads.box.status and self.reads.box.status.inputSlots
        if expect(slots ~= nil, "no state of the battery box") then
            T.expectEqual("the battery box's input slots used", slots.used, 2)
            T.expectEqual("the battery box's input slots", slots.total, 2)
        end
        if not T.expectConnected(self.alternator) then return end
        local function read(label, handle)
            local source = T.stateSource(self.reads[label], handle)
            expect(source ~= nil, "after the " .. label .. " pass the rack's status doesn't list the source")
            return source
        end
        local below, furled, gale = read("below furl", self.alternator), read("furled", self.alternator), read("gale", self.alternator)
        if below and furled then
            expect(below.reason ~= "furled", "a km/h below its furl speed it reads " .. tostring(below.reason))
            expectWatts("the turbine a km/h below its furl speed", below, 800)
            T.expectEqual("the turbine's reason at its furl speed", furled.reason, "furled")
            expectWatts("the furled turbine", furled, 680)
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
-- the first other blades its kind lists that are carried: wood before pipe for every kind, so
-- `offers` is wood on all but the pipe charger, which carries its own.
local OFFERED = {
    { label = "wooden treadmill charger", sprite = Sprites.windCharger.propeller.wood.S, offers = WOODEN_BLADES },
    { label = "steel car alternator charger", sprite = Sprites.windCharger.carAlternator.steel.S, offers = WOODEN_BLADES },
    { label = "pipe timber treadmill charger", sprite = Sprites.windCharger.timberPropeller.pipe.S, offers = PIPE_BLADES },
    { label = "steel timber car alternator charger", sprite = Sprites.windCharger.timberCarAlternator.steel.S,
        offers = WOODEN_BLADES },
    { label = "steel turbine", sprite = Sprites.windCharger.alternator.steel.S, offers = WOODEN_BLADES },
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
            if expect(T.offered(option), "on the " .. charger.label .. " Replace Blades isn't offered") then
                T.expectEqual("the blades Replace Blades takes on the " .. charger.label, option.param4:getFullType(),
                    charger.offers)
            end
        end
    end,
})

-- Replacing a broken charger's blades with another material's makes it that material's tile of
-- its kind facing the same way, its entity and model too, and its bank's record turns those
-- blades; the new blades are used and the broken old ones come back. A wooden treadmill charger
-- takes pipe blades and a steel turbine wooden ones, side by side on a bank with room for both.
local SWAPS = {
    { what = "pipe treadmill charger", from = Sprites.windCharger.propeller.wood.E, to = Sprites.windCharger.propeller.pipe.E,
        blades = PIPE_BLADES, broken = BROKEN_WOODEN_BLADES },
    { what = "wooden turbine", from = Sprites.windCharger.alternator.steel.N, to = Sprites.windCharger.alternator.wood.N,
        blades = WOODEN_BLADES, broken = "RenewableEnergy.BrokenSteelBlades" },
}

test("renewable_energy_wind_blades_swap_material", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER, CONTROLLER })
        if not bank then return end
        self.bank, self.chargers = bank, {}
        local blades, carried = {}, {}
        for i, swap in ipairs(SWAPS) do
            self.chargers[i] = T.panel(self, swap.from, { near = bank, connect = true, built = true, broken = true })
            if not self.chargers[i] then return end
            blades[i] = { type = swap.blades }
            table.insert(carried, swap.blades)
            table.insert(carried, swap.broken)
        end
        T.waitFor(self, function()
            return Wind.isBroken(self.chargers[1].object) and Wind.isBroken(self.chargers[2].object)
        end, "this client's copies of the broken blades")
        T.holdLight(self)
        T.give(self, "blades", blades)
        for i, swap in ipairs(SWAPS) do
            local charger = self.chargers[i]
            T.actionJob(self, "source", charger, SourceJobs.REPLACE_BLADES, function() return self.items.blades[i] end)
            local texture = getScriptManager():getSpriteModel(Sprites.windModelOf(swap.to) .. "0"):getTextureName()
            -- The new tile's entity, or each load of it logs "Invalid SpriteConfig object!".
            T.waitFor(self, function()
                local object = Sources.findOn(charger.square)
                local config = object and object:getSpriteConfig()
                local model = object and object:getSpriteModel()
                return object ~= nil and not Wind.isBroken(object) and Sprites.nameOf(object) == swap.to
                    and config ~= nil and config:isValid() and model ~= nil and model:getTextureName() == texture
            end, "this client's copy of the " .. swap.what .. ", its entity and its model")
        end
        T.batch(function()
            T.readCarried(self, carried)
            T.readRecord(self, bank)
        end)
    end,
    validate = function(self)
        for i, swap in ipairs(SWAPS) do
            local charger = self.chargers[i]
            if not T.expectConnected(charger) then return end
            local blades
            for _, record in ipairs(self.bank.state and self.bank.state.records or {}) do
                if Squares.samePosition(record, charger) then
                    blades = record.blades
                end
            end
            local _, _, material = Sprites.kindOf(swap.to)
            T.expectEqual("the blades in the bank's record of the " .. swap.what, blades, material)
            expect(T.carriedFirst(self, swap.blades) == nil, "the new blades of the " .. swap.what .. " stayed in the inventory")
            T.expectEqual("the " .. swap.broken .. " carried", #T.carriedItems(self, swap.broken), 1)
        end
    end,
})

-- Bladed kinds' build menu entries, each of which builds its wooden-bladed entity, and other blades
-- to build it with, with the entity those blades make of it: the entity of the tile
-- Sprites.windCharger names, since a SpriteConfig takes only its own tiles. Every bladed entry runs
-- the same OnCreate (Wind.OnCreate), so two stand for all: a mast charger, and the turbine, whose
-- blades list steel first and whose steel entity keeps its old name.
local BUILT = {
    { entry = "Base.RenewableEnergy_PropellerWood", kind = "propeller", material = "pipe",
        entity = "RenewableEnergy_PropellerPipe" },
    { entry = "Base.RenewableEnergy_TurbineWood", kind = "alternator", material = "steel",
        entity = "RenewableEnergy_AlternatorWindCharger" },
}

-- The build menu's own path builds the bladed kind of `design` from its one entry with its
-- material's blades, and the charger's OnCreate fits the blades the build took: it stands on its
-- kind's tile of those blades, facing the way it was built, as that tile's entity, whose
-- SpriteConfig takes it. The entity is named, not inferred from a valid SpriteConfig: the config
-- finds its tile once, as it is added, so a tile swapped under the old entity still reads valid.
-- One build a test, as each built charger stands in the way of the next one's walk.
local function buildsCharger(design)
    local material = design.material
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
            T.expectEqual("the " .. what .. " charger's entity", self.built, design.entity)
            expect(self.configValid, "the " .. what .. " charger's SpriteConfig refused its tile")
        end,
    }
end

for _, design in ipairs(BUILT) do
    test("renewable_energy_wind_build_menu_fits_" .. design.material .. "_blades_" .. design.kind, buildsCharger(design))
end
