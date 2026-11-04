-- Adds a strip of figures under the tooltip of a battery, a solar module or a panel mount: a
-- battery's capacity and stored energy, since watt-hours decide which battery goes into a bank and
-- a worn battery holds less than its rating; a module's output now against its rating, since a
-- worn or cracked module makes less, and a mount's for each module it holds and in all. Java draws
-- the tooltip, so the rows are a strip drawn after ISToolTipInv.render. Named to load after every
-- other mod's client Lua, so it wraps their render rather than being replaced.

require "ISUI/ISToolTipInv"
local Specs = require "RenewableEnergy/Specs"
local Recipes = require "RenewableEnergy/Recipes"
local Battery = require "RenewableEnergy/PowerBank/Battery"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local Format = require "RenewableEnergy/UI/Format"

local PAD = 5

-- "150 of 160 W": what modules make in full sun now, of what they make new (Panel.moduleWatts).
local function outputOf(now, rated)
    return getText("IGUI_RenewableEnergy_OutputOf", string.format("%d", round(now)), Format.watts(rated))
end

-- The strip's rows of `item` as { label, value }, or nil for an item without one.
local function linesOf(item)
    local fullType = item:getFullType()
    if Battery.isBattery(item) then
        local wh = Battery.nominalWh(item)
        return {
            { getText("IGUI_RenewableEnergy_Capacity") .. ":", Format.wattHours(wh) },
            { getText("IGUI_RenewableEnergy_Stored") .. ":", Format.wattHours(wh * item:getCurrentUsesFloat()) },
        }
    end
    local outputLabel = getText("IGUI_RenewableEnergy_Output") .. ":"
    local module = Specs.modules[fullType]
    if module then
        return { { outputLabel, outputOf(Panel.moduleWatts(fullType, item:getCondition()), module.watts) } }
    end
    local mount = Recipes.MOUNTS[fullType]
    if not mount then
        return nil
    end
    local lines, now, rated = {}, 0, 0
    for _, held in ipairs(Panel.modulesOf(item, mount.kind)) do
        local watts, best = Panel.moduleWatts(held.type, held.condition), Specs.modules[held.type].watts
        table.insert(lines, { getItemNameFromFullType(held.type) .. ":", outputOf(watts, best) })
        now, rated = now + watts, rated + best
    end
    table.insert(lines, { outputLabel, outputOf(now, rated) })
    return lines
end

-- The strip of the item last drawn, rebuilt only when the item, its charge, its condition or the
-- font changes, since render runs every frame. A mount's modules change only by making a new item.
local strip = {}

local function stripFor(item, font)
    local uses, condition = item:getCurrentUsesFloat(), item:getCondition()
    if strip.item == item and strip.uses == uses and strip.condition == condition and strip.font == font then
        return strip
    end
    local lines = linesOf(item)
    local textManager = getTextManager()
    local labelWidth, valueWidth = 0, 0
    for _, line in ipairs(lines or {}) do
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
    -- Vanilla skips the tooltip while a context menu is open. It also shows fluid containers
    -- (ISFluidBar) and resources (ISEnergyBar), which lack the item methods the strip reads.
    if not instanceof(self.item, "InventoryItem") or (ISContextMenu.instance and ISContextMenu.instance.visibleCheck) then
        return
    end

    local rows = stripFor(self.item, self.tooltip:getFont())
    if not rows.lines then
        return
    end
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
