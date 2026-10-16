require "TimedActions/ISBaseTimedAction"
require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"

-- Run on Treadmill: the character runs in place on a treadmill wired to a bank, the belt turning
-- its motor. A run lasts Specs.treadmill.runMinutes and stopping early counts the share run. The
-- authority settles it: complete() a whole run, serverStop() (stop() in single player) part of one.
-- A global, as the server finds the class by its Type (NetTimedAction.parse).
RenewableEnergyTreadmillAction = ISBaseTimedAction:derive("RenewableEnergyTreadmillAction")

local Action = RenewableEnergyTreadmillAction
local Specs, PowerBank = RenewableEnergy.Specs, RenewableEnergy.PowerBank

-- Endurance below which the runner gives up, as vanilla stops a sprint (IsoPlayer, exhausted).
local GIVE_UP_ENDURANCE = 0.1

-- How far from the middle of the treadmill's square, on each axis, the runner may stand: on it,
-- with a little for drift and a client's lag.
local REACH = 1.6

local function isWiredTreadmill(object)
    return object ~= nil and object:getObjectIndex() ~= -1 and PowerBank.sourceKind(object) == "treadmill"
end

local function onTreadmill(character, object)
    local square = object:getSquare()
    return square ~= nil and math.abs(character:getX() - (square:getX() + 0.5)) <= REACH
        and math.abs(character:getY() - (square:getY() + 0.5)) <= REACH
        and math.abs(character:getZ() - square:getZ()) < 1
end

local function runHours()
    return Specs.treadmill.runMinutes / 60
end

function Action:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return Specs.treadmill.runMinutes * RenewableEnergyAction.unitsPerMinute()
end

function Action:isValid()
    return isWiredTreadmill(self.object) and onTreadmill(self.character, self.object)
        and self.character:getStats():get(CharacterStat.ENDURANCE) > GIVE_UP_ENDURANCE
end

-- How far past the middle of the rear tile, toward the console, the runner stands.
local TOWARD_CONSOLE = 0.3

-- The way the belt runs the runner, from the treadmill's tile.
function Action:facing()
    local _, facing = PowerBank.sourceKind(self.object)
    return IsoDirections[facing] or self.character:getDir()
end

-- Where the runner stands: on the rear tile, a little toward the console, whichever of the two
-- tiles is the wired one.
function Action:runSpot()
    local rear, _, step = PowerBank.treadmillEnds(self.object)
    return rear.x + 0.5 + step[1] * TOWARD_CONSOLE, rear.y + 0.5 + step[2] * TOWARD_CONSOLE
end

function Action:start()
    -- The runner steps onto the belt, and back off where they were when the run ends.
    self.fromX, self.fromY = self.character:getX(), self.character:getY()
    local x, y = self:runSpot()
    self.character:setX(x)
    self.character:setY(y)
    self.character:setDir(self:facing())
    self:setActionAnim("RenewableEnergyTreadmill")
    -- The run animation's root motion would carry the runner off the belt.
    self.character:setDeferredMovementEnabled(false)
end

function Action:update()
    self.character:setDir(self:facing())
    self.character:setMetabolicTarget(Metabolics.Running10kmh)
end

local function stepOff(self)
    self.character:setDeferredMovementEnabled(true)
    if self.fromX then
        self.character:setX(self.fromX)
        self.character:setY(self.fromY)
    end
end

-- The authority's side of `share` of a run: the bank's watt-hours and the runner's sweat and
-- training.
local function settle(self, share)
    local hours = runHours() * math.max(0, math.min(1, share))
    if hours <= 0 or not isWiredTreadmill(self.object) then
        return
    end
    local spec, character = Specs.treadmill, self.character
    PowerBank.perform(character, "runTreadmill", { source = PowerBank.positionOf(self.object), hours = hours })
    local stats = character:getStats()
    stats:remove(CharacterStat.ENDURANCE, spec.endurancePerHour * hours)
    stats:add(CharacterStat.THIRST, spec.thirstPerHour * hours)
    if isServer() then
        syncPlayerStats(character, SyncPlayerStatsPacket.getBitMaskForStat(CharacterStat.ENDURANCE)
            + SyncPlayerStatsPacket.getBitMaskForStat(CharacterStat.THIRST))
    end
    for perk, xp in pairs(spec.xpPerHour) do
        addXp(character, Perks[perk], xp * hours)
    end
end

function Action:stop()
    stepOff(self)
    if not isClient() then
        settle(self, self:getJobDelta())
    end
    ISBaseTimedAction.stop(self)
end

function Action:serverStop()
    settle(self, self.netAction:getProgress())
end

function Action:perform()
    stepOff(self)
    ISBaseTimedAction.perform(self)
end

-- The server never calls isValid() and NetTimedAction checks no distance, so it checks the
-- runner is at the treadmill. Stepping off puts them back beside it, still within REACH.
function Action:complete()
    if isServer() and not (isWiredTreadmill(self.object) and onTreadmill(self.character, self.object)) then
        return false
    end
    settle(self, 1)
    return true
end

-- Parameter names match the fields set on `o`: the multiplayer server rebuilds the action by
-- passing them to new() in order (NetTimedAction).
function Action:new(character, object)
    local o = ISBaseTimedAction.new(self, character)
    o.object = object
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end
