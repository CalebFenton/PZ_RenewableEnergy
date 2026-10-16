require "TimedActions/ISBaseTimedAction"
require "Util/BuildingHelper"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/Recipes"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/Gadgets/SolarGardenLight"

-- Every hands-on job at a battery bank, a panel, a garden light or a vehicle. In multiplayer the
-- client runs start() and perform(), and the server rebuilds the action from new()'s parameters
-- and runs complete(), which makes the change; single player runs both. The server finds the
-- class by its Type with a plain global lookup (NetTimedAction.parse), which is why this one class
-- is a global outside the RenewableEnergy table.
RenewableEnergyAction = ISBaseTimedAction:derive("RenewableEnergyAction")

local Action = RenewableEnergyAction
local PowerBank = RenewableEnergy.PowerBank
local positionOf, samePosition = PowerBank.positionOf, PowerBank.samePosition

Action.CONNECT_SOURCE = "ConnectSource"
Action.DISCONNECT_SOURCE = "DisconnectSource"
Action.CLEAR_SNOW = "ClearSnow"
Action.TURN_ON = "TurnOn"
Action.TURN_OFF = "TurnOff"
Action.ATTACH_MAINTAINER = "AttachMaintainer"
Action.DETACH_MAINTAINER = "DetachMaintainer"
Action.WIRE_IN = "WireIn"
Action.UNWIRE = "Unwire"
Action.REPAIR_PART = "RepairPart"
Action.RENAME = "Rename"
Action.REPAIR_PANEL = "RepairPanel"
Action.REMOVE_BULB = "RemoveBulb"
Action.ADD_BULB = "AddBulb"
Action.CUT_PADLOCK = "CutPadlock"
Action.BOARD_ON = "BoardOn"
Action.BOARD_OFF = "BoardOff"
Action.BRAKE = "Brake"
Action.RELEASE_BRAKE = "ReleaseBrake"

-- Jobs on the bank's wiring or a cracked panel, which need light to see by.
local NEEDS_LIGHT = { [Action.WIRE_IN] = true, [Action.UNWIRE] = true, [Action.REPAIR_PART] = true, [Action.REPAIR_PANEL] = true }
-- Jobs on a part already in the bank's container rather than in the character's inventory.
local PART_IN_BANK = { [Action.UNWIRE] = true, [Action.REPAIR_PART] = true }

-- What clears snow off a flat panel without scratching it: a broom sweeps, a snow shovel pushes.
Action.SNOW_TOOLS = { ["Base.Broom"] = true, ["Base.Broom_Twig"] = true, ["Base.SnowShovel"] = true }

-- An action advances by GameTime.getMultiplier() each tick (BaseAction.update), and in the same
-- tick the clock advances getMultiplier() / (2 * minutesPerDay) in-game minutes (GameTime.update),
-- so one in-game minute is 2 * minutesPerDay units at any frame rate or game speed.
function Action.unitsPerMinute()
    return 2 * getGameTime():getMinutesPerDay()
end

-- At normal speed an action advances this many units each real second, whatever the day length:
-- an in-game minute is 2 * minutesPerDay units and lasts minutesPerDay / 24 real seconds.
local UNITS_PER_SECOND = 48

local function onSquare(object)
    return object ~= nil and object:getObjectIndex() ~= -1
end

local function isBank(bank)
    return onSquare(bank) and PowerBank.isBank(bank)
end

local function isSource(object)
    return onSquare(object) and PowerBank.sourceKind(object) ~= nil
end

local function isWindCharger(object)
    return isSource(object) and PowerBank.isWind(PowerBank.sourceKind(object))
end

local function isGardenLight(object)
    return onSquare(object) and RenewableEnergy.SolarGardenLight.isLight(object)
end

--- The bank the panel `source` is connected to, as { x, y, z }, or nil.
function Action.connectedBank(source)
    return PowerBank.bankOfSource(source:getX(), source:getY(), source:getZ())
