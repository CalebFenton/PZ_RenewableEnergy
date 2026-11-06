require "RenewableEnergy/Debug/RenewableEnergyTestLib"
local Specs = require "RenewableEnergy/Specs"
local BankJobs = require "RenewableEnergy/PowerBank/BankJobs"

-- A bank powering a building through Generator Powered Buildings (PowerBank/GpbBuildings.lua),
-- connected with that mod's own Generator > Connect to Building. They run only in a game that
-- loads that mod (DEVELOPMENT.md has the command); without it the rest of the suite is the proof
-- that nothing changed.

local T = RenewableEnergyTest
local test, expect, expectNear, expectEqual = T.test, T.expect, T.expectNear, T.expectEqual
local GPB = "buildinggenpowerv2"
-- Real ms for that mod's minute to reach a change: its building power follows at most every ten
-- real seconds (PB_Power_Distributor).
local GPB_MS = 30000
-- A pass long enough that the minutes that mod's bill may lag by are a small share of it, short of
-- the bank system's next pass.
local PASS_HOURS = 8 / 60
-- How long after a member joins a pool that mod's split may still count the pool without it.
local SETTLE_HOURS = 3 / 60

-- Queues that mod's Connect to Building (`connect`) or Disconnect from Building on `handle`'s
-- generator, a bank or a fuel generator, as the character standing beside it, and a wait until the
-- generator is in a pool or out of it, reading the bank `bank` and the appliance square `at` as
-- gpbRead does into self.reads[label] when given. A connect also waits until the building is
-- powered through it and that mod has billed it once.
local function poolJob(self, handle, bank, at, connect, label)
    T.goNextTo(self, handle.square)
    -- In multiplayer the action's own check fails on this client once the server's change reaches
    -- it (PB_ConnectBuilding:isValid, PB_DisconnectBuilding:isValid), which stops it, so a player's
    -- job there comes through the command its complete() sends from a client; the server refuses
    -- one before it sees the character beside the generator, so it goes again until it takes.
    local command = connect and "ConnectBuilding" or "DisconnectBuilding"
    local function request()
        sendClientCommand(T.player(), "PoweredBuildings", command, { genX = handle.x, genY = handle.y, genZ = handle.z })
    end
    T.step(function()
        if isClient() then
            request()
        else
            local action = connect and PB_ConnectBuilding or PB_DisconnectBuilding
            ISTimedActionQueue.add(action:new(T.player(), handle.object))
        end
    end)
    local args = T.at(bank, { at = T.at(at), generator = handle ~= bank and T.at(handle) or nil })
    T.serverUntil(self, "gpbRead", args, function(read)
        local generator = read.generator or read.bank
        if isClient() and generator.linked ~= connect then
            request()
        end
        if not connect then
            return not generator.linked
        end
        return generator.linked and generator.billedTo ~= nil and read.hooked
    end, GPB_MS)
    if label then
        T.step(function() self.reads[label] = self.server.gpbRead end)
    end
end

-- Queues two passes of the bank PASS_HOURS apart, as gpbPass reads them into self.reads.first and
-- self.reads[label], with no pass of the bank system between them: the first just after one, which
-- comes each ten game minutes.
local function measuredPasses(self, bank, at, label)
    T.serverUntil(self, "gpbRead", T.at(bank, { at = T.at(at) }), function(read)
        return read.sinceHours < 1 / 60
    end, 2 * GPB_MS)
    T.onRecord(self, bank, "gpbPass", {}, "first")
    T.serverUntil(self, "gpbRead", T.at(bank, { at = T.at(at) }), function(read)
        return read.sinceHours >= PASS_HOURS
    end, GPB_MS)
    T.onRecord(self, bank, "gpbPass", {}, label)
end

-- The watts a pool member pays of the pool's fuel an hour in the gpbRead `read`, among `members`, as
-- vanilla bills the same appliances.
local function shareW(read, members)
    return Specs.wattsFromFuel(read.bank.poolLph / read.consumption) / members
end

