-- Adds a battery's capacity and stored energy under its tooltip: watt-hours decide which battery
-- goes into a bank, and a worn battery holds less than its rating. Java draws the tooltip, so the
-- rows are a strip drawn after ISToolTipInv.render. Named to load after every other mod's client
-- Lua, so it wraps their render rather than being replaced.

require "ISUI/ISToolTipInv"
require "RenewableEnergy/PowerBank/Battery"
require "RenewableEnergy/UI/Format"

local Battery = RenewableEnergy.Battery
local Format = RenewableEnergy.Format

local PAD = 5

-- The strip of the battery last drawn, rebuilt only when the battery, its charge, its condition
-- or the font changes, since render runs every frame.
local strip = {}

local function stripFor(item, font)
    local uses, condition = item:getCurrentUsesFloat(), item:getCondition()
    if strip.item == item and strip.uses == uses and strip.condition == condition and strip.font == font then
        return strip
    end
    local wh = Battery.nominalWh(item)
    local lines = {
        { getText("IGUI_RenewableEnergy_Capacity") .. ":", Format.wattHours(wh) },
        { getText("IGUI_RenewableEnergy_Stored") .. ":", Format.wattHours(wh * uses) },
    }
    local textManager = getTextManager()
    local labelWidth, valueWidth = 0, 0
    for _, line in ipairs(lines) do
        labelWidth = math.max(labelWidth, textManager:MeasureStringX(font, line[1]))
        valueWidth = math.max(valueWidth, textManager:MeasureStringX(font, line[2]))
    end
    strip = { item = item, uses = uses, condition = condition, font = font, lines = lines, labelWidth = labelWidth,
        valueWidth = valueWidth, lineHeight = textManager:getFontHeight(font) }
    return strip
end

local vanillaRender = ISToolTipInv.render

function ISToolTipInv:render()
    vanillaRender(self)
    -- Vanilla skips the tooltip while a context menu is open.
    if not Battery.isBattery(self.item) or (ISContextMenu.instance and ISContextMenu.instance.visibleCheck) then
        return
    end

    local rows = stripFor(self.item, self.tooltip:getFont())
    local font, lineHeight = rows.font, rows.lineHeight
    local width = math.max(self.width, PAD + rows.labelWidth + PAD + rows.valueWidth + PAD)
    local height = PAD + lineHeight * #rows.lines + PAD
    local top = self.height
    -- Flip above the tooltip if the strip would leave the screen.
    if self:getAbsoluteY() + top + height > getCore():getScreenHeight() then
        top = -height
    end
    local background, border = self.backgroundColor, self.borderColor
    self:drawRect(0, top, width, height, background.a, background.r, background.g, background.b)
    self:drawRectBorder(0, top, width, height, border.a, border.r, border.g, border.b)
    local y = top + PAD
    for _, line in ipairs(rows.lines) do
        self:drawText(line[1], PAD, y, 1.0, 1.0, 0.8, 1.0, font)
        self:drawText(line[2], PAD + rows.labelWidth + PAD, y, 1.0, 1.0, 1.0, 1.0, font)
        y = y + lineHeight
    end
end
