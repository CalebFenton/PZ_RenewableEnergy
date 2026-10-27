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

-- Slack for float comparisons of kg, litres and m³, which sums and shares leave a hair off.
RenewableEnergy.EPSILON = 1e-4

-- Saves keep the mod's Global Object System classes by names that start with this.
RenewableEnergy.CLASS_PREFIX = "RenewableEnergy_"

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

--- The step in x and y to the square on each side, by compass letter: north is up the map, -y.
RenewableEnergy.SIDE_STEPS = { N = { 0, -1 }, E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 } }

return RenewableEnergy
