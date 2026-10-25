-- A gasifier's status window: its summary (RenewableEnergy.Gasifier.summaryOf) as rows.

require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/SummaryWindow"

RenewableEnergy = RenewableEnergy or {}
local SummaryWindow = RenewableEnergy.SummaryWindow
local GasifierWindow = SummaryWindow:derive("RenewableEnergyGasifierWindow")
RenewableEnergy.GasifierWindow = GasifierWindow
GasifierWindow.owner = RenewableEnergy.Gasifier

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

--- The rows the window shows for `summary`: { label, value, color }.
function GasifierWindow:rowsOf(summary)
    local rows = {}
    row(rows, "IGUI_RenewableEnergy_State", stateText(summary))
    row(rows, "IGUI_RenewableEnergy_GasifierWood", Format.kilograms(summary.hopperKg), summary.hopperKg <= 0 and "bad" or nil)
    row(rows, "IGUI_RenewableEnergy_GasifierAsh", Format.percent(summary.ash / 100), summary.ash >= ASH_WARN and "bad" or nil)
    row(rows, "IGUI_RenewableEnergy_GasifierFilter", getText("IGUI_RenewableEnergy_FilterState", summary.clean, summary.tarry),
        summary.clean == 0 and "bad" or nil)
    row(rows, "IGUI_RenewableEnergy_GasifierCondensate",
        Format.number(summary.condensate, 1) .. " / " .. Format.litres(Gasifier.CONDENSATE_MAX, 0),
        summary.condensate >= Gasifier.CONDENSATE_MAX and "bad" or nil)
    row(rows, "IGUI_RenewableEnergy_GasifierOutput", Format.percent(summary.output), summary.output < 1 and "bad" or nil)
    if summary.wear > 1 then
        row(rows, "IGUI_RenewableEnergy_GasifierWear", getText("IGUI_RenewableEnergy_WearTimes", Format.number(summary.wear, 1)), "bad")
    end
    row(rows, "IGUI_RenewableEnergy_GasifierLine", getText(summary.piped and "IGUI_RenewableEnergy_Piped" or "IGUI_RenewableEnergy_NotPiped"))
    return rows
end

return GasifierWindow
