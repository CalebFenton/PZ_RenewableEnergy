require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Treadmill (PowerBank/Treadmill.lua, TreadmillSource.lua, RenewableEnergyTreadmillAction, its menu):
-- dismantling for the motor, wiring to a bank, runs wired and unwired, unwiring and pickup.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect
local Specs, Sprites = RenewableEnergy.Specs, RenewableEnergy.Sprites
local PowerBank, Treadmill = RenewableEnergy.PowerBank, RenewableEnergy.Treadmill

local CAR_BATTERY = "Base.CarBattery1"
local INVERTER = "RenewableEnergy.PlugInInverter"
-- A bank whose inverter carries whatever the test map's house has switched on, a run included.
local L16 = "RenewableEnergy.L16Battery"
local INVERTER_CHARGER = "RenewableEnergy.InverterCharger"
-- A pass this long barely moves a bank's batteries.
local PASS_HOURS = 1 / 60

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
test("renewable_energy_treadmill_dismantle_gives_motor_once", {
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

-- Wiring a treadmill takes the Electricity level and the parts it lists; done, it uses the
-- parts and the treadmill connects to a bank like a panel. Its other tile can't be wired as well.
test("renewable_energy_treadmill_wiring_uses_parts_and_connects", {
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
            self.looseWired = Treadmill.isWiredTile(treadmill.object)
        end)
        T.doJob(self, treadmill.square, function()
            return RenewableEnergyAction:new(T.player(), RenewableEnergyAction.WIRE_TREADMILL, treadmill.object)
        end)
        T.waitFor(self, function() return Treadmill.isWiredTile(treadmill.object) end,
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
        expect(not self.looseWired, "an unwired treadmill is already wired")
        expect(self.unskilled == "skill", "below the Electricity level the wiring is refused for " .. tostring(self.unskilled))
        expect(carriedCount(self, PowerBank.WIRE) == 0 and carriedCount(self, PowerBank.SCRAP) == 0,
            "wiring left " .. carriedCount(self, PowerBank.WIRE) .. " wire and " .. carriedCount(self, PowerBank.SCRAP) .. " scrap")
        expect(self.connected.ok == true, "the bank refused the wired treadmill: " .. tostring(self.connected.reason))
        expect(self.again.ok ~= true and self.again.reason == "already wired",
            "wiring the treadmill's other tile too wasn't refused as already wired: " .. tostring(self.again.reason))
    end,
})

-- What a right-click on the treadmill tile `object` offers in its submenu: Run on Treadmill, Wire
-- to a Bank and Unwire, each nil if not offered, else { greyed, reason }.
local function treadmillMenu(object)
    local menu, context = T.worldSubmenu(object, getText("IGUI_RenewableEnergy_Treadmill"))
    local function offered(key)
        local option = menu and menu:getOptionFromName(getText(key))
        return option and { greyed = option.notAvailable == true, reason = option.toolTip and option.toolTip.description }
    end
    local seen = {
        run = offered("ContextMenu_RenewableEnergy_RunOnTreadmill"),
        wire = offered("ContextMenu_RenewableEnergy_WireTreadmill"),
        unwire = offered("ContextMenu_RenewableEnergy_UnwireTreadmill"),
    }
    if context then context:hideAndChildren() end
    return seen
end

-- A loose treadmill offers Run on Treadmill, greyed saying it needs power while it has none and
-- open once it has, and Wire to a Bank either way, greyed while the character lacks what it
-- takes, even beside a wired one. Once one tile is wired, a right-click on either tile of that
-- treadmill offers Run greyed and saying why until it is connected to a bank, and Unwire.
test("renewable_energy_treadmill_menu_offers_run_and_wiring", {
    run = function(self)
        T.setGrid(self, false)
        local wired = T.panel(self, Sprites.treadmill.S.console, { wired = true })
        if not wired then return end
        local x, y, z = wired.square:getX(), wired.square:getY(), wired.square:getZ()
        -- Its own rear tile, north of the console (Sprites.treadmill), not wired.
        self.otherTile = T.panel(self, Sprites.treadmill.S.rear, { square = getSquare(x, y - 1, z) })
        -- Another treadmill's rear tile east of it, whose console would be further east.
        self.loose = T.panel(self, Sprites.treadmill.E.rear, { square = getSquare(x + 1, y, z) })
        local indoors = T.square(self, { indoors = true }, "a free indoor square for a treadmill")
        if not indoors then return end
        self.indoor = T.panel(self, Sprites.treadmill.W.rear, { square = indoors })
        T.step(function()
            self.unpowered = treadmillMenu(self.loose.object)
            T.setGrid(self, true)
        end)
        T.step(function()
            -- The grid powers a square in a room (ItemContainer.isObjectPowered).
            if not T.need(self, indoors:hasGridPower() and indoors:getRoom() ~= nil, "grid power in the indoor square's room") then
                return
            end
            self.powered = treadmillMenu(self.indoor.object)
            self.wiredMenu = treadmillMenu(self.otherTile.object)
        end)
    end,
    validate = function(self)
        local loose, powered, wired = self.unpowered, self.powered, self.wiredMenu
        expect(loose.wire ~= nil and loose.wire.greyed, "an empty-handed character isn't offered Wire to a Bank greyed out")
        expect(loose.run ~= nil and loose.run.greyed and loose.run.reason == getText("Tooltip_RenewableEnergy_TreadmillNoPower"),
            "a loose treadmill without power doesn't offer Run greyed saying it needs power")
        expect(powered.run ~= nil and not powered.run.greyed, "a loose treadmill on grid power doesn't offer Run open")
        expect(powered.wire ~= nil, "a loose treadmill on grid power doesn't offer Wire to a Bank")
        expect(wired.run ~= nil and wired.run.greyed and wired.run.reason == getText("Tooltip_RenewableEnergy_TreadmillNotConnected"),
            "the unwired tile of a wired, unconnected treadmill doesn't offer Run greyed with the reason")
        expect(wired.wire == nil, "a wired treadmill offers to be wired again")
        expect(wired.unwire ~= nil and not wired.unwire.greyed, "a wired treadmill doesn't offer Unwire")
    end,
})

-- In the dark, Wire to Bank is greyed out saying it's too dark rather than listing what it takes,
-- as the other wiring menus do.
test("renewable_energy_treadmill_wiring_refused_in_the_dark", {
    run = function(self)
        self.treadmill = T.panel(self, Sprites.treadmill.E.rear)
        if self.treadmill then T.makeDark(self) end
    end,
    validate = function(self)
        if not expect(T.player():tooDarkToRead(), "midnight with the grid off isn't dark where the character stands") then return end
        local menu, context = T.worldSubmenu(self.treadmill.object, getText("IGUI_RenewableEnergy_Treadmill"))
        local option = menu and menu:getOptionFromName(getText("ContextMenu_RenewableEnergy_WireTreadmill"))
        local reason = option and option.toolTip and option.toolTip.description
        expect(option ~= nil and option.notAvailable and reason == getText("Tooltip_RenewableEnergy_TooDark"),
            "Wire to Bank in the dark isn't greyed out saying it's too dark (" .. tostring(reason) .. ")")
        if context then context:hideAndChildren() end
    end,
})

local SHORT_PASS_HOURS = 1 / 6

-- A run on a wired treadmill banks its watt-hours, paid out over the passes after it rather than
-- in one go, into the batteries as the status says, and costs the runner sweat and trains Fitness.
test("renewable_energy_treadmill_wired_run_pays_bank_over_passes", {
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
        T.waitFor(self, function() return T.player():getStats():get(CharacterStat.ENDURANCE) > 0.99 end,
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
            -- A short pass, then a long one that pays out the rest.
            T.bankPass(self, bank, 0, { hours = SHORT_PASS_HOURS })
            T.step(function() self.short = bank.state end)
            T.bankPass(self, bank, 0)
            T.step(function() self.after = bank.state end)
        end)
    end,
    validate = function(self)
        expect(self.treadmill.connected, "the bank refused the wired treadmill: " .. tostring(self.treadmill.reason))
        local short, after = treadmillOf(self.short), treadmillOf(self.after)
        if not expect(short ~= nil and after ~= nil, "the bank's status lists no treadmill") then return end
        local banked = self.after.status.runWhToday
        if not expect(banked > 0, "the run banked nothing") then return end
        local shortWh, laterWh = short.watts * SHORT_PASS_HOURS, after.watts
        expect(shortWh > 0 and shortWh < banked, "the short pass after the run paid out " .. shortWh .. " of its "
            .. banked .. " Wh, not a part of it")
        T.expectNear("Wh the two passes paid out of the run", shortWh + laterWh, banked, 0.01)
        T.expectNear("Wh in the batteries against the run's Wh in the status",
            self.after.status.storedWh - self.before.status.storedWh, banked, 1)
        local stats = self.server.characterStats and self.server.characterStats.values
        if expect(stats ~= nil, "no stats of the runner from the server") then
            expect(stats.ENDURANCE < 0.99, "the run cost no endurance: " .. stats.ENDURANCE)
            expect(stats.THIRST > 0.01, "the run made the runner no thirstier: " .. stats.THIRST)
        end
        expect(self.server.perkXp.value > self.xpBefore, "the run taught no Fitness")
    end,
})

-- A bank of L-16s with an inverter-charger, switched on with the grid off, and a treadmill tile of
-- `sprite` on an indoor square it powers, wired and connected to it if `wired`. Returns both
-- handles once this client sees power on the treadmill's square, or nil.
local function poweredTreadmill(self, sprite, wired)
    T.setGrid(self, false)
    local bank = T.bank(self, "batteryRackWood", { L16, L16, INVERTER_CHARGER })
    local square = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a treadmill")
    local treadmill = square and T.panel(self, sprite, { square = square, near = bank, connect = wired, wired = wired })
    if not treadmill then return nil end
    T.switchOn(self, bank)
    T.waitFor(self, function() return square:haveElectricity() end, "power from the switched-on bank on the treadmill's square here")
    return bank, treadmill
end

-- A whole run on an unwired treadmill a bank powers costs the runner sweat and trains Fitness as a
-- wired run does, and banks nothing.
test("renewable_energy_treadmill_unwired_run_trains_without_banking", {
    instant = true,
    run = function(self)
        local bank, treadmill = poweredTreadmill(self, Sprites.treadmill.N.console)
        if not bank then return end
        self.bank = bank
        T.batch(function()
            T.server(self, "setCharacterStatUntilEnd", { stat = "ENDURANCE", value = 1 })
            T.server(self, "setCharacterStatUntilEnd", { stat = "THIRST", value = 0 })
        end)
        T.waitFor(self, function() return T.player():getStats():get(CharacterStat.ENDURANCE) > 0.99 end,
            "this client's copy of the rested runner")
        T.server(self, "perkXp", { perk = "Fitness" })
        T.step(function() self.xpBefore = self.server.perkXp.value end)
        T.doJob(self, treadmill.square, function() return RenewableEnergyTreadmillAction:new(T.player(), treadmill.object) end)
        T.batch(function()
            T.server(self, "characterStats", { stats = { "ENDURANCE", "THIRST" } })
            T.server(self, "perkXp", { perk = "Fitness" })
            T.bankPass(self, bank, 0, { hours = PASS_HOURS })
        end)
    end,
    validate = function(self)
        local stats = self.server.characterStats and self.server.characterStats.values
        if expect(stats ~= nil, "no stats of the runner from the server") then
            expect(stats.ENDURANCE < 0.99, "the run cost no endurance: " .. stats.ENDURANCE)
            expect(stats.THIRST > 0.01, "the run made the runner no thirstier: " .. stats.THIRST)
        end
        expect(self.server.perkXp.value > self.xpBefore, "the run taught no Fitness")
        T.expectNear("Wh the unwired run banked", self.bank.state.status.runWhToday, 0, 0)
    end,
})

-- A run on an unwired treadmill a bank powers bills the treadmill's watts to that bank from when
-- the authority starts it until it settles; once the power goes out, the run can't go on.
test("renewable_energy_treadmill_unwired_run_draws_from_bank", {
    run = function(self)
        local bank, treadmill = poweredTreadmill(self, Sprites.treadmill.N.console)
        if not bank then return end
        self.bank = bank
        T.server(self, "setCharacterStatUntilEnd", { stat = "ENDURANCE", value = 1 })
        T.goNextTo(self, treadmill.square)
        T.waitFor(self, function() return T.player():getStats():get(CharacterStat.ENDURANCE) > 0.99 end,
            "this client's copy of the rested runner")
        T.step(function() self.goesOnPower = RenewableEnergyTreadmillAction:new(T.player(), treadmill.object):isValid() end)
        T.batch(function()
            T.bankPass(self, bank, 0, { hours = PASS_HOURS })
            T.step(function() self.before = bank.state end)
            T.server(self, "startTreadmillRun", T.at(treadmill))
            T.bankPass(self, bank, 0, { hours = PASS_HOURS })
            T.step(function() self.during = bank.state end)
            T.server(self, "completeStartedTreadmillRun", T.at(treadmill))
            T.bankPass(self, bank, 0, { hours = PASS_HOURS })
        end)
        T.perform(self, "setBankOn", { bank = bank.position, on = false })
        T.waitFor(self, function() return not treadmill.square:haveElectricity() end,
            "this client's copy of the treadmill's square without power once the bank is off")
        T.step(function()
            self.goesWithoutPower = RenewableEnergyTreadmillAction:new(T.player(), treadmill.object):isValid()
        end)
    end,
    validate = function(self)
        local before, during, after = self.before.status, self.during.status, self.bank.state.status
        local watts = Specs.treadmill.drawFuel * Specs.wattsPerFuel
        T.expectNear("W the running treadmill added to the bank's load", during.loadW - before.loadW, watts, 0.01)
        T.expectNear("W the batteries gave for the running treadmill", during.drawW - before.drawW,
            watts / Specs.inverterEfficiency, 0.01)
        T.expectNear("W of the bank's load after the run, against before it", after.loadW - before.loadW, 0, 0.01)
        local run = self.server.completeStartedTreadmillRun
        expect(run.done, "the authority settled nothing of a run on a powered, unwired treadmill")
        expect(self.goesOnPower, "a run on a powered, unwired treadmill can't go")
        expect(not self.goesWithoutPower, "a run on an unwired treadmill goes on once its power is out")
    end,
})

-- A run on a wired treadmill feeds its bank and draws nothing from the bank powering it. Catches a
-- wired run billed as a load as well.
test("renewable_energy_treadmill_wired_run_draws_nothing", {
    run = function(self)
        local bank, treadmill = poweredTreadmill(self, Sprites.treadmill.N.console, true)
        if not bank then return end
        self.treadmill = treadmill
        T.goNextTo(self, treadmill.square)
        T.batch(function()
            T.server(self, "startTreadmillRun", T.at(treadmill))
            T.server(self, "scanLoad", bank.position)
            T.step(function() self.during = self.server.scanLoad end)
            T.server(self, "completeStartedTreadmillRun", T.at(treadmill))
        end)
    end,
    validate = function(self)
        expect(self.treadmill.connected, "the bank refused the wired treadmill: " .. tostring(self.treadmill.reason))
        expect((self.during.counts.treadmill or 0) == 0, "a run on a wired treadmill draws from the bank it feeds")
        expect(self.server.completeStartedTreadmillRun.done, "the bank took nothing of a run on a wired, connected treadmill")
    end,
})

-- A run on a wired treadmill whose bank was disconnected banks nothing, so it costs the runner
-- nothing and trains nothing: the menu and the action say why, and the authority settling a whole
-- run, as a server finishes a client's action, changes nothing. Connected again, the same run
-- settles, which shows the runner stood close enough for it to. Catches a run that pays its XP
-- and sweat whether or not a bank took its watt-hours.
test("renewable_energy_treadmill_unconnected_run_gives_nothing", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        local treadmill = bank and T.panel(self, Sprites.treadmill.N.console, { near = bank, connect = true, wired = true })
        if not treadmill then return end
        self.treadmill = treadmill
        local args = { bank = bank.position, source = treadmill.position }
        T.server(self, "setCharacterStatUntilEnd", { stat = "ENDURANCE", value = 1 })
        T.goNextTo(self, treadmill.square)
        T.perform(self, "disconnectSource", args)
        T.waitFor(self, function() return PowerBank.connectedBank(treadmill.object) == nil end,
            "this client's copy of the disconnected treadmill")
        T.step(function() self.refusal = Treadmill.runRefusal(treadmill.object) end)
        T.batch(function()
            T.server(self, "completeTreadmillRun", T.at(treadmill))
            T.step(function() self.unconnected = self.server.completeTreadmillRun end)
            T.perform(self, "connectSource", args)
            T.server(self, "completeTreadmillRun", T.at(treadmill))
            T.step(function() self.connected = self.server.completeTreadmillRun end)
        end)
    end,
    validate = function(self)
        expect(self.refusal == "Tooltip_RenewableEnergy_TreadmillNotConnected",
            "a run on a disconnected treadmill isn't refused for want of a bank: " .. tostring(self.refusal))
        local idle, ran = self.unconnected, self.connected
        expect(not idle.done, "the authority settled a run on a treadmill that feeds no bank")
        T.expectNear("Fitness XP from a run on a disconnected treadmill", idle.xpAfter - idle.xpBefore, 0, 0)
        T.expectNear("endurance a run on a disconnected treadmill cost", idle.enduranceBefore - idle.enduranceAfter, 0, 0)
        expect(ran.done and ran.xpAfter > ran.xpBefore, "connected again, the authority's run settled nothing")
    end,
})

local function carried(self, key)
    T.server(self, "carried", { types = { PowerBank.WIRE, PowerBank.SCRAP } })
    T.step(function()
        self[key] = { wire = carriedCount(self, PowerBank.WIRE), scrap = carriedCount(self, PowerBank.SCRAP) }
    end)
end

-- Unwiring a treadmill takes it out of its bank and gives back the wire its wiring took; the
-- electronics scrap stays spent, as a bank's part gives back only its wire. Wired again, it takes
-- wire and scrap again but teaches nothing more. Catches an unwire that leaves the bank feeding
-- from it or keeps the wire, and a wire-unwire loop that farms Electricity XP.
test("renewable_energy_treadmill_unwire_gives_back_wire", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        local treadmill = bank and T.panel(self, Sprites.treadmill.W.rear, { near = bank })
        if not treadmill then return end
        self.bank = bank
        local wiring = Specs.treadmill.wiring
        T.setPerk(self, Perks.Electricity, wiring.skill)
        T.give(self, "parts", { { type = PowerBank.WIRE, count = wiring.wire }, { type = PowerBank.SCRAP, count = 2 * wiring.scrap },
            { type = "Base.Screwdriver" } })
        -- The wiring below uses the parts up; the step holds it until this client has them.
        T.step(function() end)
        carried(self, "beforeWiring")
        T.perform(self, "wireTreadmill", { source = treadmill.position })
        T.step(function() self.wired = self.server.perform end)
        carried(self, "afterWiring")
        T.perform(self, "connectSource", { bank = bank.position, source = treadmill.position })
        T.waitFor(self, function() return PowerBank.connectedBank(treadmill.object) ~= nil end,
            "this client's copy of the wired, connected treadmill")
        T.doJob(self, treadmill.square, function()
            return RenewableEnergyAction:new(T.player(), RenewableEnergyAction.UNWIRE_TREADMILL, treadmill.object)
        end)
        T.waitFor(self, function() return not Treadmill.isWired(treadmill.object) end, "this client's copy of the unwired treadmill")
        T.bankState(self, bank)
        carried(self, "afterUnwire")
        T.perform(self, "wireTreadmill", { source = treadmill.position })
        T.step(function() self.rewired = self.server.perform end)
    end,
    validate = function(self)
        expect(self.wired.ok and self.wired.xpAfter > self.wired.xpBefore, "the first wiring failed or taught nothing")
        expect(self.bank.state.sources == 0, "the bank still feeds from the unwired treadmill")
        local before, wired, after = self.beforeWiring, self.afterWiring, self.afterUnwire
        expect(wired.wire < before.wire and wired.scrap < before.scrap, "wiring took no wire or no scrap")
        expect(after.wire == before.wire and after.scrap == wired.scrap, "unwiring left " .. after.wire .. " wire and "
            .. after.scrap .. " scrap, expected the " .. before.wire .. " wire carried before wiring and the "
            .. wired.scrap .. " scrap left after it")
        expect(self.rewired.ok, "wiring the treadmill again failed (" .. tostring(self.rewired.reason) .. ")")
        T.expectNear("Electricity XP for wiring the same treadmill again", self.rewired.xpAfter - self.rewired.xpBefore, 0, 0)
    end,
})

