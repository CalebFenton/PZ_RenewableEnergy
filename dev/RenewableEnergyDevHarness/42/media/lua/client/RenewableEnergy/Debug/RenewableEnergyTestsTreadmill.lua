require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Vanilla's treadmill as a source for a bank: dismantled for its motor, or wired to a bank and run
-- on.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect
local Specs, Sprites = RenewableEnergy.Specs, RenewableEnergy.Sprites
local PowerBank, Sources, Treadmill = RenewableEnergy.PowerBank, RenewableEnergy.Sources, RenewableEnergy.Treadmill

local CAR_BATTERY = "Base.CarBattery1"
local INVERTER = "RenewableEnergy.PlugInInverter"

local function treadmillOf(state)
    for _, source in ipairs(state and state.status and state.status.sources or {}) do
        if source.kind == "treadmill" then
            return source
        end
    end
    return nil
end

-- Dismantling a treadmill gives its motor, the wind charger's generator, once: for the tile that
-- was clicked, not again for its other tile, which vanilla scraps along with it.
test("renewable_energy_treadmill_gives_motor", {
    validate = function()
        local props = ISMoveableSpriteProps.new(Sprites.treadmill.W.console)
        local function motors()
            local count = 0
            for _, fullType in ipairs((props:getScrapItemsList(T.player()) or {}).usable or {}) do
                if fullType == Treadmill.MOTOR then
                    count = count + 1
                end
            end
            return count
        end
        expect(motors() == 1, "a treadmill's clicked tile scraps to " .. motors() .. " motors")
        props.scrappingMainTile = false
        expect(motors() == 0, "a treadmill's other tile scraps to " .. motors() .. " motors")
    end,
})

local function carriedCount(self, fullType)
    return #(self.server.carried.items[fullType] or {})
end

-- Wiring a treadmill to feed a bank takes the Electricity level, a screwdriver, wire and scrap;
-- done, it uses the wire and scrap and the treadmill connects to a bank like a panel. Its other
-- tile can't be wired as well.
test("renewable_energy_treadmill_wired_to_bank", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        if not bank then return end
        local treadmill = T.panel(self, Sprites.treadmill.W.rear, { near = bank })
        if not treadmill then return end
        self.treadmill = treadmill
        -- Its console end, west of the rear (Sprites.treadmill).
        local square = treadmill.square
        self.console = T.panel(self, Sprites.treadmill.W.console,
            { square = getSquare(square:getX() - 1, square:getY(), square:getZ()) })
        if not self.console then return end
        local wiring = Specs.treadmill.wiring
        T.setPerk(self, Perks.Electricity, wiring.skill)
        T.give(self, "parts", { { type = PowerBank.WIRE, count = wiring.wire }, { type = PowerBank.SCRAP, count = wiring.scrap },
            { type = "Base.Screwdriver" } })
        T.step(function()
            -- What the menu would show a character a level short, carrying everything.
            local restore = PZHarness.Fixtures.setPerk(T.player(), Perks.Electricity, wiring.skill - 1)
            self.unskilled = Treadmill.wiringRefusal(T.player(), treadmill.object)
            restore()
            self.looseKind = Sources.kindOf(treadmill.object)
        end)
        T.doJob(self, treadmill.square, function()
            return RenewableEnergyAction:new(T.player(), RenewableEnergyAction.WIRE_TREADMILL, treadmill.object)
        end)
        T.waitForCopy(function() return Sources.kindOf(treadmill.object) == "treadmill" end,
            "this client's copy of the wired treadmill")
        T.batch(function()
            T.server(self, "carried", { types = { PowerBank.WIRE, PowerBank.SCRAP } })
            T.perform(self, "connectSource", { bank = bank.position, source = treadmill.position })
            T.step(function() self.connected = self.server.perform end)
            T.perform(self, "wireTreadmill", { source = self.console.position })
            T.step(function() self.again = self.server.perform end)
        end)
    end,
    validate = function(self)
        expect(self.looseKind == nil, "an unwired treadmill is already a source")
        expect(self.unskilled == "skill", "below the Electricity level the wiring is refused for " .. tostring(self.unskilled))
        expect(Sources.kindOf(self.treadmill.object) == "treadmill", "the treadmill wasn't wired")
        expect(carriedCount(self, PowerBank.WIRE) == 0 and carriedCount(self, PowerBank.SCRAP) == 0,
            "wiring left " .. carriedCount(self, PowerBank.WIRE) .. " wire and " .. carriedCount(self, PowerBank.SCRAP) .. " scrap")
        expect(self.connected.ok == true, "the bank refused the wired treadmill: " .. tostring(self.connected.reason))
        expect(self.again.ok ~= true and self.again.reason == "already wired",
            "wiring the treadmill's other tile too wasn't refused as already wired: " .. tostring(self.again.reason))
    end,
})

