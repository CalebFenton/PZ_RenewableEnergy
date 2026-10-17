-- Development only. What the --art and --promo captures share besides the harness's
-- PZHarness/Capture.lua, which runs their steps: finding a place near the character, clearing its
-- trees and vehicles, the steps that walk the character to a shot and frame it, the arrow board
-- trailer hitched to a car, dark or its arrow held lit, and the waits for it to settle.

require "PZHarness/Fixtures"

local Stage = {}

-- How far around the character a place is looked for, in squares.
Stage.SEARCH_RADIUS = 40
-- How far from a place the trees go: near a building, a tree out of the character's sight draws
-- as a black silhouette full of holes (IsoTree.render).
local TREE_RADIUS = 30
-- The character faces the camera last.
local LOOK_AROUND = { IsoDirections.N, IsoDirections.E, IsoDirections.S, IsoDirections.W, IsoDirections.SE }
-- Lighting passes a facing is held for: the main thread hands the facing to the lighting thread on
-- its next update, the thread's next pass sees with it, and the pass after that one is back.
local LOOK_PASSES = 3
-- The lighting thread updates the squares every few dozen milliseconds, and shows a change of
-- facing within about a tenth of a second, so lighting this long unchanged has settled.
local SETTLE_MS = 300
-- How far around the character the lighting has to settle, in squares.
local SETTLE_RADIUS = 15
-- Steps to scroll in to reach the closest zoom.
local STEPS_TO_CLOSEST = 8
local TOWING_CAR = "Base.OffRoad"
-- How far behind its car a trailer spawns, clear of it while both settle onto their wheels; the
-- hitch then moves it up to the tow bar.
local TRAILER_GAP = 5
local BEHIND = { N = { 0, 1 }, S = { 0, -1 }, E = { -1, 0 }, W = { 1, 0 } }

-- How many squares around the character it has seen, and the sum of their light levels: together
-- they change when a square is newly seen or its light changes.
local function lightingState(player)
    local here = player:getCurrentSquare()
    if not here then
        return nil, nil
    end
    local cell, x, y, z = getCell(), here:getX(), here:getY(), here:getZ()
    local playerNum = player:getPlayerNum()
    local seen, light = 0, 0
    for dx = -SETTLE_RADIUS, SETTLE_RADIUS do
        for dy = -SETTLE_RADIUS, SETTLE_RADIUS do
            local square = cell:getGridSquare(x + dx, y + dy, z)
            if square then
                seen = seen + (square:isSeen(playerNum) and 1 or 0)
                light = light + math.floor(square:getLightLevel(playerNum) * 100)
            end
        end
    end
    return seen, light
end

--- A runSteps wait until the lighting around the character has settled: no square newly seen and
--- no light level changed for SETTLE_MS. With `change`, the lighting must change first, since a
--- change of the clock or a new light source takes most of a second to show.
function Stage.lightingSettled(player, change)
    -- The lighting changes only once per pass of its thread, and the runs draw hundreds of frames
    -- a second, so the area is scanned once per pass rather than every frame.
    local interval = 1000 / getPerformance():getLightingFPS()
    local lastSeen, lastLight, since, sampled
    local changed = not change
    return function()
        local now = getTimestampMs()
        if sampled and now - sampled < interval then
            return false
        end
        sampled = now
        local seen, light = lightingState(player)
        if seen ~= lastSeen or light ~= lastLight or not since then
            changed = changed or since ~= nil
            lastSeen, lastLight, since = seen, light, now
            return false
        end
        return changed and now - since >= SETTLE_MS
    end
end

--- The loaded square closest to the character, within SEARCH_RADIUS on its level, for which
--- `accepts(square)` holds, or nil. Of squares as close, the one furthest west, then north.
function Stage.closestSquare(player, accepts)
    local here = player:getCurrentSquare()
    local x, y, z = here:getX(), here:getY(), here:getZ()
    local best, bestDistance, bestDx, bestDy
    -- Ring by ring outwards, until no square of the next ring can be as close as the best.
    for radius = 0, Stage.SEARCH_RADIUS do
        if bestDistance and radius * radius > bestDistance then
            break
        end
        for sx, sy in PZHarness.Fixtures.ring(x, y, radius) do
            local dx, dy = sx - x, sy - y
            local distance = dx * dx + dy * dy
            if not bestDistance or distance < bestDistance
                or (distance == bestDistance and (dx < bestDx or (dx == bestDx and dy < bestDy))) then
                local square = getCell():getGridSquare(sx, sy, z)
                if square and accepts(square) then
                    best, bestDistance, bestDx, bestDy = square, distance, dx, dy
                end
            end
        end
    end
    return best
