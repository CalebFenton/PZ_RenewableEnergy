require "TimedActions/ISBaseTimedAction"
require "Util/BuildingHelper"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Wind"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/PowerBank/Treadmill"
require "RenewableEnergy/Recipes"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/Gadgets/SolarGardenLight"

-- Every hands-on job at a battery bank, a source, a garden light or a vehicle. In multiplayer the
-- client runs start() and perform(), and the server rebuilds the action from new()'s parameters
-- and runs complete(), which makes the change; single player runs both. The server finds the
-- class by its Type with a plain global lookup (NetTimedAction.parse), which is why the class is a
-- global outside the RenewableEnergy table.
RenewableEnergyAction = ISBaseTimedAction:derive("RenewableEnergyAction")

local Action = RenewableEnergyAction
local Specs, Wind = RenewableEnergy.Specs, RenewableEnergy.Wind
local PowerBank, Sources, Treadmill = RenewableEnergy.PowerBank, RenewableEnergy.Sources, RenewableEnergy.Treadmill
local positionOf, onSquare = PowerBank.positionOf, RenewableEnergy.onSquare

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
Action.WIRE_TREADMILL = "WireTreadmill"
Action.UNWIRE_TREADMILL = "UnwireTreadmill"
Action.REPLACE_BLADES = "ReplaceBlades"
Action.CONNECT_BANK = "ConnectBank"
Action.DISCONNECT_BANK = "DisconnectBank"

-- What clears snow off a panel without scratching it: a broom sweeps, a snow shovel pushes.
local SNOW_TOOLS = { ["Base.Broom"] = true, ["Base.Broom_Twig"] = true, ["Base.SnowShovel"] = true }

-- Action units per real second at normal speed, whatever the day length: an in-game minute is
-- 2 * minutesPerDay units and lasts minutesPerDay / 24 real seconds.
local UNITS_PER_SECOND = 48

-- How far from the middle of the target's square, on each axis, a character may work: what
-- luautils.walkAdj and getCorrectSquareForWall leave as "there", plus slack for drift and client lag.
-- A vehicle job measures past the vehicle's body (ISPathFindAction.pathToVehicleArea).
local REACH = 4.6

function Action.isSnowTool(item)
    return item ~= nil and SNOW_TOOLS[item:getFullType()] == true and RenewableEnergy.notBroken(item)
end

function Action.isBoltCutters(item)
    return item ~= nil and item:hasTag(ItemTag.BOLT_CUTTERS) and RenewableEnergy.notBroken(item)
end

local function isBank(bank)
    return onSquare(bank) and PowerBank.isBank(bank)
end

local function isSource(object)
    return onSquare(object) and Sources.kindOf(object) ~= nil
end

local function isWindCharger(object)
    return onSquare(object) and Wind.isCharger(object)
end

local function isGardenLight(object)
    return onSquare(object) and RenewableEnergy.SolarGardenLight.isLight(object)
end

local function inWorld(vehicle)
    return vehicle ~= nil and not vehicle:isRemovedFromWorld()
end

-- The summary of the action's bank, or nil when there is no bank or no summary yet.
local function bankSummary(self)
    if isBank(self.bank) then
        return PowerBank.summaryOf(self.bank)
    end
end

-- The share of its full time a job takes at an Electricity level, falling in a straight line
-- with skill.
local function skillFactor(level)
    return 1 - 0.095 * (level - 3)
end

local function electricity(self)
    return self.character:getPerkLevel(Perks.Electricity)
end

