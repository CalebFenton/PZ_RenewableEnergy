require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local Wiring = require "RenewableEnergy/PowerBank/Wiring"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Sprites = require "RenewableEnergy/Sprites"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"

-- Treadmill (PowerBank/Treadmill.lua, TreadmillSource.lua, RenewableEnergyTreadmillAction, its menu):
-- dismantling for the motor, connecting it, which wires the motor, runs wired and unwired,
-- disconnecting, which unwires it, and pickup.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect
-- A pass this long barely moves a bank's batteries.
local PASS_HOURS = 1 / 60
-- A pass too short to pay out a whole run.
local SHORT_PASS_HOURS = 1 / 6
local CONTROLLER = "RenewableEnergy.ChargeController"

-- The console tile of the west-facing treadmill whose rear tile is the handle `rear`: west of it
-- (Sprites.treadmill).
local function westConsole(self, rear)
    local square = rear.square
    return T.panel(self, Sprites.treadmill.W.console, { square = getSquare(square:getX() - 1, square:getY(), square:getZ()) })
end

-- Queues the Electricity level wiring a treadmill takes and its parts, the scrap `sets` times
-- over, with a screwdriver, which wiring uses up once this client has them.
local function giveWiringParts(self, sets)
    local wiring = Treadmill.SPEC.wiring
    T.setPerk(self, Perks.Electricity, wiring.skill)
    T.give(self, "parts", { { type = Wiring.WIRE, count = wiring.wire },
        { type = Wiring.SCRAP, count = sets * wiring.scrap }, { type = "Base.Screwdriver" } })
end

