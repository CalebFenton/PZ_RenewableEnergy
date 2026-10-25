require "RenewableEnergy/Debug/RenewableEnergyTestLibArrowBoard"

-- The arrow board's power (World/ArrowBoardPower.lua): the panels charging the box, the lamps and
-- their flashing, and the box's discharge cycle.
-- Authority state goes through RenewableEnergyTestServerTrailer.lua; player actions go through
-- the vanilla and mod actions, checked on this client's copy.

local T = RenewableEnergyTest
local test, expect, expectNear = T.test, T.expect, T.expectNear
local spawnTrailer, batchOnTrailer, boxItems, modulesOnBothPanels = T.spawnTrailer, T.batchOnTrailer, T.boxItems, T.modulesOnBothPanels
local LEFT, RIGHT = T.BOARD_PANELS[1], T.BOARD_PANELS[2]

local MODULE, HOMEMADE = RenewableEnergy.Specs.factoryModule, "RenewableEnergy.HomemadeSolarModule"
local DEEP_CYCLE, L16 = "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery"
local CAR_BATTERY = RenewableEnergy.VehicleBattery.CAR_BATTERY

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
                box = { { type = DEEP_CYCLE, charge = 0.6 }, { type = L16, charge = 0.2 } },
            })
            T.onVehicle(self, trailer, "arrowBoardCharge", { hours = 1 })
            T.step(function() self.first = trailer.answer end)
            -- Little room in each: both fill, and the rest of the hour is lost.
            T.onVehicle(self, trailer, "setTrailer", { box = { { type = DEEP_CYCLE, charge = 0.99 }, { type = L16, charge = 0.99 } } })
            T.onVehicle(self, trailer, "arrowBoardCharge", { hours = 1 })
            T.step(function() self.second = trailer.answer end)
        end)
    end,
    validate = function(self)
        local Specs = RenewableEnergy.Specs
        local deepWh, l16Wh = Specs.batteries[DEEP_CYCLE].wh, Specs.batteries[L16].wh
        -- How watts follow condition is charge_scales_with_panel_condition's.
        local hourWh = self.first.watts * self.first.flatWh
        local room = 0.01 * (deepWh + l16Wh)
        if not expect(hourWh > room, "the sun at noon gives only " .. hourWh .. " Wh an hour, too little to fill both") then
            return
        end
        if not expect(hourWh <= (1 - 0.2) * l16Wh, "an hour's " .. hourWh .. " Wh overfills the empty L-16") then
            return
        end
        local deepCycle, l16 = boxItems(self.first.state)[1], boxItems(self.first.state)[2]
        expectNear("watt-hours stored in an hour", self.first.stored, hourWh, 0.001)
        expectNear("the emptier L-16's charge", l16.charge, 0.2 + hourWh / l16Wh, 0.0001)
        expectNear("the fuller deep cycle's charge", deepCycle.charge, 0.6, 0.0001)
        expectNear("watt-hours stored with little room", self.second.stored, room, 0.01)
        local full = boxItems(self.second.state)
        expect(full[1].charge == 1 and full[2].charge == 1, "the batteries aren't full: " .. full[1].charge .. ", " .. full[2].charge)
    end,
})

-- Each installed panel makes power by its condition, a half-cracked one half what a whole one
-- does and a homemade one some, and with no panels the trailer stores nothing. The trailer reads
-- a module's watts with the mounts' own PowerBank.moduleWatts, so the checks compare the passes
-- with each other rather than with that function.
test("renewable_energy_world_arrow_board_charge_scales_with_panel_condition", {
    hour = 12,
    run = function(self)
        if not spawnTrailer(self) then return end
        local trailer = self.trailer
        self.passes = {}
        local function pass(panels, box)
            T.onVehicle(self, trailer, "setTrailer", { panels = panels, box = box })
            T.onVehicle(self, trailer, "arrowBoardCharge", { hours = 1 })
            T.step(function() table.insert(self.passes, trailer.answer) end)
        end
        batchOnTrailer(function()
            pass({ [LEFT] = { type = MODULE, condition = 100 }, [RIGHT] = { type = MODULE, condition = 50 } },
                { { type = L16, charge = 0 } })
            pass({ [RIGHT] = {} })
            pass({ [LEFT] = { type = HOMEMADE, condition = 60 } })
            pass({ [LEFT] = {} })
        end)
    end,
    validate = function(self)
        local p = self.passes
        local flatWh = p[1].flatWh
        if not expect(flatWh > 0, "no sun at noon") then return end
        local whole = p[2].watts
        if not expect(whole > 0, "a whole panel made nothing at noon") then return end
        expectNear("watts of a half-cracked panel over a whole one", (p[1].watts - whole) / whole, 0.5, 0.001)
        expectNear("watt-hours they store in an hour", p[1].stored, p[1].watts * flatWh, 0.001)
        expect(p[3].watts > 0 and p[3].watts < whole, "a homemade module at 60 makes " .. p[3].watts
            .. " W, expected some and less than a whole factory module's " .. whole)
        expectNear("watts with no panels", p[4].watts, 0)
        expectNear("watt-hours stored with no panels", p[4].stored, 0)
    end,
})

