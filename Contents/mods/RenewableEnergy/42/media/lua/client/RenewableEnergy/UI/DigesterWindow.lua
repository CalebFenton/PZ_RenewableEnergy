-- A digester's status window: what its summary says (RenewableEnergy.Digester.summaryOf), which
-- every client keeps, so it reads the same in single player and multiplayer and needs no watching.

require "ISUI/ISCollapsableWindow"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/GasHeater"

RenewableEnergy = RenewableEnergy or {}
local DigesterWindow = ISCollapsableWindow:derive("RenewableEnergyDigesterWindow")
RenewableEnergy.DigesterWindow = DigesterWindow

local Digester = RenewableEnergy.Digester

local PAD = 10
local LABEL_GAP = 16
local WIDTH = 300

-- One status window per local player, of either kind (this or a class derived from it, such as
-- RenewableEnergy.GasifierWindow).
DigesterWindow.windows = {}

local COLORS = {
    text = { 1, 1, 1 },
    label = { 0.8, 0.8, 0.8 },
    warn = { 1, 0.55, 0.3 },
}

-- Below this the digester makes next to nothing (Digester's K_BY_TEMP starts at 10 °C).
local COLD_C = 10

local function temperature(celsius)
    if getCore():getOptionDisplayAsCelsius() then
        return string.format("%d °C", celsius)
    end
    return string.format("%d °F", math.floor(celsius * 9 / 5 + 32 + 0.5))
end

local function percent(fraction)
    return string.format("%d%%", math.floor(fraction * 100 + 0.5))
end

--- The window's state line: the first that applies of startup, sour, cold, nothing in it, working.
function DigesterWindow.stateText(summary)
    if not summary.fed then
        return getText("IGUI_RenewableEnergy_DigesterEmpty")
    elseif not summary.started then
        return getText("IGUI_RenewableEnergy_DigesterStarting", percent(summary.startup))
    elseif summary.sour then
        return getText("IGUI_RenewableEnergy_DigesterSour")
    elseif summary.temp < COLD_C then
        return getText("IGUI_RenewableEnergy_DigesterCold")
    elseif summary.fill <= 0 then
        return getText("IGUI_RenewableEnergy_DigesterHungry")
    end
    return getText("IGUI_RenewableEnergy_DigesterWorking")
end

-- The smell levels of DigesterObject.corpsesFor.
local function smellText(score)
    if score < 0.2 then
        return getText("IGUI_RenewableEnergy_SmellNone")
    elseif score < 1 then
        return getText("IGUI_RenewableEnergy_SmellFaint")
    elseif score < 2 then
        return getText("IGUI_RenewableEnergy_SmellStrong")
    end
    return getText("IGUI_RenewableEnergy_SmellVile")
end

local function holderText(summary)
    local name = getText("IGUI_RenewableEnergy_Holder_" .. summary.holder)
    if summary.torn then
        return getText("IGUI_RenewableEnergy_HolderTorn", name)
    end
    if summary.holder == "bags" or summary.holder == "tarp" then
        return name .. " " .. percent(summary.holderCondition / 100)
    end
    return name
end

--- The rows the window shows for `summary`: { label, value, color }.
function DigesterWindow.rows(summary)
    local rows = {}
    local function add(key, value, color)
        table.insert(rows, { label = getText(key), value = value, color = color or "text" })
    end
    add("IGUI_RenewableEnergy_DigesterState", DigesterWindow.stateText(summary), (summary.sour or not summary.started) and "warn" or nil)
    add("IGUI_RenewableEnergy_DigesterTemp", temperature(summary.temp), summary.temp < COLD_C and "warn" or nil)
    add("IGUI_RenewableEnergy_DigesterGas", string.format("%.2f / %.2f m³", summary.gas, summary.capacity))
    add("IGUI_RenewableEnergy_DigesterMaking", getText("IGUI_RenewableEnergy_PerDay", string.format("%.2f m³", summary.madePerDay)))
    add("IGUI_RenewableEnergy_DigesterHolder", holderText(summary), (summary.torn or summary.leaking) and "warn" or nil)
    add("IGUI_RenewableEnergy_DigesterFill", percent(summary.fill))
    add("IGUI_RenewableEnergy_DigesterHopper", tostring(summary.hopper))
    add("IGUI_RenewableEnergy_DigesterSludge", percent(summary.sludge / 100), summary.sludge >= 80 and "warn" or nil)
    add("IGUI_RenewableEnergy_DigesterSmell", smellText(summary.stink), summary.stink >= 1 and "warn" or nil)
    if summary.scrubber then
        add("IGUI_RenewableEnergy_DigesterScrubber", getText("IGUI_RenewableEnergy_ScrubberState",
            string.format("%.1f", summary.scrubCO2), string.format("%.1f", summary.scrubWool)),
            (summary.scrubCO2 <= 0 or summary.scrubWool <= 0) and "warn" or nil)
    end
    if summary.heaterLit then
        add("IGUI_RenewableEnergy_DigesterHeater", getText("IGUI_RenewableEnergy_HeaterBurning",
            getText("IGUI_RenewableEnergy_PerDay", string.format("%.1f m³", RenewableEnergy.GasHeater.M3_PER_HOUR * 24))))
    end
    if summary.leaking then
        add("IGUI_RenewableEnergy_DigesterLeak", getText("IGUI_RenewableEnergy_DigesterLeaking"), "warn")
    end
    return rows
end

function DigesterWindow:titleOf(summary)
    return getText("IGUI_RenewableEnergy_Digester_" .. summary.tier)
end

function DigesterWindow:summaryNow()
    return Digester.summaryOf(self.object)
end

function DigesterWindow:rowsOf(summary)
    return DigesterWindow.rows(summary)
end

function DigesterWindow:prerender()
    local summary = self:summaryNow()
    if not summary or self.object:getObjectIndex() == -1 then
        self:close()
        return
    end
    self.summary = summary
    self.title = self:titleOf(summary)
    local rows = self:rowsOf(summary)
    local font = UIFont.Small
    local lineHeight = getTextManager():getFontHeight(font) + 2
    local height = self:titleBarHeight() + PAD * 2 + #rows * lineHeight
    local labelWidth, valueWidth = 0, 0
    for _, row in ipairs(rows) do
        labelWidth = math.max(labelWidth, getTextManager():MeasureStringX(font, row.label))
        valueWidth = math.max(valueWidth, getTextManager():MeasureStringX(font, row.value))
    end
    local width = math.max(WIDTH, PAD * 2 + labelWidth + LABEL_GAP + valueWidth)
    if self:getHeight() ~= height or self:getWidth() ~= width then
        self:setHeight(height)
        self:setWidth(width)
    end
    self.rowsToDraw, self.lineHeight = rows, lineHeight
    ISCollapsableWindow.prerender(self)
end

function DigesterWindow:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed or not self.rowsToDraw then return end
    local font = UIFont.Small
    local labelWidth = 0
    for _, row in ipairs(self.rowsToDraw) do
        labelWidth = math.max(labelWidth, getTextManager():MeasureStringX(font, row.label))
    end
    local y = self:titleBarHeight() + PAD
    for _, row in ipairs(self.rowsToDraw) do
        local label, value = COLORS.label, COLORS[row.color] or COLORS.text
        self:drawText(row.label, PAD, y, label[1], label[2], label[3], 1, font)
        self:drawText(row.value, PAD + labelWidth + LABEL_GAP, y, value[1], value[2], value[3], 1, font)
        y = y + self.lineHeight
    end
end

function DigesterWindow:close()
    DigesterWindow.windows[self.playerNum] = nil
    self:setVisible(false)
    self:removeFromUIManager()
end

function DigesterWindow:new(x, y, playerNum, object)
    local o = ISCollapsableWindow.new(self, x, y, WIDTH, 100)
    o.playerNum = playerNum
    o.object = object
    o.resizable = false
    return o
end

--- Opens `playerNum`'s window of this class on `object`, replacing the one they had open.
function DigesterWindow:openOn(playerNum, object)
    local old = DigesterWindow.windows[playerNum]
    if old then
        old:close()
    end
    local x = getPlayerScreenLeft(playerNum) + 100
    local y = getPlayerScreenTop(playerNum) + 100
    local window = self:new(x, y, playerNum, object)
    window:initialise()
    window:addToUIManager()
    DigesterWindow.windows[playerNum] = window
    return window
end

--- Opens `playerNum`'s window on the digester `digester`.
function DigesterWindow.open(playerNum, digester)
    return DigesterWindow:openOn(playerNum, digester)
end

-- Formatting for derived windows.
DigesterWindow.percent, DigesterWindow.temperature = percent, temperature

return DigesterWindow
