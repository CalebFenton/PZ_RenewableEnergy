-- The gas heater: a placed tile beside a digester that burns a little of its gas to keep it warm.
-- It warms the one digester digesterNear picks, which does the burning in its own pass, so it keeps
-- warm while unloaded too and puts the heater out when its gas runs out.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Materials"
require "RenewableEnergy/GasJobs"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/GasLine/GasKit"

RenewableEnergy = RenewableEnergy or {}
local GasHeater = {}
RenewableEnergy.GasHeater = GasHeater

local Digester, GasKit = RenewableEnergy.Digester, RenewableEnergy.GasKit
local Sprites, Materials = RenewableEnergy.Sprites, RenewableEnergy.Materials

-- What a lit heater keeps its digester at, at least: as warm as vanilla's lit barbecue keeps its
-- square (IsoBarbecue's heat source).
GasHeater.TEMP = 25

--- The gas a lit heater burns an hour: a small flame, billed as an idling generator's so it follows
--- the GeneratorFuelConsumption option.
function GasHeater.m3PerHour()
    return GasKit.idleLitresPerHour() * GasKit.M3_PER_LITRE
end

-- How many squares from its digester a heater still warms it.
GasHeater.REACH = 1

GasHeater.LIGHT = "LightHeater"
GasHeater.OFF = "HeaterOff"

function GasHeater.isHeater(object)
    return Sprites.kindOf(Sprites.nameOf(object)) == "gasHeater"
end

function GasHeater.isLit(object)
    return Sprites.nameOf(object) == Sprites.gasHeater.lit
end

-- The first object within REACH of `object`'s square on its level that `matches`, or nil.
local function findNear(object, matches)
    local x, y, z = object:getX(), object:getY(), object:getZ()
    for dx = -GasHeater.REACH, GasHeater.REACH do
        for dy = -GasHeater.REACH, GasHeater.REACH do
            local found = RenewableEnergy.findObjectOn(getSquare(x + dx, y + dy, z), matches)
            if found then
                return found
            end
        end
    end
    return nil
end

--- The digester `heater` warms, or nil. This alone decides which, for the warmth and the gas.
function GasHeater.digesterNear(heater)
    return findNear(heater, Digester.isDigester)
end

--- The lit heater that warms `digester`, or nil.
function GasHeater.litHeaterFor(digester)
    return findNear(digester, function(object)
        if not (GasHeater.isHeater(object) and GasHeater.isLit(object)) then
            return false
        end
        local warmed = GasHeater.digesterNear(object)
        return warmed ~= nil and warmed:getX() == digester:getX() and warmed:getY() == digester:getY()
            and warmed:getZ() == digester:getZ()
    end)
end

-- Every job, by name, as GasJobs.define has them, read against the heater itself: minutes, as long
-- as lighting a lamp; blocker(heater); materials; doneSound. `lit`: how it leaves the heater.
GasHeater.JOBS = {
    [GasHeater.LIGHT] = {
        minutes = 1, lit = true, doneSound = "CampfireLight",
        blocker = function(heater)
            if GasHeater.isLit(heater) then
                return "Tooltip_RenewableEnergy_HeaterLit"
            end
            local digester = GasHeater.digesterNear(heater)
            local summary = digester and Digester.currentSummary(digester)
            return not (summary and summary.gas > 0) and "Tooltip_RenewableEnergy_NoDigesterNear" or nil
        end,
        materials = { Materials.FIRE_STARTER },
    },
    [GasHeater.OFF] = {
        minutes = 1, lit = false,
        blocker = function(heater)
            return not GasHeater.isLit(heater) and "Tooltip_RenewableEnergy_HeaterOut" or nil
        end,
    },
}

RenewableEnergy.GasJobs.define(GasHeater, {
    subjectOf = function(heater)
        return RenewableEnergy.onSquare(heater) and GasHeater.isHeater(heater) and heater or nil
    end,
    missing = "Tooltip_RenewableEnergy_NoHeater",
})

return GasHeater