end

--- Whether the panel `source` may be connected to `bank`.
function Action.bankInReach(source, bank)
    local here = positionOf(bank)
    for _, reachable in ipairs(PowerBank.banksInReach(source:getX(), source:getY(), source:getZ())) do
        if samePosition(reachable, here) then
            return true
        end
    end
    return false
end

function Action.isSnowTool(item)
    return item ~= nil and Action.SNOW_TOOLS[item:getFullType()] == true and not item:isBroken()
end

function Action.isBoltCutters(item)
    return item ~= nil and item:hasTag(ItemTag.BOLT_CUTTERS) and not item:isBroken()
end

-- The summary of the action's bank, or nil when there is no bank or no summary yet.
local function bankSummary(self)
    if isBank(self.bank) then
        return PowerBank.summaryOf(self.bank)
    end
end

-- Whether the action's item is where its job needs it: in the bank for a part already wired
-- in, else anywhere in the character's inventory.
local function holdsItem(self)
    if PART_IN_BANK[self.mode] then
        local container = isBank(self.bank) and self.bank:getContainer()
        return container and container:contains(self.item) or false
    end
    return self.character:getInventory():containsRecursive(self.item)
end

local function inWorld(vehicle)
    return vehicle ~= nil and not vehicle:isRemovedFromWorld()
end

-- What each job needs from moment to moment, cheap enough for isValid to ask every tick: its
-- target still in the world and its item still where the job needs it. These are what another
-- player or the world can take away mid-job, and the character's own copy of the world shows
-- them, so a multiplayer client asks them too.
local KEEPS = {
    [Action.CONNECT_SOURCE] = function(self)
        return isSource(self.object) and isBank(self.bank)
    end,
    [Action.DISCONNECT_SOURCE] = function(self)
        return isSource(self.object)
    end,
    [Action.CLEAR_SNOW] = function(self)
        return isSource(self.object) and PowerBank.sourceKind(self.object) == "flat"
            and Action.isSnowTool(self.item) and self.character:isPrimaryHandItem(self.item)
    end,
    [Action.TURN_ON] = function(self)
        return isBank(self.bank)
    end,
    [Action.TURN_OFF] = function(self)
        return isBank(self.bank)
    end,
    [Action.ATTACH_MAINTAINER] = function(self)
        return inWorld(self.vehicle) and self.item ~= nil and self.item:getFullType() == RenewableEnergy.SolarMaintainer.ITEM
            and holdsItem(self)
    end,
    [Action.DETACH_MAINTAINER] = function(self)
        return inWorld(self.vehicle)
    end,
    [Action.WIRE_IN] = function(self)
        return isBank(self.bank) and self.item ~= nil and holdsItem(self)
    end,
    [Action.UNWIRE] = function(self)
        return self.item ~= nil and holdsItem(self) and PowerBank.partKind(self.item:getFullType()) ~= nil
    end,
    [Action.REPAIR_PART] = function(self)
        return self.item ~= nil and holdsItem(self)
    end,
    [Action.RENAME] = function(self)
        return isBank(self.bank) and type(self.bankName) == "string"
    end,
    [Action.REPAIR_PANEL] = function(self)
        local part = inWorld(self.vehicle) and self.vehicle:getPartById(self.partId)
        return part and part:getInventoryItem() ~= nil or false
    end,
    [Action.REMOVE_BULB] = function(self)
        return isGardenLight(self.object)
    end,
    [Action.ADD_BULB] = function(self)
        return isGardenLight(self.object) and RenewableEnergy.SolarGardenLight.isBulb(self.item) and holdsItem(self)
    end,
    [Action.CUT_PADLOCK] = function(self)
        return inWorld(self.vehicle) and Action.isBoltCutters(self.item) and self.character:isPrimaryHandItem(self.item)
    end,
    [Action.BOARD_ON] = function(self)
        return inWorld(self.vehicle)
    end,
    [Action.BOARD_OFF] = function(self)
        return inWorld(self.vehicle)
    end,
    [Action.BRAKE] = function(self)
        return isWindCharger(self.object)
    end,
    [Action.RELEASE_BRAKE] = function(self)
        return isWindCharger(self.object)
    end,
}

