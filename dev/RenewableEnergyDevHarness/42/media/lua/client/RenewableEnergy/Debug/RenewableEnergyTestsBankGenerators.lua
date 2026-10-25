require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Specs"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/StatusRows"

-- Power bank tests: chargers and backup generators (PowerBank/Backup.lua, World/Failsafe.lua),
-- and which of the banks and generators reaching an appliance pays for it (PowerBank/Payers.lua).
-- Banks live on the authority (see RenewableEnergyTestsBank.lua).

local T = RenewableEnergyTest
local test, expect, expectNear, player = T.test, T.expect, T.expectNear, T.player
local Specs = RenewableEnergy.Specs
local Format = RenewableEnergy.Format
local StatusRows = RenewableEnergy.StatusRows
local CAR_BATTERY = RenewableEnergy.VehicleBattery.CAR_BATTERY
local PLUG_IN_INVERTER, POWER_INVERTER, INVERTER_CHARGER = T.PLUG_IN_INVERTER, T.POWER_INVERTER, T.INVERTER_CHARGER

local function distanceSquared(a, b)
    return IsoUtils.DistanceToSquared(a:getX(), a:getY(), b:getX(), b:getY())
end

local function inBackupReach(a, b)
    local reach = Specs.backupReach
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
        { CAR_BATTERY, CAR_BATTERY, Specs.charger, Specs.charger, INVERTER_CHARGER }, opts)
    local backup = bank and backupSquare(self, bank.square, SandboxVars.GeneratorTileRange - 1)
    if backup then return bank, backup end
end

-- The watts chargerBank's chargers make together.
local function chargerBankWatts()
    return 2 * Specs.chargerWatts + Specs.inverters[INVERTER_CHARGER].chargerWatts
end

-- Chargers charge only from the grid or a running generator other than the bank itself, at their
-- full watts while the batteries have room, saying so in the status window.
test("renewable_energy_bank_chargers_charge_only_from_grid_or_generator", {
    sandbox = { GeneratorFuelConsumption = 0.1 },
    run = function(self)
        local charge = 0.2
        local bank, backup = chargerBank(self, { charge = charge })
        if not bank then return end
        self.at = bank.position
        -- For half the time the room left in the batteries takes to fill.
        self.chargersW = chargerBankWatts()
        local roomWh = (1 - charge) * 2 * Specs.batteries[CAR_BATTERY].wh
        self.hours = roomWh / 2 / self.chargersW
        T.switchOn(self, bank)
        T.batch(function()
            T.bankPass(self, bank, 0)
            T.step(function() self.alone, self.ownPower = bank.state.status.chargerW, bank.state.activated end)
            T.generator(self, { square = backup, running = true })
            T.setCharge(self, bank, charge)
            T.bankPass(self, bank, 0, { hours = self.hours })
            T.step(function()
                local status = bank.state.status
                self.generatorStatus = status
                self.generatorSource = status.chargers[1] and status.chargers[1].charging
            end)
        end)
        T.step(function() T.setGrid(self, true) end)
        T.batch(function()
            T.bankPass(self, bank, 0)
            T.step(function() self.fromGrid, self.gridPowered = bank.state.status.chargeSource, bank.state.activated end)
        end)
    end,
    validate = function(self)
        expectNear("charger watts with no grid or generator" .. (self.ownPower and " while the bank powers itself" or ""), self.alone, 0, 0)
        local status = self.generatorStatus
        expectNear("charger watts from a running generator", status.chargerW, self.chargersW, 0)
        expect(self.generatorSource == "generator", "a charger says it charges from " .. tostring(self.generatorSource))
        local shown = T.rowLabelled((StatusRows.rows(status, self.at)), getText("IGUI_RenewableEnergy_GeneratorPower"))
        expect(shown ~= nil and shown.value == getText("IGUI_RenewableEnergy_GridCharging", Format.watts(status.chargerW)),
            "a bank charging from a generator reads " .. tostring(shown and shown.value))
        expect(self.fromGrid == "grid", "with the grid on the chargers charge from " .. tostring(self.fromGrid))
        expect(not self.gridPowered, "the bank ran its own generator while the grid powered its square")
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
            T.bankPass(self, bank, 0)
            T.step(function() self[key] = bank.state end)
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
            T.server(self, "removePart", { bank = bank.position, type = CAR_BATTERY })
            T.server(self, "removePart", { bank = bank.position, type = CAR_BATTERY })
            pass("empty")
        end)
    end,
    validate = function(self)
        local reads = self.reads
        for _, key in ipairs({ "full", "room", "empty" }) do
            local source = self[key].status.chargeSource
            expect(source == "generator", "the " .. key .. " bank's chargers charge from " .. tostring(source))
        end
        expectNear("charger watts into a full bank", self.full.status.chargerW, 0, 0)
        -- A bank pass lasts an hour unless told otherwise, so the room's Wh are the watts it takes.
        local roomWh = (1 - self.low) * self.room.nominalWh
        local filledW = math.min(self.chargersW, roomWh)
        expect(roomWh > 0, "the bank has no room in its batteries")
        expectNear("fuel an hour the chargers added to the generator's bill", reads.room.bill - reads.full.bill,
            fuelPerHour(filledW), 0.0001)
        expectNear("the generator's bill after vanilla rebuilt it", reads.rebuilt.bill, reads.room.bill, 0.0001)
        expectNear("the bank's charge after the chargers filled it", self.room.charge,
            self.low + filledW / self.room.nominalWh, 0.0001)
        expect(self.empty.batteries == 0, "the bank still holds " .. self.empty.batteries .. " batteries")
        expectNear("fuel an hour a bank without batteries left on the generator's bill", reads.empty.bill - reads.full.bill, 0, 0.0001)
        expectNear("charger watts into a bank without batteries", self.empty.status.chargerW, 0, 0)
    end,
})

