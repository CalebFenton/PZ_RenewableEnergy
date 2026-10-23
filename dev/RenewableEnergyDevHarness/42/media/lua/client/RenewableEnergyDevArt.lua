-- Development only; dev/run-debug-client.sh --art runs it instead of the tests. It checks the art
-- from art/models in the world: it builds one stage after another on the same open lot and saves
-- each shot to <cachedir>/Screenshots as <name>.png.

require "ISUI/ISPanel"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Debug/RenewableEnergyDebug"
local Stage = require "RenewableEnergyDevStage"
local Capture = require "PZHarness/Capture"

local Art = {}

local Sprites = RenewableEnergy.Sprites
local MARK = "REArt"
local NOON = 12

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
-- The batteries the fill tiles hold, in turn, so every look shows in every slot.
local FILL_BATTERIES = { "Base.CarBattery1", "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery" }

-- Every bank tile, of every tier, with 1 to all of its batteries, its meter cycling through every
-- level; one with fewer batteries than meter levels repeats its full count. The batteries' types
-- take turns, starting one further on each tile. Low tiers come first, at the back, so the tall
-- banks in front hide none of them.
local function fillTiles()
    local fill, x, y = {}, 0, 0
    for _, field in ipairs(FILL_TIERS) do
        local capacity = #Sprites.bankFill[field].batteries.car
        for i = 1, math.max(capacity, #METER_CHARGES) do
            local charge = METER_CHARGES[(i - 1) % #METER_CHARGES + 1]
            local types = {}
            for slot = 1, math.min(i, capacity) do
                types[slot] = FILL_BATTERIES[(i + slot - 2) % #FILL_BATTERIES + 1]
            end
            table.insert(fill, { x = x, y = y, sprite = Sprites[field], overlays = Sprites.bankOverlays(field, types, charge) })
            x = x + 1
            if x >= AREA.w then
                x, y = 0, y + 2
            end
        end
    end
    return fill
end

-- The Metal Drum and insulated digesters bare, then with each of their holder's overlays, a column
-- to each; the other barrels bare, then every barrel with a holder and its scrubber. The barrels'
-- holders lie on the east side of their square, which the next barrel to the east would hide, so
-- the variants run south.
local function digesterTiles()
    local list, holder, scrubber = {}, Sprites.digesterHolder, Sprites.digesterScrubber
    local columns = {
        { x = 1, sprite = Sprites.digester.barrel.MetalDrum, overlays = { holder.bags[1], holder.bags[2],
            holder.bags[3], holder.bagsTorn, holder.tarp[1], holder.tarp[2], holder.tarp[3], holder.tarpTorn } },
        { x = 3, sprite = Sprites.digester.insulated, overlays = holder.drum },
    }
    for _, digester in ipairs(columns) do
        table.insert(list, { x = digester.x, y = 0, sprite = digester.sprite })
        for i, overlay in ipairs(digester.overlays) do
            table.insert(list, { x = digester.x, y = i, sprite = digester.sprite, overlays = { overlay } })
        end
    end
    local others = { "Mov_OrangeBarrel", "Mov_DarkGreenBarrel", "Mov_LightGreenBarrel" }
    for i, barrel in ipairs(others) do
        table.insert(list, { x = 5, y = i - 1, sprite = Sprites.digester.barrel[barrel] })
    end
    local scrubbed = { MetalDrum = holder.bags[3], Mov_OrangeBarrel = holder.tarp[2],
        Mov_DarkGreenBarrel = holder.bags[1], Mov_LightGreenBarrel = holder.tarp[3] }
    for i, barrel in ipairs({ "MetalDrum", unpack(others) }) do
        table.insert(list, { x = 5, y = i + 3, sprite = Sprites.digester.barrel[barrel], overlays = { scrubbed[barrel], scrubber.barrel } })
    end
    -- The insulated digester with its scrubber, the dome bare and with it, then the gas heater off
    -- and lit and the game's generator bodies with the gas kit on their intakes.
    table.insert(list, { x = 7, y = 1, sprite = Sprites.digester.insulated, overlays = { holder.drum[2], scrubber.insulated } })
    table.insert(list, { x = 7, y = 4, sprite = Sprites.digester.dome })
    table.insert(list, { x = 7, y = 6, sprite = Sprites.digester.dome, overlays = { scrubber.dome } })
    table.insert(list, { x = 9, y = 0, sprite = Sprites.gasHeater.off })
    table.insert(list, { x = 9, y = 2, sprite = Sprites.gasHeater.lit })
    for i, generator in ipairs({ "appliances_misc_01_0", "appliances_misc_01_5", "appliances_misc_01_12" }) do
        table.insert(list, { x = 9, y = 2 + i * 2, sprite = generator, overlays = { Sprites.gasKitFor(generator) } })
    end
    -- Each gasifier, then lit, and two piped to a kitted generator: one to its east, one to its north.
    for column, tier in ipairs({ "primitive", "standard", "advanced" }) do
        table.insert(list, { x = column * 2 - 1, y = 10, sprite = Sprites.gasifier[tier] })
        table.insert(list, { x = column * 2 - 1, y = 12, sprite = Sprites.gasifier[tier], overlays = { Sprites.gasifierLit[tier] } })
    end
    table.insert(list, { x = 7, y = 10, sprite = Sprites.gasifier.standard,
        overlays = { Sprites.gasifierLit.standard, Sprites.gasifierPipe.E } })
    local east, north = "appliances_misc_01_0", "appliances_misc_01_6"
    table.insert(list, { x = 8, y = 10, sprite = east, overlays = { Sprites.gasKitFor(east), Sprites.gasifierPipeGenFor(east, "W") } })
    table.insert(list, { x = 9, y = 12, sprite = Sprites.gasifier.advanced, overlays = { Sprites.gasifierPipe.N } })
    table.insert(list, { x = 9, y = 11, sprite = north, overlays = { Sprites.gasKitFor(north), Sprites.gasifierPipeGenFor(north, "S") } })
    return list
end

-- The scoop rotor wind charger as its sprite model at each spin step, spaced for the rotor's swing,
-- and once as its plain tile.
local function windTiles()
    local list = {}
    local prefix, model = Sprites.windModelOf(Sprites.windScoop)
    for step = 0, model.steps - 1 do
        table.insert(list, { x = (step % 3) * 3 + 1, y = math.floor(step / 3) * 3 + 1, sprite = Sprites.windScoop,
            spriteModel = prefix .. step })
    end
    table.insert(list, { x = 1, y = 7, sprite = Sprites.windScoop })
    return list
end

-- The propeller chargers, wooden then pipe, and the alternator charger, a row each, as their sprite
-- models facing each way in turn, spaced for their rotors, each at a different spin step.
local function tallWindTiles()
    local list = {}
    for row, sprites in ipairs({ Sprites.windPropeller.wood, Sprites.windPropeller.pipe, Sprites.windAlternator }) do
        for column, facing in ipairs({ "N", "E", "S", "W" }) do
            table.insert(list, { x = (column - 1) * 3, y = row * 4 - 2, sprite = sprites[facing],
                spriteModel = Sprites.windModelOf(sprites[facing]) .. (column - 1) })
        end
    end
    return list
end

-- Where the character stands for each shot, and how far it zooms out from the closest zoom. For
-- the tiles it stands in front of a wall panel, which the depth map must draw behind it.
local SHOTS = {
    tiles = { name = "art_tiles", x = 2, y = 1, zoomSteps = 3 },
    overlays = { name = "art_overlays", x = 4, y = 10, zoomSteps = 2 },
    items = { name = "art_items", x = 4, y = 5, zoomSteps = 1 },
    fill = { name = "art_fill", x = 6, y = 12, zoomSteps = 3 },
    trailer = { name = "art_trailer", x = 8, y = 7, zoomSteps = 2 },
    trailerFront = { name = "art_trailer_front", x = 3, y = 6, zoomSteps = 2 },
    digesters = { name = "art_digesters", x = 5, y = 8, zoomSteps = 2 },
    -- Beside the second row's middle turbine, for its size against a person.
    wind = { name = "art_wind", x = 5, y = 5, zoomSteps = 2 },
    -- In front of the tall chargers, all in view; then just behind the east-facing alternator, which
    -- stands between the character and the camera.
    windTall = { name = "art_wind_tall", x = 5, y = 12, zoomSteps = 3 },
    windBehind = { name = "art_wind_behind", x = 3, y = 9, zoomSteps = 1 },
}

-- Damage stage 1 is a condition from 40 to 59, stage 2 below 40 (BaseVehicle.doDamageOverlay).
local STAGE_1, STAGE_2 = 50, 20
-- The frame's front and back, and the battery box lid.
local BODY_PARTS = { "EngineDoor", "TruckBed", "TrunkDoor" }
local BLOOD_SIDES = { "Front", "Rear", "Left", "Right" }
-- Indices into ArrowBoard.PANELS, which the server folder defines only after this file loads.
local LEFT, RIGHT = 1, 2

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
    local door = pair.trailer:getPartById(RenewableEnergy.ArrowBoard.LID):getDoor()
    -- Spawned trailers are often locked, and a locked lid wouldn't open in play.
    door:setLocked(false)
    door:setOpen(open)
    local start = getTimestampMs()
    return function() return getTimestampMs() - start >= LID_SWING_MS end
end

-- The lid shut and padlocked or not; ArrowBoard's lid watcher shows the padlock by the next frame.
local function lockLid(pair, locked)
    local door = pair.trailer:getPartById(RenewableEnergy.ArrowBoard.LID):getDoor()
    door:setOpen(false)
    door:setLockBroken(false)
    door:setLocked(locked)
end

-- How far into a flash a lit shot waits, so the frame it copies has drawn the lamps lit.
local FLASH_SETTLE_MS = 150
-- The last moment into a flash a lit shot may start, leaving the rest of the flash for the shot.
local FLASH_SHOT_MS = 500

-- The trailer switched on with a charged battery in its box, or none if not `lit`, its lamps set
-- as the clock's pass sets them, lighting the ground if `night`, the clock set to midnight then.
-- Returns a runSteps wait: at night until the lighting has settled on the dark and the board's
-- lamppost, and for lit lamps until they are a little way into a flash.
local function setLamps(pair, lit, night)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    pair.trailer:getPartById(ArrowBoard.BATTERY_BOX):getItemContainer():removeAllItems()
    if night then
        getGameTime():setTimeOfDay(0)
    end
    Stage.lightLamps(pair.trailer, lit and 0.8 or nil, night)
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
    -- One side alone settles which side is which.
    { name = "art_trailer_blood_right", set = function(pair) setBlood(pair.trailer, { "Right" }) end },
    { name = "art_trailer_blood", set = function(pair) setBlood(pair.trailer, BLOOD_SIDES) end },
    {
        name = "art_trailer_brake",
        set = function(pair)
            -- A towed trailer's brake lights follow its car's, which need charge in the car's battery.
            local part = RenewableEnergy.VehicleBattery.partOf(pair.car)
            local battery = part and part:getInventoryItem()
            if battery then
                battery:setCurrentUsesFloat(1)
            end
            pair.car:setStoplightsOn(true)
        end,
    },
    {
        name = "art_trailer_panel_cracked",
        set = function(pair)
            pair.trailer:getPartById(RenewableEnergy.ArrowBoard.PANELS[RIGHT]):setCondition(30)
            RenewableEnergy.ArrowBoard.showPanels(pair.trailer)
        end,
    },
    {
        name = "art_trailer_panel_removed",
        set = function(pair)
            pair.trailer:getPartById(RenewableEnergy.ArrowBoard.PANELS[LEFT]):setInventoryItem(nil)
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
    {
        name = "art_trailer_lid_removed",
        set = function(pair) pair.trailer:getPartById(RenewableEnergy.ArrowBoard.LID):setInventoryItem(nil) end,
    },
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

-- `art.pair` is spawned by an earlier step, so the steps read it only as they run.
local function addStates(steps, art, states)
    for _, state in ipairs(states) do
        table.insert(steps, function()
            local pair = art.pair
            pair.trailer:repair()
            -- repair() mends the panels without anything showing their models again.
            RenewableEnergy.ArrowBoard.showPanels(pair.trailer)
            if pair.car then
                pair.car:setStoplightsOn(false)
            end
            -- A part's new condition reaches the overlay on the vehicle's next update, once a frame.
            return state.set(pair) or Capture.DRAW_FRAMES
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

-- The north-west corner of the closest open lot that takes the whole stage.
local function findLot(player)
    local corner = Stage.closestSquare(player, function(square)
        return Stage.isAreaOpen(square, AREA.w, AREA.h, isOpen)
    end)
    return corner and { x = corner:getX(), y = corner:getY(), z = corner:getZ() }
end

local function lotSquare(lot, x, y)
    return getCell():getGridSquare(lot.x + x, lot.y + y, lot.z)
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
    Stage.removeVehicles(lot.x - VEHICLE_MARGIN, lot.y - VEHICLE_MARGIN, lot.x + AREA.w + VEHICLE_MARGIN - 1,
        lot.y + AREA.h + VEHICLE_MARGIN - 1, lot.z)
end

-- Places each entry of `list` ({ x, y, sprite, overlays, spriteModel }) on the lot. A sprite model
-- draws the object as that model instead of its tile; an animating object stays out of the cached
-- chunk, so the model shows at once.
local function placeTiles(lot, list)
    for _, tile in ipairs(list) do
        local object = Stage.placeTile(lotSquare(lot, tile.x, tile.y), tile.sprite)
        for _, overlay in ipairs(tile.overlays or {}) do
            object:addAttachedAnimSpriteByName(overlay)
        end
        if tile.spriteModel then
            object:setSpriteModelName(tile.spriteModel)
            object:setAnimating(true)
        end
    end
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
            print(MARK .. " missing item " .. fullType)
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
    local sheet = ISPanel.new(self, 60, 160, ICON_COLUMNS * CELL_W, rows * CELL_H + 8)
    sheet.icons = icons
    sheet.backgroundColor = { r = 0.25, g = 0.25, b = 0.25, a = 1 }
    return sheet
end

-- The steps that walk the character to a shot's spot, let it see around, zoom and save.
local function addShot(steps, player, lot, shot)
    Stage.addLookAround(steps, player, lotSquare(lot, shot.x, shot.y))
    table.insert(steps, function()
        return Stage.zoomOut(shot.zoomSteps)
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
-- The squares east of the mounts stay open for a trailer with a cracked panel. The character
-- stands south-east of the mounts and south-west of the open ground, hiding neither.
local CRACKED_SHOT = { name = "art_cracked", x = 7, y = 7, zoomSteps = 2 }

local function addCrackedShot(steps, player, lot)
    table.insert(steps, function()
        clearLot(lot)
        clearVehicles(lot)
        placeTiles(lot, CRACKED_WALLS)
        for _, panel in ipairs(CRACKED_PANELS) do
            local modules = {}
            for slot, condition in ipairs(panel.conditions) do
                modules[slot] = { type = RenewableEnergy.Specs.factoryModule, condition = condition }
            end
            RenewableEnergy.WorldSpawns.placePanel(lotSquare(lot, panel.x, panel.y), panel.sprite, modules)
        end
        recalcLot(lot)
    end)
    -- A trailer beside them with one panel cracked as theirs are and one whole, to compare the look.
    -- The tick after stocking puts the stock conditions back over any set in the same tick
    -- (ArrowBoard.lua's keepStockConditions), so they're set a step later.
    local trailer
    table.insert(steps, function()
        -- Row 4 keeps all of it on the cleared lot.
        trailer = addVehicleDebug(RenewableEnergy.ArrowBoard.SCRIPT, IsoDirections.N, 0, lotSquare(lot, 6, 4))
        return 1
    end)
    table.insert(steps, function()
        trailer:repair()
        trailer:getPartById(RenewableEnergy.ArrowBoard.PANELS[LEFT]):setCondition(30)
        trailer:getPartById(RenewableEnergy.ArrowBoard.PANELS[RIGHT]):setCondition(100)
        RenewableEnergy.ArrowBoard.showPanels(trailer)
        -- Dark, as Stage.spawnTrailer leaves its trailers.
        RenewableEnergy.ArrowBoard.setSwitch(trailer, false)
        return Stage.vehiclesAtRest({ trailer = trailer }, false)
    end)
    addShot(steps, player, lot, CRACKED_SHOT)
end

-- The tile, overlay, item, icon, fill, digester and wind shots, each on the lot cleared of the one
-- before.
local function addTileAndItemShots(steps, player, lot)
    local iconSheet = IconSheet:new()
    table.insert(steps, function()
        getGameTime():setTimeOfDay(NOON)
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
    table.insert(steps, function()
        clearLot(lot)
        placeTiles(lot, digesterTiles())
    end)
    addShot(steps, player, lot, SHOTS.digesters)
    table.insert(steps, function()
        clearLot(lot)
        placeTiles(lot, windTiles())
    end)
    addShot(steps, player, lot, SHOTS.wind)
    table.insert(steps, function()
        clearLot(lot)
        placeTiles(lot, tallWindTiles())
    end)
    addShot(steps, player, lot, SHOTS.windTall)
    addShot(steps, player, lot, SHOTS.windBehind)
end

-- The trailer hitched to its car, then the rear in each of its states. The steps spawn the pair
-- into `art.pair`.
local function addHitchedTrailerShots(steps, player, lot, art)
    table.insert(steps, function()
        clearLot(lot)
        clearVehicles(lot)
        art.pair = Stage.spawnTrailer(lotSquare(lot, 5, 3), "N")
        return Stage.vehiclesAtRest(art.pair, false)
    end)
    table.insert(steps, function()
        Stage.hitchTrailer(art.pair, player, MARK)
        return Stage.vehiclesAtRest(art.pair, true)
    end)
    addShot(steps, player, lot, SHOTS.trailer)
    addStates(steps, art, HITCHED_STATES)
end

-- A second trailer alone, facing the other way, in each of its states, then the cracked panels.
local function addLoneAndCrackedShots(steps, player, lot, art)
    -- Back to noon after the hitched trailer's night shot.
    table.insert(steps, function()
        getGameTime():setTimeOfDay(NOON)
        return Stage.lightingSettled(player, true)
    end)
    table.insert(steps, function()
        clearVehicles(lot)
        art.pair = Stage.spawnTrailer(lotSquare(lot, 5, 9), "S")
        -- From the camera's side a car facing this way would hide its trailer.
        art.pair.car:permanentlyRemove()
        art.pair.car = nil
        setBlood(art.pair.trailer, BLOOD_SIDES)
        return Stage.vehiclesAtRest(art.pair, false)
    end)
    addShot(steps, player, lot, SHOTS.trailerFront)
    addStates(steps, art, LONE_STATES)
    addCrackedShot(steps, player, lot)
end

function Art.capture(_, onDone)
    local run = Capture.new(MARK)
    local player = getPlayer()
    local lot = findLot(player)
    if not lot then
        run:fail("no open lot within " .. Stage.SEARCH_RADIUS .. " squares")
        return
    end
    print(string.format("%s stage at %d,%d", MARK, lot.x, lot.y))
    local art = {}
    addTileAndItemShots(run.steps, player, lot)
    addHitchedTrailerShots(run.steps, player, lot, art)
    addLoneAndCrackedShots(run.steps, player, lot, art)
    run:run(nil, onDone)
end

return Art
