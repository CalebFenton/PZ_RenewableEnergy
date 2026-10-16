require "TimedActions/ISBaseTimedAction"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Treadmill"

-- Run on Treadmill: the character runs in place on a treadmill wired to a bank, the belt turning
-- its motor. A run lasts Specs.treadmill.runMinutes and stopping early counts the share run. The
-- authority settles it: complete() a whole run, serverStop() (stop() in single player) part of one.
-- A global, as the server finds the class by its Type (NetTimedAction.parse).
RenewableEnergyTreadmillAction = ISBaseTimedAction:derive("RenewableEnergyTreadmillAction")

local Action = RenewableEnergyTreadmillAction
local Specs, Sprites = RenewableEnergy.Specs, RenewableEnergy.Sprites
local PowerBank, Treadmill = RenewableEnergy.PowerBank, RenewableEnergy.Treadmill

-- Endurance below which the runner gives up, as vanilla stops a sprint (IsoPlayer, exhausted).
local GIVE_UP_ENDURANCE = 0.1

-- How far from the middle of the treadmill's square, on each axis, the runner may stand: on it,
-- with a little for drift and a client's lag. Stepping off puts them back beside it, still within.
local REACH = 1.6

-- Whether the runner is on the wired treadmill.
local function running(self)
    return RenewableEnergy.onSquare(self.object) and Treadmill.isWiredTile(self.object)
        and RenewableEnergy.withinReach(self.character, self.object, REACH)
end

local function runHours()
    return Specs.treadmill.runMinutes / 60
end

function Action:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return Specs.treadmill.runMinutes * RenewableEnergy.unitsPerMinute()
end

function Action:isValid()
    return running(self) and self.character:getStats():get(CharacterStat.ENDURANCE) > GIVE_UP_ENDURANCE
end

-- How far past the middle of the rear tile, toward the console, the runner stands.
local TOWARD_CONSOLE = 0.3

-- The way the belt runs the runner, from the treadmill's tile.
local function facing(self)
    local _, way = Sprites.kindOf(Sprites.nameOf(self.object))
    return IsoDirections[way] or self.character:getDir()
end

-- Where the runner stands: on the rear tile, a little toward the console, whichever of the two
-- tiles is the wired one.
local function runSpot(self)
    local rear, _, step = Treadmill.ends(self.object)
    return rear.x + 0.5 + step[1] * TOWARD_CONSOLE, rear.y + 0.5 + step[2] * TOWARD_CONSOLE
end

-- How far the belt's top stands above the floor, in levels: the belt's box in the tiles' depth
-- geometry (tileGeometry.txt) reaches 0.17 of the 2.449 units a level stands (TileDepthTexture).
-- A runner on the floor would have their feet drawn inside the belt.
local BELT_HEIGHT = 0.17 / 2.449

local function holdOnBelt(self)
    self.character:setZ(self.object:getSquare():getZ() + BELT_HEIGHT)
    -- Vanilla pulls anyone above the floor down every frame (IsoGameCharacter.updateFalling); the
    -- fall speed, left to build, would carry them to the floor between updates.
    self.character:setLastFallSpeed(0)
end

function Action:start()
    -- A run on a treadmill that feeds no bank banks nothing; single player says so before it
    -- starts, and the authority's command refuses it in multiplayer.
    if not isClient() and Treadmill.runRefusal(self.object) then
        self:forceStop()
        return
    end
    -- The runner steps onto the belt, and back off where they were when the run ends.
    self.fromX, self.fromY = self.character:getX(), self.character:getY()
    local x, y = runSpot(self)
    self.character:setX(x)
    self.character:setY(y)
    holdOnBelt(self)
    self.character:setDir(facing(self))
    self:setActionAnim("RenewableEnergyTreadmill")
    -- The run animation's root motion would carry the runner off the belt.
    self.character:setDeferredMovementEnabled(false)
end

function Action:update()
    self.character:setDir(facing(self))
    holdOnBelt(self)
    self.character:setMetabolicTarget(Metabolics.Running10kmh)
end

local function stepOff(self)
    self.character:setDeferredMovementEnabled(true)
    if self.fromX then
        self.character:setX(self.fromX)
        self.character:setY(self.fromY)
        self.character:setZ(self.object:getSquare():getZ())
    end
end

-- The authority's side of `share` of a run: the bank's watt-hours and the runner's sweat and
-- training, none of it unless the bank takes the run. The server never calls isValid() and
-- NetTimedAction checks no distance, so it checks here, on every path that settles, that the runner
-- is at the treadmill.
local function settle(self, share)
    local hours = runHours() * math.max(0, math.min(1, share))
    if hours <= 0 or not running(self) then
        return false
    end
    local spec, character = Specs.treadmill, self.character
    if not PowerBank.perform(character, "runTreadmill", { source = PowerBank.positionOf(self.object), hours = hours }) then
        return false
    end
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
    return true
end

function Action:stop()
    -- Settled before the runner steps off, while still on the belt.
    if not isClient() then
        settle(self, self:getJobDelta())
    end
    stepOff(self)
    ISBaseTimedAction.stop(self)
end

function Action:serverStop()
    settle(self, self.netAction:getProgress())
end

function Action:perform()
    stepOff(self)
    ISBaseTimedAction.perform(self)
end

function Action:complete()
    return settle(self, 1)
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