-- A gas line counts the chargers of a bank charging from its generator into what the generator
-- delivers (GasLines.loadOf), and still does once the world is saved and loaded again, which keeps
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
            T.server(self, "saveAndLoadBank", { bank = bank.position, generator = T.at(backup) })
        end)
    end,
    validate = function(self)
        local reply = self.server.saveAndLoadBank
        expect(self.bank.state.status.chargeSource == "generator",
            "the bank's chargers charge from " .. tostring(self.bank.state.status.chargeSource))
        expect(reply.loadBefore >= reply.chargerW and reply.chargerW > 0, string.format(
            "the generator delivers %.1f W, short of the %.1f W of the bank's chargers", reply.loadBefore, reply.chargerW))
        expectNear("what the generator delivers after a save and load", reply.loadAfter, reply.loadBefore, 0.001)
    end,
})

-- Failsafe -------------------------------------------------------------------------------------

-- The failsafe starts its generator below FailsafeStartCharge and stops it at FailsafeStopCharge,
-- checked at each and a percent below it.
test("renewable_energy_bank_failsafe_starts_generator", {
    sandbox = { FailsafeStartCharge = 20, FailsafeStopCharge = 80 },
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, PLUG_IN_INVERTER })
        local backup = bank and backupSquare(self, bank.square, Specs.backupReach)
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
            T.perform(self, "setBankOn", { bank = bank.position, on = true })
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
    local left, right = StatusRows.rows(status, bank.position)
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
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, PLUG_IN_INVERTER })
        local backup = bank and backupSquare(self, bank.square, Specs.backupReach)
        if not backup then return end
        self.bank = bank
        local function lowPass(key)
            T.setCharge(self, bank, belowFailsafeStart())
            T.bankPass(self, bank, 0, { hours = 0.01 })
            T.step(function() self[key .. "Status"] = bank.state.status end)
            T.readGenerator(self, backup, key)
        end
        T.batch(function()
            T.generator(self, { square = backup, failsafe = true })
            T.perform(self, "setBankOn", { bank = bank.position, on = true })
            T.setPartCondition(self, bank, PLUG_IN_INVERTER, 0, true)
            lowPass("broken")
            T.setPartCondition(self, bank, PLUG_IN_INVERTER, 100, true)
            lowPass("repaired")
        end)
    end,
    validate = function(self)
        expect(not self.reads.broken.running, "the failsafe started its generator for a bank with a broken inverter")
        local idle = getText("IGUI_RenewableEnergy_FailsafeIdle")
        local broken, repaired = failsafeRow(self.brokenStatus, self.bank), failsafeRow(self.repairedStatus, self.bank)
        expect(broken == idle, "the status reads " .. tostring(broken) .. " for the failsafe of a bank with a broken inverter, not "
            .. idle)
        expect(self.reads.repaired.running, "the failsafe didn't start its generator once the inverter was repaired")
        expect(repaired == failsafeRange(), "the status reads " .. tostring(repaired) .. " for the failsafe of a working bank, not "
            .. failsafeRange())
    end,
})

