-- A digester's status window: its summary (RenewableEnergy.Digester.summaryOf) as rows.

local Digester = require "RenewableEnergy/Biogas/Digester"
local GasHeater = require "RenewableEnergy/Biogas/GasHeater"
local Format = require "RenewableEnergy/UI/Format"
local GasKit = require "RenewableEnergy/GasLine/GasKit"
local SummaryWindow = require "RenewableEnergy/UI/SummaryWindow"

local DigesterWindow = SummaryWindow:derive("RenewableEnergyDigesterWindow")
DigesterWindow.owner = Digester

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

-- Gas with the share of a generator tank it runs, so a player can judge m³ against petrol.
local TANK_M3 = GasKit.TANK_LITRES * GasKit.M3_PER_LITRE
local function gasText(m3, shown)
    return getText("IGUI_RenewableEnergy_GasTankShare", shown or Format.cubicMetres(m3), math.floor(m3 / TANK_M3 * 100 + 0.5))
end

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
        return Format.withShare(name, summary.holderCondition / 100)
    end
    return name
end

-- Whether a compressor is fitted and, if so, whether it has power to run.
local function compressorText(summary)
    if not summary.compressor then
        return getText("IGUI_RenewableEnergy_CompressorNone")
    end
    return getText(summary.powered and "IGUI_RenewableEnergy_CompressorPowered" or "IGUI_RenewableEnergy_CompressorNoPower")
end

--- The rows the window shows for `summary`: { label, value, color }.
function DigesterWindow:rowsOf(summary)
    local rows = {}
    row(rows, "IGUI_RenewableEnergy_State", stateText(summary), (summary.sour or not summary.started) and "bad" or nil)
    row(rows, "IGUI_RenewableEnergy_DigesterTemp", Format.temperature(summary.temp), summary.temp < COLD_C and "bad" or nil)
    row(rows, "IGUI_RenewableEnergy_DigesterGas", gasText(summary.gas,
        Format.cubicMetres(summary.gas) .. " / " .. Format.cubicMetres(summary.capacity)))
    row(rows, "IGUI_RenewableEnergy_DigesterMaking", getText("IGUI_RenewableEnergy_PerDay", gasText(summary.madePerDay)))
    row(rows, "IGUI_RenewableEnergy_DigesterHolder", holderText(summary), (summary.torn or summary.leaking) and "bad" or nil)
    -- The feed in the tank isn't used up but gas still to come, which a player reads off here.
    row(rows, "IGUI_RenewableEnergy_DigesterFill", getText("IGUI_RenewableEnergy_DigesterToCome", Format.percent(summary.fill),
        Format.number(summary.toCome, 1)))
    row(rows, "IGUI_RenewableEnergy_DigesterHopper", tostring(summary.hopper))
    row(rows, "IGUI_RenewableEnergy_DigesterSludge", Format.percent(summary.sludge / 100), summary.sludge >= Digester.SLUDGE_SLOW and "bad" or nil)
    row(rows, "IGUI_RenewableEnergy_DigesterSmell", smellText(summary.stink), summary.stink >= Digester.SMELL_SCORES[2] and "bad" or nil)
    if summary.scrubber then
        row(rows, "IGUI_RenewableEnergy_DigesterScrubber", getText("IGUI_RenewableEnergy_ScrubberState",
            Format.number(summary.scrubCO2, 1), Format.number(summary.scrubWool, 1)),
            Digester.scrubLeft(summary) <= 0 and "bad" or nil)
    end
    row(rows, "IGUI_RenewableEnergy_DigesterCompressor", compressorText(summary),
        summary.compressor and not summary.powered and "bad" or nil)
    if summary.heaterLit then
        row(rows, "IGUI_RenewableEnergy_DigesterHeater", getText("IGUI_RenewableEnergy_HeaterBurning",
            getText("IGUI_RenewableEnergy_PerDay", Format.cubicMetres(GasHeater.m3PerHour() * 24))))
    end
    if summary.leaking then
        row(rows, "IGUI_RenewableEnergy_DigesterLeak", getText("IGUI_RenewableEnergy_DigesterLeaking"), "bad")
    end
    return rows
end

return DigesterWindow
