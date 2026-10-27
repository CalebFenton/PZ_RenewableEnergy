-- The authority's side of the hands-on jobs at a vehicle (cf_commonlib's Jobs.perform), whose
-- rules are VehicleJobs'.

if isClient() then return end

local VehicleJobs = require "RenewableEnergy/Gadgets/VehicleJobs"
local CarAlternator = require "RenewableEnergy/Gadgets/CarAlternator"
local SolarMaintainer = require "RenewableEnergy/Gadgets/SolarMaintainer"
local ArrowBoard = require "RenewableEnergy/World/ArrowBoard"
local Action = require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local Jobs = require "cf_commonlib/Jobs"

-- What each vehicle job does, by its row of VehicleJobs.JOBS. Returns whether it was done.
local DO = {
    [VehicleJobs.ATTACH_MAINTAINER] = function(character, row, vehicle, item)
        return SolarMaintainer.attach(character, vehicle, item)
    end,
    [VehicleJobs.DETACH_MAINTAINER] = function(character, row, vehicle)
        return SolarMaintainer.detach(character, vehicle)
    end,
    [VehicleJobs.TAKE_OUT_ALTERNATOR] = function(character, row, vehicle)
        return CarAlternator.takeOut(character, vehicle)
    end,
    [VehicleJobs.PUT_BACK_ALTERNATOR] = function(character, row, vehicle, item)
        return CarAlternator.putBack(character, vehicle, item)
    end,
    [VehicleJobs.BOARD_ON] = function(character, row, vehicle)
        return ArrowBoard.setSwitch(vehicle, row.on)
    end,
    -- The lid unlocked, its lock broken. The cutters wear as vanilla's cutting recipes wear them
    -- (MayDegradeLight in CutUpTire, CraftRecipeData.processKeepInputItem), and a pair that breaks
    -- leaves the hands as a broken weapon does (ISDestroyStuffAction).
    [VehicleJobs.CUT_PADLOCK] = function(character, row, vehicle, cutters)
        if not ArrowBoard.cutPadlock(vehicle) then
            return false
        end
        if cutters:damageCheck(0, 3) then
            ItemUtils.checkWeapon(character)
        end
        return true
    end,
    [VehicleJobs.SEAL_PANEL] = function(character, row, vehicle, partId)
        return ArrowBoard.sealPanel(character, vehicle, partId)
    end,
}
DO[VehicleJobs.BOARD_OFF] = DO[VehicleJobs.BOARD_ON]

Action.serve({ vehicle = Jobs.targetSite(DO) })