-- Checks the gpbPass `pass` against the watts `expected` the bank's share of the pool is: within the
-- two minutes that mod's bill may lag by, at either end of the pass.
local function expectShare(what, pass, expected)
    expectNear(what, pass.gpbW, expected, expected * (2 * 2 / 60) / pass.passHours)
end

-- Queues that mod's own Turn Off on the fuel generator `generator` and switching the bank `bank`
-- off, a wait until the building no longer has that mod's power, then both out of the pool, so the
-- test leaves its squares and that mod's pools as it found them.
local function leave(self, bank, generator, at)
    if generator then
        T.goNextTo(self, generator.square)
        T.step(function() ISTimedActionQueue.add(PB_ActivateGenerator:new(T.player(), generator.object, false)) end)
    end
    T.job(self, "bank", BankJobs.TURN_OFF, bank, nil, "switchOff")
    T.serverUntil(self, "gpbRead", T.at(bank, { at = T.at(at) }), function(read)
        return not read.hooked
    end, GPB_MS)
    T.step(function() self.reads.off = self.server.gpbRead end)
    if generator then
        poolJob(self, generator, bank, at, false)
    end
    poolJob(self, bank, bank, at, false)
end

-- Connected to a house with a fridge, a switched-on bank powers it through that mod, which then
-- reports it powered while the grid is off; its fuel stays full, the litres taken each minute come
-- back as the building's watts in its load, which its batteries pay at the inverter's efficiency,
-- and the bank never counts as on the grid. Turned off, the house goes dark within a game minute.
test("renewable_energy_gpb_bank_powers_building", {
    needsMod = GPB,
    instant = true,
    -- Game minutes go by at the game's pace while that mod bills them.
    timeoutSeconds = 90,
    run = function(self)
        T.setGrid(self, false)
        -- An inverter/charger, with room to spare for the fridge and whatever the house has on.
        local bank = T.bank(self, "batteryRackWood", { T.L16, T.L16, T.INVERTER_CHARGER })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        self.bank = bank
        T.switchOn(self, bank)
        T.step(function() T.placeTile(self, fridge, T.MINI_FRIDGE) end)
        poolJob(self, bank, bank, fridge, true, "connected")
        measuredPasses(self, bank, fridge, "pass")
        T.read(self, "gpbRead", T.at(bank, { at = T.at(fridge) }), "afterPass")
        leave(self, bank, nil, fridge)
    end,
    validate = function(self)
        local connected, pass, after, off = self.reads.connected, self.reads.pass, self.reads.afterPass, self.reads.off
        expect(connected.bank.linked, "Connect to Building left the bank out of a pool")
        expect(connected.hooked and not connected.grid, "that mod doesn't report the house powered with the grid off")
        -- Put back each minute, so it is never down by more than the two minutes that mod may bill
        -- at once.
        expectNear("the bank's fuel minutes in the pool", after.bank.fuel, after.bank.maxFuel,
            after.bank.poolLph * 2 / 60)
        expect(not pass.gridPowered and not after.gridPowered, "the bank took that mod's power for the grid")
        expectEqual("the bank's state powering the house", pass.status.state, "on")
        -- That mod bills the house's vanilla bill at the fuel option, which the bank pays all of as
        -- the pool's one member.
        local expected = shareW(after, 1)
        expect(expected >= T.fridgeW() - 0.001, string.format("the pool bills %.1f W, less than the fridge's %.1f W",
            expected, T.fridgeW()))
        expectShare("the house's watts the bank paid", pass, expected)
        expectNear("the house's watts from the litres taken", pass.gpbW * pass.passHours,
            Specs.wattsFromFuel(pass.passLitres / after.consumption), 1e-6)
        local kinds = {}
        for _, entry in ipairs(pass.status.loadByKind or {}) do
            kinds[entry.kind] = entry
        end
        expectNear("the status's building row", kinds.building and kinds.building.watts, pass.gpbW, 1e-9)
        -- Its own scan of its building leaves out what that mod bills it for, the fridge among it.
        expect(not kinds.fridgeFreezer, "the bank billed the fridge on top of the house")
        local inverter = Specs.inverters[T.INVERTER_CHARGER]
        expectNear("the bank's draw", pass.drawW, pass.status.loadW / inverter.efficiency + inverter.idle, 1e-6)
        expectNear("Wh the batteries gave", pass.storedBefore - pass.storedWh, pass.drawW * pass.passHours, 0.05)
        if not T.expectOk(self.reads.switchOff, "switching the bank off") then return end
        expect(off and not off.hooked, "the house stayed powered with the bank switched off")
    end,
})