-- Lamps -----------------------------------------------------------------------------------------

-- Queues `args` set on the trailer and a zero-hour pass of its lamps, the photocell seeing dark
-- if `night`, noting in self.stages whether the lamps then show `want` ("day", "night", or nil for
-- dark).
local function lampStage(self, trailer, name, args, night, want)
    T.onVehicle(self, trailer, "setTrailer", args)
    T.onVehicle(self, trailer, "arrowBoardLamps", { hours = 0, night = night })
    T.step(function() table.insert(self.stages, { name = name, want = want, lamps = trailer.answer.state.lamps }) end)
end

local function expectLampStages(stages)
    for _, stage in ipairs(stages) do
        expect(stage.lamps == stage.want, "the lamps " .. stage.name .. " are " .. tostring(stage.lamps or "dark")
            .. ", expected " .. tostring(stage.want or "dark"))
    end
end

-- The lamps light only while switched on with the lamp board intact: switching off or wrecking
-- the board darkens them, welding it relights them, and after dark the photocell sets night.
test("renewable_energy_world_arrow_board_lamps_follow_switch_board_and_photocell", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, board = self.trailer, RenewableEnergy.ArrowBoard.BOARD
        self.stages = {}
        local function stage(name, args, night, want) lampStage(self, trailer, name, args, night, want) end
        batchOnTrailer(function()
            stage("switched on with a charged battery", { switchOn = true, box = { { type = DEEP_CYCLE, charge = 0.6 } } },
                false, "day")
            stage("after dark", {}, true, "night")
            stage("switched off", { switchOn = false }, false, nil)
            stage("on with its lamp board wrecked", { switchOn = true, frame = { [board] = 0 } }, false, nil)
            stage("on with its lamp board welded", { frame = { [board] = 100 } }, false, "day")
        end)
    end,
    validate = function(self)
        expectLampStages(self.stages)
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
                switchOn = true, box = { { type = RenewableEnergy.Specs.controller } }, panels = modulesOnBothPanels(100),
            })
            T.onVehicle(self, trailer, "arrowBoardUpdate", { hours = 1 })
        end)
    end,
    validate = function(self)
        local answer = self.trailer.answer
        expect(answer.state.switchOn, "the switch isn't on")
        expect(answer.state.lamps == nil, "the lamps are " .. tostring(answer.state.lamps) .. " with no battery in the box")
        expectNear("watt-hours stored with no battery", answer.stored, 0)
    end,
})

-- Lit, by day or night, the lamps drain Specs.arrowBoard.lampShare of a car battery an hour.
test("renewable_energy_world_arrow_board_lamps_drain_a_lightbars_share", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer = self.trailer
        local function lamps(hours, night, key)
            T.onVehicle(self, trailer, "arrowBoardLamps", { hours = hours, night = night })
            if key then
                T.step(function() self[key] = trailer.answer end)
            end
        end
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { switchOn = true, box = { { type = CAR_BATTERY, charge = 0.8 } } })
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
            local battery = boxItems(answer.state, CAR_BATTERY)[1]
            return battery and battery.charge or -1
        end
        local share = 2 * RenewableEnergy.Specs.arrowBoard.lampShare
        expectNear("the car battery's charge after two hours lit by day", charge(self.day), 0.8 - share, 2e-5)
        expectNear("the car battery's charge after two more hours lit at night", charge(self.night), 0.8 - 2 * share, 3e-5)
    end,
})

