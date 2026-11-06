-- Text for the status windows, the menus and the item tooltips. Each unit is a translation with
-- the number as %1, as vanilla's IGUI_CraftUI_CountLitres is: Russian writes "95 Вт", Chinese
-- "15 升". Decimals use a point, as vanilla's string.format numbers do.

local Items = require "cf_commonlib/Items"

local Format = {}

-- Whole units below a thousand, then one decimal: "95 W", "1.5 kW". Real 1993 setups run from
-- tens of watts to a few kilowatts, so both ends stay readable.
local function scaled(value, unitKey, kiloUnitKey)
    local magnitude = math.abs(value)
    if magnitude >= 1000 then
        return getText(kiloUnitKey, string.format("%.1f", value / 1000))
    end
    return getText(unitKey, string.format("%d", round(value)))
end

function Format.watts(watts)
    return scaled(watts or 0, "IGUI_RenewableEnergy_Watts", "IGUI_RenewableEnergy_Kilowatts")
end

function Format.wattHours(wattHours)
    return scaled(wattHours or 0, "IGUI_RenewableEnergy_WattHours", "IGUI_RenewableEnergy_KilowattHours")
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

-- "18 °C" or "64 °F", as the player's options show temperatures, with vanilla's unit.
function Format.temperature(celsius)
    return Temperature.getRoundedDisplayTemperature(celsius) .. " " .. Temperature.getTemperaturePostfix()
end

-- `value` with `places` decimals: "1.5".
function Format.number(value, places)
    return string.format("%." .. places .. "f", value)
end

-- "2.5 kg" of fuel, to a tenth.
function Format.kilograms(kg)
    return getText("IGUI_RenewableEnergy_Kilograms", Format.number(kg, 1))
end

-- "15 L", in whole litres.
function Format.litres(litres)
    return getText("IGUI_RenewableEnergy_Litres", Format.number(litres, 0))
end

-- "1.25 m³", to a hundredth. The symbol comes from a translation, which is read as UTF-8:
-- the Lua compiler turns any non-ASCII character in a literal into "?" (Kahlua's LexState keeps
-- each source character as one byte, then decodes the bytes as UTF-8).
function Format.cubicMetres(m3)
    return getText("IGUI_RenewableEnergy_CubicMetres", Format.number(m3, 2))
end

-- An item's condition as a share of its type's ConditionMax (vanilla's default when the script
-- names none, as for the Car Battery Charger).
function Format.conditionShare(fullType, condition)
    return condition / Items.conditionMaxOf(fullType)
end

-- "72%": an item's or a record's condition (Format.conditionShare).
function Format.condition(fullType, condition)
    return Format.percent(Format.conditionShare(fullType, condition))
end

-- "64%": a vehicle part's condition, which runs from 0 to 100 whatever its item's ConditionMax, as
-- vanilla's mechanics window shows it.
function Format.partCondition(part)
    return Format.percent(part:getCondition() / 100)
end

-- "Get Compost (45%)": a name with a 0..1 share after it, as vanilla labels a bag by its fill or a
-- part by its condition.
function Format.withShare(name, share)
    return getText("ContextMenu_RenewableEnergy_WithShare", name, Format.percent(share))
end

-- "Car Battery (72%)": an item by its name and condition.
function Format.itemCondition(item)
    return Format.withShare(item:getDisplayName(), Format.conditionShare(item:getFullType(), item:getCondition()))
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

-- "3 hours" or "45 minutes" for a duration in hours, in whole units of the largest unit that is at
-- least one, except that hours run on through the second day. The rate the duration comes from
-- changes from hour to hour, so finer detail would mislead.
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

--- "30 W, 25 km/h": what wind chargers make in the bank's wind, in whole km/h.
function Format.windOutput(watts, kph)
    return getText("IGUI_RenewableEnergy_WindOutput", Format.watts(watts), string.format("%d", round(kph or 0)))
end

--- A bank's name from its summary or status: the one a player gave it, else its tier's.
function Format.bankName(summary)
    return summary.name or getItemNameFromFullType(summary.bankType)
end

--- The name of a placed tile: the item it is (CustomItem), which picking it up gives back, else
--- its moveable's name (CustomName, Moveables.json), as a wind charger has.
function Format.tileName(isoObject)
    local properties = isoObject:getProperties()
    local item = properties:get("CustomItem")
    if item then
        return getItemNameFromFullType(item)
    end
    return Translator.getMoveableDisplayName(properties:get("CustomName"))
end

return Format
