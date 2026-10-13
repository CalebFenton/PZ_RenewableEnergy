require "RenewableEnergy/Debug/RenewableEnergyTestLib"
-- Development only. What the --art and --promo captures share: finding a place near the
-- character, clearing its trees, the steps that walk the character to a shot and frame it, and
-- the arrow board trailer hitched to a car.

local Stage = {}

-- Frames for a change to reach the screen, where the screenshot reads it.
Stage.DRAW_FRAMES = 10
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
-- How long a step's wait may poll before the run logs it and goes on.
local WAIT_MAX_MS = 10000
-- The highest uiRenderFPS the option takes (Core.optionUiRenderFps).
local MAX_UI_FPS = 120
-- Steps to scroll in to reach the closest zoom.
local STEPS_TO_CLOSEST = 8
local TRAILER = "Base.RenewableEnergyArrowBoardTrailer"
local TOWING_CAR = "Base.OffRoad"
-- How far behind its car a trailer spawns, clear of it while both settle onto their wheels; the
-- hitch then moves it up to the tow bar.
local TRAILER_GAP = 5
local BEHIND = { N = { 0, 1 }, S = { 0, -1 }, E = { -1, 0 }, W = { 1, 0 } }

--- Runs each step on its own tick, then waits before the next: as many ticks as the step returns,
--- or, if it returns a function, until that function returns true. A function polled for longer
--- than WAIT_MAX_MS is logged under `mark` and given up. Then calls onDone.
--- Meanwhile the UI draws as often as the option allows, since UI steps wait for its drawings;
--- the player's rate comes back before onDone, so no saved options keep it.
function Stage.runSteps(steps, onDone, mark)
    local index, wait, poll, pollStart = 1, 0, nil, 0
    local uiFps = getCore():getOptionUIRenderFPS()
    getCore():setOptionUIRenderFPS(MAX_UI_FPS)
    local function onTick()
        if poll then
            if poll() then
                poll = nil
            elseif getTimestampMs() - pollStart > WAIT_MAX_MS then
                print(string.format("%s WAIT gave up on step %d after %d ms", mark or "Stage", index - 1, WAIT_MAX_MS))
                poll = nil
            end
            return
        end
        if wait > 0 then
            wait = wait - 1
            return
        end
        local step = steps[index]
        if not step then
            Events.OnTick.Remove(onTick)
            getCore():setOptionUIRenderFPS(uiFps)
            onDone()
            return
        end
        index = index + 1
        local result = step()
        if type(result) == "function" then
            poll, pollStart = result, getTimestampMs()
        else
            wait = result or 0
        end
    end
    Events.OnTick.Add(onTick)
end

-- Which squares around the character it has seen and how lit they are, as one comparable value.
local function lightingState(player)
    local here = player:getCurrentSquare()
    if not here then
        return nil
    end
    local playerNum = player:getPlayerNum()
    local seen, light = 0, 0
    for dx = -SETTLE_RADIUS, SETTLE_RADIUS do
        for dy = -SETTLE_RADIUS, SETTLE_RADIUS do
            local square = getCell():getGridSquare(here:getX() + dx, here:getY() + dy, here:getZ())
            if square then
                seen = seen + (square:isSeen(playerNum) and 1 or 0)
                light = light + math.floor(square:getLightLevel(playerNum) * 100)
            end
        end
    end
    return seen .. "/" .. light
end

--- A runSteps wait until the lighting around the character has settled: no square newly seen and
--- no light level changed for SETTLE_MS. With `change`, the lighting must change first, since a
--- change of the clock or a new light source takes most of a second to show.
function Stage.lightingSettled(player, change)
    local last, since
    local changed = not change
    return function()
        local state, now = lightingState(player), getTimestampMs()
        if state ~= last or not since then
            changed = changed or since ~= nil
            last, since = state, now
            return false
        end
        return changed and now - since >= SETTLE_MS
    end
end

--- A runSteps wait until the zoom stops changing, which eases towards its target every frame.
function Stage.zoomSettled()
    local last
    return function()
        local zoom = getCore():getZoom(0)
        local settled = zoom == last
        last = zoom
        return settled
    end
