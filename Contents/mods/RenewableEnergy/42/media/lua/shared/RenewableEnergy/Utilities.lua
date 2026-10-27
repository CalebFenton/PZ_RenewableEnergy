-- Helpers that several of the mod's modules share; those any mod could use are cf_commonlib's.
--
-- Every module ends `return X`, and a file takes what it uses with `local X = require "..."`. A
-- file that adds to another module (Bank's parts, the *Server.lua files, ArrowBoard's) returns that
-- module. Server Lua loads after shared and client Lua, and only on the authority, so shared and
-- client code requires a server module inside the function that uses it, never as it loads.
--
-- The global table RenewableEnergy holds only what the game finds by a name in a script: OnCreate,
-- OnTest and OnIsValid paths, vehicle script functions and container AcceptItemFunctions. A module
-- named so registers itself there. The other globals are the timed action classes, which the game
-- also finds by name.

local Utilities = {}

-- Slack for float comparisons of kg, litres and m³, which sums and shares leave a hair off.
Utilities.EPSILON = 1e-4

-- Saves keep the mod's Global Object System classes by names that start with this.
Utilities.CLASS_PREFIX = "RenewableEnergy_"

--- Marks `holder` (an item or a placed object) under its modData `key` and, the first time it is
--- marked, gives `character` (if any) `xp` of `perk`: a job teaches only the first time it is done
--- on the thing. Returns whether this was the first time. Authority only; the caller sends a placed
--- object's modData on.
function Utilities.teachOnce(character, holder, key, perk, xp)
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

return Utilities