-- The rest of each job's rules: the state of its target and its bank, which a multiplayer
-- client's copy can show late, and the checks too dear for every tick, which walk through every
-- bank (the banks a panel reaches, the one it is wired to) or the whole inventory (the refusals).
-- Single player asks them before the job starts, and the authority again in complete().
local CHECKS = {
    [Action.CONNECT_SOURCE] = function(self)
        return Action.bankInReach(self.object, self.bank)
            and not samePosition(Action.connectedBank(self.object), positionOf(self.bank))
    end,
    [Action.DISCONNECT_SOURCE] = function(self)
        return Action.connectedBank(self.object) ~= nil
    end,
    [Action.TURN_ON] = function(self)
        local summary = bankSummary(self)
        return summary ~= nil and not summary.on
    end,
    [Action.TURN_OFF] = function(self)
        local summary = bankSummary(self)
        return summary ~= nil and summary.on == true
    end,
    [Action.ATTACH_MAINTAINER] = function(self)
        return RenewableEnergy.SolarMaintainer.canAttach(self.vehicle)
    end,
    [Action.DETACH_MAINTAINER] = function(self)
        return RenewableEnergy.SolarMaintainer.isAttached(self.vehicle)
    end,
    [Action.WIRE_IN] = function(self)
        return PowerBank.wiringRefusal(self.character, self.bank, self.item) == nil
    end,
    [Action.REPAIR_PART] = function(self)
        return PowerBank.repairRefusal(self.character, self.item) == nil
    end,
    [Action.REPAIR_PANEL] = function(self)
        local ArrowBoard = RenewableEnergy.ArrowBoard
        return ArrowBoard ~= nil and ArrowBoard.repairablePanel(self.vehicle, self.partId) ~= nil
            and RenewableEnergy.Recipes.panelRepairRefusal(self.character) == nil
    end,
    [Action.REMOVE_BULB] = function(self)
        return RenewableEnergy.SolarGardenLight.getBulb(self.object) ~= nil
    end,
    [Action.ADD_BULB] = function(self)
        return RenewableEnergy.SolarGardenLight.getBulb(self.object) == nil
    end,
    [Action.CUT_PADLOCK] = function(self)
        local ArrowBoard = RenewableEnergy.ArrowBoard
        local lid = ArrowBoard ~= nil and ArrowBoard.isTrailer(self.vehicle) and self.vehicle:getPartById(ArrowBoard.LID)
        return lid and ArrowBoard.isPadlocked(lid) or false
    end,
    [Action.BOARD_ON] = function(self)
        local ArrowBoard = RenewableEnergy.ArrowBoard
        return ArrowBoard ~= nil and ArrowBoard.canSwitch(self.vehicle, true)
    end,
    [Action.BOARD_OFF] = function(self)
        local ArrowBoard = RenewableEnergy.ArrowBoard
        return ArrowBoard ~= nil and ArrowBoard.canSwitch(self.vehicle, false)
    end,
    [Action.BRAKE] = function(self)
        return not PowerBank.isBraked(self.object)
    end,
    [Action.RELEASE_BRAKE] = function(self)
        return PowerBank.isBraked(self.object)
    end,
}

--- Whether the job applies to the world as it is now, every rule of it.
function Action:canPerform()
    local keeps, check = KEEPS[self.mode], CHECKS[self.mode]
    return keeps ~= nil and keeps(self) and (check == nil or check(self))
end

