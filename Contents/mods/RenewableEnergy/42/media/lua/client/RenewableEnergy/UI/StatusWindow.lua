-- The battery bank's status window. It draws the status the server sends to the players watching
-- the bank, which it does while the window is open, so it reads the same in single player and
-- multiplayer. Clicking a source's row highlights that source in the world. Its Turn On/Off and
-- Rename buttons queue the menu's jobs (RenewableEnergy.Menu), which requires this file for its
-- Status option, so they look Menu up when clicked.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "RenewableEnergy/Recipes"
require "RenewableEnergy/Sun"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"
require "RenewableEnergy/UI/Format"

RenewableEnergy = RenewableEnergy or {}
local StatusWindow = ISCollapsableWindow:derive("RenewableEnergyStatusWindow")
RenewableEnergy.StatusWindow = StatusWindow

local Format = RenewableEnergy.Format
local PowerBank, Sources = RenewableEnergy.PowerBank, RenewableEnergy.Sources
local Recipes = RenewableEnergy.Recipes
local Sun = RenewableEnergy.Sun
local Action = RenewableEnergyAction

local PAD = 10
local COLUMN_GAP = 24
local LABEL_GAP = 16
local MIN_COLUMN_WIDTH = 220
local BAR_HEIGHT = 8
local BUTTON_GAP = 8
-- Lines of the right column kept for "and N more" when the sources don't fit.
local MORE_LINE = 1
-- How long a clicked source stays highlighted, in real milliseconds.
local HIGHLIGHT_MS = 5000

-- One window per local player.
local windows = {}

local COLORS = {
    text = { r = 1, g = 1, b = 1 },
    label = { r = 0.8, g = 0.8, b = 0.8 },
    header = { r = 1, g = 1, b = 0.8 },
    dim = { r = 0.6, g = 0.6, b = 0.6 },
    highlight = { r = 0.9, g = 1, b = 0, a = 1 },
}

-- The player's good and bad highlight color options, which can change while the window is open,
-- read once a frame (StatusWindow:render).
local highlights = {}

-- The red, green and blue of a color name, "good" and "bad" among them.
local function rgb(name)
    local c = name and highlights[name]
    if c then
        return c:getR(), c:getG(), c:getB()
    end
    c = COLORS[name] or COLORS.text
    return c.r, c.g, c.b
end

-- drawProgressBar takes its color as a table; this one is refilled on every draw.
local barColor = { r = 0, g = 0, b = 0, a = 1 }

-- Summary -------------------------------------------------------------------------------------
-- The lines across the top, each { text = text, color = name }.

local function chargingLine(status)
    if #status.batteries == 0 then
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

-- Why a bank that has an inverter isn't carrying its load; overloads and missing inverters
-- have their own line.
local STATE_LINES = {
    outdoors = { key = "IGUI_RenewableEnergy_StateOutdoors", color = "bad" },
    off = { key = "IGUI_RenewableEnergy_StateOff", color = "dim" },
    grid = { key = "IGUI_RenewableEnergy_StateGrid", color = "dim" },
    empty = { key = "IGUI_RenewableEnergy_StateEmpty", color = "bad" },
}

--- The summary lines for a status snapshot.
function StatusWindow.summary(status)
    local lines = { chargingLine(status), loadLine(status), inputSlotsLine(status) }
    local state = STATE_LINES[status.state]
    if state then
        table.insert(lines, { text = getText(state.key), color = state.color })
    end
    return lines
end

-- Rows ----------------------------------------------------------------------------------------
-- A row is { header = text }, { label = text, value = text, color = name, source = entry },
-- { bar = 0..1 } or { gap = true }. They are built from the status alone, so the tests can check
-- them for any bank.

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

