-- A status window that lists an object's summary as labelled rows: the base of the digester's and
-- the gasifier's windows, which share one window per local player (ObjectWindow). A summary is
-- what every client keeps (RenewableEnergy.GlobalObjects), so the window reads the same in single
-- player and multiplayer and needs no watching. A derived class sets `owner`, its shared module
-- (nameKey, summaryOf), and defines rowsOf(summary).

require "RenewableEnergy/UI/ObjectWindow"

RenewableEnergy = RenewableEnergy or {}
local ObjectWindow = RenewableEnergy.ObjectWindow
local SummaryWindow = ObjectWindow:derive("RenewableEnergySummaryWindow")
RenewableEnergy.SummaryWindow = SummaryWindow

local PAD = ObjectWindow.PAD
local WIDTH = 300

SummaryWindow.windows = {}

--- Adds a row to `rows`: the translation of `key`, then `value`, in the color named `color`
--- (ObjectWindow.rgb: plain text when nil, "bad" for something to see to).
function SummaryWindow.row(rows, key, value, color)
    table.insert(rows, { label = getText(key), value = value, color = color })
end

-- The rows are laid out again only when the summary changed. A summary read is a fresh copy with
-- what the object's containers hold now (RenewableEnergy.GlobalObjects), so it is compared by value.
function SummaryWindow:refresh()
    local summary = self.owner.summaryOf(self.object)
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
    self.title = getText(self.owner.nameKey(summary.tier))
    local rows = self:rowsOf(summary)
    local layout = ObjectWindow.measure(rows)
    self:setHeight(self:titleBarHeight() + PAD * 2 + layout.height)
    self:setWidth(math.max(WIDTH, PAD * 2 + layout.width))
    self.rowsToDraw, self.layout = rows, layout
end

function SummaryWindow:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed or not self.rowsToDraw then return end
    self:drawRows(self.rowsToDraw, self.layout, PAD, self:titleBarHeight() + PAD)
end

function SummaryWindow:new(x, y, playerNum, object)
    return ObjectWindow.new(self, x, y, WIDTH, 100, playerNum, object)
end

return SummaryWindow
