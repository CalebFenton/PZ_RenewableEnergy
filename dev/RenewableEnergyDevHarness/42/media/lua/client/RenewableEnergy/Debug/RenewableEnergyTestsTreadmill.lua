require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local SourceJobs = require "RenewableEnergy/PowerBank/SourceJobs"
local Wiring = require "RenewableEnergy/PowerBank/Wiring"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Specs = require "RenewableEnergy/Specs"
local Sprites = require "RenewableEnergy/Sprites"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"

-- Treadmill (PowerBank/Treadmill.lua, TreadmillSource.lua, RenewableEnergyTreadmillAction, its menu):
-- dismantling for the motor, wiring the motor, runs wired and unwired, unwiring and pickup.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect
-- A pass this long barely moves a bank's batteries.
local PASS_HOURS = 1 / 60
-- A pass too short to pay out a whole run.
local SHORT_PASS_HOURS = 1 / 6

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

-- Queues a restRunner's run on `treadmill`, with the Fitness XP before it in self.reads.beforeRun,
-- then in one batch the stats and XP expectRunTrained reads and `after`'s calls.
local function trainedRun(self, treadmill, after)
    restRunner(self)
    T.readCharacter(self, "beforeRun", { perks = { "Fitness" } })
    T.doJob(self, treadmill.square, function() return RenewableEnergyTreadmillAction:new(T.player(), treadmill.object) end)
    T.batch(function()
        T.readCharacter(self, "afterRun", { stats = { "ENDURANCE", "THIRST" }, perks = { "Fitness" } })
        after()
    end)
end

-- Expects the restRunner's run, read into self.reads.afterRun, to have cost
-- endurance, made the runner thirsty and taught Fitness beyond self.reads.beforeRun.
local function expectRunTrained(self)
    local character = self.reads.afterRun
    local stats = character and character.stats
    if expect(stats ~= nil, "no stats of the runner from the server") then
        expect(stats.ENDURANCE < 0.99, "the run cost no endurance: " .. stats.ENDURANCE)
        expect(stats.THIRST > 0.01, "the run made the runner no thirstier: " .. stats.THIRST)
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

