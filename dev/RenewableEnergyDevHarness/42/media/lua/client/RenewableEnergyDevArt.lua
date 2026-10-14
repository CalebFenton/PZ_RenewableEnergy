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
--                     a battery; "REArt trailer" in console.txt says whether both worked. The
--                     same view then shows its rear in each of these states:
--     art_trailer_rust.png      rust at its full amount
--     art_trailer_blood_right.png   blood on the right side only, which settles which side is which
--     art_trailer_blood.png     blood on all four sides
--     art_trailer_brake.png     the brake lights, lit while the towing car brakes
--     art_trailer_panel_cracked.png   its right panel's module cracked, the left one whole
--     art_trailer_panel_removed.png   its left panel taken off
--     art_trailer_rear_damage1.png    the back of its frame (TruckBed: tail and sides) at damage
--                                     stage 1, then
--     art_trailer_rear_damage2.png    at stage 2
--     art_trailer_lit.png       its arrow lit by day, from a charged battery, mid-flash
--     art_trailer_dark.png      switched on but dark, with no battery in its box
--     art_trailer_lit_night.png its arrow lit at night, dimmed, lighting the ground around it
--   art_trailer_front.png   a second trailer, alone and facing the other way, blood on all four
--                     sides, for the front and left side; the same view then shows it clean with
--     art_trailer_damage1.png   its whole frame (EngineDoor and TruckBed) and the battery box lid
--                               (TrunkDoor) at damage stage 1, then
--     art_trailer_damage2.png   at stage 2
--     art_trailer_lid_removed.png   the battery box lid taken off
--     art_trailer_washed.png    blood on all four sides, then washed off by vanilla's wash action
--     art_trailer_lid_open.png  the battery box lid swung open, then
--     art_trailer_lid_shut.png  swung shut again
--     art_trailer_lid_locked.png    the shut lid padlocked, then
--     art_trailer_lid_unlocked.png  unlocked, the padlock gone
--   art_cracked.png   cracked glass on a flat panel, wooden and metal wall panels and racks (one
--                     module of each rack cracked), placed the way players place them, so the
--                     mod's own code adds the overlays, and east of them an arrow board trailer
--                     with its left panel cracked and its right one whole, to compare the look

require "ISUI/ISPanel"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Debug/RenewableEnergyDebug"
local Stage = require "RenewableEnergyDevStage"
local Capture = require "PZHarness/Capture"

local Art = {}

local Sprites = RenewableEnergy.Sprites
local MARK = "REArt"

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
    trailerFront = { name = "art_trailer_front", x = 3, y = 6, zoomSteps = 2 },
}

-- Damage stage 1 is a condition from 40 to 59, stage 2 below 40 (BaseVehicle.doDamageOverlay).
local STAGE_1, STAGE_2 = 50, 20
-- The frame's front and back, and the battery box lid.
local BODY_PARTS = { "EngineDoor", "TruckBed", "TrunkDoor" }
local BLOOD_SIDES = { "Front", "Rear", "Left", "Right" }

local function setBlood(vehicle, sides)
    for _, side in ipairs(BLOOD_SIDES) do
        vehicle:setBloodIntensity(side, 0)
    end
    for _, side in ipairs(sides) do
        vehicle:setBloodIntensity(side, 1)
    end
end

local function setCondition(vehicle, partIds, condition)
    for _, id in ipairs(partIds) do
        vehicle:getPartById(id):setCondition(condition)
    end
end

-- ISWashVehicle's own removal, side by side, without the walk to each side's area.
local function wash(vehicle)
    for _, side in ipairs(BLOOD_SIDES) do
        ISWashVehicle:new(getPlayer(), vehicle, side, nil):removeBlood(100, 0)
    end
end

-- The lid swings in real time, about a third of a second at normal speed, whatever the frame rate
-- (BaseVehicle.updateAnimationPlayer); this leaves it time to come to rest.
local LID_SWING_MS = 1000

--- Sets the lid open or shut on the lone trailer and returns a runSteps wait for its swing.
local function swingLid(pair, open)
    local door = pair.trailer:getPartById("TrunkDoor"):getDoor()
    -- Spawned trailers are often locked, and a locked lid wouldn't open in play.
    door:setLocked(false)
    door:setOpen(open)
    local start = getTimestampMs()
    return function() return getTimestampMs() - start >= LID_SWING_MS end
end

-- The lid shut and padlocked or not; ArrowBoard's lid watcher shows the padlock by the next frame.
local function lockLid(pair, locked)
    local door = pair.trailer:getPartById("TrunkDoor"):getDoor()
    door:setOpen(false)
    door:setLockBroken(false)
    door:setLocked(locked)
end