-- What a run banked that the passes haven't paid out yet goes into the batteries when the treadmill
-- is unwired or picked up: the same run on a treadmill unwired at once, on one picked up at once and
-- on one left wired, with the same passes after, stores the same. Catches unwiring, moving or
-- picking up a treadmill right after a run forfeiting the run, at once or at the next pass.
test("renewable_energy_treadmill_unwire_keeps_the_run", {
    instant = true,
    run = function(self)
        self.cases = {}
        for _, name in ipairs({ "kept", "unwired", "pickedUp" }) do
            local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER }, { charge = 0.5 })
            local treadmill = bank and T.panel(self, Sprites.treadmill.W.rear, { near = bank, connect = true, wired = true })
            if not treadmill then return end
            -- Its console end, west of the rear (Sprites.treadmill), for the pickup to take.
            local square = treadmill.square
            local console = T.panel(self, Sprites.treadmill.W.console,
                { square = getSquare(square:getX() - 1, square:getY(), square:getZ()) })
            if not console then return end
            table.insert(self.cases, { name = name, bank = bank, treadmill = treadmill, console = console })
        end
        T.server(self, "setCharacterStatUntilEnd", { stat = "ENDURANCE", value = 1 })
        for _, case in ipairs(self.cases) do
            local bank, treadmill = case.bank, case.treadmill
            T.bankState(self, bank)
            T.step(function() case.before = bank.state.storedWh end)
            T.goNextTo(self, treadmill.square)
            T.server(self, "completeTreadmillRun", T.at(treadmill))
            T.step(function() case.run = self.server.completeTreadmillRun end)
            if case.name == "unwired" then
                T.perform(self, "unwireTreadmill", { source = treadmill.position })
                T.step(function() case.unwired = self.server.perform end)
            elseif case.name == "pickedUp" then
                T.pickUpAsPlayer(self, treadmill, Sprites.treadmill.W.rear)
                -- What the pickup left on the floor: the treadmill and its wire.
                T.server(self, "takeFloorItems", { squares = { treadmill.position, case.console.position } })
            end
        end
        -- The same passes on all, enough for the wired one to pay out its whole run.
        T.batch(function()
            for _, case in ipairs(self.cases) do
                T.bankPass(self, case.bank, 0, { hours = 1 / 6 })
                T.bankPass(self, case.bank, 0)
            end
        end)
    end,
    validate = function(self)
        local stored = {}
        for _, case in ipairs(self.cases) do
            expect(case.treadmill.connected, "a bank refused its wired treadmill: " .. tostring(case.treadmill.reason))
            expect(case.run.done, "the authority settled no run on the " .. case.name .. " treadmill")
            stored[case.name] = case.bank.state.storedWh - case.before
        end
        local unwired
        for _, case in ipairs(self.cases) do
            if case.name == "unwired" then unwired = case.unwired end
        end
        expect(unwired.ok, "unwiring the treadmill failed (" .. tostring(unwired.reason) .. ")")
        if not expect(stored.kept > 0, "the run on the treadmill left wired stored nothing") then return end
        T.expectNear("Wh a run stored with the treadmill unwired at once, against left wired", stored.unwired, stored.kept, 0.5)
        T.expectNear("Wh a run stored with the treadmill picked up at once, against left wired", stored.pickedUp, stored.kept, 0.5)
    end,
})

