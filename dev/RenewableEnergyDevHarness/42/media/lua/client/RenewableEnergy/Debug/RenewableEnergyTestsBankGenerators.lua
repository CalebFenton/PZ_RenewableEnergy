require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyTestLibGenerators"
local Specs = require "RenewableEnergy/Specs"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local Format = require "RenewableEnergy/UI/Format"
local StatusRows = require "RenewableEnergy/UI/StatusRows"
local Debug = require "RenewableEnergy/Debug/RenewableEnergyDebug"

-- Power bank tests: chargers and backup generators (PowerBank/Backup.lua, World/Failsafe.lua),
-- and which of the banks and generators reaching an appliance pays for it (PowerBank/Payers.lua).
-- Banks live on the authority (see RenewableEnergyTestsBank.lua).

local T = RenewableEnergyTest
local test, expect, expectNear, expectEqual, player = T.test, T.expect, T.expectNear, T.expectEqual, T.player
local BACKUP_REACH = PowerBank.BACKUP_REACH

local function distanceSquared(a, b)
    return IsoUtils.DistanceToSquared(a:getX(), a:getY(), b:getX(), b:getY())
end

local function inBackupReach(a, b)
    local reach = BACKUP_REACH
    return math.abs(a:getX() - b:getX()) <= reach and math.abs(a:getY() - b:getY()) <= reach
end

-- The fuel an hour vanilla bills a generator for `watts` at the fuel consumption option.
local function fuelPerHour(watts)
    return Specs.fuelFromWatts(watts) * SandboxVars.GeneratorFuelConsumption
end

-- A free square within `reach` tiles of `near` for a backup generator: outdoors if there is one,
-- since a running generator makes a building toxic.
local function backupSquare(self, near, reach)
    local square
    for _, indoors in ipairs({ false, true }) do
        local candidate = not square and (T.squares(self, 1, { indoors = indoors, near = near }) or {})[1]
        if candidate and distanceSquared(candidate, near) <= reach * reach then
            square = candidate
        end
    end
    return T.need(self, square, "a free square for a generator within " .. reach .. " tiles of the bank")
end

-- Chargers and generator charging --------------------------------------------------------------

-- With the grid off, a rack bank with batteries, car battery chargers and an Inverter/Charger,
-- and a square for a backup generator in reach of it; nil if either can't be had.
local function chargerBank(self, opts)
    T.setGrid(self, false)
    local bank = T.bank(self, "batteryRackWood",
        { T.CAR_BATTERY, T.CAR_BATTERY, Specs.charger, Specs.charger, T.INVERTER_CHARGER }, opts)
    local backup = bank and backupSquare(self, bank.square, SandboxVars.GeneratorTileRange - 1)
    if backup then return bank, backup end
end

-- The watts chargerBank's chargers make together.
local function chargerBankWatts()
    return 2 * Specs.chargerWatts + Specs.inverters[T.INVERTER_CHARGER].chargerWatts
end

-- Chargers charge only from the grid or a running generator other than the bank itself, at their
-- full watts while the batteries have room, saying so in the status window.
test("renewable_energy_bank_chargers_charge_only_from_grid_or_generator", {
    sandbox = { GeneratorFuelConsumption = 0.1 },
    run = function(self)
        local charge = 0.2
        local bank, backup = chargerBank(self, { charge = charge })
        if not bank then return end
        self.at = T.at(bank)
        -- For half the time the room left in the batteries takes to fill.
        self.chargersW = chargerBankWatts()
        local roomWh = (1 - charge) * 2 * Specs.batteries[T.CAR_BATTERY].wh
        self.hours = roomWh / 2 / self.chargersW
        T.switchOn(self, bank)
        T.batch(function()
            T.bankPass(self, bank, 0, { label = "alone" })
            T.generator(self, { square = backup, running = true })
            T.setCharge(self, bank, charge)
            T.bankPass(self, bank, 0, { hours = self.hours, label = "generator" })
        end)
    end,
    validate = function(self)
        local alone, status = self.reads.alone, self.reads.generator.status
        expectEqual("charger watts with no grid or generator" .. (alone.activated and " while the bank powers itself" or ""),
            alone.status.chargerW, 0)
        expectEqual("charger watts from a running generator", status.chargerW, self.chargersW)
        expectEqual("what a charger charges from", status.chargers[1] and status.chargers[1].charging, "generator")
        local shown = T.rowLabelled((StatusRows.rows(status, self.at)), getText("IGUI_RenewableEnergy_GeneratorPower"))
        expectEqual("the generator power row of a bank charging from a generator", shown and shown.value,
            getText("IGUI_RenewableEnergy_GridCharging", Format.watts(status.chargerW)))
    end,
})

