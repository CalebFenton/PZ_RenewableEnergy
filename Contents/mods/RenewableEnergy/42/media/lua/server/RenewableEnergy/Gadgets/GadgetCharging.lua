require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/Gadgets/SolarCellCharger"

-- Charges the stage-0 gadgets, on the authority: single player or the server. Only loaded
-- vehicles and chargers charge, as vanilla's own battery chargers do.
if isClient() then
    return
end

RenewableEnergy = RenewableEnergy or {}
local GadgetCharging = {}
RenewableEnergy.GadgetCharging = GadgetCharging

-- Longest stretch one pass makes up for, since it charges at the sun of the moment.
local MAX_HOURS = 1

local lastHours

function GadgetCharging.chargeVehicles(hours)
    local vehicles = getCell():getVehicles():iterator()
    while vehicles:hasNext() do
        RenewableEnergy.SolarMaintainer.charge(vehicles:next(), hours)
    end
end

-- EveryTenMinutes fires at most once a tick however much game time passed, so the pass
-- measures the time itself.
function GadgetCharging.update()
    local now = getGameTime():getWorldAgeHours()
    local hours = lastHours and math.min(now - lastHours, MAX_HOURS) or 0
    lastHours = now
    if hours <= 0 then
        return
    end
    GadgetCharging.chargeVehicles(hours)
    RenewableEnergy.SolarCellCharger.chargeAll(hours)
end

Events.EveryTenMinutes.Add(GadgetCharging.update)

return GadgetCharging
