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

--- Its tile is in the world, just placed or its chunk loaded: notes whether it stands indoors, where
--- its fumes fill the building.
function Object:loaded(isoObject)
    self.indoors = Fumes.buildingOf(isoObject:getSquare()) ~= nil
end

--- Says whether the object fills its building with fumes now (Fumes).
function Object:setFuming(isFuming)
    local isoObject = self:getIsoObject()
    Fumes.set(self:key(), isoObject and Fumes.buildingOf(isoObject:getSquare()), isFuming)
end

-- The system removes a record whose tile is picked up or destroyed, and one whose tile is found
-- gone when its chunk loads (SGlobalObjectSystem:OnChunkLoaded), when there is no tile to ask.
function Object:aboutToRemoveFromSystem()
    Fumes.set(self:key(), nil, false)
end

return ObjectSystem