-- Wiring a treadmill takes the Electricity level and the parts it lists; done, it uses the
-- parts and the treadmill connects to a bank like a panel. Its other tile can't be wired as well.
test("renewable_energy_treadmill_wiring_uses_parts_and_connects", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        local treadmill = bank and T.panel(self, Sprites.treadmill.W.rear, { near = bank })
        self.console = treadmill and westConsole(self, treadmill)
        if not self.console then return end
        giveWiringParts(self, 1)
        T.step(function()
            -- What the menu would show a character a level short, carrying everything.
            local restore = PZHarness.Fixtures.setPerk(T.player(), Perks.Electricity, Treadmill.SPEC.wiring.skill - 1)
            self.unskilled = Treadmill.refusal(T.player(), Treadmill.WIRE, treadmill.object)
            restore()
            self.looseWired = Treadmill.isWiredTile(treadmill.object)
        end)
        T.actionJob(self, "treadmill", treadmill, Treadmill.WIRE)
        T.waitFor(self, function() return Treadmill.isWiredTile(treadmill.object) end,
            "this client's copy of the wired treadmill")
        T.batch(function()
            T.readCarried(self, { Wiring.WIRE, Wiring.SCRAP })
            T.job(self, "source", SourceJobs.CONNECT, treadmill, bank, "connected")
            T.job(self, "treadmill", Treadmill.WIRE, self.console, nil, "again")
        end)
    end,
    validate = function(self)
        expect(not self.looseWired, "an unwired treadmill is already wired")
        T.expectEqual("the wiring refusal below the Electricity level", self.unskilled, "skill")
        T.expectEqual("wire left after wiring", #T.carriedItems(self, Wiring.WIRE), 0)
        T.expectEqual("scrap left after wiring", #T.carriedItems(self, Wiring.SCRAP), 0)
        T.expectOk(self.reads.connected, "connecting the wired treadmill")
        T.expectRefused(self.reads.again, "already wired", "wiring the treadmill's other tile too wasn't refused as already wired")
    end,
})

-- What a right-click on the treadmill tile `object` offers in its submenu: Run on Treadmill, Wire
-- the Motor and Unwire the Motor, each as T.optionState.
local function treadmillMenu(object)
    local options = T.worldOptions(object, getText("IGUI_RenewableEnergy_Treadmill"), {
        run = getText("ContextMenu_RenewableEnergy_RunOnTreadmill"),
        wire = getText("ContextMenu_RenewableEnergy_WireTreadmill"),
        unwire = getText("ContextMenu_RenewableEnergy_UnwireTreadmill"),
    }) or {}
    return { run = T.optionState(options.run), wire = T.optionState(options.wire), unwire = T.optionState(options.unwire) }
end

-- A loose treadmill offers Run on Treadmill, greyed saying it needs power while it has none and
-- open once it has, and Wire the Motor either way, greyed while the character lacks what it
-- takes, even beside a wired one. Once one tile is wired, a right-click on either tile of that
-- treadmill offers Run greyed and saying why until it is connected to a bank, and Unwire the
-- Motor, greyed for the empty-handed character with the screwdriver it takes marked short.
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
        expect(loose.wire.greyed, "an empty-handed character isn't offered Wire the Motor greyed out")
        expect(loose.run.greyed and loose.run.reason == getText("Tooltip_RenewableEnergy_TreadmillNoPower"),
            "a loose treadmill without power doesn't offer Run greyed saying it needs power")
        expect(powered.run.shown and not powered.run.greyed, "a loose treadmill on grid power doesn't offer Run open")
        expect(powered.wire.shown, "a loose treadmill on grid power doesn't offer Wire the Motor")
        expect(wired.run.greyed and wired.run.reason == getText("Tooltip_RenewableEnergy_TreadmillNotConnected"),
            "the unwired tile of a wired, unconnected treadmill doesn't offer Run greyed with the reason")
        expect(not wired.wire.shown, "a wired treadmill offers to be wired again")
        local screwdriver = ISVehicleMechanics.bhs .. getItemNameFromFullType("Base.Screwdriver")
        expect(wired.unwire.greyed and (wired.unwire.reason or ""):find(screwdriver, 1, true) ~= nil,
            "a wired treadmill doesn't offer Unwire the Motor greyed with the screwdriver marked short ("
            .. tostring(wired.unwire.reason) .. ")")
    end,
})

-- In the dark, Wire the Motor is greyed out saying it's too dark rather than listing what it
-- takes, as the other wiring menus do.
test("renewable_energy_treadmill_wiring_refused_in_the_dark", {
    run = function(self)
        self.treadmill = T.panel(self, Sprites.treadmill.E.rear)
        if self.treadmill then T.makeDark(self) end
    end,
    validate = function(self)
        if not T.expectDark() then return end
        local wire = treadmillMenu(self.treadmill.object).wire
        T.expectEqual("Wire the Motor's greyed tooltip in the dark", wire.greyed and wire.reason,
            getText("Tooltip_RenewableEnergy_TooDark"))
    end,
})

-- A run on a wired treadmill banks its watt-hours, paid out over the passes after it rather than
-- in one go, into the batteries as the status says, and costs the runner sweat and trains Fitness.
test("renewable_energy_treadmill_wired_run_pays_bank_over_passes", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER }, { charge = 0.5 })
        if not bank then return end
        local treadmill = T.panel(self, Sprites.treadmill.N.console, { near = bank, connect = true, wired = true })
        if not treadmill then return end
        self.treadmill = treadmill
        T.readRecord(self, bank, "before")
        trainedRun(self, treadmill, function()
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
        local banked = after.status.runWhToday
        if not expect(banked > 0, "the run banked nothing") then return end
        local shortWh, laterWh = short.watts * SHORT_PASS_HOURS, later.watts
        expect(shortWh > 0 and shortWh < banked, "the short pass after the run paid out " .. shortWh .. " of its "
            .. banked .. " Wh, not a part of it")
        T.expectNear("Wh the two passes paid out of the run", shortWh + laterWh, banked, 0.01)
        T.expectNear("Wh in the batteries against the run's Wh in the status",
            after.status.storedWh - before.status.storedWh, banked, 1)
        expectRunTrained(self)
    end,
})