-- How far into a flash a lit shot waits, so the frame it copies has drawn the lamps lit.
local FLASH_SETTLE_MS = 150
-- The last moment into a flash a lit shot may start, leaving the rest of the flash for the shot.
local FLASH_SHOT_MS = 500

-- The trailer switched on with a charged battery in its box, or none if not `lit`, its lamps set
-- as the clock's pass sets them, dimmed for the night if `night`, the clock set to midnight then.
-- Returns a runSteps wait: at night until the lighting has settled on the dark and the board's
-- lamppost, and for lit lamps until they are a little way into a flash.
local function setLamps(pair, lit, night)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    local container = pair.trailer:getPartById(ArrowBoard.BATTERY_BOX):getItemContainer()
    container:removeAllItems()
    if lit then
        RenewableEnergy.Battery.setCharge(container:AddItem("RenewableEnergy.DeepCycleBattery"), 0.8)
    end
    if night then
        getGameTime():setTimeOfDay(0)
    end
    ArrowBoard.setSwitch(pair.trailer, true)
    ArrowBoard.runLamps(pair.trailer, 0, night)
    local settled = night and Stage.lightingSettled(getPlayer(), true)
    return function()
        if settled and not settled() then
            return false
        end
        settled = nil
        local flashLit, ms = ArrowBoard.flashPhase(getTimestampMs())
        return not lit or flashLit and ms >= FLASH_SETTLE_MS and ms <= FLASH_SHOT_MS
    end
end

-- The trailer's states, each set on a repaired trailer and shot from where the shot before stands.
-- The hitched trailer shows its rear; the lone one, facing the other way, its front and the lid.
-- A state's `set` may return how to wait before the shot, as a runSteps step does.
local HITCHED_STATES = {
    { name = "art_trailer_rust", set = function(pair) pair.trailer:setRust(1) end },
    { name = "art_trailer_blood_right", set = function(pair) setBlood(pair.trailer, { "Right" }) end },
    { name = "art_trailer_blood", set = function(pair) setBlood(pair.trailer, BLOOD_SIDES) end },
    {
        name = "art_trailer_brake",
        set = function(pair)
            -- A towed trailer's brake lights follow its car's, which need charge in the car's battery.
            local battery = pair.car:getBattery() and pair.car:getBattery():getInventoryItem()
            if battery then
                battery:setCurrentUsesFloat(1)
            end
            pair.car:setStoplightsOn(true)
        end,
    },
    {
        name = "art_trailer_panel_cracked",
        set = function(pair)
            pair.trailer:getPartById("RenewableEnergyPanelRight"):setCondition(30)
            RenewableEnergy.ArrowBoard.showPanels(pair.trailer)
        end,
    },
    {
        name = "art_trailer_panel_removed",
        set = function(pair)
            pair.trailer:getPartById("RenewableEnergyPanelLeft"):setInventoryItem(nil)
            RenewableEnergy.ArrowBoard.showPanels(pair.trailer)
        end,
    },
    { name = "art_trailer_rear_damage1", set = function(pair) setCondition(pair.trailer, { "TruckBed" }, STAGE_1) end },
    { name = "art_trailer_rear_damage2", set = function(pair) setCondition(pair.trailer, { "TruckBed" }, STAGE_2) end },
    { name = "art_trailer_lit", set = function(pair) return setLamps(pair, true, false) end },
    { name = "art_trailer_dark", set = function(pair) return setLamps(pair, false, false) end },
    -- The last of them: the lone trailer's shots put the clock back to noon.
    { name = "art_trailer_lit_night", set = function(pair) return setLamps(pair, true, true) end },
}
local LONE_STATES = {
    { name = "art_trailer_damage1", set = function(pair) setCondition(pair.trailer, BODY_PARTS, STAGE_1) end },
    { name = "art_trailer_damage2", set = function(pair) setCondition(pair.trailer, BODY_PARTS, STAGE_2) end },
    { name = "art_trailer_lid_removed", set = function(pair) pair.trailer:getPartById("TrunkDoor"):setInventoryItem(nil) end },
    {
        name = "art_trailer_washed",
        set = function(pair)
            setBlood(pair.trailer, BLOOD_SIDES)
            wash(pair.trailer)
        end,
    },
    { name = "art_trailer_lid_open", set = function(pair) return swingLid(pair, true) end },
    { name = "art_trailer_lid_shut", set = function(pair) return swingLid(pair, false) end },
    { name = "art_trailer_lid_locked", set = function(pair) lockLid(pair, true) end },
    { name = "art_trailer_lid_unlocked", set = function(pair) lockLid(pair, false) end },
}

