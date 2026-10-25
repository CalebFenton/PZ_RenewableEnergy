require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/PowerBank"

-- Power bank tests: the authority's commands and what it sends to whom, the bank's record, the
-- clock, and banks whose chunk is unloaded.
-- Banks live on the authority (see RenewableEnergyTestsBank.lua).

local T = RenewableEnergyTest
local test, expect, expectNear, player, stateItem = T.test, T.expect, T.expectNear, T.player, T.stateItem
local Specs, Sprites, Sun = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun
local PowerBank = RenewableEnergy.PowerBank
local SolarGardenLight = RenewableEnergy.SolarGardenLight
local CAR_BATTERY = RenewableEnergy.VehicleBattery.CAR_BATTERY
local PLUG_IN_INVERTER, INVERTER_CHARGER, L16, JAR_BATTERY = T.PLUG_IN_INVERTER, T.INVERTER_CHARGER, T.L16, T.JAR_BATTERY

-- Commands and permissions ---------------------------------------------------------------------

-- A command from a timed action's complete() survives forged arguments and changes nothing for
-- them; real ones change the server's record and reach this client's summary.
test("renewable_energy_bank_commands_refuse_forged_arguments", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, PLUG_IN_INVERTER })
        local panel = bank and T.panel(self, Sprites.rack.wood.S, { near = bank, connect = true })
        if not panel then return end
        self.bank, self.panel = bank, panel
        local function sourceSnowy()
            local summary = T.clientSummary(bank)
            return summary and summary.sources[1] and summary.sources[1].snowy == true
        end
        T.snowfall(self, bank)
        T.waitFor(self, sourceSnowy, "this client's summary with the panel snowy")
        local forged = {
            { "noSuchCommand", { bank = bank.position } },
            { "setBankOn", { bank = "nonsense" } },
            { "wireIn", { bank = bank.position, itemId = "nonsense" } },
            { "rename", { bank = bank.position, name = 7 } },
            { "connectSource", { bank = bank.position, source = bank.position } },
            { "connectSource" },
        }
        self.accepted = {}
        -- The forged commands change nothing this client sees, so they and the clear go together.
        T.batch(function()
            for _, call in ipairs(forged) do
                T.perform(self, call[1], call[2])
                T.step(function()
                    if self.server.perform.ok then
                        table.insert(self.accepted, call[1])
                    end
                end)
            end
            T.perform(self, "clearSnow", { source = panel.position })
        end)
        T.waitFor(self, function() return not sourceSnowy() end, "this client's summary with the snow cleared")
        T.bankState(self, bank)
        T.step(function() self.afterForged = bank.state end)
        T.batch(function()
            T.perform(self, "disconnectSource", { source = panel.position })
            T.perform(self, "rename", { bank = bank.position, name = "  Shed bank  " })
            T.perform(self, "setBankOn", { bank = bank.position, on = true })
        end)
        T.waitFor(self, function()
            local summary = T.clientSummary(bank)
            return summary ~= nil and summary.on == true and summary.name == "Shed bank" and #summary.sources == 0
        end, "this client's summary of the renamed bank, switched on with no panel")
        T.bankState(self, bank)
    end,
    validate = function(self)
        local forged, state = self.afterForged, self.bank.state
        expect(#self.accepted == 0, "the bank system accepted forged commands: " .. table.concat(self.accepted, ", "))
        expect(forged.sources == 1 and forged.batteries == 1 and forged.name == "" and not forged.on,
            string.format("forged commands changed the bank: %d panels, %d batteries, name %q, on %s",
                forged.sources, forged.batteries, forged.name, tostring(forged.on)))
        -- The waits already failed the test if this client never saw the snow come and go.
        expect(state.sources == 0, "disconnecting the panel left " .. state.sources .. " panels")
        expect(state.on, "setBankOn didn't switch the server's bank on")
        expect(state.name == "Shed bank", "the server names the bank " .. tostring(state.name))
        -- This client's summary already matched the server's (the last wait).
    end,
})

