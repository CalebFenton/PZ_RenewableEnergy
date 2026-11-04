-- What the battery bank's status window (StatusWindow) shows of a Bank status snapshot: the
-- summary lines across the top and the rows of its two columns.

local Sun = require "RenewableEnergy/Sun"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local Format = require "RenewableEnergy/UI/Format"

local StatusRows = {}

-- The lines across the top, each { text = text, color = name }.

local function chargingLine(status)
    if status.capacityWh <= 0 then
        return { text = getText("IGUI_RenewableEnergy_NoBatteries"), color = "bad" }
    end
    local watts, hours = status.charging.watts, status.charging.hours
    local shownWatts = round(watts)
    if shownWatts > 0 then
        -- Charging with no time to full: the batteries are full, and the surplus goes to waste.
        local text = hours and getText("IGUI_RenewableEnergy_ChargingFullIn", Format.signedWatts(watts), Format.duration(hours))
            or getText("IGUI_RenewableEnergy_FullSpare", Format.watts(watts))
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
        local elsewhere = status.loadElsewhere
        local text = elsewhere
            and getText("IGUI_RenewableEnergy_OverloadedElsewhere", Format.watts(status.loadW), Format.watts(status.limitW),
                Format.watts(elsewhere.watts))
            or getText("IGUI_RenewableEnergy_Overloaded", Format.watts(status.loadW), Format.watts(status.limitW))
        return { text = text, color = "bad" }
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