-- A running generator's bill, which vanilla burns at the hour and its window shows, counts the
-- chargers charging from it for what the batteries take: nothing for a full bank or one without
-- batteries, the room's watts for one with room, also after vanilla rebuilds the bill.
test("renewable_energy_bank_generator_bills_chargers_by_battery_room", {
    sandbox = { GeneratorFuelConsumption = 0.1 },
    run = function(self)
        local bank, backup = chargerBank(self)
        if not bank then return end
        self.bank = bank
        self.chargersW = chargerBankWatts()
        self.low = 0.2
        local function pass(key)
            T.bankPass(self, bank, 0, { label = key .. "Bank" })
            T.readGenerator(self, backup, key)
        end
        -- The bank stays out: its copy waits for every part, and the batteries leave.
        T.batch(function()
            local generator = T.generator(self, { square = backup, running = true })
            pass("full")
            T.setCharge(self, bank, self.low)
            pass("room")
            T.setGenerator(self, generator, { rebuild = true })
            T.readGenerator(self, backup, "rebuilt")
            T.server(self, "bankPart", T.at(bank, { type = T.CAR_BATTERY, remove = true }))
            T.server(self, "bankPart", T.at(bank, { type = T.CAR_BATTERY, remove = true }))
            pass("empty")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        for _, key in ipairs({ "full", "room", "empty" }) do
            expectEqual("what the " .. key .. " bank's chargers charge from", reads[key .. "Bank"].status.chargeSource, "generator")
        end
        local full, room, empty = reads.fullBank, reads.roomBank, reads.emptyBank
        expectEqual("charger watts into a full bank", full.status.chargerW, 0)
        -- A bank pass lasts an hour unless told otherwise, so the room's Wh are the watts it takes.
        local roomWh = (1 - self.low) * room.nominalWh
        local filledW = math.min(self.chargersW, roomWh)
        expect(roomWh > 0, "the bank has no room in its batteries")
        expectNear("fuel an hour the chargers added to the generator's bill", reads.room.bill - reads.full.bill,
            fuelPerHour(filledW), 0.0001)
        expectNear("the generator's bill after vanilla rebuilt it", reads.rebuilt.bill, reads.room.bill, 0.0001)
        expectNear("the bank's charge after the chargers filled it", room.charge, self.low + filledW / room.nominalWh, 0.0001)
        expectEqual("batteries left in the bank", empty.batteries, 0)
        expectNear("fuel an hour a bank without batteries left on the generator's bill", reads.empty.bill - reads.full.bill, 0, 0.0001)
        expectEqual("charger watts into a bank without batteries", empty.status.chargerW, 0)
    end,
})

-- The job must retire the removed charger's saved demand, not just its hardware rating.
-- Read the bill in the same authority call as Unwire, before any native update can repair it.
test("renewable_energy_settlement_unwire_charger_releases_generator_bill", {
    sandbox = { GeneratorFuelConsumption = 0.1 },
    run = function(self)
        T.setMultiplier(self, 0)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood",
            { T.CAR_BATTERY, T.POWER_INVERTER, Specs.charger }, { charge = 0.2 })
        local square = bank and backupSquare(self, bank.square, BACKUP_REACH)
        if not square then return end
        local generator = T.generator(self, { square = square, running = true })
        T.give(self, "tools", { { type = "Base.Screwdriver" }, { type = "Base.Wrench" } })
        T.forceRoll(self, 1 - T.UNDER)
        T.job(self, "bank", BankJobs.TURN_ON, bank, nil, "switched")
        T.bankPass(self, bank, 0, { hours = 0.01 })
        -- Keep catch-up real without advancing the world into a periodic billing event.
        T.readRecord(self, bank, nil, 0.01)
        T.job(self, "bank", BankJobs.UNWIRE, bank, { type = Specs.charger, inTarget = true }, "unwired",
            { reads = { snapshot = { name = "bankSettlement", args = T.at(bank, { generators = { T.at(generator) } }) } } })
        T.setGenerator(self, generator, { rebuild = true })
        T.read(self, "bankSettlement", T.at(bank, { generators = { T.at(generator) } }), "rebuilt")
    end,
    validate = function(self)
        if not T.expectOk(self.reads.switched, "switching the charging bank on")
            or not T.expectOk(self.reads.unwired, "unwiring only the charger") then return end
        local before, after = self.reads.unwired.before.snapshot, self.reads.unwired.after.snapshot
        expect(before.activated and before.on, "the partial bank was not active before Unwire")
        expect(before.charge > 0 and before.charge < 1, "the charging bank was not partial")
        expect(before.chargeWantW > 0, "the normal pass did not establish charging demand")
        expect(before.generators[1].running and before.generators[1].chargesBank,
            "the ordinary generator was not the bank's charging supplier")
        expectEqual("charger rating before Unwire", before.chargerMaxW, Specs.chargerWatts)
        for _, state in ipairs({ after, self.reads.rebuilt }) do
            expectEqual("bank activation after removing only the charger", state.activated, before.activated)
            expectEqual("bank switch after removing only the charger", state.on, before.on)
            expectEqual("remaining batteries", state.batteries, 1)
            expectEqual("remaining charger rating", state.chargerMaxW, 0)
            expectEqual("remaining saved charging demand", state.chargeWantW, 0)
            expect(state.generators[1].running, "Unwire stopped the ordinary generator")
            expectNear("generator bill after charger removal, including native rebuild",
                state.generators[1].bill, before.generators[1].bill - fuelPerHour(before.chargeWantW), 0.0001)
            expectEqual("parts remaining after Unwire", #state.items, 2)
        end
    end,
})

-- The native clock's whole-bank pass must leave a fuel bill for the final charger demand,
-- without a player action or a standalone bank pass to settle it afterward.
test("renewable_energy_bank_clock_settles_generator_chargers", {
    -- Start in the same ten-minute bucket as the hour's pass, so jumping doesn't bill before it.
    hour = 12 + 59 / 60,
    sandbox = { GeneratorFuelConsumption = 0.1 },
    run = function(self)
        T.setMultiplier(self, 0)
        local bank, backup = chargerBank(self, { charge = 0.2 })
        if not bank then return end
        T.generator(self, { square = backup, running = true })
        T.watch(self, bank)
        T.readGenerator(self, backup, "before")
        T.runToHourlyPass(self, bank, 14, "the bank's clock-driven pass")
        T.step(function() self.chargerW = T.clientStatus(bank).chargerW end)
        T.readGenerator(self, backup, "charging")
        T.step(function() T.setMultiplier(self, 0) end)
    end,
    validate = function(self)
        expect(self.chargerW > 0, "the clock-driven pass did not charge the bank")
        expectNear("the clock-driven chargers' fuel bill", self.reads.charging.bill - self.reads.before.bill,
            fuelPerHour(self.chargerW), 0.0001)
    end,
})

-- A gas line counts the chargers of a bank charging from its generator into what the generator
-- delivers (Payers.deliveredW), and still does once the world is saved and loaded again, which keeps
-- only a bank's saved fields: otherwise, until the bank's next pass, the line would give the share
-- of its cap the bank draws to the other banks charging from it.
test("renewable_energy_bank_charging_generator_kept_through_save", {
    run = function(self)
        local bank, backup = chargerBank(self, { charge = 0.2 })
        if not bank then return end
        self.bank = bank
        T.generator(self, { square = backup, running = true })
        T.batch(function()
            T.bankPass(self, bank, 0, { hours = 0.1 })
            T.reloadRecord(self, bank, "saved", { load = { name = "generatorLoad", args = T.at(backup) },
                bank = { name = "PZHarness.readRecord", args = T.at(bank, { kind = "bank" }) } })
        end)
    end,
    validate = function(self)
        local reply = self.reads.saved
        local loadBefore, loadAfter, chargerW = reply.before.load.deliveredW, reply.after.load.deliveredW, reply.before.bank.chargerMaxW
        expectEqual("what the bank's chargers charge from", self.bank.state.status.chargeSource, "generator")
        expect(loadBefore >= chargerW and chargerW > 0, string.format(
            "the generator delivers %.1f W, short of the %.1f W of the bank's chargers", loadBefore, chargerW))
        expectNear("what the generator delivers after a save and load", loadAfter, loadBefore, 0.001)
    end,
})

-- Failsafe -------------------------------------------------------------------------------------

-- The failsafe starts its generator below FailsafeStartCharge and stops it at FailsafeStopCharge,
-- checked at each and a percent below it.
test("renewable_energy_bank_failsafe_starts_generator", {
    sandbox = { FailsafeStartCharge = 20, FailsafeStopCharge = 80 },
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        local backup = bank and backupSquare(self, bank.square, BACKUP_REACH)
        if not backup then return end
        local start, stop = SandboxVars.RenewableEnergy.FailsafeStartCharge / 100, SandboxVars.RenewableEnergy.FailsafeStopCharge / 100
        -- The failsafe acts on the charge before the pass's own drain, which the next setCharge undoes.
        local function at(key, charge)
            T.setCharge(self, bank, charge)
            T.bankPass(self, bank, 0, { hours = 0.01 })
            T.step(function()
                local generator = bank.state.status.generator
                self.found = self.found or (generator and generator.failsafe)
            end)
            T.readGenerator(self, backup, key)
        end
        T.batch(function()
            T.generator(self, { square = backup, failsafe = true })
            T.job(self, "bank", BankJobs.TURN_ON, bank)
            at("atStart", start)
            at("belowStart", start - 0.01)
            at("belowStop", stop - 0.01)
            at("atStop", stop)
        end)
    end,
    validate = function(self)
        if not expect(self.found, "the bank didn't find the failsafe generator") then return end
        local reads = self.reads
        expect(not reads.atStart.running, "the failsafe started the generator at exactly its start charge")
        expect(reads.belowStart.running, "the failsafe didn't start the generator a percent below its start charge")
        expect(reads.belowStop.running, "the failsafe stopped the generator a percent below its stop charge")
        expect(not reads.atStop.running, "the failsafe didn't stop the generator at exactly its stop charge")
    end,
})

-- The charge just under the failsafe's start.
local function belowFailsafeStart()
    return SandboxVars.RenewableEnergy.FailsafeStartCharge / 100 - 0.05
end

-- What the status window's Failsafe row reads for the status `status` of the bank handle `bank`, or
-- nil without one.
local function failsafeRow(status, bank)
    local label = getText("IGUI_RenewableEnergy_Failsafe")
    local left, right = StatusRows.rows(status, bank)
    local row = T.rowLabelled(left, label) or T.rowLabelled(right, label)
    return row and row.value
end

local function failsafeRange()
    local options = SandboxVars.RenewableEnergy
    return getText("IGUI_RenewableEnergy_FailsafeRange", options.FailsafeStartCharge, options.FailsafeStopCharge)
end

-- A switched-on bank that can't carry its load, its only inverter broken, leaves its failsafe
-- generator stopped however low it runs, and the status says the failsafe is idle; repaired, the
-- bank has it started.
test("renewable_energy_bank_failsafe_waits_for_a_working_bank", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        local backup = bank and backupSquare(self, bank.square, BACKUP_REACH)
        if not backup then return end
        self.bank = bank
        local function lowPass(key)
            T.setCharge(self, bank, belowFailsafeStart())
            T.bankPass(self, bank, 0, { hours = 0.01, label = key .. "Bank" })
            T.readGenerator(self, backup, key)
        end
        T.batch(function()
            T.generator(self, { square = backup, failsafe = true })
            T.job(self, "bank", BankJobs.TURN_ON, bank)
            T.bankPart(self, bank, T.PLUG_IN_INVERTER, { condition = 0, recount = true })
            lowPass("broken")
            T.bankPart(self, bank, T.PLUG_IN_INVERTER, { condition = 100, recount = true })
            lowPass("repaired")
        end)
    end,
    validate = function(self)
        expect(not self.reads.broken.running, "the failsafe started its generator for a bank with a broken inverter")
        expectEqual("the failsafe row of a bank with a broken inverter",
            failsafeRow(self.reads.brokenBank.status, self.bank), getText("IGUI_RenewableEnergy_FailsafeIdle"))
        expect(self.reads.repaired.running, "the failsafe didn't start its generator once the inverter was repaired")
        expectEqual("the failsafe row of a working bank", failsafeRow(self.reads.repairedBank.status, self.bank), failsafeRange())
    end,
})

