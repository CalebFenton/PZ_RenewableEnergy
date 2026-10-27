require "RenewableEnergy/Debug/RenewableEnergyTestLibArrowBoard"
local ArrowBoard = require "RenewableEnergy/ArrowBoard/Trailer"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local Specs = require "RenewableEnergy/Specs"

-- The arrow board's power (ArrowBoard/Power.lua): the panels charging the box, the lamps and
-- their flashing, and the box's discharge cycle.
-- Authority state goes through RenewableEnergyTestServerTrailer.lua; player actions go through
-- the vanilla and mod actions, checked on this client's copy.

local T = RenewableEnergyTest
local test, expect, expectEqual, expectNear = T.test, T.expect, T.expectEqual, T.expectNear
local spawnTrailer, batchOnTrailer, boxItems, modulesOnBothPanels = T.spawnTrailer, T.batchOnTrailer, T.boxItems, T.modulesOnBothPanels
local LEFT, RIGHT = T.BOARD_PANELS[1], T.BOARD_PANELS[2]

-- The panels charge the emptiest battery first, all of it while it has room; once all are full
-- the rest goes unstored.
test("renewable_energy_world_arrow_board_panels_charge_the_emptiest_battery", {
    hour = 12,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", {
                panels = modulesOnBothPanels(100),
                box = { { type = T.DEEP_CYCLE, charge = 0.6 }, { type = T.L16, charge = 0.2 } },
            })
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "charge", with = { 1 } }, "first")
            -- Little room in each: both fill, and the rest of the hour is lost.
            T.onVehicle(self, trailer, "setTrailer", { box = { { type = T.DEEP_CYCLE, charge = 0.99 }, { type = T.L16, charge = 0.99 } } })
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "charge", with = { 1 } }, "second")
        end)
    end,
    validate = function(self)
        local deepWh, l16Wh = Specs.batteries[T.DEEP_CYCLE].wh, Specs.batteries[T.L16].wh
        -- How watts follow condition is charge_scales_with_panel_condition's.
        local first, second = self.reads.first, self.reads.second
        local hourWh = first.watts * first.flatWh
        local room = 0.01 * (deepWh + l16Wh)
        if not expect(hourWh > room, "the sun at noon gives only " .. hourWh .. " Wh an hour, too little to fill both") then
            return
        end
        if not expect(hourWh <= (1 - 0.2) * l16Wh, "an hour's " .. hourWh .. " Wh overfills the empty L-16") then
            return
        end
        local deepCycle, l16 = boxItems(first.state)[1], boxItems(first.state)[2]
        expectNear("watt-hours stored in an hour", first.result, hourWh, 0.001)
        expectNear("the emptier L-16's charge", l16.charge, 0.2 + hourWh / l16Wh, 0.0001)
        expectNear("the fuller deep cycle's charge", deepCycle.charge, 0.6, 0.0001)
        expectNear("watt-hours stored with little room", second.result, room, 0.01)
        local full = boxItems(second.state)
        expectEqual("the deep cycle's charge with little room", full[1].charge, 1)
        expectEqual("the L-16's charge with little room", full[2].charge, 1)
    end,
})

-- Each installed panel makes power by its condition, a half-cracked one half what a whole one
-- does and a homemade one some, and with no panels the trailer stores nothing. The trailer reads
-- a module's watts with the mounts' own Panel.moduleWatts, so the checks compare the passes
-- with each other rather than with that function.
test("renewable_energy_world_arrow_board_charge_scales_with_panel_condition", {
    hour = 12,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        local function pass(label, panels, box)
            T.onVehicle(self, trailer, "setTrailer", { panels = panels, box = box })
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "charge", with = { 1 } }, label)
        end
        batchOnTrailer(function()
            pass("wholeAndHalf", { [LEFT] = { type = T.FACTORY_MODULE, condition = 100 }, [RIGHT] = { type = T.FACTORY_MODULE, condition = 50 } },
                { { type = T.L16, charge = 0 } })
            pass("whole", { [RIGHT] = {} })
            pass("homemade", { [LEFT] = { type = T.HOMEMADE_MODULE, condition = 60 } })
            pass("none", { [LEFT] = {} })
        end)
    end,
    validate = function(self)
        local both, homemade, none = self.reads.wholeAndHalf, self.reads.homemade, self.reads.none
        local flatWh = both.flatWh
        if not expect(flatWh > 0, "no sun at noon") then return end
        local whole = self.reads.whole.watts
        if not expect(whole > 0, "a whole panel made nothing at noon") then return end
        expectNear("watts of a half-cracked panel over a whole one", (both.watts - whole) / whole, 0.5, 0.001)
        expectNear("watt-hours they store in an hour", both.result, both.watts * flatWh, 0.001)
        expect(homemade.watts > 0 and homemade.watts < whole, "a homemade module at 60 makes " .. homemade.watts
            .. " W, expected some and less than a whole factory module's " .. whole)
        expectNear("watts with no panels", none.watts, 0)
        expectNear("watt-hours stored with no panels", none.result, 0)
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