-- A bank of L-16s with an inverter-charger, which carries whatever the test map's house has
-- switched on, a run included, switched on with the grid off, and a treadmill tile of
-- `sprite` on an indoor square it powers, wired and connected to it if `wired`. Returns both
-- handles once this client sees power on the treadmill's square, or nil.
local function poweredTreadmill(self, sprite, wired)
    T.setGrid(self, false)
    local bank = T.bank(self, "batteryRackWood", { T.L16, T.L16, T.INVERTER_CHARGER })
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
        trainedRun(self, treadmill, function() T.bankPass(self, bank, 0, { hours = PASS_HOURS }) end)
    end,
    validate = function(self)
        expectRunTrained(self)
        T.expectEqual("Wh the unwired run banked", self.bank.state.status.runWhToday, 0)
    end,
})

-- A run on an unwired treadmill a bank powers bills the treadmill's watts to that bank from when
-- the authority starts it until it settles; once the power goes out, the run can't go on.
test("renewable_energy_treadmill_unwired_run_draws_from_bank", {
    run = function(self)
        local bank, treadmill = poweredTreadmill(self, Sprites.treadmill.N.console)
        if not bank then return end
        self.bank = bank
        restRunner(self)
        T.goNextTo(self, treadmill.square)
        T.step(function() self.goesOnPower = RenewableEnergyTreadmillAction:new(T.player(), treadmill.object):isValid() end)
        T.batch(function()
            T.bankPass(self, bank, 0, { hours = PASS_HOURS, label = "before" })
            T.server(self, "startTreadmillRun", T.at(treadmill))
            T.bankPass(self, bank, 0, { hours = PASS_HOURS, label = "during" })
            T.server(self, "completeStartedTreadmillRun", T.at(treadmill))
            T.bankPass(self, bank, 0, { hours = PASS_HOURS })
        end)
        T.job(self, "bank", BankJobs.TURN_OFF, bank)
        T.waitFor(self, function() return not treadmill.square:haveElectricity() end,
            "this client's copy of the treadmill's square without power once the bank is off")
        T.step(function()
            self.goesWithoutPower = RenewableEnergyTreadmillAction:new(T.player(), treadmill.object):isValid()
        end)
    end,
    validate = function(self)
        local before, during, after = self.reads.before.status, self.reads.during.status, self.bank.state.status
        local watts = Specs.wattsFromFuel(Treadmill.SPEC.drawFuel)
        T.expectNear("W the running treadmill added to the bank's load", during.loadW - before.loadW, watts, 0.01)
        T.expectNear("W the batteries gave for the running treadmill", during.drawW - before.drawW,
            watts / Specs.inverters[T.INVERTER_CHARGER].efficiency, 0.01)
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
            T.read(self, "scanLoad", T.at(bank), "during")
            T.server(self, "completeStartedTreadmillRun", T.at(treadmill))
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.treadmill) then return end
        T.expectEqual("treadmills the wired run drew from the bank it feeds", self.reads.during.counts.treadmill or 0, 0)
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
    end,
})

-- Queues wiring the loose treadmill `treadmill` with the parts giveWiringParts gave and connecting
-- it to `bank`, as the server's character, with the parts carried before and after the wiring in
-- self.beforeWiring and self.afterWiring, the answers in self.reads.wired and self.reads.connected,
-- and a wait until this client sees it connected.
local function wireAndConnect(self, bank, treadmill)
    carriedParts(self, "beforeWiring")
    T.job(self, "treadmill", Treadmill.WIRE, treadmill, nil, "wired", { xp = { "Electricity" } })
    carriedParts(self, "afterWiring")
    T.job(self, "source", SourceJobs.CONNECT, treadmill, bank, "connected")
    T.waitFor(self, function() return PowerBank.connectedBank(treadmill.object) ~= nil end,
        "this client's copy of the wired, connected treadmill")
end

