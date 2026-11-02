require "RenewableEnergy/Debug/RenewableEnergyTestLibArrowBoard"
local ArrowBoard = require "RenewableEnergy/ArrowBoard/Trailer"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local Specs = require "RenewableEnergy/Specs"
local Items = require "cf_commonlib/Items"

-- The arrow board's power (ArrowBoard/Power.lua): the panels charging the box, the lamps and
-- their flashing, and the box's discharge cycle.
-- Authority state goes through RenewableEnergyTestServerTrailer.lua; player actions go through
-- the vanilla and mod actions, checked on this client's copy.

local T = RenewableEnergyTest
local test, expect, expectEqual, expectNear = T.test, T.expect, T.expectEqual, T.expectNear
local spawnTrailer, batchOnTrailer, boxItems, modulesOnBothPanels = T.spawnTrailer, T.batchOnTrailer, T.boxItems, T.modulesOnBothPanels
local LEFT, RIGHT = ArrowBoard.PANELS[1], ArrowBoard.PANELS[2]

-- Each installed panel makes power by its module's condition, a half-cracked one half what a whole
-- one does and a new homemade one, capped lower, less than a new factory one; the trailer stores
-- nothing without panels or without a battery. The trailer reads a module's watts with the mounts'
-- own Panel.moduleWatts, so the checks compare the passes with each other rather than with that
-- function. An hour's output goes to the emptiest battery first, all of it while that has room;
-- once all are full the rest goes unstored.
test("renewable_energy_world_arrow_board_panels_charge_the_box", {
    hour = 12,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        local function pass(label, args)
            T.onVehicle(self, trailer, "setTrailer", args)
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "charge", with = { 1 } }, label)
        end
        local function battery(type, charge)
            return { type = type, charge = charge }
        end
        local function new(type)
            return { type = type, condition = Items.conditionMaxOf(type) }
        end
        batchOnTrailer(function()
            pass("whole", { panels = { [LEFT] = new(T.FACTORY_MODULE), [RIGHT] = {} }, box = { battery(T.L16, 0) } })
            pass("wholeAndHalf", { panels = { [RIGHT] = { type = T.FACTORY_MODULE, condition = math.floor(Items.conditionMaxOf(T.FACTORY_MODULE) / 2) } } })
            pass("homemade", { panels = { [LEFT] = new(T.HOMEMADE_MODULE), [RIGHT] = {} } })
            pass("none", { panels = { [LEFT] = {} } })
            pass("emptiest", { panels = modulesOnBothPanels(100), box = { battery(T.DEEP_CYCLE, 0.6), battery(T.L16, 0.2) } })
            -- Little room in each: both fill, and the rest of the hour is lost.
            pass("full", { box = { battery(T.DEEP_CYCLE, 0.99), battery(T.L16, 0.99) } })
            pass("noBattery", { box = { { type = Specs.controller } } })
        end)
    end,
    validate = function(self)
        local reads = self.reads
        local flatWh = reads.whole.flatWh
        if not expect(flatWh > 0, "no sun at noon") then return end
        local whole = reads.whole.watts
        if not expect(whole > 0, "a whole panel made nothing at noon") then return end
        expectNear("watt-hours a whole panel stores in an hour", reads.whole.result, whole * flatWh, 0.001)
        expectNear("watts of a half-cracked panel over a whole one", (reads.wholeAndHalf.watts - whole) / whole, 0.5, 0.001)
        expect(reads.homemade.watts > 0 and reads.homemade.watts < whole, "a new homemade module makes "
            .. reads.homemade.watts .. " W, expected some and less than a new factory module's " .. whole)
        expectNear("watt-hours stored with no panels", reads.none.result, 0)
        expectNear("watt-hours stored with no battery", reads.noBattery.result, 0)

        local deepWh, l16Wh = Specs.batteries[T.DEEP_CYCLE].wh, Specs.batteries[T.L16].wh
        local emptiest, full = reads.emptiest, reads.full
        local hourWh = emptiest.watts * flatWh
        local room = 0.01 * (deepWh + l16Wh)
        if not expect(hourWh > room, "the sun at noon gives only " .. hourWh .. " Wh an hour, too little to fill both") then
            return
        end
        if not expect(hourWh <= (1 - 0.2) * l16Wh, "an hour's " .. hourWh .. " Wh overfills the empty L-16") then
            return
        end
        local deepCycle, l16 = boxItems(emptiest.state)[1], boxItems(emptiest.state)[2]
        expectNear("the emptier L-16's charge", l16.charge, 0.2 + hourWh / l16Wh, 0.0001)
        expectNear("the fuller deep cycle's charge", deepCycle.charge, 0.6, 0.0001)
        expectNear("watt-hours stored with little room", full.result, room, 0.01)
        local filled = boxItems(full.state)
        expectEqual("the deep cycle's charge with little room", filled[1].charge, 1)
        expectEqual("the L-16's charge with little room", filled[2].charge, 1)
    end,
})

