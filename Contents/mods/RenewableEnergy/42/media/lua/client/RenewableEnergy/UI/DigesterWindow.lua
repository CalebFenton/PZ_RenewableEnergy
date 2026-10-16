-- A digester's status window: what its summary says (RenewableEnergy.Digester.summaryOf), which
-- every client keeps, so it reads the same in single player and multiplayer and needs no watching.

require "ISUI/ISCollapsableWindow"
require "RenewableEnergy/Biogas/Digester"

RenewableEnergy = RenewableEnergy or {}
local DigesterWindow = ISCollapsableWindow:derive("RenewableEnergyDigesterWindow")
RenewableEnergy.DigesterWindow = DigesterWindow

local Digester = RenewableEnergy.Digester

local PAD = 10
local LABEL_GAP = 16
local WIDTH = 300

-- One window per local player.
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
    if summary.leaking then
        add("IGUI_RenewableEnergy_DigesterLeak", getText("IGUI_RenewableEnergy_DigesterLeaking"), "warn")
    end
    return rows
end

function DigesterWindow:titleOf(summary)
    return getText("IGUI_RenewableEnergy_Digester_" .. summary.tier)
end

function DigesterWindow:prerender()
    local summary = Digester.summaryOf(self.digester)
    if not summary or self.digester:getObjectIndex() == -1 then
        self:close()
        return
    end
    self.summary = summary
    self.title = self:titleOf(summary)
    local rows = DigesterWindow.rows(summary)
    local font = UIFont.Small
    local lineHeight = getTextManager():getFontHeight(font) + 2
    local height = self:titleBarHeight() + PAD * 2 + #rows * lineHeight
    if self:getHeight() ~= height then
        self:setHeight(height)
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

function DigesterWindow:new(x, y, playerNum, digester)
    local o = ISCollapsableWindow.new(self, x, y, WIDTH, 100)
    o.playerNum = playerNum
    o.digester = digester
    o.resizable = false
    return o
end

--- Opens `playerNum`'s window on the digester `digester`, replacing one they had open.
function DigesterWindow.open(playerNum, digester)
    local old = DigesterWindow.windows[playerNum]
    if old then
        old:close()
    end
    local x = getPlayerScreenLeft(playerNum) + 100
    local y = getPlayerScreenTop(playerNum) + 100
    local window = DigesterWindow:new(x, y, playerNum, digester)
    window:initialise()
    window:addToUIManager()
    DigesterWindow.windows[playerNum] = window
    return window
end

return DigesterWindow