-- Queues reading the wire and scrap the authority's character carries into self[key].
local function carriedParts(self, key)
    T.readCarried(self, { Wiring.WIRE, Wiring.SCRAP })
    T.step(function()
        self[key] = { wire = #T.carriedItems(self, Wiring.WIRE), scrap = #T.carriedItems(self, Wiring.SCRAP) }
    end)
end

-- Queues a rested runner, not thirsty, until the test ends, and a wait until this client has it.
local function restRunner(self)
    T.batch(function()
        T.setStat(self, "ENDURANCE", 1)
        T.setStat(self, "THIRST", 0)
    end)
    T.waitFor(self, function() return T.player():getStats():get(CharacterStat.ENDURANCE) > 0.99 end,
        "this client's copy of the rested runner")
end

-- Expects the restRunner's whole run, read into self.reads.afterRun, to have cost its endurance and
-- thirst, by Treadmill.SPEC an hour's 0.6 and 0.2 over half an hour (0.3 and 0.1; the game's own
-- metabolism moves them a little more meanwhile), and taught Fitness beyond self.reads.beforeRun
-- (by how much is vanilla's, through its XP multipliers).
local function expectRunTrained(self)
    local character = self.reads.afterRun
    local stats = character and character.stats
    if expect(stats ~= nil, "no stats of the runner from the server") then
        T.expectNear("endurance the run cost", 1 - stats.ENDURANCE, 0.3, 0.02)
        T.expectNear("thirst the run gave", stats.THIRST, 0.1, 0.01)
    end
    expect(character and character.xp.Fitness > self.reads.beforeRun.xp.Fitness, "the run taught no Fitness")
end

-- Dismantling a treadmill gives its motor, the wind charger's generator, once: for the tile that
-- was clicked, not again for its other tile, which vanilla scraps along with it.
test("renewable_energy_treadmill_dismantle_gives_motor_once", {
    run = function(self)
        local treadmill = T.panel(self, Sprites.treadmill.W.rear)
        if not (treadmill and westConsole(self, treadmill)) then return end
        T.server(self, "scrapItems", T.at(treadmill, { sprite = Sprites.treadmill.W.rear, type = Treadmill.MOTOR }))
    end,
    validate = function(self)
        local scrap = self.server.scrapItems
        if not expect(scrap.scrapped, "dismantling the treadmill left one of its tiles standing") then return end
        T.expectEqual("motors dismantling a treadmill gave", scrap.count, 1)
    end,
})

-- Connecting a loose treadmill to a bank takes the Electricity level and its wiring's wire and
-- scrap, and teaches Electricity; done, the treadmill is wired and feeds the bank, and its other
-- tile can't be connected as well. Disconnecting it (Unwire, so labelled while it feeds a bank)
-- takes it out of its bank and gives back the wire; the electronics scrap stays spent, as a bank's
-- part gives back only its wire. Connected again, it takes wire and scrap again but teaches nothing
-- more. Catches a disconnect that leaves the bank feeding from it or keeps the wire, and a
-- connect-disconnect loop that farms Electricity XP.
test("renewable_energy_treadmill_connect_wires_and_disconnect_gives_back_wire", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        local treadmill = bank and T.panel(self, Sprites.treadmill.W.rear, { near = bank })
        local console = treadmill and westConsole(self, treadmill)
        if not console then return end
        self.bank = bank
        giveWiringParts(self, 2)
        T.step(function()
            -- What the menu would show a character a level short, carrying everything.
            local restore = PZHarness.Fixtures.setPerk(T.player(), Perks.Electricity, Treadmill.SPEC.wiring.skill - 1)
            self.unskilled = Treadmill.refusal(T.player(), Treadmill.CONNECT, treadmill.object, bank.object)
            restore()
        end)
        carriedParts(self, "beforeWiring")
        T.readCharacter(self, "beforeConnect", { perks = { "Electricity" } })
        T.actionJob(self, "treadmill", treadmill, Treadmill.CONNECT, bank)
        T.waitFor(self, function() return PowerBank.connectedBank(treadmill.object) ~= nil end,
            "this client's copy of the wired, connected treadmill")
        T.readCharacter(self, "afterConnect", { perks = { "Electricity" } })
        carriedParts(self, "afterWiring")
        T.job(self, "treadmill", Treadmill.CONNECT, console, bank, "again")
        T.actionJob(self, "treadmill", treadmill, Treadmill.UNWIRE)
        T.waitFor(self, function() return not Treadmill.isWired(treadmill.object) end, "this client's copy of the unwired treadmill")
        T.readRecord(self, bank)
        carriedParts(self, "afterUnwire")
        T.job(self, "treadmill", Treadmill.CONNECT, treadmill, bank, "reconnected", { xp = { "Electricity" } })
    end,
    validate = function(self)
        local wiring, reads = Treadmill.SPEC.wiring, self.reads
        T.expectEqual("the connect refusal below the Electricity level", self.unskilled, "skill")
        local before, wired, after = self.beforeWiring, self.afterWiring, self.afterUnwire
        T.expectEqual("wire connecting took", before.wire - wired.wire, wiring.wire)
        T.expectEqual("scrap connecting took", before.scrap - wired.scrap, wiring.scrap)
        expect(reads.afterConnect.xp.Electricity > reads.beforeConnect.xp.Electricity, "the first connection taught no Electricity")
        T.expectRefused(reads.again, "already wired", "connecting the treadmill's other tile too wasn't refused as already wired")
        T.expectEqual("sources the bank feeds from after disconnecting", self.bank.state.sources, 0)
        T.expectEqual("wire carried after disconnecting, against before connecting", after.wire, before.wire)
        T.expectEqual("scrap carried after disconnecting, against after connecting", after.scrap, wired.scrap)
        T.expectOk(reads.reconnected, "connecting the treadmill again")
        T.expectEqual("Electricity XP for connecting the same treadmill again",
            reads.reconnected.xpAfter.Electricity - reads.reconnected.xpBefore.Electricity, 0)
    end,
})

-- What a right-click on the treadmill tile `object` offers in its submenu: Run on Treadmill,
-- Connect to a Battery Bank (with no bank in reach) and Unwire the Motor, each as T.optionState.
local function treadmillMenu(object)
    local options = T.worldOptions(object, getText("IGUI_RenewableEnergy_Treadmill"), {
        run = getText("ContextMenu_RenewableEnergy_RunOnTreadmill"),
        connect = getText("ContextMenu_RenewableEnergy_ConnectToBank"),
        unwire = getText("ContextMenu_RenewableEnergy_UnwireTreadmill"),
    }) or {}
    return { run = T.optionState(options.run), connect = T.optionState(options.connect), unwire = T.optionState(options.unwire) }
end

