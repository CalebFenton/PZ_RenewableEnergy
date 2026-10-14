require "RenewableEnergy/Utilities"

-- The places of one kind of placed tile, for code that runs each loaded tile now and then.
--
-- MapObjects reports a tile when its chunk loads, and OnObjectAdded when one is placed (vanilla's
-- moveables fire it in single player too). Nothing reports a chunk unloading, so a place whose
-- tile isn't there any more is dropped while the places are walked; MapObjects reports the tile
-- again when its chunk loads. A tile leaving its square is dropped at once.
RenewableEnergy = RenewableEnergy or {}
local PlaceTracker = {}
PlaceTracker.__index = PlaceTracker
RenewableEnergy.PlaceTracker = PlaceTracker

-- MapObjects keeps one function per sprite and priority, and each tracker has its own sprites.
local LOAD_PRIORITY = 7
-- World squares lie well under this in x and y, so the key below stays exact in a double.
local SPAN = 1e6

--- The place x, y, z as one number. A key joined from strings would cost nearly twice the time
--- and six times the memory of each lookup in Kahlua.
function PlaceTracker.key(x, y, z)
    return (z * SPAN + y) * SPAN + x
end

local function forget(tracker, key)
    tracker.places[key] = nil
    if tracker.onLost then
        tracker.onLost(key)
    end
end

--- Starts tracking the tiles that `options.matches(isoObject)` accepts, which have the sprites
--- `options.sprites`. `options.onFound(isoObject)`, if given, runs for each such tile as its chunk
--- loads or it is placed, and `options.onLost(key)` for each place dropped. With
--- `options.keepPlaces` false the tracker keeps no places, and only calls onFound.
function PlaceTracker.new(options)
    local self = setmetatable({
        matches = options.matches,
        onFound = options.onFound,
        onLost = options.onLost,
        places = {},
    }, PlaceTracker)
    local keep = options.keepPlaces ~= false
    local function found(isoObject)
        if keep then
            self:add(isoObject)
        end
        if self.onFound then
            self.onFound(isoObject)
        end
    end
    MapObjects.OnLoadWithSprite(options.sprites, found, LOAD_PRIORITY)
    Events.OnObjectAdded.Add(function(isoObject)
        if self.matches(isoObject) then
            found(isoObject)
        end
    end)
    if keep then
        Events.OnObjectAboutToBeRemoved.Add(function(isoObject)
            if self.matches(isoObject) then
                forget(self, PlaceTracker.key(isoObject:getX(), isoObject:getY(), isoObject:getZ()))
            end
        end)
    end
    return self
end

--- Tracks the place of `isoObject` without calling onFound.
function PlaceTracker:add(isoObject)
    local x, y, z = isoObject:getX(), isoObject:getY(), isoObject:getZ()
    local key = PlaceTracker.key(x, y, z)
    if not self.places[key] then
        self.places[key] = { x = x, y = y, z = z }
    end
end

--- Calls `fn` with the tile at each place whose square is loaded, and drops the others.
function PlaceTracker:each(fn)
    local cell = getCell()
    for key, place in pairs(self.places) do
        local isoObject = RenewableEnergy.findObjectOn(cell:getGridSquare(place.x, place.y, place.z), self.matches)
        if isoObject then
            fn(isoObject)
        else
            forget(self, key)
        end
    end
end

return PlaceTracker
