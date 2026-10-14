-- Text for the status window, the menus and the battery tooltip. Unit symbols are SI and the
-- same in every language, so they are not translated.

RenewableEnergy = RenewableEnergy or {}
local Format = {}
RenewableEnergy.Format = Format

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

-- "72%": an item's condition as a share of its type's ConditionMax, which is 10 for an item
-- whose script names none, such as vanilla's Car Battery Charger.
function Format.condition(fullType, condition)
    return Format.percent(condition / getScriptManager():FindItem(fullType):getConditionMax())
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

-- Compass points clockwise from north, in eighths. +x is east and +y is south in the world.
local COMPASS = {
    "IGUI_RenewableEnergy_Compass_N",
    "IGUI_RenewableEnergy_Compass_NE",
    "IGUI_RenewableEnergy_Compass_E",
    "IGUI_RenewableEnergy_Compass_SE",
    "IGUI_RenewableEnergy_Compass_S",
    "IGUI_RenewableEnergy_Compass_SW",
    "IGUI_RenewableEnergy_Compass_W",
    "IGUI_RenewableEnergy_Compass_NW",
}

--- "6 tiles north-east": where `to` is from `from`, both { x, y }.
function Format.away(from, to)
    local dx, dy = to.x - from.x, to.y - from.y
    local tiles = round(math.sqrt(dx * dx + dy * dy))
    if tiles == 0 then
        return getText("IGUI_RenewableEnergy_Here")
    end
    -- Kahlua's % truncates toward zero (KahluaThread.primitiveMath), so a negative eighth
    -- would stay negative; the added turn keeps it in 0..7.
    local eighth = (math.floor(math.deg(math.atan2(dx, -dy)) / 45 + 0.5) + 8) % 8
    local key = tiles == 1 and "IGUI_RenewableEnergy_AwayOne" or "IGUI_RenewableEnergy_Away"
    return getText(key, tiles, getText(COMPASS[eighth + 1]))
end

--- A bank's name from its summary or status: the one a player gave it, else its tier's.
function Format.bankName(bank)
    return bank.name or getItemNameFromFullType(bank.bankType)
end

return Format
