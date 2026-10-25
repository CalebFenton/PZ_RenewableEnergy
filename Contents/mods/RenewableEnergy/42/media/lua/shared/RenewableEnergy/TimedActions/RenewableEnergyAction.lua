-- Every hands-on job at a battery bank, a source, a garden light or a vehicle
-- (RenewableEnergy.JobAction); the authority's complete() makes the change. The server finds the
-- class by its Type with a plain global lookup (NetTimedAction.parse), which is why the class is a
-- global outside the RenewableEnergy table.

require "Util/BuildingHelper"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/TimedActions/JobAction"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Wind"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/PowerBank/Treadmill"
require "RenewableEnergy/Recipes"
require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "RenewableEnergy/Gadgets/CarAlternator"

RenewableEnergyAction = RenewableEnergy.JobAction:derive("RenewableEnergyAction")

local Action = RenewableEnergyAction
Action.REPORTS_LOOT = true
local Specs, Wind = RenewableEnergy.Specs, RenewableEnergy.Wind
local PowerBank, Sources, Treadmill = RenewableEnergy.PowerBank, RenewableEnergy.Sources, RenewableEnergy.Treadmill
local positionOf, onSquare = PowerBank.positionOf, RenewableEnergy.onSquare
local CarAlternator = RenewableEnergy.CarAlternator
local Recipes, SolarMaintainer = RenewableEnergy.Recipes, RenewableEnergy.SolarMaintainer
local SolarGardenLight = RenewableEnergy.SolarGardenLight

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
Action.SEAL_PANEL = "RepairPanel"
Action.SEAL_MODULE = "SealModule"
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
Action.TAKE_OUT_ALTERNATOR = "TakeOutAlternator"
Action.PUT_BACK_ALTERNATOR = "PutBackAlternator"

-- What clears snow off a panel without scratching it: a broom sweeps, a snow shovel pushes.
local SNOW_TOOLS = { ["Base.Broom"] = true, ["Base.Broom_Twig"] = true, ["Base.SnowShovel"] = true }

-- How far from the middle of the target's square, on each axis, a character may work: what
-- luautils.walkAdj and getCorrectSquareForWall leave as "there", plus slack for drift and client lag.
-- A vehicle job measures past the vehicle's body (ISPathFindAction.pathToVehicleArea).
Action.REACH = 4.6

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
    return onSquare(object) and SolarGardenLight.isLight(object)
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
    return wiring.seconds * skillFactor(electricity(self)) / skillFactor(0) * (share or 1) * RenewableEnergy.UNITS_PER_SECOND
end

local function partWiring(self)
    return self.item and PowerBank.wiringFor(self.item:getFullType())
end

local function connectMinutes(self)
    return SandboxVars.RenewableEnergy.ConnectPanelMin * skillFactor(electricity(self))
end

-- ArrowBoard is server code (server/RenewableEnergy/World/ArrowBoard.lua): it loads after the
-- shared files, and not at all on a multiplayer client, so it is looked up when a job asks.
local function arrowBoard()
    return RenewableEnergy.ArrowBoard
end

local JOBS

-- Whether the action's item is where its job needs it: in the bank for a part already wired
-- in, else anywhere in the character's inventory.
local function holdsItem(self)
    if self:row().partInBank then
        local container = isBank(self.bank) and self.bank:getContainer()
        return container and container:contains(self.item) or false
    end
    return self.character:getInventory():containsRecursive(self.item)
end

-- Turn On and Turn Off: the bank's switch set to `on`.
local function bankSwitchJob(on)
    return {
        keeps = function(self) return isBank(self.bank) end,
        check = function(self)
            local summary = bankSummary(self)
            return summary ~= nil and PowerBank.switchRefusal(summary, on) == nil
        end,
        command = function(self) return "setBankOn", { bank = positionOf(self.bank), on = on } end,
        minutes = 0.5,
        doneSound = "LightSwitch",
    }
end

-- Connect and Disconnect the bank to the house's wiring, as vanilla's ISPlugGenerator, which can't
-- tell the bank its state changed. Unlike vanilla's, it needs light: it is wiring at the house's
-- panel, as wiring a part in is.
local function bankConnectJob(connected)
    return {
        keeps = function(self) return isBank(self.bank) end,
        check = function(self)
            local summary = bankSummary(self)
            return summary ~= nil and PowerBank.connectRefusal(self.character, self.bank, summary, connected) == nil
        end,
        command = function(self)
            return "setBankConnected", { bank = positionOf(self.bank), connected = connected }
        end,
        units = 300,
        light = true,
        sound = "GeneratorConnect",
    }
end

-- The arrow board's switch set to `on`.
local function boardSwitchJob(on)
    return {
        keeps = function(self) return inWorld(self.vehicle) end,
        check = function(self) return arrowBoard() ~= nil and arrowBoard().canSwitch(self.vehicle, on) end,
        run = function(self) return arrowBoard().setSwitch(self.vehicle, on) end,
        minutes = 0.5, position = "Mid",
        doneSound = "LightSwitch",
    }