-- `pair` returns the current pair, which the steps only know once they run.
local function addStates(steps, pair, states)
    for _, state in ipairs(states) do
        table.insert(steps, function()
            pair().trailer:repair()
            -- repair() mends the panels without anything showing their models again.
            RenewableEnergy.ArrowBoard.showPanels(pair().trailer)
            if pair().car then
                pair().car:setStoplightsOn(false)
            end
            -- A part's new condition reaches the overlay on the vehicle's next update, once a frame.
            return state.set(pair()) or Capture.DRAW_FRAMES
        end)
        table.insert(steps, function()
            Capture.screenshot(MARK, state.name)
        end)
    end
end

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

-- The world can park vehicles on and around the lot after it was chosen, as its chunks load, and
-- one there hides the trailer or runs into it.
local VEHICLE_MARGIN = 4

local function clearVehicles(lot)
    local found = {}
    for x = -VEHICLE_MARGIN, AREA.w + VEHICLE_MARGIN - 1 do
        for y = -VEHICLE_MARGIN, AREA.h + VEHICLE_MARGIN - 1 do
            local square = lotSquare(lot, x, y)
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

-- The mod's items in the README's order, then those that only sit in a vehicle part, after a
-- vanilla car battery for scale.
local function itemTypes()
    local names = { SCALE_ITEM }
    for _, list in ipairs({ RenewableEnergy.Debug.ITEMS, RenewableEnergy.Debug.PART_ITEMS }) do
        for _, fullType in ipairs(list) do
            table.insert(names, fullType)
        end
    end
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
    for i, icon in ipairs(self.icons) do
        local column, row = (i - 1) % ICON_COLUMNS, math.floor((i - 1) / ICON_COLUMNS)
        local x, y = column * CELL_W, row * CELL_H + 6
        if icon.texture then
            self:drawTextureScaled(icon.texture, x + (CELL_W - ICON_SIZE) / 2, y, ICON_SIZE, ICON_SIZE, 1, 1, 1, 1)
        end
        self:drawTextCentre(icon.name, x + CELL_W / 2, y + ICON_SIZE + 2, 1, 1, 1, 1, UIFont.Small)
    end
end

