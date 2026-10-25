-- A digester's status window: its summary (RenewableEnergy.Digester.summaryOf) as rows.

require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/GasHeater"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/SummaryWindow"

RenewableEnergy = RenewableEnergy or {}
local SummaryWindow = RenewableEnergy.SummaryWindow
local DigesterWindow = SummaryWindow:derive("RenewableEnergyDigesterWindow")
RenewableEnergy.DigesterWindow = DigesterWindow
DigesterWindow.owner = RenewableEnergy.Digester

local Digester, GasHeater, Format = RenewableEnergy.Digester, RenewableEnergy.GasHeater, RenewableEnergy.Format
local row = SummaryWindow.row

-- Below this the digester makes nothing.
local COLD_C = Digester.K_BY_TEMP[1][1]

-- The state row: the first that applies of never fed, starting up, sour, cold, nothing left to
-- digest, working.
local function stateText(summary)
    if not summary.fed then
        return getText("IGUI_RenewableEnergy_DigesterEmpty")
    elseif not summary.started then
        return getText("IGUI_RenewableEnergy_DigesterStarting", Format.percent(summary.startup))
    elseif summary.sour then
        return getText("IGUI_RenewableEnergy_DigesterSour")
    elseif summary.temp < COLD_C then
        return getText("IGUI_RenewableEnergy_DigesterCold")
    elseif summary.fill <= 0 then
        return getText("IGUI_RenewableEnergy_DigesterHungry")
    end
    return getText("IGUI_RenewableEnergy_DigesterWorking")
end

-- Each smell level's word, from none below Digester.SMELL_SCORES' first.
local SMELLS = { "IGUI_RenewableEnergy_SmellNone", "IGUI_RenewableEnergy_SmellFaint", "IGUI_RenewableEnergy_SmellStrong",
    "IGUI_RenewableEnergy_SmellVile" }

local function smellText(score)
    local level = 0
    for i, from in ipairs(Digester.SMELL_SCORES) do
        if score >= from then
            level = i
        end
    end
    return getText(SMELLS[level + 1])
end

-- The holder, with its condition if it wears.
local function holderText(summary)
    local name = getText("IGUI_RenewableEnergy_Holder_" .. summary.holder)
    if summary.torn then
        return getText("IGUI_RenewableEnergy_HolderTorn", name)
    end
    if Digester.HOLDERS[summary.holder].wearPerDay then
        return name .. " " .. Format.percent(summary.holderCondition / 100)
    end
    return name
end

--- The rows the window shows for `summary`: { label, value, color }.
function DigesterWindow:rowsOf(summary)
    local rows = {}
    row(rows, "IGUI_RenewableEnergy_State", stateText(summary), (summary.sour or not summary.started) and "bad" or nil)
    row(rows, "IGUI_RenewableEnergy_DigesterTemp", Format.temperature(summary.temp), summary.temp < COLD_C and "bad" or nil)
    row(rows, "IGUI_RenewableEnergy_DigesterGas", Format.cubicMetres(summary.gas, 2) .. " / " .. Format.cubicMetres(summary.capacity, 2))
    row(rows, "IGUI_RenewableEnergy_DigesterMaking", getText("IGUI_RenewableEnergy_PerDay", Format.cubicMetres(summary.madePerDay, 2)))
    row(rows, "IGUI_RenewableEnergy_DigesterHolder", holderText(summary), (summary.torn or summary.leaking) and "bad" or nil)
    row(rows, "IGUI_RenewableEnergy_DigesterFill", Format.percent(summary.fill))
    row(rows, "IGUI_RenewableEnergy_DigesterHopper", tostring(summary.hopper))
    row(rows, "IGUI_RenewableEnergy_DigesterSludge", Format.percent(summary.sludge / 100), summary.sludge >= Digester.SLUDGE_SLOW and "bad" or nil)
    row(rows, "IGUI_RenewableEnergy_DigesterSmell", smellText(summary.stink), summary.stink >= Digester.SMELL_SCORES[2] and "bad" or nil)
    if summary.scrubber then
        row(rows, "IGUI_RenewableEnergy_DigesterScrubber", getText("IGUI_RenewableEnergy_ScrubberState",
            Format.number(summary.scrubCO2, 1), Format.number(summary.scrubWool, 1)),
            (summary.scrubCO2 <= 0 or summary.scrubWool <= 0) and "bad" or nil)
    end
    if summary.heaterLit then
        row(rows, "IGUI_RenewableEnergy_DigesterHeater", getText("IGUI_RenewableEnergy_HeaterBurning",
            getText("IGUI_RenewableEnergy_PerDay", Format.cubicMetres(GasHeater.m3PerHour() * 24, 2))))
    end
    if summary.leaking then
        row(rows, "IGUI_RenewableEnergy_DigesterLeak", getText("IGUI_RenewableEnergy_DigesterLeaking"), "bad")
    end
    return rows
end

return DigesterWindow
