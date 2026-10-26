require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sun"

-- Power bank tests: the authority's commands and what it sends to whom, the bank's record, the
-- clock, and banks whose chunk is unloaded.
-- Banks live on the authority (see RenewableEnergyTestsBank.lua).

local T = RenewableEnergyTest
local test, expect, expectNear, expectEqual = T.test, T.expect, T.expectNear, T.expectEqual
local player, stateItem = T.player, T.stateItem
local Specs, Sprites, Sun = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun
local PowerBank, BankJobs, SourceJobs = RenewableEnergy.PowerBank, RenewableEnergy.BankJobs, RenewableEnergy.SourceJobs
local SolarGardenLight = RenewableEnergy.SolarGardenLight

-- Commands and permissions ---------------------------------------------------------------------

-- A command from a timed action's complete() survives forged arguments and changes nothing for
-- them; real ones change the server's record and reach this client's summary.
test("renewable_energy_bank_commands_refuse_forged_arguments", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        -- A flat panel: snow slides off a rack, which Clear Snow leaves alone.
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not panel then return end
        self.bank, self.panel = bank, panel
        local function sourceSnowy()
            local summary = T.clientSummary(bank)
            return summary and summary.sources[1] and summary.sources[1].snowy == true
        end
        T.snowfall(self, bank)
        T.waitFor(self, sourceSnowy, "this client's summary with the panel snowy")
        -- Each row: feature, job, the target's place, with.
        local forged = {
            { "bank", "NoSuchJob", bank.position },
            { "bank", BankJobs.TURN_ON, panel.position },
            { "bank", BankJobs.WIRE_IN, bank.position, "nonsense" },
            { "bank", BankJobs.RENAME, bank.position, 7 },
            { "source", SourceJobs.CONNECT, bank.position, bank.position },
            { "source", SourceJobs.CONNECT, panel.position },
        }
        self.accepted = {}
        T.giveBeforeCalls(self, "broom", { { type = "Base.Broom" } })
        -- The forged jobs change nothing this client sees, so they and the clear go together.
        T.batch(function()
            for _, row in ipairs(forged) do
                T.job(self, row[1], row[2], row[3], row[4])
                T.step(function()
                    if self.server.job.ok then
                        table.insert(self.accepted, row[2])
                    end
                end)
            end
            T.job(self, "source", SourceJobs.CLEAR_SNOW, panel.position, { type = "Base.Broom" })
        end)
        T.waitFor(self, function() return not sourceSnowy() end, "this client's summary with the snow cleared")
        T.bankState(self, bank, "afterForged")
        T.batch(function()
            T.job(self, "source", SourceJobs.DISCONNECT, panel.position)
            T.job(self, "bank", BankJobs.RENAME, bank.position, "  Shed bank  ")
            T.job(self, "bank", BankJobs.TURN_ON, bank.position)
        end)
        T.waitForSummary(self, bank, function(summary)
            return summary.on == true and summary.name == "Shed bank" and #summary.sources == 0
        end, "this client's summary of the renamed bank, switched on with no panel")
        T.bankState(self, bank)
    end,
    validate = function(self)
        local forged, state = self.reads.afterForged, self.bank.state
        expect(#self.accepted == 0, "the bank system accepted forged commands: " .. table.concat(self.accepted, ", "))
        expect(forged.sources == 1 and forged.batteries == 1 and forged.name == "" and not forged.on,
            string.format("forged commands changed the bank: %d panels, %d batteries, name %q, on %s",
                forged.sources, forged.batteries, forged.name, tostring(forged.on)))
        -- The waits already failed the test if this client never saw the snow come and go.
        expectEqual("panels left after the disconnect", state.sources, 0)
        expect(state.on, "Turn On didn't switch the server's bank on")
        expectEqual("the server's name of the bank", state.name, "Shed bank")
        -- This client's summary already matched the server's (the last wait).
    end,
})