-- With no bank in reach, a loose treadmill offers Run on Treadmill, greyed saying it needs power
-- while it has none and open once it has, and Connect to a Battery Bank greyed saying there's no
-- bank in reach. A treadmill left wired without a bank, right-clicked on either tile, offers Run
-- greyed saying why and Unwire the Motor, greyed for the empty-handed character with the
-- screwdriver it takes marked short.
test("renewable_energy_treadmill_menu_offers_run_and_connect", {
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
        expect(loose.connect.greyed and loose.connect.reason == getText("Tooltip_RenewableEnergy_NoBankInReach"),
            "a loose treadmill with no bank in reach doesn't offer Connect greyed saying so")
        expect(not loose.unwire.shown, "a loose treadmill offers to be unwired")
        expect(loose.run.greyed and (loose.run.reason or ""):find(getText("Tooltip_RenewableEnergy_TreadmillNoPower"), 1, true) ~= nil,
            "a loose treadmill without power doesn't offer Run greyed saying it needs power")
        expect(powered.run.shown and not powered.run.greyed, "a loose treadmill on grid power doesn't offer Run open")
        expect(wired.run.greyed and (wired.run.reason or ""):find(getText("Tooltip_RenewableEnergy_TreadmillNotConnected"), 1, true) ~= nil,
            "the unwired tile of a wired, unconnected treadmill doesn't offer Run greyed with the reason")
        local screwdriver = ISVehicleMechanics.bhs .. getItemNameFromFullType("Base.Screwdriver")
        expect(wired.unwire.greyed and (wired.unwire.reason or ""):find(screwdriver, 1, true) ~= nil,
            "a wired treadmill doesn't offer Unwire the Motor greyed with the screwdriver marked short ("
            .. tostring(wired.unwire.reason) .. ")")
    end,
})

-- A run on a wired treadmill banks a run's 120 Wh (Treadmill.SPEC: 240 W for 30 minutes), paid out
-- at no more than 240 W over the passes after it rather than in one go: 40 Wh in a sixth of an
-- hour, the other 80 in the next, into the batteries as the status says; and it costs the runner
-- sweat and trains Fitness.
test("renewable_energy_treadmill_wired_run_pays_bank_over_passes", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER }, { charge = 0.5 })
        if not bank then return end
        local treadmill = T.panel(self, Sprites.treadmill.N.console, { near = bank, connect = true, wired = true })
        if not treadmill then return end
        self.treadmill = treadmill
        T.readRecord(self, bank, "before")
        restRunner(self)
        T.readCharacter(self, "beforeRun", { perks = { "Fitness" } })
        T.doJob(self, treadmill.square, function() return RenewableEnergyTreadmillAction:new(T.player(), treadmill.object) end)
        T.batch(function()
            T.readCharacter(self, "afterRun", { stats = { "ENDURANCE", "THIRST" }, perks = { "Fitness" } })
            -- A short pass, then a long one that pays out the rest.
            T.bankPass(self, bank, 0, { hours = SHORT_PASS_HOURS, label = "short" })
            T.bankPass(self, bank, 0, { label = "after" })
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.treadmill) then return end
        local before, after = self.reads.before, self.reads.after
        local short = T.findIn(self.reads.short.status.sources, "kind", "treadmill")
        local later = T.findIn(after.status.sources, "kind", "treadmill")
        if not expect(short ~= nil and later ~= nil, "the bank's status lists no treadmill") then return end
        T.expectNear("Wh the run banked", after.status.runWhToday, 120, 0.01)
        T.expectNear("Wh the sixth of an hour after the run paid out", short.watts * SHORT_PASS_HOURS, 40, 0.01)
        T.expectNear("Wh the hour after that paid out", later.watts, 80, 0.01)
        T.expectNear("Wh in the batteries after both passes", after.status.storedWh - before.status.storedWh, 120, 1)
        expectRunTrained(self)
    end,
})

