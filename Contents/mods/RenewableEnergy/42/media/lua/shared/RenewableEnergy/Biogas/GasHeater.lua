-- The gas heater: a placed tile beside a digester that burns a little of its gas to keep it warm.
-- A lit heater shows the lit tile; the digester beside it does the burning in its own pass
-- (DigesterObject:heat), so it keeps warm while its chunk is unloaded too, and puts the heater out
-- when its gas runs out.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Biogas/Digester"

RenewableEnergy = RenewableEnergy or {}
local GasHeater = {}
RenewableEnergy.GasHeater = GasHeater

local Digester, Sprites = RenewableEnergy.Digester, RenewableEnergy.Sprites

GasHeater.ITEM = "RenewableEnergy.GasHeater"
-- What a lit heater keeps the digester beside it at, at least, and the gas it burns an hour.
GasHeater.TEMP = 25
GasHeater.M3_PER_HOUR = 0.1
-- A heater warms a digester on its own square or one next to it.
GasHeater.REACH = 1

GasHeater.LIGHT = "LightHeater"
GasHeater.OFF = "HeaterOff"

function GasHeater.isHeater(object)
    local name = object and Sprites.nameOf(object)
    return name == Sprites.gasHeater.off or name == Sprites.gasHeater.lit
end

function GasHeater.isLit(object)
    return Sprites.nameOf(object) == Sprites.gasHeater.lit
end

-- The first object within REACH of x, y, z on its level that `matches`, or nil.
local function findNear(x, y, z, matches)
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

--- The digester a heater at `heater` warms, or nil.
function GasHeater.digesterNear(heater)
    return findNear(heater:getX(), heater:getY(), heater:getZ(), Digester.isDigester)
end

--- A lit heater beside the digester at x, y, z, or nil.
function GasHeater.litHeaterNear(x, y, z)
    return findNear(x, y, z, function(object)
        return GasHeater.isHeater(object) and GasHeater.isLit(object)
    end)
end

--- The state of the heater that refuses `job`, as a translation key, or nil.
function GasHeater.blocker(job, heater)
    if job == GasHeater.LIGHT then
        if GasHeater.isLit(heater) then
            return "Tooltip_RenewableEnergy_HeaterLit"
        end
        local digester = GasHeater.digesterNear(heater)
        local summary = digester and Digester.currentSummary(digester)
        if not (summary and summary.gas > 0) then
            return "Tooltip_RenewableEnergy_NoDigesterNear"
        end
    elseif job == GasHeater.OFF then
        return not GasHeater.isLit(heater) and "Tooltip_RenewableEnergy_HeaterOut" or nil
    end
    return nil
end

local function notBroken(item)
    return not item:isBroken()
end

--- What refuses `character` doing `job` at `heater`: a translation key, or nil.
function GasHeater.refusal(character, job, heater)
    if not (heater and heater:getObjectIndex() ~= -1 and GasHeater.isHeater(heater)) then
        return "Tooltip_RenewableEnergy_NoHeater"
    end
    local blocker = GasHeater.blocker(job, heater)
    if blocker then
        return blocker
    end
    if job == GasHeater.LIGHT and not character:getInventory():containsTagEvalRecurse(ItemTag.START_FIRE, notBroken) then
        return "Tooltip_RenewableEnergy_NeedsFire"
    end
    return nil
end

--- Lights or puts out `heater`. Authority only.
function GasHeater.setLit(heater, lit)
    if GasHeater.isLit(heater) == lit then return end
    -- The tile's own sprite, with its properties; setSprite(name) would make a bare texture.
    heater:setSprite(getSprite(lit and Sprites.gasHeater.lit or Sprites.gasHeater.off))
    if isServer() then
        heater:transmitUpdatedSpriteToClients()
    end
end

--- Does `job` at `heater` for `character`, once its timed action finished. Authority only. Returns
--- whether it was done.
function GasHeater.perform(character, job, heater)
    if GasHeater.refusal(character, job, heater) then
        return false
    end
    local lit = job == GasHeater.LIGHT
    GasHeater.setLit(heater, lit)
    local digester = GasHeater.digesterNear(heater)
    local record = digester and Digester.recordOf(digester)
    if record then
        record.heaterLit = lit
        record:sendSummary()
    end
    return true
end

return GasHeater