-- The server takes no bank job as a client command, only the status window's watch, whose
-- refresh still brings the status up to date.
test("renewable_energy_bank_client_commands_ignored", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.CAR_BATTERY, T.PLUG_IN_INVERTER })
        if not bank then return end
        self.bank = bank
        T.bankState(self, bank, "before")
        -- A battery taken out past the bank's commands shows in the status only once something makes
        -- the bank look again: here the watch sent after the forged commands, which the server
        -- handles in the order they came.
        T.bankPart(self, bank, T.CAR_BATTERY, { remove = true })
        T.step(function()
            local p, part = player(), stateItem(self.reads.before, T.PLUG_IN_INVERTER)
            local system = PowerBank.clientSystem
            system:sendCommand(p, "setBankOn", { bank = bank.position, on = true })
            system:sendCommand(p, "rename", { bank = bank.position, name = "Forged" })
            system:sendCommand(p, "unwire", { bank = bank.position, itemId = part and part.id or -1 })
            PowerBank.watchStatus(p, bank.object)
            T.defer(self, function() PowerBank.unwatchStatus(p, bank.object) end)
        end)
        T.waitForStatus(self, bank, function(status) return #status.batteries == 1 end,
            "this client's status after the watch, with the battery taken out")
        T.bankState(self, bank)
    end,
    validate = function(self)
        local after = self.bank.state
        expect(not after.on, "a client command switched the bank on")
        expectEqual("the bank's name after the client commands", after.name, self.reads.before.name)
        expect(stateItem(after, T.PLUG_IN_INVERTER) ~= nil, "a client command unwired the inverter")
    end,
})

-- Every client keeps a bank's summary, resent only when it changes; the whole status goes only to
-- the players watching the bank, until they stop.
test("renewable_energy_bank_status_only_to_watchers", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY, T.PLUG_IN_INVERTER }, { charge = 0.5 })
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not panel then return end
        self.bank = bank
        T.step(function() self.summary = T.clientSummary(bank) end)
        T.bankPass(self, bank, 1000, { label = "unwatched" })
        T.step(function()
            self.unwatched = { status = T.clientStatus(bank), resent = T.clientSummary(bank) ~= self.summary }
        end)
        T.watch(self, bank)
        T.bankPass(self, bank, 0, { label = "watched" })
        T.waitForStatus(self, bank, function(status) return status.solarW == 0 end,
            "this client's status of the watched bank's dark pass")
        T.step(function() PowerBank.unwatchStatus(player(), bank.object) end)
        T.waitFor(self, function() return T.clientStatus(bank) == nil end, "this client letting go of the status it stopped watching")
        -- The unwatch and the pass's call are separate packets, which a server may take in either order.
        T.serverUntil(self, "bankState", { bank = bank.position }, function(state) return state.watchers == 0 end)
        T.bankPass(self, bank, 1000, { label = "stopped" })
        T.step(function() self.stoppedStatus = T.clientStatus(bank) end)
    end,
    validate = function(self)
        local reads = self.reads
        expect(self.unwatched.status == nil, "this client has the status of a bank nobody here watches")
        expectEqual("players watching a bank nobody opened", reads.unwatched.watchers, 0)
        expect(not self.unwatched.resent, "a pass that changed nothing in the summary sent it again")
        expectEqual("players watching the bank this client watches", reads.watched.watchers, 1)
        -- The wait after the unwatch already failed the test if this client kept the status.
        expectEqual("players watching the bank after this client stopped", reads.stopped.watchers, 0)
        expect(self.stoppedStatus == nil, "a pass sent this client the status of a bank it stopped watching")
    end,
})

-- Squares between the character and the far bank, counted ring by ring: well past where the menu's
-- walk leaves a character, and the slack the server allows on top of it.
local FAR_TILES = 8

