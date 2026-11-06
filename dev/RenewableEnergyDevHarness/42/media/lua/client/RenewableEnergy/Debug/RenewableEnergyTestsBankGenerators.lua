require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyTestLibGenerators"
local Specs = require "RenewableEnergy/Specs"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"
local StatusRows = require "RenewableEnergy/UI/StatusRows"
local Debug = require "RenewableEnergy/Debug/RenewableEnergyDebug"
local Squares = require "cf_commonlib/Squares"

-- Power bank tests: chargers and backup generators (PowerBank/Backup.lua, PowerBank/Failsafe.lua),
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

-- Chargers charge only from the grid or a running generator other than the bank itself: a bank
-- powering its area from its own batteries charges nothing. A running generator's bill, which
-- vanilla burns at the hour and its window shows, counts the chargers charging from it for what the
-- batteries take: nothing for a full bank or one without batteries, their full watts while the
-- room outlasts the pass, also after vanilla rebuilds the bill.
test("renewable_energy_bank_generator_bills_chargers_by_battery_room", {
    sandbox = { GeneratorFuelConsumption = 0.1 },
    run = function(self)
        self.low = 0.2
        local bank, backup = chargerBank(self, { charge = self.low })
        if not bank then return end
        self.bank = bank
        self.chargersW = chargerBankWatts()
        -- Half the time the room takes to fill at the chargers' watts.
        self.roomHours = (1 - self.low) * 2 * Specs.batteries[T.CAR_BATTERY].wh / 2 / self.chargersW
        local function pass(key, hours)
            T.bankPass(self, bank, 0, { hours = hours, label = key .. "Bank" })
            T.readGenerator(self, backup, key)
        end
        T.switchOn(self, bank)
        -- The bank stays out: its copy waits for every part, and the batteries leave.
        T.batch(function()
            -- Short, so the area's load can't run the low batteries empty and switch the bank off.
            T.bankPass(self, bank, 0, { hours = 0.01, label = "alone" })
            T.job(self, "bank", BankJobs.TURN_OFF, bank)
            T.setCharge(self, bank, 1)
            local generator = T.generator(self, { square = backup, running = true })
            pass("full")
            T.setCharge(self, bank, self.low)
            pass("room", self.roomHours)
            T.setGenerator(self, generator, { rebuild = true })
            T.readGenerator(self, backup, "rebuilt")
            T.server(self, "bankPart", T.at(bank, { type = T.CAR_BATTERY, remove = true }))
            T.server(self, "bankPart", T.at(bank, { type = T.CAR_BATTERY, remove = true }))
            pass("empty")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        local alone = reads.alone
        expect(alone.activated, "the switched-on bank with room in its batteries didn't power its area by itself: "
            .. tostring(alone.status.state))
        expectEqual("charger watts of the bank powering its area with no grid or generator", alone.status.chargerW, 0)
        for _, key in ipairs({ "full", "room", "empty" }) do
            expectEqual("what the " .. key .. " bank's chargers charge from", reads[key .. "Bank"].status.chargeSource, "generator")
        end
        local full, room, empty = reads.fullBank, reads.roomBank, reads.emptyBank
        expectEqual("charger watts into a full bank", full.status.chargerW, 0)
        expectEqual("charger watts into a bank with room", room.status.chargerW, self.chargersW)
        expectEqual("what a charger charges from", room.status.chargers[1] and room.status.chargers[1].charging, "generator")
        expectNear("fuel an hour the chargers added to the generator's bill", reads.room.bill - reads.full.bill,
            T.fuelPerHour(self.chargersW), 0.0001)
        expectNear("the generator's bill after vanilla rebuilt it", reads.rebuilt.bill, reads.room.bill, 0.0001)
        -- Half the room: 0.2 + (1 - 0.2) / 2.
        expectNear("the bank's charge after the chargers filled it", room.charge, self.low + (1 - self.low) / 2, 0.0001)
        expectEqual("batteries left in the bank", empty.batteries, 0)
        expectNear("fuel an hour a bank without batteries left on the generator's bill", reads.empty.bill - reads.full.bill, 0, 0.0001)
        expectEqual("charger watts into a bank without batteries", empty.status.chargerW, 0)
    end,
})

-- Unwiring a bank's charger takes what it charged at off its generator's bill at once, read in the
-- same authority call as the job, before any vanilla update could rebuild the bill, and again after
-- one has; the bank stays on with its battery and inverter.
test("renewable_energy_bank_unwire_charger_releases_generator_bill", {
    sandbox = { GeneratorFuelConsumption = 0.1 },
    run = function(self)
        -- No ten-minute pass may bill the generator between the reads.
        T.setMultiplier(self, 0)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood",
            { T.CAR_BATTERY, T.POWER_INVERTER, Specs.charger }, { charge = 0.2 })
        local square = bank and backupSquare(self, bank.square, BACKUP_REACH)
        if not square then return end
        local generator = T.generator(self, { square = square, running = true })
        T.give(self, "tools", { { type = "Base.Screwdriver" }, { type = "Base.Wrench" } })
        T.job(self, "bank", BankJobs.TURN_ON, bank, nil, "switched")
        T.bankPass(self, bank, 0, { hours = 0.01 })
        -- Time since that pass for the job to catch up, without the clock running into a billing.
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
        expect(before.activated and before.charge < 1 and before.generators[1].running and before.generators[1].chargesBank,
            "before Unwire the bank must be on with room in its battery, charging from the running generator")
        for _, state in ipairs({ after, self.reads.rebuilt }) do
            local what = state == after and "" or " after vanilla rebuilt the bill"
            expect(state.activated and state.on, "taking out only the charger switched the bank off" .. what)
            expect(state.generators[1].running, "Unwire stopped the generator" .. what)
            expectEqual("parts left after Unwire" .. what, #state.items, 2)
            expectNear("the generator's bill without the charger" .. what,
                state.generators[1].bill, before.generators[1].bill - T.fuelPerHour(Specs.chargerWatts), 0.0001)
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
            T.fuelPerHour(self.chargerW), 0.0001)
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
            -- Full, the chargers want nothing: what the generator delivers then is the area's own load.
            T.setCharge(self, bank, 1)
            T.bankPass(self, bank, 0, { hours = 0.1 })
            T.read(self, "generatorLoad", T.at(backup), "full")
            T.setCharge(self, bank, 0.2)
            T.bankPass(self, bank, 0, { hours = 0.1 })
            T.reloadRecord(self, bank, "saved", { load = { name = "generatorLoad", args = T.at(backup) },
                bank = { name = "PZHarness.readRecord", args = T.at(bank, { kind = "bank" }) } })
        end)
    end,
    validate = function(self)
        local reply = self.reads.saved
        local loadBefore, loadAfter = reply.before.load.deliveredW, reply.after.load.deliveredW
        expectEqual("what the bank's chargers charge from", self.bank.state.status.chargeSource, "generator")
        expectNear("watts the generator delivers to the bank's chargers", loadBefore - self.reads.full.deliveredW,
            chargerBankWatts(), 0.001)
        expectNear("what the generator delivers after a save and load", loadAfter, loadBefore, 0.001)
    end,
})

