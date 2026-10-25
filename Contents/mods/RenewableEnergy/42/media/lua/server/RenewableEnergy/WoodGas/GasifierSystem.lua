-- The gasifiers on the authority (RenewableEnergy.ObjectSystem), and the jobs players do at them,
-- whose rules are GasifierJobs'.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/ObjectSystem"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/WoodGas/GasifierJobs"
require "RenewableEnergy/WoodGas/GasifierObject"

RenewableEnergy = RenewableEnergy or {}
local Gasifier, GasifierJobs, ObjectSystem = RenewableEnergy.Gasifier, RenewableEnergy.GasifierJobs, RenewableEnergy.ObjectSystem
local GasifierObject = RenewableEnergy.GasifierObject

local GasifierSystem = ObjectSystem.define({
    name = "Gasifier", kind = "gasifier", owner = Gasifier, Object = GasifierObject, isObject = Gasifier.isGasifier,
})
RenewableEnergy.GasifierSystem = GasifierSystem

-- What each job does to the gasifier's record `record` (its tile `isoObject`) beyond taking its
-- materials, by its row of GasifierJobs.JOBS. `item` is the container Drain Condensate fills, nil
-- for the ground. Returns whether it was done.
local DO = {
    [GasifierJobs.LIGHT] = function(character, record, row, isoObject)
        return record:light(isoObject)
    end,
    [GasifierJobs.PUT_OUT] = function(character, record)
        record:goOut()
        return true
    end,
    [GasifierJobs.CLEAN_ASH] = function(character, record)
        local count = math.floor(record.ash / Gasifier.ASH_PER_ITEM)
        RenewableEnergy.giveItems(character, Gasifier.WOOD_ASH, count)
        record.ash = record.ash - count * Gasifier.ASH_PER_ITEM
        return true
    end,
    -- Into `item` as much of the condensate as it takes, or all of it onto the ground.
    [GasifierJobs.DRAIN] = function(character, record, row, isoObject, item)
        if item then
            local fluid = item:getFluidContainer()
            local litres = math.min(record.condensate, fluid:getFreeCapacity())
            fluid:addFluid(Gasifier.VINEGAR, litres)
            item:syncItemFields()
            record.condensate = record.condensate - litres
        else
            record.condensate = 0
        end
        return true
    end,
}

--- The authority's side of the jobs at a record (GasJobs.perform), whose `with` is the container
--- Drain Condensate fills.
GasifierSystem.jobSite = ObjectSystem.jobSite(Gasifier, DO)

return GasifierSystem