-- On a multiplayer server a bank job counts only within the character's reach: a rename far away
-- changes nothing, one beside it goes through. The server finishes them, so that no refusal
-- clears the client's queue.
test("renewable_energy_bank_far_action_refused", {
    mpOnly = "only a multiplayer server checks the reach of a client's action; single player trusts its own character",
    instant = true,
    run = function(self)
        local far = T.square(self, { minDistance = FAR_TILES }, "an outdoor square far from the character")
        self.far = far and T.bank(self, "batteryBoxWood", {}, { square = far, outdoors = true })
        self.near = self.far and T.bank(self, "batteryBoxWood", {}, { outdoors = true })
        if not self.near then return end
        T.batch(function()
            for _, row in ipairs({ { "far", "Far" }, { "near", "Near" } }) do
                local key, bank = row[1], self[row[1]]
                T.read(self, "completeRename", { bank = bank.position, name = row[2] }, key .. "Rename")
                T.bankState(self, bank, key)
            end
        end)
    end,
    validate = function(self)
        local reads = self.reads
        expect(not reads.farRename.done, "an action from " .. FAR_TILES .. " squares away was done")
        expectEqual("the name of the bank renamed from " .. FAR_TILES .. " squares away", reads.far.name, "")
        expect(reads.nearRename.done, "renaming the bank beside the character wasn't done")
        expectEqual("the name of the bank renamed beside the character", reads.near.name, "Near")
    end,
})

-- The record and the clock ---------------------------------------------------------------------

-- A bank tile that loads without its container is rebuilt into a working bank that keeps its name
-- and panels, on the server and in this client's summary.
test("renewable_energy_bank_rebuilt_bank_keeps_its_record", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", {})
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not panel then return end
        self.bank, self.panel = bank, panel
        T.batch(function()
            T.job(self, "bank", BankJobs.RENAME, bank.position, "Cellar")
            T.read(self, "rebuildBank", { bank = bank.position }, "rebuilt")
        end)
        T.waitFor(self, function()
            local rebuilt, summary = PowerBank.findOn(bank.square), PowerBank.summaryOf(bank.square)
            return rebuilt ~= nil and rebuilt ~= bank.object and summary ~= nil and summary.name == "Cellar"
        end, "this client's copy of the rebuilt bank, named")
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        local state, summary = self.reads.rebuilt, PowerBank.summaryOf(self.bank.square)
        expectEqual("the rebuilt bank's name", state.name, "Cellar")
        expectEqual("the rebuilt bank's panels", state.sources, 1)
        if not expect(summary ~= nil, "this client has no summary of the rebuilt bank") then return end
        expectEqual("the name in this client's summary of the rebuilt bank", summary.name, "Cellar")
        expectEqual("the panels in this client's summary of the rebuilt bank", #summary.sources, 1)
    end,
})

-- Connecting a panel brings the bank up to now first: the hour before the connect earns nothing for
-- it, the pass after does.
test("renewable_energy_bank_connect_credits_from_connection", {
    hour = 12,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY }, { charge = 0.5 })
        local panel = bank and T.panel(self, Sprites.flat, { near = bank })
        if not panel then return end
        T.batch(function()
            T.bankState(self, bank, nil, 1)
            T.job(self, "source", SourceJobs.CONNECT, panel.position, bank.position, "connect")
            T.bankState(self, bank, "connected")
            T.bankPass(self, bank, 1000, { label = "passed" })
        end)
    end,
    validate = function(self)
        if not T.expectOk(self.reads.connect, "connecting the panel") then return end
        local connected, passed = self.reads.connected, self.reads.passed
        expectNear("hours between the connect and the bank's last pass", connected.age - connected.lastHour, 0, 0.01)
        expectEqual("solar Wh today credited for the hour before the connect", connected.solarWhToday, 0)
        expect(passed.solarWhToday > 0, "the pass after the connect credited the panel nothing")
    end,
})

