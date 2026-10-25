-- Helpers that several of the mod's modules share; those any mod could use are cf_commonlib's.
--
-- RenewableEnergy is the mod's one global table. The other globals are the timed action classes
-- (RenewableEnergy*Action), which the game looks up by name. Every file that adds to the table
-- creates it first if no file has yet, so files may load in any order.

RenewableEnergy = RenewableEnergy or {}

-- Slack for float comparisons of kg, litres and m³, which sums and shares leave a hair off.
RenewableEnergy.EPSILON = 1e-4

--- Gives `container` the AcceptItemFunction `fnName` (a path from the global table, where
--- ItemContainer finds it) unless it has one. The filter is neither saved nor sent, so every side
--- sets it on its own copy whenever the object loads or is placed.
function RenewableEnergy.adoptContainer(container, fnName)
    if container and container:getAcceptItemFunction() == nil then
        container:setAcceptItemFunction(fnName)
    end
end

--- Whether the door part `partId` of `vehicle` leaves what it covers open: the door open, taken
--- off, or no such part or door at all.
function RenewableEnergy.isPartOpen(vehicle, partId)
    local part = vehicle:getPartById(partId)
    local door = part and part:getDoor()
    return not (door and part:getInventoryItem()) or door:isOpen()
end

--- Appends to `entries` (a new table when nil) a loot entry { weight, list } for each list of
--- each group { weight, lists } of `groups`, in order, and returns `entries`.
function RenewableEnergy.weightedEntries(groups, entries)
    entries = entries or {}
    for _, group in ipairs(groups) do
        for _, list in ipairs(group[2]) do
            table.insert(entries, { group[1], list })
        end
    end
    return entries
end

--- Action units per real second at normal speed, whatever the day length: an in-game minute is
--- Clock.unitsPerMinute() units and lasts minutesPerDay / 24 real seconds.
RenewableEnergy.UNITS_PER_SECOND = 48

--- Marks `holder` (an item or a placed object) under its modData `key` and, the first time it is
--- marked, gives `character` (if any) `xp` of `perk`: a job teaches only the first time it is done
--- on the thing. Returns whether this was the first time. Authority only; the caller sends a placed
--- object's modData on.
function RenewableEnergy.teachOnce(character, holder, key, perk, xp)
    local data = holder:getModData()
    if data[key] then
        return false
    end
    data[key] = true
    if character then
        addXp(character, perk, xp)
    end
    return true
end

--- Whether `object` is a vanilla generator: an IsoGenerator that isn't a battery bank, which is a
--- generator too (PowerBank.isBank).
function RenewableEnergy.isGenerator(object)
    return object ~= nil and instanceof(object, "IsoGenerator") and not RenewableEnergy.PowerBank.isBank(object)
end

-- Item ConditionMax by full type, read once from the item scripts.
local CONDITION_MAX = {}

--- The ConditionMax of items of `fullType`, as its item script gives it; 100 for a type with none.
function RenewableEnergy.conditionMaxOf(fullType)
    if not CONDITION_MAX[fullType] then
        local script = getScriptManager():FindItem(fullType)
        CONDITION_MAX[fullType] = script and script:getConditionMax() or 100
    end
    return CONDITION_MAX[fullType]
end

--- How the glass of a module of `fullType` at `condition` looks (Specs.crackLooks): nil whole,
--- "light" or "heavy" cracks. Every look of a module, a mount's tile or the arrow board's, asks
--- this, so they agree. The share is taken by division, which rounds a share that is exactly a
--- threshold to the threshold's own literal, as a product of the max wouldn't.
function RenewableEnergy.crackLookOf(fullType, condition)
    local looks = RenewableEnergy.Specs.crackLooks
    local share = condition / RenewableEnergy.conditionMaxOf(fullType)
    if share < looks.heavyBelow then
        return "heavy"
    elseif share < looks.lightBelow then
        return "light"
    end
    return nil
end

--- Calls `fn(square)` for every loaded square on level `z` within `radius` squares of x, y on each
--- axis, x, y included, until one call returns a value other than nil, which this returns.
function RenewableEnergy.eachSquareAround(x, y, z, radius, fn)
    for squareX = x - radius, x + radius do
        for squareY = y - radius, y + radius do
            local square = getSquare(squareX, squareY, z)
            local result = square and fn(square)
            if result ~= nil then
                return result
            end
        end
    end
    return nil
end

--- The step in x and y to the square on each side, by compass letter: north is up the map, -y.
RenewableEnergy.SIDE_STEPS = { N = { 0, -1 }, E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 } }

return RenewableEnergy
