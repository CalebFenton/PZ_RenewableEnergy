require "TimedActions/ISBaseTimedAction"
require "Util/BuildingHelper"
---@class RenewableEnergy
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/Gadgets/SolarMaintainer"

-- Every hands-on job at a battery bank, a panel or a vehicle. In multiplayer the client runs
-- start() and perform(), and the server rebuilds the action from new()'s parameters and runs
-- complete(), which makes the change; single player runs both. The server finds the class by its
-- Type with a plain global lookup (NetTimedAction.parse), which is why this one class is a global
-- outside the RenewableEnergy table.
RenewableEnergyAction = ISBaseTimedAction:derive("RenewableEnergyAction")

local Action = RenewableEnergyAction

Action.CONNECT_SOURCE = "ConnectSource"
Action.DISCONNECT_SOURCE = "DisconnectSource"
Action.CLEAR_SNOW = "ClearSnow"
Action.TURN_ON = "TurnOn"
Action.TURN_OFF = "TurnOff"
Action.RESET_INVERTER = "ResetInverter"
Action.CONNECT_VEHICLE = "ConnectVehicle"
Action.DISCONNECT_VEHICLE = "DisconnectVehicle"
Action.ATTACH_MAINTAINER = "AttachMaintainer"
Action.DETACH_MAINTAINER = "DetachMaintainer"

-- What clears snow off a flat panel without scratching it: a broom sweeps, a snow shovel pushes.
Action.SNOW_TOOLS = { ["Base.Broom"] = true, ["Base.Broom_Twig"] = true, ["Base.SnowShovel"] = true }

-- An action advances by GameTime.getMultiplier() each tick (BaseAction.update), and in the same
-- tick the clock advances getMultiplier() / (2 * minutesPerDay) in-game minutes (GameTime.update),
-- so one in-game minute is 2 * minutesPerDay units at any frame rate or game speed.
function Action.unitsPerMinute()
    return 2 * getGameTime():getMinutesPerDay()
end

local function position(object)
    return { x = object:getX(), y = object:getY(), z = object:getZ() }
end

local function onSquare(object)
    return object ~= nil and object:getObjectIndex() ~= -1
end

local function statusOf(bank)
    return RenewableEnergy.PowerBank.getStatus(bank:getX(), bank:getY(), bank:getZ())
end

local function isBank(bank)
    return onSquare(bank) and RenewableEnergy.PowerBank.isBank(bank)
end

local function isSource(object)
    return onSquare(object) and RenewableEnergy.PowerBank.sourceKind(object) ~= nil
end

local function samePosition(a, b)
    return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y and a.z == b.z
end

function Action.connectedBank(source)
    return RenewableEnergy.PowerBank.bankOfSource(source:getX(), source:getY(), source:getZ())
end

function Action.bankInReach(source, bank)
    local here = position(bank)
    for _, reachable in ipairs(RenewableEnergy.PowerBank.banksInReach(source:getX(), source:getY(), source:getZ())) do
        if samePosition(reachable, here) then
            return true
        end
    end
    return false
end

function Action.isSnowTool(item)
    return item ~= nil and Action.SNOW_TOOLS[item:getFullType()] == true and not item:isBroken()
end

-- The server takes the very wire PowerBank.findVehicleWire finds, so the client asks the same.
function Action.hasVehicleWire(character)
    return RenewableEnergy.PowerBank.findVehicleWire(character) ~= nil
end

-- The status of the action's bank, or nil when there is no bank or no status yet.
local function bankStatus(self)
    if isBank(self.bank) then
        return statusOf(self.bank)
    end
end

-- Whether the job applies to the world as it is now. Both sides ask: the client to offer and
-- start the job, the server again in complete(). The server re-checks everything it is told too.
local CHECKS = {
    [Action.CONNECT_SOURCE] = function(self)
        return isSource(self.object) and isBank(self.bank) and Action.bankInReach(self.object, self.bank)
            and not samePosition(Action.connectedBank(self.object), position(self.bank))
    end,
    [Action.DISCONNECT_SOURCE] = function(self)
        return isSource(self.object) and Action.connectedBank(self.object) ~= nil
    end,
    [Action.CLEAR_SNOW] = function(self)
        return isSource(self.object) and RenewableEnergy.PowerBank.sourceKind(self.object) == "flat"
            and Action.isSnowTool(self.item) and self.character:isPrimaryHandItem(self.item)
    end,
    [Action.TURN_ON] = function(self)
        local status = bankStatus(self)
        return status ~= nil and not status.on
    end,
    [Action.TURN_OFF] = function(self)
        local status = bankStatus(self)
        return status ~= nil and status.on == true
    end,
    [Action.RESET_INVERTER] = function(self)
        local status = bankStatus(self)
        return status ~= nil and status.inverter.state == "tripped"
    end,
    [Action.CONNECT_VEHICLE] = function(self)
        local status = bankStatus(self)
        return status ~= nil and status.vehicle == nil and self.vehicle ~= nil
            and RenewableEnergy.PowerBank.vehicleInReach(position(self.bank), self.vehicle) and Action.hasVehicleWire(self.character)
    end,
    [Action.DISCONNECT_VEHICLE] = function(self)
        local status = bankStatus(self)
        return status ~= nil and status.vehicle ~= nil
    end,
    [Action.ATTACH_MAINTAINER] = function(self)
        return self.vehicle ~= nil and self.item ~= nil and self.item:getFullType() == RenewableEnergy.SolarMaintainer.ITEM
            and self.character:getInventory():containsRecursive(self.item) and RenewableEnergy.SolarMaintainer.canAttach(self.vehicle)
    end,
    [Action.DETACH_MAINTAINER] = function(self)
        return self.vehicle ~= nil and RenewableEnergy.SolarMaintainer.isAttached(self.vehicle)
    end,
}

