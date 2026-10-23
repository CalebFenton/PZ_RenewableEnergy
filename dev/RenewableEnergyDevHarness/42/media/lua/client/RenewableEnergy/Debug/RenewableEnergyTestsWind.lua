require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Wind chargers (Wind.lua, PowerBank/WindSource.lua, client Wind/*): a bank source on the game's
-- wind, with its power curve, brake, storm breakage, blades and model.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect
local Specs, Sprites, Wind = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Wind
local sourceAt = T.stateSource

local CAR_BATTERY = "Base.CarBattery1"
local INVERTER = "RenewableEnergy.PlugInInverter"
local CONTROLLER = "RenewableEnergy.ChargeController"
local WOODEN_BLADES = "RenewableEnergy.WoodenBlades"

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

-- Solid walls built around a wind charger shelter it like trees and buildings do: a ring of
-- player walls raises its shelter and cuts its output.
local WALL = "walls_exterior_wooden_01_24"

test("renewable_energy_wind_walls_shelter", {
    run = function(self)
        local bank, rotor = scoopOnBank(self)
        if not bank then return end
        self.passes = {}
        local rated = Specs.wind.turbines.scoop.ratedKph
        local function pass(label)
            T.bankPass(self, bank, 0, { windKph = rated })
            T.step(function() self.passes[label] = sourceAt(bank.state, rotor.position) end)
        end
        pass("open")
        -- In a step, so the walls go up after the open pass: placeTile acts when it is called.
        T.step(function()
            local p = rotor.position
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local square = getSquare(p.x + dx, p.y + dy, p.z)
                    if (dx ~= 0 or dy ~= 0) and square then
                        T.placeTile(self, square, WALL)
                    end
                end
            end
        end)
        pass("walled")
    end,
    validate = function(self)
        if not T.expectConnected(self.rotor) then return end
        local open, walled = self.passes.open, self.passes.walled
        if not expect(open ~= nil and walled ~= nil, "the bank's status lists no scoop rotor") then return end
        expect(walled.shelterPct > open.shelterPct,
            "walls around it left its shelter at " .. walled.shelterPct .. "% (open: " .. open.shelterPct .. "%)")
        expect(walled.watts < open.watts,
            "walled in it made " .. walled.watts .. " W, open " .. open.watts .. " W")
    end,
})

-- Each charger's power curve: nothing at its cut-in speed, the cube of the wind on the way up,
-- its rating at its rated speed, more for standing higher only up to the height cap; the
-- alternator furls from its furl speed, and only the propeller and the alternator break, from
-- their break speed.
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
            if spec.breakKph then
                expect(not Wind.canBreak(spec, spec.breakKph - 1) and Wind.canBreak(spec, spec.breakKph),
                    kind .. " doesn't break from exactly its break speed")
            else
                expect(not Wind.canBreak(spec, 1000), kind .. " can break")
            end
        end
    end,
})

-- This client draws each wind charger as its turning model, once the charger is added to the map
-- (OnObjectAdded, which the placePanel handler fires as placing does): the propeller's by its
-- blades and facing, the alternator's by its facing.
local DRAWN = {
    scoop = Sprites.windScoop,
    propellerPipeE = Sprites.windPropeller.pipe.E,
    propellerWoodN = Sprites.windPropeller.wood.N,
    alternatorW = Sprites.windAlternator.W,
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
            expect(object ~= nil and object:getSpriteModel() ~= nil, "the " .. label .. " charger has no sprite model on this client")
        end
    end,
})

-- Left unbraked through an hour of its break speed, a propeller's blades break on a roll under
-- the hour's chance, not on one at it, and it makes nothing until a spare set goes on. A km/h
-- below its break speed or with Storm Damage off, even on the lowest roll, or braked, it comes
-- through whole. The menu offers Replace Blades, greyed until the character carries blades that
-- fit.
test("renewable_energy_wind_propeller_breaks_in_storm_and_blades_mend", {
    instant = true,
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { CAR_BATTERY, INVERTER, CONTROLLER })
        if not bank then return end
        self.left = T.panel(self, Sprites.windPropeller.wood.S, { near = bank, connect = true })
        self.braked = T.panel(self, Sprites.windPropeller.pipe.S, { near = bank, connect = true })
        if not (self.left and self.braked) then return end
        local spec = Specs.wind.turbines.propeller
        T.perform(self, "setBrake", { source = self.braked.position, braked = true })
        T.forceRoll(self, 0)
        T.bankPass(self, bank, 0, { windKph = spec.breakKph - 1 })
        T.step(function()
            self.belowBreak = bank.state
            T.setSandbox(self, "StormDamage", false)
        end)
        T.bankPass(self, bank, 0, { windKph = spec.breakKph })
        T.step(function()
            self.stormOff = bank.state
            T.setSandbox(self, "StormDamage", true)
        end)
        -- An hour's chance at a Storm Damage Rate of 100 is the spec's breakPerHour. Each list
        -- holds one roll, for the unbraked propeller: a draw for the braked one fails the pass.
        T.batch(function()
            T.forceRoll(self, { spec.breakPerHour })
            T.bankPass(self, bank, 0, { windKph = spec.breakKph })
            T.step(function() self.atChance = bank.state end)
            T.forceRoll(self, { spec.breakPerHour - 1e-9 })
            T.bankPass(self, bank, 0, { windKph = spec.breakKph })
            T.step(function() self.storm = bank.state end)
            -- Every later roll misses, so whatever else draws one while the test goes on neither
            -- runs past the list nor comes up.
            T.forceRoll(self, 1 - 1e-9)
        end)
        T.waitFor(self, function() return Wind.isBroken(self.left.object) end, "this client's copy of the broken blades")
        T.step(function()
            local menu, context = T.worldSubmenu(self.left.object, RenewableEnergy.Menu.nameOf(self.left.object))
            local option = T.optionNamed(menu, getText("ContextMenu_RenewableEnergy_ReplaceBlades"))
            self.emptyHanded = option ~= nil and option.notAvailable == true
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
        for key, what in pairs({ belowBreak = "a km/h below its break speed", stormOff = "with Storm Damage off",
            atChance = "on a roll at the hour's chance" }) do
            local whole = sourceAt(self[key], self.left.position)
            if expect(whole ~= nil, "the bank's status lists no propeller") then
                expect(not whole.broken, what .. " it broke")
            end
        end
        local left, braked = sourceAt(self.storm, self.left.position), sourceAt(self.storm, self.braked.position)
        if not expect(left and braked, "after the storm the bank's status lists no propellers") then return end
        expect(left.broken and left.watts == 0 and left.reason == "broken",
            "unbraked, a roll under the chance left it broken " .. tostring(left.broken) .. ", " .. left.watts .. " W, "
            .. tostring(left.reason))
        expect(not braked.broken, "the braked propeller broke")
        expect(self.emptyHanded == true, "with no blades carried, Replace Blades isn't offered greyed out")
        expect(T.carriedFirst(self, WOODEN_BLADES) == nil, "replacing the blades left them in the inventory")
        local mended = sourceAt(self.mended, self.left.position)
        expect(mended ~= nil and not mended.broken and mended.watts > 0, "with new blades it still makes nothing")
    end,
})

-- Input slots: a battery box's free slots take a panel and a scoop rotor and refuse the homemade
-- alternator, which takes more. On a rack with a controller the alternator makes its curve's
-- watts a km/h below its furl speed, turns out of the wind at it, making its furled share, and
-- breaks, furled, at its break speed on a roll under its chance. With the controller worn out the
-- alternator no longer fits the slots left, but a panel connected after it still does.
test("renewable_energy_wind_alternator_slots_and_furling", {
    instant = true,
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local box = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        if not box then return end
        T.batch(function()
            self.panel = T.panel(self, Sprites.flat, { near = box, connect = true })
            self.scoop = T.panel(self, Sprites.windScoop, { near = box, connect = true })
            self.refused = T.panel(self, Sprites.windAlternator.N, { near = box, connect = true })
            T.bankState(self, box)
            T.step(function() self.box = box.state end)
        end)
        local rack = T.bank(self, "batteryRackWood", { CAR_BATTERY, INVERTER, CONTROLLER })
        if not rack then return end
        T.batch(function()
            self.alternator = T.panel(self, Sprites.windAlternator.E, { near = rack, connect = true })
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
            pass("gale", spec.breakKph)
            T.setPartCondition(self, rack, CONTROLLER, 0, true)
            pass("no controller", spec.furlKph - 1, 1000)
        end)
    end,
    validate = function(self)
        expect(self.panel.connected and self.scoop.connected, "a battery box refused a panel or the scoop rotor")
        expect(not self.refused.connected and self.refused.reason == "Tooltip_RenewableEnergy_NoInputSlot",
            "a battery box with its slots taken took the alternator: " .. tostring(self.refused.reason))
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
            T.expectNear("furled share of the rating", furled.watts / Wind.watts(spec, spec.ratedKph, furled.z, furled.shelterPct / 100),
                spec.furledShare, 0.01)
        end
        if gale then
            expect(gale.broken and gale.watts == 0, "furled at its break speed it didn't break")
        end
        local alternator, panel = read("no controller", self.alternator), read("no controller", self.after)
        if alternator and panel then
            expect(alternator.reason == "noController", "without the controller the alternator reads " .. tostring(alternator.reason))
            expect(panel.reason ~= "noController" and panel.watts > 0,
                "a panel after the alternator lost its slot too: " .. panel.watts .. " W, " .. tostring(panel.reason))
        end
    end,
})
