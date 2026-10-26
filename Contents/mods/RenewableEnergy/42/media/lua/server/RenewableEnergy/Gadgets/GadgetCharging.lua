-- Runs the small solar gadgets and the arrow board trailers' panels, on the authority: single
-- player or the server. Only loaded vehicles, chargers and garden lights run, as vanilla's own
-- battery chargers do.

if isClient() then return end

local RenewableEnergy = require "RenewableEnergy/Utilities"
local Sun = require "RenewableEnergy/Sun"
local SolarMaintainer = require "RenewableEnergy/Gadgets/SolarMaintainerServer"
local SolarCellCharger = require "RenewableEnergy/Gadgets/SolarCellChargerServer"
local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLightServer"
local ArrowBoard = require "RenewableEnergy/World/ArrowBoardPower"
local Clock = require "cf_commonlib/Clock"

local GadgetCharging = {}
RenewableEnergy.GadgetCharging = GadgetCharging

-- Longest stretch one pass makes up for, since it charges at the sun of the moment.
local LONGEST_PASS = 1

-- The last pass's world age in hours, unsaved: the first pass after loading makes up nothing.
local clock = {}

function GadgetCharging.chargeVehicles(hours)
    local sky = Sun.skyNow()
    -- IsoCell.getVehicles is a Set, which only an iterator walks.
    local vehicles = getCell():getVehicles():iterator()
    while vehicles:hasNext() do
        local vehicle = vehicles:next()
        SolarMaintainer.charge(vehicle, hours, sky)
        ArrowBoard.update(vehicle, hours, sky)
    end
end

-- EveryTenMinutes fires at most once a tick however much game time passed, so the pass
-- measures the time itself.
function GadgetCharging.update()
    local hours = Clock.hoursSince(clock, LONGEST_PASS)
    if hours <= 0 then
        return
    end
    GadgetCharging.chargeVehicles(hours)
    SolarCellCharger.chargeAll(hours)
    SolarGardenLight.updateAll(hours)
end

Events.EveryTenMinutes.Add(GadgetCharging.update)

return GadgetCharging