-- Lamps -----------------------------------------------------------------------------------------

-- Queues `args` set on the trailer and a zero-hour pass of its lamps, the photocell seeing dark
-- if `night`, noting in self.stages that the lamps should then show `want` ("day", "night", or nil
-- for dark); the pass's answer goes in self.reads[name].
local function lampStage(self, trailer, name, args, night, want)
    table.insert(self.stages, { name = name, want = want or "dark" })
    T.onVehicle(self, trailer, "setTrailer", args)
    T.onVehicle(self, trailer, "arrowBoardRun", { call = "runLamps", with = { 0, night } }, name)
end

local function expectLampStages(self)
    for _, stage in ipairs(self.stages) do
        expectEqual("the lamps " .. stage.name, self.reads[stage.name].state.lamps or "dark", stage.want)
    end
end

-- The lamps light only while switched on with the lamp board intact and a battery in the box:
-- switching off or wrecking the board darkens them, welding it relights them, and after dark the
-- photocell sets night.
test("renewable_energy_world_arrow_board_lamps_follow_switch_board_and_photocell", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, board = self.trailer, ArrowBoard.BOARD
        self.stages = {}
        local function stage(name, args, night, want) lampStage(self, trailer, name, args, night, want) end
        batchOnTrailer(function()
            stage("switched on with only a controller in the box", { switchOn = true, box = { { type = Specs.controller } } },
                false, nil)
            stage("switched on with a charged battery", { box = { { type = T.DEEP_CYCLE, charge = 0.6 } } }, false, "day")
            stage("after dark", {}, true, "night")
            stage("switched off", { switchOn = false }, false, nil)
            stage("on with its lamp board wrecked", { switchOn = true, frame = { [board] = 0 } }, false, nil)
            stage("on with its lamp board welded", { frame = { [board] = 100 } }, false, "day")
        end)
    end,
    validate = function(self)
        expectLampStages(self)
    end,
})

-- Lit, by day or night, the lamps drain ArrowBoard.SPEC.lampShare of a car battery an hour.
test("renewable_energy_world_arrow_board_lamps_drain_a_lightbars_share", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer = self.trailer
        local function lamps(hours, night, label)
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "runLamps", with = { hours, night } }, label)
        end
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { switchOn = true, box = { { type = T.CAR_BATTERY, charge = 0.8 } } })
            -- A pass draws at the lamps' current state and only then sets it for `night`
            -- (ArrowBoard.runLamps), so a zero-hour pass sets the state the measured pass draws at.
            lamps(0, false)
            lamps(2, false, "day")
            lamps(0, true)
            lamps(2, true, "night")
        end)
    end,
    validate = function(self)
        -- A battery's charge is kept in whole uses of its UseDelta, which each pass rounds to.
        local function charge(answer)
            local battery = boxItems(answer.state, T.CAR_BATTERY)[1]
            return battery and battery.charge or -1
        end
        local share = 2 * ArrowBoard.SPEC.lampShare
        expectNear("the car battery's charge after two hours lit by day", charge(self.reads.day), 0.8 - share, 2e-5)
        expectNear("the car battery's charge after two more hours lit at night", charge(self.reads.night), 0.8 - 2 * share, 3e-5)
    end,
})

