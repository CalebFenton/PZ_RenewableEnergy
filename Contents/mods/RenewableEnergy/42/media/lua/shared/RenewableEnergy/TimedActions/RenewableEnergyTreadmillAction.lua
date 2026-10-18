require "TimedActions/ISBaseTimedAction"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Treadmill"

-- Run on Treadmill: the character runs in place on a treadmill. On one wired to a bank the belt
-- turns its motor, and the run banks watt-hours; on an unwired one the motor turns the belt, on
-- power, which the run draws from start to end (Treadmill.startDrawing). A run lasts
-- Specs.treadmill.runMinutes and stopping early counts the share run. The authority settles it:
-- complete() a whole run, serverStop() (stop() in single player) part of one.
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

-- Whether the runner is on the treadmill, still wired or not as it was when the run began: an
-- unwired one wired meanwhile would draw power while its motor fed a bank.
local function running(self)
    local object = self.object
    if not (RenewableEnergy.onSquare(object) and RenewableEnergy.withinReach(self.character, object, REACH)) then
        return false
    end
    if self.wired then
        return Treadmill.isWiredTile(object)
    end
    return Treadmill.isTreadmill(object) and Treadmill.wiredHalf(object) == nil
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

-- A run on an unwired treadmill stops when its power goes out. The server never calls isValid(),
-- but the client's stop reaches it (serverStop).
function Action:isValid()
    return running(self) and self.character:getStats():get(CharacterStat.ENDURANCE) > GIVE_UP_ENDURANCE
        and (self.wired or Treadmill.isPowered(self.object))
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

-- How far the belt's top stands above the floor, in levels: the height of the belt's box in the
-- tiles' depth geometry (tileGeometry.txt) over the height of a level (TileDepthTexture).
-- A runner on the floor would have their feet drawn inside the belt.
local BELT_HEIGHT = 0.17 / 2.449

local function holdOnBelt(self)
    self.character:setZ(self.object:getSquare():getZ() + BELT_HEIGHT)
    -- Vanilla pulls anyone above the floor down every frame (IsoGameCharacter.updateFalling); the
    -- fall speed, left to build, would carry them to the floor between updates.
    self.character:setLastFallSpeed(0)
end

-- The authority's start of a run's draw on an unwired, powered treadmill, which a powering bank
-- bills until the run settles. Grid and generator power need only be there: the grid bills nothing,
-- and vanilla burns generator fuel only for an appliance's own consumption
-- (IsoGenerator.setSurroundingElectricity), which a treadmill doesn't have.
local function startDrawing(self)
    if not self.wired and Treadmill.isPowered(self.object) then
        Treadmill.startDrawing(self.object, self)
        self.drawing = true
    end
end

function Action:serverStart()
    startDrawing(self)
end

function Action:start()
    -- A run on a wired treadmill that feeds no bank banks nothing, and an unwired one won't go
    -- without power; single player says so before it starts. In multiplayer the authority's command
    -- refuses the first, and settle pays nothing for the second, which never drew.
    if not isClient() then
        if Treadmill.runRefusal(self.object) then
            self:forceStop()
            return
        end
        startDrawing(self)
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

-- The authority's side of `share` of a run: the bank's watt-hours, for a wired treadmill, and the
-- runner's sweat and training, none of it unless the bank takes the run or, unwired, the run drew
-- power. Its draw ends first, whatever comes of it. The server never calls isValid() and
-- NetTimedAction checks no distance, so it checks here, on every path that settles, that the runner
-- is at the treadmill.
local function settle(self, share)
    local drew = self.drawing
    Treadmill.stopDrawing(self.object, self)
    self.drawing = nil
    local hours = runHours() * math.max(0, math.min(1, share))
    if hours <= 0 or not running(self) then
        return false
    end
    local spec, character = Specs.treadmill, self.character
    if self.wired then
        if not PowerBank.perform(character, "runTreadmill", { source = PowerBank.positionOf(self.object), hours = hours }) then
            return false
        end
    elseif not drew then
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
    -- Whether this run feeds a bank, fixed for the run; the menu hands a wired treadmill's wired tile.
    o.wired = Treadmill.isWired(object)
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end
