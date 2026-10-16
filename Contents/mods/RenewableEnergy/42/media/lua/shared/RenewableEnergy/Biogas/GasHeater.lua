-- The gas heater: a placed tile beside a digester that burns a little of its gas to keep it warm.
-- A lit heater shows the lit tile. It warms one digester, the one digesterNear picks, which does
-- the burning in its own pass (DigesterObject), so it keeps warm while its chunk is unloaded too,
-- and puts the heater out when its gas runs out. Lighting and putting it out are jobs the
-- authority does (server/RenewableEnergy/Biogas/DigesterSystem.lua).

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Materials"
require "RenewableEnergy/Biogas/Digester"

RenewableEnergy = RenewableEnergy or {}
local GasHeater = {}
RenewableEnergy.GasHeater = GasHeater

local Digester, Sprites, Materials = RenewableEnergy.Digester, RenewableEnergy.Sprites, RenewableEnergy.Materials

-- What a lit heater keeps its digester at, at least, and the gas it burns an hour.
GasHeater.TEMP = 25
GasHeater.M3_PER_HOUR = 0.1
-- A heater warms a digester on its own square or one next to it.
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

-- Every job, by name, as DigesterJobs.JOBS has them: minutes, as long as lighting a lamp;
-- blocker(heater); materials; doneSound. `lit`: how it leaves the heater.
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

--- What `job` takes (RenewableEnergy.Materials).
function GasHeater.materials(job)
    return GasHeater.JOBS[job].materials or {}
end

--- What `job` takes of `character`, as needs (RenewableEnergy.firstUnmet, RenewableEnergy.Needs).
function GasHeater.needs(character, job)
    return Materials.needs(character, GasHeater.materials(job))
end

--- The state of `heater` that refuses `job`, as a translation key, or nil.
function GasHeater.blocker(job, heater)
    return GasHeater.JOBS[job].blocker(heater)
end

--- What refuses `character` doing `job` at `heater`: a blocker key, "short" when they lack a
--- need, or nil.
function GasHeater.refusal(character, job, heater)
    if not (RenewableEnergy.onSquare(heater) and GasHeater.isHeater(heater) and GasHeater.JOBS[job]) then
        return "Tooltip_RenewableEnergy_NoHeater"
    end
    return GasHeater.blocker(job, heater)
        or (RenewableEnergy.firstUnmet(GasHeater.needs(character, job)) and "short")
        or nil
end

return GasHeater
