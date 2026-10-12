-- Development only; dev/run-debug-client.sh --art runs it instead of the tests. It checks the art
-- from art/models in the world and saves screenshots to <cachedir>/Screenshots, building one
-- stage after another on the same open lot:
--   art_tiles.png     every placed tile, the wall panels on walls it builds, the character
--                     standing in front of a wall panel (the depth map must draw them in front)
--   art_overlays.png  snow on every panel tile that takes it, and the crate's contents and lid
--   art_items.png     every item of the mod on the ground, a car battery first for scale
--   art_icons.png     every item's icon at twice its size, as the crafting window draws it
--   art_fill.png      every bank tile, of every tier, with every battery overlay it has, and every
--                     level of its charge meter
--   art_trailer.png   the arrow board trailer hitched to a car, its battery box open and holding
--                     a battery; "REArt trailer" in console.txt says whether both worked

require "ISUI/ISPanel"
require "RenewableEnergy/Sprites"
local Stage = require "RenewableEnergyDevStage"

local Art = {}

local Sprites = RenewableEnergy.Sprites

local SCALE_ITEM = "Base.CarBattery1"
local ITEMS_PER_ROW = 10

-- Vanilla brick walls: one on a square's north edge, one on its west edge.
local WALL_NORTH = "walls_exterior_house_01_1"
local WALL_WEST = "walls_exterior_house_01_0"

-- The lot, in squares east and south of its north-west corner. Each tile entry is a sprite and
-- the overlays drawn on it.
local AREA = { w = 10, h = 13 }
local WALLS = {
    { x = 1, y = 1, sprite = WALL_NORTH }, { x = 2, y = 1, sprite = WALL_NORTH }, { x = 3, y = 1, sprite = WALL_NORTH },
    { x = 4, y = 1, sprite = WALL_NORTH }, { x = 5, y = 1, sprite = WALL_NORTH }, { x = 6, y = 1, sprite = WALL_NORTH },
    { x = 0, y = 2, sprite = WALL_WEST }, { x = 0, y = 3, sprite = WALL_WEST },
    { x = 7, y = 2, sprite = WALL_WEST }, { x = 7, y = 3, sprite = WALL_WEST },
}
local TILES = {
    { x = 1, y = 1, sprite = Sprites.wall.metal.S }, { x = 2, y = 1, sprite = Sprites.wall.metal.S },
    { x = 4, y = 1, sprite = Sprites.wall.wood.S }, { x = 5, y = 1, sprite = Sprites.wall.wood.S },
    { x = 0, y = 2, sprite = Sprites.wall.metal.E }, { x = 0, y = 3, sprite = Sprites.wall.metal.E },
    { x = 7, y = 2, sprite = Sprites.wall.wood.E }, { x = 7, y = 3, sprite = Sprites.wall.wood.E },
    { x = 0, y = 5, sprite = Sprites.rack.metal.S }, { x = 1, y = 5, sprite = Sprites.rack.metal.E },
    { x = 2, y = 5, sprite = Sprites.rack.metal.N }, { x = 3, y = 5, sprite = Sprites.rack.metal.W },
    { x = 5, y = 5, sprite = Sprites.rack.wood.S }, { x = 6, y = 5, sprite = Sprites.rack.wood.E },
    { x = 7, y = 5, sprite = Sprites.rack.wood.N }, { x = 8, y = 5, sprite = Sprites.rack.wood.W },
    { x = 0, y = 7, sprite = Sprites.flat }, { x = 1, y = 7, sprite = Sprites.failsafe },
    { x = 2, y = 7, sprite = Sprites.cellCharger }, { x = 3, y = 7, sprite = Sprites.crate },
    { x = 5, y = 7, sprite = Sprites.gardenLight.off }, { x = 6, y = 7, sprite = Sprites.gardenLight.lit },
    { x = 0, y = 9, sprite = Sprites.batteryBoxWood }, { x = 1, y = 9, sprite = Sprites.batteryBoxMetal },
    { x = 3, y = 9, sprite = Sprites.batteryRackWood }, { x = 4, y = 9, sprite = Sprites.batteryRackMetal },
    { x = 6, y = 9, sprite = Sprites.batteryBankWood }, { x = 7, y = 9, sprite = Sprites.batteryBankMetal },
    { x = 0, y = 11, sprite = Sprites.flat, overlays = { Sprites.snow.flat } },
    { x = 0, y = 12, sprite = Sprites.crate, overlays = { Sprites.crateOverlays.full } },
    { x = 1, y = 12, sprite = Sprites.crate, overlays = { Sprites.crateOverlays.closed } },
}
for column, material in ipairs({ "metal", "wood" }) do
    for offset, facing in ipairs({ "S", "E", "N", "W" }) do
        table.insert(TILES, { x = (column - 1) * 4 + offset, y = 11, sprite = Sprites.rack[material][facing],
            overlays = { Sprites.snow.rack[material][facing] } })
    end