-- How far from the middle of the target's square, on each axis in squares, a character may work
-- on a bank, a panel or a garden light: what luautils.walkAdj counts as already there, the square
-- getCorrectSquareForWall moves a wall's target to, and a couple more for the character's drift
-- and a multiplayer client's lag. A vehicle job gets as much past the vehicle's body, whose areas
-- the menu walks the character to (ISPathFindAction.pathToVehicleArea).
local REACH = 4.6

-- Whether the character stands where the menu would have walked them for the job.
local function withinReach(character, target)
    if instanceof(target, "BaseVehicle") then
        local extents = target:getScript():getExtents()
        local reach = math.max(extents:x(), extents:z()) / 2 + REACH
        return IsoUtils.DistanceTo(character:getX(), character:getY(), target:getX(), target:getY()) <= reach
            and math.abs(character:getZ() - target:getZ()) < 1
    end
    local square = target:getSquare()
    return square ~= nil and math.abs(character:getX() - (square:getX() + 0.5)) <= REACH
        and math.abs(character:getY() - (square:getY() + 0.5)) <= REACH
        and math.abs(character:getZ() - square:getZ()) < 1
end

-- The bank's command for each mode, run on the authority by PowerBank.perform.
local COMMANDS = {
    [Action.CONNECT_SOURCE] = function(self)
        return "connectSource", { bank = positionOf(self.bank), source = positionOf(self.object) }
    end,
    [Action.DISCONNECT_SOURCE] = function(self)
        return "disconnectSource", { source = positionOf(self.object) }
    end,
    [Action.CLEAR_SNOW] = function(self)
        return "clearSnow", { source = positionOf(self.object) }
    end,
    [Action.TURN_ON] = function(self)
        return "setBankOn", { bank = positionOf(self.bank), on = true }
    end,
    [Action.TURN_OFF] = function(self)
        return "setBankOn", { bank = positionOf(self.bank), on = false }
    end,
    [Action.WIRE_IN] = function(self)
        return "wireIn", { bank = positionOf(self.bank), itemId = self.item:getID() }
    end,
    [Action.UNWIRE] = function(self)
        return "unwire", { bank = positionOf(self.bank), itemId = self.item:getID() }
    end,
    [Action.REPAIR_PART] = function(self)
        return "repairPart", { bank = positionOf(self.bank), itemId = self.item:getID() }
    end,
    [Action.RENAME] = function(self)
        return "rename", { bank = positionOf(self.bank), name = self.bankName }
    end,
    [Action.BRAKE] = function(self)
        return "setBrake", { source = positionOf(self.object), braked = true }
    end,
    [Action.RELEASE_BRAKE] = function(self)
        return "setBrake", { source = positionOf(self.object), braked = false }
    end,
}

-- In-game minutes of the jobs that skill doesn't speed up.
local MINUTES = {
    [Action.CLEAR_SNOW] = 5,
    [Action.TURN_ON] = 0.5,
    [Action.TURN_OFF] = 0.5,
    [Action.BOARD_ON] = 0.5,
    [Action.BOARD_OFF] = 0.5,
    [Action.ATTACH_MAINTAINER] = 1,
    [Action.DETACH_MAINTAINER] = 1,
    [Action.RENAME] = 0.5,
    -- As long as vanilla's for a lamp's bulb at the default day length (ISLightActions).
    [Action.REMOVE_BULB] = 1,
    [Action.ADD_BULB] = 1,
    -- A lever or pin at the foot of the mast.
    [Action.BRAKE] = 1,
    [Action.RELEASE_BRAKE] = 1,
}

-- The share of its full time a job takes at an Electricity level: all of it at level 3, less
-- above it and more below, in a straight line.
local function skillFactor(level)
    return 1 - 0.095 * (level - 3)
end

-- Wiring a part in takes PowerBank.wiringFor's seconds at Electricity 0, less with skill;
-- unwiring takes half that. A part that is gone takes no time, and complete() refuses it.
local function wiringUnits(self)
    local wiring = self.item and PowerBank.wiringFor(self.item:getFullType())
    if not wiring then
        return 1
    end
    local level = self.character:getPerkLevel(Perks.Electricity)
    local seconds = wiring.seconds * skillFactor(level) / skillFactor(0)
    if self.mode == Action.UNWIRE then
        seconds = seconds / 2
    end
    return seconds * UNITS_PER_SECOND