-- Moving a live source settles both old topologies first and publishes both ends. Its earlier
-- output belongs to the old bank; only a later pass can credit the destination.
test("renewable_energy_bank_source_transfer_settles_both_ends", {
    hour = 12,
    run = function(self)
        local old = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY }, { charge = 0.1 })
        local new = old and T.bank(self, "batteryBoxWood", { T.CAR_BATTERY }, { near = old, charge = 0.1 })
        local panel = new and T.panel(self, Sprites.flat, { near = old, connect = true })
        if not panel then return end
        self.old, self.new, self.panel = old, new, panel
        T.watch(self, old)
        T.watch(self, new)
        T.batch(function()
            T.bankState(self, old, nil, 1)
            T.bankState(self, new, nil, 1)
            T.job(self, "source", SourceJobs.CONNECT, panel.position, new.position, "transfer")
            T.bankState(self, old, "oldTransferred")
            T.bankState(self, new, "newTransferred")
        end)
        T.waitForStatus(self, old, function(status) return #status.sources == 0 end,
            "the watched old bank without the transferred panel")
        T.waitForStatus(self, new, function(status)
            return T.stateSource({ status = status }, panel.position) ~= nil
        end, "the watched destination with the transferred panel")
        T.bankPass(self, new, 1000)
        T.bankState(self, old, "oldAfter")
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) or not T.expectOk(self.reads.transfer, "transferring the panel") then return end
        local old, new = self.reads.oldTransferred, self.reads.newTransferred
        expectEqual("sources left at the old bank", old.sources, 0)
        expectEqual("sources at the destination", new.sources, 1)
        expect(old.solarWhToday > 0, "the old bank lost the panel's output before the transfer")
        expectEqual("destination's solar Wh before it owned the panel", new.solarWhToday, 0)
        expect(self.new.state.solarWhToday > 0, "the destination earned nothing after the transfer")
        expectEqual("old bank's solar Wh after the destination ran", self.reads.oldAfter.solarWhToday, old.solarWhToday)
    end,
})

-- Switching a bank on brings it up to now first: the hour it stood off bills no load, the pass
-- after does. The Inverter/Charger carries whatever the house around switches on.
test("renewable_energy_bank_switch_on_bills_from_switch", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, T.INVERTER_CHARGER })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        T.placeTile(self, fridge, T.MINI_FRIDGE)
        T.batch(function()
            T.bankState(self, bank, nil, 1)
            T.job(self, "bank", BankJobs.TURN_ON, bank.position, nil, "switch")
            T.bankState(self, bank, "switched")
            T.bankPass(self, bank, 0, { hours = 0.1, label = "passed" })
        end)
    end,
    validate = function(self)
        if not T.expectOk(self.reads.switch, "switching the bank on") then return end
        local switched, passed = self.reads.switched, self.reads.passed
        expect(switched.on, "Turn On left the bank off")
        expectNear("hours between the switch and the bank's last pass", switched.age - switched.lastHour, 0, 0.01)
        expectEqual("load Wh today billed for the hour the bank was off", switched.loadWhToday, 0)
        expect(passed.loadWhToday > 0, "the pass after the switch billed the mini fridge nothing")
    end,
})

-- A pass the batteries can't last bills the load they carried: more than nothing, no more than
-- the energy they held less the inverter's losses.
test("renewable_energy_bank_empty_pass_bills_what_it_carried", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, T.INVERTER_CHARGER }, { charge = 0.02 })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        T.placeTile(self, fridge, T.MINI_FRIDGE)
        T.batch(function()
            T.job(self, "bank", BankJobs.TURN_ON, bank.position, nil, "switch")
            T.bankState(self, bank, "before")
            T.bankPass(self, bank, 0, { label = "after" })
        end)
    end,
    validate = function(self)
        if not T.expectOk(self.reads.switch, "switching the bank on") then return end
        local before, after = self.reads.before, self.reads.after
        expect(after.storedWh == 0 and after.status.state == "empty",
            "an hour of load left the bank at " .. after.storedWh .. " Wh, " .. after.status.state)
        local billed, most = after.loadWhToday - before.loadWhToday, before.storedWh * Specs.inverters[T.INVERTER_CHARGER].efficiency
        expect(billed > 0 and billed <= most + 1e-6, "the pass that emptied the bank billed " .. billed
            .. " Wh of load, expected more than 0 and at most the " .. most .. " Wh the batteries could give")
    end,
})

