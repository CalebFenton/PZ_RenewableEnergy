require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Vanilla's treadmill as a source for a bank: dismantled for its motor, or wired to a bank and run
-- on.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect
local Specs, Sprites = RenewableEnergy.Specs, RenewableEnergy.Sprites
local PowerBank, Treadmill = RenewableEnergy.PowerBank, RenewableEnergy.Treadmill

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
        option = menu and menu:getOptionFromName(getText("ContextMenu_RenewableEnergy_UnwireTreadmill"))
        expect(option ~= nil and not option.notAvailable, "a wired treadmill doesn't offer Unwire")
        if context then context:hideAndChildren() end
    end,
})

-- In the dark, Wire to Bank on a treadmill is greyed out saying it's too dark, not with the list
-- of what it takes, which the character can't fix by carrying more. Catches the light check
-- missing from the treadmill's menu, as the other wiring menus have it.
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

-- Unwiring a treadmill takes it out of its bank and gives back its wire; the electronics scrap
-- stays spent, as a bank's part gives back only its wire. Wired again, it takes wire and scrap
-- again but teaches nothing more. Catches an unwire that leaves the bank feeding from it or keeps
-- the wire, and a wire-unwire loop that farms Electricity XP.
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
        T.perform(self, "wireTreadmill", { source = treadmill.position })
        T.step(function() self.wired = self.server.perform end)
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
        local wiring = Specs.treadmill.wiring
        expect(self.wired.ok and self.wired.xpAfter > self.wired.xpBefore, "the first wiring failed or taught nothing")
        expect(self.bank.state.sources == 0, "the bank still feeds from the unwired treadmill")
        local after = self.afterUnwire
        expect(after.wire == wiring.wire and after.scrap == wiring.scrap, "unwiring left " .. after.wire .. " wire and "
            .. after.scrap .. " scrap, expected the " .. wiring.wire .. " wire back and the spent scrap not")
        expect(self.rewired.ok, "wiring the treadmill again failed (" .. tostring(self.rewired.reason) .. ")")
        T.expectNear("Electricity XP for wiring the same treadmill again", self.rewired.xpAfter - self.rewired.xpBefore, 0, 0)
    end,
})

-- What a run banked that the passes haven't paid out yet goes into the batteries when the treadmill
-- is unwired, as it would have over the passes. Catches unwiring, moving or picking up a treadmill
-- right after a run forfeiting the run.
test("renewable_energy_treadmill_unwire_keeps_the_run", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER }, { charge = 0.5 })
        local treadmill = bank and T.panel(self, Sprites.treadmill.N.console, { near = bank, connect = true, wired = true })
        if not treadmill then return end
        self.bank, self.treadmill = bank, treadmill
        T.goNextTo(self, treadmill.square)
        T.bankState(self, bank)
        T.step(function() self.before = bank.state end)
        T.server(self, "completeTreadmillRun", T.at(treadmill))
        T.perform(self, "unwireTreadmill", { source = treadmill.position })
        T.step(function() self.unwired = self.server.perform end)
        T.bankState(self, bank)
    end,
    validate = function(self)
        expect(self.treadmill.connected, "the bank refused the wired treadmill: " .. tostring(self.treadmill.reason))
        expect(self.server.completeTreadmillRun.done, "the authority settled no run")
        expect(self.unwired.ok, "unwiring the treadmill failed (" .. tostring(self.unwired.reason) .. ")")
        local spec = Specs.treadmill
        T.expectNear("Wh in the batteries from the run once the treadmill was unwired",
            self.bank.state.storedWh - self.before.storedWh, spec.watts * spec.runMinutes / 60, 1)
    end,
})

-- Picking up a wired, connected treadmill leaves its wire on the floor and takes it out of its
-- bank, and the treadmill it becomes carries no wiring to be placed with. Catches the wiring lost
-- with nothing back, and wiring that travels with the item while its wire comes back too.
test("renewable_energy_treadmill_pickup_drops_wire", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, INVERTER })
        local treadmill = bank and T.panel(self, Sprites.treadmill.W.rear, { near = bank, connect = true, wired = true })
        if not treadmill then return end
        self.bank, self.treadmill = bank, treadmill
        -- Its console end, west of the rear (Sprites.treadmill).
        local square = treadmill.square
        local console = T.panel(self, Sprites.treadmill.W.console,
            { square = getSquare(square:getX() - 1, square:getY(), square:getZ()) })
        if not console then return end
        T.pickUpAsPlayer(self, treadmill, Sprites.treadmill.W.rear)
        T.bankState(self, bank)
        T.server(self, "takeFloorItems", { squares = { treadmill.position, console.position } })
    end,
    validate = function(self)
        expect(self.treadmill.connected, "the bank refused the wired treadmill: " .. tostring(self.treadmill.reason))
        expect(self.bank.state.sources == 0, "the bank still feeds from the picked-up treadmill")
        local wire, wiredItems = 0, 0
        for _, item in ipairs(self.server.takeFloorItems.items) do
            if item.type == PowerBank.WIRE then
                wire = wire + 1
            elseif item.modData[Treadmill.WIRED] then
                wiredItems = wiredItems + 1
            end
        end
        expect(wire == Specs.treadmill.wiring.wire, "picking up the wired treadmill left " .. wire .. " wire, expected "
            .. Specs.treadmill.wiring.wire)
        expect(wiredItems == 0, "the picked-up treadmill still carries its wiring")
    end,
})