-- The controller cuts the lamps off once every battery is down to its cutoff, drawing none below
-- it, and relights them only at the reconnect level. Charges are whole uses, so each boundary is
-- probed one use either side; the panels charging back past reconnect relight them.
test("renewable_energy_world_arrow_board_lamps_cut_off_and_come_back", {
    hour = 12,
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, spec = self.trailer, ArrowBoard.SPEC
        local use = instanceItem(T.DEEP_CYCLE):getUseDelta()
        self.use, self.stages = use, {}
        local function stage(name, args, want) lampStage(self, trailer, name, args, false, want) end
        local function battery(charge)
            return { { type = T.DEEP_CYCLE, charge = charge } }
        end
        batchOnTrailer(function()
            stage("lit, a use above the cutoff", { switchOn = true, panels = { [LEFT] = {}, [RIGHT] = {} },
                box = battery(spec.cutoff + use) }, "day")
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "runLamps", with = { 2, false } }, "cut")
            stage("cut off, a use above the cutoff", { box = battery(spec.cutoff + use) }, nil)
            stage("cut off, a use under the reconnect level", { box = battery(spec.reconnect - use) }, nil)
            stage("cut off, at the reconnect level", { box = battery(spec.reconnect) }, "day")
            stage("lit, set to the cutoff", { box = battery(spec.cutoff) }, nil)
            -- A few hours of noon sun on two whole panels put it back over the reconnect level.
            T.onVehicle(self, trailer, "setTrailer", { panels = modulesOnBothPanels(100), box = battery(spec.reconnect - use) })
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "update", with = { 3 } }, "charged")
        end)
    end,
    validate = function(self)
        local spec, wh = ArrowBoard.SPEC, Specs.batteries[T.DEEP_CYCLE].wh
        expectLampStages(self)
        -- A battery's charge is read back as a 32-bit float.
        local cut, chargedState = self.reads.cut.state, self.reads.charged.state
        expectNear("watt-hours drawn down to the cutoff", self.reads.cut.result, self.use * wh, 1e-3)
        expectNear("the battery's charge once cut off", boxItems(cut, T.DEEP_CYCLE)[1].charge, spec.cutoff, 1e-6)
        expectEqual("the lamps drawn down to the cutoff", cut.lamps, nil)
        local charged = boxItems(chargedState, T.DEEP_CYCLE)[1]
        if not expect(charged.charge >= spec.reconnect, "the panels left the battery at " .. charged.charge
            .. ", too little sun to show the lamps coming back") then
            return
        end
        expectEqual("the lamps with the battery charged back to " .. charged.charge, chargedState.lamps, "day")
    end,
})

-- While the server has the lamps lit, this game flashes the board lit and dark by the real clock,
-- lit for SPEC.onShare of each of SPEC.flashesPerMinute flashes, and at night also lights the
-- ground, through dark flashes too; switched off, it shows neither. Each look feeds this game's
-- flash (ArrowBoard.flashLamps) both phases rather than waiting for them.
test("renewable_energy_world_arrow_board_lamps_flash_for_players", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, spec = self.trailer, ArrowBoard.SPEC
        self.period = 60000 / spec.flashesPerMinute
        self.looks = {}
        -- Queues a wait for this client's copy of the lamps at `lamps`, then notes what this game
        -- shows of them in a lit and a dark flash.
        local function look(name, lamps)
            T.waitForVehicleCopy(self, trailer, function(copy) return copy.lamps == lamps end,
                "this client's copy of the lamps " .. name)
            T.step(function()
                local vehicle = trailer.vehicle
                local entry = ArrowBoard.trailerEntry(vehicle)
                if not T.need(self, entry.box, "this game's flashing of the lamps") then return end
                local shown = { name = name }
                ArrowBoard.flashLamps(vehicle, entry, true)
                shown.lit, shown.litGround = vehicle:getWindowLightsOn(), entry.light ~= nil
                ArrowBoard.flashLamps(vehicle, entry, false)
                shown.dark, shown.darkGround = vehicle:getWindowLightsOn(), entry.light ~= nil
                self.looks[name] = shown
            end)
        end
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { switchOn = true, box = { { type = T.DEEP_CYCLE, charge = 0.8 } } })
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "runLamps", with = { 0, false } })
        end)
        look("by day", "day")
        -- The game's own frames flash the board, both ways within a flash.
        local seen = {}
        T.waitFor(self, function()
            seen[trailer.vehicle:getWindowLightsOn()] = true
            return seen[true] and seen[false]
        end, "the board flashing lit and dark by itself", self.period)
        T.onVehicle(self, trailer, "arrowBoardRun", { call = "runLamps", with = { 0, true } })
        look("at night", "night")
        T.onVehicle(self, trailer, "setTrailer", { switchOn = false })
        look("switched off", nil)
    end,
    validate = function(self)
        local looks = self.looks
        for name, want in pairs({ ["by day"] = { lit = true, ground = false }, ["at night"] = { lit = true, ground = true },
            ["switched off"] = { lit = false, ground = false } }) do
            local shown = looks[name]
            expectEqual("the board " .. name .. " in a lit flash", shown.lit, want.lit)
            expectEqual("the board " .. name .. " in a dark flash", shown.dark, false)
            expectEqual("the ground lit " .. name .. " in a lit flash", shown.litGround, want.ground)
            expectEqual("the ground lit " .. name .. " in a dark flash", shown.darkGround, want.ground)
        end
        local litMs = self.period * ArrowBoard.SPEC.onShare
        local phases = {}
        for _, ms in ipairs({ 0, litMs - 1, litMs, self.period - 1, self.period }) do
            table.insert(phases, tostring(ArrowBoard.flashPhase(ms)))
        end
        expectEqual("the flash lit at the start of a flash, at the end of its lit share, then dark from it to the next",
            table.concat(phases, ","), "true,true,false,false,true")
    end,
})