-- A sledgehammer brings the bank up to now first: its batteries land with at least the inverter's
-- idle draw since the last pass taken.
test("renewable_energy_bank_sledgehammer_settles_batteries", {
    instant = true,
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { T.CAR_BATTERY, T.INVERTER_CHARGER }, { charge = 0.9 })
        if not bank then return end
        T.give(self, "sledgehammer", { { type = "Base.Sledgehammer", equip = "primary" } })
        T.switchOn(self, bank)
        T.bankState(self, bank, "before", 1)
        T.doJob(self, bank.square, function() return ISDestroyStuffAction:new(T.player(), bank.object) end)
        T.waitFor(self, function() return PowerBank.findOn(bank.square) == nil end, "the destroyed bank gone from this client")
        T.read(self, "takeFloorItems", { squares = { T.at(bank.square) } }, "floor")
    end,
    validate = function(self)
        local battery, before = T.findIn(self.reads.floor.items, "type", T.CAR_BATTERY), self.reads.before
        if not expect(battery, "the destroyed bank left no battery on the floor") then return end
        local most = before.charge - Specs.inverters[T.INVERTER_CHARGER].idle / before.nominalWh
        expect(battery.uses <= most + 1e-4, "the battery left the destroyed bank at " .. battery.uses
            .. " after an hour on since its last pass at " .. before.charge .. ", expected at most " .. most)
    end,
})

-- The game's clock runs banks and gadgets on the authority: each fixture charges by more than
-- nothing and no more than full sun on its rating over the time its passes covered.
test("renewable_energy_bank_clock_drives_banks_and_gadgets", {
    hour = 12,
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { T.CAR_BATTERY }, { charge = 0.5 })
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        local squares = T.need(self, T.squares(self, 2, { bare = true }), "two bare outdoor squares for the gadgets")
        if not (panel and squares) then return end
        self.bank = bank
        T.watch(self, bank)
        local car = T.placeVehicle(self, "Base.CarNormal", { battery = T.CAR_BATTERY, charge = 0.5 })
        local trailer = T.placeVehicle(self, RenewableEnergy.ArrowBoard.SCRIPT)
        local charger = T.placeAsPlayer(self, squares[1], RenewableEnergy.SolarCellCharger.ITEM, Sprites.cellCharger)
        local light = T.placeAsPlayer(self, squares[2], SolarGardenLight.ITEM, Sprites.gardenLight.off)
        local function fixtures()
            return { bank = bank.position, car = T.vehicleArgs(car), trailer = T.vehicleArgs(trailer),
                charger = T.at(charger, { kind = "charger" }), light = T.at(light, { kind = "gardenLight" }) }
        end
        T.read(self, "stockGadgets", fixtures, "before")
        T.step(function()
            if not T.need(self, panel.connected, "a panel connected to the bank") then return end
            self.nextHour = math.floor(self.reads.before.bankPassAge) + 2
            -- Jumping fires EveryTenMinutes, but EveryHours needs a native clock crossing.
            T.setTime(self, 14 - 1 / 60)
            T.setMultiplier(self, 10)
        end)
        -- The bank's pass and the gadgets' run on the same tick; the bank's status coming back an
        -- hour on from its last pass says both have.
        T.waitForStatus(self, bank, function(status) return status.hour >= self.nextHour end,
            "this client's status of the bank's pass an hour on")
        T.read(self, "gadgetCharges", fixtures, "after")
    end,
    validate = function(self)
        local before, after = self.reads.before, self.reads.after
        local function charged(name, what, ratedW, hours)
            local gain, most = after[name] - before[name], Sun.wattsFrom(ratedW, Sun.FULL_SUN, 0) * hours
            expect(gain > 0 and gain <= most, string.format(
                "%s gained %.4f Wh as the clock moved on %.2f hours, expected more than 0 and at most %.4f", what, gain, hours, most))
        end
        local bankHours, gadgetHours = after.bankPassAge - before.bankPassAge, after.age - before.age
        charged("bank", "the bank with a connected panel", Specs.mounts.flat.modules * Specs.modules[Specs.factoryModule].watts, bankHours)
        charged("car", "the car with a maintainer", Specs.maintainerWatts, gadgetHours)
        charged("charger", "the solar battery charger", Specs.cellChargerWatts, gadgetHours)
        charged("light", "the garden light", Specs.gardenLight.watts, gadgetHours)
        -- A storm during the passes may have cracked a panel since.
        charged("trailer", "the arrow board's battery box", math.max(before.trailerWatts, after.trailerWatts), gadgetHours)
    end,
})

