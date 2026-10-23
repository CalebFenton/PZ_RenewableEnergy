-- A gasifier's status window: its summary (RenewableEnergy.Gasifier.summaryOf) as rows.

require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/SummaryWindow"

RenewableEnergy = RenewableEnergy or {}
local SummaryWindow = RenewableEnergy.SummaryWindow
local GasifierWindow = SummaryWindow:derive("RenewableEnergyGasifierWindow")
RenewableEnergy.GasifierWindow = GasifierWindow

local Gasifier, Format = RenewableEnergy.Gasifier, RenewableEnergy.Format
local row = SummaryWindow.row

-- The ash pit warns from here.
local ASH_WARN = 80

local function stateText(summary)
    if summary.lit then
        return getText("IGUI_RenewableEnergy_GasifierLit")
    elseif summary.cold then
        return getText("IGUI_RenewableEnergy_GasifierCold")
    end
    return getText("IGUI_RenewableEnergy_GasifierOut")
end

function GasifierWindow:titleOf(summary)
    return getText("IGUI_RenewableEnergy_Gasifier_" .. summary.tier)
end

function GasifierWindow:summaryNow()
    return Gasifier.summaryOf(self.object)
end

--- The rows the window shows for `summary`: { label, value, color }.
function GasifierWindow:rowsOf(summary)
    local rows = {}
    row(rows, "IGUI_RenewableEnergy_GasifierState", stateText(summary))
    row(rows, "IGUI_RenewableEnergy_GasifierWood", string.format("%.1f kg", summary.hopperKg), summary.hopperKg <= 0 and "warn" or nil)
    row(rows, "IGUI_RenewableEnergy_GasifierAsh", Format.percent(summary.ash / 100), summary.ash >= ASH_WARN and "warn" or nil)
    row(rows, "IGUI_RenewableEnergy_GasifierFilter", getText("IGUI_RenewableEnergy_FilterState", summary.clean, summary.tarry),
        summary.clean == 0 and "warn" or nil)
    row(rows, "IGUI_RenewableEnergy_GasifierCondensate", string.format("%.1f / %d L", summary.condensate, Gasifier.CONDENSATE_MAX),
        summary.condensate >= Gasifier.CONDENSATE_MAX and "warn" or nil)
    row(rows, "IGUI_RenewableEnergy_GasifierOutput", Format.percent(summary.output), summary.output < 1 and "warn" or nil)
    if summary.wear > 1 then
        row(rows, "IGUI_RenewableEnergy_GasifierWear", getText("IGUI_RenewableEnergy_WearTimes", string.format("%.1f", summary.wear)), "warn")
    end
    row(rows, "IGUI_RenewableEnergy_GasifierLine", getText(summary.piped and "IGUI_RenewableEnergy_Piped" or "IGUI_RenewableEnergy_NotPiped"))
    return rows
end

--- Opens `playerNum`'s window on the gasifier `gasifier`.
function GasifierWindow.open(playerNum, gasifier)
    return GasifierWindow:openOn(playerNum, gasifier)
end

return GasifierWindow
