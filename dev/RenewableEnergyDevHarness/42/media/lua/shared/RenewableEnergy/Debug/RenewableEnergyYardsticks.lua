-- Development only. The yardsticks the tests and the --loot town report measure power against:
-- a guessed weather mix, the south-facing mounts, vanilla's appliance draws, and a day of sun
-- added up over them.

local Specs = require "RenewableEnergy/Specs"
local Sun = require "RenewableEnergy/Sun"

local Yardsticks = {}

--- Weather as Sun.planeIrradiance takes it, with no fog, rain or snow, and `cloud` cover from 0
--- to 1.
function Yardsticks.cloudy(cloud)
    return { cloud = cloud, fog = 0, rain = 0, snowing = false, groundSnow = 0 }
end

--- A guessed mix of clear, broken and overcast days: { share, weather } rows.
Yardsticks.WEATHER_MIX = {
    { 0.4, Sun.CLEAR_WEATHER },
    { 0.3, Yardsticks.cloudy(0.5) },
    { 0.3, Yardsticks.cloudy(1) },
}

--- The mounts the light is measured on, by name: Sun.planeIrradiance's kind and facing.
Yardsticks.SOUTH_MOUNTS = { flat = { "flat" }, rack = { "rack", "S" }, wall = { "wall", "S" } }

-- Vanilla's generator fuel an hour for each appliance kind (IsoGenerator's *PowerConsumption
-- constants).
Yardsticks.APPLIANCE_FUEL = {
    fridgeFreezer = 0.13, fridge = 0.08, light = 0.002, television = 0.03, radio = 0.01,
    microwave = 0.09, range = 0.09, washer = 0.09, dryer = 0.09, batteryCharger = 0.05,
}

--- The watts an appliance of the kind `name` (an APPLIANCE_FUEL key) draws as a bank bills it.
function Yardsticks.applianceWatts(name)
    return Specs.wattsFromFuel(Yardsticks.APPLIANCE_FUEL[name])
end

--- Light on `mount` (a SOUTH_MOUNTS row) over the day `dayOfYear` at `latitude`, in W·h/m²: the
--- irradiance at the middle of each `step` hours, weighted by the { share, weather } rows of
--- `weather` (WEATHER_MIX's shape).
function Yardsticks.dayIrradiance(dayOfYear, mount, weather, latitude, step)
    local total = 0
    for hour = -12, 12 - step, step do
        local sun = Sun.position(dayOfYear, hour + step / 2, latitude)
        for _, part in ipairs(weather) do
            total = total + part[1] * Sun.planeIrradiance(sun, mount[1], mount[2], part[2]) * step
        end
    end
    return total
end

return Yardsticks
