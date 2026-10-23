-- Sunlight on a solar panel: where the sun is, how much the weather lets through, and what a
-- panel on each mount makes of it. The pure functions take every input as an argument so tests
-- can integrate a whole year without moving the game clock.

require "RenewableEnergy/Specs"

RenewableEnergy = RenewableEnergy or {}
local Sun = {}
RenewableEnergy.Sun = Sun

local Specs = RenewableEnergy.Specs
local rad, sin, cos, tan, acos, max, min = math.rad, math.sin, math.cos, math.tan, math.acos, math.max, math.min

-- Clear-sky light on a horizontal surface with the sun overhead (panels are rated at it), and an
-- exponent fit to clear-sky models that stands in for air mass.
Sun.FULL_SUN = 1000
local FULL_SUN = Sun.FULL_SUN
local AIR_MASS_EXPONENT = 1.15
-- Share of clear-sky light from the whole sky rather than the sun's disc; tuned with the cloud
-- weighting so flat, wall and rack yearly output compare as measured insolation does.
local CLEAR_DIFFUSE = 0.15
-- The share of the light that full cloud, fog or rain stops. What gets through cloud is all diffuse.
local CLOUD_LOSS = 0.75
local FOG_LOSS = 0.3
local RAIN_LOSS = 0.3
local SNOWFALL_FACTOR = 0.5
-- Ground reflection: grass and soil, and fresh snow, which lifts a wall panel's winter output.
local GROUND_ALBEDO = 0.2
local SNOW_ALBEDO = 0.7
-- The share of a panel's rating the bank stores after wiring, dust, mismatch, controller and
-- battery charging losses.
local SYSTEM_EFFICIENCY = 0.8

-- Weather without cloud, fog, rain or snow.
Sun.CLEAR_WEATHER = { cloud = 0, fog = 0, rain = 0, snowing = false, groundSnow = 0 }

-- Horizontal unit vectors (east, north) a panel facing each way leans towards.
local FACINGS = { S = { 0, -1 }, N = { 0, 1 }, E = { 1, 0 }, W = { -1, 0 } }

-- Each mount's tilt from flat as { sine, cosine }, which every irradiance sum needs.
local TILTS = {}
for kind, mount in pairs(Specs.mounts) do
    local tilt = rad(mount.tilt)
    TILTS[kind] = { sin(tilt), cos(tilt) }
end

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
    local horizontal = FULL_SUN * sun.up ^ AIR_MASS_EXPONENT
    horizontal = horizontal * (1 - CLOUD_LOSS * weather.cloud) * (1 - FOG_LOSS * weather.fog) * (1 - RAIN_LOSS * weather.rain)
    if weather.snowing then
        horizontal = horizontal * SNOWFALL_FACTOR
    end
    local diffuseShare = CLEAR_DIFFUSE + (1 - CLEAR_DIFFUSE) * weather.cloud
    local diffuse = horizontal * diffuseShare
    local direct = horizontal * (1 - diffuseShare) / sun.up

    local tilt = TILTS[kind]
    local sinTilt, cosTilt = tilt[1], tilt[2]
    local lean = FACINGS[facing] or FACINGS.S
    local incidence = sun.east * sinTilt * lean[1] + sun.north * sinTilt * lean[2] + sun.up * cosTilt
    local albedo = GROUND_ALBEDO + (SNOW_ALBEDO - GROUND_ALBEDO) * weather.groundSnow
    return direct * max(0, incidence) + diffuse * (1 + cosTilt) / 2 + horizontal * albedo * (1 - cosTilt) / 2
end

--- Watts a panel rated `ratedWatts` makes in `irradiance`, under `snow` cover from 0 to 1.
function Sun.wattsFrom(ratedWatts, irradiance, snow)
    local watts = ratedWatts * irradiance / FULL_SUN * SYSTEM_EFFICIENCY
        * SandboxVars.RenewableEnergy.SunlightMultiplier * (1 - (snow or 0))
    return max(0, watts)
end

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

--- The sun now as a flat cell sees it, { up, flat }: the sun's `up` as Sun.position gives it,
--- below 0 at night, and `flat`, the light on open flat ground in W/m², weather included. A pass
--- over many gadgets works it out once.
function Sun.skyNow()
    local sun = Sun.positionNow()
    return { up = sun.up, flat = Sun.planeIrradiance(sun, "flat", nil, Sun.weatherNow()) }
end

--- Watts a flat cell rated `ratedWatts` lying on `square` makes under `sky` (Sun.skyNow, now
--- if nil): none under a roof or for no square.
function Sun.squareWatts(square, ratedWatts, sky)
    if not (square and square:isOutside()) then
        return 0
    end
    return Sun.wattsFrom(ratedWatts, (sky or Sun.skyNow()).flat, 0)
end

--- Whether it is dark under `sky` (Sun.skyNow or Sun.positionNow, now if nil): the sun at or
--- below the horizon, when a photocell switches its lamp on.
function Sun.isDark(sky)
    return (sky or Sun.positionNow()).up <= 0
end

return Sun