end

function Action:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    local level = self.character:getPerkLevel(Perks.Electricity)
    if self.mode == Action.CONNECT_SOURCE or self.mode == Action.DISCONNECT_SOURCE then
        local minutes = SandboxVars.RenewableEnergy.ConnectPanelMin * skillFactor(level)
        if self.mode == Action.DISCONNECT_SOURCE then
            minutes = minutes / 2
        end
        return minutes * Action.unitsPerMinute()
    elseif self.mode == Action.WIRE_IN or self.mode == Action.UNWIRE then
        return wiringUnits(self)
    elseif self.mode == Action.REPAIR_PART then
        -- As vanilla's ISFixGenerator.
        return 150 - level * 3
    elseif self.mode == Action.REPAIR_PANEL then
        -- As the crafting window times Repair Cracked Module (ISHandcraftAction).
        return RenewableEnergy.Recipes.moduleRepairRecipe():getTime(self.character) * 5
    elseif self.mode == Action.CUT_PADLOCK then
        -- A squeeze of the handles, far quicker than unbolting the lid.
        return 100
    end
    return MINUTES[self.mode] * Action.unitsPerMinute()
end

function Action:target()
    return self.vehicle or self.object or self.bank
end

function Action:isValid()
    -- In multiplayer the server's complete() moves the item (into the bank, out of it, onto the
    -- vehicle) while this client's action is still finishing; failing then would stop the action
    -- and empty the player's queue (ISBaseTimedAction.stop). Vanilla stops checking there too
    -- (ISInstallVehiclePart.isValid).
    if self.action and self.action:getJobDelta() >= 0.9 then
        return true
    end
    -- The game asks every tick (IsoGameCharacter.update), so this asks only what can change
    -- mid-job and is cheap to see. The rest waits for start() and complete().
    local keeps = KEEPS[self.mode]
    if not (keeps and keeps(self)) then
        return false
    end
    -- The server can't tell whether a remote player stands in the dark
    -- (IsoPlayer.tooDarkToRead), so the player's own side checks the light.
    if NEEDS_LIGHT[self.mode] and self.character:tooDarkToRead() then
        HaloTextHelper.addBadText(self.character, getText("Tooltip_RenewableEnergy_TooDark"))
        return false
    end
    return withinReach(self.character, self:target())
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
    -- Single player checks every rule once here, and again in complete(), as vanilla's crafting
    -- checks its recipe in start() and leaves isValid to whether the bench is still in use
    -- (ISHandcraftAction). A multiplayer client leaves them to the server's complete().
    if not isClient() and not self:canPerform() then
        self:forceStop()
        return
    end
    if isClient() and self.item then
        -- Server syncs can replace the item objects while the action waits in the queue. A bank
        -- gone meanwhile leaves no item, and isValid then stops the job.
        local container = self.character:getInventory()
        if PART_IN_BANK[self.mode] then
            container = isBank(self.bank) and self.bank:getContainer()
        end
        self.item = container and container:getItemWithIDRecursiv(self.item:getID()) or nil
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
    if self.mode == Action.CUT_PADLOCK then
        -- As vanilla works on a vehicle part at waist height (ISUninstallVehiclePart).
        self:setActionAnim("VehicleWorkOnMid")
        return
    end
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", self.vehicle and "Mid" or "Low")
    self.character:reportEvent("EventLootItem")
    if self.mode == Action.CONNECT_SOURCE or self.mode == Action.ATTACH_MAINTAINER
        or self.mode == Action.WIRE_IN or self.mode == Action.UNWIRE then
        self.sound = self.character:playSound("GeneratorConnect")
    elseif self.mode == Action.REPAIR_PART or self.mode == Action.REPAIR_PANEL then
        self.sound = self.character:playSound("GeneratorRepair")
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
    if self.mode == Action.TURN_ON or self.mode == Action.TURN_OFF or self.mode == Action.BOARD_ON
        or self.mode == Action.BOARD_OFF then
        self.character:playSound("LightSwitch")
    end
    if self.mode == Action.CUT_PADLOCK then
        -- The sound of a lock giving way, as when a character forces a locked window
        -- (OpenWindowState).
        self.character:playSound("BreakLockOnWindow")
    end
    ISInventoryPage.renderDirty = true
    ISBaseTimedAction.perform(self)
