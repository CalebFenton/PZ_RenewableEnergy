require "RenewableEnergy/Sprites"

-- The failsafe shares its square with the generator it watches. It is placed as a floor rug
-- (MoveType = FloorRug), the one kind of object allowed onto a square that already holds something
-- solid, which also files it under the generator, just above the floor. So it is moved to the end
-- of the square's objects, to draw over the generator: when it is added, and whenever its chunk
-- loads, because a square loads its objects in their saved order.
--
-- Every side does this to its own copy and nothing is sent, so that generator syncs, which name an
-- object by its index on the square (IsoGenerator.syncIsoObjectSend), agree everywhere. Moving it
-- goes through RemoveTileObject, which fires OnObjectAboutToBeRemoved and OnTileRemoved for the
-- failsafe, so their handlers must leave it alone.

local FAILSAFE = RenewableEnergy.Sprites.failsafe
-- MapObjects keeps one function per sprite and priority.
local LOAD_PRIORITY = 6

local function moveToTop(failsafe)
    local square = failsafe:getSquare()
    if not square then
        return
    end
    local last = square:getObjects():size() - 1
    if failsafe:getObjectIndex() == last then
        return
    end
    square:RemoveTileObject(failsafe)
    square:AddSpecialObject(failsafe, last)
end

local function onObjectAdded(isoObject)
    if isoObject and isoObject:getTextureName() == FAILSAFE then
        moveToTop(isoObject)
    end
end

MapObjects.OnLoadWithSprite(FAILSAFE, moveToTop, LOAD_PRIORITY)
Events.OnObjectAdded.Add(onObjectAdded)
