-- The authority's half of the tile tests: placed panels and scrapping.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
local Sprites = require "RenewableEnergy/Sprites"
local Items = require "cf_commonlib/Items"
require "PZHarness/ServerFixtures"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"
local Kinds = require "RenewableEnergy/Debug/RenewableEnergyTestKinds"
local PanelSource = require "RenewableEnergy/PowerBank/PanelSource"

local handler, need, Fixtures = PZHarness.serverHandler, PZHarness.need, PZHarness.Fixtures

-- The panel drawn as `args.sprite` on the square at `args`, changed by `args.change`, if given: its
-- modules replaced by `change.modules` and, with `change.snow`, snow laid on it first; then its
-- cracks shown as the mod shows them. Answers its overlays in drawing order.
handler("panelCracks", function(_, args)
    local panel = Kinds.find(args)
    local change = args.change
    if change then
        if change.snow then
            panel:addAttachedAnimSpriteByName(Sprites.snow.flat)
        end
        PanelSource.writeModules(panel, change.modules)
    else
        PanelSource.showCracks(panel)
    end
    return { overlays = Fixtures.overlaysOf(panel) }
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
    for _, tile in ipairs(tilesOf(PZHarness.squareAt(args), args.sprite)) do
        local object = Fixtures.newTile(need(tile.square, "a loaded square for every tile of " .. args.sprite), tile.sprite)
        defer(function() Fixtures.removePlaced(object) end)
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
    local object = Kinds.find(args)
    local props = ISMoveableSpriteProps.fromObject(object)
    local tiles = tilesOf(object:getSquare(), args.sprite)
    local inventory, squares = player:getInventory(), {}
    for _, tile in ipairs(tiles) do
        table.insert(squares, tile.square)
    end
    -- The items lying on the object's squares and in the inventory, as a set.
    local function held()
        local found, items = PZHarness.Fixtures.worldItems(squares), inventory:getItems()
        for i = 0, items:size() - 1 do
            found[items:get(i)] = inventory
        end
        return found
    end
    local before = held()
    local def = ISMoveableDefinitions:getInstance().getScrapDefinition(props.material)
    for _, second in ipairs({ false, true }) do
        local tools = def and (second and def.tools2 or def.tools) or {}
        if not props:hasScrapTool(player, second) then
            for _, tool in ipairs(tools) do
                if not tool:find("^Tag%.") then
                    Items.addItem(inventory, tool)
                    break
                end
            end
        end
    end
    local can = props:canScrapObject(player)
    need(can.canScrap, string.format("a %s the character may dismantle (canScrap %s, valid %s, tools %s and %s, full %s)",
        args.sprite, tostring(props.canScrap), tostring(can.craftValid), tostring(can.haveTool), tostring(can.haveTool2),
        tostring(can.containerFull)))
    props:scrapObject(player)
    local count, scrapped = 0, true
    for _, tile in ipairs(tiles) do
        scrapped = scrapped and Fixtures.objectWithSprite(tile.square, tile.sprite) == nil
    end
    for _, new in ipairs(PZHarness.Fixtures.newSince(before, held())) do
        local onFloor = instanceof(new, "IsoWorldInventoryObject")
        count = count + ((onFloor and new:getItem() or new):getFullType() == args.type and 1 or 0)
        if onFloor then
            Fixtures.removePlaced(new)
        else
            Items.removeItem(new)
        end
    end
    return { count = count, scrapped = scrapped }
end)
