-- A status window that lists an object's summary as labelled rows: the base of the digester's and
-- the gasifier's windows. A summary is what every client keeps (RenewableEnergy.GlobalObjects), so
-- the window reads the same in single player and multiplayer and needs no watching. A derived
-- class defines titleOf(summary), summaryNow() and rowsOf(summary).

require "ISUI/ISCollapsableWindow"
require "RenewableEnergy/TimedActions/RenewableEnergyInfoAction"

RenewableEnergy = RenewableEnergy or {}
local SummaryWindow = ISCollapsableWindow:derive("RenewableEnergySummaryWindow")
RenewableEnergy.SummaryWindow = SummaryWindow

local PAD = 10
local LABEL_GAP = 16
local WIDTH = 300

-- One summary window per local player, of whichever kind.
SummaryWindow.windows = {}

local COLORS = {
    text = { 1, 1, 1 },
    label = { 0.8, 0.8, 0.8 },
    warn = { 1, 0.55, 0.3 },
}

--- Adds a row to `rows`: the translation of `key`, then `value`, in COLORS[`color`] ("text" when
--- nil, "warn" for something to see to).
function SummaryWindow.row(rows, key, value, color)
    table.insert(rows, { label = getText(key), value = value, color = color or "text" })
end

-- The rows are laid out again only when the summary changed. A summary read is a fresh copy with
-- what the object's containers hold now (RenewableEnergy.GlobalObjects), so it is compared by value.
-- The window closes once the object is gone or the character walked away from it.
function SummaryWindow:prerender()
    local summary = self:summaryNow()
    if not (summary and RenewableEnergy.onSquare(self.object) and RenewableEnergy.InfoAction.inReach(self.playerNum, self.object)) then
        self:close()
        return
    end
    if not RenewableEnergy.sameValue(summary, self.summary) then
        self.summary = summary
        self:layOut(summary)
    end
    ISCollapsableWindow.prerender(self)
end

function SummaryWindow:layOut(summary)
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
    self:setHeight(height)
    self:setWidth(math.max(WIDTH, PAD * 2 + labelWidth + LABEL_GAP + valueWidth))
    self.rowsToDraw, self.lineHeight, self.labelWidth = rows, lineHeight, labelWidth
end

function SummaryWindow:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed or not self.rowsToDraw then return end
    local font = UIFont.Small
    local y = self:titleBarHeight() + PAD
    for _, row in ipairs(self.rowsToDraw) do
        local label, value = COLORS.label, COLORS[row.color] or COLORS.text
        self:drawText(row.label, PAD, y, label[1], label[2], label[3], 1, font)
        self:drawText(row.value, PAD + self.labelWidth + LABEL_GAP, y, value[1], value[2], value[3], 1, font)
        y = y + self.lineHeight
    end
end

function SummaryWindow:close()
    SummaryWindow.windows[self.playerNum] = nil
    self:setVisible(false)
    self:removeFromUIManager()
end

function SummaryWindow:new(x, y, playerNum, object)
    local o = ISCollapsableWindow.new(self, x, y, WIDTH, 100)
    o.playerNum = playerNum
    o.object = object
    o.resizable = false
    return o
end

--- Opens `playerNum`'s window of this class on `object`, replacing the one they had open.
function SummaryWindow:openOn(playerNum, object)
    local old = SummaryWindow.windows[playerNum]
    if old then
        old:close()
    end
    local window = self:new(getPlayerScreenLeft(playerNum) + 100, getPlayerScreenTop(playerNum) + 100, playerNum, object)
    window:initialise()
    window:addToUIManager()
    SummaryWindow.windows[playerNum] = window
    return window
end

return SummaryWindow