-- Two banks have one failsafe generator in backup reach: it answers to the nearer, so the farther,
-- run low, doesn't start it while the nearer is full, and its status says another bank runs it.
test("renewable_energy_bank_failsafe_answers_to_nearest_bank", {
    run = function(self)
        T.setGrid(self, false)
        local parts = { CAR_BATTERY, PLUG_IN_INVERTER }
        local first = T.bank(self, "batteryBoxWood", parts)
        local backup = first and backupSquare(self, first.square, Specs.backupReach)
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
            T.perform(self, "setBankOn", { bank = near.position, on = true })
            T.perform(self, "setBankOn", { bank = far.position, on = true })
            T.setCharge(self, far, belowFailsafeStart())
            T.bankPass(self, near, 0, { hours = 0.01 })
            T.bankPass(self, far, 0, { hours = 0.01 })
            T.step(function()
                self.nearStatus, self.farStatus = near.state.status, far.state.status
            end)
            T.readGenerator(self, backup, "after")
        end)
    end,
    validate = function(self)
        expect(not self.reads.after.running, "the farther bank started the failsafe generator the nearer bank keeps stopped")
        local other = getText("IGUI_RenewableEnergy_FailsafeOtherBank")
        local near, far = failsafeRow(self.nearStatus, self.nearBank), failsafeRow(self.farStatus, self.farBank)
        expect(near == failsafeRange(), "the nearer bank's status reads " .. tostring(near) .. " for the failsafe, not "
            .. failsafeRange())
        expect(far == other, "the farther bank's status reads " .. tostring(far) .. " for the failsafe, not " .. other)
    end,
})

-- Squares in a line for the relay test, every one free: a bank B, failsafe generators one and two
-- squares on from it, and a bank A three squares past the farther. B and A stand indoors. Both
-- generators are nearer B than A, the farther one is in A's backup reach and the nearer isn't.
-- Nil, and missing, without such a line near the character.
local function relayLine(self)
    local isFree, origin = RenewableEnergy.Debug.isFreeSquare, player():getSquare()
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
        local parts = { CAR_BATTERY, PLUG_IN_INVERTER }
        local b = T.bank(self, "batteryBoxWood", parts, { square = line.b })
        local a = b and T.bank(self, "batteryBoxWood", parts, { square = line.a })
        if not a then return end
        self.bankB, self.bankA = b, a
        T.batch(function()
            T.generator(self, { square = line.near, failsafe = true })
            T.generator(self, { square = line.far, failsafe = true })
            T.perform(self, "setBankOn", { bank = b.position, on = true })
            T.perform(self, "setBankOn", { bank = a.position, on = true })
            T.setCharge(self, b, belowFailsafeStart())
            T.bankPass(self, b, 0, { hours = 0.01 })
            T.bankPass(self, a, 0, { hours = 0.01 })
            T.step(function() self.bStatus, self.aStatus = b.state.status, a.state.status end)
            T.readGenerator(self, line.near, "near")
            T.readGenerator(self, line.far, "far")
        end)
    end,
    validate = function(self)
        expect(self.reads.near.running, "the low bank didn't start the failsafe generator beside it")
        expect(self.reads.far.running, "the low bank didn't start the farther failsafe generator, which answers to it")
        local low, other = failsafeRow(self.bStatus, self.bankB), failsafeRow(self.aStatus, self.bankA)
        expect(low == failsafeRange(), "the low bank's status reads " .. tostring(low) .. " for the failsafe, not "
            .. failsafeRange())
        local otherBank = getText("IGUI_RenewableEnergy_FailsafeOtherBank")
        expect(other == otherBank, "the other bank's status reads " .. tostring(other) .. " for the failsafe, not " .. otherBank)
    end,
})