function Action:canPerform()
    local check = CHECKS[self.mode]
    return check ~= nil and check(self)
end

-- The bank's command for each mode, run on the authority by PowerBank.perform.
local COMMANDS = {
    [Action.CONNECT_SOURCE] = function(self)
        return "connectSource", { bank = position(self.bank), source = position(self.object) }
    end,
    [Action.DISCONNECT_SOURCE] = function(self)
        return "disconnectSource", { source = position(self.object) }
    end,
    [Action.CLEAR_SNOW] = function(self)
        return "clearSnow", { source = position(self.object) }
    end,
    [Action.TURN_ON] = function(self)
        return "setBankOn", { bank = position(self.bank), on = true }
    end,
    [Action.TURN_OFF] = function(self)
        return "setBankOn", { bank = position(self.bank), on = false }
    end,
    [Action.RESET_INVERTER] = function(self)
        return "resetInverter", { bank = position(self.bank) }
    end,
    [Action.CONNECT_VEHICLE] = function(self)
        return "connectVehicle", { bank = position(self.bank), vehicle = self.vehicle:getId() }
    end,
    [Action.DISCONNECT_VEHICLE] = function(self)
        return "disconnectVehicle", { bank = position(self.bank) }
    end,
}

-- In-game minutes per job at Electricity 3; wiring goes faster with skill, the rest does not.
local MINUTES = {
    [Action.CLEAR_SNOW] = 5,
    [Action.TURN_ON] = 0.5,
    [Action.TURN_OFF] = 0.5,
    [Action.RESET_INVERTER] = 0.5,
    [Action.CONNECT_VEHICLE] = 3,
    [Action.DISCONNECT_VEHICLE] = 1,
    [Action.ATTACH_MAINTAINER] = 1,
    [Action.DETACH_MAINTAINER] = 1,
}

-- Full time at Electricity 3, about a third of it at 10, about a quarter longer at 0.
local function skillFactor(level)
    return 1 - 0.095 * (level - 3)
end

function Action:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    if self.mode == Action.CONNECT_SOURCE or self.mode == Action.DISCONNECT_SOURCE then
        local minutes = SandboxVars.RenewableEnergy.ConnectPanelMin * skillFactor(self.character:getPerkLevel(Perks.Electricity))
        if self.mode == Action.DISCONNECT_SOURCE then
            minutes = minutes / 2
        end
        return minutes * Action.unitsPerMinute()
    end
    return MINUTES[self.mode] * Action.unitsPerMinute()
end

function Action:target()
    return self.vehicle or self.object or self.bank
end

function Action:isValid()
    if self.item and not self.character:getInventory():containsRecursive(self.item) then
        return false
    end
    -- A multiplayer client's copy of the bank's status can lag behind the server's, which
    -- checks again in complete().
    return isClient() or self:canPerform()
end

function Action:waitToStart()
    self.character:faceThisObject(self:target())
    return self.character:shouldBeTurning()
end

function Action:update()
    self.character:faceThisObject(self:target())
    if self.mode == Action.CLEAR_SNOW then
        self.character:setMetabolicTarget(Metabolics.LightWork)
    end
end

function Action:start()
    if isClient() and self.item then
        -- Server syncs can replace the item objects while the action waits in the queue.
        self.item = self.character:getInventory():getItemById(self.item:getID())
    end
    if self.mode == Action.CLEAR_SNOW then
        if self.item and self.item:getType() == "SnowShovel" then
            self:setActionAnim(BuildingHelper.getShovelAnim(self.item))
            self.sound = self.character:playSound("Shoveling")
        else
            self:setActionAnim("Rake")
        end
        return
    end
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", self.vehicle and "Mid" or "Low")
    self.character:reportEvent("EventLootItem")
    if self.mode == Action.CONNECT_SOURCE or self.mode == Action.CONNECT_VEHICLE or self.mode == Action.ATTACH_MAINTAINER then
        self.sound = self.character:playSound("GeneratorConnect")
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
    if self.mode == Action.TURN_ON or self.mode == Action.TURN_OFF or self.mode == Action.RESET_INVERTER then
        self.character:playSound("LightSwitch")
    end
    ISInventoryPage.renderDirty = true
    ISBaseTimedAction.perform(self)
end

-- The server never calls isValid(), so this checks the action again.
function Action:complete()
    if not self:canPerform() then
        return false
    end
    if self.mode == Action.ATTACH_MAINTAINER then
        return RenewableEnergy.SolarMaintainer.attach(self.character, self.vehicle, self.item)
    elseif self.mode == Action.DETACH_MAINTAINER then
        return RenewableEnergy.SolarMaintainer.detach(self.character, self.vehicle)
    end
    local command, args = COMMANDS[self.mode](self)
    local ok = RenewableEnergy.PowerBank.perform(self.character, command, args)
    return ok == true
end

-- Parameter names must match the fields set on `o`: the multiplayer server rebuilds the action by
-- passing those fields to new() in parameter order (NetTimedAction). `object` is the panel, `bank`
-- the bank's IsoGenerator, `item` the snow tool or the maintainer; unused ones are nil.
function Action:new(character, mode, object, bank, vehicle, item)
    local o = ISBaseTimedAction.new(self, character)
    o.mode = mode
    o.object = object
    o.bank = bank
    o.vehicle = vehicle
    o.item = item
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end