-- Unloaded ---------------------------------------------------------------------------------------

-- Hours the bank powers while away, which its batteries carry the houses around through, and the
-- wear its inverter brings to the trip, pending on the item: together they make a whole point,
-- with a tenth to spare so the summed fractions can't fall short of it, so the hours away must
-- reach the inverter for its wear to show.
local AWAY_HOURS = 20
local PRIMED_WEAR = math.max(0, 1.1 - Specs.partWear.perHour.inverter * AWAY_HOURS)

-- This client's copy of the bank at `position`, found afresh: a chunk loaded again brings new
-- objects.
local function bankHere(position)
    return PowerBank.findOn(getSquare(position.x, position.y, position.z))
end

-- While its chunk is unloaded a switched-on bank carries on from what it last knew: a pass across
-- midnight draws on its charge, turns its day on the depth of yesterday's deepest discharge, and
-- counts the hours its inverter powered. When the chunk loads, the batteries take the charge it
-- reached and that discharge's wear, and the inverter those hours' wear, on the server's items and
-- this client's copies. Batteries enough to carry what the houses around draw through the hours
-- away, so the inverter powers them all.
test("renewable_energy_bank_unloaded_bank_writes_back_on_load", {
    spOnly = T.CHUNK_RELOAD_SP_ONLY,
    timeoutSeconds = T.CHUNK_RELOAD_SECONDS,
    sandbox = { BatteryWear = 100 },
    run = function(self)
        T.setGrid(self, false)
        local parts = { T.JAR_BATTERY, T.INVERTER_CHARGER }
        for _ = 2, Specs.banks["RenewableEnergy.BatteryRackMetal"].maxBatteries do
            table.insert(parts, T.L16)
        end
        local stand = T.square(self, nil, "a free outdoor square to stand on")
        local bank = stand and T.bank(self, "batteryRackMetal", parts, { near = stand })
        if not bank then return end
        self.bank, self.parts = bank, parts
        local at = bank.position
        T.step(function() T.setTime(self, 23.5) end)
        T.switchOn(self, bank)
        T.batch(function()
            T.bankPass(self, bank, 0, { hours = 0.1 })
            T.setCharge(self, bank, 0.3)
            T.bankPass(self, bank, 0, { hours = 0.1 })
            T.setCharge(self, bank, 1)
            T.bankPart(self, bank, T.INVERTER_CHARGER, { wear = PRIMED_WEAR })
            T.bankState(self, bank, "left")
        end)
        T.reloadChunk(self, at, function()
            T.step(function() T.setTime(self, 24.01) end)
            T.serverUntil(self, "bankState", { bank = at }, function(state)
                return state ~= nil and state.calendarDay ~= self.reads.left.calendarDay
            end)
            T.bankPass(self, bank, 0, { hours = AWAY_HOURS, label = "away" })
        end)
        T.bankState(self, bank)
        T.waitFor(self, function()
            local copy = bankHere(at)
            local inverter = copy and copy:getContainer():getFirstType(T.INVERTER_CHARGER)
            return inverter ~= nil and inverter:getCondition() == T.stateCondition(bank.state, T.INVERTER_CHARGER)
        end, "this client's copy of the bank loaded again")
    end,
    validate = function(self)
        local away, back, left = self.reads.away, self.bank.state, self.reads.left
        expectEqual("items the server sees in the bank away (any: its chunk stayed loaded)", #away.items, 0)
        expect(away.calendarDay ~= left.calendarDay, "the day never turned while the bank was away")
        expect(away.status.state == "on" and away.charge < 1, string.format(
            "the bank away drew it to %.3f in %d hours, %s", away.charge, AWAY_HOURS, tostring(away.status.state)))
        local cameBack = {
            [T.JAR_BATTERY] = T.conditionAfterDischarge(T.JAR_BATTERY, left.cycleDepth),
            [T.L16] = T.conditionAfterDischarge(T.L16, left.cycleDepth),
            [T.INVERTER_CHARGER] = 100 - math.floor(PRIMED_WEAR + Specs.partWear.perHour.inverter * AWAY_HOURS),
        }
        expect(cameBack[T.JAR_BATTERY] < 100 and cameBack[T.INVERTER_CHARGER] < 100, string.format("a %.2f deep day and %d hours on"
            .. " don't wear both the jar battery and the inverter a whole point, so their wear can't show", left.cycleDepth, AWAY_HOURS))
        local function check(what, fullType, condition, uses)
            expectEqual(what .. "'s condition", condition, cameBack[fullType])
            if fullType ~= T.INVERTER_CHARGER then
                expectNear(what .. "'s charge", uses, away.charge, 0.001)
            end
        end
        expectEqual("parts the bank came back holding", #back.items, #self.parts)
        for _, item in ipairs(back.items) do
            check("the server's " .. item.type, item.type, item.condition, item.uses)
        end
        local copy = bankHere(self.bank.position)
        if not expect(copy ~= nil, "this client has no copy of the bank loaded again") then return end
        local items = copy:getContainer():getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            check("this client's " .. item:getFullType(), item:getFullType(), item:getCondition(), item:getCurrentUsesFloat())
        end
    end,
})

-- A switched-on bank whose chunk is unloaded when the grid goes carries what was switched on in its
-- reach, measured while the grid still powered it: the hours away drain it for that load, not just
-- its inverter's idle draw, and its inverter/charger no longer charges from the grid.
test("renewable_energy_bank_unloaded_bank_carries_its_load_when_the_grid_goes", {
    spOnly = T.CHUNK_RELOAD_SP_ONLY,
    timeoutSeconds = T.CHUNK_RELOAD_SECONDS,
    run = function(self)
        T.setGrid(self, true)
        local stand = T.square(self, nil, "a free outdoor square to stand on")
        local bank = stand and T.bank(self, "batteryRackWood", { T.L16, T.L16, T.INVERTER_CHARGER }, { near = stand })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        self.bank = bank
        local at = bank.position
        T.switchOn(self, bank)
        T.step(function() self.fridge = T.placeTile(self, fridge, T.MINI_FRIDGE) end)
        T.bankPass(self, bank, 0, { label = "onGrid" })
        -- The fridge goes before the trip: unloaded, the bank keeps what it measured, and a tile in a
        -- chunk that loads again is a new copy the fixture's removal would miss.
        T.step(function() PZHarness.Fixtures.removePlaced(self.fridge.object) end)
        T.reloadChunk(self, at, function()
            T.step(function() T.setGrid(self, false) end)
            T.bankPass(self, bank, 0, { hours = 2, label = "away" })
        end)
    end,
    validate = function(self)
        local onGrid, away = self.reads.onGrid, self.reads.away
        expectEqual("items the server sees in the bank away (any: its chunk stayed loaded)", #away.items, 0)
        expect(onGrid.status.state == "grid" and onGrid.status.loadW >= T.fridgeW(), string.format(
            "on the grid the bank reads %s and measures %.1f W with a fridge on", tostring(onGrid.status.state), onGrid.status.loadW))
        expectEqual("the state of the bank away with the grid gone", away.status.state, "on")
        expectEqual("the load the bank carries away, against the one it measured on the grid", away.status.loadW, onGrid.status.loadW)
        expect(away.drawW > onGrid.status.loadW, string.format("away the bank draws %.1f W for a load of %.1f W",
            away.drawW, onGrid.status.loadW))
        expect(away.charge < onGrid.charge, "away with the grid gone the bank's charge didn't fall")
        expect(away.status.chargeSource == nil, "away with the grid gone the chargers charge from " .. tostring(away.status.chargeSource))
    end,
})