-- The lamps light only while switched on with the lamp board intact: switching off or wrecking
-- the board darkens them, welding it relights them, and after dark the photocell sets night.
test("renewable_energy_world_arrow_board_lamps_follow_switch_board_and_photocell", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, board = self.trailer, ArrowBoard.BOARD
        self.stages = {}
        local function stage(name, args, night, want) lampStage(self, trailer, name, args, night, want) end
        batchOnTrailer(function()
            stage("switched on with a charged battery", { switchOn = true, box = { { type = T.DEEP_CYCLE, charge = 0.6 } } },
                false, "day")
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

-- Switched on in the noon sun with only a controller in the box, the pass stores nothing and the
-- lamps stay dark.
test("renewable_energy_world_arrow_board_lamps_stay_dark_without_batteries", {
    hour = 12,
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer = self.trailer
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", {
                switchOn = true, box = { { type = Specs.controller } }, panels = modulesOnBothPanels(100),
            })
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "update", with = { 1 } }, "update")
        end)
    end,
    validate = function(self)
        local answer = self.reads.update
        expect(answer.state.switchOn, "the switch isn't on")
        expectEqual("the lamps with no battery in the box", answer.state.lamps, nil)
        expectNear("watt-hours stored with no battery", answer.result, 0)
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

-- While the server has the lamps lit, this game flashes them lit and dark (ArrowBoard.flashPhase);
-- switched off, they stay dark for a whole flash period.
test("renewable_energy_world_arrow_board_lamps_flash_for_players", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer = self.trailer
        local period = 60000 / ArrowBoard.SPEC.flashesPerMinute
        -- Queues counting the frames the board shows lit and dark into self[key], until `enough`
        -- of them are seen or `ms` pass.
        local function watch(key, ms, enough)
            T.step(function()
                local seen = { lit = 0, dark = 0 }
                self[key] = seen
                T.waitUntil(function()
                    local lit = trailer.vehicle:getWindowLightsOn()
                    seen.lit, seen.dark = seen.lit + (lit and 1 or 0), seen.dark + (lit and 0 or 1)
                    return enough(seen)
                end, ms, "the lamps' flashes")
            end)
        end
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { switchOn = true, box = { { type = T.DEEP_CYCLE, charge = 0.8 } } })
            T.onVehicle(self, trailer, "arrowBoardRun", { call = "runLamps", with = { 0, false } })
        end)
        T.waitForVehicleCopy(self, trailer, function(copy) return copy.lamps == "day" end, "this client's copy of the lit lamps")
        watch("lit", 2 * period, function(seen) return seen.lit > 0 and seen.dark > 0 end)
        T.onVehicle(self, trailer, "setTrailer", { switchOn = false })
        T.waitForVehicleCopy(self, trailer, function(copy) return copy.lamps == nil end, "this client's copy of the dark lamps")
        watch("dark", period, function(seen) return seen.lit > 0 end)
    end,
    validate = function(self)
        local lit, dark = self.lit, self.dark
        expect(lit.lit > 0 and lit.dark > 0, string.format("lit, the board showed lit %d and dark %d frames", lit.lit, lit.dark))
        expect(dark.lit == 0, string.format("switched off, the board showed lit %d of %d frames", dark.lit, dark.lit + dark.dark))
    end,
})

-- The box's discharge cycle is the calendar day's: a pass just after midnight, half an hour after
-- the evening's, finishes the day and wears its battery by the day's depth, run flat from full;
-- the evening's passes wear nothing.
test("renewable_energy_world_arrow_board_cycle_ends_at_midnight", {
    sandbox = { BatteryWear = 100 },
    run = function(self)
        local trailer = spawnTrailer(self, { repair = true })
        if not trailer then return end
        -- readUntil sends its args as they are, so they carry the trailer's own.
        local function lampsArgs()
            local args = T.vehicleArgs(trailer)
            args.call, args.with = "runLamps", { 0, true }
            return args
        end
        T.step(function() T.setTime(self, 23.5) end)
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { box = { { type = T.CAR_BATTERY, charge = 1 } } })
            T.onVehicle(self, trailer, "arrowBoardRun", lampsArgs)
            T.onVehicle(self, trailer, "setTrailer", { box = { { type = T.CAR_BATTERY, charge = 0 } } })
            T.onVehicle(self, trailer, "arrowBoardRun", lampsArgs, "evening")
        end)
        T.step(function()
            self.full = instanceItem(T.CAR_BATTERY):getConditionMax()
            T.setTime(self, 24.01)
        end)
        T.readUntil(self, "arrowBoardRun", lampsArgs, "morning", function(reply)
            local battery = boxItems(reply.state, T.CAR_BATTERY)[1]
            return battery ~= nil and battery.condition < self.full
        end)
    end,
    validate = function(self)
        local new = instanceItem(T.CAR_BATTERY)
        local full = new:getConditionMax()
        local expected = full - math.floor(Battery.cycleWear(new, 1) * full)
        if not expect(expected < full, "a flat day wears a car battery less than a point, so its wear can't show") then return end
        local evening = boxItems(self.reads.evening.state, T.CAR_BATTERY)[1]
        expectEqual("the battery's condition after the evening's passes", evening and evening.condition, full)
        local morning = boxItems(self.reads.morning.state, T.CAR_BATTERY)[1]
        expectEqual("the battery's condition after midnight", morning and morning.condition, expected)
    end,
})
