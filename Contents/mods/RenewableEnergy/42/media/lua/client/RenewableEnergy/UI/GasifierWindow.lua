-- A gasifier's status window: the digester's window (RenewableEnergy.DigesterWindow) reading the
-- gasifier's summary, which every client keeps.

require "RenewableEnergy/UI/DigesterWindow"
require "RenewableEnergy/WoodGas/Gasifier"

RenewableEnergy = RenewableEnergy or {}
local DigesterWindow = RenewableEnergy.DigesterWindow
local GasifierWindow = DigesterWindow:derive("RenewableEnergyGasifierWindow")
RenewableEnergy.GasifierWindow = GasifierWindow

local Gasifier = RenewableEnergy.Gasifier
local percent = DigesterWindow.percent

-- The ash pit warns from here.
local ASH_WARN = 80

function GasifierWindow.stateText(summary)
    if summary.lit then
        return getText("IGUI_RenewableEnergy_GasifierLit")
    elseif summary.cold then
        return getText("IGUI_RenewableEnergy_GasifierCold")
    end
    return getText("IGUI_RenewableEnergy_GasifierOut")
end

--- The rows the window shows for `summary`: { label, value, color }.
function GasifierWindow.rows(summary)
    local rows = {}
    local function add(key, value, color)
        table.insert(rows, { label = getText(key), value = value, color = color or "text" })
    end
    add("IGUI_RenewableEnergy_GasifierState", GasifierWindow.stateText(summary))
    add("IGUI_RenewableEnergy_GasifierWood", string.format("%.1f kg", summary.hopperKg), summary.hopperKg <= 0 and "warn" or nil)
    add("IGUI_RenewableEnergy_GasifierAsh", percent(summary.ash / 100), summary.ash >= ASH_WARN and "warn" or nil)
    add("IGUI_RenewableEnergy_GasifierFilter", getText("IGUI_RenewableEnergy_FilterState", summary.clean, summary.tarry),
        summary.clean == 0 and "warn" or nil)
    add("IGUI_RenewableEnergy_GasifierOutput", percent(summary.output), summary.output < 1 and "warn" or nil)
    if summary.wear > 1 then
        add("IGUI_RenewableEnergy_GasifierWear", getText("IGUI_RenewableEnergy_WearTimes", string.format("%.1f", summary.wear)), "warn")
    end
    add("IGUI_RenewableEnergy_GasifierLine", getText(summary.piped and "IGUI_RenewableEnergy_Piped" or "IGUI_RenewableEnergy_NotPiped"))
    return rows
end

function GasifierWindow:titleOf(summary)
    return getText("IGUI_RenewableEnergy_Gasifier_" .. summary.tier)
end

function GasifierWindow:summaryNow()
    return Gasifier.summaryOf(self.object)
end

function GasifierWindow:rowsOf(summary)
    return GasifierWindow.rows(summary)
end

--- Opens `playerNum`'s window on the gasifier `gasifier`.
function GasifierWindow.open(playerNum, gasifier)
    return GasifierWindow:openOn(playerNum, gasifier)
end

return GasifierWindow