-- Failsafe -------------------------------------------------------------------------------------

-- The condition at and below which a running vanilla generator may catch fire, which a failsafe,
-- with nobody standing by, never starts (Backup.lua).
local FIRE_CONDITION = 20

-- The failsafe starts its generator below FailsafeStartCharge and stops it at FailsafeStopCharge,
-- checked at each and a percent below it. It starts one a point above the condition that may catch
-- fire, and leaves one at that condition, and one without fuel, stopped.
test("renewable_energy_bank_failsafe_starts_generator", {
    sandbox = { FailsafeStartCharge = 20, FailsafeStopCharge = 80 },
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        local backup = bank and backupSquare(self, bank.square, BACKUP_REACH)
        local worn = backup and backupSquare(self, bank.square, BACKUP_REACH)
        local dry = worn and backupSquare(self, bank.square, BACKUP_REACH)
        if not dry then return end
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
            T.generator(self, { square = backup, failsafe = true, condition = FIRE_CONDITION + 1 })
            T.generator(self, { square = worn, failsafe = true, condition = FIRE_CONDITION })
            T.generator(self, { square = dry, failsafe = true, fuel = 0 })
            T.job(self, "bank", BankJobs.TURN_ON, bank)
            at("atStart", start)
            at("belowStart", start - 0.01)
            T.readGenerator(self, worn, "worn")
            T.readGenerator(self, dry, "dry")
            at("belowStop", stop - 0.01)
            at("atStop", stop)
        end)
    end,
    validate = function(self)
        if not expect(self.found, "the bank didn't find the failsafe generator") then return end
        local reads = self.reads
        expect(not reads.atStart.running, "the failsafe started the generator at exactly its start charge")
        expect(reads.belowStart.running, "the failsafe didn't start the generator a percent below its start charge, a point"
            .. " above the condition that may catch fire")
        expect(not reads.worn.running, "the failsafe started a generator at the condition that may catch fire")
        expect(not reads.dry.running, "the failsafe started a generator without fuel")
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

-- A failsafe generator outdoors past backup reach, as fumes keep generators, but whose power
-- reaches the bank: the failsafe starts it below its start charge, the chargers fill the bank from
-- it, the status shows the failsafe, and the failsafe stops it at its stop charge.
test("renewable_energy_bank_failsafe_runs_generator_past_backup_reach", {
    sandbox = { FailsafeStartCharge = 20, FailsafeStopCharge = 80 },
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood",
            { T.CAR_BATTERY, T.CAR_BATTERY, Specs.charger, Specs.charger, T.INVERTER_CHARGER })
        if not bank then return end
        self.bank = bank
        local range = SandboxVars.GeneratorTileRange - 2
        local square = T.square(self, { indoors = false, near = bank.square, minDistance = BACKUP_REACH + 2,
            accept = function(candidate)
                return candidate:getZ() == bank.z and not inBackupReach(candidate, bank.square)
                    and distanceSquared(candidate, bank.square) <= range * range
            end }, "an outdoor square past the bank's backup reach and in a generator's reach of it")
        if not square then return end
        local generator = T.generator(self, { square = square, failsafe = true })
        T.batch(function()
            T.job(self, "bank", BankJobs.TURN_ON, bank)
            T.setCharge(self, bank, belowFailsafeStart())
            T.bankPass(self, bank, 0, { hours = 0.01 })
            T.readGenerator(self, generator, "low")
            T.bankPass(self, bank, 0, { hours = 0.01, label = "charging" })
            T.setCharge(self, bank, SandboxVars.RenewableEnergy.FailsafeStopCharge / 100)
            T.bankPass(self, bank, 0, { hours = 0.01 })
            T.readGenerator(self, generator, "full")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        expect(reads.low.running, "the failsafe didn't start its generator past backup reach below its start charge")
        expectEqual("the chargers' source", reads.charging.status.chargeSource, "generator")
        expectEqual("the failsafe row", failsafeRow(reads.charging.status, self.bank), failsafeRange())
        expect(not reads.full.running, "the failsafe didn't stop its generator past backup reach at its stop charge")
    end,
})

-- Squares in a line for the nearest-bank test, every one free: a bank B, failsafe generators one and two
-- squares on from it, and a bank A three squares past the farther. B and A stand indoors. Both
-- generators reach both banks and are nearer B.
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

-- A failsafe answers to the nearest bank its generator reaches. Two failsafe generators both answer
-- to B, nearer them: a bank A, run low, doesn't start the farther one while B is full, and says
-- another bank runs it; once B runs low, it runs both.
test("renewable_energy_bank_failsafe_answers_to_nearest_bank", {
    run = function(self)
        T.setGrid(self, false)
        local line = relayLine(self)
        if not line then return end
        local parts = { T.CAR_BATTERY, T.PLUG_IN_INVERTER }
        local b = T.bank(self, "batteryBoxWood", parts, { square = line.b })
        local a = b and T.bank(self, "batteryBoxWood", parts, { square = line.a })
        if not a then return end
        self.bankB, self.bankA = b, a
        local function passes(key)
            T.bankPass(self, b, 0, { hours = 0.01, label = key .. "B" })
            T.bankPass(self, a, 0, { hours = 0.01, label = key .. "A" })
            T.readGenerator(self, line.near, key .. "Near")
            T.readGenerator(self, line.far, key .. "Far")
        end
        T.batch(function()
            T.generator(self, { square = line.near, failsafe = true })
            T.generator(self, { square = line.far, failsafe = true })
            T.job(self, "bank", BankJobs.TURN_ON, b)
            T.job(self, "bank", BankJobs.TURN_ON, a)
            T.setCharge(self, a, belowFailsafeStart())
            passes("aLow")
            T.setCharge(self, b, belowFailsafeStart())
            passes("bLow")
        end)
    end,
    validate = function(self)
        local reads, otherBank = self.reads, getText("IGUI_RenewableEnergy_FailsafeOtherBank")
        expect(not reads.aLowFar.running, "the farther bank started the failsafe generator the full nearer bank keeps stopped")
        expectEqual("the full bank's failsafe row", failsafeRow(reads.aLowB.status, self.bankB), failsafeRange())
        expectEqual("the low farther bank's failsafe row", failsafeRow(reads.aLowA.status, self.bankA), otherBank)
        expect(reads.bLowNear.running, "the low bank didn't start the failsafe generator beside it")
        expect(reads.bLowFar.running, "the low bank didn't start the farther failsafe generator, which answers to it")
        expectEqual("the low bank's failsafe row", failsafeRow(reads.bLowB.status, self.bankB), failsafeRange())
        expectEqual("the other bank's failsafe row", failsafeRow(reads.bLowA.status, self.bankA), otherBank)
    end,
})

-- A bank job that starts a failsafe generator moves what that generator now reaches first onto its
-- bill at once: Rename's catch-up of a bank below its start charge starts B, and the fridge nearer B
-- than the running A leaves A's bill for B's, read in the job's own authority call and again after
-- vanilla rebuilds A's bill. The bank has no charger and stays on, so neither its activation nor
-- its charging changes: a job that settled bills only on those would miss the move.
test("renewable_energy_bank_failsafe_start_moves_appliance_to_its_generator", {
    sandbox = { GeneratorFuelConsumption = 0.1, FailsafeStartCharge = 20, FailsafeStopCharge = 80 },
    run = function(self)
        -- No ten-minute pass may bill the generators between the reads.
        T.setMultiplier(self, 0)
        T.setGrid(self, false)
        local line = relayLine(self)
        if not line then return end
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.POWER_INVERTER },
            { square = line.b, charge = 0.5 })
        if not bank then return end
        local a = T.generator(self, { square = line.near, running = true })
        local b = T.generator(self, { square = line.far, running = true, failsafe = true })
        local args = T.at(bank, { generators = { T.at(a), T.at(b) } })
        T.job(self, "bank", BankJobs.TURN_ON, bank, nil, "switched")
        -- Both generators' bills without the fridge, so what the building around draws cancels.
        T.bankPass(self, bank, 0, { hours = 0.01 })
        T.billGenerators(self)
        T.read(self, "bankSettlement", args, "bare")
        T.setGenerator(self, b, { running = false })
        T.step(function() T.placeTile(self, line.a, T.MINI_FRIDGE) end)
        T.setCharge(self, bank, belowFailsafeStart())
        T.readRecord(self, bank, nil, 0.01)
        T.job(self, "bank", BankJobs.RENAME, bank, "Shed", "renamed", { reads = { snapshot = { name = "bankSettlement", args = args } } })
        -- No bank pass or billing after the job: only vanilla's rebuild.
        T.setGenerator(self, a, { rebuild = true })
        T.read(self, "bankSettlement", args, "rebuilt")
    end,
    validate = function(self)
        local reads = self.reads
        if not T.expectOk(reads.switched, "switching the failsafe bank on")
            or not T.expectOk(reads.renamed, "renaming the bank") then return end
        local before, after, bare = reads.renamed.before.snapshot, reads.renamed.after.snapshot, reads.bare.generators
        expect(before.activated and before.generators[1].running and not before.generators[2].running,
            "before Rename the bank must be on, A running and failsafe B stopped")
        expect(before.charge < SandboxVars.RenewableEnergy.FailsafeStartCharge / 100 and before.lastHour < before.age,
            "before Rename the bank must be below its failsafe start charge, with time since its last pass to catch up")
        for _, state in ipairs({ after, reads.rebuilt }) do
            local what = state == after and "" or " after vanilla rebuilt A's bill"
            expect(state.generators[1].running and state.generators[2].running,
                "Rename's catch-up didn't leave A running and start failsafe B" .. what)
            expect(state.activated == before.activated and state.chargeSource == before.chargeSource
                and state.chargeWantW == before.chargeWantW,
                "Rename changed the bank's activation or charging, which the fridge's move must not need" .. what)
            expectNear("A's bill once B takes the fridge" .. what, state.generators[1].bill, bare[1].bill, 0.0001)
            expectNear("B's bill with the fridge" .. what, state.generators[2].bill,
                bare[2].bill + T.fuelPerHour(T.fridgeW()), 0.0001)
        end
    end,
})