-- Unwiring a treadmill takes it out of its bank and gives back the wire its wiring took; the
-- electronics scrap stays spent, as a bank's part gives back only its wire. Wired again, it takes
-- wire and scrap again but teaches nothing more. Catches an unwire that leaves the bank feeding
-- from it or keeps the wire, and a wire-unwire loop that farms Electricity XP.
test("renewable_energy_treadmill_unwire_gives_back_wire", {
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        local treadmill = bank and T.panel(self, Sprites.treadmill.W.rear, { near = bank })
        if not treadmill then return end
        self.bank = bank
        giveWiringParts(self, 2)
        wireAndConnect(self, bank, treadmill)
        T.actionJob(self, "treadmill", treadmill, Treadmill.UNWIRE)
        T.waitFor(self, function() return not Treadmill.isWired(treadmill.object) end, "this client's copy of the unwired treadmill")
        T.readRecord(self, bank)
        carriedParts(self, "afterUnwire")
        T.job(self, "treadmill", Treadmill.WIRE, treadmill, nil, "rewired", { xp = { "Electricity" } })
    end,
    validate = function(self)
        local firstWiring, rewired = self.reads.wired, self.reads.rewired
        expect(firstWiring.ok and firstWiring.xpAfter.Electricity > firstWiring.xpBefore.Electricity, "the first wiring failed or taught nothing")
        T.expectOk(self.reads.connected, "connecting the wired treadmill")
        T.expectEqual("sources the bank feeds from after unwiring", self.bank.state.sources, 0)
        local before, wired, after = self.beforeWiring, self.afterWiring, self.afterUnwire
        expect(wired.wire < before.wire and wired.scrap < before.scrap, "wiring took no wire or no scrap")
        T.expectEqual("wire carried after unwiring, against before wiring", after.wire, before.wire)
        T.expectEqual("scrap carried after unwiring, against after wiring", after.scrap, wired.scrap)
        T.expectOk(rewired, "wiring the treadmill again")
        T.expectEqual("Electricity XP for wiring the same treadmill again", rewired.xpAfter.Electricity - rewired.xpBefore.Electricity, 0)
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
            local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER }, { charge = 0.5 })
            local treadmill = bank and T.panel(self, Sprites.treadmill.W.rear, { near = bank, connect = true, wired = true })
            -- The pickup takes both tiles.
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
            elseif case.name == "pickedUp" then
                T.pickUpAsPlayer(self, treadmill, Sprites.treadmill.W.rear)
                -- What the pickup left on the floor: the treadmill and its wire.
                T.takeFloorItems(self, { treadmill, case.console })
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
        end
        T.expectOk(self.reads.unwired, "unwiring the treadmill")
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
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        local treadmill = bank and T.panel(self, Sprites.treadmill.W.rear, { near = bank })
        -- The pickup takes both tiles.
        local console = treadmill and westConsole(self, treadmill)
        if not console then return end
        self.bank = bank
        giveWiringParts(self, 1)
        wireAndConnect(self, bank, treadmill)
        T.pickUpAsPlayer(self, treadmill, Sprites.treadmill.W.rear)
        T.readRecord(self, bank)
        T.takeFloorItems(self, { treadmill, console }, "floor")
    end,
    validate = function(self)
        T.expectOk(self.reads.wired, "wiring the treadmill")
        T.expectOk(self.reads.connected, "connecting the wired treadmill")
        T.expectEqual("sources the bank feeds from after the pickup", self.bank.state.sources, 0)
        local took = self.beforeWiring.wire - self.afterWiring.wire
        local wire, wiredItems = 0, 0
        for _, item in ipairs(self.reads.floor.items) do
            if item.type == Wiring.WIRE then
                wire = wire + 1
            elseif item.modData[Treadmill.WIRED_KEY] then
                wiredItems = wiredItems + 1
            end
        end
        expect(took > 0, "wiring the treadmill took no wire")
        T.expectEqual("wire the pickup left on the floor, against what the wiring took", wire, took)
        T.expectEqual("picked-up treadmill items still carrying their wiring", wiredItems, 0)
    end,
})