-- Picking up a wired, connected treadmill leaves the wire its wiring took on the floor and takes it
-- out of its bank, and the treadmill it becomes carries no wiring to be placed with. Catches the
-- wiring lost with nothing back, and wiring that travels with the item while its wire comes back too.
test("renewable_energy_treadmill_pickup_drops_wire", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        local treadmill = bank and T.panel(self, Sprites.treadmill.W.rear, { near = bank })
        if not treadmill then return end
        self.bank, self.treadmill = bank, treadmill
        -- Its console end, west of the rear (Sprites.treadmill).
        local square = treadmill.square
        local console = T.panel(self, Sprites.treadmill.W.console,
            { square = getSquare(square:getX() - 1, square:getY(), square:getZ()) })
        if not console then return end
        local wiring = Specs.treadmill.wiring
        T.setPerk(self, Perks.Electricity, wiring.skill)
        T.give(self, "parts", { { type = PowerBank.WIRE, count = wiring.wire }, { type = PowerBank.SCRAP, count = wiring.scrap },
            { type = "Base.Screwdriver" } })
        -- The wiring below uses the parts up; the step holds it until this client has them.
        T.step(function() end)
        carried(self, "beforeWiring")
        T.perform(self, "wireTreadmill", { source = treadmill.position })
        T.step(function() self.wired = self.server.perform end)
        carried(self, "afterWiring")
        T.perform(self, "connectSource", { bank = bank.position, source = treadmill.position })
        T.step(function() self.connected = self.server.perform end)
        T.waitFor(self, function() return PowerBank.connectedBank(treadmill.object) ~= nil end,
            "this client's copy of the wired, connected treadmill")
        T.pickUpAsPlayer(self, treadmill, Sprites.treadmill.W.rear)
        T.bankState(self, bank)
        T.server(self, "takeFloorItems", { squares = { treadmill.position, console.position } })
    end,
    validate = function(self)
        expect(self.wired.ok, "wiring the treadmill failed (" .. tostring(self.wired.reason) .. ")")
        expect(self.connected.ok, "the bank refused the wired treadmill: " .. tostring(self.connected.reason))
        expect(self.bank.state.sources == 0, "the bank still feeds from the picked-up treadmill")
        local took = self.beforeWiring.wire - self.afterWiring.wire
        local wire, wiredItems = 0, 0
        for _, item in ipairs(self.server.takeFloorItems.items) do
            if item.type == PowerBank.WIRE then
                wire = wire + 1
            elseif item.modData[Treadmill.WIRED] then
                wiredItems = wiredItems + 1
            end
        end
        expect(took > 0 and wire == took, "picking up the wired treadmill left " .. wire .. " wire, its wiring took " .. took)
        expect(wiredItems == 0, "the picked-up treadmill still carries its wiring")
    end,
})
