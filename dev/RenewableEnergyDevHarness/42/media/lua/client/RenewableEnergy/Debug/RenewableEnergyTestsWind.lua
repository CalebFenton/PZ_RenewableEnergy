require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Wind chargers (Wind.lua, PowerBank/WindSource.lua, client Wind/*): a bank source on the game's
-- wind, with its power curve, brake, storm breakage, blades and model.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect
local PowerBank, Specs, Sprites, Wind = RenewableEnergy.PowerBank, RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Wind
local sourceAt = T.stateSource

local CAR_BATTERY = "Base.CarBattery1"
local INVERTER = "RenewableEnergy.PlugInInverter"
local CONTROLLER = "RenewableEnergy.ChargeController"
local WOODEN_BLADES = "RenewableEnergy.WoodenBlades"
local PIPE_BLADES = "RenewableEnergy.PipeBlades"
local BROKEN_WOODEN_BLADES = "RenewableEnergy.BrokenWoodenBlades"

-- A battery box and a scoop rotor connected to it, the rotor's handle also in self.rotor; nil
-- when either is missing.
local function scoopOnBank(self)
    local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
    self.rotor = bank and T.panel(self, Sprites.windScoop, { near = bank, connect = true })
    if not self.rotor then return nil end
    return bank, self.rotor
end

-- A scoop rotor wired to a bank makes power once the wind is past its cut-in speed, none at it or
-- with its brake on, and the status says why.
test("renewable_energy_wind_scoop_cut_in_and_brake", {
    run = function(self)
        local bank, rotor = scoopOnBank(self)
        if not bank then return end
        self.passes = {}
        local spec = Specs.wind.turbines.scoop
        local function pass(label, kph)
            T.bankPass(self, bank, 0, { windKph = kph })
            T.step(function() self.passes[label] = sourceAt(bank.state, rotor.position) end)
        end
        T.batch(function()
            pass("windy", spec.ratedKph)
            T.step(function() self.windyBankW = bank.state.status.windW end)
            pass("cut-in", spec.cutInKph)
            pass("past cut-in", spec.cutInKph + 1)
            T.perform(self, "setBrake", { source = rotor.position, braked = true })
            pass("braked", spec.ratedKph)
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.rotor) then return end
        local function read(label)
            local source = self.passes[label]
            expect(source ~= nil, "after the " .. label .. " pass the bank's status lists no scoop rotor")
            return source
        end
        local windy = read("windy")
        if windy then
            expect(windy.watts > 0, "the scoop rotor made nothing at its rated speed")
            T.expectNear("the bank's wind watts", self.windyBankW, windy.watts, 0.01)
        end
        local calm = read("cut-in")
        if calm then
            expect(calm.watts == 0 and calm.reason == "calm",
                "at its cut-in speed it made " .. calm.watts .. " W, reason " .. tostring(calm.reason))
        end
        local turning = read("past cut-in")
        if turning then
            expect(turning.watts > 0, "a km/h past its cut-in speed it made nothing")
        end
        local braked = read("braked")
        if braked then
            expect(braked.watts == 0 and braked.reason == "braked",
                "braked it made " .. braked.watts .. " W, reason " .. tostring(braked.reason))
        end
    end,
})

-- Ringing the charger `handle` with `sprite` tiles on `level` (the ringOfTiles handler).
local function ring(self, handle, level, sprite)
    local p = handle.position
    T.server(self, "ringOfTiles", { x = p.x, y = p.y, level = level, sprite = sprite })
end

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
        self.passes = {}
        local function pass(label)
            T.bankPass(self, bank, 0, { windKph = Specs.wind.turbines.scoop.ratedKph })
            T.step(function() self.passes[label] = sourceAt(bank.state, rotor.position) end)
        end
        local level = rotor.position.z
        T.batch(function()
            pass("open")
            ring(self, rotor, level, LOW_WALL)
            ring(self, rotor, level, TALL_FENCE)
            pass("fenced")
            ring(self, rotor, level, WALL)
            pass("walled")
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.rotor) then return end
        local open, fenced, walled = self.passes.open, self.passes.fenced, self.passes.walled
        if not expect(open and fenced and walled, "the bank's status lists no scoop rotor") then return end
        expect(fenced.shelterPct == open.shelterPct,
            "fences around it took its shelter from " .. open.shelterPct .. "% to " .. fenced.shelterPct .. "%")
        expect(walled.shelterPct > open.shelterPct and walled.watts < open.watts, string.format(
            "walls around it left it at %d%% shelter, %g W (open: %d%%, %g W)",
            walled.shelterPct, walled.watts, open.shelterPct, open.watts))
    end,
})

-- A treadmill charger's blades turn a level above its foot (Specs.wind.turbines rotorAbove), and
-- its shelter is counted there: walls around its foot leave it in the open, walls on the level
-- above shelter it.
test("renewable_energy_wind_mast_sheltered_only_at_its_blades", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        self.mast = bank and T.panel(self, Sprites.windCharger.propeller.wood.S, { near = bank, connect = true })
        if not self.mast then return end
        self.passes = {}
        local function pass(label)
            T.bankPass(self, bank, 0, { windKph = Specs.wind.turbines.propeller.ratedKph })
            T.step(function() self.passes[label] = sourceAt(bank.state, self.mast.position) end)
        end
        local foot = self.mast.position.z
        T.batch(function()
            pass("open")
            ring(self, self.mast, foot, WALL)
            pass("foot")
            ring(self, self.mast, foot + 1, WALL)
            pass("blades")
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.mast) then return end
        local open, foot, blades = self.passes.open, self.passes.foot, self.passes.blades
        if not expect(open and foot and blades, "the bank's status lists no treadmill charger") then return end
        expect(foot.shelterPct == open.shelterPct,
            "walls around its foot took its shelter from " .. open.shelterPct .. "% to " .. foot.shelterPct .. "%")
        expect(blades.shelterPct > open.shelterPct and blades.watts < open.watts, string.format(
            "walls at its blades left it at %d%% shelter, %g W (open: %d%%, %g W)",
            blades.shelterPct, blades.watts, open.shelterPct, open.watts))
    end,
})

-- Two treadmill chargers two squares apart take wind from each other, each its crowdShare of the
-- distance (Specs.wind.crowdRadius, crowdLoss), which costs enough for the status to say so; a
-- scoop rotor right beside one turns a level below its blades and takes nothing, nor loses any.
test("renewable_energy_wind_chargers_close_together_crowd_each_other", {
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { CAR_BATTERY, INVERTER, CONTROLLER })
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
            T.bankPass(self, bank, 0, { windKph = Specs.wind.turbines.propeller.ratedKph })
            T.step(function() self.state = bank.state end)
        end)
    end,
    validate = function(self)
        for _, handle in ipairs({ self.first, self.second, self.scoop }) do
            if not T.expectConnected(handle) then return end
        end
        local spec = Specs.wind.turbines.propeller
        local wanted = Wind.crowding({ self.distance })
        for label, handle in pairs({ first = self.first, second = self.second }) do
            local source = sourceAt(self.state, handle.position)
            if expect(source ~= nil, "the bank's status lists no " .. label .. " treadmill charger") then
                expect(source.crowdingPct == math.floor(100 * wanted + 0.5), string.format(
                    "the %s charger, %g squares from the other, loses %d%% to it, not %.0f%%", label, self.distance,
                    source.crowdingPct, 100 * wanted))
                T.expectNear("the " .. label .. " charger's watts", source.watts,
                    Wind.watts(spec, spec.ratedKph, source.z, source.shelterPct / 100, wanted), spec.watts * 0.01)
                expect(source.reason == "crowded", "the " .. label .. " charger reads " .. tostring(source.reason))
            end
        end
        local scoop = sourceAt(self.state, self.scoop.position)
        if expect(scoop ~= nil, "the bank's status lists no scoop rotor") then
            expect(scoop.crowdingPct == 0, "the scoop rotor below the chargers' blades loses " .. scoop.crowdingPct .. "% to them")
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
        local wind = Specs.wind
        for kind, spec in pairs(wind.turbines) do
            local function watts(kph, z)
                return Wind.watts(spec, kph, z or 0, 0)
            end
            expect(watts(spec.cutInKph) == 0, kind .. " makes power at its cut-in speed")
            local midway = (spec.cutInKph + spec.ratedKph) / 2
            if not Wind.furled(spec, midway) then
                T.expectNear(kind .. " halfway to its rated speed, as an eighth of its rating",
                    watts(midway), spec.watts / 8, 0.001)
            end
            expect(watts(spec.ratedKph) == spec.watts, kind .. " makes " .. watts(spec.ratedKph) .. " W at its rated speed")
            if not spec.furlKph then
                expect(watts(spec.ratedKph * 2) == spec.watts, kind .. " makes more than its rating above its rated speed")
            end
            local top = wind.maxBonusLevel
            expect(watts(spec.ratedKph, top) > watts(spec.ratedKph, 0), kind .. " makes no more standing higher")
            expect(watts(spec.ratedKph, top + 2) == watts(spec.ratedKph, top), kind .. " gains above the height cap")
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
        local bank = T.bank(self, "batteryRackWood", { CAR_BATTERY, INVERTER, CONTROLLER })
        if not bank then return end
        self.left = T.panel(self, Sprites.windCharger.propeller.wood.S, { near = bank, connect = true })
        self.braked = T.panel(self, Sprites.windCharger.propeller.pipe.S, { near = bank, connect = true })
        if not (self.left and self.braked) then return end
        local spec, blades = Specs.wind.turbines.propeller, Specs.wind.blades.wood
        local gale = Specs.storm.fullKph
        T.perform(self, "setBrake", { source = self.braked.position, braked = true })
        T.forceRoll(self, 0)
        T.bankPass(self, bank, 0, { windKph = blades.breakKph })
        T.step(function()
            self.atBreak = bank.state
            T.setSandbox(self, "StormDamage", false)
        end)
        T.bankPass(self, bank, 0, { windKph = gale })
        T.step(function()
            self.stormOff = bank.state
            T.setSandbox(self, "StormDamage", true)
        end)
        -- An hour's chance at full strength and a Storm Damage Rate of 100. Each list holds one
        -- roll, for the unbraked propeller: a draw for the braked one fails the pass.
        local chance = RenewableEnergy.Chance.stormDamage(RenewableEnergy.Chance.stormPerHour(blades.stormShare), 1)
        T.batch(function()
            T.forceRoll(self, { chance })
            T.bankPass(self, bank, 0, { windKph = gale })
            T.step(function() self.atChance = bank.state end)
            T.forceRoll(self, { chance - 1e-9 })
            T.bankPass(self, bank, 0, { windKph = gale })
            T.step(function() self.storm = bank.state end)
            -- Every later roll misses, so whatever else draws one while the test goes on neither
            -- runs past the list nor comes up.
            T.forceRoll(self, 1 - 1e-9)
        end)
        T.waitFor(self, function() return Wind.isBroken(self.left.object) end, "this client's copy of the broken blades")
        T.step(function()
            local menu, context = T.worldSubmenu(self.left.object, RenewableEnergy.Menu.nameOf(self.left.object))
            self.emptyHanded = T.optionState(T.optionNamed(menu, getText("ContextMenu_RenewableEnergy_ReplaceBlades"))).greyed
            if context then context:hideAndChildren() end
        end)
        T.give(self, "blades", { { type = WOODEN_BLADES } })
        T.doJob(self, self.left.square, function()
            return RenewableEnergyAction:new(T.player(), RenewableEnergyAction.REPLACE_BLADES, self.left.object,
                nil, nil, self.items.blades[1])
        end)
        T.waitFor(self, function() return not Wind.isBroken(self.left.object) end, "this client's copy of the new blades")
        T.batch(function()
            T.readCarried(self, { WOODEN_BLADES })
            T.bankPass(self, bank, 0, { windKph = spec.ratedKph })
            T.step(function() self.mended = bank.state end)
        end)
    end,
    validate = function(self)
        if not (T.expectConnected(self.left) and T.expectConnected(self.braked)) then return end
        for key, what in pairs({ atBreak = "at its blades' break speed", stormOff = "with Storm Damage off",
            atChance = "on a roll at the hour's chance" }) do
            local whole = sourceAt(self[key], self.left.position)
            if expect(whole ~= nil, "the bank's status lists no propeller") then
                expect(not whole.broken, what .. " it broke")
            end
        end
        local whole = sourceAt(self.atChance, self.left.position)
        if whole then
            expect(whole.reason == "gale", "whole in the strongest wind it reads " .. tostring(whole.reason))
        end
        local left, braked = sourceAt(self.storm, self.left.position), sourceAt(self.storm, self.braked.position)
        if not expect(left and braked, "after the storm the bank's status lists no propellers") then return end
        expect(left.broken and left.watts == 0 and left.reason == "broken",
            "unbraked, a roll under the chance left it broken " .. tostring(left.broken) .. ", " .. left.watts .. " W, "
            .. tostring(left.reason))
        expect(not braked.broken and braked.reason == "braked",
            "the braked propeller broke or reads " .. tostring(braked.reason))
        expect(self.emptyHanded == true, "with no blades carried, Replace Blades isn't offered greyed out")
        expect(T.carriedFirst(self, WOODEN_BLADES) == nil, "replacing the blades left them in the inventory")
        local mended = sourceAt(self.mended, self.left.position)
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
        local box = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        if not box then return end
        T.batch(function()
            self.panel = T.panel(self, Sprites.flat, { near = box, connect = true })
            self.scoop = T.panel(self, Sprites.windScoop, { near = box, connect = true })
            self.refused = T.panel(self, Sprites.windCharger.alternator.steel.N, { near = box, connect = true })
            T.bankState(self, box)
            T.step(function() self.box = box.state end)
        end)
        local rack = T.bank(self, "batteryRackWood", { CAR_BATTERY, INVERTER, CONTROLLER })
        if not rack then return end
        T.batch(function()
            self.alternator = T.panel(self, Sprites.windCharger.alternator.steel.E, { near = rack, connect = true })
            self.after = T.panel(self, Sprites.flat, { near = rack, connect = true })
        end)
        if not (self.panel and self.scoop and self.refused and self.alternator and self.after) then return end
        local spec = Specs.wind.turbines.alternator
        self.passes = {}
        local function pass(label, kph, light)
            T.bankPass(self, rack, light or 0, { windKph = kph })
            T.step(function() self.passes[label] = rack.state end)
        end
        T.batch(function()
            pass("below furl", spec.furlKph - 1)
            pass("furled", spec.furlKph)
            -- The one roll the gale draws; the passes after it are below the break speed.
            T.forceRoll(self, { 0 })
            pass("gale", Specs.storm.fullKph)
            T.setPartCondition(self, rack, CONTROLLER, 0, true)
            pass("no controller", spec.furlKph - 1, 1000)
        end)
    end,
    validate = function(self)
        expect(self.panel.connected and self.scoop.connected, "a battery box refused a panel or the scoop rotor")
        expect(not self.refused.connected and self.refused.reason == "Tooltip_RenewableEnergy_NoInputSlot",
            "a battery box with its slots taken took the turbine: " .. tostring(self.refused.reason))
        local slots = self.box and self.box.status and self.box.status.inputSlots
        if expect(slots ~= nil, "no state of the battery box") then
            expect(slots.used == 2 and slots.total == Specs.freeSlots, "input slots read " .. slots.used .. " of " .. slots.total)
        end
        if not T.expectConnected(self.alternator) then return end
        local function read(label, handle)
            local source = sourceAt(self.passes[label], handle.position)
            expect(source ~= nil, "after the " .. label .. " pass the rack's status doesn't list the source")
            return source
        end
        local spec = Specs.wind.turbines.alternator
        local below, furled, gale = read("below furl", self.alternator), read("furled", self.alternator), read("gale", self.alternator)
        if below and furled then
            expect(below.reason ~= "furled" and below.watts > furled.watts,
                "a km/h below its furl speed it reads " .. tostring(below.reason) .. ", " .. below.watts .. " W")
            expect(furled.reason == "furled", "at its furl speed it reads " .. tostring(furled.reason))
            T.expectNear("furled share of the rating", furled.watts / Wind.watts(spec, spec.ratedKph, furled.z,
                furled.shelterPct / 100, furled.crowdingPct / 100), spec.furledShare, 0.01)
        end
        if gale then
            expect(gale.broken and gale.watts == 0, "furled in the strongest wind it didn't break")
        end
        local alternator, panel = read("no controller", self.alternator), read("no controller", self.after)
        if alternator and panel then
            expect(alternator.reason == "noController", "without the controller the turbine reads " .. tostring(alternator.reason))
            expect(panel.reason ~= "noController" and panel.watts > 0,
                "a panel after the turbine lost its slot too: " .. panel.watts .. " W, " .. tostring(panel.reason))
        end
    end,
})

-- Every bladed charger takes any blades (Specs.wind.turbines blades): a broken one takes wooden
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
                modData[Wind.BROKEN] = true
                T.defer(self, function() modData[Wind.BROKEN] = nil end)
            end
        end)
    end,
    validate = function(self)
        local pipe, wood = self.items.blades[1], self.items.blades[2]
        local carried = { wood = wood, pipe = pipe }
        for i, charger in ipairs(OFFERED) do
            local object = self.chargers[i].object
            for material, blades in pairs(carried) do
                local refusal = Wind.bladesRefusal(object, blades)
                expect(refusal == nil, material .. " blades on the " .. charger.label .. " are refused for " .. tostring(refusal))
            end
            local menu, context = T.worldSubmenu(object, RenewableEnergy.Menu.nameOf(object))
            local option = T.optionNamed(menu, getText("ContextMenu_RenewableEnergy_ReplaceBlades"))
            if context then context:hideAndChildren() end
            local kind, _, own = Sprites.kindOf(charger.sprite)
            local wanted = carried[own]
            for _, material in ipairs(Specs.wind.turbines[kind].blades) do
                wanted = wanted or carried[material]
            end
            expect(option ~= nil and not option.notAvailable and option.param2 ~= nil and option.param2:getID() == wanted:getID(),
                "on the " .. charger.label .. " Replace Blades isn't offered with the " .. wanted:getFullType() .. ": "
                .. tostring(option and option.param2 and option.param2:getFullType()))
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
            T.doJob(self, self.charger.square, function()
                return RenewableEnergyAction:new(T.player(), RenewableEnergyAction.REPLACE_BLADES, self.charger.object,
                    nil, nil, self.items.blades[1])
            end)
            self.texture = getScriptManager():getSpriteModel(Sprites.windModelOf(to) .. "0"):getTextureName()
            -- The new tile's entity, or each load of it logs "Invalid SpriteConfig object!".
            T.waitFor(self, function()
                local object = RenewableEnergy.Sources.on(self.charger.square)
                local config = object and object:getSpriteConfig()
                local model = object and object:getSpriteModel()
                self.object = object
                return object ~= nil and not Wind.isBroken(object) and Sprites.nameOf(object) == to
                    and config ~= nil and config:isValid() and model ~= nil and model:getTextureName() == self.texture
            end, "this client's copy of the " .. what .. ", its entity and its model")
            T.batch(function()
                T.readCarried(self, { newBlades, brokenBlades })
                T.bankState(self, self.bank)
            end)
        end,
        validate = function(self)
            if not T.expectConnected(self.charger) then return end
            local blades
            for _, record in ipairs(self.bank.state and self.bank.state.records or {}) do
                if PowerBank.samePosition(record, self.charger.position) then
                    blades = record.blades
                end
            end
            local _, _, material = Sprites.kindOf(to)
            expect(blades == material, "the bank's record of the " .. what .. " has " .. tostring(blades) .. " blades")
            expect(T.carriedFirst(self, newBlades) == nil, "the new blades stayed in the inventory")
            expect(#T.carriedItems(self, brokenBlades) == 1,
                "the inventory holds " .. #T.carriedItems(self, brokenBlades) .. " " .. brokenBlades .. ", not 1")
        end,
    })
end

swapTest("renewable_energy_wind_blades_swap_material", "pipe treadmill charger",
    { kind = "batteryBoxWood", parts = { CAR_BATTERY, INVERTER } },
    Sprites.windCharger.propeller.wood.E, Sprites.windCharger.propeller.pipe.E, PIPE_BLADES, BROKEN_WOODEN_BLADES)
swapTest("renewable_energy_wind_turbine_blades_swap_material", "wooden turbine",
    { kind = "batteryRackWood", parts = { CAR_BATTERY, INVERTER, CONTROLLER } },
    Sprites.windCharger.alternator.steel.N, Sprites.windCharger.alternator.wood.N, WOODEN_BLADES, "RenewableEnergy.BrokenSteelBlades")

-- A charger losing more than SHELTERED_LOSS (30%) of its unsheltered watts to shelter gives
-- "sheltered" as its reason, and one losing less gives none: a ring of walls beside it costs about
-- 6%, walls filling the squares out to 5 about 43% (WindSource's shelter weights, worked by hand).
test("renewable_energy_wind_sheltered_reason", {
    run = function(self)
        local bank, rotor = scoopOnBank(self)
        if not bank then return end
        self.passes = {}
        local rated = Specs.wind.turbines.scoop.ratedKph
        local function wallsOut(from, to)
            T.step(function()
                local p = rotor.position
                T.batch(function()
                    for dx = -5, 5 do
                        for dy = -5, 5 do
                            local distance = math.sqrt(dx * dx + dy * dy)
                            local square = getSquare(p.x + dx, p.y + dy, p.z)
                            if distance > from and distance <= to and square then
                                T.placeTile(self, square, WALL)
                            end
                        end
                    end
                end)
            end)
        end
        local function pass(label)
            T.bankPass(self, bank, 0, { windKph = rated })
            T.step(function() self.passes[label] = sourceAt(bank.state, rotor.position) end)
        end
        wallsOut(0, 1.5)
        pass("ring")
        wallsOut(1.5, 5)
        pass("walled")
    end,
    validate = function(self)
        if not T.expectConnected(self.rotor) then return end
        local spec = Specs.wind.turbines.scoop
        for _, label in ipairs({ "ring", "walled" }) do
            local source = self.passes[label]
            if not expect(source ~= nil, "after the " .. label .. " pass the bank's status lists no scoop rotor") then return end
            local loss = 1 - source.watts / Wind.watts(spec, spec.ratedKph, source.z, 0)
            expect((source.reason == "sheltered") == (loss > 0.3), string.format(
                "%s, losing %.0f%% of its watts to shelter, it reads %s", label, 100 * loss, tostring(source.reason)))
        end
        local walled = self.passes.walled
        expect(walled.reason == "sheltered", "walled in out to 5 squares it reads " .. tostring(walled.reason))
    end,
})

-- Two speakers make the alternator, or four portable radios of one kind or both, and the craft
-- takes them all. An input whose items take different amounts has a base amount of 1
-- (InputScript.Load), which is all T.recipeInputs gives of the preferred item; setup gives the rest.
local ALTERNATOR_RECIPE = "RenewableEnergy_MakeHomemadeAlternator"
local SPEAKER, RED_RADIO, BLACK_RADIO = "Base.Speaker", "Base.RadioRed", "Base.RadioBlack"
local MAGNET_ROWS = {
    { "from_speakers", SPEAKER, { { type = SPEAKER, count = 1 } } },
    { "from_four_radios", RED_RADIO, { { type = RED_RADIO, count = 3 } } },
    { "from_mixed_radios", RED_RADIO, { { type = RED_RADIO, count = 1 }, { type = BLACK_RADIO, count = 2 } } },
}
for _, row in ipairs(MAGNET_ROWS) do
    local behavior, first, rest = row[1], row[2], row[3]
    T.craftTest(T.craftName("wind", ALTERNATOR_RECIPE, behavior), {
        recipe = ALTERNATOR_RECIPE,
        from = first,
        prefer = { first },
        setup = function(self) T.giveBeforeCalls(self, "magnets", rest) end,
        counts = { ["RenewableEnergy.HomemadeAlternator"] = 1, [SPEAKER] = 0, [RED_RADIO] = 0, [BLACK_RADIO] = 0 },
    })
end