-- Pooled with a fuel generator, the bank pays half of what the house draws, and the generator's
-- fuel pays the other half.
test("renewable_energy_gpb_bank_pays_its_share_of_a_pool", {
    needsMod = GPB,
    instant = true,
    timeoutSeconds = 120,
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { T.L16, T.L16, T.POWER_INVERTER })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        local home = bank and bank.square:getBuilding()
        -- Outdoors beside the house, as that mod connects a generator, and beyond the reach in which
        -- a running generator carries a bank's load instead (Backup.lua).
        local outside = fridge and T.square(self, { near = bank, minDistance = 4, accept = function(square)
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local beside = getSquare(square:getX() + dx, square:getY() + dy, square:getZ())
                    if beside and beside:getBuilding() == home then return true end
                end
            end
            return false
        end }, "a free square outside the bank's house")
        if not outside then return end
        self.bank = bank
        T.switchOn(self, bank)
        T.step(function() T.placeTile(self, fridge, T.MINI_FRIDGE) end)
        poolJob(self, bank, bank, fridge, true, "bankConnected")
        local generator = T.generator(self, { square = outside, fuel = 10, running = true })
        poolJob(self, generator, bank, fridge, true, "generatorConnected")
        -- That mod splits a bill it makes two minutes at once by the pool it last counted, so the
        -- bank's share halves a few minutes after the generator joins.
        T.serverUntil(self, "gpbRead", T.at(bank, { at = T.at(fridge) }), function(read)
            local joined = self.reads.generatorConnected.generator.billedTo
            return read.bank.billedTo >= joined + SETTLE_HOURS
        end, GPB_MS)
        measuredPasses(self, bank, fridge, "pass")
        T.read(self, "gpbRead", T.at(bank, { at = T.at(fridge), generator = T.at(generator) }), "afterPass")
        leave(self, bank, generator, fridge)
    end,
    validate = function(self)
        local pass, after = self.reads.pass, self.reads.afterPass
        expect(after.generator.linked and after.generator.activated, "the fuel generator isn't running in the pool")
        expect(after.generator.fuel < 10, "the fuel generator burned nothing in the pool")
        expectEqual("the fuel generator's pool, against the bank's", tostring(after.generator.pool), tostring(after.bank.pool))
        expectNear("the pool's fuel an hour the fuel generator reports, against the bank's", after.generator.poolLph,
            after.bank.poolLph, 1e-6)
        expectShare("the bank's half of the house's watts", pass, shareW(after, 2))
        expect(self.reads.off and not self.reads.off.hooked, "the house stayed powered with the pool switched off")
    end,
})

-- That mod's own Turn On/Off would switch a bank behind the bank's back, so it is refused on a
-- bank, here and on the authority, which checks it again before switching.
test("renewable_energy_gpb_turn_on_off_refused_on_bank", {
    needsMod = GPB,
    run = function(self)
        local bank = T.bank(self, "batteryRackWood", { T.L16, T.POWER_INVERTER })
        if not bank then return end
        T.step(function()
            self.here = PB_ActivateGenerator:new(T.player(), bank.object, true):isValid()
        end)
        T.read(self, "gpbRead", T.at(bank, { at = T.at(bank) }), "server")
    end,
    validate = function(self)
        expect(not self.here, "this client offers that mod's Turn On on a bank")
        expect(not self.reads.server.bank.switchable, "the authority would let that mod switch a bank")
    end,
})
