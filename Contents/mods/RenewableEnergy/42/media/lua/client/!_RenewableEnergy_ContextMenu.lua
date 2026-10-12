-- Named to load before every other mod's client Lua, so the OnPreFillWorldObjectContextMenu hook
-- that takes the battery bank out of fetchVars.generator runs before other mods' hooks read it.
require "RenewableEnergy/UI/Menu"