local function powerRows(rows, status)
    header(rows, "IGUI_RenewableEnergy_Power")
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
    if status.chargerW > 0 then
        row(rows, getText("IGUI_RenewableEnergy_ChargersNow"), Format.watts(status.chargerW))
    end
    if status.generator then
        local running = status.generator.running
        row(rows, getText("IGUI_RenewableEnergy_Generator"),
            getText(running and "IGUI_RenewableEnergy_GeneratorRunning" or "IGUI_RenewableEnergy_GeneratorStopped"),
            not running and "dim" or nil)
    end
    row(rows, getText("IGUI_RenewableEnergy_UsedToday"), Format.wattHours(status.loadWhToday))
end

local LOAD_KINDS = {
    fridgeFreezer = "IGUI_RenewableEnergy_LoadFridgeFreezer",
    fridge = "IGUI_RenewableEnergy_LoadFridge",
    miniFridge = "IGUI_RenewableEnergy_LoadMiniFridge",
    light = "IGUI_RenewableEnergy_LoadLight",
    television = "IGUI_RenewableEnergy_LoadTelevision",
    radio = "IGUI_RenewableEnergy_LoadRadio",
    microwave = "IGUI_RenewableEnergy_LoadMicrowave",
    range = "IGUI_RenewableEnergy_LoadRange",
    washer = "IGUI_RenewableEnergy_LoadWasher",
    dryer = "IGUI_RenewableEnergy_LoadDryer",
    batteryCharger = "IGUI_RenewableEnergy_LoadBatteryCharger",
    other = "IGUI_RenewableEnergy_LoadOther",
}

-- "TV" or "Lights (3)": a kind of load from Bank status `loadByKind`.
local function loadLabel(entry)
    local name = getText(LOAD_KINDS[entry.kind] or LOAD_KINDS.other)
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

-- The cheapest repair that helps a battery of this condition, or nil for one in perfect shape.
local function batteryRepair(condition)
    if condition < Recipes.SERVICE_CAP then
        return "IGUI_RenewableEnergy_RepairService"
    elseif condition < Recipes.RECONDITION_CONDITION then
        return "IGUI_RenewableEnergy_RepairRecondition"
    elseif condition < 100 then
        return "IGUI_RenewableEnergy_RepairRebuild"
    end
end

-- "64% charged, 72% condition (recondition)": a battery from Bank status `batteries`.
local function batteryValue(battery)
    local charge, condition = Format.percent(battery.charge), Format.condition(battery.fullType, battery.condition)
    local repair = batteryRepair(battery.condition)
    if repair then
        return getText("IGUI_RenewableEnergy_BatteryValueRepair", charge, condition, getText(repair))
    end
    return getText("IGUI_RenewableEnergy_BatteryValue", charge, condition)
end

local function batteryRows(rows, status)
    header(rows, "IGUI_RenewableEnergy_Batteries", #status.batteries)
    for _, battery in ipairs(status.batteries) do
        row(rows, getItemNameFromFullType(battery.fullType), batteryValue(battery), battery.condition <= 0 and "bad" or nil)
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
    propeller = "IGUI_RenewableEnergy_WindPropeller",
    alternator = "IGUI_RenewableEnergy_WindAlternator",
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
    calm = { key = "IGUI_RenewableEnergy_ReasonCalm" },
    furled = { key = "IGUI_RenewableEnergy_ReasonFurled" },
    sheltered = { key = "IGUI_RenewableEnergy_ReasonSheltered", fixable = true },
    idle = { key = "IGUI_RenewableEnergy_ReasonIdle" },
}

--- "Wooden rack, 6 tiles north-east": a source from Bank status `sources`, from the bank at
--- `bank`.
function StatusWindow.sourceLabel(source, bank)
    local name = SOURCE_NAMES[source.kind .. (source.material or "")]
    return getText("IGUI_RenewableEnergy_SourceWhere", getText(name), Format.away(bank, source))
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