-- The server takes no bank job as a client command, only the status window's watch, whose
-- refresh still brings the status up to date.
test("renewable_energy_bank_client_commands_ignored", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, CAR_BATTERY, PLUG_IN_INVERTER })
        if not bank then return end
        self.bank = bank
        T.bankState(self, bank)
        T.step(function() self.before = bank.state end)
        -- A battery taken out past the bank's commands shows in the status only once something makes
        -- the bank look again: here the watch sent after the forged commands, which the server
        -- handles in the order they came.
        T.server(self, "removePart", { bank = bank.position, type = CAR_BATTERY })
        T.step(function()
            local p, part = player(), stateItem(self.before, PLUG_IN_INVERTER)
            local system = PowerBank.clientSystem
            system:sendCommand(p, "setBankOn", { bank = bank.position, on = true })
            system:sendCommand(p, "rename", { bank = bank.position, name = "Forged" })
            system:sendCommand(p, "unwire", { bank = bank.position, itemId = part and part.id or -1 })
            PowerBank.watchStatus(p, bank.object)
            T.defer(self, function() PowerBank.unwatchStatus(p, bank.object) end)
        end)
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return status ~= nil and #status.batteries == 1
        end, "this client's status after the watch, with the battery taken out")
        T.bankState(self, bank)
    end,
    validate = function(self)
        local before, after = self.before, self.bank.state
        expect(not after.on, "a client command switched the bank on")
        expect(after.name == before.name, "a client command renamed the bank " .. tostring(after.name))
        expect(stateItem(after, PLUG_IN_INVERTER) ~= nil, "a client command unwired the inverter")
    end,
})

-- Every client keeps a bank's summary, resent only when it changes; the whole status goes only to
-- the players watching the bank, until they stop.
test("renewable_energy_bank_status_only_to_watchers", {
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY, PLUG_IN_INVERTER }, { charge = 0.5 })
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        if not panel then return end
        self.bank = bank
        T.step(function() self.summary = T.clientSummary(bank) end)
        T.bankPass(self, bank, 1000)
        T.step(function()
            self.unwatched = { status = T.clientStatus(bank), watchers = bank.state.watchers,
                resent = T.clientSummary(bank) ~= self.summary }
        end)
        T.watch(self, bank)
        T.bankPass(self, bank, 0)
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return status ~= nil and status.solarW == 0
        end, "this client's status of the watched bank's dark pass")
        T.step(function()
            self.watchers = bank.state.watchers
            PowerBank.unwatchStatus(player(), bank.object)
        end)
        T.waitFor(self, function() return T.clientStatus(bank) == nil end, "this client letting go of the status it stopped watching")
        -- The unwatch and the pass's call are separate packets, which a server may take in either order.
        T.serverUntil(self, "bankState", bank.position, function(state) return state.watchers == 0 end)
        T.bankPass(self, bank, 1000)
        T.step(function() self.stopped = { status = T.clientStatus(bank), watchers = bank.state.watchers } end)
    end,
    validate = function(self)
        local unwatched, stopped = self.unwatched, self.stopped
        if not expect(unwatched and stopped, "the queue stopped before the bank was watched and let go") then return end
        expect(unwatched.status == nil, "this client has the status of a bank nobody here watches")
        expect(unwatched.watchers == 0, unwatched.watchers .. " players watch a bank nobody opened")
        expect(not unwatched.resent, "a pass that changed nothing in the summary sent it again")
        expect(self.watchers == 1, tostring(self.watchers) .. " players watch the bank this client watches, expected 1")
        -- The wait after the unwatch already failed the test if this client kept the status.
        expect(stopped.watchers == 0, stopped.watchers .. " players still watch the bank after this client stopped")
        expect(stopped.status == nil, "a pass sent this client the status of a bank it stopped watching")
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
            for _, bank in ipairs({ self.far, self.near }) do
                T.server(self, "completeRename", { bank = bank.position, name = bank == self.far and "Far" or "Near" })
                T.step(function() bank.done = self.server.completeRename and self.server.completeRename.done end)
                T.bankState(self, bank)
            end
        end)
    end,
    validate = function(self)
        local far, near = self.far and self.far.state, self.near and self.near.state
        if not expect(far ~= nil and near ~= nil, "the server never reported the banks' states") then
            return
        end
        expect(not self.far.done and far.name == "", "an action from " .. FAR_TILES .. " squares away renamed the bank "
            .. tostring(far.name))
        expect(self.near.done and near.name == "Near", "renaming the bank beside the character left it called "
            .. tostring(near.name))
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
            T.perform(self, "rename", { bank = bank.position, name = "Cellar" })
            T.server(self, "rebuildBank", { bank = bank.position })
        end)
        T.waitFor(self, function()
            local rebuilt, summary = PowerBank.findOn(bank.square), PowerBank.summaryOf(bank.square)
            return rebuilt ~= nil and rebuilt ~= bank.object and summary ~= nil and summary.name == "Cellar"
        end, "this client's copy of the rebuilt bank, named")
    end,
    validate = function(self)
        if not T.expectConnected(self.panel) then return end
        local state, summary = self.server.rebuildBank, PowerBank.summaryOf(self.bank.square)
        expect(state.name == "Cellar", "the rebuilt bank is named " .. string.format("%q", tostring(state.name)))
        expect(state.sources == 1, "the rebuilt bank has " .. tostring(state.sources) .. " panels")
        expect(summary ~= nil and summary.name == "Cellar" and #summary.sources == 1,
            "this client's summary of the rebuilt bank names it " .. tostring(summary and summary.name)
            .. " with " .. tostring(summary and #summary.sources) .. " panels")
    end,
})

