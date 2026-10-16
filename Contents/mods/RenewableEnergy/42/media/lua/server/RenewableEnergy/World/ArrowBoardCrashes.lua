require "RenewableEnergy/World/ArrowBoard"

-- Crashes of the arrow board trailer (ArrowBoard.lua). A crash reaches a towed trailer only as
-- damage to vanilla's part ids (BaseVehicle.crash, addDamageFront/Rear), which the panels aren't,
-- and Lua can't read the trailer's own crash durability. So the game running the trailer's physics
-- watches its velocity: single player every loaded trailer; a multiplayer client the trailer
-- behind the car it drives, asking the server to crack the panels as vanilla's own crash command
-- does. A crash can snap the hitch in the physics step that jolts the trailer
-- (Bullet.onVehicleConstraintImpulse), so that client goes on watching for CRASH.unhitchedMs, and
-- the server takes the crash from the car's driver while the trailer is within
-- CRASH.unhitchedSquares of the car's tow bar.

local ArrowBoard = RenewableEnergy.ArrowBoard

-- A hard crash: the trailer's velocity changing by at least `kmh` within `ms` of real time, as a
-- car stopping dead against a wall from that speed does. Hard braking sheds about 3 km/h in that
-- time and running over a zombie or a kerb a few, so bumps never crack a panel. The physics spreads
-- a crash over several frames, and a trailer thrown forward jolts again when the hitch brings it up
-- short, half a second or more later, so a jolt is a new crash only after `quietMs` without one.
-- `unhitchedMs` and `unhitchedSquares` cover a crash that snaps the hitch (above).
local CRASH = { kmh = 20, ms = 250, quietMs = 2000, unhitchedMs = 1000, unhitchedSquares = 8 }
local LIMIT_SQ = (CRASH.kmh / 3.6) ^ 2

-- The client command a driver sends when the trailer they tow crashes.
local COMMAND_MODULE, CRASH_COMMAND = "RenewableEnergyArrowBoard", "crashed"

-- The loaded trailers whose crashes this game watches, by vehicle: their recent velocities,
-- oldest first, in the lists ms, x and y, used as a ring of SAMPLE_SLOTS from `head`, `count`
-- long, so that watching allocates nothing each frame; when they last jolted (joltedAt); whether
-- they have joined the cell (inCell); on a multiplayer client the car of this game's player that
-- last towed them and until when its crashes still count (car, carUntil).
local watched = {}
-- Enough for CRASH.ms at a thousand frames a second; at a higher rate the oldest samples go
-- early, which still leaves a crash's jolt well inside the window.
local SAMPLE_SLOTS = 256

local CLIENT = isClient()
-- A dedicated server runs no vehicle physics (BaseVehicle.createPhysics), so it watches nothing.
local WATCHES = not isServer()

--- Watches the trailer's crashes from now until it leaves the world, in a game that runs vehicle
--- physics. Called from its panels' part `init`.
function ArrowBoard.watchCrashes(vehicle)
    if WATCHES and not watched[vehicle] then
        watched[vehicle] = { ms = {}, x = {}, y = {}, head = 1, count = 0, joltedAt = -math.huge }
    end
end

local function drivenHere(car)
    local driver = car:getDriver()
    return driver ~= nil and instanceof(driver, "IsoPlayer") and driver:isLocalPlayer()
end

-- On a multiplayer client, the car this game's player drives that tows the trailer or towed it a
-- moment ago, whose game runs the trailer's physics; nil if none.
local function carTowingHere(vehicle, entry, now)
    local tow = vehicle:getVehicleTowedBy()
    if tow and drivenHere(tow) then
        entry.car, entry.carUntil = tow, now + CRASH.unhitchedMs
    elseif entry.car and (now > entry.carUntil or tow or not drivenHere(entry.car)) then
        entry.car = nil
    end
    return entry.car
end

local velocity = Vector3f.new()

-- Records the velocity `x`, `y` at `now` as the newest sample.
local function record(entry, now, x, y)
    local slot = (entry.head + entry.count - 1) % SAMPLE_SLOTS + 1
    if entry.count == SAMPLE_SLOTS then
        entry.head = entry.head % SAMPLE_SLOTS + 1
    else
        entry.count = entry.count + 1
    end
    entry.ms[slot], entry.x[slot], entry.y[slot] = now, x, y
end

