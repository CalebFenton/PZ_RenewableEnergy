-- Adds a battery's capacity and stored energy under its tooltip. Vanilla already shows the charge
-- and the condition as bars; watt-hours are what decide which battery goes into a bank. Java draws
-- the item tooltip, so the rows go in a strip drawn after ISToolTipInv.render. This file is named
-- to load after every other mod's client Lua, so it wraps their versions of render rather than
-- being replaced by them.

require "ISUI/ISToolTipInv"
require "RenewableEnergy/Specs"
require "RenewableEnergy/UI/Format"

local PAD = 5

local function batterySpec(item)
    return instanceof(item, "InventoryItem") and RenewableEnergy.Specs.batteries[item:getFullType()] or nil
end

-- The strip of the battery last drawn, rebuilt only when the battery, its charge or the font
-- changes, since render runs every frame.
local strip = {}

local function stripFor(item, spec, font)
    local uses = item:getCurrentUsesFloat()
    if strip.item == item and strip.uses == uses and strip.font == font then
        return strip
    end
    local Format = RenewableEnergy.Format
    local lines = {
        { getText("IGUI_RenewableEnergy_Capacity") .. ":", Format.wattHours(spec.wh) },
        { getText("IGUI_RenewableEnergy_Stored") .. ":", Format.wattHours(spec.wh * uses) },
    }
    local textManager = getTextManager()
    local labelWidth, valueWidth = 0, 0
    for _, line in ipairs(lines) do
        labelWidth = math.max(labelWidth, textManager:MeasureStringX(font, line[1]))
        valueWidth = math.max(valueWidth, textManager:MeasureStringX(font, line[2]))
    end
    strip = { item = item, uses = uses, font = font, lines = lines, labelWidth = labelWidth, valueWidth = valueWidth }
    return strip
end

local vanillaRender = ISToolTipInv.render

function ISToolTipInv:render()
    vanillaRender(self)
    local spec = batterySpec(self.item)
    -- Vanilla skips the tooltip while a context menu is open.
    if not spec or (ISContextMenu.instance and ISContextMenu.instance.visibleCheck) then
        return
    end

    local font = self.tooltip:getFont()
    local lineHeight = getTextManager():getFontHeight(font)
    local rows = stripFor(self.item, spec, font)
    local width = math.max(self.width, PAD + rows.labelWidth + PAD + rows.valueWidth + PAD)
    local height = PAD + lineHeight * #rows.lines + PAD
    local top = self.height
    -- Flip above the tooltip if the strip would leave the screen.
    if self:getAbsoluteY() + top + height > getCore():getScreenHeight() then
        top = -height
    end
    self:drawRect(0, top, width, height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)
    self:drawRectBorder(0, top, width, height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)
    local y = top + PAD
    for _, line in ipairs(rows.lines) do
        self:drawText(line[1], PAD, y, 1.0, 1.0, 0.8, 1.0, font)
        self:drawText(line[2], PAD + rows.labelWidth + PAD, y, 1.0, 1.0, 1.0, 1.0, font)
        y = y + lineHeight
    end
end