-- Two banks have one failsafe generator in backup reach: it answers to the nearer, so the farther,
-- run low, doesn't start it while the nearer is full, and its status says another bank runs it.
test("renewable_energy_bank_failsafe_answers_to_nearest_bank", {
    run = function(self)
        T.setGrid(self, false)
        local parts = { T.CAR_BATTERY, T.PLUG_IN_INVERTER }
        local first = T.bank(self, "batteryBoxWood", parts)
        local backup = first and backupSquare(self, first.square, BACKUP_REACH)
        local otherSquare = backup and T.square(self, { indoors = true, near = backup }, "a free indoor square for a second bank")
        if not otherSquare then return end
        local dFirst, dOther = distanceSquared(first.square, backup), distanceSquared(otherSquare, backup)
        if not T.need(self, inBackupReach(otherSquare, backup) and dFirst ~= dOther,
            "a second bank square in the generator's backup reach, nearer or farther than the first") then return end
        local second = T.bank(self, "batteryBoxWood", parts, { square = otherSquare })
        if not second then return end
        local near, far = first, second
        if dOther < dFirst then near, far = second, first end
        self.nearBank, self.farBank = near, far
        T.batch(function()
            T.generator(self, { square = backup, failsafe = true })
            T.job(self, "bank", BankJobs.TURN_ON, near)
            T.job(self, "bank", BankJobs.TURN_ON, far)
            T.setCharge(self, far, belowFailsafeStart())
            T.bankPass(self, near, 0, { hours = 0.01, label = "nearBank" })
            T.bankPass(self, far, 0, { hours = 0.01, label = "farBank" })
            T.readGenerator(self, backup, "after")
        end)
    end,
    validate = function(self)
        expect(not self.reads.after.running, "the farther bank started the failsafe generator the nearer bank keeps stopped")
        expectEqual("the nearer bank's failsafe row", failsafeRow(self.reads.nearBank.status, self.nearBank), failsafeRange())
        expectEqual("the farther bank's failsafe row", failsafeRow(self.reads.farBank.status, self.farBank),
            getText("IGUI_RenewableEnergy_FailsafeOtherBank"))
    end,
})

