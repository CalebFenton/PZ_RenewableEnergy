require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Wind chargers: a source of the bank like a panel, on the game's wind.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect
local Specs, Sprites, Wind = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Wind

local CAR_BATTERY = "Base.CarBattery1"
local INVERTER = "RenewableEnergy.PlugInInverter"

local function sourceOf(state, kind)
    for _, source in ipairs(state and state.status and state.status.sources or {}) do
        if source.kind == kind then
            return source
        end
    end
    return nil
end

-- A scoop rotor wired to a bank makes power in the wind by its power curve and shelter, none in a
-- calm or with its brake on, and the status says why.
test("renewable_energy_wind_scoop_feeds_bank", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        if not bank then return end
        self.bank = bank
        local rotor = T.panel(self, Sprites.windScoop, { near = bank, connect = true })
        if not rotor then return end
        self.rotor = rotor
        local function pass(label, kph)
            T.bankPass(self, bank, 0, { windKph = kph })
            T.step(function() self[label] = bank.state end)
        end
        pass("windy", 30)
        pass("calm", Specs.wind.turbines.scoop.cutInKph - 1)
        T.server(self, "perform", function()
            return { command = "setBrake", args = { source = rotor.position, braked = true } }
        end)
        pass("braked", 30)
    end,
    validate = function(self)
        expect(self.rotor.connected, "the bank refused the scoop rotor: " .. tostring(self.rotor.reason))
        local windy = sourceOf(self.windy, "scoop")
        if not expect(windy ~= nil, "the bank's status lists no scoop rotor") then return end
        local expected = Wind.watts(Specs.wind.turbines.scoop, 30, windy.z, windy.shelterPct / 100)
        T.expectNear("scoop rotor watts in a 30 km/h wind", windy.watts, expected, 2)
        expect(windy.watts > 0, "the scoop rotor made nothing in a 30 km/h wind")
        T.expectNear("the bank's wind watts", self.windy.status.windW, windy.watts, 0.01)
        local calm = sourceOf(self.calm, "scoop")
        expect(calm.watts == 0 and calm.reason == "calm", "in a calm it made " .. calm.watts .. " W, reason " .. tostring(calm.reason))
        local braked = sourceOf(self.braked, "scoop")
        expect(braked.watts == 0 and braked.reason == "braked", "braked it made " .. braked.watts .. " W, reason " .. tostring(braked.reason))
    end,
})

-- A wind charger takes its input slots like a panel: a battery box's two free slots take one panel
-- and one scoop rotor, and refuse a third source.
test("renewable_energy_wind_takes_input_slots", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        if not bank then return end
        self.panel = T.panel(self, Sprites.flat, { near = bank, connect = true })
        self.rotor = T.panel(self, Sprites.windScoop, { near = bank, connect = true })
        self.third = T.panel(self, Sprites.flat, { near = bank, connect = true })
        T.bankState(self, bank)
        T.step(function() self.state = bank.state end)
    end,
    validate = function(self)
        expect(self.panel.connected and self.rotor.connected, "a battery box refused a panel or the scoop rotor")
        expect(not self.third.connected and self.third.reason == "Tooltip_RenewableEnergy_NoInputSlot",
            "a battery box took a third source: " .. tostring(self.third.reason))
        local slots = self.state.status.inputSlots
        expect(slots.used == 2 and slots.total == Specs.freeSlots, "input slots read " .. slots.used .. " of " .. slots.total)
    end,
})

-- Shelter takes up to its share off, each level up adds its bonus, and no wind gets more than the
-- rating out of a charger.
test("renewable_energy_wind_power_curve", {
    validate = function()
        local spec = Specs.wind.turbines.scoop
        local open = Wind.watts(spec, 30, 0, 0)
        local hemmed = Wind.watts(spec, 30, 0, 1)
        local high = Wind.watts(spec, 30, 2, 0)
        T.expectNear("hemmed-in share", hemmed / open, 1 - Specs.wind.shelterLoss, 0.001)
        T.expectNear("two levels up", high / open, 1 + 2 * Specs.wind.heightBonusPerLevel, 0.001)
        expect(Wind.watts(spec, spec.ratedKph * 2, 0, 0) == spec.ratedW, "above its rated speed it makes more than its rating")
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
        for label, sprite in pairs(DRAWN) do
            self.chargers[label] = T.panel(self, sprite)
        end
    end,
    validate = function(self)
        for label, charger in pairs(self.chargers) do
            local object = charger and charger.object
            expect(object ~= nil and object:getSpriteModel() ~= nil, "the " .. label .. " charger has no sprite model on this client")
        end
    end,
})

