-- The Solar Battery Maintainer: a small panel clipped to a vehicle that keeps its battery
-- topped up in daylight.
--
-- An attached maintainer is a mark in the modData of the vehicle's Battery part. That part
-- stays when its battery is swapped, and vehicle:transmitPartModData sends its modData to
-- multiplayer clients, so the menu there can tell what is attached. Attaching, detaching and
-- charging are the authority's: server/RenewableEnergy/Gadgets/SolarMaintainerServer.lua.

local RenewableEnergy = require "RenewableEnergy/Utilities"
local VehicleBattery = require "RenewableEnergy/Gadgets/VehicleBattery"

local SolarMaintainer = {}
RenewableEnergy.SolarMaintainer = SolarMaintainer

SolarMaintainer.ITEM = "RenewableEnergy.SolarMaintainer"
-- Its cell's rated watts.
SolarMaintainer.WATTS = 10

-- Battery part modData: set while a maintainer is attached.
SolarMaintainer.ATTACHED_KEY = "RenewableEnergy_SolarMaintainer"

function SolarMaintainer.isAttached(vehicle)
    local part = VehicleBattery.partOf(vehicle)
    return part ~= nil and part:getModData()[SolarMaintainer.ATTACHED_KEY] ~= nil
end

function SolarMaintainer.canAttach(vehicle)
    return VehicleBattery.partOf(vehicle) ~= nil and not SolarMaintainer.isAttached(vehicle)
end

return SolarMaintainer