-- Squares in a line for the relay test, every one free: a bank B, failsafe generators one and two
-- squares on from it, and a bank A three squares past the farther. B and A stand indoors. Both
-- generators are nearer B than A, the farther one is in A's backup reach and the nearer isn't.
-- Nil, and missing, without such a line near the character.
local function relayLine(self)
    local isFree, origin = Debug.isFreeSquare, player():getSquare()
    local z = origin:getZ()
    for radius = 1, 30 do
        for x, y in PZHarness.Fixtures.ring(origin:getX(), origin:getY(), radius) do
            for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
                local line = {}
                for name, steps in pairs({ b = 0, near = 1, far = 2, a = 5 }) do
                    local square = getSquare(x + d[1] * steps, y + d[2] * steps, z)
                    local indoors = name == "b" or name == "a"
                    if square and not self.used[square] and (isFree(square, indoors) or not indoors and isFree(square, true)) then
                        line[name] = square
                    end
                end
                if line.b and line.near and line.far and line.a then
                    for _, square in pairs(line) do
                        self.used[square] = true
                    end
                    return line
                end
            end
        end
    end
    return T.need(self, nil, "a line of free squares for two banks and two failsafe generators")
end

-- Two failsafe generators both answer to the bank nearer them, B, which runs both once it runs low;
-- a bank A that has only the farther one in reach says another bank runs it.
test("renewable_energy_bank_failsafe_runs_every_relay_answering_to_it", {
    run = function(self)
        T.setGrid(self, false)
        local line = relayLine(self)
        if not line then return end
        local parts = { T.CAR_BATTERY, T.PLUG_IN_INVERTER }
        local b = T.bank(self, "batteryBoxWood", parts, { square = line.b })
        local a = b and T.bank(self, "batteryBoxWood", parts, { square = line.a })
        if not a then return end
        self.bankB, self.bankA = b, a
        T.batch(function()
            T.generator(self, { square = line.near, failsafe = true })
            T.generator(self, { square = line.far, failsafe = true })
            T.job(self, "bank", BankJobs.TURN_ON, b)
            T.job(self, "bank", BankJobs.TURN_ON, a)
            T.setCharge(self, b, belowFailsafeStart())
            T.bankPass(self, b, 0, { hours = 0.01, label = "bankB" })
            T.bankPass(self, a, 0, { hours = 0.01, label = "bankA" })
            T.readGenerator(self, line.near, "near")
            T.readGenerator(self, line.far, "far")
        end)
    end,
    validate = function(self)
        expect(self.reads.near.running, "the low bank didn't start the failsafe generator beside it")
        expect(self.reads.far.running, "the low bank didn't start the farther failsafe generator, which answers to it")
        expectEqual("the low bank's failsafe row", failsafeRow(self.reads.bankB.status, self.bankB), failsafeRange())
        expectEqual("the other bank's failsafe row", failsafeRow(self.reads.bankA.status, self.bankA),
            getText("IGUI_RenewableEnergy_FailsafeOtherBank"))
    end,
})