-- Units a wiring job of `wiring` (as Specs.wiring's) takes: its seconds at Electricity 0, less with
-- skill, times `share`. A part that is gone takes no time, and complete() refuses it.
local function wiringUnits(self, wiring, share)
    if not wiring then
        return 1
    end
    return wiring.seconds * skillFactor(electricity(self)) / skillFactor(0) * (share or 1) * UNITS_PER_SECOND
end

local function partWiring(self)
    return self.item and PowerBank.wiringFor(self.item:getFullType())
end

local function connectMinutes(self)
    return SandboxVars.RenewableEnergy.ConnectPanelMin * skillFactor(electricity(self))
end

local function arrowBoard()
    return RenewableEnergy.ArrowBoard
end

local JOBS

-- Whether the action's item is where its job needs it: in the bank for a part already wired
-- in, else anywhere in the character's inventory.
local function holdsItem(self)
    if JOBS[self.mode].partInBank then
        local container = isBank(self.bank) and self.bank:getContainer()
        return container and container:contains(self.item) or false
    end
    return self.character:getInventory():containsRecursive(self.item)
end

-- Every job, by mode:
-- - keeps(self): what the job needs from moment to moment, cheap enough for isValid to ask every
--   tick: its target still in the world and its item still where the job needs it. These are what
--   another player or the world can take away mid-job, and the character's own copy of the world
--   shows them, so a multiplayer client asks them too.
-- - check(self), if any: the rest of its rules, the state of its target and its bank, which a
--   multiplayer client's copy can show late, and the checks too dear for every tick. Single player
--   asks them before the job starts, and the authority again in complete().
-- - command(self): the bank command (Commands.lua) and its args that complete() runs on the
--   authority; or run(self), the job itself for one that isn't the bank's.
-- - minutes: the in-game minutes it takes (a number, or a function of the action); or units, its
--   length in action units.
-- - light: it needs light to see by. partInBank: its item is in the bank's container rather than
--   the character's inventory. sound: what it sounds like while it runs; doneSound: when it ends.
-- - begin(self), if any, starts its animation in place of the crouch over the target.
JOBS = {
    [Action.CONNECT_SOURCE] = {
        keeps = function(self) return isSource(self.object) and isBank(self.bank) end,
        check = function(self) return Sources.connectRefusal(self.object, positionOf(self.bank)) == nil end,
        command = function(self)
            return "connectSource", { bank = positionOf(self.bank), source = positionOf(self.object) }
        end,
        minutes = connectMinutes,
        sound = "GeneratorConnect",
    },
    [Action.DISCONNECT_SOURCE] = {
        keeps = function(self) return isSource(self.object) end,
        check = function(self) return PowerBank.connectedBank(self.object) ~= nil end,
        command = function(self) return "disconnectSource", { source = positionOf(self.object) } end,
        minutes = function(self) return connectMinutes(self) / 2 end,
    },
    [Action.CLEAR_SNOW] = {
        keeps = function(self)
            return isSource(self.object) and Sources.sweepable(Sources.kindOf(self.object))
                and Action.isSnowTool(self.item) and self.character:isPrimaryHandItem(self.item)
        end,
        command = function(self) return "clearSnow", { source = positionOf(self.object) } end,
        minutes = 5,
        metabolics = Metabolics.LightWork,
        begin = function(self)
            if self.item and self.item:getType() == "SnowShovel" then
                self:setActionAnim(BuildingHelper.getShovelAnim(self.item))
                self.sound = self.character:playSound("Shoveling")
            else
                self:setActionAnim("Rake")
            end
        end,
    },
    [Action.TURN_ON] = {
        keeps = function(self) return isBank(self.bank) end,
        check = function(self)
            local summary = bankSummary(self)
            return summary ~= nil and PowerBank.switchRefusal(summary, true) == nil
        end,
        command = function(self) return "setBankOn", { bank = positionOf(self.bank), on = true } end,
        minutes = 0.5,
        doneSound = "LightSwitch",
    },
    [Action.TURN_OFF] = {
        keeps = function(self) return isBank(self.bank) end,
        check = function(self)
            local summary = bankSummary(self)
            return summary ~= nil and PowerBank.switchRefusal(summary, false) == nil
        end,
        command = function(self) return "setBankOn", { bank = positionOf(self.bank), on = false } end,
        minutes = 0.5,
        doneSound = "LightSwitch",
    },
    -- Vanilla's ISPlugGenerator, which can't tell the bank its state changed.
    [Action.CONNECT_BANK] = {
        keeps = function(self) return isBank(self.bank) end,
        check = function(self)
            local summary = bankSummary(self)
            return summary ~= nil and PowerBank.connectRefusal(self.character, self.bank, summary, true) == nil
        end,
        command = function(self) return "setBankConnected", { bank = positionOf(self.bank), connected = true } end,
        units = 300,
        sound = "GeneratorConnect",
    },
    [Action.DISCONNECT_BANK] = {
        keeps = function(self) return isBank(self.bank) end,
        check = function(self)
            local summary = bankSummary(self)
            return summary ~= nil and PowerBank.connectRefusal(self.character, self.bank, summary, false) == nil
        end,
        command = function(self) return "setBankConnected", { bank = positionOf(self.bank), connected = false } end,
        units = 300,
        sound = "GeneratorConnect",
    },
    [Action.ATTACH_MAINTAINER] = {
        keeps = function(self)
            return inWorld(self.vehicle) and self.item ~= nil and self.item:getFullType() == RenewableEnergy.SolarMaintainer.ITEM
                and holdsItem(self)
        end,
        check = function(self) return RenewableEnergy.SolarMaintainer.canAttach(self.vehicle) end,
        run = function(self) return RenewableEnergy.SolarMaintainer.attach(self.character, self.vehicle, self.item) end,
        minutes = 1,
        sound = "GeneratorConnect",
    },
    [Action.DETACH_MAINTAINER] = {
        keeps = function(self) return inWorld(self.vehicle) end,
        check = function(self) return RenewableEnergy.SolarMaintainer.isAttached(self.vehicle) end,
        run = function(self) return RenewableEnergy.SolarMaintainer.detach(self.character, self.vehicle) end,
        minutes = 1,
    },
    [Action.WIRE_IN] = {
        keeps = function(self) return isBank(self.bank) and self.item ~= nil and holdsItem(self) end,
        check = function(self) return PowerBank.wiringRefusal(self.character, self.bank, self.item) == nil end,
        command = function(self) return "wireIn", { bank = positionOf(self.bank), itemId = self.item:getID() } end,
        units = function(self) return wiringUnits(self, partWiring(self)) end,
        light = true,
        sound = "GeneratorConnect",
    },
    [Action.UNWIRE] = {
        keeps = function(self) return PowerBank.unwireBlocker(self.bank, self.item) == nil end,
        check = function(self) return PowerBank.unwireRefusal(self.character, self.bank, self.item) == nil end,
        command = function(self) return "unwire", { bank = positionOf(self.bank), itemId = self.item:getID() } end,
        units = function(self) return wiringUnits(self, partWiring(self), 0.5) end,
        light = true,
        partInBank = true,
        sound = "GeneratorConnect",
    },
    [Action.REPAIR_PART] = {
        keeps = function(self) return self.item ~= nil and holdsItem(self) end,
        check = function(self) return PowerBank.repairRefusal(self.character, self.item) == nil end,
        command = function(self) return "repairPart", { bank = positionOf(self.bank), itemId = self.item:getID() } end,
        -- As vanilla's ISFixGenerator.
        units = function(self) return 150 - electricity(self) * 3 end,
        light = true,
        partInBank = true,
        sound = "GeneratorRepair",
    },
    [Action.RENAME] = {
        keeps = function(self) return isBank(self.bank) and type(self.bankName) == "string" end,
        command = function(self) return "rename", { bank = positionOf(self.bank), name = self.bankName } end,
        minutes = 0.5,
    },
    [Action.REPAIR_PANEL] = {
        keeps = function(self)
            local part = inWorld(self.vehicle) and self.vehicle:getPartById(self.partId)
            return part and part:getInventoryItem() ~= nil or false
        end,
        check = function(self)
            local ArrowBoard = arrowBoard()
            return ArrowBoard ~= nil and ArrowBoard.repairablePanel(self.vehicle, self.partId) ~= nil
                and RenewableEnergy.Recipes.panelRepairRefusal(self.character) == nil
        end,
        run = function(self) return arrowBoard().repairPanel(self.character, self.vehicle, self.partId) end,
        -- As the crafting window times Seal Cracked Module (ISHandcraftAction).
        units = function(self) return RenewableEnergy.Recipes.moduleRepairRecipe():getTime(self.character) * 5 end,
        light = true,
        sound = "GeneratorRepair",
    },
    -- As long as vanilla's for a lamp's bulb at the default day length (ISLightActions).
    [Action.REMOVE_BULB] = {
        keeps = function(self) return isGardenLight(self.object) end,
        check = function(self) return RenewableEnergy.SolarGardenLight.getBulb(self.object) ~= nil end,
        run = function(self) return RenewableEnergy.SolarGardenLight.removeBulb(self.character, self.object) end,
        minutes = 1,
    },
    [Action.ADD_BULB] = {
        keeps = function(self)
            return isGardenLight(self.object) and RenewableEnergy.SolarGardenLight.isBulb(self.item) and holdsItem(self)
        end,
        check = function(self) return RenewableEnergy.SolarGardenLight.getBulb(self.object) == nil end,
        run = function(self) return RenewableEnergy.SolarGardenLight.addBulb(self.character, self.object, self.item) end,
        minutes = 1,
    },
    -- Cut Padlock: the lid unlocked, its lock broken (ArrowBoard.cutPadlock). The cutters wear as
    -- vanilla's cutting recipes wear them (MayDegradeLight in CutUpTire,
    -- CraftRecipeData.processKeepInputItem), and a pair that breaks leaves the hands as a broken
    -- weapon does (ISDestroyStuffAction).
    [Action.CUT_PADLOCK] = {
        keeps = function(self)
            return inWorld(self.vehicle) and Action.isBoltCutters(self.item) and self.character:isPrimaryHandItem(self.item)
        end,
        check = function(self)
            local ArrowBoard = arrowBoard()
            local lid = ArrowBoard ~= nil and ArrowBoard.isTrailer(self.vehicle) and self.vehicle:getPartById(ArrowBoard.LID)
            return lid and ArrowBoard.isPadlocked(lid) or false
        end,
        run = function(self)
            if not arrowBoard().cutPadlock(self.vehicle) then
                return false
            end
            if self.item:damageCheck(0, 3) then
                ItemUtils.checkWeapon(self.character)
            end
            return true
        end,
        -- A squeeze of the handles, far quicker than unbolting the lid.
        units = 100,
        -- As vanilla works on a vehicle part at waist height (ISUninstallVehiclePart).
        begin = function(self) self:setActionAnim("VehicleWorkOnMid") end,
        -- The sound of a lock giving way, as when a character forces a locked window
        -- (OpenWindowState).
        doneSound = "BreakLockOnWindow",
    },
    [Action.BOARD_ON] = {
        keeps = function(self) return inWorld(self.vehicle) end,
        check = function(self) return arrowBoard() ~= nil and arrowBoard().canSwitch(self.vehicle, true) end,
        run = function(self) return arrowBoard().setSwitch(self.vehicle, true) end,
        minutes = 0.5,
        doneSound = "LightSwitch",
    },
    [Action.BOARD_OFF] = {
        keeps = function(self) return inWorld(self.vehicle) end,
        check = function(self) return arrowBoard() ~= nil and arrowBoard().canSwitch(self.vehicle, false) end,
        run = function(self) return arrowBoard().setSwitch(self.vehicle, false) end,
        minutes = 0.5,
        doneSound = "LightSwitch",
    },
    -- A lever or pin at the foot of the mast.
    [Action.BRAKE] = {
        keeps = function(self) return isWindCharger(self.object) end,
        check = function(self) return not Wind.isBraked(self.object) end,
        command = function(self) return "setBrake", { source = positionOf(self.object), braked = true } end,
        minutes = 1,
    },
    [Action.RELEASE_BRAKE] = {
        keeps = function(self) return isWindCharger(self.object) end,
        check = function(self) return Wind.isBraked(self.object) end,
        command = function(self) return "setBrake", { source = positionOf(self.object), braked = false } end,
        minutes = 1,
    },
    -- Either tile of a treadmill wired by someone else meanwhile ends the job, so it is wired once.
    [Action.WIRE_TREADMILL] = {
        keeps = function(self)
            return onSquare(self.object) and Treadmill.isTreadmill(self.object) and Treadmill.wiredHalf(self.object) == nil
        end,
        check = function(self) return Treadmill.wiringRefusal(self.character, self.object) == nil end,
        command = function(self) return "wireTreadmill", { source = positionOf(self.object) } end,
        units = function(self) return wiringUnits(self, Specs.treadmill.wiring) end,
        light = true,
        sound = "GeneratorConnect",
    },
    -- As a part comes out of a bank: quicker than wiring, with the same tools, the wire given back.
    [Action.UNWIRE_TREADMILL] = {
        keeps = function(self) return onSquare(self.object) and Treadmill.isWiredTile(self.object) end,
        check = function(self) return Treadmill.unwiringRefusal(self.character, self.object) == nil end,
        command = function(self) return "unwireTreadmill", { source = positionOf(self.object) } end,
        units = function(self) return wiringUnits(self, Specs.treadmill.wiring, 0.5) end,
        light = true,
        sound = "GeneratorConnect",
    },
    -- Lowering the head, unbolting the broken blades and bolting new ones on.
    [Action.REPLACE_BLADES] = {
        keeps = function(self) return isWindCharger(self.object) and self.item ~= nil and holdsItem(self) end,
        check = function(self) return Wind.bladesRefusal(self.object, self.item) == nil end,
        command = function(self)
            return "replaceBlades", { source = positionOf(self.object), itemId = self.item:getID() }
        end,
        minutes = 20,
    },
}

