-- Helpers that several of the mod's modules share; those any mod could use are cf_commonlib's.
--
-- Every module ends `return X`, and a file takes what it uses with `local X = require "..."`,
-- this table as `local RenewableEnergy = require "RenewableEnergy/Utilities"`. A file that adds
-- to another module (Bank's parts, the *Server.lua files, ArrowBoard's) returns that module.
-- RenewableEnergy is the mod's one global table: a module goes in it only when something finds it
-- by name: a script's or container's Lua path, the dev mod, or a file that can't require it,
-- because the module requires that file or is server Lua, which loads after shared and client
-- Lua. Such a file reads the table when the function runs, never as it loads. The other globals
-- are the timed action classes, which the game finds by name.

RenewableEnergy = RenewableEnergy or {}

-- Specs requires this file, so the helpers below find it in the table as they run.

-- Slack for float comparisons of kg, litres and m³, which sums and shares leave a hair off.
RenewableEnergy.EPSILON = 1e-4

-- Saves keep the mod's Global Object System classes by names that start with this.
RenewableEnergy.CLASS_PREFIX = "RenewableEnergy_"

--- Whether the door part `partId` of `vehicle` leaves what it covers open: the door open, taken
--- off, or no such part or door at all.
function RenewableEnergy.isPartOpen(vehicle, partId)
    local part = vehicle:getPartById(partId)
    local door = part and part:getDoor()
    return not (door and part:getInventoryItem()) or door:isOpen()
end

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

--- The step in x and y to the square on each side, by compass letter: north is up the map, -y.
RenewableEnergy.SIDE_STEPS = { N = { 0, -1 }, E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 } }

return RenewableEnergy