-- Dismantling a treadmill gives its motor, the wind charger's generator, once for the clicked tile.
test("renewable_energy_wind_treadmill_gives_motor", {
    validate = function()
        local props = ISMoveableSpriteProps.new(Sprites.treadmill.W.console)
        local function motors()
            local count = 0
            for _, fullType in ipairs((props:getScrapItemsList(T.player()) or {}).usable or {}) do
                if fullType == RenewableEnergy.TREADMILL_MOTOR then
                    count = count + 1
                end
            end
            return count
        end
        expect(motors() == 1, "a treadmill's tile scraps to " .. motors() .. " motors")
    end,
})

-- Treadmill -------------------------------------------------------------------------------------

local PowerBank = RenewableEnergy.PowerBank

local function carriedCount(self, fullType)
    return #(self.server.carried.items[fullType] or {})
end

-- Wiring a treadmill to feed a bank takes the Electricity level, a screwdriver, wire and scrap;
-- done, it uses the wire and scrap and the treadmill connects to a bank like a panel.
test("renewable_energy_wind_treadmill_wired_to_bank", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        if not bank then return end
        local treadmill = T.panel(self, Sprites.treadmill.W.rear, { near = bank })
        if not treadmill then return end
        self.treadmill = treadmill
        local wiring = Specs.treadmill.wiring
        T.setPerk(self, Perks.Electricity, wiring.skill)
        T.give(self, "parts", { { type = PowerBank.WIRE, count = wiring.wire }, { type = PowerBank.SCRAP, count = wiring.scrap },
            { type = "Base.Screwdriver" } })
        T.step(function()
            -- What the menu would show a character a level short, carrying everything.
            local restore = PZHarness.Fixtures.setPerk(T.player(), Perks.Electricity, wiring.skill - 1)
            self.unskilled = RenewableEnergy.firstUnmet(PowerBank.treadmillNeeds(T.player()))
            restore()
            self.looseKind = PowerBank.sourceKind(treadmill.object)
        end)
        T.goNextTo(self, treadmill.square)
        T.step(function()
            ISTimedActionQueue.add(RenewableEnergyAction:new(T.player(), RenewableEnergyAction.WIRE_TREADMILL, treadmill.object))
        end)
        T.waitUntil(function() return PowerBank.sourceKind(treadmill.object) == "treadmill" end, 120)
        T.server(self, "carried", { types = { PowerBank.WIRE, PowerBank.SCRAP } })
        T.server(self, "perform", function()
            return { command = "connectSource", args = { bank = bank.position, source = treadmill.position } }
        end)
    end,
    validate = function(self)
        expect(self.looseKind == nil, "an unwired treadmill is already a source")
        expect(self.unskilled and self.unskilled.kind == "skill", "below the Electricity level the wiring isn't refused for skill")
        expect(PowerBank.sourceKind(self.treadmill.object) == "treadmill", "the treadmill wasn't wired")
        expect(carriedCount(self, PowerBank.WIRE) == 0 and carriedCount(self, PowerBank.SCRAP) == 0,
            "wiring left " .. carriedCount(self, PowerBank.WIRE) .. " wire and " .. carriedCount(self, PowerBank.SCRAP) .. " scrap")
        expect(self.server.perform.ok == true, "the bank refused the wired treadmill: " .. tostring(self.server.perform.reason))
    end,
})

-- The treadmill's submenu built for a right-click on `object`, and the context to hide after.
local function treadmillMenu(object)
    local context = ISContextMenu.get(0, 0, 0)
    RenewableEnergy.Menu.onFill(0, context, { object }, false)
    local option = context:getOptionFromName(getText("IGUI_RenewableEnergy_Treadmill"))
    return option and option.subOption and context:getSubMenu(option.subOption), context
end

-- A loose treadmill offers Wire to a Bank, greyed while the character lacks what it takes, even
-- beside a wired one. Once one tile is wired, a right-click on either tile of that treadmill
-- offers Run on Treadmill instead, greyed and saying why until it is connected to a bank.
test("renewable_energy_wind_treadmill_menu", {
    run = function(self)
        local wired = T.panel(self, Sprites.treadmill.S.console, { wired = true })
        if not wired then return end
        local function place(field, sprite, x, y)
            T.server(self, "placePanel", { x = x, y = y, z = 0, sprite = sprite })
            T.waitUntil(function() return PowerBank.treadmillOn(getSquare(x, y, 0)) ~= nil end, 120)
            T.step(function() self[field] = PowerBank.treadmillOn(getSquare(x, y, 0)) end)
        end
        local x, y = wired.square:getX(), wired.square:getY()
        -- Its own rear tile, north of the console (Sprites.treadmill), not wired.
        place("otherTile", Sprites.treadmill.S.rear, x, y - 1)
        -- Another treadmill's rear tile east of it, whose console would be further east.
        place("loose", Sprites.treadmill.E.rear, x + 1, y)
    end,
    validate = function(self)
        local wire = getText("ContextMenu_RenewableEnergy_WireTreadmill")
        local run = getText("ContextMenu_RenewableEnergy_RunOnTreadmill")
        if not expect(self.loose and self.otherTile, "the treadmill tiles never arrived") then return end
        local menu, context = treadmillMenu(self.loose)
        local option = menu and menu:getOptionFromName(wire)
        expect(option ~= nil and option.notAvailable, "an empty-handed character isn't offered Wire to a Bank greyed out")
        expect(menu == nil or menu:getOptionFromName(run) == nil, "a loose treadmill beside a wired one offers a run")
        context:hideAndChildren()
        menu, context = treadmillMenu(self.otherTile)
        option = menu and menu:getOptionFromName(run)
        expect(option ~= nil and option.notAvailable
            and option.toolTip.description == getText("Tooltip_RenewableEnergy_TreadmillNotConnected"),
            "the unwired tile of a wired, unconnected treadmill doesn't offer Run greyed with the reason")
        expect(menu == nil or menu:getOptionFromName(wire) == nil, "a wired treadmill offers to be wired again")
        context:hideAndChildren()
    end,
})