--- Whether the job applies to the world as it is now, every rule of it.
function Action:canPerform()
    local job = JOBS[self.mode]
    return job ~= nil and job.keeps(self) and (job.check == nil or job.check(self))
end

--- Whether the job of `mode` needs light to see by: isValid stops it in the dark, and the menu
--- greys it there.
function Action.needsLight(mode)
    return JOBS[mode].light == true
end

-- Whether the character stands where the menu would have walked them for the job.
local function atJob(self)
    return RenewableEnergy.withinReach(self.character, self:target(), REACH)
end

-- A job field that is a value or a function of the action.
local function valueOf(field, self)
    if type(field) == "function" then
        return field(self)
    end
    return field
end

function Action:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    local job = JOBS[self.mode]
    if job.units then
        return valueOf(job.units, self)
    end
    return valueOf(job.minutes, self) * RenewableEnergy.unitsPerMinute()
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
    local job = JOBS[self.mode]
    if not (job and job.keeps(self)) then
        return false
    end
    -- The server can't tell whether a remote player stands in the dark
    -- (IsoPlayer.tooDarkToRead), so the player's own side checks the light.
    if job.light and self.character:tooDarkToRead() then
        HaloTextHelper.addBadText(self.character, getText("Tooltip_RenewableEnergy_TooDark"))
        return false
    end
    return atJob(self)
