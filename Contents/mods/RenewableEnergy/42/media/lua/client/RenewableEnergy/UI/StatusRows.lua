-- What the battery bank's status window (StatusWindow) shows of a Bank status snapshot: the
-- summary lines across the top and the rows of its two columns.

require "RenewableEnergy/Recipes"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/UI/Format"

RenewableEnergy = RenewableEnergy or {}
local StatusRows = {}
RenewableEnergy.StatusRows = StatusRows

local Format = RenewableEnergy.Format
local PowerBank, Sources = RenewableEnergy.PowerBank, RenewableEnergy.Sources
local Recipes = RenewableEnergy.Recipes
local Sun = RenewableEnergy.Sun

-- The lines across the top, each { text = text, color = name }.

local function chargingLine(status)
    if status.capacityWh <= 0 then
        return { text = getText("IGUI_RenewableEnergy_NoBatteries"), color = "bad" }
    end
    local watts, hours = status.charging.watts, status.charging.hours
    local shownWatts = round(watts)
    if shownWatts > 0 then
        local text = hours and getText("IGUI_RenewableEnergy_ChargingFullIn", Format.signedWatts(watts), Format.duration(hours))
            or getText("IGUI_RenewableEnergy_Charging", Format.signedWatts(watts))
        return { text = text, color = "good" }
    elseif shownWatts < 0 then
        local text = hours and getText("IGUI_RenewableEnergy_DrainingEmptyIn", Format.signedWatts(watts), Format.duration(hours))
            or getText("IGUI_RenewableEnergy_Draining", Format.signedWatts(watts))
        return { text = text, color = hours and hours < 12 and "bad" or nil }
    end
    return { text = getText("IGUI_RenewableEnergy_NotCharging"), color = "dim" }
end

local function loadLine(status)
    if status.overloaded then
        return { text = getText("IGUI_RenewableEnergy_Overloaded", Format.watts(status.loadW), Format.watts(status.limitW)), color = "bad" }
    elseif status.limitW <= 0 then
        return { text = getText("IGUI_RenewableEnergy_NoWorkingInverter"), color = "bad" }
    end
    return { text = getText("IGUI_RenewableEnergy_LoadOf", Format.watts(status.loadW), Format.watts(status.limitW)) }
end

local function inputSlotsLine(status)
    local slots, controllers = status.inputSlots, #status.controllers
    local text
    if controllers == 0 then
        text = getText("IGUI_RenewableEnergy_InputSlots", slots.used, slots.total)
    elseif controllers == 1 then
        text = getText("IGUI_RenewableEnergy_InputSlotsOneController", slots.used, slots.total)
    else
        text = getText("IGUI_RenewableEnergy_InputSlotsControllers", slots.used, slots.total, controllers)
    end
    return { text = text, color = slots.used > slots.total and "bad" or nil }
end

-- Why a bank that has an inverter and batteries isn't carrying its load; overloads and missing
-- inverters or batteries have their own line.
local STATE_LINES = {
    outdoors = { key = "IGUI_RenewableEnergy_StateOutdoors", color = "bad" },
    disconnected = { key = "IGUI_RenewableEnergy_StateDisconnected", color = "bad" },
    off = { key = "IGUI_RenewableEnergy_StateOff", color = "dim" },
    grid = { key = "IGUI_RenewableEnergy_StateGrid", color = "dim" },
    empty = { key = "IGUI_RenewableEnergy_StateEmpty", color = "bad" },
}

--- The summary lines for a status snapshot.
function StatusRows.summary(status)
    local lines = { chargingLine(status), loadLine(status), inputSlotsLine(status) }
    local state = STATE_LINES[status.state]
    if state then
        table.insert(lines, { text = getText(state.key), color = state.color })
    end
    return lines
end

-- The rows are ObjectWindow's, built from the status alone, so the tests can check them for any
-- bank.

local function header(rows, key, ...)
    if #rows > 0 then
        table.insert(rows, { gap = true })
    end
    table.insert(rows, { header = getText(key, ...) })
end

local function row(rows, label, value, colorName)
    table.insert(rows, { label = label, value = value, color = colorName })
end