-- Connecting a panel brings the bank up to now first: the hour before the connect earns nothing for
-- it, the pass after does.
test("renewable_energy_bank_connect_credits_from_connection", {
    hour = 12,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY }, { charge = 0.5 })
        local panel = bank and T.panel(self, Sprites.flat, { near = bank })
        if not panel then return end
        T.batch(function()
            T.server(self, "ageBank", { bank = bank.position, hours = 1 })
            T.performInto(self, "connected", "connectSource", { bank = bank.position, source = panel.position })
            T.bankState(self, bank)
            T.step(function() self.afterConnect = bank.state end)
            T.bankPass(self, bank, 1000)
            T.step(function() self.afterPass = bank.state end)
        end)
    end,
    validate = function(self)
        if not T.expectOk(self.connected, "connecting the panel") then return end
        local connected, passed = self.afterConnect, self.afterPass
        expectNear("hours between the connect and the bank's last pass", connected.age - connected.lastHour, 0, 0.01)
        expectNear("solar Wh today credited for the hour before the connect", connected.solarWhToday, 0, 0)
        expect(passed.solarWhToday > 0, "the pass after the connect credited the panel nothing")
    end,
})

-- Switching a bank on brings it up to now first: the hour it stood off bills no load, the pass
-- after does. The Inverter/Charger carries whatever the house around switches on.
test("renewable_energy_bank_switch_on_bills_from_switch", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { CAR_BATTERY, INVERTER_CHARGER })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        T.placeTile(self, fridge, T.MINI_FRIDGE)
        T.batch(function()
            T.server(self, "ageBank", { bank = bank.position, hours = 1 })
            T.performInto(self, "switched", "setBankOn", { bank = bank.position, on = true })
            T.bankState(self, bank)
            T.step(function() self.afterSwitch = bank.state end)
            T.bankPass(self, bank, 0, { hours = 0.1 })
            T.step(function() self.afterPass = bank.state end)
        end)
    end,
    validate = function(self)
        if not T.expectOk(self.switched, "switching the bank on") then return end
        local switched, passed = self.afterSwitch, self.afterPass
        expect(switched.on, "setBankOn left the bank off")
        expectNear("hours between the switch and the bank's last pass", switched.age - switched.lastHour, 0, 0.01)
        expectNear("load Wh today billed for the hour the bank was off", switched.loadWhToday, 0, 0)
        expect(passed.loadWhToday > 0, "the pass after the switch billed the mini fridge nothing")
    end,
})

