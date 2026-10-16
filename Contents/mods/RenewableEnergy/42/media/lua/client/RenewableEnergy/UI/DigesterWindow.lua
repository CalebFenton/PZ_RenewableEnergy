-- A digester's status window: its summary (RenewableEnergy.Digester.summaryOf) as rows.

require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/GasHeater"
require "RenewableEnergy/UI/Format"
require "RenewableEnergy/UI/SummaryWindow"

RenewableEnergy = RenewableEnergy or {}
local SummaryWindow = RenewableEnergy.SummaryWindow
local DigesterWindow = SummaryWindow:derive("RenewableEnergyDigesterWindow")
RenewableEnergy.DigesterWindow = DigesterWindow

local Digester, GasHeater, Format = RenewableEnergy.Digester, RenewableEnergy.GasHeater, RenewableEnergy.Format
local row = SummaryWindow.row

-- Below this the digester makes nothing.
local COLD_C = Digester.K_BY_TEMP[1][1]

--- The window's state line: the first that applies of startup, sour, cold, nothing in it, working.
function DigesterWindow.stateText(summary)
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

function DigesterWindow:titleOf(summary)
    return getText("IGUI_RenewableEnergy_Digester_" .. summary.tier)
end

function DigesterWindow:summaryNow()
    return Digester.summaryOf(self.object)
end

--- The rows the window shows for `summary`: { label, value, color }.
function DigesterWindow:rowsOf(summary)
    local rows = {}
    row(rows, "IGUI_RenewableEnergy_DigesterState", DigesterWindow.stateText(summary), (summary.sour or not summary.started) and "warn" or nil)
    row(rows, "IGUI_RenewableEnergy_DigesterTemp", Format.temperature(summary.temp), summary.temp < COLD_C and "warn" or nil)
    row(rows, "IGUI_RenewableEnergy_DigesterGas", Format.cubicMetres(summary.gas, 2) .. " / " .. Format.cubicMetres(summary.capacity, 2))
    row(rows, "IGUI_RenewableEnergy_DigesterMaking", getText("IGUI_RenewableEnergy_PerDay", Format.cubicMetres(summary.madePerDay, 2)))
    row(rows, "IGUI_RenewableEnergy_DigesterHolder", holderText(summary), (summary.torn or summary.leaking) and "warn" or nil)
    row(rows, "IGUI_RenewableEnergy_DigesterFill", Format.percent(summary.fill))
    row(rows, "IGUI_RenewableEnergy_DigesterHopper", tostring(summary.hopper))
    row(rows, "IGUI_RenewableEnergy_DigesterSludge", Format.percent(summary.sludge / 100), summary.sludge >= Digester.SLUDGE_SLOW and "warn" or nil)
    row(rows, "IGUI_RenewableEnergy_DigesterSmell", smellText(summary.stink), summary.stink >= Digester.SMELL_SCORES[2] and "warn" or nil)
    if summary.scrubber then
        row(rows, "IGUI_RenewableEnergy_DigesterScrubber", getText("IGUI_RenewableEnergy_ScrubberState",
            string.format("%.1f", summary.scrubCO2), string.format("%.1f", summary.scrubWool)),
            (summary.scrubCO2 <= 0 or summary.scrubWool <= 0) and "warn" or nil)
    end
    if summary.heaterLit then
        row(rows, "IGUI_RenewableEnergy_DigesterHeater", getText("IGUI_RenewableEnergy_HeaterBurning",
            getText("IGUI_RenewableEnergy_PerDay", Format.cubicMetres(GasHeater.M3_PER_HOUR * 24, 1))))
    end
    if summary.leaking then
        row(rows, "IGUI_RenewableEnergy_DigesterLeak", getText("IGUI_RenewableEnergy_DigesterLeaking"), "warn")
    end
    return rows
end

--- Opens `playerNum`'s window on the digester `digester`.
function DigesterWindow.open(playerNum, digester)
    return DigesterWindow:openOn(playerNum, digester)
end

return DigesterWindow
