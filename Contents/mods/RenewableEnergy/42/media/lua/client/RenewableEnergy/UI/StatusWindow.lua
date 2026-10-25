-- The battery bank's status window, one per local player (ObjectWindow). It draws the status the
-- server sends to the bank's watchers (StatusRows), so it reads the same in single player and
-- multiplayer. Menu requires this file, so the window looks Menu up when it needs it.

require "ISUI/ISButton"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/ObjectWindow"
require "RenewableEnergy/UI/StatusRows"

RenewableEnergy = RenewableEnergy or {}
local ObjectWindow = RenewableEnergy.ObjectWindow
local StatusWindow = ObjectWindow:derive("RenewableEnergyStatusWindow")
RenewableEnergy.StatusWindow = StatusWindow
StatusWindow.windows = {}

local Format = RenewableEnergy.Format
local PowerBank, Sources = RenewableEnergy.PowerBank, RenewableEnergy.Sources
local StatusRows = RenewableEnergy.StatusRows
local PAD, COLORS, rgb = ObjectWindow.PAD, ObjectWindow.COLORS, ObjectWindow.rgb
local lineHeight, measure = ObjectWindow.lineHeight, ObjectWindow.measure

local COLUMN_GAP = 24
local BUTTON_GAP = 8
-- Lines of the right column kept for "and N more" when the sources don't fit.
local MORE_LINE = 1
-- How long a clicked source stays highlighted, in real milliseconds.
local HIGHLIGHT_MS = 5000

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
        local h = ObjectWindow.rowHeight(r)
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
    RenewableEnergy.Menu.queueBank(self.playerNum, self.switchJob, self.object)
end

function StatusWindow:onRename()
    RenewableEnergy.Menu.askName(self.playerNum, self.object)
end

-- Rebuilds the rows and the layout when a new snapshot arrives.
function StatusWindow:setStatus(status)
    self.status = status
    if not status then
        self.summaryLines = {}
        self.left, self.right = { { label = getText("IGUI_RenewableEnergy_Waiting"), value = "", color = "dim" } }, {}
    else
        self.summaryLines = StatusRows.summary(status)
        self.left, self.right = StatusRows.rows(status, PowerBank.positionOf(self.object))
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
    local switchKey, refusal = "ContextMenu_Turn_On", nil
    if status then
        switchKey, self.switchJob, refusal = RenewableEnergy.Menu.switchOf(status)
    end
    self.switchButton:setTitle(getText(switchKey))
    fitButton(self.switchButton, PAD, buttonY)
    self.switchButton:setEnable(status ~= nil and not refusal)
    self.switchButton:setTooltip(refusal and getText(refusal) or nil)
    fitButton(self.renameButton, PAD + self.switchButton:getWidth() + BUTTON_GAP, buttonY)
    self.renameButton:setEnable(status ~= nil)

    self:setWidth(math.max(PAD + left.width + COLUMN_GAP + right.width + PAD, PAD + summary.width + PAD))
    self:setHeight(buttonY + self.switchButton:getHeight() + PAD)
end

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
    local object = Sources.findOn(getSquare(source.x, source.y, source.z))
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

function StatusWindow:refresh()
    if self.highlight and getTimestampMs() >= self.highlight.untilMs then
        self:clearHighlight()
    end
    -- Every snapshot is a new table (Bank:sendStatus, ClientBankSystem's OnServerCommand).
    local status = PowerBank.statusOf(self.object)
    if status ~= self.status or not self.left then
        self:setStatus(status)
    end
end

function StatusWindow:isRowHighlighted(r)
    return self.highlight ~= nil and PowerBank.samePosition(r.source, self.highlight.source)
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
        self:drawSummary(PAD, self:titleBarHeight() + PAD)
        self:drawRows(self.left, self.leftLayout, PAD, self.columnsTop)
        self:drawRows(self.right, self.rightLayout, PAD + self.leftLayout.width + COLUMN_GAP, self.columnsTop)
    end
    ISCollapsableWindow.render(self)
end

function StatusWindow:close()
    self:clearHighlight()
    ObjectWindow.close(self)
    PowerBank.unwatchStatus(getSpecificPlayer(self.playerNum), self.object)
end

function StatusWindow:new(x, y, playerNum, bank)
    local o = ObjectWindow.new(self, x, y, 400, 300, playerNum, bank)
    -- Nearly opaque: vanilla's translucent window lets the text of windows behind show through the rows.
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.95 }
    return o
end

--- Opens the status window of `bank` (the bank's IsoGenerator) for a local player, in place of
--- the one already open, and watches the bank's status until it closes.
function StatusWindow:openOn(playerNum, bank)
    local window = ObjectWindow.openOn(self, playerNum, bank)
    PowerBank.watchStatus(getSpecificPlayer(playerNum), bank)
    return window
end

return StatusWindow
