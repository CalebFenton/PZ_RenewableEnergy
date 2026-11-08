-- The base of the records of the mod's Global Object System features with tiers (digesters,
-- gasifiers), on cf_commonlib's ObjectSystem.Object, with what the mod's session-only services ask
-- of them. Each feature's system is cf_commonlib's ObjectSystem.define of its declared owner.

if isClient() then return end

local Utilities = require "RenewableEnergy/Utilities"
local Fumes = require "RenewableEnergy/Fumes"
local LibObjectSystem = require "cf_commonlib/ObjectSystem"

local ObjectSystem = {}

--- The base of the mod's records (cf_commonlib's ObjectSystem.Object). Saves keep its class name.
local Object = LibObjectSystem.Object:derive(Utilities.CLASS_PREFIX .. "Object")
ObjectSystem.Object = Object

--- What the record goes by in session-only services (Stink, Fumes).
function Object:key()
    return self.luaSystem.owner.feature.kind .. ":" .. self.x .. "," .. self.y .. "," .. self.z
end

function Object:tierSpec()
    return self.luaSystem.owner.TIERS[self.tier]
end

--- Its tile is in the world, just placed or its chunk loaded.
function Object:loaded(isoObject)
    self:lookIndoors(isoObject)
end

--- Looks whether the object, `isoObject` if given, stands indoors, where its fumes fill the
--- building (Fumes.buildingOf): as it loads, and before each change it tells. A room a player
--- built is a building only once the game has made one of it, which a loading game does after its
--- first chunks load (IsoWorld.init), and never on a dedicated server; a wall knocked down ends it.
function Object:lookIndoors(isoObject)
    isoObject = isoObject or self:getIsoObject()
    if isoObject then
        self.indoors = Fumes.buildingOf(isoObject:getSquare()) ~= nil
    end
end

--- Says whether the object fills its building with fumes now (Fumes).
function Object:setFuming(isFuming)
    local isoObject = self:getIsoObject()
    Fumes.set(self:key(), isoObject and isoObject:getSquare(), isFuming)
end

-- The system removes a record whose tile is picked up or destroyed, and one whose tile is found
-- gone when its chunk loads (SGlobalObjectSystem:OnChunkLoaded), when there is no tile to ask.
function Object:aboutToRemoveFromSystem()
    Fumes.set(self:key(), nil, false)
end

return ObjectSystem
