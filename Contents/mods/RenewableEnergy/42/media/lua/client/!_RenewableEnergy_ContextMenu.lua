-- Named to load before every other mod's client Lua, so the OnPreFillWorldObjectContextMenu hook
-- that takes the battery bank out of fetchVars.generator runs before other mods' hooks read it.

require "ISUI/ISWorldObjectContextMenu"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/PowerBank/PowerBank"

local PowerBank = RenewableEnergy.PowerBank

-- The generator vanilla would have offered its menu on had the bank not been there.
--
-- fetchVars.generator holds only the last IsoGenerator the fetch walked, and a bank is one.
-- Clearing the slot would also hide the menu of a real generator beside the bank, where a backup
-- generator stands. This walks the objects in the fetch's order (each entry, then its square once;
-- ISWorldObjectContextMenuLogic.fetch) so the generator handed back is the one vanilla would pick.
local function otherGenerator(worldobjects)
    local found, seen = nil, {}
    local function consider(object)
        if RenewableEnergy.isGenerator(object) then
            found = object
        end
    end
    for _, object in ipairs(worldobjects or {}) do
        consider(object)
        local square = object:getSquare()
        if square and not seen[square] then
            seen[square] = true
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do
                consider(objects:get(i))
            end
        end
    end
    return found
end

-- Runs before vanilla reads fetchVars, so vanilla offers no generator options (fuel, plug in) for
-- the bank itself.
local function onPreFill(playerNum, context, worldobjects, test)
    local generator = ISWorldObjectContextMenu.fetchVars.generator
    if generator and PowerBank.isBank(generator) then
        ISWorldObjectContextMenu.fetchVars.generator = otherGenerator(worldobjects)
    end
end

Events.OnPreFillWorldObjectContextMenu.Add(onPreFill)
