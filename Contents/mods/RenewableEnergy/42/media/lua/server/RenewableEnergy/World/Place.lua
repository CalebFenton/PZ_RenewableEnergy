-- Putting things in the world on the authority, as a player's placing or building them would:
-- moveable tiles from the item their tile gives back, build-menu entities, crates. What goes in
-- them is the caller's.

if isClient() then return end

require "Moveables/ISMoveableSpriteProps"
local Sprites = require "RenewableEnergy/Sprites"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local Tiles = require "cf_commonlib/Tiles"

local Place = {}

--- Places a moveable tile the way a player's placing it would, from the item its tile gives
--- back, carrying `modData` (keys copied onto the item, which placing copies onto the object).
---@param square IsoGridSquare
---@param spriteName string a mount tile of Sprites, or a garden light
---@param modData table?
function Place.moveable(square, spriteName, modData)
    local sprite = getSprite(spriteName)
    local item = instanceItem(sprite:getProperties():get("CustomItem"))
    for key, value in pairs(modData or {}) do
        item:getModData()[key] = value
    end
    ISMoveableSpriteProps.new(sprite):placeMoveableInternal(nil, square, item, spriteName)
end

--- Places a panel mount holding `modules` (a Panel.MODULES_KEY list).
function Place.panel(square, spriteName, modules)
    Place.moveable(square, spriteName, { [Panel.MODULES_KEY] = modules })
end

--- Builds the entity of the tile `sprite` (Tiles.newEntity) as ISBuildIsoEntity:create does: a
--- thumpable with its entity's components on the square, then the entity's OnCreate, which
--- announces it (OnObjectAdded) where it needs announcing, and sends it to the clients.
--- `wear(thumpable)`, if given, sets its worn state before they get it. Returns the thumpable.
function Place.entity(square, sprite, onCreate, wear)
    return Tiles.addToWorld(square, Tiles.newEntity(square, sprite), {
        beforeSend = function(thumpable)
            thumpable:setExplored(true)
            onCreate({ thumpable = thumpable })
            if wear then
                wear(thumpable)
            end
            square:RecalcAllWithNeighbours(true)
        end,
        announce = false,
    })
end

--- Places a crate of the mod's tile, `fill(container)` stocking it, explored so that neither the
--- room's loot nor loot respawn fills it, with the lid overlay vanilla gives a filled container
--- (CrateOverlays.lua), as ItemPickerJava does after filling one. Returns it.
---@param square IsoGridSquare
---@return IsoObject
function Place.crate(square, fill)
    local crate = IsoObject.new(square:getCell(), square, Sprites.crate)
    crate:createContainersFromSpriteProperties()
    local container = crate:getContainer()
    fill(container)
    container:setExplored(true)
    return Tiles.addToWorld(square, crate, {
        -- On a server this sends the overlay, naming the crate by its index on the square
        -- (IsoObject.setOverlaySprite).
        afterSend = ItemPickerJava.updateOverlaySprite,
    })
end

-- A world bank stands with its back to a wall of its square, as furniture does: each facing, and
-- the step from the square across its back edge. S, the facing a bank takes with no wall, first.
local BACK_TO_WALL = { { "S", 0, -1 }, { "E", -1, 0 }, { "N", 0, 1 }, { "W", 1, 0 } }

--- The facing that puts a bank on `square` with its back to a wall, or S with no wall around it.
---@param square IsoGridSquare
---@return string facing "S", "E", "N" or "W"
function Place.bankFacing(square)
    for _, back in ipairs(BACK_TO_WALL) do
        local behind = getCell():getGridSquare(square:getX() + back[2], square:getY() + back[3], square:getZ())
        if behind and square:isWallTo(behind) then
            return back[1]
        end
    end
    return "S"
end

return Place
