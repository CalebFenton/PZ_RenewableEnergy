-- Sunlight on a solar panel: where the sun is, how much of it the weather lets through, and
-- what a panel on each mount makes of it (design §2.1, §2.2, §4).
--
-- The pure functions take every input as an argument, so the tests can integrate a whole
-- year without moving the game clock. The `...Now` functions read the game's clock and
-- weather.

local Specs = require "RenewableEnergy/Specs"

local Sun = {}
RenewableEnergy.Sun = Sun

local rad, sin, cos, tan, acos, max, min = math.rad, math.sin, math.cos, math.tan, math.acos, math.max, math.min

-- Clear-sky light on a horizontal surface at a sun overhead, and how much it thins as the
-- sun drops (a fit to clear-sky models that stands in for air mass). Panels are rated at it.
local CLEAR_SKY = 1000
Sun.FULL_SUN = CLEAR_SKY
local AIR_MASS_EXPONENT = 1.15
-- The share of clear-sky light that comes from the whole sky rather than the sun's disc.
-- With the cloud weighting below it puts a year's flat and south-wall output against a
-- 38° rack where Louisville's measured insolation does (RenewableEnergyTestsPower checks).
local CLEAR_DIFFUSE = 0.15
-- Overcast still lets about a quarter through, all of it diffuse.
local CLOUD_LOSS = 0.75
local FOG_LOSS = 0.3
local RAIN_LOSS = 0.3
local SNOWFALL_FACTOR = 0.5
-- Ground reflection: grass and soil, and fresh snow, which lifts a wall panel's winter output.
local GROUND_ALBEDO = 0.2
local SNOW_ALBEDO = 0.7
-- Wiring, dust, mismatch, controller and battery charging losses between the panel's
-- rating and what the bank stores.
local SYSTEM_LOSSES = 0.8

-- Weather without cloud, fog, rain or snow.
Sun.CLEAR_WEATHER = { cloud = 0, fog = 0, rain = 0, snowing = false, groundSnow = 0 }

-- Horizontal unit vectors (east, north) a panel facing each way leans towards.
local FACINGS = { S = { 0, -1 }, N = { 0, 1 }, E = { 1, 0 }, W = { -1, 0 } }

local DAYS_BEFORE_MONTH = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }

--- Day of the year, 1 to 365, from the game's 0-based month and day.
function Sun.dayOfYear(month, day)
    return DAYS_BEFORE_MONTH[month + 1] + day + 1
end

local function declination(dayOfYear)
    return rad(23.44) * sin(rad(360 / 365 * (284 + dayOfYear)))
end

--- Hours from solar noon to sunset at a latitude on a day; 0 in polar night.
function Sun.halfDayHours(dayOfYear, latitude)
    local cosine = -tan(rad(latitude)) * tan(declination(dayOfYear))
    return math.deg(acos(max(-1, min(1, cosine)))) / 15
end

--- The direction of the sun as a unit vector: east, north, up.
---@param dayOfYear number
---@param hoursFromNoon number solar hours, negative in the morning
---@param latitude number degrees north
function Sun.position(dayOfYear, hoursFromNoon, latitude)
    local delta, phi, h = declination(dayOfYear), rad(latitude), rad(15 * hoursFromNoon)
    return {
        east = -cos(delta) * sin(h),
        north = cos(phi) * sin(delta) - sin(phi) * cos(delta) * cos(h),
        up = sin(phi) * sin(delta) + cos(phi) * cos(delta) * cos(h),
    }
end