-- Starting B in Rename's catch-up changes the appliance payer even though A stays the nearest
-- charging supplier and the non-charger bank changes neither activation nor charging demand.
test("renewable_energy_settlement_bank_job_failsafe_reassigns_generator_bill", {
    sandbox = { GeneratorFuelConsumption = 0.1, FailsafeStartCharge = 20, FailsafeStopCharge = 80 },
    run = function(self)
        T.setMultiplier(self, 0)
        T.setGrid(self, false)
        local line = relayLine(self)
        if not line then return end
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.POWER_INVERTER },
            { square = line.b, charge = 0.5 })
        if not bank then return end
        local a = T.generator(self, { square = line.near, running = true })
        local b = T.generator(self, { square = line.far, running = true, failsafe = true })
        local positions = { T.at(a), T.at(b) }
        local function snapshot(label)
            T.read(self, "bankSettlement", T.at(bank, { generators = positions }), label)
        end
        local function baseline(label)
            T.bankPass(self, bank, 0, { hours = 0.01 })
            T.server(self, "billGenerators", {})
            snapshot(label)
        end
        T.forceRoll(self, 1 - T.UNDER)
        T.job(self, "bank", BankJobs.TURN_ON, bank, nil, "switched")
        -- Measure both generators' bills without the added appliance so ambient building loads cancel.
        baseline("bothBare")
        T.setGenerator(self, b, { running = false })
        T.step(function() T.placeTile(self, line.a, T.MINI_FRIDGE) end)
        T.setCharge(self, bank, belowFailsafeStart())
        T.readRecord(self, bank, nil, 0.01)
        T.job(self, "bank", BankJobs.RENAME, bank, "Settlement bank", "renamed",
            { reads = { snapshot = { name = "bankSettlement", args = T.at(bank, { generators = positions }) } } })
        -- No bank pass or explicit bill after the job: only vanilla rebuilds and keepShares.
        T.setGenerator(self, a, { rebuild = true })
        snapshot("rebuilt")
    end,
    validate = function(self)
        local reads = self.reads
        if not T.expectOk(reads.switched, "switching the failsafe bank on")
            or not T.expectOk(reads.renamed, "renaming the bank through standalone catch-up") then return end
        local before, after = reads.renamed.before.snapshot, reads.renamed.after.snapshot
        expect(before.generators[1].running and not before.generators[2].running,
            "A must already run and failsafe B must be stopped before Rename")
        expect(before.activated and before.on, "the bank was not active before Rename")
        expect(before.charge > 0 and before.charge < SandboxVars.RenewableEnergy.FailsafeStartCharge / 100,
            "the bank was not below its failsafe start threshold")
        expect(before.lastHour < before.age, "Rename had no elapsed bank pass to catch up")
        expectEqual("non-charger bank's saved demand before Rename", before.chargeWantW, 0)
        expect(before.generators[1].chargesBank and not before.generators[2].chargesBank,
            "A was not the bank's nearest charging supplier before Rename")
        expectNear("Rename caught the bank up to now", after.lastHour, after.age, 0.0001)
        for _, state in ipairs({ after, reads.rebuilt }) do
            expect(state.generators[1].running and state.generators[2].running,
                "Rename's catch-up did not leave A running and start failsafe B")
            expectEqual("bank activation after failsafe catch-up", state.activated, before.activated)
            expectEqual("bank switch after failsafe catch-up", state.on, before.on)
            expectEqual("charging source after failsafe catch-up", state.chargeSource, before.chargeSource)
            expectEqual("charging demand after failsafe catch-up", state.chargeWantW, before.chargeWantW)
            expect(state.generators[1].chargesBank and not state.generators[2].chargesBank,
                "starting B changed the nearest charging supplier away from A")
            expectNear("A's immediate bill after B takes the appliance, including native rebuild",
                state.generators[1].bill, reads.bothBare.generators[1].bill, 0.0001)
            expectNear("B's immediate bill for the appliance, including native rebuild",
                state.generators[2].bill, reads.bothBare.generators[2].bill + fuelPerHour(T.fridgeW()), 0.0001)
        end
    end,
})

