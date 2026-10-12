-- Development only. What the --art and --promo captures share: finding a place near the
-- character, clearing its trees, and the steps that walk the character to a shot and frame it.

local Stage = {}

-- How far around the character a place is looked for, in squares.
Stage.SEARCH_RADIUS = 40
-- How far from a place the trees go: near a building, a tree out of the character's sight draws
-- as a black silhouette full of holes (IsoTree.render).
local TREE_RADIUS = 30
-- The character faces the camera last.
local LOOK_AROUND = { IsoDirections.N, IsoDirections.E, IsoDirections.S, IsoDirections.W, IsoDirections.SE }
-- Steps to scroll in to reach the closest zoom.
local STEPS_TO_CLOSEST = 8

--- Runs each step on its own tick, then waits as many ticks as the step returns, then calls onDone.
function Stage.runSteps(steps, onDone)
    local index, wait = 1, 0
    local function onTick()
        if wait > 0 then
            wait = wait - 1
            return
        end
        local step = steps[index]
        if not step then
            Events.OnTick.Remove(onTick)
            onDone()
            return
        end
        index = index + 1
        wait = step() or 0
    end
    Events.OnTick.Add(onTick)
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
--- never saw are drawn dark.
function Stage.addLookAround(steps, player, square)
    table.insert(steps, function()
        player:teleportTo(square:getX() + 0.5, square:getY() + 0.5, square:getZ())
        return 30
    end)
    for _, direction in ipairs(LOOK_AROUND) do
        table.insert(steps, function()
            player:faceDirection(direction)
            return 40
        end)
    end
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

return Stage
