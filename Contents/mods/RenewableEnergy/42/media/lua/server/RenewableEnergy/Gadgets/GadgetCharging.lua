require "RenewableEnergy/Gadgets/SolarMaintainer"
require "RenewableEnergy/Gadgets/SolarCellCharger"
require "RenewableEnergy/Gadgets/SolarGardenLight"

-- Runs the small solar gadgets, on the authority: single player or the server. Only loaded
-- vehicles, chargers and garden lights run, as vanilla's own battery chargers do.
if isClient() then
    return
end

RenewableEnergy = RenewableEnergy or {}
local GadgetCharging = {}
RenewableEnergy.GadgetCharging = GadgetCharging

-- Longest stretch one pass makes up for, since it charges at the sun of the moment.
local LONGEST_PASS = 1

-- World age in hours at the last pass.
local lastHour

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
    local hours = lastHour and math.min(now - lastHour, LONGEST_PASS) or 0
    lastHour = now
    if hours <= 0 then
        return
    end
    GadgetCharging.chargeVehicles(hours)
    RenewableEnergy.SolarCellCharger.chargeAll(hours)
    RenewableEnergy.SolarGardenLight.updateAll(hours)
end

Events.EveryTenMinutes.Add(GadgetCharging.update)

return GadgetCharging