-- Treadmills a bank of L-16s with an inverter-charger powers, the grid off. A run on an unwired one
-- bills its motor to that bank from when the authority starts it until it settles, as vanilla bills
-- a washer: 0.09 fuel an hour at 2000 W a unit (Specs.wattsPerFuel), 180 W of load and 200 W from
-- the batteries through the inverter's 90%; once the power goes out a run can't go on. A run on one
-- wired to that bank draws nothing. Each run is stopped halfway, as the server stops a client's
-- action, and settles half of one (Treadmill.SPEC: 30 minutes, 0.6 endurance an hour, so 0.15):
-- the unwired one's draw ends and it banks nothing; the wired one banks half a run's 120 Wh, which
-- the next hour pays out at 60 W. Catches a wired run billed as a load, a part run paid in full or
-- not at all, and a stopped run left drawing.
test("renewable_energy_treadmill_runs_draw_unwired_and_settle_their_share", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { T.L16, T.L16, T.INVERTER_CHARGER }, { charge = 0.5 })
        local squares = bank and T.squares(self, 2, { indoors = true, near = bank })
        if not T.need(self, squares, "free indoor squares for two treadmills") then return end
        local unwired = T.panel(self, Sprites.treadmill.N.console, { square = squares[1] })
        local wired = T.panel(self, Sprites.treadmill.N.console, { square = squares[2], near = bank, connect = true, wired = true })
        if not (unwired and wired) then return end
        self.wired = wired
        T.switchOn(self, bank)
        T.waitFor(self, function() return unwired.square:haveElectricity() end,
            "power from the switched-on bank on the treadmill's square here")
        restRunner(self)
        T.goNextTo(self, unwired.square)
        T.step(function() self.goesOnPower = RenewableEnergyTreadmillAction:new(T.player(), unwired.object):isValid() end)
        T.batch(function()
            T.bankPass(self, bank, 0, { hours = PASS_HOURS, label = "before" })
            T.server(self, "startTreadmillRun", T.at(unwired))
            T.read(self, "scanLoad", T.at(bank), "unwiredLoad")
            T.bankPass(self, bank, 0, { hours = PASS_HOURS, label = "during" })
            T.read(self, "completeStartedTreadmillRun", T.at(unwired, { progress = 0.5 }), "unwiredRun")
            T.read(self, "scanLoad", T.at(bank), "stoppedLoad")
            T.bankPass(self, bank, 0, { hours = PASS_HOURS, label = "after" })
        end)
        restRunner(self)
        T.goNextTo(self, wired.square)
        T.batch(function()
            T.server(self, "startTreadmillRun", T.at(wired))
            T.read(self, "scanLoad", T.at(bank), "wiredLoad")
            T.read(self, "completeStartedTreadmillRun", T.at(wired, { progress = 0.5 }), "wiredRun")
            -- An hour: long enough to pay out all a half run banked.
            T.bankPass(self, bank, 0, { label = "paid" })
        end)
        T.job(self, "bank", BankJobs.TURN_OFF, bank)
        T.waitFor(self, function() return not unwired.square:haveElectricity() end,
            "this client's copy of the treadmill's square without power once the bank is off")
        T.step(function()
            self.goesWithoutPower = RenewableEnergyTreadmillAction:new(T.player(), unwired.object):isValid()
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.wired) then return end
        local reads = self.reads
        local before, during, after, paid = reads.before.status, reads.during.status, reads.after.status, reads.paid.status
        expect(self.goesOnPower, "a run on a powered, unwired treadmill can't go")
        T.expectEqual("treadmills the unwired run drew through", reads.unwiredLoad.counts.treadmill, 1)
        T.expectNear("W the running treadmill added to the bank's load", during.loadW - before.loadW, 180, 0.01)
        T.expectNear("W the batteries gave for the running treadmill", during.drawW - before.drawW, 200, 0.01)
        T.expectEqual("treadmills drawing once the unwired run stopped", reads.stoppedLoad.counts.treadmill or 0, 0)
        T.expectNear("W of the bank's load after the run, against before it", after.loadW - before.loadW, 0, 0.01)
        T.expectEqual("Wh the unwired run banked", after.runWhToday, 0)
        expect(not self.goesWithoutPower, "a run on an unwired treadmill goes on once its power is out")
        T.expectEqual("treadmills the wired run drew from the bank it feeds", reads.wiredLoad.counts.treadmill or 0, 0)
        for _, name in ipairs({ "unwiredRun", "wiredRun" }) do
            local run = reads[name]
            T.expectNear("endurance half the " .. name .. " cost", run.enduranceBefore - run.enduranceAfter, 0.15, 0.001)
        end
        T.expectNear("Wh half the wired run banked", paid.runWhToday - after.runWhToday, 60, 0.01)
        local treadmill = T.findIn(paid.sources, "kind", "treadmill")
        if expect(treadmill ~= nil, "the bank's status lists no treadmill") then
            T.expectNear("W the wired treadmill paid out over the hour after its half run", treadmill.watts, 60, 0.01)
        end
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
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        local treadmill = bank and T.panel(self, Sprites.treadmill.N.console, { near = bank, connect = true, wired = true })
        if not treadmill then return end
        self.treadmill = treadmill
        T.setStat(self, "ENDURANCE", 1)
        T.goNextTo(self, treadmill.square)
        T.job(self, "source", SourceJobs.DISCONNECT, treadmill)
        T.waitFor(self, function() return PowerBank.connectedBank(treadmill.object) == nil end,
            "this client's copy of the disconnected treadmill")
        T.step(function() self.refusal = Treadmill.runRefusal(treadmill.object) end)
        T.batch(function()
            T.read(self, "completeTreadmillRun", T.at(treadmill), "unconnected")
            T.job(self, "source", SourceJobs.CONNECT, treadmill, bank)
            T.read(self, "completeTreadmillRun", T.at(treadmill), "connected")
        end)
    end,
    validate = function(self)
        T.expectEqual("the run refusal on a disconnected treadmill", self.refusal, "Tooltip_RenewableEnergy_TreadmillNotConnected")
        local idle, ran = self.reads.unconnected, self.reads.connected
        expect(not idle.done, "the authority settled a run on a treadmill that feeds no bank")
        T.expectEqual("Fitness XP from a run on a disconnected treadmill", idle.xpAfter - idle.xpBefore, 0)
        T.expectEqual("endurance a run on a disconnected treadmill cost", idle.enduranceBefore - idle.enduranceAfter, 0)
        expect(ran.done and ran.xpAfter > ran.xpBefore, "connected again, the authority's run settled nothing")
        T.expectNear("endurance the run cost connected again", ran.enduranceBefore - ran.enduranceAfter, 0.3, 0.001)
    end,
})