-- Records the trailer's velocity now and returns whether a new crash began: the velocity changed
-- by a crash's worth within CRASH.ms, CRASH.quietMs after the last jolt. A trailer at rest
-- (BaseVehicle.isAtRest: under 0.025 m/s, no hit pending) keeps one still sample, which is all a
-- crash into it needs to be seen, so a parked trailer costs no scan.
local function sampleCrash(vehicle, entry, now)
    if vehicle:isAtRest() then
        entry.head, entry.count = 1, 0
        record(entry, now, 0, 0)
        return false
    end
    vehicle:getLinearVelocity(velocity)
    local x, y = velocity:x(), velocity:z()
    local ms, xs, ys = entry.ms, entry.x, entry.y
    while entry.count > 0 and now - ms[entry.head] > CRASH.ms do
        entry.head = entry.head % SAMPLE_SLOTS + 1
        entry.count = entry.count - 1
    end
    local jolted, slot = false, entry.head
    for _ = 1, entry.count do
        local dx, dy = x - xs[slot], y - ys[slot]
        if dx * dx + dy * dy >= LIMIT_SQ then
            jolted = true
            break
        end
        slot = slot % SAMPLE_SLOTS + 1
    end
    record(entry, now, x, y)
    if not jolted then
        return false
    end
    local newCrash = now - entry.joltedAt >= CRASH.quietMs
    entry.joltedAt = now
    return newCrash
end

local cell

-- OnTick, but on a dedicated server: samples each watched trailer whose physics this game runs,
-- and cracks its panels, or asks the server to, when it crashes.
--
-- Per tick: on a multiplayer client a towing check for each loaded trailer, and a sample only of
-- one its player tows; in single player one isAtRest call for each parked trailer, and a scan of
-- at most CRASH.ms of samples for each moving one. The game fires nothing on a crash that Lua
-- sees (above), so the velocity is all there is. Allocates nothing.
local function sampleTrailers()
    local now = getTimestampMs()
    cell = cell or getCell()
    -- A vehicle joins the cell a frame after it enters the world, so one not yet in it waits. Once
    -- in, it stays until it leaves the world, so the cell's list is searched only until then.
    for vehicle, entry in pairs(watched) do
        if vehicle:isRemovedFromWorld() then
            watched[vehicle] = nil
        elseif entry.inCell or cell:getVehicles():contains(vehicle) then
            entry.inCell = true
            local car = CLIENT and carTowingHere(vehicle, entry, now)
            if (car or not CLIENT) and sampleCrash(vehicle, entry, now) then
                if CLIENT then
                    -- From the driver, whom the server checks: in split screen, not always player 1.
                    sendClientCommand(car:getDriver(), COMMAND_MODULE, CRASH_COMMAND, { vehicle = vehicle:getId(), car = car:getId() })
                else
                    ArrowBoard.crashCrack(vehicle)
                end
            end
        end
    end
end

local hitch, coupler = Vector3f.new(), Vector3f.new()

-- Whether the trailer, no longer towed, is still close behind the car.
local function justUnhitched(vehicle, car)
    if vehicle:getVehicleTowedBy() then
        return false
    end
    local hitchAt = car:getTowingWorldPos("trailer", hitch)
    local couplerAt = vehicle:getTowedByWorldPos("trailer", coupler)
    local squares = CRASH.unhitchedSquares
    return hitchAt ~= nil and couplerAt ~= nil
        and (hitchAt:x() - couplerAt:x()) ^ 2 + (hitchAt:y() - couplerAt:y()) ^ 2 <= squares * squares
end

-- When the server last took a crash for each trailer, by vehicle id. Entries older than
-- CRASH.quietMs no longer gate anything and go as the next crash comes in.
local crashTakenAt = {}

local function forgetOldCrashes(now)
    for id, at in pairs(crashTakenAt) do
        if now - at >= CRASH.quietMs then
            crashTakenAt[id] = nil
        end
    end
end

-- The server takes a crash only from the driver of the car towing the trailer, or towing it until
-- a moment ago, and only one within CRASH.quietMs: a client's own gate is all that keeps one crash
-- from cracking the panels twice, so the server keeps it too.
local function onClientCommand(module, command, player, args)
    if module ~= COMMAND_MODULE or command ~= CRASH_COMMAND or type(args) ~= "table" or type(args.vehicle) ~= "number"
        or type(args.car) ~= "number" then
        return
    end
    local vehicle, car = getVehicleById(args.vehicle), getVehicleById(args.car)
    if not (ArrowBoard.isTrailer(vehicle) and car and car:isDriver(player)
        and (vehicle:getVehicleTowedBy() == car or justUnhitched(vehicle, car))) then
        return
    end
    local now = getTimestampMs()
    forgetOldCrashes(now)
    if not crashTakenAt[args.vehicle] then
        crashTakenAt[args.vehicle] = now
        ArrowBoard.crashCrack(vehicle)
    end
end

if WATCHES then
    Events.OnTick.Add(sampleTrailers)
end
if not CLIENT then
    Events.OnClientCommand.Add(onClientCommand)
end