-- A run on a treadmill wired to a bank banks its watt-hours in the next pass, and costs the runner
-- endurance and water and trains Fitness and Sprinting.
test("renewable_energy_wind_treadmill_run_feeds_bank", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        if not bank then return end
        T.bankSet(self, bank, { charge = 0.5 }, true)
        local treadmill = T.panel(self, Sprites.treadmill.N.console, { near = bank, connect = true, wired = true })
        if not treadmill then return end
        self.treadmill = treadmill
        T.server(self, "setCharacterStatUntilEnd", { stat = "ENDURANCE", value = 1 })
        T.server(self, "setCharacterStatUntilEnd", { stat = "THIRST", value = 0 })
        T.waitUntil(function() return T.player():getStats():get(CharacterStat.ENDURANCE) > 0.99 end, 120)
        T.server(self, "perkXp", { perk = "Fitness" })
        T.step(function() self.xpBefore = self.server.perkXp.value end)
        T.bankState(self, bank)
        T.step(function() self.before = bank.state end)
        T.goNextTo(self, treadmill.square)
        T.step(function()
            ISTimedActionQueue.add(RenewableEnergyTreadmillAction:new(T.player(), treadmill.object))
        end)
        T.server(self, "characterStat", { stat = "ENDURANCE" })
        T.step(function() self.endurance = self.server.characterStat.value end)
        T.server(self, "characterStat", { stat = "THIRST" })
        T.step(function() self.thirst = self.server.characterStat.value end)
        T.server(self, "perkXp", { perk = "Fitness" })
        T.bankPass(self, bank, 0)
        T.step(function() self.after = bank.state end)
    end,
    validate = function(self)
        expect(self.treadmill.connected, "the bank refused the wired treadmill: " .. tostring(self.treadmill.reason))
        local spec = Specs.treadmill
        local hours = spec.runMinutes / 60
        local wh = spec.watts * hours
        local source = sourceOf(self.after, "treadmill")
        if not expect(source ~= nil, "the bank's status lists no treadmill") then return end
        T.expectNear("the treadmill's watts over an hour's pass", source.watts, wh, 0.01)
        T.expectNear("the bank's treadmill Wh today", self.after.status.runWhToday, wh, 0.01)
        T.expectNear("Wh stored by the run", self.after.status.storedWh - self.before.status.storedWh, wh, 1)
        T.expectNear("endurance after the run", self.endurance, 1 - spec.endurancePerHour * hours, 0.02)
        T.expectNear("thirst after the run", self.thirst, spec.thirstPerHour * hours, 0.02)
        expect(self.server.perkXp.value > self.xpBefore, "the run taught no Fitness")
        local label = RenewableEnergy.StatusWindow.panelLabel(source, source)
        expect(label:find(getText("IGUI_RenewableEnergy_Treadmill"), 1, true) == 1, "the window calls the treadmill " .. label)
    end,
})

-- Propeller and homemade alternator ------------------------------------------------------------

local CONTROLLER = "RenewableEnergy.ChargeController"

-- The status entry of the source at `position` in a bank state.
local function sourceAt(state, position)
    for _, source in ipairs(state and state.status and state.status.sources or {}) do
        if PowerBank.samePosition(source, position) then
            return source
        end
    end
    return nil
end