function IconSheet:new()
    local icons = {}
    for _, fullType in ipairs(itemTypes()) do
        table.insert(icons, { texture = Stage.iconTexture(fullType), name = getScriptManager():getItem(fullType):getName() })
    end
    local rows = math.ceil(#icons / ICON_COLUMNS)
    local o = ISPanel.new(self, 60, 160, ICON_COLUMNS * CELL_W, rows * CELL_H + 8)
    o.icons = icons
    o.backgroundColor = { r = 0.25, g = 0.25, b = 0.25, a = 1 }
    return o
end

-- The steps that walk the character to a shot's spot, let it see around, zoom and save.
local function addShot(steps, player, lot, shot)
    Stage.addLookAround(steps, player, lotSquare(lot, shot.x, shot.y))
    table.insert(steps, function()
        Stage.zoomOut(shot.zoomSteps)
        return Capture.zoomSettled()
    end)
    table.insert(steps, function()
        return Capture.DRAW_FRAMES
    end)
    table.insert(steps, function()
        Capture.screenshot(MARK, shot.name)
    end)
end

-- Cracked mounts, by lot square, and their modules' conditions in slot order. Each rack has one
-- cracked module, the wooden one its lower and the metal one its upper.
local CRACKED_WALLS = {
    { x = 1, y = 1, sprite = WALL_NORTH }, { x = 2, y = 1, sprite = WALL_NORTH },
    { x = 0, y = 2, sprite = WALL_WEST }, { x = 0, y = 3, sprite = WALL_WEST },
}
local CRACKED_PANELS = {
    { x = 1, y = 1, sprite = Sprites.wall.metal.S, conditions = { 40 } },
    { x = 2, y = 1, sprite = Sprites.wall.wood.S, conditions = { 40 } },
    { x = 0, y = 2, sprite = Sprites.wall.metal.E, conditions = { 40 } },
    { x = 0, y = 3, sprite = Sprites.wall.wood.E, conditions = { 40 } },
    { x = 2, y = 3, sprite = Sprites.flat, conditions = { 30 } },
    { x = 1, y = 5, sprite = Sprites.rack.wood.S, conditions = { 30, 100 } },
    { x = 3, y = 5, sprite = Sprites.rack.metal.S, conditions = { 100, 45 } },
}
-- Lot squares x 5 to 8, y 1 to 3 stay open, east of the mounts, for a trailer with a cracked panel.
-- The character stands south-east of the mounts and south-west of the open ground, hiding neither.
local CRACKED_SHOT = { name = "art_cracked", x = 7, y = 7, zoomSteps = 2 }

local function addCrackedShot(steps, player, lot)
    table.insert(steps, function()
        clearLot(lot)
        clearVehicles(lot)
        placeTiles(lot, CRACKED_WALLS)
        for _, panel in ipairs(CRACKED_PANELS) do
            local modules = {}
            for slot, condition in ipairs(panel.conditions) do
                modules[slot] = { type = "RenewableEnergy.SolarModule", condition = condition }
            end
            RenewableEnergy.WorldSpawns.placePanel(lotSquare(lot, panel.x, panel.y), panel.sprite, modules)
        end
        recalcLot(lot)
    end)
    -- A trailer beside them with one panel cracked as theirs are and one whole, to compare the look.
    -- The tick after stocking puts the stock conditions back over any set in the same tick
    -- (ArrowBoard.keepStockConditions), so they're set a step later.
    local trailer
    table.insert(steps, function()
        -- Row 4 keeps all of it on the cleared lot.
        trailer = addVehicleDebug(RenewableEnergy.ArrowBoard.SCRIPT, IsoDirections.N, 0, lotSquare(lot, 6, 4))
        return 1
    end)
    table.insert(steps, function()
        trailer:repair()
        trailer:getPartById("RenewableEnergyPanelLeft"):setCondition(30)
        trailer:getPartById("RenewableEnergyPanelRight"):setCondition(100)
        RenewableEnergy.ArrowBoard.showPanels(trailer)
        -- Dark, as Stage.spawnTrailer leaves its trailers.
        RenewableEnergy.ArrowBoard.setSwitch(trailer, false)
        return Stage.vehiclesAtRest({ trailer = trailer }, false)
    end)
    addShot(steps, player, lot, CRACKED_SHOT)
end

-- The tile, overlay, item, icon and fill shots, each on the lot cleared of the one before.
local function addTileAndItemShots(steps, player, lot)
    local iconSheet = IconSheet:new()
    table.insert(steps, function()
        getGameTime():setTimeOfDay(12)
        Stage.removeTrees(lot.x, lot.y, lot.z)
        buildTileStage(lot)
    end)
    addShot(steps, player, lot, SHOTS.tiles)
    addShot(steps, player, lot, SHOTS.overlays)
    table.insert(steps, function()
        clearLot(lot)
        dropItems(lot)
    end)
    addShot(steps, player, lot, SHOTS.items)
    table.insert(steps, function()
        iconSheet:addToUIManager()
        return Capture.drawn(Capture.DRAW_FRAMES)
    end)
    table.insert(steps, function()
        Capture.screenshot(MARK, "art_icons")
    end)
    table.insert(steps, function()
        iconSheet:removeFromUIManager()
        return 1
    end)
    table.insert(steps, function()
        clearLot(lot)
        placeTiles(lot, fillTiles())
    end)
    addShot(steps, player, lot, SHOTS.fill)
end

-- The trailer hitched to its car, then the rear in each of its states. `art.trailer` holds the
-- pair the steps spawn.
local function addHitchedTrailerShots(steps, player, lot, art)
    table.insert(steps, function()
        clearLot(lot)
        clearVehicles(lot)
        art.trailer = Stage.spawnTrailer(lotSquare(lot, 5, 3), "N")
        return Stage.vehiclesAtRest(art.trailer, false)
    end)
    table.insert(steps, function()
        Stage.hitchTrailer(art.trailer, player, "REArt")
        return Stage.vehiclesAtRest(art.trailer, true)
    end)
    addShot(steps, player, lot, SHOTS.trailer)
    addStates(steps, art.currentPair, HITCHED_STATES)
end

-- A second trailer alone, facing the other way, in each of its states, then the cracked panels.
local function addLoneAndCrackedShots(steps, player, lot, art)
    -- Back to noon after the hitched trailer's night shot.
    table.insert(steps, function()
        getGameTime():setTimeOfDay(12)
        return Stage.lightingSettled(player, true)
    end)
    table.insert(steps, function()
        clearVehicles(lot)
        art.trailer = Stage.spawnTrailer(lotSquare(lot, 5, 9), "S")
        -- From the camera's side a car facing this way would hide its trailer.
        art.trailer.car:permanentlyRemove()
        art.trailer.car = nil
        setBlood(art.trailer.trailer, BLOOD_SIDES)
        return Stage.vehiclesAtRest(art.trailer, false)
    end)
    addShot(steps, player, lot, SHOTS.trailerFront)
    addStates(steps, art.currentPair, LONE_STATES)
    addCrackedShot(steps, player, lot)
end

function Art.capture(onDone)
    local run = Capture.new(MARK)
    local player = getPlayer()
    local lot = findLot(player)
    if not lot then
        run:fail("no open lot within " .. Stage.SEARCH_RADIUS .. " squares")
        return
    end
    print(string.format("REArt stage at %d,%d", lot.x, lot.y))
    local art = {}
    function art.currentPair()
        return art.trailer
    end
    addTileAndItemShots(run.steps, player, lot)
    addHitchedTrailerShots(run.steps, player, lot, art)
    addLoneAndCrackedShots(run.steps, player, lot, art)
    run:run(nil, onDone)
end

return Art
