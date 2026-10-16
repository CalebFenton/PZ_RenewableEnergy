-- The digesters on the authority: the Global Object System that keeps them, building one, the
-- pass that runs them all, and the jobs players do at them.

if isClient() then return end

require "Map/SGlobalObjectSystem"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/DigesterJobs"
require "RenewableEnergy/Biogas/Stink"
local DigesterObject = require "RenewableEnergy/Biogas/DigesterObject"

RenewableEnergy = RenewableEnergy or {}
local Digester, DigesterJobs, Stink = RenewableEnergy.Digester, RenewableEnergy.DigesterJobs, RenewableEnergy.Stink

local DigesterSystem = SGlobalObjectSystem:derive("RenewableEnergy_DigesterSystem")
RenewableEnergy.DigesterSystem = DigesterSystem

-- MapObjects keeps one function per sprite and priority.
local LOAD_PRIORITY = 6

function DigesterSystem:new()
    return SGlobalObjectSystem.new(self, Digester.SYSTEM_NAME)
end

function DigesterSystem:initSystem()
    Digester.serverSystem = self
    self.system:setObjectModDataKeys(DigesterObject.SAVED_FIELDS)
    self.system:setObjectSyncKeys({ "summary" })
end

-- The summary isn't saved; each digester gets it before any client connects, and its stink, which
-- lasts only the session, from its first pass.
function DigesterSystem:initLuaObjects()
    SGlobalObjectSystem.initLuaObjects(self)
    for i = 1, self:getLuaObjectCount() do
        local digester = self:getLuaObjectByIndex(i)
        digester.summary = digester:buildSummary()
    end
end

function DigesterSystem:isValidIsoObject(isoObject)
    return Digester.isDigester(isoObject)
end

function DigesterSystem:newLuaObject(globalObject)
    return DigesterObject:new(self, globalObject)
end

function DigesterSystem:OnObjectAboutToBeRemoved(isoObject)
    if not Digester.isDigester(isoObject) then return end
    local digester = self:getLuaObjectOnSquare(isoObject:getSquare())
    if not digester then return end
    Stink.set(digester:key(), digester.x, digester.y, digester.z, 0)
    if digester.madeToxic then
        local building = isoObject:getSquare():getBuilding()
        digester.madeToxic = nil
        if building and not self:buildingNeedsFumes(building, digester) then
            building:setToxic(false)
        end
    end
    self:removeLuaObject(digester)
end

--- Whether a digester other than `except` fills `building` with fumes.
function DigesterSystem:buildingNeedsFumes(building, except)
    for i = 1, self:getLuaObjectCount() do
        local digester = self:getLuaObjectByIndex(i)
        if digester ~= except and digester.madeToxic then
            local square = digester:getSquare()
            if square and square:getBuilding() == building then
                return true
            end
        end
    end
    return false
end

--- The digester at `position` ({ x, y, z }), or nil.
function DigesterSystem.at(position)
    local self = Digester.serverSystem
    if not (self and type(position) == "table" and position.x) then
        return nil
    end
    return self:getLuaObjectAt(position.x, position.y, position.z)
end

-- Building -------------------------------------------------------------------------------------

-- The build menu's OnCreate for every digester (scripts/RenewableEnergy/Entities.txt), on the
-- authority: the new tile becomes a digester. The build adds it to the square before this runs
-- and sends it to the clients after.
function DigesterSystem.OnCreate(params)
    local thumpable = params.thumpable
    if thumpable and thumpable:getSquare() then
        DigesterSystem.instance:loadIsoObject(thumpable)
    end
end

-- Jobs ------------------------------------------------------------------------------------------

--- Does `job` for `character` at the digester `isoObject`, on the authority, once the timed action
--- that does it has finished. Returns whether it was done.
function DigesterSystem.perform(character, job, isoObject, item)
    local digester = isoObject and Digester.recordOf(isoObject)
    if not digester or DigesterJobs.refusal(character, job, digester.summary or digester:buildSummary(), item) then
        return false
    end
    -- Bring the digester up to now first, so the job works on what is there.
    digester:update()
    local done = DigesterJobs.apply(character, job, digester, isoObject, item)
    if done then
        digester:afterChange()
    end
    return done
end

-- Map loading ---------------------------------------------------------------------------------

local function loadDigester(isoObject)
    if Digester.isDigester(isoObject) then
        DigesterSystem.instance:loadIsoObject(isoObject)
    end
end

for _, name in ipairs(Digester.sprites()) do
    MapObjects.OnLoadWithSprite(name, loadDigester, LOAD_PRIORITY)
end

-- The pass ---------------------------------------------------------------------------------------

function DigesterSystem.updateAll()
    local self = DigesterSystem.instance
    for i = 1, self:getLuaObjectCount() do
        self:getLuaObjectByIndex(i):update()
    end
end

Events.EveryTenMinutes.Add(DigesterSystem.updateAll)

SGlobalObjectSystem.RegisterSystemClass(DigesterSystem)

return DigesterSystem
