require "RenewableEnergy/Debug/RenewableEnergyTestLib"

-- Arrow board crashes (World/ArrowBoardCrashes.lua): the crash watcher, and the server's gate on
-- the crash a driver's client reports. Both are fed their inputs: a trailer's velocities, and
-- stand-ins for the trailer and the car towing it.

local T = RenewableEnergyTest
local test, expect, player = T.test, T.expect, T.player

-- The crash watcher (ArrowBoard.sampleCrash), fed a frame at a time the velocities a trailer would
-- show, tells a crash from what isn't one: a speed change of a crash's worth within the window is
-- one, into a parked trailer, at speed, sideways too; a bump, or braking spread past the window,
-- isn't; a jolt soon after one, as the hitch brings a trailer up short, is the same crash, and
-- one after the quiet time a new one.
test("renewable_energy_world_arrow_board_crash_watch_tells_crashes", {
    instant = true,
    validate = function()
        local ArrowBoard = RenewableEnergy.ArrowBoard
        local crash = ArrowBoard.CRASH
        local crashMs, frame = crash.kmh / 3.6, 16
        local cruise, stopped = { 0, -30 / 3.6 }, { 0, 0 }
        -- Feeds `ground` velocities in m/s ({ x, y }, or "rest") one frame apart into a new watch;
        -- answers the frames that began a new crash, joined with commas.
        local function crashes(ground)
            local watch, found = ArrowBoard.newCrashWatch(), {}
            for i, v in ipairs(ground) do
                local atRest = v == "rest"
                if ArrowBoard.sampleCrash(watch, i * frame, atRest and 0 or v[1], atRest and 0 or v[2], atRest) then
                    table.insert(found, i)
                end
            end
            return table.concat(found, ",")
        end
        -- `list` with `frames` more frames at velocity `v`.
        local function hold(list, v, frames)
            for _ = 1, frames do
                table.insert(list, v)
            end
            return list
        end
        local function cruising(after)
            local list = hold({}, cruise, 5)
            table.insert(list, after)
            return list
        end

        expect(crashes({ "rest", { 0, -1.01 * crashMs } }) == "2", "a crash's jolt into a parked trailer went unseen")
        expect(crashes({ "rest", { 0, -0.99 * crashMs } }) == "", "a jolt just short of a crash's into a parked trailer cracked it")
        expect(crashes(cruising(stopped)) == "6", "stopping dead from 30 km/h went unseen")
        expect(crashes(cruising({ 1.01 * crashMs, cruise[2] })) == "6", "a crash's jolt sideways went unseen")
        expect(crashes(cruising({ 0, cruise[2] + 6 / 3.6 })) == "", "a bump of 6 km/h cracked the panels")
        -- Off 30 km/h over twice the window, the window sees half the speed shed.
        local braking, frames = {}, math.ceil(2 * crash.ms / frame)
        for i = 0, frames do
            table.insert(braking, { 0, cruise[2] * (1 - i / frames) })
        end
        expect(crashes(braking) == "", "braking to a stop over " .. frames * frame .. " ms cracked the panels")

        -- Stopped dead, thrown forward on the hitch 600 ms later, then stopped dead again once
        -- the throw has been out of the window for the quiet time.
        local hits = hold(cruising(stopped), stopped, math.floor(600 / frame))
        table.insert(hits, { 0, -1.01 * crashMs })
        local rebound = #hits
        hold(hits, { 0, -1.01 * crashMs }, math.ceil((crash.ms + crash.quietMs) / frame))
        table.insert(hits, stopped)
        local seen = crashes(hits)
        expect(seen == "6," .. #hits, string.format("a crash, its rebound at frame %d and a crash at frame %d began crashes at frames %s",
            rebound, #hits, seen))
    end,
})

-- A world position as the game's getters answer it.
local function worldPos(x, y)
    return { x = function() return x end, y = function() return y end }
end

-- Stand-ins for an arrow board and the car `driver` drives, with what ArrowBoard.takesCrash reads
-- of them: the trailer hitched to the car while `trailer.towed`, its coupler `trailer.behind`
-- squares from the car's tow bar. A new negative id each run keeps clear of real vehicles and of
-- earlier runs' crashes.
local function crashPair(driver)
    local car = {
        isDriver = function(_, p) return p == driver end,
        getTowingWorldPos = function() return worldPos(0, 0) end,
    }
    local trailer = { id = -getTimestampMs(), towed = true, behind = 0 }
    function trailer:getScriptName() return RenewableEnergy.ArrowBoard.SCRIPT end
    function trailer:getId() return self.id end
    function trailer:getVehicleTowedBy() return self.towed and car or nil end
    function trailer:getTowedByWorldPos() return worldPos(0, self.behind) end
    return trailer, car
end

-- The server takes a crash its driver reports for the trailer behind their car, but not the same
-- crash reported again within the quiet time; a crash that snapped the hitch counts while the
-- trailer is close behind, up to CRASH.unhitchedSquares.
test("renewable_energy_world_arrow_board_crash_command_from_the_driver", {
    instant = true,
    validate = function()
        local ArrowBoard, p = RenewableEnergy.ArrowBoard, player()
        local crash = ArrowBoard.CRASH
        local trailer, car = crashPair(p)
        local now = getTimestampMs()
        expect(ArrowBoard.takesCrash(p, trailer, car, now), "the server refused a crash from the driver towing the trailer")
        expect(not ArrowBoard.takesCrash(p, trailer, car, now + crash.quietMs - 1), "the server took a crash twice within the quiet time")
        trailer.towed, trailer.behind = false, crash.unhitchedSquares + 0.1
        expect(not ArrowBoard.takesCrash(p, trailer, car, now + crash.quietMs),
            "the server took a crash of a trailer unhitched " .. trailer.behind .. " squares behind")
        trailer.behind = crash.unhitchedSquares
        expect(ArrowBoard.takesCrash(p, trailer, car, now + crash.quietMs),
            "the server refused a later crash that snapped the hitch " .. trailer.behind .. " squares behind")
    end,
})

-- The server takes a crash only from the player driving the car that tows the trailer: anyone
-- else's report counts for nothing.
test("renewable_energy_world_arrow_board_crash_command_needs_the_driver", {
    instant = true,
    validate = function()
        local ArrowBoard = RenewableEnergy.ArrowBoard
        local trailer, car = crashPair("someone else")
        expect(not ArrowBoard.takesCrash(player(), trailer, car, getTimestampMs()),
            "the server took a crash from a player not driving the car")
    end,
})