-- Left unbraked through a storm, a propeller's blades break and it makes nothing until a spare set
-- goes on; a braked one comes through whole. The menu offers Replace Blades, greyed until the
-- character carries blades that fit.
test("renewable_energy_wind_propeller_storm_and_blades", {
    instant = true,
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { CAR_BATTERY, INVERTER, CONTROLLER })
        if not bank then return end
        self.left = T.panel(self, Sprites.windPropeller.wood.S, { near = bank, connect = true })
        self.braked = T.panel(self, Sprites.windPropeller.pipe.S, { near = bank, connect = true })
        if not (self.left and self.braked) then return end
        T.server(self, "perform", function()
            return { command = "setBrake", args = { source = self.braked.position, braked = true } }
        end)
        -- Long enough in a gale that an unbraked propeller all but surely breaks: 1 - 0.75^60.
        local spec = Specs.wind.turbines.propeller
        T.bankPass(self, bank, 0, { windKph = spec.breakKph + 5, hours = 60 })
        T.step(function() self.storm = bank.state end)
        T.waitUntil(function() return PowerBank.isBroken(self.left.object) end, 120)
        T.step(function()
            local context = ISContextMenu.get(0, 0, 0)
            local menu = RenewableEnergy.Menu.addSourceOptions(0, context, self.left.object)
            self.emptyHanded = menu:getOptionFromName(getText("ContextMenu_RenewableEnergy_ReplaceBlades"))
            self.emptyHanded = self.emptyHanded and self.emptyHanded.notAvailable
            context:hideAndChildren()
        end)
        T.give(self, "blades", { { type = "RenewableEnergy.WoodenBlades" } })
        T.goNextTo(self, self.left.square)
        T.step(function()
            ISTimedActionQueue.add(RenewableEnergyAction:new(T.player(), RenewableEnergyAction.REPLACE_BLADES, self.left.object,
                nil, nil, self.items.blades[1]))
        end)
        T.waitUntil(function() return not PowerBank.isBroken(self.left.object) end, 120)
        T.server(self, "carried", { types = { "RenewableEnergy.WoodenBlades" } })
        T.bankPass(self, bank, 0, { windKph = 30 })
        T.step(function() self.mended = bank.state end)
    end,
    validate = function(self)
        expect(self.left.connected and self.braked.connected, "the bank refused a propeller")
        local left, braked = sourceAt(self.storm, self.left.position), sourceAt(self.storm, self.braked.position)
        if not expect(left and braked, "the bank's status lists no propellers") then return end
        expect(left.broken and left.watts == 0 and left.reason == "broken",
            "unbraked through the gale it reads broken " .. tostring(left.broken) .. ", " .. left.watts .. " W, " .. tostring(left.reason))
        expect(not braked.broken, "the braked propeller broke")
        expect(self.emptyHanded == true, "with no blades carried, Replace Blades isn't offered greyed out")
        expect(#(self.server.carried.items["RenewableEnergy.WoodenBlades"] or {}) == 0, "replacing the blades left them in the inventory")
        local mended = sourceAt(self.mended, self.left.position)
        expect(mended and not mended.broken and mended.watts > 0, "with new blades it still makes nothing")
    end,
})

-- The homemade alternator takes three input slots, more than a bank without a controller has; in a
-- gale it turns out of the wind and makes its furled share, without breaking.
test("renewable_energy_wind_alternator_slots_and_furling", {
    instant = true,
    sandbox = { StormDamage = true, StormDamageRate = 100 },
    run = function(self)
        local box = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        if not box then return end
        self.refused = T.panel(self, Sprites.windAlternator.N, { near = box, connect = true })
        local rack = T.bank(self, "batteryRackWood", { CAR_BATTERY, INVERTER, CONTROLLER })
        if not rack then return end
        self.alternator = T.panel(self, Sprites.windAlternator.E, { near = rack, connect = true })
        if not self.alternator then return end
        local spec = Specs.wind.turbines.alternator
        T.bankPass(self, rack, 0, { windKph = spec.furlKph + 5, hours = 60 })
        T.step(function() self.gale = rack.state end)
    end,
    validate = function(self)
        expect(not self.refused.connected and self.refused.reason == "Tooltip_RenewableEnergy_NoInputSlot",
            "a battery box with two free slots took the alternator: " .. tostring(self.refused.reason))
        expect(self.alternator.connected, "a rack with a controller refused the alternator: " .. tostring(self.alternator.reason))
        local source = sourceAt(self.gale, self.alternator.position)
        if not expect(source ~= nil, "the rack's status lists no alternator") then return end
        local spec = Specs.wind.turbines.alternator
        local expected = Wind.watts(spec, spec.furlKph + 5, source.z, source.shelterPct / 100)
        T.expectNear("furled alternator watts", source.watts, expected, 2)
        T.expectNear("furled share", expected / Wind.watts(spec, spec.ratedKph, source.z, source.shelterPct / 100), spec.furledShare, 0.001)
        expect(source.reason == "furled" and not source.broken, "in a gale it reads " .. tostring(source.reason) .. ", broken " .. tostring(source.broken))
    end,
})