--- Light falling on a panel, in W/m².
---@param sun table Sun.position
---@param kind string "flat", "wall" or "rack" (Specs.mounts)
---@param facing string? "S", "E", "N" or "W"; ignored for flat panels
---@param weather table { cloud, fog, rain, snowing, groundSnow }, each 0 to 1 (snowing a boolean)
function Sun.planeIrradiance(sun, kind, facing, weather)
    if sun.up <= 0 then
        return 0
    end
    local horizontal = CLEAR_SKY * sun.up ^ AIR_MASS_EXPONENT
    horizontal = horizontal * (1 - CLOUD_LOSS * weather.cloud) * (1 - FOG_LOSS * weather.fog) * (1 - RAIN_LOSS * weather.rain)
    if weather.snowing then
        horizontal = horizontal * SNOWFALL_FACTOR
    end
    local diffuseShare = CLEAR_DIFFUSE + (1 - CLEAR_DIFFUSE) * weather.cloud
    local diffuse = horizontal * diffuseShare
    local direct = horizontal * (1 - diffuseShare) / sun.up

    local tilt = rad(Specs.mounts[kind].tilt)
    local lean = FACINGS[facing] or FACINGS.S
    local incidence = sun.east * sin(tilt) * lean[1] + sun.north * sin(tilt) * lean[2] + sun.up * cos(tilt)
    local albedo = GROUND_ALBEDO + (SNOW_ALBEDO - GROUND_ALBEDO) * weather.groundSnow
    return direct * max(0, incidence) + diffuse * (1 + cos(tilt)) / 2 + horizontal * albedo * (1 - cos(tilt)) / 2
end

--- Watts a panel rated `ratedWatts` makes in `irradiance`, under `snow` cover from 0 to 1.
function Sun.wattsFrom(ratedWatts, irradiance, snow)
    local watts = ratedWatts * irradiance / CLEAR_SKY * SYSTEM_LOSSES
        * SandboxVars.RenewableEnergy.SunlightMultiplier * (1 - (snow or 0))
    return max(0, watts)
end

-- Game clock and weather ------------------------------------------------------------------

--- The weather the panels see now.
function Sun.weatherNow()
    local climate = getClimateManager()
    return {
        cloud = climate:getCloudIntensity(),
        fog = climate:getFogIntensity(),
        rain = climate:getRainIntensity(),
        snowing = climate:isSnowing(),
        groundSnow = climate:getSnowFracNow(),
    }
end

--- The sun `hoursAgo` game hours before now.
---
--- The game draws its own dawn and dusk from the season (ErosionSeason: noon shifts through
--- the year, day length runs between the solstices'). The game hour is stretched onto the
--- solar hour so that the sun rises and sets exactly when the sky brightens and darkens.
function Sun.positionNow(hoursAgo)
    local time = getGameTime()
    local season = getClimateManager():getSeason()
    local dayOfYear = Sun.dayOfYear(time:getMonth(), time:getDay())
    local latitude = season:getLat()
    local gameHalfDay = season:getDaylight() / 2
    local hoursFromNoon = time:getTimeOfDay() - (hoursAgo or 0) - season:getDayHighNoon()
    if hoursFromNoon < -12 then
        hoursFromNoon = hoursFromNoon + 24
    end
    if gameHalfDay <= 0 then
        return Sun.position(dayOfYear, 12, latitude)
    end
    return Sun.position(dayOfYear, hoursFromNoon * Sun.halfDayHours(dayOfYear, latitude) / gameHalfDay, latitude)
end

--- The sun's height above the horizon now, in degrees.
function Sun.elevation()
    return math.deg(math.asin(max(-1, min(1, Sun.positionNow().up))))
end

--- Light on a panel now, in W/m², weather included.
function Sun.irradiance(kind, facing)
    return Sun.planeIrradiance(Sun.positionNow(), kind, facing, Sun.weatherNow())
end

--- Watts a panel rated `ratedWatts` on a `kind` mount facing `facing` makes now, under
--- `snow` cover from 0 to 1.
function Sun.panelWatts(ratedWatts, kind, facing, snow)
    return Sun.wattsFrom(ratedWatts, Sun.irradiance(kind, facing), snow)
end

--- Light on a flat surface on `square` now, in W/m²: 0 under a roof or for no square.
function Sun.squareIrradiance(square)
    if not (square and square:isOutside()) then
        return 0
    end
    return Sun.irradiance("flat")
end

--- Watts a flat cell rated `ratedWatts` lying on `square` makes now.
function Sun.squareWatts(square, ratedWatts)
    return Sun.wattsFrom(ratedWatts, Sun.squareIrradiance(square), 0)
end

return Sun