end

-- Cut Padlock, on the authority: the lid unlocked, its lock broken. Vanilla saves and sends a
-- broken lock with the door, never locks it again (BaseVehicle.canLockDoor), and keeps it on the
-- lid's item while the lid is off (Vehicles.UninstallComplete.Door). The cutters wear as vanilla's
-- cutting recipes wear them (MayDegradeLight in CutUpTire, CraftRecipeData.processKeepInputItem),
-- and a pair that breaks leaves the hands as a broken weapon does (ISDestroyStuffAction).
local function cutPadlock(self)
    local lid = self.vehicle:getPartById(RenewableEnergy.ArrowBoard.LID)
    local door = lid:getDoor()
    door:setLocked(false)
    door:setLockBroken(true)
    self.vehicle:transmitPartDoor(lid)
    if self.item:damageCheck(0, 3) then
        ItemUtils.checkWeapon(self.character)
    end
    return true
end

-- The server never calls isValid(), so this checks the action again. NetTimedAction checks no
-- distance, so the server also makes sure the character is at the job, which a modified client
-- could otherwise send for any bank or vehicle in the world.
function Action:complete()
    if not self:canPerform() then
        return false
    end
    if isServer() and not withinReach(self.character, self:target()) then
        return false
    end
    if self.mode == Action.ATTACH_MAINTAINER then
        return RenewableEnergy.SolarMaintainer.attach(self.character, self.vehicle, self.item)
    elseif self.mode == Action.DETACH_MAINTAINER then
        return RenewableEnergy.SolarMaintainer.detach(self.character, self.vehicle)
    elseif self.mode == Action.REPAIR_PANEL then
        return RenewableEnergy.ArrowBoard.repairPanel(self.character, self.vehicle, self.partId)
    elseif self.mode == Action.REMOVE_BULB then
        return RenewableEnergy.SolarGardenLight.removeBulb(self.character, self.object)
    elseif self.mode == Action.ADD_BULB then
        return RenewableEnergy.SolarGardenLight.addBulb(self.character, self.object, self.item)
    elseif self.mode == Action.CUT_PADLOCK then
        return cutPadlock(self)
    elseif self.mode == Action.BOARD_ON or self.mode == Action.BOARD_OFF then
        return RenewableEnergy.ArrowBoard.setSwitch(self.vehicle, self.mode == Action.BOARD_ON)
    end
    local command, args = COMMANDS[self.mode](self)
    local ok = PowerBank.perform(self.character, command, args)
    return ok == true
end

-- Parameter names must match the fields set on `o`: the multiplayer server rebuilds the action by
-- passing those fields to new() in parameter order (NetTimedAction). `object` is the panel or the
-- garden light, `bank` the bank's IsoGenerator, `item` the tool or part the job uses, `bankName`
-- the bank's new name, `partId` the vehicle part worked on; unused ones are nil. The name can't
-- be a field called `name`, which NetTimedAction reads as the action's own name.
function Action:new(character, mode, object, bank, vehicle, item, bankName, partId)
    local o = ISBaseTimedAction.new(self, character)
    o.mode = mode
    o.object = object
    o.bank = bank
    o.vehicle = vehicle
    o.item = item
    o.bankName = bankName
    o.partId = partId
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end
