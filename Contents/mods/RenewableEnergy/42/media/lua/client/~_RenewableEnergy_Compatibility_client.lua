require "ISUI/ISToolTipInv"
require "RenewableEnergy/Specs"
require "RenewableEnergy/UI/RenewableEnergyFormat"

-- Adds a battery's capacity and stored energy under its tooltip. Vanilla already shows the charge
-- and the condition as bars; watt-hours are what decide which battery goes into a bank. Java draws
-- the item tooltip, so the rows go in a strip drawn after ISToolTipInv.render. This file is named
-- to load after every other mod's client Lua, so it wraps their versions of render rather than
-- being replaced by them.

local PAD = 5

local function batterySpec(item)
    return instanceof(item, "InventoryItem") and RenewableEnergy.Specs.batteries[item:getFullType()] or nil
end

local function rows(item, spec)
    local Format = RenewableEnergy.Format
    return {
        { getText("IGUI_RenewableEnergy_Capacity") .. ":", Format.wattHours(spec.wh) },
        { getText("IGUI_RenewableEnergy_Stored") .. ":", Format.wattHours(spec.wh * item:getCurrentUsesFloat()) },
    }
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
    local textManager = getTextManager()
    local lineHeight = textManager:getFontHeight(font)
    local lines = rows(self.item, spec)
    local labelWidth, valueWidth = 0, 0
    for _, line in ipairs(lines) do
        labelWidth = math.max(labelWidth, textManager:MeasureStringX(font, line[1]))
        valueWidth = math.max(valueWidth, textManager:MeasureStringX(font, line[2]))
    end
    local width = math.max(self.width, PAD + labelWidth + PAD + valueWidth + PAD)
    local height = PAD + lineHeight * #lines + PAD
    local top = self.height
    -- Flip above the tooltip if the strip would leave the screen.
    if self:getAbsoluteY() + top + height > getCore():getScreenHeight() then
        top = -height
    end
    self:drawRect(0, top, width, height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)
    self:drawRectBorder(0, top, width, height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)
    local y = top + PAD
    for _, line in ipairs(lines) do
        self:drawText(line[1], PAD, y, 1.0, 1.0, 0.8, 1.0, font)
        self:drawText(line[2], PAD + labelWidth + PAD, y, 1.0, 1.0, 1.0, 1.0, font)
        y = y + lineHeight
    end
end