-- A run on a wired treadmill past its bank's inputs still tires the runner, but its watt-hours are
-- lost rather than kept for later: a rack's controller takes a flat panel, a scoop rotor and the
-- treadmill, and worn out it leaves the rack its 2 free slots, which the panel and the scoop,
-- connected first, take. The run settles, costing its 0.3 endurance (Treadmill.SPEC: 0.6 an hour,
-- 30 minutes), the next pass pays the treadmill nothing for want of an input, and once the
-- controller is mended the pass after pays nothing of that run either.
test("renewable_energy_treadmill_run_past_the_inputs_is_lost", {
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER, CONTROLLER })
        if not bank then return end
        T.batch(function()
            self.panel = T.panel(self, Sprites.flat, { near = bank, connect = true })
            self.scoop = T.panel(self, Sprites.windScoop, { near = bank, connect = true })
        end)
        self.treadmill = T.panel(self, Sprites.treadmill.N.console, { near = bank, connect = true, wired = true })
        if not (self.panel and self.scoop and self.treadmill) then return end
        T.setStat(self, "ENDURANCE", 1)
        T.goNextTo(self, self.treadmill.square)
        T.batch(function()
            T.bankPart(self, bank, CONTROLLER, { condition = 0, recount = true })
            T.read(self, "completeTreadmillRun", T.at(self.treadmill), "run")
            T.bankPass(self, bank, 0, { label = "starved" })
            T.bankPart(self, bank, CONTROLLER, { condition = 100, recount = true })
            T.bankPass(self, bank, 0, { label = "mended" })
        end)
    end,
    validate = function(self)
        for _, handle in ipairs({ self.panel, self.scoop, self.treadmill }) do
            if not T.expectConnected(handle) then return end
        end
        local run = self.reads.run
        expect(run.done, "the authority settled no run on a treadmill past its bank's inputs")
        T.expectNear("endurance the run cost", run.enduranceBefore - run.enduranceAfter, 0.3, 0.001)
        for label, reason in pairs({ starved = "noController", mended = "idle" }) do
            local treadmill = T.stateSource(self.reads[label], self.treadmill)
            if expect(treadmill ~= nil, "the bank's " .. label .. " status lists no treadmill") then
                T.expectEqual("the treadmill's watts " .. label, treadmill.watts, 0)
                T.expectEqual("the treadmill's reason " .. label, treadmill.reason, reason)
                T.expectEqual("Wh the run banked " .. label, self.reads[label].status.runWhToday, 0)
            end
        end
    end,
})