-- A loose treadmill offers Wire to a Bank, greyed while the character lacks what it takes, even
-- beside a wired one. Once one tile is wired, a right-click on either tile of that treadmill
-- offers Run on Treadmill instead, greyed and saying why until it is connected to a bank.
test("renewable_energy_treadmill_menu", {
    run = function(self)
        local wired = T.panel(self, Sprites.treadmill.S.console, { wired = true })
        if not wired then return end
        local x, y, z = wired.square:getX(), wired.square:getY(), wired.square:getZ()
        -- Its own rear tile, north of the console (Sprites.treadmill), not wired.
        self.otherTile = T.panel(self, Sprites.treadmill.S.rear, { square = getSquare(x, y - 1, z) })
        -- Another treadmill's rear tile east of it, whose console would be further east.
        self.loose = T.panel(self, Sprites.treadmill.E.rear, { square = getSquare(x + 1, y, z) })
    end,
    validate = function(self)
        local wire = getText("ContextMenu_RenewableEnergy_WireTreadmill")
        local run = getText("ContextMenu_RenewableEnergy_RunOnTreadmill")
        local label = getText("IGUI_RenewableEnergy_Treadmill")
        local menu, context = T.worldSubmenu(self.loose.object, label)
        local option = menu and menu:getOptionFromName(wire)
        expect(option ~= nil and option.notAvailable, "an empty-handed character isn't offered Wire to a Bank greyed out")
        expect(menu == nil or menu:getOptionFromName(run) == nil, "a loose treadmill beside a wired one offers a run")
        if context then context:hideAndChildren() end
        menu, context = T.worldSubmenu(self.otherTile.object, label)
        option = menu and menu:getOptionFromName(run)
        expect(option ~= nil and option.notAvailable
            and option.toolTip.description == getText("Tooltip_RenewableEnergy_TreadmillNotConnected"),
            "the unwired tile of a wired, unconnected treadmill doesn't offer Run greyed with the reason")
        expect(menu == nil or menu:getOptionFromName(wire) == nil, "a wired treadmill offers to be wired again")
        if context then context:hideAndChildren() end
    end,
})

-- A run on a treadmill wired to a bank banks its watt-hours, paid out over the passes after it at
-- no more than a runner's watts, and costs the runner endurance and water and trains Fitness.
test("renewable_energy_treadmill_run_feeds_bank", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        if not bank then return end
        T.bankSet(self, bank, { charge = 0.5 }, true)
        local treadmill = T.panel(self, Sprites.treadmill.N.console, { near = bank, connect = true, wired = true })
        if not treadmill then return end
        self.treadmill = treadmill
        T.batch(function()
            T.server(self, "setCharacterStatUntilEnd", { stat = "ENDURANCE", value = 1 })
            T.server(self, "setCharacterStatUntilEnd", { stat = "THIRST", value = 0 })
        end)
        T.waitForCopy(function() return T.player():getStats():get(CharacterStat.ENDURANCE) > 0.99 end,
            "this client's copy of the rested runner")
        T.batch(function()
            T.server(self, "perkXp", { perk = "Fitness" })
            T.step(function() self.xpBefore = self.server.perkXp.value end)
            T.bankState(self, bank)
            T.step(function() self.before = bank.state end)
        end)
        T.doJob(self, treadmill.square, function() return RenewableEnergyTreadmillAction:new(T.player(), treadmill.object) end)
        T.batch(function()
            T.server(self, "characterStats", { stats = { "ENDURANCE", "THIRST" } })
            T.server(self, "perkXp", { perk = "Fitness" })
            -- A pass as long as the default ten minutes, then a long one.
            T.bankPass(self, bank, 0, { hours = 1 / 6 })
            T.step(function() self.short = bank.state end)
            T.bankPass(self, bank, 0)
            T.step(function() self.after = bank.state end)
        end)
    end,
    validate = function(self)
        expect(self.treadmill.connected, "the bank refused the wired treadmill: " .. tostring(self.treadmill.reason))
        local spec = Specs.treadmill
        local hours = spec.runMinutes / 60
        local wh = spec.watts * hours
        local short, after = treadmillOf(self.short), treadmillOf(self.after)
        if not expect(short ~= nil and after ~= nil, "the bank's status lists no treadmill") then return end
        T.expectNear("the treadmill's watts in a ten-minute pass", short.watts, spec.watts, 0.01)
        T.expectNear("the treadmill's watts in the hour after", after.watts, wh - spec.watts / 6, 0.01)
        T.expectNear("the bank's treadmill Wh today", self.after.status.runWhToday, wh, 0.01)
        T.expectNear("Wh stored by the run", self.after.status.storedWh - self.before.status.storedWh, wh, 1)
        local stats = self.server.characterStats and self.server.characterStats.values
        if expect(stats ~= nil, "no stats of the runner from the server") then
            T.expectNear("endurance after the run", stats.ENDURANCE, 1 - spec.endurancePerHour * hours, 0.02)
            T.expectNear("thirst after the run", stats.THIRST, spec.thirstPerHour * hours, 0.02)
        end
        expect(self.server.perkXp.value > self.xpBefore, "the run taught no Fitness")
        local label = RenewableEnergy.StatusWindow.sourceLabel(after, after)
        expect(label:find(getText("IGUI_RenewableEnergy_Treadmill"), 1, true) == 1, "the window calls the treadmill " .. label)
    end,
})
