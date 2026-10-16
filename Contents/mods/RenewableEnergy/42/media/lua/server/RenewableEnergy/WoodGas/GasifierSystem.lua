-- The gasifiers on the authority: the Global Object System that keeps them, building one, the pass
-- that runs them all, and the jobs players do at them.

if isClient() then return end

require "Map/SGlobalObjectSystem"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Fumes"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/WoodGas/GasifierJobs"
local GasifierObject = require "RenewableEnergy/WoodGas/GasifierObject"

RenewableEnergy = RenewableEnergy or {}
local Gasifier, GasifierJobs = RenewableEnergy.Gasifier, RenewableEnergy.GasifierJobs

local GasifierSystem = SGlobalObjectSystem:derive("RenewableEnergy_GasifierSystem")
RenewableEnergy.GasifierSystem = GasifierSystem

-- MapObjects keeps one function per sprite and priority.
local LOAD_PRIORITY = 6

function GasifierSystem:new()
    return SGlobalObjectSystem.new(self, Gasifier.SYSTEM_NAME)
end

function GasifierSystem:initSystem()
    Gasifier.serverSystem = self
    self.system:setObjectModDataKeys(GasifierObject.SAVED_FIELDS)
    self.system:setObjectSyncKeys({ "summary" })
end

-- The summary isn't saved; each gasifier gets it before any client connects.
function GasifierSystem:initLuaObjects()
    SGlobalObjectSystem.initLuaObjects(self)
    for i = 1, self:getLuaObjectCount() do
        local gasifier = self:getLuaObjectByIndex(i)
        gasifier.summary = gasifier:buildSummary()
    end
end

function GasifierSystem:isValidIsoObject(isoObject)
    return Gasifier.isGasifier(isoObject)
end

function GasifierSystem:newLuaObject(globalObject)
    return GasifierObject:new(self, globalObject)
end

function GasifierSystem:OnObjectAboutToBeRemoved(isoObject)
    if not Gasifier.isGasifier(isoObject) then return end
    local gasifier = self:getLuaObjectOnSquare(isoObject:getSquare())
    if not gasifier then return end
    RenewableEnergy.Fumes.set(gasifier:key(), isoObject:getSquare():getBuilding(), false)
    self:removeLuaObject(gasifier)
end

-- Building -------------------------------------------------------------------------------------

-- The build menu's OnCreate for every gasifier (scripts/RenewableEnergy/Entities.txt), on the
-- authority: the new tile becomes a gasifier, with its filter. The build adds it to the square
-- before this runs and sends it to the clients after.
function GasifierSystem.OnCreate(params)
    local thumpable = params.thumpable
    if thumpable and thumpable:getSquare() then
        GasifierSystem.instance:loadIsoObject(thumpable)
    end
end

-- Jobs ------------------------------------------------------------------------------------------

local function notBroken(item)
    return not item:isBroken()
end

-- Lighting takes one use of a match or lighter, as a campfire does.
local function useFireStarter(character)
    local item = character:getInventory():getFirstTagEvalRecurse(ItemTag.START_FIRE, notBroken)
    if item and instanceof(item, "DrainableComboItem") then
        item:UseAndSync()
    end
end

local function cleanOutAsh(character, gasifier)
    local count = math.floor(gasifier.ash / Gasifier.ASH_PER_ITEM)
    for _ = 1, count do
        Actions.addOrDropItem(character, instanceItem(Gasifier.WOOD_ASH))
    end
    gasifier.ash = gasifier.ash - count * Gasifier.ASH_PER_ITEM
end

--- Does `job` for `character` at the gasifier `isoObject`, on the authority, once the timed action
--- that does it has finished. Returns whether it was done.
function GasifierSystem.perform(character, job, isoObject)
    local gasifier = isoObject and Gasifier.recordOf(isoObject)
    if not gasifier then
        return false
    end
    -- Bring it up to now first, so the job works on what is there.
    gasifier:update()
    if GasifierJobs.refusal(character, job, gasifier:buildSummary()) then
        return false
    end
    if job == GasifierJobs.LIGHT then
        useFireStarter(character)
        if gasifier.fireKg <= 0 and not gasifier:stoke(Gasifier.hopperOf(isoObject)) then
            return false
        end
        gasifier.lit = true
        gasifier.outSince = nil
        gasifier.lastHour = getGameTime():getWorldAgeHours()
    elseif job == GasifierJobs.PUT_OUT then
        gasifier:goOut()
    elseif job == GasifierJobs.CLEAN_ASH then
        cleanOutAsh(character, gasifier)
    end
    gasifier:afterChange()
    return true
end

-- Map loading ---------------------------------------------------------------------------------

local function loadGasifier(isoObject)
    if Gasifier.isGasifier(isoObject) then
        GasifierSystem.instance:loadIsoObject(isoObject)
    end
end

for _, name in ipairs(Gasifier.sprites()) do
    MapObjects.OnLoadWithSprite(name, loadGasifier, LOAD_PRIORITY)
end

-- The pass ---------------------------------------------------------------------------------------

function GasifierSystem.updateAll()
    local self = GasifierSystem.instance
    for i = 1, self:getLuaObjectCount() do
        self:getLuaObjectByIndex(i):update()
    end
end

Events.EveryTenMinutes.Add(GasifierSystem.updateAll)

SGlobalObjectSystem.RegisterSystemClass(GasifierSystem)

return GasifierSystem
