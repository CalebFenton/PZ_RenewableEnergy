require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/StatusRows"

-- Power bank tests (PowerBank/* and the bank rows of Specs.lua), split by topic across
-- RenewableEnergyTestsBank*.lua; this file has charging, loads, inverters and turning on. Banks
-- live on the authority: the helpers drive and read its record through T.server; what players
-- see is checked on this client's copies.

local T = RenewableEnergyTest
local test, expect, expectNear, player, stateItem, copyItem = T.test, T.expect, T.expectNear, T.player, T.stateItem, T.copyItem
local Action = RenewableEnergyAction
local Specs, Sprites, Sun = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun
local PowerBank = RenewableEnergy.PowerBank
local StatusRows = RenewableEnergy.StatusRows
local FRIDGE = "appliances_refrigeration_01_0"
local CAR_BATTERY = RenewableEnergy.VehicleBattery.CAR_BATTERY
local PLUG_IN_INVERTER, POWER_INVERTER, INVERTER_CHARGER, L16 = T.PLUG_IN_INVERTER, T.POWER_INVERTER, T.INVERTER_CHARGER, T.L16

-- Charging and loads ---------------------------------------------------------------------------

-- An hour of full sun on a connected panel charges the bank by what the panel makes, and the
-- charge, the status and the tile's battery overlays reach this client's copies.
test("renewable_energy_bank_panel_charges_bank", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY }, { charge = 0.2 })
        self.panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not self.panel then return end
        self.bank = bank
        T.watch(self, bank)
        T.bankState(self, bank)
        T.step(function() self.before = bank.state end)
        T.bankPass(self, bank, Sun.FULL_SUN)
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return math.abs(T.copyUses(bank, CAR_BATTERY) - bank.state.charge) < 0.001
                and status ~= nil and status.solarW == bank.state.status.solarW
                and table.concat(T.overlaysOf(bank.object), ",") == table.concat(bank.state.overlays, ",")
        end, "this client's copies of the charged battery, the status and the overlays")
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        -- The run's last wait already failed the test if this client's copies differ from the server's.
        local after = self.bank.state
        local status = after.status
        -- How watts follow the sun is renewable_energy_solar_sun_watts_multiplier_snow_roof's.
        expect(status.solarW > 0, "a connected panel in full sun makes nothing")
        expectNear("Wh gained in an hour", after.storedWh - self.before.storedWh, status.solarW, 0.5)
        expectNear("percent of full sun", status.sources[1] and status.sources[1].fullSunPct, 100, 0)
        local battery = stateItem(after, CAR_BATTERY)
        expectNear("the battery's charge", battery and battery.uses, after.charge, 0.001)
        expect(table.concat(after.overlays, ",") ~= "", "the charged bank's tile shows no batteries")
    end,
})

-- At night a bank that is on powers its squares, here too, and pays its inverter's idle draw and
-- losses on top of the appliances its pass finds; the pass takes that draw from the batteries.
test("renewable_energy_bank_powers_at_night", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { L16, L16, INVERTER_CHARGER })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        self.bank = bank
        T.switchOn(self, bank)
        T.bankState(self, bank)
        T.waitFor(self, function() return bank.square:haveElectricity() end, "power on the switched-on bank's square here")
        T.step(function() self.powered = bank.state.activated and bank.state.powered end)
        T.bankPass(self, bank, 0)
        T.step(function() self.without = bank.state end)
        -- A step, since single player places a tile at once.
        T.step(function() T.placeTile(self, fridge, T.MINI_FRIDGE) end)
        T.batch(function()
            T.bankPass(self, bank, 0)
            T.step(function() self.with = bank.state end)
            T.bankPass(self, bank, 0)
        end)
    end,
    validate = function(self)
        local after, without, with = self.bank.state, self.without.status, self.with.status
        expect(self.powered, "switching on a charged bank with an inverter did not power its square")
        expect(without.drawW > 0, "a bank that is on with nothing switched on draws nothing for its inverter")
        expect(with.drawW - without.drawW > T.fridgeW(), string.format(
            "a fridge drawing %.1f W adds %.1f W to the draw, no inverter losses", T.fridgeW(), with.drawW - without.drawW))
        expectNear("Wh used in an hour", self.with.storedWh - after.storedWh, after.status.drawW, 0.5)
        local charging = after.status.charging
        expect(charging.watts < 0 and charging.hours ~= nil, "the status doesn't say the bank is draining")
    end,
})

-- While the grid still powers its square, a bank that is on stands by: its generator stays off and
-- its batteries carry nothing, so through a night they don't drain or wear, and its inverter/charger
-- fills them from the grid. It still measures what is switched on in its reach, the same load it
-- carries once the grid goes, at its next pass.
test("renewable_energy_bank_stands_by_on_the_grid", {
    run = function(self)
        T.setGrid(self, true)
        local bank = T.bank(self, "batteryRackWood", { L16, L16, INVERTER_CHARGER }, { charge = 0.5 })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        self.bank = bank
        T.step(function() T.need(self, bank.square:hasGridPower(), "grid power on the bank's square") end)
        T.switchOn(self, bank)
        T.step(function() T.placeTile(self, fridge, T.MINI_FRIDGE) end)
        T.bankPass(self, bank, 0, { hours = 12 })
        T.step(function()
            self.onGrid = bank.state
            T.setGrid(self, false)
        end)
        T.bankPass(self, bank, 0)
        T.step(function() self.offGrid = bank.state end)
    end,
    validate = function(self)
        local onGrid, offGrid = self.onGrid, self.offGrid
        expect(onGrid.status.state == "grid", "a switched-on bank on the grid reads " .. tostring(onGrid.status.state))
        expect(not onGrid.activated, "the bank ran its own generator while the grid powered its square")
        expectNear("the bank's draw on the grid", onGrid.drawW, 0, 0)
        expect(onGrid.status.loadW >= T.fridgeW(), string.format(
            "on the grid the bank measures a load of %.1f W with a fridge on", onGrid.status.loadW))
        expectNear("the load the bank measured on the grid, against the one it carries after", onGrid.status.loadW,
            offGrid.status.loadW, 0)
        expectNear("the bank's deepest drop after a night on the grid", onGrid.cycleDepth, 0, 0)
        expect(onGrid.status.chargeSource == "grid" and onGrid.charge > 0.5, string.format(
            "on the grid the chargers charge from %s and the bank's charge went from 0.5 to %.3f", tostring(onGrid.status.chargeSource), onGrid.charge))
        expect(offGrid.activated and offGrid.drawW > 0, string.format("with the grid gone the bank reads %s, powers %s and draws %.1f W for a load of %.1f W",
            tostring(offGrid.status.state), tostring(offGrid.activated), offGrid.drawW, offGrid.status.loadW))
        expect(offGrid.charge < onGrid.charge, "with the grid gone the bank's charge didn't fall")
    end,
})

-- The scan sees what is switched on whether or not the bank powers it, so a cut bank knows when
-- the load fits again; and, as vanilla bills them, a mini fridge with its ice box is a fridge-freezer.
test("renewable_energy_bank_scan_sees_load_while_off", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, PLUG_IN_INVERTER })
        if not bank then return end
        local squares = T.need(self, T.squares(self, 2, { indoors = true, near = bank.square }), "two free indoor squares for fridges")
        if not squares then return end
        T.serverInto(self, "without", "scanLoad", bank.position)
        T.step(function()
            T.placeTile(self, squares[1], FRIDGE)
            T.placeTile(self, squares[2], T.MINI_FRIDGE)
            T.server(self, "scanLoad", bank.position)
        end)
    end,
    validate = function(self)
        local with, without = self.server.scanLoad, self.without
        local function count(load, kind)
            return load.counts[kind] or 0
        end
        expectNear("fridge-freezers found, the mini fridge among them",
            count(with, "fridgeFreezer") - count(without, "fridgeFreezer"), 2, 0)
        expect(with.watts > without.watts, "the fridges added no watts to the scan's load")
    end,
})

-- The kind and draw the stand-in for another mod's appliance reports, a Pump House's in generator
-- fuel an hour; the status lists a kind it doesn't know as other.
local CONSUMER_KIND, CONSUMER_FUEL = "testConsumer", 0.2

-- Another mod's appliance in a bank's reach (Loads.addConsumer) is in the bank's load at the draw
-- its mod reports, under the mod's own kind, and not while it reports none. Catches a scan that
-- never asks another mod, or bills its appliance switched off.
test("renewable_energy_bank_bills_another_mods_appliance", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, PLUG_IN_INVERTER })
        local square = bank and T.square(self, { indoors = true, near = bank.square }, "a free indoor square for the appliance")
        if not square then return end
        T.server(self, "drawAt", T.at(square, { kind = CONSUMER_KIND, fuel = 0 }))
        T.serverInto(self, "off", "scanLoad", bank.position)
        T.server(self, "drawAt", T.at(square, { kind = CONSUMER_KIND, fuel = CONSUMER_FUEL }))
        T.server(self, "scanLoad", bank.position)
    end,
    validate = function(self)
        local on, off = self.server.scanLoad, self.off
        expect((off.counts[CONSUMER_KIND] or 0) == 0, "the scan bills an appliance that draws nothing")
        expect(on.counts[CONSUMER_KIND] == 1, "the scan lists the drawing appliance " .. tostring(on.counts[CONSUMER_KIND]) .. " times")
        expectNear("the watts it adds", on.watts - off.watts, Specs.wattsFromFuel(CONSUMER_FUEL), 0.01)
    end,
})

-- Banks stand indoors only: placement is refused outdoors, and a bank found outdoors won't
-- switch on.
test("renewable_energy_bank_refused_outdoors", {
    run = function(self)
        T.setGrid(self, false)
        local indoor = T.square(self, { indoors = true }, "a free indoor square")
        local outdoor = T.square(self, {}, "a free outdoor square")
        if not (indoor and outdoor) then return end
        self.indoorOk = PowerBank.canPlaceBank(indoor)
        self.outdoorOk, self.reason = PowerBank.canPlaceBank(outdoor)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, PLUG_IN_INVERTER }, { square = outdoor })
        if not bank then return end
        self.bank = bank
        T.watch(self, bank)
        T.perform(self, "setBankOn", { bank = bank.position, on = true })
        T.bankState(self, bank)
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return status ~= nil and status.state == "outdoors"
        end, "this client's status of the outdoor bank saying it must go inside")
    end,
    validate = function(self)
        local state = self.bank.state
        expect(self.indoorOk, "a bank is refused inside a building")
        expect(not self.outdoorOk and self.reason == "Tooltip_RenewableEnergy_BankIndoorsOnly",
            "a bank may stand outdoors (reason " .. tostring(self.reason) .. ")")
        expect(not state.activated and state.status.state == "outdoors",
            "a bank outdoors switched on (state " .. tostring(state.status.state) .. ")")
    end,
})

-- A removed running bank leaves nothing powered, on this client too, and is forgotten.
test("renewable_energy_bank_removed_bank_leaves_no_power", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { L16, INVERTER_CHARGER })
        if not bank then return end
        self.bank = bank
        T.switchOn(self, bank)
        T.bankState(self, bank)
        T.waitFor(self, function() return bank.square:haveElectricity() end, "power on the switched-on bank's square here")
        T.server(self, "removeBank", { bank = bank.position })
        T.waitFor(self, function() return not bank.square:haveElectricity() and PowerBank.findOn(bank.square) == nil end,
            "the removed bank and its power gone from this client")
    end,
    validate = function(self)
        -- The run's last wait already failed the test if this client kept the bank or its power.
        local removed = self.server.removeBank
        expect(self.bank.state.powered, "the switched-on bank didn't power its square")
        expect(not removed.powered, "the removed bank's square still has power")
        expect(not removed.registered, "the removed bank is still registered")
        expect(PowerBank.summaryOf(self.bank.square) == nil, "this client still has the removed bank's summary")
    end,
})

-- Inverters and overload -----------------------------------------------------------------------

-- A bank's limit is its working inverters' ratings together: a broken one drops out, on this
-- client's summary too.
test("renewable_energy_bank_limit_sums_working_inverters", {
    run = function(self)
        self.bank = T.bank(self, "batteryBankWood", { CAR_BATTERY, POWER_INVERTER, POWER_INVERTER })
        if not self.bank then return end
        T.batch(function()
            T.bankState(self, self.bank)
            T.step(function() self.twoInverters = self.bank.state.limitW end)
            T.setPartCondition(self, self.bank, POWER_INVERTER, 0, true)
        end)
        T.waitFor(self, function()
            local summary = T.clientSummary(self.bank)
            return summary ~= nil and summary.limitW == self.bank.state.limitW
        end, "this client's summary with the broken inverter's limit")
    end,
    validate = function(self)
        -- The run's last wait already failed the test if this client's summary has another limit.
        local inverterW = Specs.inverters[POWER_INVERTER].watts
        expectNear("limit of two Power Inverters", self.twoInverters, 2 * inverterW, 0)
        expectNear("limit with one of them broken", self.bank.state.limitW, inverterW, 0)
    end,
})

-- Fridges the inverter carries beside what the house already draws run; one more cuts the bank's
-- power at the next pass, which strains the inverter and shows in this client's status, and the
-- power comes back by itself at the pass after one is taken away.
test("renewable_energy_bank_overload_cuts_and_returns", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { L16, L16, INVERTER_CHARGER })
        if not bank then return end
        self.bank = bank
        T.watch(self, bank)
        T.switchOn(self, bank)
        T.bankPass(self, bank, 0)
        -- Steps, since single player places a tile at once.
        T.step(function()
            local status = bank.state.status
            local fit = math.floor((status.limitW - status.loadW) / T.fridgeW())
            local squares = T.need(self, fit >= 0 and T.squares(self, fit + 1, { indoors = true, near = bank.square }),
                fit + 1 .. " free indoor squares for fridges beside the " .. status.loadW .. " W the house draws")
            if not squares then return end
            for i = 1, fit do
                T.placeTile(self, squares[i], T.MINI_FRIDGE)
            end
            local last = squares[fit + 1]
            T.bankPass(self, bank, 0)
            T.step(function()
                self.fitting = bank.state
                T.placeTile(self, last, T.MINI_FRIDGE)
                T.bankPass(self, bank, 0)
                T.step(function() self.cut = bank.state end)
                T.waitFor(self, function()
                    local copy = T.clientStatus(bank)
                    return copy ~= nil and copy.overloaded == true
                end, "this client's status of the overloaded bank")
                T.step(function() self.copyCut = T.clientStatus(bank).state end)
                T.batch(function()
                    T.server(self, "removeTile", { x = last:getX(), y = last:getY(), z = last:getZ(), sprite = T.MINI_FRIDGE })
                    T.bankPass(self, bank, 0)
                end)
            end)
        end)
    end,
    validate = function(self)
        local fitting, cut, back = self.fitting, self.cut, self.bank.state
        expect(fitting.activated and not fitting.overloaded, string.format("fridges and the house, %.1f W in all, on a %.1f W"
            .. " inverter didn't run", fitting.status.loadW, fitting.status.limitW))
        local status = cut.status
        expect(not cut.activated and cut.overloaded and status.state == "overloaded",
            "a fridge over the limit didn't cut the power (state " .. tostring(status.state) .. ")")
        expect(status.loadW > status.limitW, "the cut bank's status shows " .. tostring(status.loadW) .. " W of load on a "
            .. tostring(status.limitW) .. " W limit")
        expect(self.copyCut == "overloaded", "this client's status of the cut bank reads " .. tostring(self.copyCut))
        -- The overload's strain, and the two hours on before it, which make no whole point.
        local wear = Specs.partWear
        expectNear("inverter condition before the overload", T.stateCondition(fitting, INVERTER_CHARGER), 100, 0)
        expectNear("inverter condition after the overload", T.stateCondition(cut, INVERTER_CHARGER),
            100 - math.floor(wear.perOverload.inverter + 2 * wear.perHour.inverter), 0)
        expect(back.activated and not back.overloaded, "the power didn't come back once the load fit")
    end,
})

-- Turn On without a working inverter is refused by every layer: the window's switch, the action
-- and the authority's command.
test("renewable_energy_bank_turn_on_refused_without_inverter", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY })
        if not self.bank then return end
        T.step(function() T.openWindow(self) end)
        T.performInto(self, "refused", "setBankOn", { bank = self.bank.position, on = true })
        T.bankState(self, self.bank)
    end,
    validate = function(self)
        local bank, button, why = self.bank.object, self.window.switchButton, getText("Tooltip_RenewableEnergy_NoInverter")
        expect(not Action:new(player(), Action.TURN_ON, nil, bank):canPerform(), "Turn On can start on a bank without an inverter")
        T.expectRefused(self.refused, "Tooltip_RenewableEnergy_NoInverter", "the authority switched on a bank without an inverter")
        expect(not self.bank.state.on, "the bank without an inverter is on")
        expect(not button.enable and button.tooltip == why,
            "the window's switch isn't greyed out saying there's no inverter (" .. tostring(button.tooltip) .. ")")
    end,
})

-- Turn On with nothing to store a charge in is refused by every layer, as without an inverter: a
-- bank holding only an inverter, and one whose only battery is dead. Switched on, either would
-- power its area from nothing until its next pass.
test("renewable_energy_bank_turn_on_refused_without_batteries", {
    run = function(self)
        T.setGrid(self, false)
        self.empty = T.bank(self, "batteryBoxWood", { PLUG_IN_INVERTER })
        self.dead = self.empty and T.bank(self, "batteryBoxWood", { CAR_BATTERY, PLUG_IN_INVERTER })
        if not self.dead then return end
        self.bank = self.empty
        T.setPartCondition(self, self.dead, CAR_BATTERY, 0, true)
        T.waitFor(self, function()
            local battery = copyItem(self.dead, CAR_BATTERY)
            return battery ~= nil and battery:getCondition() == 0
        end, "this client's copy of the dead battery")
        T.step(function() T.openWindow(self) end)
        T.batch(function()
            T.performInto(self, "emptyRefused", "setBankOn", { bank = self.empty.position, on = true })
            T.performInto(self, "deadRefused", "setBankOn", { bank = self.dead.position, on = true })
            T.bankState(self, self.empty)
            T.bankState(self, self.dead)
        end)
    end,
    validate = function(self)
        local key = "Tooltip_RenewableEnergy_NoBatteries"
        for _, case in ipairs({ { self.empty, self.emptyRefused, "holding no battery" },
            { self.dead, self.deadRefused, "whose only battery is dead" } }) do
            local bank, refused, what = case[1], case[2], case[3]
            expect(not Action:new(player(), Action.TURN_ON, nil, bank.object):canPerform(), "Turn On can start on a bank " .. what)
            T.expectRefused(refused, key, "the authority switched on a bank " .. what)
            expect(not bank.state.on and not bank.state.activated, "the bank " .. what .. " is on")
        end
        local button = self.window.switchButton
        expect(not button.enable and button.tooltip == getText(key),
            "the window's switch isn't greyed out saying there are no batteries (" .. tostring(button.tooltip) .. ")")
        expect(T.hasLine(StatusRows.summary(self.dead.state.status), getText("IGUI_RenewableEnergy_NoBatteries")),
            "the window of the bank whose only battery is dead doesn't say it has no working batteries")
    end,
})