-- While a backup generator carries a switched-on bank's load, the bank's day figure counts none of
-- it, the generator's share is kept apart, and the batteries keep their charge.
test("renewable_energy_bank_backup_load_kept_apart", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, PLUG_IN_INVERTER })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        local backup = fridge and backupSquare(self, bank.square, Specs.backupReach)
        if not backup then return end
        T.placeTile(self, fridge, T.MINI_FRIDGE)
        T.generator(self, { square = backup, running = true })
        T.batch(function()
            T.performInto(self, "switched", "setBankOn", { bank = bank.position, on = true })
            T.bankState(self, bank)
            T.step(function() self.before = bank.state end)
            T.bankPass(self, bank, 0)
            T.step(function() self.after = bank.state end)
        end)
    end,
    validate = function(self)
        if not T.expectOk(self.switched, "switching the bank on") then return end
        local before, after = self.before, self.after
        expectNear("load Wh the bank carried while the generator ran", after.loadWhToday - before.loadWhToday, 0, 0)
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
local SHARING_PARTS = { CAR_BATTERY, CAR_BATTERY, INVERTER_CHARGER }

-- Queues a pass of both banks, leaving in self[key] the load each carries and whether both ran.
local function passBoth(self, near, far, key)
    T.batch(function()
        T.bankPass(self, near, 0, { hours = 0.01 })
        T.bankPass(self, far, 0, { hours = 0.01 })
        T.step(function()
            self[key] = { near = near.state.status.loadW, far = far.state.status.loadW,
                ran = near.state.activated and far.state.activated }
        end)
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
        T.perform(self, "setBankOn", { bank = near.position, on = false })
        T.bankPass(self, far, 0, { hours = 0.01 })
        T.step(function() self.farAlone = far.state.status.loadW end)
        T.step(function() T.placeTile(self, fridges[2], T.MINI_FRIDGE) end)
        T.bankPass(self, far, 0, { hours = 0.01 })
        T.step(function() self.farAloneWithFridge = far.state.status.loadW end)
    end,
    validate = function(self)
        if not expect(self.before.ran and self.shared.ran, "a bank wasn't powering its squares while both were on") then return end
        expectNear("watts the fridge added to the nearer bank", self.shared.near - self.before.near, T.fridgeW(), 0.01)
        expectNear("watts the fridge added to the farther bank", self.shared.far - self.before.far, 0, 0.01)
        expectNear("watts a fridge added to the farther bank once the nearer stopped",
            self.farAloneWithFridge - self.farAlone, T.fridgeW(), 0.01)
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
        local bank = T.bank(self, "batteryBankWood", { CAR_BATTERY, CAR_BATTERY, POWER_INVERTER, POWER_INVERTER }, { charge = 1 })
        local fridges = bank and T.need(self, T.squares(self, 2, { indoors = true, near = bank.square }), "two free indoor squares for fridges")
        local generatorSquare = fridges and fartherSquare(self, fridges[1], bank.square, { minDistance = 6 })
        -- Out of the bank's backup reach, where it would carry the bank's load instead.
        if not (generatorSquare and T.need(self, not inBackupReach(generatorSquare, bank.square),
            "a square for the generator out of the bank's backup reach")) then return end
        T.switchOn(self, bank)
        local generator = T.generator(self, { square = generatorSquare, running = true })
        local function pass(key)
            T.batch(function()
                T.bankPass(self, bank, 0, { hours = 0.01 })
                T.step(function() self[key] = { bankW = bank.state.status.loadW, ran = bank.state.activated } end)
                T.server(self, "billGenerators", {})
                T.readGenerator(self, generator, key)
            end)
        end
        pass("before")
        T.step(function() T.placeTile(self, fridges[1], T.MINI_FRIDGE) end)
        pass("shared")
        T.perform(self, "setBankOn", { bank = bank.position, on = false })
        T.readGenerator(self, generator, "alone")
        T.step(function() T.placeTile(self, fridges[2], T.MINI_FRIDGE) end)
        T.setGenerator(self, generator, { rebuild = true })
        T.readGenerator(self, generator, "aloneWithFridge")
    end,
    validate = function(self)
        local reads = self.reads
        if not expect(self.before.ran and self.shared.ran, "the bank wasn't powering its squares while on") then return end
        expectNear("watts the fridge added to the bank", self.shared.bankW - self.before.bankW, T.fridgeW(), 0.01)
        expectNear("fuel the fridge added to the generator's bill while the bank ran",
            reads.shared.bill - reads.before.bill, 0, 0.0001)
        expectNear("fuel a fridge added to the generator's bill once the bank was off",
            reads.aloneWithFridge.bill - reads.alone.bill, fuelPerHour(T.fridgeW()), 0.0001)
    end,
})