end

--- The loaded square closest to the character, within SEARCH_RADIUS on its level, for which
--- `accepts(square)` holds, or nil.
function Stage.closestSquare(player, accepts)
    local here = player:getCurrentSquare()
    local best, bestDistance
    for dx = -Stage.SEARCH_RADIUS, Stage.SEARCH_RADIUS do
        for dy = -Stage.SEARCH_RADIUS, Stage.SEARCH_RADIUS do
            local distance = dx * dx + dy * dy
            if not bestDistance or distance < bestDistance then
                local square = getCell():getGridSquare(here:getX() + dx, here:getY() + dy, here:getZ())
                if square and accepts(square) then
                    best, bestDistance = square, distance
                end
            end
        end
    end
    return best
end

--- A clear, still day at once: no cloud, fog or rain however the weather turns while the shots
--- run. Stopping the weather alone leaves its fog to fade out over seconds.
function Stage.clearWeather()
    local climate = getClimateManager()
    climate:stopWeatherAndThunder()
    for _, id in ipairs({ ClimateManager.FLOAT_CLOUD_INTENSITY, ClimateManager.FLOAT_FOG_INTENSITY,
        ClimateManager.FLOAT_PRECIPITATION_INTENSITY }) do
        local float = climate:getClimateFloat(id)
        float:setEnableAdmin(true)
        float:setAdminValue(0)
    end
end

--- Removes every tree around x, y on level z.
function Stage.removeTrees(x, y, z)
    for dx = -TREE_RADIUS, TREE_RADIUS do
        for dy = -TREE_RADIUS, TREE_RADIUS do
            local square = getCell():getGridSquare(x + dx, y + dy, z)
            local tree = square and square:getTree()
            if tree then
                square:RemoveTileObject(tree)
            end
        end
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

--- Saves a full screenshot as <cachedir>/Screenshots/<file>.png and logs it under `mark`.
function Stage.screenshot(mark, file)
    getCore():TakeFullScreenshot(file .. ".png")
    print(mark .. " saved " .. file .. ".png")
end

--- Spawns a car on `square` facing `facing` ("N", "E", "S" or "W") and the arrow board trailer
--- behind it, both repaired: { car, trailer, facing }. A vehicle joins the cell's list, and gets
--- its physics, only on a later update, so hitch them some ticks later.
function Stage.spawnTrailer(square, facing)
    local behind = BEHIND[facing]
    local trailerSquare = getCell():getGridSquare(square:getX() + behind[1] * TRAILER_GAP,
        square:getY() + behind[2] * TRAILER_GAP, square:getZ())
    local pair = {
        car = addVehicleDebug(TOWING_CAR, IsoDirections[facing], 0, square),
        trailer = addVehicleDebug(TRAILER, IsoDirections[facing], 0, trailerSquare),
        facing = facing,
    }
    pair.car:repair()
    pair.trailer:repair()
    return pair
end

--- Lines up and hitches the trailer of Stage.spawnTrailer's `pair`, opens its battery box and puts
--- a battery in it, and logs under `mark` whether both worked.
function Stage.hitchTrailer(pair, player, mark)
    local car, trailer = pair.car, pair.trailer
    RenewableEnergyTest.lineUpTrailer(car, trailer, pair.facing)
    car:addPointConstraint(player, trailer, "trailer", "trailer")
    local lid = trailer:getPartById("TrunkDoor")
    local box = trailer:getPartById("RenewableEnergyBatteryBox")
    local container = box and box:getItemContainer()
    if lid and lid:getDoor() then
        lid:getDoor():setOpen(true)
    end
    if container then
        container:AddItem("RenewableEnergy.DeepCycleBattery")
    end
    print(string.format("%s trailer towedBy=%s lid=%s container=%s items=%d", mark,
        tostring(trailer:getVehicleTowedBy() == car), tostring(lid ~= nil), tostring(container ~= nil),
        container and container:getItems():size() or 0))
end

return Stage
