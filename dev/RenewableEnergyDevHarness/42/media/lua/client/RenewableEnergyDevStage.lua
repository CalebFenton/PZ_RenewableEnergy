-- Development only. What the dev mod's captures and scenarios need besides the harness's staging
-- (PZHarness/Stage.lua): testing an area for room, placing a tile so it draws at once, and setting
-- out the arrow board trailer; PZHarness/Capture.lua runs the steps.

require "PZHarness/Fixtures"

local Stage = {}

local TOWING_CAR = "Base.OffRoad"
-- How far behind its car a trailer spawns, clear of it while both settle onto their wheels; the
-- hitch then moves it up to the tow bar.
Stage.TRAILER_GAP = 5
local BEHIND = { N = { 0, 1 }, S = { 0, -1 }, E = { -1, 0 }, W = { 1, 0 } }

--- Whether `accepts(square)` holds for every square of the `w` by `h` rectangle whose north-west
--- corner is `corner`, on its level. `accepts` is passed nil for a square not loaded; a nil
--- `corner` is not open.
function Stage.isAreaOpen(corner, w, h, accepts)
    if not corner then
        return false
    end
    local cell, x, y, z = getCell(), corner:getX(), corner:getY(), corner:getZ()
    for dy = 0, h - 1 do
        for dx = 0, w - 1 do
            if not accepts(cell:getGridSquare(x + dx, y + dy, z)) then
                return false
            end
        end
    end
    return true
end

--- A tile of `spriteName` placed on `square` as the tests place one (PZHarness.Fixtures.newTile),
--- with `modData`, its neighbours recalculated so it draws at once. Returns it.
function Stage.placeTile(square, spriteName, modData)
    local object = PZHarness.Fixtures.newTile(square, spriteName, modData)
    square:RecalcAllWithNeighbours(true)
    return object
end

--- Spawns a car on `square` facing `facing` ("N", "E", "S" or "W") and the arrow board trailer
--- behind it, both repaired, the trailer's lamps switched off: { car, trailer, facing }. A vehicle
--- joins the cell's list, and gets its physics, only on a later update, so wait with
--- vehiclesAtRest before hitching them.
function Stage.spawnTrailer(square, facing)
    local behind = BEHIND[facing]
    local trailerSquare = getCell():getGridSquare(square:getX() + behind[1] * Stage.TRAILER_GAP,
        square:getY() + behind[2] * Stage.TRAILER_GAP, square:getZ())
    local pair = {
        car = addVehicleDebug(TOWING_CAR, IsoDirections[facing], 0, square),
        -- The tests' spawn, which keeps a whole trailer's panels whole past stocking.
        trailer = PZHarness.testSettings.spawnVehicle(RenewableEnergy.ArrowBoard.SCRIPT, trailerSquare, facing,
            { repair = true }),
        facing = facing,
    }
    pair.car:repair()
    -- Most trailers are found switched on, and a shot of a flashing board would show it lit or dark
    -- by the moment it was taken; a shot of the lamps lights them itself.
    RenewableEnergy.ArrowBoard.setSwitch(pair.trailer, false)
    return pair
end

--- Lines up and hitches the trailer of Stage.spawnTrailer's `pair`, opens its battery box and puts
--- a battery in it, and logs under `mark` whether both worked.
function Stage.hitchTrailer(pair, player, mark)
    local car, trailer = pair.car, pair.trailer
    PZHarness.Fixtures.lineUpTrailer(car, trailer, pair.facing)
    car:addPointConstraint(player, trailer, "trailer", "trailer")
    local lid = trailer:getPartById(RenewableEnergy.ArrowBoard.LID)
    local box = trailer:getPartById(RenewableEnergy.ArrowBoard.BATTERY_BOX)
    local container = box and box:getItemContainer()
    if lid and lid:getDoor() then
        lid:getDoor():setOpen(true)
    end
    if container then
        container:AddItem(RenewableEnergy.ArrowBoard.STOCK.battery)
    end
    print(string.format("%s trailer towedBy=%s lid=%s container=%s items=%d", mark,
        tostring(trailer:getVehicleTowedBy() == car), tostring(lid ~= nil), tostring(container ~= nil),
        container and container:getItems():size() or 0))
end

-- Physics runs in real time, so the trailer steps wait for the vehicles to stand still: spawned,
-- they settle onto their wheels, and a trailer hitched before then swings round as the hitch pulls
-- it up to the car's tow bar. Vehicles at rest report a creep of about a tenth of a metre a second
-- until their physics sleeps, seconds later.
local STILL_MS = 250
local STILL_SPEED = 0.2
local HITCH_GAP = 0.1

--- A runSteps wait until the vehicles of Stage.spawnTrailer's `pair` (the trailer alone once its
--- car is gone) stand still on their squares, and with `hitch`, with the trailer's tow point at
--- the car's.
function Stage.vehiclesAtRest(pair, hitch)
    local velocity, towing, towed = Vector3f.new(), Vector3f.new(), Vector3f.new()
    local since
    local function isStill(vehicle)
        local square = vehicle:getSquare()
        return square ~= nil and square:getVehicleContainer() == vehicle
            and vehicle:getLinearVelocity(velocity):length() < STILL_SPEED
    end
    return function()
        local still = isStill(pair.trailer) and (pair.car == nil or isStill(pair.car))
        if still and hitch then
            local towPoint = pair.car:getTowingWorldPos("trailer", towing)
            local towedPoint = pair.trailer:getTowedByWorldPos("trailer", towed)
            still = towPoint ~= nil and towedPoint ~= nil and pair.trailer:getVehicleTowedBy() == pair.car
                and IsoUtils.DistanceToSquared(towPoint:x(), towPoint:y(), towedPoint:x(), towedPoint:y())
                    < HITCH_GAP * HITCH_GAP
        end
        if not still then
            since = nil
            return false
        end
        since = since or getTimestampMs()
        return getTimestampMs() - since >= STILL_MS
    end
end

--- Switches the trailer on and sets its lamps as the clock's pass sets them, lighting the ground
--- if `night`, after putting a battery charged to `charge` in its box if `charge` is given.
function Stage.lightLamps(trailer, charge, night)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    if charge then
        local container = trailer:getPartById(ArrowBoard.BATTERY_BOX):getItemContainer()
        RenewableEnergy.Battery.setCharge(container:AddItem(ArrowBoard.STOCK.battery), charge)
    end
    ArrowBoard.setSwitch(trailer, true)
    ArrowBoard.runLamps(trailer, 0, night)
end

-- Trailers whose lamps Stage.holdLampsLit holds lit, by vehicle.
local heldLit

--- Switches the trailer on with a charged battery in its box, and holds its lamps lit through
--- their flashes, for a shot that can't time its frame to a flash. The holding runs after
--- ArrowBoard's flashing in each tick, since it is added later, once a shot first asks for it.
function Stage.holdLampsLit(trailer)
    Stage.lightLamps(trailer, 1, false)
    if not heldLit then
        heldLit = {}
        Events.OnTick.Add(function()
            for vehicle in pairs(heldLit) do
                if vehicle:isRemovedFromWorld() then
                    heldLit[vehicle] = nil
                else
                    vehicle:setWindowLightsOn(true)
                end
            end
        end)
    end
    heldLit[trailer] = true
end

return Stage
