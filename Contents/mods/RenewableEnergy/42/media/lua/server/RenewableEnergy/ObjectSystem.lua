-- The authority's side of features kept in a Global Object System (digesters, gasifiers): a system
-- per feature that saves each record with the world, runs every record each ten minutes loaded or
-- not, and sends clients its summary; a base for the records; and their side of the jobs players
-- do at them (GasJobs.perform).

if isClient() then return end

require "Map/SGlobalObjectSystem"
require "Map/SGlobalObject"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Fumes"

RenewableEnergy = RenewableEnergy or {}
local ObjectSystem = {}
RenewableEnergy.ObjectSystem = ObjectSystem

local Sprites, Fumes = RenewableEnergy.Sprites, RenewableEnergy.Fumes

-- Cap on one pass (a save loaded after the clock jumped). These objects run while unloaded, so time
-- away counts as digesting or burning.
local LONGEST_PASS = 24 * 7

--- The base of a feature's records. A record is its global object's table, so the fields its
--- class's SAVED_FIELDS names are saved with the world. A class defines advance(hours), what the
--- time does to it; afterChange(), which shows and tells what changed; and buildSummary(), what
--- every client keeps of it.
local Object = SGlobalObject:derive("RenewableEnergy_Object")
ObjectSystem.Object = Object

--- What the record goes by in session-only services (Stink, Fumes).
function Object:key()
    return self.luaSystem.kind .. ":" .. self.x .. "," .. self.y .. "," .. self.z
end

function Object:tierSpec()
    return self.luaSystem.owner.TIERS[self.tier]
end

--- Brings the record up to now: what the game hours since it last caught up did to it.
function Object:catchUp()
    local now = getGameTime():getWorldAgeHours()
    local hours = math.min(LONGEST_PASS, now - (self.lastHour or now))
    self.lastHour = now
    self:advance(hours)
end

--- Brings the record up to now, then shows and tells what changed.
function Object:update()
    self:catchUp()
    self:afterChange()
end

--- Sends the clients the summary, if it changed.
function Object:sendSummary()
    local summary = self:buildSummary()
    if not RenewableEnergy.sameValue(summary, self.summary) then
        self.summary = summary
        self:updateOnClient()
    end
end

--- Says whether the object fills its building with fumes now (RenewableEnergy.Fumes).
function Object:setFuming(isFuming)
    local isoObject = self:getIsoObject()
    Fumes.set(self:key(), isoObject and isoObject:getSquare():getBuilding(), isFuming)
end

-- The system removes a record whose tile is picked up or destroyed, and one whose tile is found
-- gone when its chunk loads (SGlobalObjectSystem:OnChunkLoaded), when there is no tile to ask.
function Object:aboutToRemoveFromSystem()
    Fumes.set(self:key(), nil, false)
end

--- Defines and registers a feature's system. `spec`: name (the class is RenewableEnergy_<name>System),
--- kind (its tiles' Sprites kind), owner (its shared module: SYSTEM_NAME, TIERS, and the
--- accessors of GlobalObjects.addAccessors), Object (its record class), isObject(isoObject).
--- Returns the class, whose System.OnCreate(params) is the build menu's for its tiles.
function ObjectSystem.define(spec)
    local System = SGlobalObjectSystem:derive("RenewableEnergy_" .. spec.name .. "System")
    System.kind, System.owner = spec.kind, spec.owner

    function System:new()
        return SGlobalObjectSystem.new(self, spec.owner.SYSTEM_NAME)
    end

    function System:initSystem()
        spec.owner.serverSystem = self
        self.system:setObjectModDataKeys(spec.Object.SAVED_FIELDS)
        self.system:setObjectSyncKeys({ "summary" })
    end

    -- The summary isn't saved; each record gets it before any client connects.
    function System:initLuaObjects()
        SGlobalObjectSystem.initLuaObjects(self)
        for i = 1, self:getLuaObjectCount() do
            local record = self:getLuaObjectByIndex(i)
            record.summary = record:buildSummary()
        end
    end

    function System:isValidIsoObject(isoObject)
        return spec.isObject(isoObject)
    end

    function System:newLuaObject(globalObject)
        return spec.Object:new(self, globalObject)
    end

    -- The build menu's OnCreate (scripts/RenewableEnergy/Entities.txt), on the authority: the new
    -- tile gets its record. The build adds it to the square before this runs and sends it to the
    -- clients after.
    function System.OnCreate(params)
        local thumpable = params.thumpable
        if thumpable and thumpable:getSquare() then
            System.instance:loadIsoObject(thumpable)
        end
    end

    -- Every record, loaded or not, each ten minutes.
    local function updateAll()
        local self = System.instance
        for i = 1, self:getLuaObjectCount() do
            self:getLuaObjectByIndex(i):update()
        end
    end

    local function load(isoObject)
        if spec.isObject(isoObject) then
            System.instance:loadIsoObject(isoObject)
        end
    end
    for _, name in ipairs(Sprites.namesOf(spec.kind)) do
        MapObjects.OnLoadWithSprite(name, load, Sprites.LOAD_PRIORITY)
    end
    Events.EveryTenMinutes.Add(updateAll)
    SGlobalObjectSystem.RegisterSystemClass(System)
    return System
end

--- The authority's side of the jobs at a feature's tiles (a site of GasJobs.perform), whose
--- records are `owner`'s: each job works on the record of the tile worked at, brought up to now
--- first, and `DO[job](character, record, row, isoObject, with)` does it, returning whether it was
--- done. A tile without a record has nothing for a job to work on.
function ObjectSystem.jobSite(owner, DO)
    return {
        open = function(isoObject)
            local record = owner.recordOf(isoObject)
            if record then
                record:catchUp()
            end
            return record
        end,
        act = function(character, job, record, row, isoObject, with)
            return record ~= nil and DO[job](character, record, row, isoObject, with)
        end,
        tell = function(record)
            if record then
                record:afterChange()
            end
        end,
    }
end

return ObjectSystem
