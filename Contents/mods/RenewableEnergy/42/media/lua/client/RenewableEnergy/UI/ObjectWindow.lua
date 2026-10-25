-- The base of the status windows of an object: a bank's (StatusWindow), a digester's and a
-- gasifier's (SummaryWindow). Each family keeps one window per local player in its class's
-- `windows`; a new one opens where the player's last one of the family stood, takes the
-- controller's focus, and closes with B, as vanilla's windows do. It closes once its object is
-- gone or the character walked away (cf_commonlib's OpenAction.inReach), as vanilla's animal
-- windows close. A derived class defines refresh(), which brings it up to date before each frame
-- is drawn and returns false when there is nothing left to show.
--
-- The windows draw their rows alike: a row is { header = text }, { label = text, value = text,
-- color = name, source = entry }, { bar = 0..1 } or { gap = true }, measured by
-- ObjectWindow.measure and drawn by ObjectWindow:drawRows.

require "ISUI/ISCollapsableWindow"
local OpenAction = require "cf_commonlib/OpenAction"

RenewableEnergy = RenewableEnergy or {}
local ObjectWindow = ISCollapsableWindow:derive("RenewableEnergyObjectWindow")
RenewableEnergy.ObjectWindow = ObjectWindow

-- Where a player's first window of a family opens, from their screen's top left corner.
local FIRST_OFFSET = 100

ObjectWindow.PAD = 10
local LABEL_GAP = 16
local MIN_COLUMN_WIDTH = 220
local BAR_HEIGHT = 8

ObjectWindow.COLORS = {
    text = { r = 1, g = 1, b = 1 },
    label = { r = 0.8, g = 0.8, b = 0.8 },
    header = { r = 1, g = 1, b = 0.8 },
    dim = { r = 0.6, g = 0.6, b = 0.6 },
    highlight = { r = 0.9, g = 1, b = 0, a = 1 },
}
local COLORS = ObjectWindow.COLORS

-- The player's good and bad highlight color options, which can change while a window is open,
-- read once a frame (ObjectWindow:prerender).
local highlights = {}

--- The red, green and blue of a color name, "good" and "bad" among them.
function ObjectWindow.rgb(name)
    local c = name and highlights[name]
    if c then
        return c:getR(), c:getG(), c:getB()
    end
    c = COLORS[name] or COLORS.text
    return c.r, c.g, c.b
end
local rgb = ObjectWindow.rgb

-- drawProgressBar takes its color as a table; this one is refilled on every draw.
local barColor = { r = 0, g = 0, b = 0, a = 1 }

function ObjectWindow.lineHeight()
    return getTextManager():getFontHeight(UIFont.Small)
end
local lineHeight = ObjectWindow.lineHeight

function ObjectWindow.rowHeight(r)
    if r.bar then
        return BAR_HEIGHT + 4
    elseif r.header then
        return lineHeight() + 4
    elseif r.gap then
        return math.floor(lineHeight() / 2)
    end
    return lineHeight()
end
local rowHeight = ObjectWindow.rowHeight

--- The column `rows` make: { width, height, labelWidth }. Sets each row's height.
function ObjectWindow.measure(rows)
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

-- Whether a row is drawn highlighted; a derived class that highlights rows overrides it.
function ObjectWindow:isRowHighlighted(r)
    return false
end

--- Draws `rows`, measured as `layout`, from `x`, `y`, noting where each row and the column
--- landed (layout.x, r.top) for clicks.
function ObjectWindow:drawRows(rows, layout, x, y)
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
            if self:isRowHighlighted(r) then
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

function ObjectWindow:prerender()
    if not (OpenAction.inReach(self.playerNum, self.object) and self:refresh() ~= false) then
        self:close()
        return
    end
    local core = getCore()
    highlights.good, highlights.bad = core:getGoodHighlitedColor(), core:getBadHighlitedColor()
    ISCollapsableWindow.prerender(self)
end

function ObjectWindow:close()
    self.windows[self.playerNum] = nil
    self:removeFromUIManager()
    if JoypadState.players[self.playerNum + 1] then
        setPrevFocusForPlayer(self.playerNum)
    end
end

function ObjectWindow:onJoypadDown(button)
    if button == Joypad.BButton then
        self:close()
    end
end

function ObjectWindow:new(x, y, width, height, playerNum, object)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.playerNum = playerNum
    o.object = object
    o:setResizable(false)
    return o
end

--- Opens `playerNum`'s window of this class on `object` (the class's new(x, y, playerNum,
--- object)), in place of the one of its family they had open.
function ObjectWindow:openOn(playerNum, object)
    local open = self.windows[playerNum]
    local x, y = getPlayerScreenLeft(playerNum) + FIRST_OFFSET, getPlayerScreenTop(playerNum) + FIRST_OFFSET
    if open then
        x, y = open:getX(), open:getY()
        open:close()
    end
    local window = self:new(x, y, playerNum, object)
    window:initialise()
    window:addToUIManager()
    self.windows[playerNum] = window
    if JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, window)
    end
    return window
end

--- Walks `playerNum`'s character over to `object` and opens their window of the class `window`
--- (an ObjectWindow) on it there, as things stand then (cf_commonlib's OpenAction).
function ObjectWindow.queueOpen(playerNum, object, window)
    OpenAction.queue(getSpecificPlayer(playerNum), object, function(character, target)
        window:openOn(character:getPlayerNum(), target)
    end)
end

return ObjectWindow