-- The controller cuts the lamps off once every battery is down to its cutoff, drawing none below
-- it, and relights them only at the reconnect level. Charges are whole uses, so each boundary is
-- probed one use either side; the panels charging back past reconnect relight them.
test("renewable_energy_world_arrow_board_lamps_cut_off_and_come_back", {
    hour = 12,
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer, spec = self.trailer, RenewableEnergy.Specs.arrowBoard
        local use = instanceItem(DEEP_CYCLE):getUseDelta()
        self.use, self.stages = use, {}
        local function stage(name, args, want) lampStage(self, trailer, name, args, false, want) end
        local function battery(charge)
            return { { type = DEEP_CYCLE, charge = charge } }
        end
        batchOnTrailer(function()
            stage("lit, a use above the cutoff", { switchOn = true, panels = { [LEFT] = {}, [RIGHT] = {} },
                box = battery(spec.cutoff + use) }, "day")
            T.onVehicle(self, trailer, "arrowBoardLamps", { hours = 2, night = false })
            T.step(function() self.cut = trailer.answer end)
            stage("cut off, a use above the cutoff", { box = battery(spec.cutoff + use) }, nil)
            stage("cut off, a use under the reconnect level", { box = battery(spec.reconnect - use) }, nil)
            stage("cut off, at the reconnect level", { box = battery(spec.reconnect) }, "day")
            stage("lit, set to the cutoff", { box = battery(spec.cutoff) }, nil)
            -- A few hours of noon sun on two whole panels put it back over the reconnect level.
            T.onVehicle(self, trailer, "setTrailer", { panels = modulesOnBothPanels(100), box = battery(spec.reconnect - use) })
            T.onVehicle(self, trailer, "arrowBoardUpdate", { hours = 3 })
            T.step(function() self.charged = trailer.answer end)
        end)
    end,
    validate = function(self)
        local spec, wh = RenewableEnergy.Specs.arrowBoard, RenewableEnergy.Specs.batteries[DEEP_CYCLE].wh
        expectLampStages(self.stages)
        -- A battery's charge is read back as a 32-bit float.
        expectNear("watt-hours drawn down to the cutoff", self.cut.drawn, self.use * wh, 1e-3)
        local battery = boxItems(self.cut.state, DEEP_CYCLE)[1]
        expectNear("the battery's charge once cut off", battery.charge, spec.cutoff, 1e-6)
        expect(self.cut.state.lamps == nil, "the lamps are " .. tostring(self.cut.state.lamps) .. " drawn down to the cutoff")
        local charged = boxItems(self.charged.state, DEEP_CYCLE)[1]
        if not expect(charged.charge >= spec.reconnect, "the panels left the battery at " .. charged.charge
            .. ", too little sun to show the lamps coming back") then
            return
        end
        expect(self.charged.state.lamps == "day", "the lamps are " .. tostring(self.charged.state.lamps)
            .. " with the battery charged back to " .. charged.charge)
    end,
})

-- The frames a watch of the lamps may take at most: far more than its real time needs at any
-- frame rate.
local FLASH_WATCH_FRAMES = 100000

-- While the server has the lamps lit, this game flashes them lit and dark (ArrowBoard.flashPhase);
-- switched off, they stay dark for a whole flash period.
test("renewable_energy_world_arrow_board_lamps_flash_for_players", {
    run = function(self)
        if not spawnTrailer(self, { repair = true }) then return end
        local trailer = self.trailer
        local period = 60000 / RenewableEnergy.Specs.arrowBoard.flashesPerMinute
        -- Queues counting the frames the board shows lit and dark into self[key], until `enough`
        -- of them are seen or `ms` pass.
        local function watch(key, ms, enough)
            T.step(function()
                local seen = { lit = 0, dark = 0, start = getTimestampMs() }
                self[key] = seen
                T.waitUntil(function()
                    local lit = trailer.vehicle:getWindowLightsOn()
                    seen.lit, seen.dark = seen.lit + (lit and 1 or 0), seen.dark + (lit and 0 or 1)
                    return enough(seen) or getTimestampMs() - seen.start >= ms
                end, FLASH_WATCH_FRAMES, "the lamps' flashes")
            end)
        end
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { switchOn = true, box = { { type = DEEP_CYCLE, charge = 0.8 } } })
            T.onVehicle(self, trailer, "arrowBoardLamps", { hours = 0, night = false })
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
        -- serverUntil sends its args as they are, so they carry the trailer's own.
        local function lampsArgs()
            local args = T.vehicleArgs(trailer)
            args.hours, args.night = 0, true
            return args
        end
        T.step(function() T.setTime(self, 23.5) end)
        batchOnTrailer(function()
            T.onVehicle(self, trailer, "setTrailer", { box = { { type = CAR_BATTERY, charge = 1 } } })
            T.onVehicle(self, trailer, "arrowBoardLamps", lampsArgs)
            T.onVehicle(self, trailer, "setTrailer", { box = { { type = CAR_BATTERY, charge = 0 } } })
            T.onVehicle(self, trailer, "arrowBoardLamps", lampsArgs)
            T.step(function() self.evening = trailer.state end)
        end)
        T.step(function()
            self.full = instanceItem(CAR_BATTERY):getConditionMax()
            T.setTime(self, 24.01)
        end)
        T.serverUntil(self, "arrowBoardLamps", lampsArgs, function(reply)
            local battery = boxItems(reply.state, CAR_BATTERY)[1]
            return battery ~= nil and battery.condition < self.full
        end)
        T.step(function() trailer.state = self.server.arrowBoardLamps.state end)
    end,
    validate = function(self)
        local new = instanceItem(CAR_BATTERY)
        local full = new:getConditionMax()
        local expected = full - math.floor(RenewableEnergy.Battery.cycleWear(new, 1) * full)
        if not expect(expected < full, "a flat day wears a car battery less than a point, so its wear can't show") then return end
        local evening = boxItems(self.evening, CAR_BATTERY)[1]
        expect(evening ~= nil and evening.condition == full, "the evening's passes left the battery at "
            .. tostring(evening and evening.condition))
        local morning = boxItems(self.trailer.state, CAR_BATTERY)[1]
        expect(morning ~= nil and morning.condition == expected, "after midnight the battery is at "
            .. tostring(morning and morning.condition) .. ", expected " .. expected)
    end,
})