local function sourceRows(rows, status, bank)
    header(rows, "IGUI_RenewableEnergy_Sources", #status.sources)
    for _, source in ipairs(status.sources) do
        local value, colorName = sourceValue(source, status)
        table.insert(rows, { label = StatusWindow.sourceLabel(source, bank), value = value, color = colorName, source = source })
    end
end

--- The rows of both columns for a status snapshot of the bank at `bank` ({ x, y, z }).
function StatusWindow.rows(status, bank)
    local left, right = {}, {}
    powerRows(left, status)
    loadRows(left, status)
    storageRows(left, status)
    partRows(left, status)
    batteryRows(right, status)
    sourceRows(right, status, bank)
    return left, right
end

-- Layout --------------------------------------------------------------------------------------

local function lineHeight()
    return getTextManager():getFontHeight(UIFont.Small)
end

local function rowHeight(r)
    if r.bar then
        return BAR_HEIGHT + 4
    elseif r.header then
        return lineHeight() + 4
    elseif r.gap then
        return math.floor(lineHeight() / 2)
    end
    return lineHeight()
end

local function measure(rows)
    local textManager = getTextManager()
    local labelWidth, valueWidth, height, headerWidth = 0, 0, 0, 0
    for _, r in ipairs(rows) do
        if r.header then
            headerWidth = math.max(headerWidth, textManager:MeasureStringX(UIFont.Small, r.header))
        elseif r.label then
            labelWidth = math.max(labelWidth, textManager:MeasureStringX(UIFont.Small, r.label))
            valueWidth = math.max(valueWidth, textManager:MeasureStringX(UIFont.Small, r.value))
        end
        r.height = rowHeight(r)
        height = height + r.height
    end
    local width = math.max(MIN_COLUMN_WIDTH, headerWidth, labelWidth + LABEL_GAP + valueWidth)
    return { width = width, height = height, labelWidth = labelWidth }
end

local function measureSummary(lines)
    local textManager = getTextManager()
    local width = 0
    for _, line in ipairs(lines) do
        width = math.max(width, textManager:MeasureStringX(UIFont.Medium, line.text))
    end
    local fontHeight = textManager:getFontHeight(UIFont.Medium)
    return { width = width, height = #lines * fontHeight, lineHeight = fontHeight }
end

-- Keeps as many right-column rows as fit beside the left column, then one "and N more" line
-- counting the entries left out.
local function fit(rows, height)
    local used, kept = 0, {}
    for i, r in ipairs(rows) do
        local h = rowHeight(r)
        if used + h + MORE_LINE * lineHeight() > height and i < #rows then
            local hidden = 0
            for j = i, #rows do
                if rows[j].label then
                    hidden = hidden + 1
                end
            end
            table.insert(kept, { label = getText("IGUI_RenewableEnergy_More", hidden), value = "", color = "dim" })
            return kept
        end
        table.insert(kept, r)
        used = used + h
    end
    return kept
end

-- Window --------------------------------------------------------------------------------------

local function addButton(self, title, onClick)
    local button = ISButton:new(PAD, 0, 100, math.floor(lineHeight() * 1.5), title, self, onClick)
    button:initialise()
    self:addChild(button)
    return button
end

local function fitButton(button, x, y)
    button:setWidth(getTextManager():MeasureStringX(UIFont.Small, button:getTitle()) + 20)
    button:setX(x)
    button:setY(y)
end

function StatusWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.switchButton = addButton(self, getText("ContextMenu_Turn_On"), StatusWindow.onSwitch)
    self.renameButton = addButton(self, getText("ContextMenu_RenewableEnergy_Rename"), StatusWindow.onRename)
end

function StatusWindow:onSwitch()
    RenewableEnergy.Menu.queueBank(self.playerNum, self.status.on and Action.TURN_OFF or Action.TURN_ON, self.bank)
end

function StatusWindow:onRename()
    RenewableEnergy.Menu.askName(self.playerNum, self.bank)
end

-- Rebuilds the rows and the layout when a new snapshot arrives.
function StatusWindow:setStatus(status)
    self.status = status
    if not status then
        self.summaryLines = {}
        self.left, self.right = { { label = getText("IGUI_RenewableEnergy_Waiting"), value = "", color = "dim" } }, {}
    else
        self.summaryLines = StatusWindow.summary(status)
        self.left, self.right = StatusWindow.rows(status, PowerBank.positionOf(self.bank))
    end
    self.title = status and Format.bankName(status) or getText("IGUI_RenewableEnergy_StatusTitle")
    local summary = measureSummary(self.summaryLines)
    local left = measure(self.left)
    self.right = fit(self.right, math.max(left.height, lineHeight() * 8))
    local right = measure(self.right)
    self.summaryLayout, self.leftLayout, self.rightLayout = summary, left, right

    local top = self:titleBarHeight() + PAD
    self.columnsTop = top + summary.height + (summary.height > 0 and PAD or 0)
    local buttonY = self.columnsTop + math.max(left.height, right.height) + PAD
    local on = status ~= nil and status.on == true
    self.switchButton:setTitle(getText(on and "ContextMenu_Turn_Off" or "ContextMenu_Turn_On"))
    fitButton(self.switchButton, PAD, buttonY)
    -- Greyed and explained as the menu's Turn On is.
    local refusal = status and PowerBank.switchRefusal(status, not on)
    self.switchButton:setEnable(status ~= nil and not refusal)
    self.switchButton:setTooltip(refusal and getText(refusal) or nil)
    fitButton(self.renameButton, PAD + self.switchButton:getWidth() + BUTTON_GAP, buttonY)
    self.renameButton:setEnable(status ~= nil)

    self:setWidth(math.max(PAD + left.width + COLUMN_GAP + right.width + PAD, PAD + summary.width + PAD))
    self:setHeight(buttonY + self.switchButton:getHeight() + PAD)
end

-- Highlighting a source -------------------------------------------------------------------------

function StatusWindow:clearHighlight()
    local highlight = self.highlight
    if highlight then
        highlight.object:setHighlighted(self.playerNum, false)
        self.highlight = nil
    end
end

--- Highlights the source of a Bank status `sources` entry in the world for a few seconds, the
--- way vanilla shows the object a moveable action works on. Returns the source, or nil if its
--- square isn't loaded.
function StatusWindow:highlightSource(source)
    self:clearHighlight()
    local object = Sources.on(getSquare(source.x, source.y, source.z))
    if not object then
        return nil
    end
    local c = COLORS.highlight
    object:setHighlightColor(self.playerNum, c.r, c.g, c.b, c.a)
    object:setHighlighted(self.playerNum, true, false)
    self.highlight = { object = object, source = source, untilMs = getTimestampMs() + HIGHLIGHT_MS }
    return object
end

-- The source row under a point in the window, if any.
function StatusWindow:sourceRowAt(x, y)
    local layout = self.rightLayout
    if not (layout and layout.x) or x < layout.x or x > layout.x + layout.width then
        return nil
    end
    for _, r in ipairs(self.right or {}) do
        if r.source and r.top and y >= r.top and y < r.top + r.height then
            return r
        end
    end
end

function StatusWindow:onMouseDown(x, y)
    local r = not self.isCollapsed and self:sourceRowAt(x, y)
    if r then
        self:highlightSource(r.source)
        return true
    end
    return ISCollapsableWindow.onMouseDown(self, x, y)
end

function StatusWindow:prerender()
    -- Picked up or destroyed.
    if not RenewableEnergy.onSquare(self.bank) then
        self:close()
        return
    end
    if self.highlight and getTimestampMs() >= self.highlight.untilMs then
        self:clearHighlight()
    end
    -- Every snapshot is a new table (Bank:sendStatus, ClientBankSystem's OnServerCommand).
    local status = PowerBank.statusOf(self.bank)
    if status ~= self.status or not self.left then
        self:setStatus(status)
    end
    ISCollapsableWindow.prerender(self)
end

local function isHighlighted(self, r)
    return self.highlight ~= nil and PowerBank.samePosition(r.source, self.highlight.source)
end

function StatusWindow:drawRows(rows, layout, x, y)
    local width = layout.width
    layout.x = x
    for _, r in ipairs(rows) do
        r.top = y
        if r.header then
            local c = COLORS.header
            self:drawText(r.header, x, y + 2, c.r, c.g, c.b, 1, UIFont.Small)
            self:drawRect(x, y + r.height - 2, width, 1, 0.4, c.r, c.g, c.b)
        elseif r.bar then
            barColor.r, barColor.g, barColor.b = rgb(r.bar < 0.25 and "bad" or "good")
            self:drawProgressBar(x, y + 2, width, BAR_HEIGHT, r.bar, barColor)
        elseif r.label then
            if isHighlighted(self, r) then
                local c = COLORS.highlight
                self:drawRect(x - 2, y, width + 4, r.height, 0.2, c.r, c.g, c.b)
            end
            local label = COLORS.label
            self:drawText(r.label, x, y, label.r, label.g, label.b, 1, UIFont.Small)
            local red, green, blue = rgb(r.color)
            self:drawTextRight(r.value, x + width, y, red, green, blue, 1, UIFont.Small)
        end
        y = y + r.height
    end
end

function StatusWindow:drawSummary(x, y)
    local height = self.summaryLayout.lineHeight
    for _, line in ipairs(self.summaryLines) do
        local red, green, blue = rgb(line.color)
        self:drawText(line.text, x, y, red, green, blue, 1, UIFont.Medium)
        y = y + height
    end
end

function StatusWindow:render()
    if not self.isCollapsed and self.left then
        local core = getCore()
        highlights.good, highlights.bad = core:getGoodHighlitedColor(), core:getBadHighlitedColor()
        self:drawSummary(PAD, self:titleBarHeight() + PAD)
        self:drawRows(self.left, self.leftLayout, PAD, self.columnsTop)
        self:drawRows(self.right, self.rightLayout, PAD + self.leftLayout.width + COLUMN_GAP, self.columnsTop)
    end
    ISCollapsableWindow.render(self)
end

function StatusWindow:close()
    self:clearHighlight()
    self:removeFromUIManager()
    windows[self.playerNum] = nil
    PowerBank.unwatchStatus(getSpecificPlayer(self.playerNum), self.bank)
    if JoypadState.players[self.playerNum + 1] then
        setPrevFocusForPlayer(self.playerNum)
    end
end

function StatusWindow:onJoypadDown(button)
    if button == Joypad.BButton then
        self:close()
    end
end

function StatusWindow:new(x, y, playerNum, bank)
    local o = ISCollapsableWindow.new(self, x, y, 400, 300)
    o.title = getText("IGUI_RenewableEnergy_StatusTitle")
    o.playerNum = playerNum
    o.bank = bank
    o.summaryLines = {}
    -- Nearly opaque: vanilla's translucent window lets the text of windows behind show through the rows.
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.95 }
    o:setResizable(false)
    return o
end

--- Opens the status window of `bank` (the bank's IsoGenerator) for a local player, replacing
--- the one already open, and watches the bank's status until it closes.
function StatusWindow.open(playerNum, bank)
    local open = windows[playerNum]
    local x, y = getPlayerScreenLeft(playerNum) + 100, getPlayerScreenTop(playerNum) + 100
    if open then
        x, y = open:getX(), open:getY()
        open:close()
    end
    local window = StatusWindow:new(x, y, playerNum, bank)
    window:initialise()
    window:addToUIManager()
    windows[playerNum] = window
    PowerBank.watchStatus(getSpecificPlayer(playerNum), bank)
    if JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, window)
    end
    return window
end

return StatusWindow