-- A pass the batteries can't last bills the load they carried: more than nothing, no more than
-- the energy they held less the inverter's losses.
test("renewable_energy_bank_empty_pass_bills_what_it_carried", {
    run = function(self)
        T.setGrid(self, false)
        local bank = T.bank(self, "batteryRackWood", { CAR_BATTERY, INVERTER_CHARGER }, { charge = 0.02 })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        T.placeTile(self, fridge, T.MINI_FRIDGE)
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
        expect(after.storedWh == 0 and after.status.state == "empty",
            "an hour of load left the bank at " .. after.storedWh .. " Wh, " .. after.status.state)
        local billed, most = after.loadWhToday - before.loadWhToday, before.storedWh * Specs.inverters[INVERTER_CHARGER].efficiency
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
        local bank = T.bank(self, "batteryRackWood", { CAR_BATTERY, INVERTER_CHARGER }, { charge = 0.9 })
        if not bank then return end
        T.give(self, "sledgehammer", { { type = "Base.Sledgehammer", equip = "primary" } })
        T.switchOn(self, bank)
        T.batch(function()
            T.server(self, "ageBank", { bank = bank.position, hours = 1 })
            T.bankState(self, bank)
        end)
        T.step(function() self.before = bank.state end)
        T.doJob(self, bank.square, function() return ISDestroyStuffAction:new(T.player(), bank.object) end)
        T.waitFor(self, function() return PowerBank.findOn(bank.square) == nil end, "the destroyed bank gone from this client")
        T.server(self, "takeFloorItems", { squares = { T.at(bank.square) } })
    end,
    validate = function(self)
        local battery
        for _, item in ipairs(self.server.takeFloorItems.items) do
            if item.type == CAR_BATTERY then
                battery = item
            end
        end
        if not expect(battery, "the destroyed bank left no battery on the floor") then return end
        local most = self.before.charge - Specs.inverters[INVERTER_CHARGER].idle / self.before.nominalWh
        expect(battery.uses <= most + 1e-4, "the battery left the destroyed bank at " .. battery.uses
            .. " after an hour on since its last pass at " .. self.before.charge .. ", expected at most " .. most)
    end,
})

-- How far the clock jumps. EveryTenMinutes fires on the next tick when the minute of the hour
-- lands in another ten (GameTime.update), which a jump of more than ten minutes past whole hours
-- always does; the gadget pass makes up for at most an hour.
local CLOCK_JUMP_HOURS = 1.25

