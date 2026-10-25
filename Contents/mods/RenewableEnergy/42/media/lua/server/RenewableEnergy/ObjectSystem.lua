-- The mod's features kept in a Global Object System on the authority (digesters, gasifiers, banks),
-- defined through cf_commonlib's ObjectSystem with the mod's own names, tiles and pass cap, and the
-- base of their records with what the mod's session-only services ask of them.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Fumes"
local LibObjectSystem = require "cf_commonlib/ObjectSystem"

RenewableEnergy = RenewableEnergy or {}
local ObjectSystem = {}
RenewableEnergy.ObjectSystem = ObjectSystem

local Sprites, Fumes = RenewableEnergy.Sprites, RenewableEnergy.Fumes

-- Saves keep the system and record classes by their names, which start with this.
local PREFIX = "RenewableEnergy_"

-- Cap on one pass (a save loaded after the clock jumped). These objects run while unloaded, so time
-- away counts as digesting or burning.
local LONGEST_PASS = 24 * 7

--- The base of the mod's records (cf_commonlib's ObjectSystem.Object).
local Object = LibObjectSystem.Object:derive(PREFIX .. "Object")
ObjectSystem.Object = Object

--- What the record goes by in session-only services (Stink, Fumes).
function Object:key()
    return self.luaSystem.kind .. ":" .. self.x .. "," .. self.y .. "," .. self.z
end

function Object:tierSpec()
    return self.luaSystem.owner.TIERS[self.tier]
end

--- Says whether the object fills its building with fumes now (RenewableEnergy.Fumes).
function Object:setFuming(isFuming)
    local isoObject = self:getIsoObject()
    Fumes.set(self:key(), isoObject and Fumes.buildingOf(isoObject:getSquare()), isFuming)
end

-- The system removes a record whose tile is picked up or destroyed, and one whose tile is found
-- gone when its chunk loads (SGlobalObjectSystem:OnChunkLoaded), when there is no tile to ask.
function Object:aboutToRemoveFromSystem()
    Fumes.set(self:key(), nil, false)
end

-- `spec` with the mod's prefix, for cf_commonlib's ObjectSystem.
local function prefixed(spec)
    return {
        prefix = PREFIX, name = spec.name, owner = spec.owner, Object = spec.Object, isObject = spec.isObject,
    }
end

--- A system class RenewableEnergy_<name>System (cf_commonlib's ObjectSystem.deriveSystem), not
--- registered. `spec`: name, owner, Object, isObject.
function ObjectSystem.deriveSystem(spec)
    return LibObjectSystem.deriveSystem(prefixed(spec))
end

--- Defines and registers a feature's system (cf_commonlib's ObjectSystem.define), loaded with the
--- tiles of its Sprites kind and given its record as the build menu's OnCreate builds one
--- (scripts/RenewableEnergy/Entities.txt). `spec`: name (the class is
--- RenewableEnergy_<name>System), kind, owner (its shared module: SYSTEM_NAME, TIERS, and the
--- accessors of GlobalObjects.addAccessors), Object (its record class, an ObjectSystem.Object),
--- isObject. Returns the class.
function ObjectSystem.define(spec)
    local full = prefixed(spec)
    full.sprites = Sprites.namesOf(spec.kind)
    full.loadPriority = Sprites.LOAD_PRIORITY
    full.longestPass = LONGEST_PASS
    full.loadOnCreate = true
    local System = LibObjectSystem.define(full)
    System.kind = spec.kind
    return System
end

return ObjectSystem