-- While a backup generator carries a switched-on bank's load, the bank's day figure counts none of
-- it, the generator's share is kept apart, and the batteries keep their charge.
test("renewable_energy_bank_backup_load_kept_apart", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        local backup = fridge and backupSquare(self, bank.square, BACKUP_REACH)
        if not backup then return end
        T.placeTile(self, fridge, T.MINI_FRIDGE)
        T.generator(self, { square = backup, running = true })
        T.batch(function()
            T.job(self, "bank", BankJobs.TURN_ON, bank, nil, "switched")
            T.readRecord(self, bank, "before")
            T.bankPass(self, bank, 0, { label = "after" })
        end)
    end,
    validate = function(self)
        local reads = self.reads
        if not T.expectOk(reads.switched, "switching the bank on") then return end
        local before, after = reads.before, reads.after
        expectEqual("load Wh the bank carried while the generator ran", after.loadWhToday - before.loadWhToday, 0)
        local backupWh = (after.status.backupWhToday or 0) - (before.status.backupWhToday or 0)
        expect(backupWh > 0, "an hour of the generator carrying the load counted " .. backupWh .. " Wh")
        expectNear("Wh in the batteries while the generator carried the load", after.storedWh, before.storedWh, 0.01)
    end,
})

-- Sharing a reach ------------------------------------------------------------------------------

-- A free square for a source that reaches `fridge` and lies farther from it than `nearer`.
local function fartherSquare(self, fridge, nearer, opts)
    local square = T.square(self, { indoors = opts.indoors, near = fridge, minDistance = opts.minDistance },
        "a free square for a second source")
    return T.need(self, square and distanceSquared(square, fridge) > distanceSquared(nearer, fridge)
        and distanceSquared(square, fridge) <= SandboxVars.GeneratorTileRange ^ 2 and square,
        "a square for a second source farther from the fridge than the first, in its reach")
end

-- Banks that carry the area's own appliances besides the fridges.
local SHARING_PARTS = { T.CAR_BATTERY, T.CAR_BATTERY, T.INVERTER_CHARGER }

