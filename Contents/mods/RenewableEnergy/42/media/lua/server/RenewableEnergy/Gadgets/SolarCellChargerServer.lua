-- The Solar Battery Charger on the authority: the charge GadgetCharging's pass gives.

if isClient() then return end

local Sun = require "RenewableEnergy/Sun"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local SolarCellCharger = require "RenewableEnergy/Gadgets/SolarCellCharger"

local function cellWh()
    return SolarCellCharger.BATTERY_WH
end

--- Adds `hours` of the panel's output under `sky` (Sun.skyNow) to the batteries in
--- `charger`, one use at a time to the emptiest, so a set fills evenly (Battery.shift). Returns the
--- uses it added.
function SolarCellCharger.charge(charger, hours, sky)
    local container = charger:getContainer()
    if not container then
        return 0
    end
    local data = charger:getModData()
    local stored = (data[SolarCellCharger.STORED_KEY] or 0)
        + Sun.squareWatts(charger:getSquare(), SolarCellCharger.WATTS, sky) * hours
    local moved, added, short = Battery.shift(container, stored, 1, 1, SolarCellCharger.isCell, cellWh, 1)
    -- Full batteries take nothing, and a panel stores nothing for later.
    data[SolarCellCharger.STORED_KEY] = short and stored - moved or 0
    return added
end

--- Charges every loaded charger the authority has seen for `hours` under `sky` (Sun.skyNow).
function SolarCellCharger.chargeAll(hours, sky)
    SolarCellCharger.eachLoaded(function(charger)
        SolarCellCharger.charge(charger, hours, sky)
    end)
end

return SolarCellCharger