-- Counts, in the floor items `items` (a T.takeFloorItems read's), the Electric Wire and the
-- treadmill items still carrying their wiring.
local function wireAndWired(items)
    local wire, wired = 0, 0
    for _, item in ipairs(items) do
        if item.type == Wiring.WIRE then
            wire = wire + 1
        elseif item.modData[Treadmill.WIRED_KEY] then
            wired = wired + 1
        end
    end
    return wire, wired
end

-- What a run banked that the passes haven't paid out yet goes into the batteries when the treadmill
-- is unwired or smashed: the same run on a treadmill unwired at once, on one smashed at once and
-- on one left wired, with the same passes after, stores a whole run's 120 Wh (Treadmill.SPEC: 240 W
-- for 30 minutes) each. Smashing it leaves the 2 wire its wiring took on the floor. Catches
-- unwiring or smashing a treadmill right after a run forfeiting the run, at once or at the next
-- pass, and a smash that loses the wire.
test("renewable_energy_treadmill_unwire_keeps_the_run", {
    instant = true,
    run = function(self)
        self.cases = {}
        for _, name in ipairs({ "kept", "unwired", "smashed" }) do
            local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER }, { charge = 0.5 })
            local treadmill = bank and T.panel(self, Sprites.treadmill.W.rear, { near = bank, connect = true, wired = true })
            -- The sledgehammer takes both tiles.
            local console = treadmill and westConsole(self, treadmill)
            if not console then return end
            table.insert(self.cases, { name = name, bank = bank, treadmill = treadmill, console = console })
        end
        T.setStat(self, "ENDURANCE", 1)
        T.give(self, "screwdriver", { { type = "Base.Screwdriver" } })
        for _, case in ipairs(self.cases) do
            local bank, treadmill = case.bank, case.treadmill
            T.readRecord(self, bank, case.name .. "Before")
            T.goNextTo(self, treadmill.square)
            T.read(self, "completeTreadmillRun", T.at(treadmill), case.name .. "Run")
            if case.name == "unwired" then
                T.job(self, "treadmill", Treadmill.UNWIRE, treadmill, nil, "unwired")
            elseif case.name == "smashed" then
                T.smash(self, treadmill, Treadmill.isWiredTile, "wired treadmill")
                T.takeFloorItems(self, { treadmill, case.console }, "floor")
            end
        end
        -- The same passes on all, enough for the wired one to pay out its whole run.
        T.batch(function()
            for _, case in ipairs(self.cases) do
                T.bankPass(self, case.bank, 0, { hours = SHORT_PASS_HOURS })
                T.bankPass(self, case.bank, 0)
            end
        end)
    end,
    validate = function(self)
        local stored = {}
        for _, case in ipairs(self.cases) do
            expect(case.treadmill.connected, "a bank refused its wired treadmill: " .. tostring(case.treadmill.reason))
            expect(self.reads[case.name .. "Run"].done, "the authority settled no run on the " .. case.name .. " treadmill")
            stored[case.name] = case.bank.state.storedWh - self.reads[case.name .. "Before"].storedWh
            T.expectEqual("sources the bank of the " .. case.name .. " treadmill feeds from", case.bank.state.sources,
                case.name == "kept" and 1 or 0)
        end
        T.expectOk(self.reads.unwired, "unwiring the treadmill")
        for _, name in ipairs({ "kept", "unwired", "smashed" }) do
            T.expectNear("Wh the run on the " .. name .. " treadmill stored", stored[name], 120, 1)
        end
        local wire = wireAndWired(self.reads.floor.items)
        T.expectEqual("wire the smash left on the floor", wire, 2)
    end,
})

-- A treadmill left wired without a bank picks up unwired: the wire its wiring took lands on the
-- floor, and the treadmill it becomes carries no wiring to be placed with. Catches a pickup that
-- loses the wire or lets wiring travel with the item.
test("renewable_energy_treadmill_wired_pick_up_leaves_wire", {
    instant = true,
    run = function(self)
        local treadmill = T.panel(self, Sprites.treadmill.W.rear, { wired = true })
        -- The pickup takes both tiles.
        local console = treadmill and westConsole(self, treadmill)
        if not console then return end
        T.give(self, "screwdriver", { { type = "Base.Screwdriver" } })
        T.pickUpAsPlayer(self, treadmill, Sprites.treadmill.W.rear)
        -- What the pickup left on the floor: the treadmill and its wire.
        T.takeFloorItems(self, { treadmill, console }, "floor")
    end,
    validate = function(self)
        local wire, wired = wireAndWired(self.reads.floor.items)
        T.expectEqual("wire the pickup left on the floor, against what wiring takes", wire, Treadmill.SPEC.wiring.wire)
        T.expectEqual("picked-up treadmill items still carrying their wiring", wired, 0)
    end,
})