-- Queues a pass of both banks, read into self.reads[key .. "Near"] and self.reads[key .. "Far"].
local function passBoth(self, near, far, key)
    T.batch(function()
        T.bankPass(self, near, 0, { hours = 0.01, label = key .. "Near" })
        T.bankPass(self, far, 0, { hours = 0.01, label = key .. "Far" })
    end)
end

-- Two switched-on banks reach a fridge: the nearer pays for it, and the other once the nearer stops.
test("renewable_energy_bank_nearest_bank_pays_shared_appliance", {
    run = function(self)
        T.setGrid(self, false)
        local near = T.bank(self, "batteryBoxWood", SHARING_PARTS, { charge = 1 })
        local fridges = near and T.need(self, T.squares(self, 2, { indoors = true, near = near.square }), "two free indoor squares for fridges")
        local farSquare = fridges and fartherSquare(self, fridges[1], near.square, { indoors = true, minDistance = 4 })
        if not (farSquare and T.need(self, distanceSquared(farSquare, fridges[2]) > distanceSquared(near.square, fridges[2]),
            "a square for the second bank farther from both fridges")) then return end
        local far = T.bank(self, "batteryBoxWood", SHARING_PARTS, { charge = 1, square = farSquare })
        if not far then return end
        T.switchOn(self, near)
        T.switchOn(self, far)
        passBoth(self, near, far, "before")
        T.step(function() T.placeTile(self, fridges[1], T.MINI_FRIDGE) end)
        passBoth(self, near, far, "shared")
        T.job(self, "bank", BankJobs.TURN_OFF, near)
        T.bankPass(self, far, 0, { hours = 0.01, label = "farAlone" })
        T.step(function() T.placeTile(self, fridges[2], T.MINI_FRIDGE) end)
        T.bankPass(self, far, 0, { hours = 0.01, label = "farAloneWithFridge" })
    end,
    validate = function(self)
        local reads = self.reads
        local function loadW(key) return reads[key].status.loadW end
        local ran = reads.beforeNear.activated and reads.beforeFar.activated and reads.sharedNear.activated
            and reads.sharedFar.activated
        if not expect(ran, "a bank wasn't powering its squares while both were on") then return end
        expectNear("watts the fridge added to the nearer bank", loadW("sharedNear") - loadW("beforeNear"), T.fridgeW(), 0.01)
        expectNear("watts the fridge added to the farther bank", loadW("sharedFar") - loadW("beforeFar"), 0, 0.01)
        expectNear("watts a fridge added to the farther bank once the nearer stopped",
            loadW("farAloneWithFridge") - loadW("farAlone"), T.fridgeW(), 0.01)
    end,
})

-- Three fridges by a bank whose plug-in inverter carries one, with a bigger bank farther off
-- reaching them all: the nearer keeps what it carries and hands the rest to the farther, and
-- both stay on, where before the nearer overloaded, dumped everything on the farther, and that
-- overloaded too.
test("renewable_energy_bank_overloaded_bank_hands_load_to_one_with_room", {
    run = function(self)
        T.setGrid(self, false)
        local near = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.CAR_BATTERY, T.PLUG_IN_INVERTER }, { charge = 1 })
        local fridges = near and T.need(self, T.squares(self, 3, { indoors = true, near = near.square }), "three free indoor squares for fridges")
        if not fridges then return end
        local farSquare
        for _, square in ipairs(T.squares(self, 40, { indoors = true, near = fridges[1], minDistance = 4 }) or {}) do
            local fits = not farSquare
            for _, fridge in ipairs(fridges) do
                fits = fits and distanceSquared(square, fridge) > distanceSquared(near.square, fridge)
                    and distanceSquared(square, fridge) <= SandboxVars.GeneratorTileRange ^ 2
            end
            farSquare = fits and square or farSquare
        end
        if not T.need(self, farSquare, "a square for the second bank farther from every fridge, in their reach") then return end
        local far = T.bank(self, "batteryBoxWood", SHARING_PARTS, { charge = 1, square = farSquare })
        if not far then return end
        T.switchOn(self, near)
        T.switchOn(self, far)
        passBoth(self, near, far, "before")
        T.step(function()
            for _, fridge in ipairs(fridges) do
                T.placeTile(self, fridge, T.MINI_FRIDGE)
            end
        end)
        passBoth(self, near, far, "fridges")
    end,
    validate = function(self)
        local reads = self.reads
        local nearNow, farNow = reads.fridgesNear, reads.fridgesFar
        if not expect(T.fridgeW() < nearNow.status.limitW and 2 * T.fridgeW() > nearNow.status.limitW,
            "the nearer bank's inverter carries one fridge and not two") then return end
        expect(nearNow.activated and not nearNow.status.overloaded, "the nearer bank overloaded with load it could hand on")
        expect(farNow.activated and not farNow.status.overloaded, "the farther bank overloaded taking the nearer one's load")
        expect(nearNow.status.loadW <= nearNow.status.limitW, "the nearer bank carries " .. nearNow.status.loadW
            .. " W, beyond its inverter's " .. nearNow.status.limitW .. " W")
        local farGained = farNow.status.loadW - reads.beforeFar.status.loadW
        expect(farGained > 0, "the farther bank took none of the fridges")
        expectNear("watts the three fridges added to the two banks together",
            nearNow.status.loadW - reads.beforeNear.status.loadW + farGained, 3 * T.fridgeW(), 0.01)
    end,
})