end

function Action:waitToStart()
    self.character:faceThisObject(self:target())
    return self.character:shouldBeTurning()
end

function Action:update()
    self.character:faceThisObject(self:target())
    local metabolics = JOBS[self.mode].metabolics
    if metabolics then
        self.character:setMetabolicTarget(metabolics)
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
    local job = JOBS[self.mode]
    if isClient() and self.item then
        -- Server syncs can replace the item objects while the action waits in the queue. A bank
        -- gone meanwhile leaves no item, and isValid then stops the job.
        local container = self.character:getInventory()
        if job.partInBank then
            container = isBank(self.bank) and self.bank:getContainer()
        end
        self.item = container and container:getItemWithIDRecursiv(self.item:getID()) or nil
    end
    if job.begin then
        job.begin(self)
        return
    end
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", self.vehicle and "Mid" or "Low")
    self.character:reportEvent("EventLootItem")
    if job.sound then
        self.sound = self.character:playSound(job.sound)
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
    local doneSound = JOBS[self.mode].doneSound
    if doneSound then
        self.character:playSound(doneSound)
    end
    ISInventoryPage.renderDirty = true
    ISBaseTimedAction.perform(self)
end

-- The server never calls isValid(), so this checks the action again. NetTimedAction checks no
-- distance, so the server also makes sure the character is at the job, which a modified client
-- could otherwise send for any bank or vehicle in the world.
function Action:complete()
    if not self:canPerform() then
        return false
    end
    if isServer() and not atJob(self) then
        return false
    end
    local job = JOBS[self.mode]
    if job.run then
        return job.run(self)
    end
    local ok = PowerBank.perform(self.character, job.command(self))
    return ok == true
end

-- Parameter names must match the fields set on `o`: the multiplayer server rebuilds the action by
-- passing those fields to new() in parameter order (NetTimedAction). `object` is the source or the
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
