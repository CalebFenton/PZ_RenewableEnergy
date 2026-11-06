require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local Specs = require "RenewableEnergy/Specs"
local Sun = require "RenewableEnergy/Sun"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local BankMenu = require "RenewableEnergy/UI/BankMenu"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local StatusRows = require "RenewableEnergy/UI/StatusRows"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Sprites = require "RenewableEnergy/Sprites"

-- Power bank tests (PowerBank/* and the bank rows of Specs.lua), split by topic across
-- RenewableEnergyTestsBank*.lua; this file has charging, loads, inverters and turning on. Banks
-- live on the authority: the helpers drive and read its record through T.server; what players
-- see is checked on this client's copies.

local T = RenewableEnergyTest
local test, expect, expectNear, expectEqual, player, stateItem =
    T.test, T.expect, T.expectNear, T.expectEqual, T.player, T.stateItem
local FRIDGE = "appliances_refrigeration_01_0"

-- Charging and loads ---------------------------------------------------------------------------

-- Hours of full sun on a connected panel charge the bank by the panel's rating at the system
-- efficiency over those hours, and the charge, the status and the tile's battery overlays reach
-- this client's copies. Sun past what the batteries hold leaves them exactly full.
local SUNNY_HOURS = 2.5
test("renewable_energy_bank_panel_charges_bank", {
    run = function(self)
        -- Two batteries, so that the sunny hours fit at the default Sunlight Multiplier.
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.CAR_BATTERY }, { charge = 0.2 })
        self.panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not self.panel then return end
        self.bank = bank
        T.watch(self, bank)
        T.batch(function()
            T.readRecord(self, bank, "before")
            T.bankPass(self, bank, Sun.FULL_SUN, { hours = SUNNY_HOURS, label = "sunny" })
        end)
        T.waitForStatus(self, bank, function(status)
            return math.abs(T.copyUses(bank, T.CAR_BATTERY) - bank.state.charge) < 0.001
                and status.solarW == bank.state.status.solarW
                and table.concat(T.overlaysOf(bank.object), ",") == table.concat(bank.state.overlays, ",")
        end, "this client's copies of the charged battery, the status and the overlays")
        T.bankPass(self, bank, Sun.FULL_SUN, { hours = 12, label = "overfilled" })
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        -- The run's last wait already failed the test if this client's copies differ from the server's.
        local before, after, full = self.reads.before, self.reads.sunny, self.reads.overfilled
        local status = after.status
        if not expect(before.storedWh + T.flatPanelW() * SUNNY_HOURS < before.nominalWh,
            "the sunny hours would fill the bank, so its gain can't show") then return end
        expectNear("a flat panel's watts in full sun", status.solarW, T.flatPanelW(), 1e-9)
        expectNear("Wh gained in " .. SUNNY_HOURS .. " hours", after.storedWh - before.storedWh, T.flatPanelW() * SUNNY_HOURS, 0.01)
        expectEqual("percent of full sun", status.sources[1] and status.sources[1].fullSunPct, 100)
        local battery = stateItem(after, T.CAR_BATTERY)
        expectNear("the battery's charge", battery and battery.uses, after.charge, 0.001)
        -- Each battery in its slot, and the meter the south-facing box shows.
        expectEqual("overlays on the charged bank's tile", #after.overlays, 2 + 1)
        battery = stateItem(full, T.CAR_BATTERY)
        expectEqual("the bank's charge after more sun than it holds", full.charge, 1)
        expectEqual("the battery's charge after more sun than it holds", battery and battery.uses, 1)
    end,
})

-- What the last pass found, the sun and each source's watts, is still in the status once the world
-- is saved and loaded again, which keeps only a bank's saved fields: a window opened before the
-- next pass shows it rather than night and nothing coming in.
test("renewable_energy_bank_status_kept_through_save", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY }, { charge = 0.2 })
        self.panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not self.panel then return end
        T.batch(function()
            T.bankPass(self, bank, Sun.FULL_SUN, { hours = 0.1 })
            T.reloadRecord(self, bank, "saved", { bank = { name = "PZHarness.readRecord", args = T.at(bank, { kind = "bank" }) } })
        end)
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        local before, after = self.reads.saved.before.bank.status, self.reads.saved.after.bank.status
        expectNear("a flat panel's watts in full sun before the save", before.solarW, T.flatPanelW(), 1e-9)
        expectEqual("the panel's watts after the save", after.solarW, before.solarW)
        expectEqual("the sun's elevation after the save", after.sunElevation, before.sunElevation)
        expectEqual("the sun on a flat panel after the save", after.irradiance, before.irradiance)
    end,
})

-- A bank's capacity is each battery's watt-hours at its condition, a dead one's nothing, on this
-- client's summary too. The batteries are wired in parallel: sun fills them by that capacity and
-- leaves every live one at the same charge, while a dead one keeps what it held. Catches capacity
-- counted at the rating, and a pass that charges a dead battery or splits the charge unevenly.
test("renewable_energy_bank_capacity_counts_each_battery_by_condition", {
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, T.L16, T.JAR_BATTERY }, { charge = 0.5 })
        self.panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not self.panel then return end
        self.bank = bank
        self.carMax = instanceItem(T.CAR_BATTERY):getConditionMax()
        self.carCondition = math.floor(self.carMax / 2)
        T.batch(function()
            T.bankPart(self, bank, T.CAR_BATTERY, { condition = self.carCondition })
            T.bankPart(self, bank, T.JAR_BATTERY, { condition = 0, recount = true })
            T.readRecord(self, bank, "worn")
            T.bankPass(self, bank, Sun.FULL_SUN, { label = "sunny" })
        end)
        T.waitForSummary(self, bank, function(summary) return summary.capacityWh == bank.state.nominalWh end,
            "this client's summary with the worn bank's capacity")
        T.waitFor(self, function() return math.abs(T.copyUses(bank, T.L16) - bank.state.charge) < 0.001 end,
            "this client's copy of the charged L-16")
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        local worn, sunny = self.reads.worn, self.reads.sunny
        -- Half a car battery, a whole L-16 and nothing of the dead jar battery.
        local capacity = Specs.batteries[T.CAR_BATTERY].wh * self.carCondition / self.carMax + Specs.batteries[T.L16].wh
        expectNear("the worn bank's capacity", worn.nominalWh, capacity, 1e-6)
        expectNear("the worn bank's charge", worn.charge, 0.5, 1e-4)
        local charge = 0.5 + T.flatPanelW() / capacity
        expectNear("the bank's charge after an hour of full sun", sunny.charge, charge, 1e-4)
        for _, fullType in ipairs({ T.CAR_BATTERY, T.L16 }) do
            local battery = stateItem(sunny, fullType)
            expectNear("the charge of the " .. fullType .. " after the sun", battery and battery.uses, charge, 1e-4)
        end
        local dead = stateItem(sunny, T.JAR_BATTERY)
        expectNear("the dead jar battery's charge after the sun", dead and dead.uses, 0.5, 1e-4)
    end,
})

-- At night a bank that is on powers its squares, here too, and pays its inverter's idle draw and
-- losses on top of the appliances its pass finds; the pass takes that draw from the batteries, and
-- the status says how long they last. Switched off, it powers nothing, here too, and draws nothing.
test("renewable_energy_bank_powers_at_night", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { T.L16, T.L16, T.INVERTER_CHARGER })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        self.bank = bank
        T.switchOn(self, bank)
        T.readRecord(self, bank, "on")
        T.waitFor(self, function() return bank.square:haveElectricity() end, "power on the switched-on bank's square here")
        T.bankPass(self, bank, 0, { label = "without" })
        -- A step, since single player places a tile at once.
        T.step(function() T.placeTile(self, fridge, T.MINI_FRIDGE) end)
        T.batch(function()
            T.bankPass(self, bank, 0, { label = "with" })
            T.bankPass(self, bank, 0, { label = "lastOn" })
        end)
        T.job(self, "bank", BankJobs.TURN_OFF, bank, nil, "switchOff")
        T.waitFor(self, function() return not bank.square:haveElectricity() end,
            "this client's copy of the switched-off bank's square without power")
        T.batch(function()
            T.readRecord(self, bank, "off")
            T.bankPass(self, bank, 0, { label = "offPass" })
        end)
    end,
    validate = function(self)
        local on, without, with = self.reads.on, self.reads.without.status, self.reads.with.status
        local lastOn = self.reads.lastOn
        expect(on.activated and on.powered, "switching on a charged bank with an inverter did not power its square")
        -- One inverter carries the load at its efficiency and idles on top.
        local inverter = Specs.inverters[T.INVERTER_CHARGER]
        expectNear("the draw for what the house has on", without.drawW, without.loadW / inverter.efficiency + inverter.idle, 1e-6)
        -- Vanilla bills appliances in single-precision fuel.
        expectNear("the load a fridge adds", with.loadW - without.loadW, T.fridgeW(), 0.001)
        expectNear("the draw a fridge adds", with.drawW - without.drawW, T.fridgeW() / inverter.efficiency, 0.001)
        expectNear("Wh used in an hour", self.reads.with.storedWh - lastOn.storedWh, lastOn.status.drawW, 0.5)
        -- Nothing comes in at night, so the net is the draw, which empties what is stored at that rate.
        local charging, drawW = lastOn.status.charging, lastOn.status.drawW
        expectNear("the status's net watts into the batteries", charging.watts, -drawW, 1e-9)
        expectNear("the status's hours until the batteries are empty", charging.hours, lastOn.storedWh / drawW, 1e-6)
        if not T.expectOk(self.reads.switchOff, "switching the bank off") then return end
        local off, offPass = self.reads.off, self.reads.offPass
        expect(not off.activated and not off.powered, "the switched-off bank still powers its square")
        expectEqual("the switched-off bank's draw", offPass.drawW, 0)
        expectNear("Wh the switched-off bank used in an hour", off.storedWh - offPass.storedWh, 0, 1e-6)
    end,
})

-- While the grid still powers its square, a bank that is on stands by: its generator stays off and
-- its batteries carry nothing, so through a night they don't drain or wear, and its inverter/charger
-- fills them from the grid, up to full and no further. It still measures what is switched on in its
-- reach, the same load it carries once the grid goes, at its next pass, which the batteries pay.
test("renewable_energy_bank_stands_by_on_the_grid", {
    run = function(self)
        T.setGrid(self, true)
        local bank = T.bank(self, "batteryRackWood", { T.L16, T.L16, T.INVERTER_CHARGER }, { charge = 0.5 })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        self.bank = bank
        T.step(function() T.need(self, bank.square:hasGridPower(), "grid power on the bank's square") end)
        T.switchOn(self, bank)
        T.bankPass(self, bank, 0, { hours = 0.1, label = "noFridge" })
        T.step(function() T.placeTile(self, fridge, T.MINI_FRIDGE) end)
        T.bankPass(self, bank, 0, { hours = 12, label = "onGrid" })
        T.step(function() T.setGrid(self, false) end)
        T.bankPass(self, bank, 0, { label = "offGrid" })
    end,
    validate = function(self)
        local onGrid, offGrid = self.reads.onGrid, self.reads.offGrid
        expectEqual("the state of a switched-on bank on the grid", onGrid.status.state, "grid")
        expect(not onGrid.activated, "the bank ran its own generator while the grid powered its square")
        expectEqual("the bank's draw on the grid", onGrid.drawW, 0)
        expectNear("the load a fridge adds on the grid", onGrid.status.loadW - self.reads.noFridge.status.loadW, T.fridgeW(), 0.001)
        expectEqual("the load the bank measured on the grid, against the one it carries after", onGrid.status.loadW,
            offGrid.status.loadW)
        expectEqual("the bank's deepest drop after a night on the grid", onGrid.cycleDepth, 0)
        expectEqual("what the chargers charge from on the grid", onGrid.status.chargeSource, "grid")
        -- Twelve hours of a charger with its rating to spare fill the room exactly.
        expectNear("the bank's charge after a night of grid charging from half", onGrid.charge, 1, 1e-4)
        expect(offGrid.activated and offGrid.drawW > 0, string.format("with the grid gone the bank reads %s, powers %s and draws %.1f W for a load of %.1f W",
            tostring(offGrid.status.state), tostring(offGrid.activated), offGrid.drawW, offGrid.status.loadW))
        expectNear("Wh the batteries gave in the first hour off the grid", onGrid.storedWh - offGrid.storedWh, offGrid.drawW, 0.5)
    end,
})

-- The kind and draw the stand-in for another mod's appliance reports, a Pump House's in generator
-- fuel an hour; the status lists a kind it doesn't know as other.
local CONSUMER_KIND, CONSUMER_FUEL = "testConsumer", 0.2

-- The load scan counts what is switched on in its reach whether or not the bank powers it, so a cut
-- bank knows when the load fits again: a mini fridge with its ice box as a fridge-freezer, as
-- vanilla bills it; nothing for loot on the floor; and another mod's appliance
-- (GeneratorReach.addDraw) at the draw its mod reports, under the mod's own kind, but not while it
-- reports none. Catches a scan that never asks another mod, or bills its appliance switched off.
test("renewable_energy_bank_scan_counts_what_is_switched_on", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        if not bank then return end
        local squares = T.need(self, T.squares(self, 3, { indoors = true, near = bank.square }),
            "free indoor squares for two fridges and another mod's appliance")
        if not squares then return end
        local consumer = squares[3]
        T.server(self, "drawAt", T.at(consumer, { kind = CONSUMER_KIND, fuel = 0 }))
        T.floorItem(self, squares[1], "Base.Nails")
        T.read(self, "scanLoad", T.at(bank), "without")
        T.step(function()
            T.placeTile(self, squares[1], FRIDGE)
            T.placeTile(self, squares[2], T.MINI_FRIDGE)
            T.read(self, "scanLoad", T.at(bank), "with")
            T.floorItem(self, squares[1], "Base.Nails")
            T.read(self, "scanLoad", T.at(bank), "withLoot")
        end)
        T.server(self, "drawAt", T.at(consumer, { kind = CONSUMER_KIND, fuel = CONSUMER_FUEL }))
        T.read(self, "scanLoad", T.at(bank), "withConsumer")
    end,
    validate = function(self)
        local without, with, withLoot, withConsumer = self.reads.without, self.reads.with, self.reads.withLoot,
            self.reads.withConsumer
        local function count(load, kind)
            return load.counts[kind] or 0
        end
        expectEqual("fridge-freezers found, the mini fridge among them",
            count(with, "fridgeFreezer") - count(without, "fridgeFreezer"), 2)
        expectNear("the watts the two fridges add to the scan's load", with.watts - without.watts, 2 * T.fridgeW(), 0.01)
        expectEqual("fridge-freezers with loot before and after the appliance",
            count(withLoot, "fridgeFreezer"), count(with, "fridgeFreezer"))
        expectNear("the load with additional ground loot", withLoot.watts, with.watts, 0.01)
        expectEqual("times the scan bills the appliance drawing nothing", count(withLoot, CONSUMER_KIND), 0)
        expectEqual("times the scan lists the drawing appliance", count(withConsumer, CONSUMER_KIND), 1)
        expectNear("the watts it adds", withConsumer.watts - withLoot.watts, Specs.wattsFromFuel(CONSUMER_FUEL), 0.01)
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
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER }, { square = outdoor })
        if not bank then return end
        self.bank = bank
        T.watch(self, bank)
        T.job(self, "bank", BankJobs.TURN_ON, bank)
        T.readRecord(self, bank)
        T.waitForStatus(self, bank, function(status) return status.state == "outdoors" end, "this client's status of the outdoor bank saying it must go inside")
    end,
    validate = function(self)
        local state = self.bank.state
        expect(self.indoorOk, "a bank is refused inside a building")
        expect(not self.outdoorOk, "a bank may stand outdoors")
        expectEqual("the reason a bank is refused outdoors", self.reason, "Tooltip_RenewableEnergy_BankIndoorsOnly")
        expect(not state.activated, "a bank outdoors switched on")
        expectEqual("the outdoor bank's state", state.status.state, "outdoors")
    end,
})

-- A removed running bank leaves nothing powered, on this client too, and is forgotten.
test("renewable_energy_bank_removed_bank_leaves_no_power", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { T.L16, T.INVERTER_CHARGER })
        if not bank then return end
        self.bank = bank
        T.switchOn(self, bank)
        T.readRecord(self, bank)
        T.waitFor(self, function() return bank.square:haveElectricity() end, "power on the switched-on bank's square here")
        T.read(self, "removeBank", T.at(bank), "removed")
        T.waitFor(self, function() return not bank.square:haveElectricity() and PowerBank.findOn(bank.square) == nil end,
            "the removed bank and its power gone from this client")
    end,
    validate = function(self)
        -- The run's last wait already failed the test if this client kept the bank or its power.
        local removed = self.reads.removed
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
        self.bank = T.bank(self, "batteryBankWood", { T.CAR_BATTERY, T.POWER_INVERTER, T.POWER_INVERTER })
        if not self.bank then return end
        T.batch(function()
            T.readRecord(self, self.bank, "twoInverters")
            T.bankPart(self, self.bank, T.POWER_INVERTER, { condition = 0, recount = true })
        end)
        T.waitForSummary(self, self.bank, function(summary) return summary.limitW == self.bank.state.limitW end,
            "this client's summary with the broken inverter's limit")
    end,
    validate = function(self)
        -- The run's last wait already failed the test if this client's summary has another limit.
        local inverterW = Specs.inverters[T.POWER_INVERTER].watts
        expectEqual("limit of two Power Inverters", self.reads.twoInverters.limitW, 2 * inverterW)
        expectEqual("limit with one of them broken", self.bank.state.limitW, inverterW)
    end,
})

-- Fridges the inverter carries beside what the house already draws run; one more cuts the bank's
-- power at the next pass, which strains the inverter and shows in this client's status, and the
-- power comes back by itself at the pass after one is taken away.
test("renewable_energy_bank_overload_cuts_and_returns", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { T.L16, T.L16, T.INVERTER_CHARGER })
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
            T.bankPass(self, bank, 0, { label = "fitting" })
            T.step(function()
                T.placeTile(self, last, T.MINI_FRIDGE)
                T.bankPass(self, bank, 0, { label = "cut" })
                T.waitForStatus(self, bank, function(status) return status.overloaded == true end,
                    "this client's status of the overloaded bank")
                T.step(function() self.copyCut = T.clientStatus(bank).state end)
                T.batch(function()
                    T.server(self, "removeAt", { x = last:getX(), y = last:getY(), z = last:getZ(), sprite = T.MINI_FRIDGE })
                    T.bankPass(self, bank, 0)
                end)
            end)
        end)
    end,
    validate = function(self)
        local fitting, cut, back = self.reads.fitting, self.reads.cut, self.bank.state
        expect(fitting.activated and not fitting.overloaded, string.format("fridges and the house, %.1f W in all, on a %.1f W"
            .. " inverter didn't run", fitting.status.loadW, fitting.status.limitW))
        local status = cut.status
        expect(not cut.activated and cut.overloaded, "a fridge over the limit didn't cut the power")
        expectEqual("the cut bank's state", status.state, "overloaded")
        expect(status.loadW > status.limitW, "the cut bank's status shows " .. tostring(status.loadW) .. " W of load on a "
            .. tostring(status.limitW) .. " W limit")
        expectEqual("the state in this client's status of the cut bank", self.copyCut, "overloaded")
        -- The overload's strain, and the two hours on before it, which make no whole point.
        local wear = Specs.partWear
        expectEqual("inverter condition before the overload", T.stateCondition(fitting, T.INVERTER_CHARGER), 100)
        expectEqual("inverter condition after the overload", T.stateCondition(cut, T.INVERTER_CHARGER),
            100 - math.floor(wear.perOverload.inverter + 2 * wear.perHour.inverter))
        expect(back.activated and not back.overloaded, "the power didn't come back once the load fit")
    end,
})

-- A load of exactly the inverters' rating runs; a watt more cuts the power. Catches a bank cut
-- while running at its rating.
test("renewable_energy_bank_load_at_the_limit_runs", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { T.L16, T.L16, T.INVERTER_CHARGER })
        if not bank then return end
        T.switchOn(self, bank)
        local limitW = Specs.inverters[T.INVERTER_CHARGER].watts
        T.batch(function()
            T.onRecord(self, bank, "applyLoad", { appliances = { { name = "fridgeFreezer", watts = limitW } } }, "atLimit")
            T.onRecord(self, bank, "applyLoad", { appliances = { { name = "fridgeFreezer", watts = limitW + 1 } } }, "overLimit")
        end)
    end,
    validate = function(self)
        local atLimit, overLimit = self.reads.atLimit, self.reads.overLimit
        expect(atLimit.activated and not atLimit.overloaded, "a load of exactly the inverter's rating cut the bank")
        expect(overLimit.overloaded and not overLimit.activated, "a load a watt over the inverter's rating didn't cut the bank")
    end,
})

-- A bank that ran empty stays off until it holds a whole pass of its draw: a charge a little short
-- of the inverter's draw over the pass leaves it empty, a little more brings it back. Catches a
-- bank that comes back at any charge and stops and starts every pass.
test("renewable_energy_bank_empty_bank_resumes_with_a_pass_of_draw", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, T.INVERTER_CHARGER }, { charge = 0.01 })
        if not bank then return end
        T.batch(function()
            T.job(self, "bank", BankJobs.TURN_ON, bank, nil, "switch")
            T.bankPass(self, bank, 0, { label = "emptied" })
        end)
        T.step(function()
            local emptied = self.reads.emptied
            local inverter = Specs.inverters[T.INVERTER_CHARGER]
            -- An hour's draw (the passes' default) for the load the bank measured.
            local passWh = emptied.status.loadW / inverter.efficiency + inverter.idle
            T.batch(function()
                T.setCharge(self, bank, (passWh - 0.5) / emptied.nominalWh)
                T.bankPass(self, bank, 0, { label = "short" })
                T.setCharge(self, bank, (passWh + 0.5) / emptied.nominalWh)
                T.bankPass(self, bank, 0, { label = "enough" })
            end)
        end)
    end,
    validate = function(self)
        if not T.expectOk(self.reads.switch, "switching the bank on") then return end
        local emptied, short, enough = self.reads.emptied, self.reads.short, self.reads.enough
        if not expectEqual("the state of the bank its pass emptied", emptied.status.state, "empty") then return end
        expectEqual("the load the bank measured after it emptied", enough.status.loadW, emptied.status.loadW)
        expectEqual("the state of the empty bank holding a little less than a pass of draw", short.status.state, "empty")
        expect(not short.activated, "the empty bank holding a little less than a pass of draw powers its squares")
        expectEqual("the state of the empty bank holding a little more than a pass of draw", enough.status.state, "on")
        expect(enough.activated, "the empty bank holding a little more than a pass of draw doesn't power its squares")
    end,
})

-- Turn On without a working inverter is refused by every layer: the bank's menu, the window's
-- switch, the action and the authority's command.
test("renewable_energy_bank_turn_on_refused_without_inverter", {
    run = function(self)
        self.bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY })
        if not self.bank then return end
        T.openWindow(self, self.bank)
        T.job(self, "bank", BankJobs.TURN_ON, self.bank, nil, "refused")
        T.readRecord(self, self.bank)
    end,
    validate = function(self)
        local bank, button, key = self.bank.object, self.window.switchButton, "Tooltip_RenewableEnergy_NoInverter"
        T.noteOption(self, "Turn On", T.menuOption(BankMenu.addBankOptions, bank, getText("ContextMenu_Turn_On")))
        T.expectOptionRefused(self, "Turn On", key)
        expect(not RenewableEnergyAction:new(player(), "bank", BankJobs.TURN_ON, bank):canPerform(),
            "Turn On can start on a bank without an inverter")
        T.expectRefused(self.reads.refused, key, "the authority switched on a bank without an inverter")
        expect(not self.bank.state.on, "the bank without an inverter is on")
        expect(not button.enable, "the window's switch isn't greyed out without an inverter")
        expectEqual("the tooltip of the window's switch", button.tooltip, getText(key))
    end,
})

-- Turn On with nothing to store a charge in is refused by the authority, as without an inverter: a
-- bank holding only an inverter, and one whose only battery is dead. Switched on, either would
-- power its area from nothing until its next pass.
test("renewable_energy_bank_turn_on_refused_without_batteries", {
    run = function(self)
        T.setGrid(self, false)
        self.empty = T.bank(self, "batteryBoxWood", { T.PLUG_IN_INVERTER })
        self.dead = self.empty and T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        if not self.dead then return end
        T.bankPart(self, self.dead, T.CAR_BATTERY, { condition = 0, recount = true })
        T.batch(function()
            T.job(self, "bank", BankJobs.TURN_ON, self.empty, nil, "emptyRefused")
            T.job(self, "bank", BankJobs.TURN_ON, self.dead, nil, "deadRefused")
            T.readRecord(self, self.empty)
            T.readRecord(self, self.dead)
        end)
    end,
    validate = function(self)
        local key = "Tooltip_RenewableEnergy_NoBatteries"
        for _, case in ipairs({ { self.empty, self.reads.emptyRefused, "holding no battery" },
            { self.dead, self.reads.deadRefused, "whose only battery is dead" } }) do
            local bank, refused, what = case[1], case[2], case[3]
            T.expectRefused(refused, key, "the authority switched on a bank " .. what)
            expect(not bank.state.on and not bank.state.activated, "the bank " .. what .. " is on")
        end
        expect(T.hasLine(StatusRows.summary(self.dead.state.status), getText("IGUI_RenewableEnergy_NoBatteries")),
            "the window of the bank whose only battery is dead doesn't say it has no working batteries")
    end,
})