-- The game's clock runs banks and gadgets on the authority: each fixture charges by more than
-- nothing and no more than full sun on its rating over the time its passes covered.
test("renewable_energy_bank_clock_drives_banks_and_gadgets", {
    hour = 12,
    instant = true,
    run = function(self)
        local bank = T.bank(self, "batteryBoxWood", { CAR_BATTERY }, { charge = 0.5 })
        local panel = bank and T.panel(self, Sprites.flat, { near = bank, connect = true })
        local squares = T.need(self, T.squares(self, 2, { bare = true }), "two bare outdoor squares for the gadgets")
        if not (panel and squares) then return end
        self.bank = bank
        T.watch(self, bank)
        local car = T.placeVehicle(self, "Base.CarNormal", { battery = CAR_BATTERY, charge = 0.5 })
        local trailer = T.placeVehicle(self, RenewableEnergy.ArrowBoard.SCRIPT)
        local charger = T.placeAsPlayer(self, squares[1], RenewableEnergy.SolarCellCharger.ITEM, Sprites.cellCharger)
        local light = T.placeAsPlayer(self, squares[2], SolarGardenLight.ITEM, Sprites.gardenLight.off)
        local function fixtures()
            return { bank = bank.position, car = T.vehicleArgs(car), trailer = T.vehicleArgs(trailer),
                charger = T.at(charger), light = T.at(light) }
        end
        T.server(self, "stockGadgets", fixtures)
        T.step(function()
            if not T.need(self, panel.connected, "a panel connected to the bank") then return end
            self.before = self.server.stockGadgets
            T.setTime(self, getGameTime():getTimeOfDay() + CLOCK_JUMP_HOURS)
        end)
        -- The bank's pass and the gadgets' run on the same tick; the bank's status coming back an
        -- hour on from its last pass says both have.
        T.waitFor(self, function()
            local status = T.clientStatus(bank)
            return status ~= nil and status.hour >= self.before.bankPassAge + 1
        end, "this client's status of the bank's pass an hour on")
        T.server(self, "gadgetCharges", fixtures)
    end,
    validate = function(self)
        local before, after = self.before, self.server.gadgetCharges
        if not expect(before and after, "the clock test's gadgets were never read before and after") then return end
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
    timeoutSeconds = 120,
    sandbox = { BatteryWear = 100 },
    run = function(self)
        T.setGrid(self, false)
        local parts = { JAR_BATTERY, INVERTER_CHARGER }
        for _ = 2, Specs.banks["RenewableEnergy.BatteryRackMetal"].maxBatteries do
            table.insert(parts, L16)
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
            T.server(self, "takePartWear", { bank = at, type = INVERTER_CHARGER, points = PRIMED_WEAR })
            T.step(function() self.left = bank.state end)
        end)
        T.reloadChunk(self, at, function()
            T.step(function() T.setTime(self, 24.01) end)
            T.serverUntil(self, "bankState", at, function(state)
                return state ~= nil and state.calendarDay ~= self.left.calendarDay
            end)
            T.bankPass(self, bank, 0, { hours = AWAY_HOURS })
            T.step(function() self.away = bank.state end)
        end)
        T.bankState(self, bank)
        T.waitFor(self, function()
            local copy = bankHere(at)
            local inverter = copy and copy:getContainer():getFirstType(INVERTER_CHARGER)
            return inverter ~= nil and inverter:getCondition() == T.stateCondition(bank.state, INVERTER_CHARGER)
        end, "this client's copy of the bank loaded again")
    end,
    validate = function(self)
        local away, back = self.away, self.bank.state
        expect(#away.items == 0, "the bank's chunk stayed loaded while the character was away")
        expect(away.calendarDay ~= self.left.calendarDay, "the day never turned while the bank was away")
        expect(away.status.state == "on" and away.charge < 1, string.format(
            "the bank away drew it to %.3f in %d hours, %s", away.charge, AWAY_HOURS, tostring(away.status.state)))
        local cameBack = {
            [JAR_BATTERY] = T.conditionAfterDischarge(JAR_BATTERY, self.left.cycleDepth),
            [L16] = T.conditionAfterDischarge(L16, self.left.cycleDepth),
            [INVERTER_CHARGER] = 100 - math.floor(PRIMED_WEAR + Specs.partWear.perHour.inverter * AWAY_HOURS),
        }
        expect(cameBack[JAR_BATTERY] < 100 and cameBack[INVERTER_CHARGER] < 100, string.format("a %.2f deep day and %d hours on"
            .. " don't wear both the jar battery and the inverter a whole point, so their wear can't show", self.left.cycleDepth, AWAY_HOURS))
        local function check(what, fullType, condition, uses)
            expectNear(what .. "'s condition", condition, cameBack[fullType], 0)
            if fullType ~= INVERTER_CHARGER then
                expectNear(what .. "'s charge", uses, away.charge, 0.001)
            end
        end
        expect(#back.items == #self.parts, "the bank came back holding " .. #back.items .. " of its " .. #self.parts .. " parts")
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
    timeoutSeconds = 120,
    run = function(self)
        T.setGrid(self, true)
        local stand = T.square(self, nil, "a free outdoor square to stand on")
        local bank = stand and T.bank(self, "batteryRackWood", { L16, L16, INVERTER_CHARGER }, { near = stand })
        local fridge = bank and T.square(self, { indoors = true, near = bank }, "a free indoor square for a fridge")
        if not fridge then return end
        self.bank = bank
        local at = bank.position
        T.switchOn(self, bank)
        T.step(function() self.fridge = T.placeTile(self, fridge, T.MINI_FRIDGE) end)
        T.bankPass(self, bank, 0)
        -- The fridge goes before the trip: unloaded, the bank keeps what it measured, and a tile in a
        -- chunk that loads again is a new copy the fixture's removal would miss.
        T.step(function()
            self.onGrid = bank.state
            PZHarness.Fixtures.removePlaced(self.fridge.object)
        end)
        T.reloadChunk(self, at, function()
            T.step(function() T.setGrid(self, false) end)
            T.bankPass(self, bank, 0, { hours = 2 })
            T.step(function() self.away = bank.state end)
        end)
    end,
    validate = function(self)
        local onGrid, away = self.onGrid, self.away
        expect(#away.items == 0, "the bank's chunk stayed loaded while the character was away")
        expect(onGrid.status.state == "grid" and onGrid.status.loadW >= T.fridgeW(), string.format(
            "on the grid the bank reads %s and measures %.1f W with a fridge on", tostring(onGrid.status.state), onGrid.status.loadW))
        expect(away.status.state == "on", "away with the grid gone the bank reads " .. tostring(away.status.state))
        expectNear("the load the bank carries away, against the one it measured on the grid", away.status.loadW, onGrid.status.loadW, 0)
        expect(away.drawW > onGrid.status.loadW, string.format("away the bank draws %.1f W for a load of %.1f W",
            away.drawW, onGrid.status.loadW))
        expect(away.charge < onGrid.charge, "away with the grid gone the bank's charge didn't fall")
        expect(away.status.chargeSource == nil, "away with the grid gone the chargers charge from " .. tostring(away.status.chargeSource))
    end,
})
