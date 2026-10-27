-- Places in the world as numbers, and the nearest of several: every choice between equally near
-- places breaks the tie the same way, so whoever asks picks the same one.

local Places = {}

-- World squares lie well under this in x and y, so a place key stays unique and exact in a double.
local SPAN = 1e6

--- The place x, y, z as one number: string keys cost far more time and memory per lookup in Kahlua.
function Places.key(x, y, z)
    return (z * SPAN + y) * SPAN + x
end

local function fieldsPlace(entry)
    return entry.x, entry.y, entry.z
end

--- The place of an IsoObject, as Places.nearest takes it.
function Places.objectPlace(isoObject)
    return isoObject:getX(), isoObject:getY(), isoObject:getZ()
end

-- The squared distance from x, y, z to the place px, py, pz, each level counting as a square, and
-- the place's key.
local function measure(x, y, z, px, py, pz)
    local dx, dy, dz = px - x, py - y, pz - z
    return dx * dx + dy * dy + dz * dz, Places.key(px, py, pz)
end

--- The nearest of `list` to x, y, z that `accepts(entry)` takes (every entry without it), or nil.
--- Of equally near ones the lower place (Places.key) wins. `placeOf(entry)` gives an entry's x, y,
--- z; without it, its x, y and z fields.
function Places.nearest(list, x, y, z, placeOf, accepts)
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

--- Sorts `list` nearest first to x, y, z, in the order Places.nearest picks.
function Places.sortNearest(list, x, y, z, placeOf)
    placeOf = placeOf or fieldsPlace
    local distances, keys = {}, {}
    for _, entry in ipairs(list) do
        distances[entry], keys[entry] = measure(x, y, z, placeOf(entry))
    end
    table.sort(list, function(a, b)
        return distances[a] < distances[b] or (distances[a] == distances[b] and keys[a] < keys[b])
    end)
end

return Places
