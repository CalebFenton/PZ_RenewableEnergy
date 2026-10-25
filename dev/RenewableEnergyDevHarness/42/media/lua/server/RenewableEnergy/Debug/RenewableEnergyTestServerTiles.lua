-- The authority's half of the tile tests: placed panels, their modData, and scrapping. Only registers
-- handlers, so a --stay rerun loads it again (RELOAD_FILES); RenewableEnergyTestHelpers.lua says
-- how these handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
require "RenewableEnergy/Sprites"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler
local objectAt, overlaysOf = Helpers.objectAt, PZHarness.Fixtures.overlaysOf
local Sprites = RenewableEnergy.Sprites

-- The panel drawn as `args.sprite` on the square at `args`, changed by `args.change`, if given: its
-- modules replaced by `change.modules` and, with `change.snow`, snow laid on it first; then its
-- cracks shown as the mod shows them. Answers its overlays in drawing order.
handler("panelCracks", function(_, args)
    local PanelSource = RenewableEnergy.PanelSource
    local panel, missing = objectAt(args)
    if not panel then
        return nil, missing
    end
    local change = args.change
    if change then
        if change.snow then
            panel:addAttachedAnimSpriteByName(Sprites.snow.flat)
        end
        PanelSource.writeModules(panel, change.modules)
    end
    PanelSource.showCracks(panel)
    return { overlays = overlaysOf(panel) }
end)

-- The modData key `args.key` of the object drawn as `args.sprite` on the square at `args`.
handler("objectModData", function(_, args)
    local object, missing = objectAt(args)
    if not object then
        return nil, missing
    end
    return { value = object:getModData()[args.key] }
end)

-- The tiles of the object the tile `spriteName` is part of, each { square, sprite }, laid out so
-- that `spriteName` stands on `square`: its sprite grid's, or the one tile without a grid.
local function tilesOf(square, spriteName)
    local sprite = getSprite(spriteName)
    local grid = sprite and sprite:getSpriteGrid()
    if not grid then
        return { { square = square, sprite = spriteName } }
    end
    local x, y = square:getX() - grid:getSpriteGridPosX(sprite), square:getY() - grid:getSpriteGridPosY(sprite)
    local tiles = {}
    for gx = 0, grid:getWidth() - 1 do
        for gy = 0, grid:getHeight() - 1 do
            local member = grid:getSprite(gx, gy)
            if member then
                table.insert(tiles, { square = getSquare(x + gx, y + gy, square:getZ()), sprite = member:getName() })
            end
        end
    end
    return tiles
end

-- Every tile of the object `args.sprite` is part of, placed so that `args.sprite` stands on the
-- square at `args`, its containers looked in and empty, as vanilla dismantles only such an object
-- (IsoObject.isObjectNoContainerOrEmpty). Removed when the test ends.
handler("placeWhole", function(_, args, defer)
    for _, tile in ipairs(tilesOf(PZHarness.Fixtures.squareAt(args), args.sprite)) do
        if not tile.square then
            return nil, "a loaded square for every tile of " .. args.sprite
        end
        local object = PZHarness.Fixtures.newTile(tile.square, tile.sprite)
        defer(function() PZHarness.Fixtures.removePlaced(object) end)
        for i = 0, object:getContainerCount() - 1 do
            local container = object:getContainerByIndex(i)
            container:setExplored(true)
            Helpers.emptyContainer(container)
        end
    end
    return {}
end)

-- Dismantles the object drawn as `args.sprite` on the square at `args` as the authority's
-- character, clicking that tile, the way the moveables action completes a scrap
-- (ISMoveableSpriteProps.scrapObject), first giving the character the tools its scrap definition
-- asks for that it lacks. Answers whether every tile went and how many `args.type` it gave, into
-- the inventory or onto the object's squares; what the dismantling gave and the tools go away.
handler("scrapItems", function(player, args)
    local object, missing = objectAt(args)
    if not object then
        return nil, missing
    end
    local props = ISMoveableSpriteProps.fromObject(object)
    local tiles = tilesOf(object:getSquare(), args.sprite)
    local inventory = player:getInventory()
    -- The items in the inventory and lying on the object's squares, by ID, but those in `before`.
    local function itemsBut(before)
        local found = {}
        local items = inventory:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if not before[item:getID()] then
                found[item:getID()] = { item = item }
            end
        end
        for _, tile in ipairs(tiles) do
            local objects = tile.square and tile.square:getWorldObjects()
            for i = 0, (objects and objects:size() or 0) - 1 do
                local item = objects:get(i):getItem()
                if not before[item:getID()] then
                    found[item:getID()] = { item = item, square = tile.square, object = objects:get(i) }
                end
            end
        end
        return found
    end
    local before = itemsBut({})
    local def = ISMoveableDefinitions:getInstance().getScrapDefinition(props.material)
    for _, second in ipairs({ false, true }) do
        local tools = def and (second and def.tools2 or def.tools) or {}
        if not props:hasScrapTool(player, second) then
            for _, tool in ipairs(tools) do
                if not tool:find("^Tag%.") then
                    sendAddItemToContainer(inventory, inventory:AddItem(tool))
                    break
                end
            end
        end
    end
    local can = props:canScrapObject(player)
    if not can.canScrap then
        return nil, string.format("a %s the character may dismantle (canScrap %s, valid %s, tools %s and %s, full %s)",
            args.sprite, tostring(props.canScrap), tostring(can.craftValid), tostring(can.haveTool), tostring(can.haveTool2),
            tostring(can.containerFull))
    end
    props:scrapObject(player)
    local count, scrapped = 0, true
    for _, tile in ipairs(tiles) do
        scrapped = scrapped and PZHarness.Fixtures.objectWithSprite(tile.square, tile.sprite) == nil
    end
    for _, new in pairs(itemsBut(before)) do
        count = count + (new.item:getFullType() == args.type and 1 or 0)
        if new.object then
            Helpers.removeFloorItem(new.square, new.object)
        else
            inventory:Remove(new.item)
            sendRemoveItemFromContainer(inventory, new.item)
        end
    end
    return { count = count, scrapped = scrapped }
end)