-- Two running generators reach a fridge: the nearer one's bill counts it and the farther one's
-- doesn't, also after vanilla rebuilds both bills.
test("renewable_energy_bank_nearest_generator_pays_shared_appliance", {
    run = function(self)
        T.setGrid(self, false)
        local fridge = T.square(self, { indoors = true }, "a free indoor square for a fridge")
        local nearSquare = fridge and T.square(self, { near = fridge }, "a free outdoor square for a generator")
        local farSquare = nearSquare and fartherSquare(self, fridge, nearSquare, { minDistance = 6 })
        if not farSquare then return end
        local near = T.generator(self, { square = nearSquare, running = true })
        local far = T.generator(self, { square = farSquare, running = true })
        local function read(key)
            T.readGenerator(self, near, "near" .. key)
            T.readGenerator(self, far, "far" .. key)
        end
        T.server(self, "billGenerators", {})
        read("Before")
        T.step(function() T.placeTile(self, fridge, T.MINI_FRIDGE) end)
        T.server(self, "billGenerators", {})
        read("Shared")
        T.setGenerator(self, near, { rebuild = true })
        read("Rebuilt")
    end,
    validate = function(self)
        local reads = self.reads
        for _, when in ipairs({ "Shared", "Rebuilt" }) do
            local after = when == "Shared" and "" or " after vanilla rebuilt the bills"
            expectNear("fuel the fridge added to the nearer generator's bill" .. after,
                reads["near" .. when].bill - reads.nearBefore.bill, fuelPerHour(T.fridgeW()), 0.0001)
            expectNear("fuel the fridge added to the farther generator's bill" .. after,
                reads["far" .. when].bill - reads.farBefore.bill, 0, 0.0001)
        end
    end,
})

-- A running generator and a switched-on bank reach a fridge nearer the bank: the bank pays for it,
-- and once the bank is off the generator pays for one. The bank has no charger, which would refill
-- it from the generator on its bill.
test("renewable_energy_bank_and_generator_nearest_pays", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBankWood", { T.CAR_BATTERY, T.CAR_BATTERY, T.POWER_INVERTER, T.POWER_INVERTER }, { charge = 1 })
        local fridges = bank and T.need(self, T.squares(self, 2, { indoors = true, near = bank.square }), "two free indoor squares for fridges")
        local generatorSquare = fridges and fartherSquare(self, fridges[1], bank.square, { minDistance = 6 })
        -- Out of the bank's backup reach, where it would carry the bank's load instead.
        if not (generatorSquare and T.need(self, not inBackupReach(generatorSquare, bank.square),
            "a square for the generator out of the bank's backup reach")) then return end
        T.switchOn(self, bank)
        local generator = T.generator(self, { square = generatorSquare, running = true })
        local function pass(key)
            T.batch(function()
                T.bankPass(self, bank, 0, { hours = 0.01, label = key .. "Bank" })
                T.server(self, "billGenerators", {})
                T.readGenerator(self, generator, key)
            end)
        end
        pass("before")
        T.step(function() T.placeTile(self, fridges[1], T.MINI_FRIDGE) end)
        pass("shared")
        T.job(self, "bank", BankJobs.TURN_OFF, bank)
        T.readGenerator(self, generator, "alone")
        T.step(function() T.placeTile(self, fridges[2], T.MINI_FRIDGE) end)
        T.setGenerator(self, generator, { rebuild = true })
        T.readGenerator(self, generator, "aloneWithFridge")
    end,
    validate = function(self)
        local reads = self.reads
        local before, shared = reads.beforeBank, reads.sharedBank
        if not expect(before.activated and shared.activated, "the bank wasn't powering its squares while on") then return end
        expectNear("watts the fridge added to the bank", shared.status.loadW - before.status.loadW, T.fridgeW(), 0.01)
        expectNear("fuel the fridge added to the generator's bill while the bank ran",
            reads.shared.bill - reads.before.bill, 0, 0.0001)
        expectNear("fuel a fridge added to the generator's bill once the bank was off",
            reads.aloneWithFridge.bill - reads.alone.bill, fuelPerHour(T.fridgeW()), 0.0001)
    end,
})
