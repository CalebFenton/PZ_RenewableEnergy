---@class RenewableEnergy
require "RenewableEnergy/Utilities"

-- Number formatting for the status window, the menus and the battery tooltip. Unit symbols are SI
-- and the same in every language, so they are not translated.
local Format = {}

-- Whole units below a thousand, then one decimal: "95 W", "1.5 kW". Real 1993 setups run from
-- tens of watts to a few kilowatts, so both ends stay readable.
local function scaled(value, unit, kiloUnit)
    local magnitude = math.abs(value)
    if magnitude >= 1000 then
        return string.format("%.1f %s", value / 1000, kiloUnit)
    end
    return string.format("%d %s", round(value), unit)
end

function Format.watts(watts)
    return scaled(watts or 0, "W", "kW")
end

function Format.wattHours(wattHours)
    return scaled(wattHours or 0, "Wh", "kWh")
end

-- With an explicit sign, for flows into (+) and out of (-) the bank.
function Format.signedWatts(watts)
    watts = watts or 0
    local text = Format.watts(watts)
    if round(watts) > 0 then
        return "+" .. text
    end
    return text
end

-- A 0..1 fraction as "64%".
function Format.percent(fraction)
    return string.format("%d%%", round((fraction or 0) * 100))
end

-- A multiplier as the change it makes: 0.86 is "-14%", 1.04 is "+4%".
function Format.change(factor)
    local delta = round(((factor or 1) - 1) * 100)
    if delta > 0 then
        return "+" .. delta .. "%"
    end
    return delta .. "%"
end

-- In the player's chosen scale, as the game's own thermometers show it.
function Format.temperature(celsius)
    return Temperature.getRoundedDisplayTemperature(celsius) .. " " .. Temperature.getTemperaturePostfix()
end

-- Vanilla translates both forms of each unit into every language.
local UNITS = {
    day = { "IGUI_Gametime_day", "IGUI_Gametime_days" },
    hour = { "IGUI_Gametime_hour", "IGUI_Gametime_hours" },
    minute = { "IGUI_Gametime_minute", "IGUI_Gametime_minutes" },
}

local function amount(count, unit)
    return count .. " " .. getText(UNITS[unit][count == 1 and 1 or 2])
end

-- "3 hours" or "45 minutes" for a duration in hours: the largest unit that is at least one,
-- since the rate it comes from changes from hour to hour anyway.
function Format.duration(hours)
    if hours >= 48 then
        return amount(math.floor(hours / 24), "day")
    elseif hours >= 1 then
        return amount(math.floor(hours), "hour")
    end
    return amount(math.max(1, math.floor(hours * 60)), "minute")
end

local COMPASS = {
    N = "IGUI_RenewableEnergy_Compass_N",
    NE = "IGUI_RenewableEnergy_Compass_NE",
    E = "IGUI_RenewableEnergy_Compass_E",
    SE = "IGUI_RenewableEnergy_Compass_SE",
    S = "IGUI_RenewableEnergy_Compass_S",
    SW = "IGUI_RenewableEnergy_Compass_SW",
    W = "IGUI_RenewableEnergy_Compass_W",
    NW = "IGUI_RenewableEnergy_Compass_NW",
}

-- "north-east" for "NE".
function Format.compass(point)
    return getText(COMPASS[point])
end

-- A vehicle's name as vanilla shows it, from its script's car model name.
function Format.vehicleName(modelName)
    local key = "IGUI_VehicleName" .. modelName
    return getText(key)
end

RenewableEnergy.Format = Format
return Format
