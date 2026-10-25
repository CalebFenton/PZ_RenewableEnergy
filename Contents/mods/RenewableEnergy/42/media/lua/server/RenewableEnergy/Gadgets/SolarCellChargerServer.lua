-- The Solar Battery Charger on the authority: the charge GadgetCharging's pass gives.

if isClient() then return end

require "RenewableEnergy/Specs"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/Gadgets/SolarCellCharger"

local SolarCellCharger = RenewableEnergy.SolarCellCharger
local Battery, Specs, Sun = RenewableEnergy.Battery, RenewableEnergy.Specs, RenewableEnergy.Sun

--- Adds `hours` of the panel's output under `sky` (Sun.skyNow, now if nil) to the batteries in
--- `charger`, one use at a time to the emptiest, so a set fills evenly. Returns the uses it added.
function SolarCellCharger.charge(charger, hours, sky)
    local container = charger:getContainer()
    if not container then
        return 0
    end
    local data = charger:getModData()
    local stored = (data[SolarCellCharger.STORED_KEY] or 0)
        + Sun.squareWatts(charger:getSquare(), Specs.cellChargerWatts, sky) * hours
    local added = 0
    local battery = Battery.emptiestIn(container, SolarCellCharger.isCell)
    while battery do
        local useWh = battery:getUseDelta() * Specs.cellChargerBatteryWh
        if stored < useWh then
            break
        end
        battery:setCurrentUses(battery:getCurrentUses() + 1)
        -- syncItemFields reaches only a player's inventory; this reaches a placed container.
        sendItemStats(battery)
        stored = stored - useWh
        added = added + 1
        battery = Battery.emptiestIn(container, SolarCellCharger.isCell)
    end
    -- Full batteries take nothing, and a panel stores nothing for later.
    data[SolarCellCharger.STORED_KEY] = battery and stored or 0
    return added
end

--- Charges every loaded charger the authority has seen.
function SolarCellCharger.chargeAll(hours)
    local sky = Sun.skyNow()
    SolarCellCharger.eachLoaded(function(charger)
        SolarCellCharger.charge(charger, hours, sky)
    end)
end

return SolarCellCharger