-- The box's discharge cycle is the calendar day's: a lamp pass across midnight finishes the day
-- and wears its battery by the day's depth, run down from full, what the lamps drew before
-- midnight included; what they drew after starts the next day's. The evening's passes wear nothing.
-- The lamps stay lit only above the controller's cutoff, too shallow a day for a point of wear at
-- the usual Battery Wear.
local EVENING_CHARGE, PASS_HOURS, PAST_MIDNIGHT = 0.2, 0.6, 0.5
test("renewable_energy_world_arrow_board_cycle_ends_at_midnight", {
    sandbox = { BatteryWear = 1000 },
    run = function(self)
        local trailer = spawnTrailer(self, { repair = true })
        if not trailer then return end
        local function lampsArgs(hours)
            return { call = "runLamps", with = { hours, true } }
        end
        -- The clock stands still at the same minutes past the hour on both sides of midnight, so
        -- the gadgets' ten-minute pass never runs (GameTime.update) and the test's pass is the one
        -- that crosses midnight; a server frame between them lets the clock step at 23:30 first
        -- (as in renewable_energy_battery_depth_of_discharge_wears_batteries).
        T.step(function()
            T.setMultiplier(self, 0)
            T.setTime(self, 23.5)
        end)
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { box = { { type = T.CAR_BATTERY, charge = 1 } }, switchOn = true })
            T.onVehicle(self, trailer, "arrowBoardRun", lampsArgs(0))
            T.onVehicle(self, trailer, "setTrailer", { box = { { type = T.CAR_BATTERY, charge = EVENING_CHARGE } } })
            T.onVehicle(self, trailer, "arrowBoardRun", lampsArgs(0), "evening")
        end)
        T.awaitServerFrame(self)
        T.step(function() T.setTime(self, 24 + PAST_MIDNIGHT) end)
        T.serverUntil(self, "vehicleState", function() return T.at(trailer, { id = trailer.id }) end, function(reply)
            return reply.state.calendarDay ~= self.reads.evening.state.calendarDay
        end)
        T.onVehicle(self, trailer, "arrowBoardRun", lampsArgs(PASS_HOURS), "morning")
    end,
    validate = function(self)
        local evening, morning = self.reads.evening.state, self.reads.morning.state
        local before, after = boxItems(evening, T.CAR_BATTERY)[1], boxItems(morning, T.CAR_BATTERY)[1]
        if not (expect(before and after, "no car battery in the box")
            and expect(evening.lamps ~= nil, "the lamps weren't lit in the evening")) then return end
        local full = instanceItem(T.CAR_BATTERY):getConditionMax()
        expectEqual("the battery's condition after the evening's passes", before.condition, full)
        local drawn = before.charge - after.charge
        if not expect(drawn > 0, "the lamps drew nothing across midnight") then return end
        local afterMidnight = drawn * PAST_MIDNIGHT / PASS_HOURS
        local expected = T.conditionAfterDischarge(T.CAR_BATTERY, 1 - EVENING_CHARGE + drawn - afterMidnight)
        if not expect(expected < full, "the day's depth wears a car battery less than a point, so its wear can't show") then return end
        expectEqual("the battery's condition after midnight", after.condition, expected)
        expectNear("the box's cycle depth on the new day, the draw after midnight", morning.box.cycleDepth, afterMidnight, 1e-4)
    end,
})