-- Each family of source's rows: its watts now and today (the Bank status fields), always for
-- panels and for the others once they have made anything today.
local FAMILY_ROWS = {
    { now = "solarW", today = "solarWhToday", nowKey = "IGUI_RenewableEnergy_PanelsNow",
        todayKey = "IGUI_RenewableEnergy_PanelsToday", always = true },
    { now = "windW", today = "windWhToday", nowKey = "IGUI_RenewableEnergy_WindNow", todayKey = "IGUI_RenewableEnergy_WindToday",
        value = function(status) return Format.windOutput(status.windW, status.windKph) end },
    { now = "runW", today = "runWhToday", nowKey = "IGUI_RenewableEnergy_TreadmillsNow",
        todayKey = "IGUI_RenewableEnergy_TreadmillsToday" },
}

-- Grid power reaching the bank, whatever state the bank is in, and whether its chargers fill the
-- batteries from it: without a charger the grid charges nothing.
local function gridRow(rows, status)
    if not status.gridPowered then
        return
    end
    local label = getText("IGUI_RenewableEnergy_Grid")
    if status.chargerMaxW <= 0 then
        row(rows, label, getText("IGUI_RenewableEnergy_GridNoCharger"), "dim")
    elseif status.chargeSource == "grid" and status.chargerW > 0 then
        row(rows, label, getText("IGUI_RenewableEnergy_GridCharging", Format.watts(status.chargerW)), "good")
    else
        row(rows, label, getText("IGUI_RenewableEnergy_GridOn"))
    end
end

local function powerRows(rows, status)
    header(rows, "IGUI_RenewableEnergy_Power")
    gridRow(rows, status)
    if status.sunElevation > 0 then
        row(rows, getText("IGUI_RenewableEnergy_Sunlight"), Format.percent(status.irradiance / Sun.FULL_SUN))
    else
        row(rows, getText("IGUI_RenewableEnergy_Sunlight"), getText("IGUI_RenewableEnergy_Night"), "dim")
    end
    for _, family in ipairs(FAMILY_ROWS) do
        if family.always or status[family.now] > 0 or status[family.today] > 0 then
            row(rows, getText(family.nowKey), family.value and family.value(status) or Format.watts(status[family.now]))
            row(rows, getText(family.todayKey), Format.wattHours(status[family.today]))
        end
    end
    -- A generator the chargers fill from, as the grid row says it of the grid; it bills them.
    if status.chargeSource == "generator" and status.chargerW > 0 then
        row(rows, getText("IGUI_RenewableEnergy_GeneratorPower"), getText("IGUI_RenewableEnergy_GridCharging",
            Format.watts(status.chargerW)), "good")
    end
    local generator = status.generator
    if generator then
        row(rows, getText("IGUI_RenewableEnergy_Generator"),
            getText(generator.running and "IGUI_RenewableEnergy_GeneratorRunning" or "IGUI_RenewableEnergy_GeneratorStopped"),
            not generator.running and "dim" or nil)
        if generator.failsafe then
            if not generator.controls then
                row(rows, getText("IGUI_RenewableEnergy_Failsafe"), getText("IGUI_RenewableEnergy_FailsafeOtherBank"), "dim")
            elseif not generator.armed then
                row(rows, getText("IGUI_RenewableEnergy_Failsafe"), getText("IGUI_RenewableEnergy_FailsafeIdle"), "dim")
            else
                row(rows, getText("IGUI_RenewableEnergy_Failsafe"), getText("IGUI_RenewableEnergy_FailsafeRange",
                    PowerBank.failsafeRange()))
            end
        end
    end
    row(rows, getText("IGUI_RenewableEnergy_UsedToday"), Format.wattHours(status.loadWhToday))
    -- What the backup generator ran in the bank's place, kept apart so the bank's own figure
    -- tells whether its batteries and sources keep up.
    if status.backupWhToday > 0 then
        row(rows, getText("IGUI_RenewableEnergy_GeneratorToday"), Format.wattHours(status.backupWhToday))
    end
end

local LOAD_KINDS = {
    fridgeFreezer = "IGUI_RenewableEnergy_LoadFridgeFreezer",
    fridge = "IGUI_RenewableEnergy_LoadFridge",
    light = "IGUI_RenewableEnergy_LoadLight",
    television = "IGUI_RenewableEnergy_LoadTelevision",
    radio = "IGUI_RenewableEnergy_LoadRadio",
    microwave = "IGUI_RenewableEnergy_LoadMicrowave",
    range = "IGUI_RenewableEnergy_LoadRange",
    washer = "IGUI_RenewableEnergy_LoadWasher",
    dryer = "IGUI_RenewableEnergy_LoadDryer",
    batteryCharger = "IGUI_RenewableEnergy_LoadBatteryCharger",
    treadmill = "IGUI_RenewableEnergy_Treadmill",
    other = "IGUI_RenewableEnergy_LoadOther",
}

