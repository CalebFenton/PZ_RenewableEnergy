require "RenewableEnergy/Gadgets/VehicleBattery"

-- The Solar Battery Maintainer: a small panel clipped to a vehicle that keeps its battery
-- topped up in daylight.
--
-- An attached maintainer is a mark in the modData of the vehicle's Battery part. That part
-- stays when its battery is swapped, and vehicle:transmitPartModData sends its modData to
-- multiplayer clients, so the menu there can tell what is attached. Attaching, detaching and
-- charging are the authority's: server/RenewableEnergy/Gadgets/SolarMaintainerServer.lua.
RenewableEnergy = RenewableEnergy or {}
local SolarMaintainer = {}
RenewableEnergy.SolarMaintainer = SolarMaintainer
local VehicleBattery = RenewableEnergy.VehicleBattery

SolarMaintainer.ITEM = "RenewableEnergy.SolarMaintainer"

-- Battery part modData: { condition } of the attached maintainer.
SolarMaintainer.ATTACHED_KEY = "RenewableEnergy_SolarMaintainer"

--- The vehicle's Battery part, which holds the maintainer's mark, or nil.
function SolarMaintainer.batteryPart(vehicle)
    return vehicle and vehicle:getPartById(VehicleBattery.PART)
end

function SolarMaintainer.isAttached(vehicle)
    local part = SolarMaintainer.batteryPart(vehicle)
    return part ~= nil and part:getModData()[SolarMaintainer.ATTACHED_KEY] ~= nil
end

function SolarMaintainer.canAttach(vehicle)
    return SolarMaintainer.batteryPart(vehicle) ~= nil and not SolarMaintainer.isAttached(vehicle)
end

return SolarMaintainer