end

-- A wind charger's brake, a lever or pin at the foot of the mast, set to `braked`.
local function brakeJob(braked)
    return {
        keeps = function(self) return isWindCharger(self.object) end,
        check = function(self) return Wind.isBraked(self.object) ~= braked end,
        command = function(self) return "setBrake", { source = positionOf(self.object), braked = braked } end,
        minutes = 1,
    }
end

-- Every job, by name:
-- - keeps(self): what the job needs from moment to moment (JobAction): its target still in the
--   world and its item still where the job needs it.
-- - check(self), if any: the rest of its rules, the state of its target and its bank, which a
--   multiplayer client's copy can show late, and the checks too dear for every tick. Single player
--   asks them before the job starts, and the authority again in complete().
-- - command(self): the bank job (BankJobs.lua) and its args that complete() runs on the
--   authority; or run(self), the job itself for one that isn't the bank's.
-- - minutes: the in-game minutes it takes (a number, or a function of the action); or units, its
--   length in action units.
-- - light: it needs light to see by. partInBank: its item is in the bank's container rather than
--   the character's inventory. How it looks and its exertion are JobAction's row fields; one at a
--   vehicle reaches at waist height (`position = "Mid"`).
JOBS = {
    [Action.CONNECT_SOURCE] = {
        keeps = function(self) return isSource(self.object) and isBank(self.bank) end,
        check = function(self)
            return Sources.connectRefusal(self.object, positionOf(self.bank)) == nil
                and Sources.bankRefusal(self.bank:isConnected()) == nil
        end,
        command = function(self)
            return "connectSource", { bank = positionOf(self.bank), source = positionOf(self.object) }
        end,
        minutes = connectMinutes,
        light = true,
        sound = "GeneratorConnect",
    },
    [Action.DISCONNECT_SOURCE] = {
        keeps = function(self) return isSource(self.object) end,
        check = function(self) return PowerBank.connectedBank(self.object) ~= nil end,
        command = function(self) return "disconnectSource", { source = positionOf(self.object) } end,
        minutes = function(self) return connectMinutes(self) / 2 end,
        light = true,
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
    [Action.TURN_ON] = bankSwitchJob(true),
    [Action.TURN_OFF] = bankSwitchJob(false),
    [Action.CONNECT_BANK] = bankConnectJob(true),
    [Action.DISCONNECT_BANK] = bankConnectJob(false),
    [Action.ATTACH_MAINTAINER] = {
        keeps = function(self)
            return inWorld(self.vehicle) and self.item ~= nil and self.item:getFullType() == SolarMaintainer.ITEM
                and holdsItem(self)
        end,
        check = function(self) return SolarMaintainer.canAttach(self.vehicle) end,
        run = function(self) return SolarMaintainer.attach(self.character, self.vehicle, self.item) end,
        minutes = 1, position = "Mid",
        sound = "GeneratorConnect",
    },
    [Action.DETACH_MAINTAINER] = {
        keeps = function(self) return inWorld(self.vehicle) end,
        check = function(self) return SolarMaintainer.isAttached(self.vehicle) end,
        run = function(self) return SolarMaintainer.detach(self.character, self.vehicle) end,
        minutes = 1, position = "Mid",
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
        keeps = function(self) return PowerBank.unwiringBlocker(self.bank, self.item) == nil end,
        check = function(self) return PowerBank.unwiringRefusal(self.character, self.bank, self.item) == nil end,
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
    [Action.SEAL_PANEL] = {
        keeps = function(self)
            local part = inWorld(self.vehicle) and self.vehicle:getPartById(self.partId)
            return part and part:getInventoryItem() ~= nil or false
        end,
        check = function(self)
            local ArrowBoard = arrowBoard()
            return ArrowBoard ~= nil and ArrowBoard.sealablePanel(self.vehicle, self.partId) ~= nil
                and Recipes.sealInPlaceRefusal(self.character) == nil
        end,
        run = function(self) return arrowBoard().sealPanel(self.character, self.vehicle, self.partId) end,
        -- As the crafting window times Seal Cracked Module (ISHandcraftAction).
        units = function(self) return Recipes.moduleRepairRecipe():getTime(self.character) * 5 end,
        light = true, position = "Mid",
        sound = "GeneratorRepair",
    },
    -- Seal Cracked Panel's twin for a module on a placed panel.
    [Action.SEAL_MODULE] = {
        keeps = function(self) return isSource(self.object) end,
        check = function(self)
            return Recipes.sealableModule(self.object, self.slot) ~= nil
                and Recipes.sealInPlaceRefusal(self.character) == nil
        end,
        command = function(self) return "sealModule", { source = positionOf(self.object), slot = self.slot } end,
        units = function(self) return Recipes.moduleRepairRecipe():getTime(self.character) * 5 end,
        light = true,
        sound = "GeneratorRepair",
    },
    -- As long as vanilla's for a lamp's bulb at the default day length (ISLightActions).
    [Action.REMOVE_BULB] = {
        keeps = function(self) return isGardenLight(self.object) end,
        check = function(self) return SolarGardenLight.getBulb(self.object) ~= nil end,
        run = function(self) return SolarGardenLight.removeBulb(self.character, self.object) end,
        minutes = 1,
    },
    [Action.ADD_BULB] = {
        keeps = function(self)
            return isGardenLight(self.object) and SolarGardenLight.isBulb(self.item) and holdsItem(self)
        end,
        check = function(self) return SolarGardenLight.getBulb(self.object) == nil end,
        run = function(self) return SolarGardenLight.addBulb(self.character, self.object, self.item) end,
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
        anim = "VehicleWorkOnMid",
        -- The sound of a lock giving way, as when a character forces a locked window
        -- (OpenWindowState).
        doneSound = "BreakLockOnWindow",
    },
    [Action.BOARD_ON] = boardSwitchJob(true),
    [Action.BOARD_OFF] = boardSwitchJob(false),
    [Action.BRAKE] = brakeJob(true),
    [Action.RELEASE_BRAKE] = brakeJob(false),
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
        light = true,
    },
    -- Take Out and Put Back Alternator (RenewableEnergy.CarAlternator), worked as vanilla works on
    -- an engine-bay part (ISUninstallVehiclePart). The hood and the engine are checked with the
    -- rest, not every tick: a multiplayer client's copy shows the hood the menu opened only a
    -- little after the server opened it.
    [Action.TAKE_OUT_ALTERNATOR] = {
        keeps = function(self) return CarAlternator.isCar(self.vehicle) end,
        check = function(self) return CarAlternator.refusal(self.character, self.vehicle, false) == nil end,
        run = function(self) return CarAlternator.takeOut(self.character, self.vehicle) end,
        units = function(self) return CarAlternator.units(self.character) end,
        metabolics = Metabolics.MediumWork,
        anim = "VehicleWorkOnMid",
    },
    [Action.PUT_BACK_ALTERNATOR] = {
        keeps = function(self)
            return CarAlternator.isCar(self.vehicle) and self.item ~= nil and self.item:getFullType() == CarAlternator.ITEM
                and holdsItem(self)
        end,
        check = function(self) return CarAlternator.refusal(self.character, self.vehicle, true) == nil end,
        run = function(self) return CarAlternator.putBack(self.character, self.vehicle, self.item) end,
        units = function(self) return CarAlternator.units(self.character) end,
        metabolics = Metabolics.MediumWork,
        anim = "VehicleWorkOnMid",
    },
}

--- Whether the job applies to the world as it is now, every rule of it.
function Action:canPerform()
    local row = self:row()
    return row.keeps(self) and (row.check == nil or row.check(self))
end

--- Whether the job `job` needs light to see by: isValid stops it in the dark, and the menu
--- greys it there.
function Action.needsLight(job)
    return JOBS[job].light == true
end

function Action:keeps()
    return self:row().keeps(self)
end

function Action:row()
    return JOBS[self.job]
end

-- A job field that is a value or a function of the action.
local function valueOf(field, self)
    if type(field) == "function" then
        return field(self)
    end
    return field
end

function Action:units()
    local row = self:row()
    if row.units then
        return valueOf(row.units, self)
    end
    return valueOf(row.minutes, self) * RenewableEnergy.unitsPerMinute()
end

function Action:target()
    return self.vehicle or self.object or self.bank
end

-- A bank gone meanwhile leaves no item, and isValid then stops the job.
function Action:findItems()
    if not self.item then
        return
    end
    local container = self.character:getInventory()
    if self:row().partInBank then
        container = isBank(self.bank) and self.bank:getContainer()
    end
    self.item = container and container:getItemWithIDRecursiv(self.item:getID()) or nil
end

function Action:complete()
    if not (self:canPerform() and self:atJobForAuthority()) then
        return false
    end
    local row = self:row()
    if row.run then
        return row.run(self)
    end
    local ok = PowerBank.perform(self.character, row.command(self))
    return ok == true
end

-- Parameter names must match the fields set on `o`: the multiplayer server rebuilds the action by
-- passing those fields to new() in parameter order (NetTimedAction). `object` is the source or the
-- garden light, `bank` the bank's IsoGenerator, `item` the tool or part the job uses, `bankName`
-- the bank's new name, `partId` the vehicle part worked on, `slot` the panel's module; unused
-- ones are nil. The name can't be a field called `name`, which NetTimedAction reads as the
-- action's own name. Returns nil for a job there is none of, which the server turns down
-- (NetTimedActionPacket.processServer).
function Action:new(character, job, object, bank, vehicle, item, bankName, partId, slot)
    if not JOBS[job] then
        return nil
    end
    local o = ISBaseTimedAction.new(self, character)
    o.job = job
    o.object = object
    o.bank = bank
    o.vehicle = vehicle
    o.item = item
    o.bankName = bankName
    o.partId = partId
    o.slot = slot
    o.maxTime = o:getDuration()
    return o
end