-- "TV" or "Lights (3)": a kind of load from Bank status `loadByKind`. Another mod's kind is its own
-- translation key (Loads.addConsumer).
local function loadLabel(entry)
    local key = LOAD_KINDS[entry.kind] or (entry.kind:find("^IGUI_") and entry.kind) or LOAD_KINDS.other
    local name = getText(key)
    if entry.count > 1 then
        return getText("IGUI_RenewableEnergy_LoadCount", name, entry.count)
    end
    return name
end

local function loadRows(rows, status)
    header(rows, "IGUI_RenewableEnergy_Drawing")
    if #status.loadByKind == 0 then
        row(rows, getText("IGUI_RenewableEnergy_NothingOn"), "", "dim")
        return
    end
    for _, entry in ipairs(status.loadByKind) do
        row(rows, loadLabel(entry), Format.watts(entry.watts))
    end
end

local function storageRows(rows, status)
    header(rows, "IGUI_RenewableEnergy_Storage")
    if #status.batteries == 0 then
        row(rows, getText("IGUI_RenewableEnergy_Stored"), getText("IGUI_RenewableEnergy_NoBatteries"), "bad")
        return
    end
    table.insert(rows, { bar = status.charge })
    row(rows, getText("IGUI_RenewableEnergy_Stored"), Format.wattHours(status.storedWh) .. " / " .. Format.wattHours(status.capacityWh)
        .. " (" .. Format.percent(status.charge) .. ")")
    row(rows, getText("IGUI_RenewableEnergy_CycleDepth"), Format.percent(status.cycleDepth))
end

local CHARGING_FROM = {
    grid = "IGUI_RenewableEnergy_ChargingFromGrid",
    generator = "IGUI_RenewableEnergy_ChargingFromGenerator",
}

-- "84%, working" or "0%, broken": a part from Bank status `inverters`, `controllers` or
-- `chargers`, and its color.
local function partValue(part)
    local condition = Format.condition(part.type, part.condition)
    if not part.working then
        return getText("IGUI_RenewableEnergy_PartBroken", condition), "bad"
    elseif part.charging then
        return getText("IGUI_RenewableEnergy_PartState", condition, getText(CHARGING_FROM[part.charging])), "good"
    end
    return getText("IGUI_RenewableEnergy_PartState", condition, getText("IGUI_RenewableEnergy_Working")), nil
end

local function partRows(rows, status)
    header(rows, "IGUI_RenewableEnergy_Parts")
    local count = 0
    for _, list in ipairs({ status.inverters, status.controllers, status.chargers }) do
        for _, part in ipairs(list) do
            row(rows, getItemNameFromFullType(part.type), partValue(part))
            count = count + 1
        end
    end
    if count == 0 then
        row(rows, getText("IGUI_RenewableEnergy_NoParts"), "", "bad")
    end
end

-- The repair that makes the most of one of a battery's limited repairs, or nil for one in perfect
-- shape: Service where its step reaches the repair limit anyway (it keeps the charge),
-- Recondition further below it, and past the limit only a rebuild.
local function batteryRepair(condition, repaired)
    local limit = Recipes.repairLimit(repaired or 0)
    if condition < limit then
        return condition + Recipes.SERVICE_REPAIR >= limit and "IGUI_RenewableEnergy_RepairService"
            or "IGUI_RenewableEnergy_RepairRecondition"
    elseif condition < 100 then
        return "IGUI_RenewableEnergy_RepairRebuild"
    end
end

-- "64% charged, 72% condition (recondition)": a battery from Bank status `batteries`.
local function batteryValue(battery)
    local charge, condition = Format.percent(battery.charge), Format.condition(battery.type, battery.condition)
    local repair = batteryRepair(battery.condition, battery.repaired)
    if repair then
        return getText("IGUI_RenewableEnergy_BatteryValueRepair", charge, condition, getText(repair))
    end
    return getText("IGUI_RenewableEnergy_BatteryValue", charge, condition)
end