-- While a running generator in backup reach carries a switched-on bank's load, the bank's day
-- figure counts none of it, the generator's share is kept apart, and the batteries keep their
-- charge, even beside a stopped generator whose failsafe answers to the bank.
local BACKUP_HOURS = 1
test("renewable_energy_bank_backup_load_kept_apart", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        local failsafe = fridge and backupSquare(self, bank.square, BACKUP_REACH)
        local running = failsafe and backupSquare(self, bank.square, BACKUP_REACH)
        if not running then return end
        T.placeTile(self, fridge, T.MINI_FRIDGE)
        T.generator(self, { square = failsafe, failsafe = true })
        T.generator(self, { square = running, running = true })
        T.batch(function()
            T.job(self, "bank", BankJobs.TURN_ON, bank, nil, "switched")
            -- Between the failsafe's start and stop charges, so it leaves its generator stopped.
            T.setCharge(self, bank, 0.5)
            T.readRecord(self, bank, "before")
            T.bankPass(self, bank, 0, { hours = BACKUP_HOURS, label = "after" })
            T.readGenerator(self, failsafe, "failsafe")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        if not T.expectOk(reads.switched, "switching the bank on") then return end
        if not expect(not reads.failsafe.running, "the failsafe started its generator at half charge") then return end
        local before, after = reads.before, reads.after
        local shown = after.status.generator
        expect(shown and shown.running and not shown.failsafe, "the bank's backup isn't the running generator")
        expectEqual("load Wh the bank carried while the generator ran", after.loadWhToday - before.loadWhToday, 0)
        local backupWh = (after.status.backupWhToday or 0) - (before.status.backupWhToday or 0)
        expect(after.status.loadW > 0, "the bank measured no load for the generator to carry")
        expectNear("Wh the generator carried", backupWh, after.status.loadW * BACKUP_HOURS, 0.01)
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

-- Two switched-on banks as near a fridge as each other: the lower place (Squares.placeKey) pays for
-- it, whichever bank's pass comes first.
test("renewable_energy_bank_equally_near_banks_lower_place_pays", {
    run = function(self)
        T.setGrid(self, false)
        local fridge = T.square(self, { indoors = true }, "a free indoor square for a fridge")
        local first = fridge and T.square(self, { indoors = true, near = fridge, minDistance = 2 }, "a free indoor square for a bank")
        local second = first and T.square(self, { indoors = true, near = fridge, minDistance = 2, accept = function(square)
            return distanceSquared(square, fridge) == distanceSquared(first, fridge)
        end }, "a free indoor square for a second bank as near the fridge as the first")
        if not (second and T.need(self, distanceSquared(first, fridge) <= SandboxVars.GeneratorTileRange ^ 2,
            "bank squares in reach of the fridge")) then return end
        local banks = { T.bank(self, "batteryBoxWood", SHARING_PARTS, { charge = 1, square = first }) }
        banks[2] = banks[1] and T.bank(self, "batteryBoxWood", SHARING_PARTS, { charge = 1, square = second })
        if not banks[2] then return end
        self.banks = banks
        T.switchOn(self, banks[1])
        T.switchOn(self, banks[2])
        local function pass(key, order)
            T.batch(function()
                for _, i in ipairs(order) do
                    T.bankPass(self, banks[i], 0, { hours = 0.01, label = key .. i })
                end
            end)
        end
        pass("before", { 1, 2 })
        T.step(function() T.placeTile(self, fridge, T.MINI_FRIDGE) end)
        pass("forward", { 1, 2 })
        pass("reversed", { 2, 1 })
    end,
    validate = function(self)
        local reads, banks = self.reads, self.banks
        local function key(bank) return Squares.placeKey(bank.x, bank.y, bank.z) end
        local lower = key(banks[1]) < key(banks[2]) and 1 or 2
        for _, order in ipairs({ "forward", "reversed" }) do
            for i = 1, 2 do
                local before, after = reads["before" .. i], reads[order .. i]
                if not expect(before.activated and after.activated, "a bank wasn't powering its squares while both were on") then return end
                expectNear(string.format("watts the fridge added to the %s place's bank, passes %s", i == lower and "lower" or "higher", order),
                    after.status.loadW - before.status.loadW, i == lower and T.fridgeW() or 0, 0.01)
            end
        end
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
        -- The nearer carries one fridge at most, so the farther takes at least the other two.
        expect(farGained >= 2 * T.fridgeW() - 0.01, string.format("the farther bank took %.1f W of the fridges, less than"
            .. " the two the nearer can't carry, %.1f W", farGained, 2 * T.fridgeW()))
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
        T.billGenerators(self)
        read("Before")
        T.step(function() T.placeTile(self, fridge, T.MINI_FRIDGE) end)
        T.billGenerators(self)
        read("Shared")
        T.setGenerator(self, near, { rebuild = true })
        read("Rebuilt")
    end,
    validate = function(self)
        local reads = self.reads
        for _, when in ipairs({ "Shared", "Rebuilt" }) do
            local after = when == "Shared" and "" or " after vanilla rebuilt the bills"
            expectNear("fuel the fridge added to the nearer generator's bill" .. after,
                reads["near" .. when].bill - reads.nearBefore.bill, T.fuelPerHour(T.fridgeW()), 0.0001)
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
                T.billGenerators(self)
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
            reads.aloneWithFridge.bill - reads.alone.bill, T.fuelPerHour(T.fridgeW()), 0.0001)
    end,
})
