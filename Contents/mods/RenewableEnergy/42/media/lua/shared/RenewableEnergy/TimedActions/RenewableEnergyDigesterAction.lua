require "TimedActions/ISBaseTimedAction"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/DigesterJobs"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"

-- Every hands-on job at a digester (RenewableEnergy.DigesterJobs). In multiplayer the client runs
-- start() and perform() and the server rebuilds the action from new()'s parameters and runs
-- complete(), which does the job; single player runs both. A global, as the server finds the class
-- by its Type (NetTimedAction.parse).
RenewableEnergyDigesterAction = ISBaseTimedAction:derive("RenewableEnergyDigesterAction")

local Action = RenewableEnergyDigesterAction
local Digester, DigesterJobs = RenewableEnergy.Digester, RenewableEnergy.DigesterJobs

-- How far from the middle of the digester's square, on each axis in squares, the character may work
-- at it: what luautils.walkAdj counts as there, and a little for drift and a client's lag.
local REACH = 2.6

local function onSquare(object)
    return object ~= nil and object:getObjectIndex() ~= -1 and Digester.isDigester(object)
end

local function withinReach(character, object)
    local square = object:getSquare()
    return square ~= nil and math.abs(character:getX() - (square:getX() + 0.5)) <= REACH
        and math.abs(character:getY() - (square:getY() + 0.5)) <= REACH
        and math.abs(character:getZ() - square:getZ()) < 1
end

function Action:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    local summary = self.digester and Digester.currentSummary(self.digester)
    return DigesterJobs.minutesFor(self.job, summary, self.item) * RenewableEnergyAction.unitsPerMinute()
end

function Action:isValid()
    if self.action and self.action:getJobDelta() >= 0.9 then
        return true
    end
    if not onSquare(self.digester) then
        return false
    end
    if self.item and not self.character:getInventory():containsRecursive(self.item) then
        return false
    end
    return withinReach(self.character, self.digester)
end

function Action:waitToStart()
    self.character:faceThisObject(self.digester)
    return self.character:shouldBeTurning()
end

function Action:update()
    self.character:faceThisObject(self.digester)
    if self.job == DigesterJobs.TAKE_SLUDGE or self.job == DigesterJobs.UPGRADE or self.job == DigesterJobs.FILL_PUMP then
        self.character:setMetabolicTarget(Metabolics.HeavyWork)
    end
end

function Action:start()
    if not isClient() and DigesterJobs.refusal(self.character, self.job, Digester.currentSummary(self.digester), self.item) then
        self:forceStop()
        return
    end
    if isClient() and self.item then
        self.item = self.character:getInventory():getItemWithIDRecursiv(self.item:getID())
    end
    if self.job == DigesterJobs.UPGRADE then
        self:setActionAnim(CharacterActionAnims.Build)
        self.sound = self.character:playSound("Hammering")
    elseif self.job == DigesterJobs.SEW_TARP then
        self:setActionAnim("SewingCloth")
    elseif self.job == DigesterJobs.FILL_PUMP then
        -- Vanilla has no pump stroke; a tire pump is worked kneeling at a wheel.
        self:setActionAnim("VehicleWorkOnTire")
    else
        self:setActionAnim("Loot")
        self.character:SetVariable("LootPosition", "Mid")
    end
end

function Action:stop()
    if self.sound then
        self.character:stopOrTriggerSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function Action:perform()
    if self.sound then
        self.character:stopOrTriggerSound(self.sound)
    end
    ISInventoryPage.renderDirty = true
    ISBaseTimedAction.perform(self)
end

-- The server never calls isValid(), so this checks the job again, and that the character is at the
-- digester, which NetTimedAction doesn't check.
function Action:complete()
    if not onSquare(self.digester) or (isServer() and not withinReach(self.character, self.digester)) then
        return false
    end
    return RenewableEnergy.DigesterSystem.perform(self.character, self.job, self.digester, self.item)
end

-- Parameter names match the fields: the multiplayer server rebuilds the action by passing them to
-- new() in order (NetTimedAction). `digester` is the digester's tile, `item` the bag Take Sludge
-- fills; nil for the other jobs.
function Action:new(character, job, digester, item)
    local o = ISBaseTimedAction.new(self, character)
    o.job = job
    o.digester = digester
    o.item = item
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end