local function batteryRows(rows, status)
    header(rows, "IGUI_RenewableEnergy_Batteries", #status.batteries)
    for _, battery in ipairs(status.batteries) do
        row(rows, getItemNameFromFullType(battery.type), batteryValue(battery), battery.condition <= 0 and "bad" or nil)
    end
end

-- Sources by kind and material (Bank status `sources`): panels by mount and material, wind
-- chargers by kind, and the treadmill.
local SOURCE_NAMES = {
    flat = "IGUI_RenewableEnergy_MountFlat",
    wallwood = "IGUI_RenewableEnergy_MountWallWood",
    wallmetal = "IGUI_RenewableEnergy_MountWallMetal",
    rackwood = "IGUI_RenewableEnergy_MountRackWood",
    rackmetal = "IGUI_RenewableEnergy_MountRackMetal",
    scoop = "IGUI_RenewableEnergy_WindScoop",
    propeller = "IGUI_RenewableEnergy_WindTreadmill",
    carAlternator = "IGUI_RenewableEnergy_WindCarAlternator",
    alternator = "IGUI_RenewableEnergy_WindTurbine",
    treadmill = "IGUI_RenewableEnergy_Treadmill",
}

-- Why a source makes less than it could (Bank status `reason`), and whether the player can do
-- something about it.
local REASONS = {
    night = { key = "IGUI_RenewableEnergy_ReasonNight" },
    cloud = { key = "IGUI_RenewableEnergy_ReasonCloud" },
    angle = { key = "IGUI_RenewableEnergy_ReasonAngle" },
    snow = { key = "IGUI_RenewableEnergy_ReasonSnow", fixable = true },
    cracked = { key = "IGUI_RenewableEnergy_ReasonCracked", fixable = true },
    noController = { key = "IGUI_RenewableEnergy_ReasonNoController", fixable = true },
    braked = { key = "IGUI_RenewableEnergy_ReasonBraked", fixable = true },
    broken = { key = "IGUI_RenewableEnergy_ReasonBroken", fixable = true },
    gale = { key = "IGUI_RenewableEnergy_ReasonGale", fixable = true },
    calm = { key = "IGUI_RenewableEnergy_ReasonCalm" },
    furled = { key = "IGUI_RenewableEnergy_ReasonFurled" },
    sheltered = { key = "IGUI_RenewableEnergy_ReasonSheltered", fixable = true },
    crowded = { key = "IGUI_RenewableEnergy_ReasonCrowded", fixable = true },
    idle = { key = "IGUI_RenewableEnergy_ReasonIdle" },
}

-- "Wooden rack, 6 tiles north-east": a source from Bank status `sources`, from the bank at
-- `bankPosition`.
local function sourceLabel(source, bankPosition)
    local name = SOURCE_NAMES[source.kind .. (source.material or "")]
    return getText("IGUI_RenewableEnergy_SourceWhere", getText(name), Format.away(bankPosition, source))
end

-- A source's output, by family: a panel's with its share of full sun, a wind charger's with the
-- bank's wind.
local OUTPUTS = {
    panel = function(source)
        return getText("IGUI_RenewableEnergy_PanelOutput", Format.watts(source.watts), source.fullSunPct)
    end,
    wind = function(source, status) return Format.windOutput(source.watts, status.windKph) end,
    treadmill = function(source) return Format.watts(source.watts) end,
}

-- "45 W, 64% sun, cloudy", "30 W, 25 km/h" or "75 W" for a source of the bank `status`, and its
-- color.
local function sourceValue(source, status)
    local value = OUTPUTS[Sources.familyOf(source.kind)](source, status)
    local reason = REASONS[source.reason]
    if not reason then
        return value, nil
    end
    return getText("IGUI_RenewableEnergy_SourceOutputReason", value, getText(reason.key)), reason.fixable and "bad" or "dim"
end

local function sourceRows(rows, status, bankPosition)
    header(rows, "IGUI_RenewableEnergy_Sources", #status.sources)
    for _, source in ipairs(status.sources) do
        local value, colorName = sourceValue(source, status)
        table.insert(rows, { label = sourceLabel(source, bankPosition), value = value, color = colorName, source = source })
    end
end

--- The rows of both columns for a status snapshot of the bank at `bankPosition` ({ x, y, z }).
function StatusRows.rows(status, bankPosition)
    local left, right = {}, {}
    powerRows(left, status)
    loadRows(left, status)
    storageRows(left, status)
    partRows(left, status)
    batteryRows(right, status)
    sourceRows(right, status, bankPosition)
    return left, right
end

return StatusRows
