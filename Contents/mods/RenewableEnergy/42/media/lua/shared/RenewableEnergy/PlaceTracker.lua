-- The places of one kind of placed tile, for code that runs each loaded tile now and then.
--
-- MapObjects reports a tile when its chunk loads, and OnObjectAdded when one is placed (vanilla's
-- moveables fire it in single player too). Nothing reports a chunk unloading, so a place whose
-- tile isn't there any more is dropped while the places are walked; MapObjects reports the tile
-- again when its chunk loads. A tile leaving its square is dropped at once.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"

RenewableEnergy = RenewableEnergy or {}
local PlaceTracker = {}
PlaceTracker.__index = PlaceTracker
RenewableEnergy.PlaceTracker = PlaceTracker

-- Its own priority, apart from the systems' loaders of the same sprites (Sprites.LOAD_PRIORITY).
-- Every tracker shares it, so no two trackers may take the same sprite.
local LOAD_PRIORITY = RenewableEnergy.Sprites.LOAD_PRIORITY + 1
-- World squares lie well under this in x and y, so a place key stays unique and exact in a double.
local SPAN = 1e6

--- The place x, y, z as one number: string keys cost far more time and memory per lookup in Kahlua.
function PlaceTracker.key(x, y, z)
    return (z * SPAN + y) * SPAN + x
end

local function fieldsPlace(entry)
    return entry.x, entry.y, entry.z
end

--- The place of an IsoObject, as PlaceTracker.nearest takes it.
function PlaceTracker.objectPlace(isoObject)
    return isoObject:getX(), isoObject:getY(), isoObject:getZ()
end

-- The squared distance from x, y, z to the place px, py, pz, each level counting as a square, and
-- the place's key.
local function measure(x, y, z, px, py, pz)
    local dx, dy, dz = px - x, py - y, pz - z
    return dx * dx + dy * dy + dz * dz, PlaceTracker.key(px, py, pz)
end

--- The nearest of `list` to x, y, z that `accepts(entry)` takes (every entry without it), or nil.
--- Of equally near ones the lower place (PlaceTracker.key) wins, so whoever asks picks the same
--- one. `placeOf(entry)` gives an entry's x, y, z; without it, its x, y and z fields.
function PlaceTracker.nearest(list, x, y, z, placeOf, accepts)
    placeOf = placeOf or fieldsPlace
    local best, bestDistance, bestKey
    for _, entry in ipairs(list) do
        if not accepts or accepts(entry) then
            local distance, key = measure(x, y, z, placeOf(entry))
            if not best or distance < bestDistance or (distance == bestDistance and key < bestKey) then
                best, bestDistance, bestKey = entry, distance, key
            end
        end
    end
    return best
end

--- Sorts `list` nearest first to x, y, z, in the order PlaceTracker.nearest picks.
function PlaceTracker.sortNearest(list, x, y, z, placeOf)
    placeOf = placeOf or fieldsPlace
    local distances, keys = {}, {}
    for _, entry in ipairs(list) do
        distances[entry], keys[entry] = measure(x, y, z, placeOf(entry))
    end
    table.sort(list, function(a, b)
        return distances[a] < distances[b] or (distances[a] == distances[b] and keys[a] < keys[b])
    end)
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
