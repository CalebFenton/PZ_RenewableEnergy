-- The failsafe shares its square with the generator it watches. It is placed as a floor rug, the
-- one kind of object allowed onto a square that already holds something solid, which files it
-- under the generator. So it is moved to the end of the square's objects, to draw over the
-- generator: when it is added, and whenever its chunk loads, because a square loads its objects
-- in their saved order.
--
-- Every side does this to its own copy and nothing is sent, so that generator syncs, which name an
-- object by its index on the square (IsoGenerator.syncIsoObjectSend), agree everywhere.
-- RemoveTileObject fires OnObjectAboutToBeRemoved and OnTileRemoved for the failsafe, so their
-- handlers must leave it alone.

local Sprites = require "RenewableEnergy/Sprites"
local Tiles = require "cf_commonlib/Tiles"

local Failsafe = {}

local FAILSAFE = Sprites.failsafe

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

--- Whether `isoObject` is a failsafe relay.
function Failsafe.isFailsafe(isoObject)
    return Sprites.nameOf(isoObject) == FAILSAFE
end

Tiles.onLoad({ FAILSAFE }, moveToTop, { matches = Failsafe.isFailsafe, added = true })

return Failsafe
