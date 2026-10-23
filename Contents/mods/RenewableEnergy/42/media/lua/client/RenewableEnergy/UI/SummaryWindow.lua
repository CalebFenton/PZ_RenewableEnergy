-- A status window that lists an object's summary as labelled rows: the base of the digester's and
-- the gasifier's windows, which share one window per local player (ObjectWindow). A summary is
-- what every client keeps (RenewableEnergy.GlobalObjects), so the window reads the same in single
-- player and multiplayer and needs no watching. A derived class defines titleOf(summary),
-- summaryNow() and rowsOf(summary).

require "RenewableEnergy/UI/ObjectWindow"

RenewableEnergy = RenewableEnergy or {}
local SummaryWindow = RenewableEnergy.ObjectWindow:derive("RenewableEnergySummaryWindow")
RenewableEnergy.SummaryWindow = SummaryWindow

local PAD = 10
local LABEL_GAP = 16
local WIDTH = 300

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
function SummaryWindow:refresh()
    local summary = self:summaryNow()
    if not summary then
        return false
    end
    if not RenewableEnergy.sameValue(summary, self.summary) then
        self.summary = summary
        self:layOut(summary)
    end
    return true
end

function SummaryWindow:layOut(summary)
    self.title = self:titleOf(summary)
    local rows = self:rowsOf(summary)
    local font = UIFont.Small
    local textManager = getTextManager()
    local lineHeight = textManager:getFontHeight(font) + 2
    local labelWidth, valueWidth = 0, 0
    for _, row in ipairs(rows) do
        labelWidth = math.max(labelWidth, textManager:MeasureStringX(font, row.label))
        valueWidth = math.max(valueWidth, textManager:MeasureStringX(font, row.value))
    end
    self:setHeight(self:titleBarHeight() + PAD * 2 + #rows * lineHeight)
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

function SummaryWindow:new(x, y, playerNum, object)
    return RenewableEnergy.ObjectWindow.new(self, x, y, WIDTH, 100, playerNum, object)
end

return SummaryWindow