-- How a family's watts now read, where not plain watts (Sources.FAMILIES).
local NOW_VALUE = {
    wind = function(status) return Format.windOutput(status.windW, status.windKph) end,
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
    for _, family in ipairs(Sources.FAMILIES) do
        if family.always or status[family.now] > 0 or status[family.today] > 0 then
            local value = NOW_VALUE[family.name]
            row(rows, getText(family.nowKey), value and value(status) or Format.watts(status[family.now]))
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

-- "Lights ×3": the name of `count` things of a kind, plain for one.
local function counted(name, count)
    if count > 1 then
        return getText("IGUI_RenewableEnergy_Count", name, count)
    end
    return name
end

-- "TV" or "Lights ×3": a kind of load from Bank status `loadByKind` or `loadElsewhere.byKind`.
-- Another mod's kind is its own translation key (GeneratorReach.addDraw).
local function loadLabel(entry)
    local key = LOAD_KINDS[entry.kind] or (entry.kind:find("^IGUI_") and entry.kind) or LOAD_KINDS.other
    return counted(getText(key), entry.count)
end

-- `list` split by `nameOf(entry)`, as { name, entries } in the order each name first appears.
local function groupBy(list, nameOf)
    local groups, byName = {}, {}
    for _, entry in ipairs(list) do
        local name = nameOf(entry)
        local group = byName[name]
        if not group then
            group = { name = name, entries = {} }
            byName[name] = group
            table.insert(groups, group)
        end
        table.insert(group.entries, entry)
    end
    return groups
end

local function kindRows(rows, byKind)
    if #byKind == 0 then
        row(rows, getText("IGUI_RenewableEnergy_NothingOn"), "", "dim")
    end
    for _, entry in ipairs(byKind) do
        row(rows, loadLabel(entry), Format.watts(entry.watts))
    end
end

-- What the bank pays for by kind. Its reach takes in the neighbours' fridges, as a generator's
-- does, so what stands in other buildings gets a list of its own, headed by how far the nearest
-- is, for the player to know where to switch off or pick up.
local function loadRows(rows, status, bankPosition)
    local elsewhere = status.loadElsewhere
    if not elsewhere then
        header(rows, "IGUI_RenewableEnergy_Drawing")
        kindRows(rows, status.loadByKind)
        return
    end
    header(rows, "IGUI_RenewableEnergy_DrawingHere")
    kindRows(rows, status.loadByKind)
    header(rows, "IGUI_RenewableEnergy_DrawingElsewhere", Format.away(bankPosition, elsewhere))
    kindRows(rows, elsewhere.byKind)
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

-- "64% charged, 72% condition": batteries of one type from Bank status `batteries`, by what they
-- hold together and the most worn of them, and its color.
local function batteryValue(batteries)
    local storedWh, capacityWh, condition = 0, 0, math.huge
    for _, battery in ipairs(batteries) do
        storedWh = storedWh + battery.charge * battery.nominalWh
        capacityWh = capacityWh + battery.nominalWh
        condition = math.min(condition, battery.condition)
    end
    local charge = capacityWh > 0 and storedWh / capacityWh or 0
    local value = getText("IGUI_RenewableEnergy_BatteryValue", Format.percent(charge),
        Format.condition(batteries[1].type, condition))
    return value, condition <= 0 and "bad" or nil
end

local function batteryRows(rows, status)
    header(rows, "IGUI_RenewableEnergy_Batteries", #status.batteries)
    local groups = groupBy(status.batteries, function(battery) return getItemNameFromFullType(battery.type) end)
    for _, group in ipairs(groups) do
        row(rows, counted(group.name, #group.entries), batteryValue(group.entries))
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
    timberPropeller = "IGUI_RenewableEnergy_WindTimberTreadmill",
    timberCarAlternator = "IGUI_RenewableEnergy_WindTimberCarAlternator",
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

local function sourceName(source)
    return getText(SOURCE_NAMES[source.kind .. (source.material or "")])
end

-- "Wooden rack, 6 tiles north-east": a source from Bank status `sources`, from the bank at
-- `bankPosition`.
local function sourceLabel(source, bankPosition)
    return getText("IGUI_RenewableEnergy_SourceWhere", sourceName(source), Format.away(bankPosition, source))
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

-- "45 W, 64% sun, snow", "0 W, 25 km/h, braked" or "0 W, broken" for a source of the bank
-- `status` with its `reason` (REASONS).
local function sourceValue(source, status, reason)
    local value = OUTPUTS[Sources.familyOf(source.kind)](source, status)
    return getText("IGUI_RenewableEnergy_SourceOutputReason", value, getText(reason.key))
end

-- "100 W" for a kind's sources, with "blades 40% left" for the most worn blades among them that
-- still turn, so chargers due new blades show before they break.
local function groupValue(entries)
    local watts, leftPct = 0, nil
    for _, source in ipairs(entries) do
        watts = watts + source.watts
        if source.bladesLeftPct and not source.broken then
            leftPct = math.min(leftPct or 100, source.bladesLeftPct)
        end
    end
    if not leftPct then
        return Format.watts(watts)
    end
    return getText("IGUI_RenewableEnergy_SourceOutputReason", Format.watts(watts),
        getText("IGUI_RenewableEnergy_BladesLeft", leftPct))
end

-- One row per kind of source with their watts together, and after it a red row of its own for each
-- source short for a reason the player can fix, so a cracked module or braked charger stands out
-- of a long list. Each row's `sources` are what clicking it highlights.
local function sourceRows(rows, status, bankPosition)
    header(rows, "IGUI_RenewableEnergy_Sources", #status.sources)
    for _, group in ipairs(groupBy(status.sources, sourceName)) do
        table.insert(rows, { label = counted(group.name, #group.entries), value = groupValue(group.entries),
            sources = group.entries })
        for _, source in ipairs(group.entries) do
            local reason = REASONS[source.reason]
            if reason and reason.fixable then
                table.insert(rows, { label = sourceLabel(source, bankPosition), value = sourceValue(source, status, reason),
                    color = "bad", sources = { source } })
            end
        end
    end
end

--- The rows of both columns for a status snapshot of the bank at `bankPosition` ({ x, y, z }).
function StatusRows.rows(status, bankPosition)
    local left, right = {}, {}
    powerRows(left, status)
    loadRows(left, status, bankPosition)
    storageRows(left, status)
    partRows(left, status)
    batteryRows(right, status)
    sourceRows(right, status, bankPosition)
    return left, right
end

return StatusRows