end

--- Removes every tree within TREE_RADIUS of x, y on level z.
function Stage.removeTrees(x, y, z)
    local cell = getCell()
    for dx = -TREE_RADIUS, TREE_RADIUS do
        for dy = -TREE_RADIUS, TREE_RADIUS do
            local square = cell:getGridSquare(x + dx, y + dy, z)
            local tree = square and square:getTree()
            if tree then
                square:RemoveTileObject(tree)
            end
        end
    end
end

--- Grass, weeds and bushes a character could pull up (as vanilla's remove-grass and building code
--- tell them from other objects).
function Stage.isGroundCover(object)
    local props = object:getProperties()
    return props ~= nil and (props:has(IsoFlagType.canBeRemoved)
        or (props:has(IsoFlagType.vegitation) and object:getType() ~= IsoObjectType.tree))
end

--- Clears the ground cover off `square`, so what is set on it shows.
function Stage.clearGroundCover(square)
    local objects = square and square:getObjects()
    for i = (objects and objects:size() or 0) - 1, 0, -1 do
        if Stage.isGroundCover(objects:get(i)) then
            square:RemoveTileObject(objects:get(i))
        end
    end
end

--- Removes every vehicle standing on a square from x1, y1 to x2, y2 on level z. Found through the
--- squares, since the cell keeps its vehicles in a Java Set (IsoCell.getVehicles), which Lua can't walk.
function Stage.removeVehicles(x1, y1, x2, y2, z)
    local cell, found = getCell(), {}
    for x = x1, x2 do
        for y = y1, y2 do
            local square = cell:getGridSquare(x, y, z)
            local vehicle = square and square:getVehicleContainer()
            if vehicle then
                found[vehicle] = true
            end
        end
    end
    for vehicle in pairs(found) do
        vehicle:permanentlyRemove()
    end
end

--- Adds the steps that put the character on `square` and have it look around, since squares it
--- never saw are drawn dark. Its sight sweeps round with each turn, so only the last waits for the
--- lighting to settle.
function Stage.addLookAround(steps, player, square)
    table.insert(steps, function()
        player:teleportTo(square:getX() + 0.5, square:getY() + 0.5, square:getZ())
        return function()
            return player:getCurrentSquare() == square
        end
    end)
    for _, direction in ipairs(LOOK_AROUND) do
        local target = direction:ToVector()
        local length = math.sqrt(target:getX() ^ 2 + target:getY() ^ 2)
        local targetX, targetY = target:getX() / length, target:getY() / length
        -- Turned at once, body and animation, rather than over the half second a turn takes; its
        -- sight follows on the lighting thread, which runs at its own rate.
        table.insert(steps, function()
            player:setTargetAndCurrentDirection(targetX, targetY)
            local untilMs = getTimestampMs() + LOOK_PASSES * 1000 / getPerformance():getLightingFPS()
            return function()
                return getTimestampMs() >= untilMs
            end
        end)
    end
    table.insert(steps, function()
        return Stage.lightingSettled(player)
    end)
end

--- Sets the zoom `stepsOut` steps out from the closest.
function Stage.zoomOut(stepsOut)
    for _ = 1, STEPS_TO_CLOSEST do
        getCore():doZoomScroll(0, -1)
    end
    for _ = 1, stepsOut do
        getCore():doZoomScroll(0, 1)
    end
end

--- The icon the crafting window draws for `fullType`: the script's, which for a moveable is not
--- the tile the inventory shows, or else the item's own.
function Stage.iconTexture(fullType)
    local icon = getScriptManager():getItem(fullType):getIcon()
    return icon and getTexture("Item_" .. icon) or instanceItem(fullType):getTex()
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
    local trailerSquare = getCell():getGridSquare(square:getX() + behind[1] * TRAILER_GAP,
        square:getY() + behind[2] * TRAILER_GAP, square:getZ())
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
            local a = pair.car:getTowingWorldPos("trailer", towing)
            local b = pair.trailer:getTowedByWorldPos("trailer", towed)
            still = a ~= nil and b ~= nil and pair.trailer:getVehicleTowedBy() == pair.car
                and IsoUtils.DistanceToSquared(a:x(), a:y(), b:x(), b:y()) < HITCH_GAP * HITCH_GAP
        end
        if not still then
            since = nil
            return false
        end
        since = since or getTimestampMs()
        return getTimestampMs() - since >= STILL_MS
    end
end

--- Switches the trailer on and sets its lamps as the clock's pass sets them, dimmed for the night
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