end

-- The charge each meter level shows, from empty to full.
local METER_CHARGES = { 0.05, 0.2, 0.5, 0.8, 1 }
local FILL_TIERS = { "batteryBoxWood", "batteryBoxMetal", "batteryRackWood", "batteryRackMetal", "batteryBankWood",
    "batteryBankMetal" }

-- Every bank tile, of every tier, with 1 to all of its batteries, its meter cycling through every
-- level; one with fewer batteries than meter levels repeats its full count. Low tiers come first,
-- at the back, so the tall banks in front hide none of them.
local function fillTiles()
    local fill, x, y = {}, 0, 0
    for _, field in ipairs(FILL_TIERS) do
        local capacity = #Sprites.bankFill[field].batteries
        for i = 1, math.max(capacity, #METER_CHARGES) do
            local charge = METER_CHARGES[(i - 1) % #METER_CHARGES + 1]
            table.insert(fill, { x = x, y = y, sprite = Sprites[field],
                overlays = Sprites.bankOverlays(field, math.min(i, capacity), charge) })
            x = x + 1
            if x >= AREA.w then
                x, y = 0, y + 2
            end
        end
    end
    return fill
end

-- Where the character stands for each shot, and how far it zooms out from the closest zoom.
local SHOTS = {
    tiles = { name = "art_tiles", x = 2, y = 1, zoomSteps = 3 },
    overlays = { name = "art_overlays", x = 4, y = 10, zoomSteps = 2 },
    items = { name = "art_items", x = 4, y = 5, zoomSteps = 1 },
    fill = { name = "art_fill", x = 6, y = 12, zoomSteps = 3 },
    trailer = { name = "art_trailer", x = 8, y = 7, zoomSteps = 2 },
}

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
    local corner = Stage.closestSquare(player, function(square)
        return lotFits(square:getX(), square:getY(), square:getZ())
    end)
    return corner and { x = corner:getX(), y = corner:getY(), z = corner:getZ() }
end

local function lotSquare(lot, x, y)
    return getCell():getGridSquare(lot.x + x, lot.y + y, lot.z)
end

local function placeTile(square, spriteName, overlays)
    local object = IsoObject.new(square, spriteName, spriteName)
    square:AddTileObject(object)
    for _, overlay in ipairs(overlays or {}) do
        object:addAttachedAnimSpriteByName(overlay)
    end
end

local function recalcLot(lot)
    for x = 0, AREA.w - 1 do
        for y = 0, AREA.h - 1 do
            lotSquare(lot, x, y):RecalcAllWithNeighbours(true)
        end
    end
end

-- Takes the last stage down to the floor, so the next one starts on an empty lot.
local function clearLot(lot)
    for x = 0, AREA.w - 1 do
        for y = 0, AREA.h - 1 do
            local square = lotSquare(lot, x, y)
            square:removeAllWorldObjects()
            local objects = square:getObjects()
            for i = objects:size() - 1, 0, -1 do
                local object = objects:get(i)
                if not object:isFloor() then
                    square:RemoveTileObject(object)
                end
            end
        end
    end
    recalcLot(lot)
end

local function placeTiles(lot, list)
    for _, tile in ipairs(list) do
        placeTile(lotSquare(lot, tile.x, tile.y), tile.sprite, tile.overlays)
    end
    recalcLot(lot)
end

local function buildTileStage(lot)
    placeTiles(lot, WALLS)
    placeTiles(lot, TILES)
end

-- The mod's items in name order, after a vanilla car battery for scale.
local function itemTypes()
    local names = {}
    local scripts = getScriptManager():getAllItems()
    for i = 0, scripts:size() - 1 do
        local script = scripts:get(i)
        if script:getModuleName() == "RenewableEnergy" then
            table.insert(names, script:getFullName())
        end
    end
    table.sort(names)
    table.insert(names, 1, SCALE_ITEM)
    return names
end

local function dropItems(lot)
    for i, fullType in ipairs(itemTypes()) do
        local item = instanceItem(fullType)
        if item then
            local column, row = (i - 1) % ITEMS_PER_ROW, math.floor((i - 1) / ITEMS_PER_ROW)
            lotSquare(lot, column, 1 + row * 2):AddWorldInventoryItem(item, 0.5, 0.5, 0)
        else
            print("REArt missing item " .. fullType)
        end
    end
end

-- A sheet of every item's icon, the script's Icon at twice its size with the item's name under it.
local IconSheet = ISPanel:derive("RenewableEnergyDevArtIcons")
local ICON_SIZE, CELL_W, CELL_H, ICON_COLUMNS = 64, 190, 96, 10

function IconSheet:render()
    ISPanel.render(self)
    for i, script in ipairs(self.scripts) do
        local column, row = (i - 1) % ICON_COLUMNS, math.floor((i - 1) / ICON_COLUMNS)
        local x, y = column * CELL_W, row * CELL_H + 6
        local texture = getTexture("Item_" .. tostring(script:getIcon()))
        if texture then
            self:drawTextureScaled(texture, x + (CELL_W - ICON_SIZE) / 2, y, ICON_SIZE, ICON_SIZE, 1, 1, 1, 1)
        end
        self:drawTextCentre(script:getName(), x + CELL_W / 2, y + ICON_SIZE + 2, 1, 1, 1, 1, UIFont.Small)
    end
end

function IconSheet:new()
    local scripts = {}
    for _, fullType in ipairs(itemTypes()) do
        table.insert(scripts, getScriptManager():getItem(fullType))
    end
    local rows = math.ceil(#scripts / ICON_COLUMNS)
    local o = ISPanel.new(self, 60, 160, ICON_COLUMNS * CELL_W, rows * CELL_H + 8)
    o.scripts = scripts
    o.backgroundColor = { r = 0.25, g = 0.25, b = 0.25, a = 1 }
    return o
end

-- The steps that walk the character to a shot's spot, let it see around, zoom and save.
local function addShot(steps, player, lot, shot)
    Stage.addLookAround(steps, player, lotSquare(lot, shot.x, shot.y))
    table.insert(steps, function()
        Stage.zoomOut(shot.zoomSteps)
        return 240
    end)
    table.insert(steps, function()
        Stage.screenshot("REArt", shot.name)
        return 10
    end)
end

function Art.capture(onDone)
    local player = getPlayer()
    local lot = findLot(player)
    if not lot then
        print("REArt found no open lot within " .. Stage.SEARCH_RADIUS .. " squares")
        onDone()
        return
    end
    print(string.format("REArt stage at %d,%d", lot.x, lot.y))
    local trailer
    local iconSheet = IconSheet:new()
    local steps = {}
    table.insert(steps, function()
        getClimateManager():stopWeatherAndThunder()
        getGameTime():setTimeOfDay(12)
        Stage.removeTrees(lot.x, lot.y, lot.z)
        buildTileStage(lot)
        return 30
    end)
    addShot(steps, player, lot, SHOTS.tiles)
    addShot(steps, player, lot, SHOTS.overlays)
    table.insert(steps, function()
        clearLot(lot)
        dropItems(lot)
        return 30
    end)
    addShot(steps, player, lot, SHOTS.items)
    table.insert(steps, function()
        iconSheet:addToUIManager()
        return 20
    end)
    table.insert(steps, function()
        Stage.screenshot("REArt", "art_icons")
        return 10
    end)
    table.insert(steps, function()
        iconSheet:removeFromUIManager()
        return 1
    end)
    table.insert(steps, function()
        clearLot(lot)
        placeTiles(lot, fillTiles())
        return 30
    end)
    addShot(steps, player, lot, SHOTS.fill)
    table.insert(steps, function()
        clearLot(lot)
        trailer = Stage.spawnTrailer(lotSquare(lot, 5, 3), "N")
        -- A vehicle joins the cell's list, and gets its physics, only on a later update.
        return 30
    end)
    table.insert(steps, function()
        Stage.hitchTrailer(trailer, player, "REArt")
        return 60
    end)
    addShot(steps, player, lot, SHOTS.trailer)
    Stage.runSteps(steps, onDone)
end

return Art
