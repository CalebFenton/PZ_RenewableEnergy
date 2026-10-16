-- The digesters on the authority (RenewableEnergy.ObjectSystem), and the jobs players do at them
-- and at their gas heaters, whose rules are DigesterJobs' and GasHeater's.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Materials"
require "RenewableEnergy/ObjectSystem"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/DigesterJobs"
require "RenewableEnergy/Biogas/GasHeater"
local DigesterObject = require "RenewableEnergy/Biogas/DigesterObject"

RenewableEnergy = RenewableEnergy or {}
local Digester, DigesterJobs, GasHeater = RenewableEnergy.Digester, RenewableEnergy.DigesterJobs, RenewableEnergy.GasHeater
local Materials, ObjectSystem = RenewableEnergy.Materials, RenewableEnergy.ObjectSystem

local DigesterSystem = ObjectSystem.define({
    name = "Digester", kind = "digester", owner = Digester, Object = DigesterObject, isObject = Digester.isDigester,
})
RenewableEnergy.DigesterSystem = DigesterSystem

-- Jobs ------------------------------------------------------------------------------------------

-- Take Sludge, as vanilla's ISGetCompost fills compost bags from a composter: into the part-filled
-- compost bag `item`, or a new one for the empty sandbag `item`.
local function takeSludge(character, digester, item)
    local perUse = DigesterJobs.sludgePerUse()
    local usesPerBag = math.floor(1 / getScriptManager():FindItem(DigesterJobs.COMPOST_BAG):getUseDelta() + 0.5)
    local uses = math.floor(digester.sludge / perUse)
    if item:getFullType() == DigesterJobs.COMPOST_BAG then
        uses = math.min(uses, usesPerBag - item:getCurrentUses())
        if uses <= 0 then
            return false
        end
        item:setCurrentUses(item:getCurrentUses() + uses)
        syncItemFields(character, item)
    else
        uses = math.min(uses, usesPerBag)
        if uses <= 0 then
            return false
        end
        RenewableEnergy.takeItem(character, item)
        local bag = instanceItem(DigesterJobs.COMPOST_BAG)
        bag:setCurrentUses(uses)
        RenewableEnergy.giveItems(character, bag)
    end
    digester.sludge = math.max(0, digester.sludge - uses * perUse)
    return true
end

-- Fills `tank` from the digester as far as `job` goes. Returns the m³ moved.
local function fillTank(character, job, digester, tank)
    local plain, scrubbed, perUse = DigesterJobs.fillUses(job, digester, tank)
    if plain + scrubbed <= 0 then
        return 0
    end
    tank:setCurrentUses(tank:getCurrentUses() + plain + scrubbed)
    syncItemFields(character, tank)
    local m3 = (plain + scrubbed) * perUse
    digester.gas = math.max(0, digester.gas - m3)
    if scrubbed > 0 then
        digester.scrubCO2 = math.max(0, digester.scrubCO2 - scrubbed * perUse)
        digester.scrubWool = math.max(0, digester.scrubWool - scrubbed * perUse)
    end
    return m3
end

-- What each job does to the digester `digester` (its tile `isoObject`) beyond taking its
-- materials. `item` is the job's bag or tank. Returns whether it was done.
local DO = {
    [DigesterJobs.TAKE_SLUDGE] = function(character, digester, isoObject, item)
        return takeSludge(character, digester, item)
    end,
    [DigesterJobs.VENT] = function(character, digester)
        digester.gas = 0
        if digester.indoors then
            digester.leakHours = math.max(digester.leakHours, 1)
        end
        return true
    end,
    [DigesterJobs.UPGRADE] = function(character, digester, isoObject)
        digester:upgrade(isoObject)
        return true
    end,
    [DigesterJobs.FIT_SCRUBBER] = function(character, digester)
        digester.scrubber = true
        digester.scrubCO2 = 0
        digester.scrubWool = Digester.WOOL_M3
        return true
    end,
    [DigesterJobs.REPACK_WOOL] = function(character, digester)
        digester.scrubWool = Digester.WOOL_M3
        return true
    end,
}
for _, job in ipairs({ DigesterJobs.REPLACE_BAGS, DigesterJobs.SEW_TARP }) do
    DO[job] = function(character, digester)
        digester.holder = job == DigesterJobs.SEW_TARP and "tarp" or "bags"
        digester.holderCondition = 100
        digester.gas = 0
        return true
    end
end
for _, job in ipairs({ DigesterJobs.FILL_PUMP, DigesterJobs.FILL_COMPRESSOR }) do
    DO[job] = function(character, digester, isoObject, item)
        local m3 = fillTank(character, job, digester, item)
        if m3 > 0 and job == DigesterJobs.FILL_PUMP then
            character:getStats():remove(CharacterStat.ENDURANCE, m3 * Digester.PUMP_ENDURANCE_PER_M3)
        end
        return m3 > 0
    end
end
for job, charge in pairs(DigesterJobs.CHARGES) do
    DO[job] = function(character, digester)
        digester.scrubCO2 = Digester.SCRUB_M3[charge]
        return true
    end
end

local function apply(character, job, digester, isoObject, item)
    if not DO[job](character, digester, isoObject, item) then
        return false
    end
    Materials.consume(character, DigesterJobs.MATERIALS[job])
    local xp = DigesterJobs.XP[job]
    if xp then
        addXp(character, Perks[xp.perk], xp.amount)
    end
    return true
end

-- Lights or puts out `heater`. Its digester is brought up to now first, so the time before counts
-- at the heater's old state.
local function performHeater(character, job, heater)
    local digester = GasHeater.digesterNear(heater)
    local record = digester and Digester.recordOf(digester)
    if record then
        record:advance(record:elapsedHours())
    end
    local done = not GasHeater.refusal(character, job, heater)
    if done then
        Materials.consume(character, GasHeater.materials(job))
        local lit = job == GasHeater.LIGHT
        if record then
            record:setHeaterLit(heater, lit)
        else
            DigesterObject.showHeaterLit(heater, lit)
        end
    end
    if record then
        record:afterChange()
    end
    return done
end

--- Does `job` for `character` at `isoObject`, a digester or its gas heater, on the authority, once
--- the timed action that does it has finished. `item` is the job's bag or tank. Returns whether it
--- was done.
function DigesterSystem.perform(character, job, isoObject, item)
    if GasHeater.isHeater(isoObject) then
        return performHeater(character, job, isoObject)
    end
    return ObjectSystem.perform(Digester, DigesterJobs, apply, character, job, isoObject, item)
end

return DigesterSystem
