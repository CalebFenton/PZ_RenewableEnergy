-- The hands-on jobs at a vehicle: a Solar Maintainer clipped on or off, a car's alternator taken
-- out or put back, and the arrow board trailer's switch, padlock and panels. What each takes of the
-- character and what refuses it (cf_commonlib's Jobs); VehicleJobsServer does them.
-- A job at a vehicle reaches at waist height, from the area of the part it works on.

local Specs = require "RenewableEnergy/Specs"
local ModuleRepair = require "RenewableEnergy/PowerBank/ModuleRepair"
local ArrowBoard = require "RenewableEnergy/ArrowBoard/Power"
local SolarMaintainer = require "RenewableEnergy/Gadgets/SolarMaintainer"
local VehicleBattery = require "RenewableEnergy/Gadgets/VehicleBattery"
local CarAlternator = require "RenewableEnergy/Gadgets/CarAlternator"
local Items = require "cf_commonlib/Items"
local Jobs = require "cf_commonlib/Jobs"

local VehicleJobs = {}

VehicleJobs.ATTACH_MAINTAINER = "AttachMaintainer"
VehicleJobs.DETACH_MAINTAINER = "DetachMaintainer"
VehicleJobs.TAKE_OUT_ALTERNATOR = "TakeOutAlternator"
VehicleJobs.PUT_BACK_ALTERNATOR = "PutBackAlternator"
VehicleJobs.BOARD_ON = "BoardOn"
VehicleJobs.BOARD_OFF = "BoardOff"
VehicleJobs.CUT_PADLOCK = "CutPadlock"
VehicleJobs.SEAL_PANEL = "RepairPanel"
VehicleJobs.REGLAZE_PANEL = "ReglazePanel"

function VehicleJobs.isBoltCutters(item)
    return item ~= nil and item:hasTag(ItemTag.BOLT_CUTTERS) and Items.notBroken(item)
end

-- The vehicle area of `vehicle`'s part `id`.
local function areaOf(vehicle, id)
    return vehicle:getPartById(id):getArea()
end

-- Where a maintainer clips on: the vehicle's battery.
local function atBattery(vehicle)
    return VehicleBattery.partOf(vehicle):getArea()
end

-- Where the arrow board's switch is: in its battery box.
local function atBox(vehicle)
    return areaOf(vehicle, ArrowBoard.BATTERY_BOX)
end

-- The arrow board's switch set to `on`.
local function boardJob(on)
    return {
        on = on, minutes = 0.5, position = "Mid", doneSound = "LightSwitch", area = atBox, hideBlocked = true,
        blocker = function(character, vehicle)
            return not ArrowBoard.canSwitch(vehicle, on) and "Tooltip_RenewableEnergy_CantSwitchLamps" or nil
        end,
    }
end

-- An alternator hangs on two bolts and a belt tensioner: a wrench, and a little more skill than
-- the battery's screwdriver.
local SKILL = { perk = "Mechanics", need = 2 }

-- Take Out and Put Back Alternator (CarAlternator), worked as vanilla works on an
-- engine-bay part (ISUninstallVehiclePart). A shut hood isn't the menu's blocker, as the menu
-- opens it first, as vanilla's engine jobs do.
local function alternatorJob(putBack)
    return {
        units = function(vehicle, item, character) return CarAlternator.units(character) end,
        metabolics = Metabolics.MediumWork, anim = "VehicleWorkOnMid",
        area = function(vehicle) return areaOf(vehicle, CarAlternator.ENGINE) end,
        blocker = function(character, vehicle)
            return CarAlternator.blocker(character, vehicle, putBack)
                or not CarAlternator.hoodOpen(vehicle) and "Tooltip_RenewableEnergy_HoodShut" or nil
        end,
        materials = putBack and { SKILL, Specs.WRENCH, { item = CarAlternator.ITEM, need = 1, keep = true } } or { SKILL, Specs.WRENCH },
    }
end

-- Every job, by name (Jobs.define); `with` is the maintainer, alternator or bolt cutters a job
-- works with, or the panel part Seal Cracked Panel or Reglaze Panel mends.
VehicleJobs.JOBS = {
    [VehicleJobs.ATTACH_MAINTAINER] = {
        minutes = 1, position = "Mid", sound = "GeneratorConnect", area = atBattery, hideBlocked = true,
        blocker = function(character, vehicle)
            return not SolarMaintainer.canAttach(vehicle) and "Tooltip_RenewableEnergy_CantAttachMaintainer" or nil
        end,
        with = Items.ofType(SolarMaintainer.ITEM), withMissing = "Tooltip_RenewableEnergy_NeedsMaintainer",
    },
    [VehicleJobs.DETACH_MAINTAINER] = {
        minutes = 1, position = "Mid", area = atBattery, hideBlocked = true,
        blocker = function(character, vehicle)
            return not SolarMaintainer.isAttached(vehicle) and "Tooltip_RenewableEnergy_NoMaintainerAttached" or nil
        end,
    },
    [VehicleJobs.TAKE_OUT_ALTERNATOR] = alternatorJob(false),
    [VehicleJobs.PUT_BACK_ALTERNATOR] = alternatorJob(true),
    [VehicleJobs.BOARD_ON] = boardJob(true),
    [VehicleJobs.BOARD_OFF] = boardJob(false),
    -- A squeeze of the handles, far quicker than unbolting the lid, as vanilla works on a part at
    -- waist height (ISUninstallVehiclePart), ending in the sound of a lock giving way, as when a
    -- character forces a locked window (OpenWindowState).
    [VehicleJobs.CUT_PADLOCK] = {
        units = 100, anim = "VehicleWorkOnMid", doneSound = "BreakLockOnWindow", wield = true, hideBlocked = true,
        area = function(vehicle) return areaOf(vehicle, ArrowBoard.LID) end,
        blocker = function(character, vehicle)
            local lid = ArrowBoard.isTrailer(vehicle) and vehicle:getPartById(ArrowBoard.LID)
            return not (lid and ArrowBoard.isPadlocked(lid)) and "Tooltip_RenewableEnergy_NotPadlocked" or nil
        end,
        with = VehicleJobs.isBoltCutters, withMissing = "Tooltip_RenewableEnergy_NeedsBoltCutters",
    },
    -- Seal Cracked Module's and Reglaze Module's twins for a panel still on the trailer.
    [VehicleJobs.SEAL_PANEL] = ModuleRepair.jobRow(ModuleRepair.SEAL, ArrowBoard.sealRefusal,
        { position = "Mid", area = areaOf }),
    [VehicleJobs.REGLAZE_PANEL] = ModuleRepair.jobRow(ModuleRepair.REGLAZE, function(vehicle, partId)
        return not ArrowBoard.reglazablePanel(vehicle, partId) and "Tooltip_RenewableEnergy_NotDamaged" or nil
    end, { position = "Mid", area = areaOf }),
}

Jobs.define(VehicleJobs, {
    subjectOf = function(vehicle) return instanceof(vehicle, "BaseVehicle") and vehicle or nil end, missing = "Tooltip_RenewableEnergy_NoVehicle",
})

return VehicleJobs
