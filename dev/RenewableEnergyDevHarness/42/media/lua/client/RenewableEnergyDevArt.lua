-- Development only; dev/run-debug-client.sh --art runs it instead of the tests. It checks the art
-- from art/models in the world and saves screenshots to <cachedir>/Screenshots:
--   art_tiles.png     every placed tile, the wall panels on walls it builds, the character
--                     standing in front of a wall panel (the depth map must draw them in front)
--   art_overlays.png  every overlay on the tile it belongs to: snow, batteries, meter, crate
--   art_items.png     every item on the ground at the closest zoom, a car battery first for scale
require "RenewableEnergy/Sprites"

RenewableEnergyDevArt = {}

local Sprites = RenewableEnergy.Sprites

local ITEMS = {
    "Base.CarBattery1",
    "RenewableEnergy.SolarModule", "RenewableEnergy.SolarFlat", "RenewableEnergy.SolarWall",
    "RenewableEnergy.SolarRack", "RenewableEnergy.BatteryBox", "RenewableEnergy.BatteryBank",
    "RenewableEnergy.PlugInInverter", "RenewableEnergy.PowerInverter", "RenewableEnergy.InverterCharger",
    "RenewableEnergy.ChargeController", "RenewableEnergy.SolarFailsafe", "RenewableEnergy.DeepCycleBattery",
    "RenewableEnergy.L16Battery", "RenewableEnergy.SolarMaintainer", "RenewableEnergy.SolarCellCharger",
    "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2",
}
local ITEMS_PER_ROW = 9

-- Vanilla brick walls: one on a square's north edge, one on its west edge.
local WALL_NORTH = "walls_exterior_house_01_1"
local WALL_WEST = "walls_exterior_house_01_0"

-- The stage, in squares east and south of the open lot's north-west corner. Each entry is a tile
-- and the overlays drawn on it.
local AREA = { w = 10, h = 13 }
local WALLS = {
    { x = 1, y = 1, sprite = WALL_NORTH }, { x = 2, y = 1, sprite = WALL_NORTH }, { x = 3, y = 1, sprite = WALL_NORTH },
    { x = 0, y = 2, sprite = WALL_WEST }, { x = 0, y = 3, sprite = WALL_WEST },
}
local TILES = {
    { x = 1, y = 1, sprite = Sprites.wall.S }, { x = 2, y = 1, sprite = Sprites.wall.S },
    { x = 0, y = 2, sprite = Sprites.wall.E }, { x = 0, y = 3, sprite = Sprites.wall.E },
    { x = 2, y = 3, sprite = Sprites.rack.S }, { x = 3, y = 3, sprite = Sprites.rack.E },
    { x = 4, y = 3, sprite = Sprites.rack.N }, { x = 5, y = 3, sprite = Sprites.rack.W },
    { x = 1, y = 5, sprite = Sprites.flat }, { x = 2, y = 5, sprite = Sprites.failsafe },
    { x = 3, y = 5, sprite = Sprites.batteryBox }, { x = 4, y = 5, sprite = Sprites.batteryBank },
    { x = 5, y = 5, sprite = Sprites.cellCharger }, { x = 6, y = 5, sprite = Sprites.crate },
    { x = 0, y = 7, sprite = Sprites.flat, overlays = { Sprites.snow.flat } },
    { x = 1, y = 7, sprite = Sprites.rack.S, overlays = { Sprites.snow.rack.S } },
    { x = 2, y = 7, sprite = Sprites.rack.E, overlays = { Sprites.snow.rack.E } },
    { x = 3, y = 7, sprite = Sprites.batteryBank, overlays = Sprites.bankOverlays(Sprites.batteryBank, 12, 1) },
    { x = 4, y = 7, sprite = Sprites.batteryBank, overlays = Sprites.bankOverlays(Sprites.batteryBank, 5, 0.5) },
    { x = 5, y = 7, sprite = Sprites.batteryBank, overlays = Sprites.bankOverlays(Sprites.batteryBank, 1, 0.05) },
    { x = 6, y = 7, sprite = Sprites.batteryBox, overlays = Sprites.bankOverlays(Sprites.batteryBox, 2, 1) },
    { x = 7, y = 7, sprite = Sprites.crate, overlays = { Sprites.crateOverlays.full } },
    { x = 8, y = 7, sprite = Sprites.crate, overlays = { Sprites.crateOverlays.closed } },
}
local ITEMS_TOP = 10
-- Where the character stands for each shot: in front of a wall panel, then by each group.
local SHOTS = {
    { name = "art_tiles", x = 2, y = 1, zoomSteps = 2 },
    { name = "art_overlays", x = 4, y = 8, zoomSteps = 2 },
    { name = "art_items", x = 4, y = ITEMS_TOP + 1, zoomSteps = 0 },
}
local SEARCH_RADIUS = 40
local TREE_RADIUS = 30
local LOOK_AROUND = { IsoDirections.N, IsoDirections.E, IsoDirections.S, IsoDirections.W, IsoDirections.SE }

local function isOpen(square)
    return square ~= nil and square:isOutside() and square:isSolidFloor() and square:getObjects():size() == 1
        and not square:HasTree() and square:getWall(true) == nil and square:getWall(false) == nil
        and square:getVehicleContainer() == nil
end

local function lotFits(cornerX, cornerY, z)
    for x = cornerX, cornerX + AREA.w - 1 do
        for y = cornerY, cornerY + AREA.h - 1 do
            if not isOpen(getCell():getGridSquare(x, y, z)) then
                return false
            end
        end
    end
    return true
end

-- The north-west corner of the closest open lot that takes the whole stage.
local function findLot(player)
    local here = player:getCurrentSquare()
    local best, bestDistance
    for dx = -SEARCH_RADIUS, SEARCH_RADIUS do
        for dy = -SEARCH_RADIUS, SEARCH_RADIUS do
            local distance = dx * dx + dy * dy
            if (not bestDistance or distance < bestDistance) and lotFits(here:getX() + dx, here:getY() + dy, here:getZ()) then
                best, bestDistance = { x = here:getX() + dx, y = here:getY() + dy, z = here:getZ() }, distance
            end
        end
    end
    return best
end

local function placeTile(square, spriteName, overlays)
    local object = IsoObject.new(square, spriteName, spriteName)
    square:AddTileObject(object)
    for _, overlay in ipairs(overlays or {}) do
        object:addAttachedAnimSpriteByName(overlay)
    end
end

local function removeTrees(lot)
    for dx = -TREE_RADIUS, TREE_RADIUS do
        for dy = -TREE_RADIUS, TREE_RADIUS do
            local square = getCell():getGridSquare(lot.x + dx, lot.y + dy, lot.z)
            local tree = square and square:getTree()
            if tree then
                square:RemoveTileObject(tree)
            end
        end
    end
end

local function buildStage(lot)
    local function square(x, y)
        return getCell():getGridSquare(lot.x + x, lot.y + y, lot.z)
    end
    for _, wall in ipairs(WALLS) do
        placeTile(square(wall.x, wall.y), wall.sprite)
    end
    for _, tile in ipairs(TILES) do
        placeTile(square(tile.x, tile.y), tile.sprite, tile.overlays)
    end
    for i, fullType in ipairs(ITEMS) do
        local item = instanceItem(fullType)
        if item then
            local column, row = (i - 1) % ITEMS_PER_ROW, math.floor((i - 1) / ITEMS_PER_ROW)
            square(column, ITEMS_TOP + row * 1):AddWorldInventoryItem(item, 0.5, 0.5, 0)
        else
            print("REArt missing item " .. fullType)
        end
    end
    for x = 0, AREA.w - 1 do
        for y = 0, AREA.h - 1 do
            square(x, y):RecalcAllWithNeighbours(true)
        end
    end
end

-- Runs each step on its own tick, then waits as many ticks as the step returns.
local function runSteps(steps, onDone)
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

function RenewableEnergyDevArt.capture(onDone)
    local player = getPlayer()
    local lot = findLot(player)
    if not lot then
        print("REArt found no open lot within " .. SEARCH_RADIUS .. " squares")
        onDone()
        return
    end
    print(string.format("REArt stage at %d,%d", lot.x, lot.y))
    local steps = {}
    table.insert(steps, function()
        getClimateManager():stopWeatherAndThunder()
        getGameTime():setTimeOfDay(12)
        removeTrees(lot)
        buildStage(lot)
        return 30
    end)
    for _, shot in ipairs(SHOTS) do
        table.insert(steps, function()
            player:teleportTo(lot.x + shot.x + 0.5, lot.y + shot.y + 0.5, lot.z)
            return 30
        end)
        -- Squares the character never saw are drawn dark, so they look around first.
        for _, direction in ipairs(LOOK_AROUND) do
            table.insert(steps, function()
                player:faceDirection(direction)
                return 30
            end)
        end
        table.insert(steps, function()
            for _ = 1, 8 do
                getCore():doZoomScroll(0, -1)
            end
            for _ = 1, shot.zoomSteps do
                getCore():doZoomScroll(0, 1)
            end
            return 240
        end)
        table.insert(steps, function()
            getCore():TakeFullScreenshot(shot.name .. ".png")
            print("REArt saved " .. shot.name .. ".png")
            return 10
        end)
    end
    runSteps(steps, onDone)
end
