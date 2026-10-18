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
local Materials, ObjectSystem, Sprites = RenewableEnergy.Materials, RenewableEnergy.ObjectSystem, RenewableEnergy.Sprites

local DigesterSystem = ObjectSystem.define({
    name = "Digester", kind = "digester", owner = Digester, Object = DigesterObject, isObject = Digester.isDigester,
})
RenewableEnergy.DigesterSystem = DigesterSystem

-- A barrel digester is the entity of the barrel it was built from, which the build menu builds on
-- the Metal Drum's. Swapped before the record reads the tile, and before ISBuildIsoEntity:create
-- sends the object, so clients get it whole.
local onCreate = DigesterSystem.OnCreate
function DigesterSystem.OnCreate(params)
    local thumpable, data = params.thumpable, params.craftRecipeData
    local items = thumpable and data and data:getAllConsumedItems()
    for i = 0, items and items:size() - 1 or -1 do
        local tile = Sprites.digester.barrel[items:get(i):getType()]
        if tile then
            RenewableEnergy.setEntityTile(thumpable, tile)
            break
        end
    end
    onCreate(params)
end

-- What each job does to the digester `digester` (its tile `isoObject`) beyond taking its
-- materials, by its row of DigesterJobs.JOBS. `item` is the job's bag or tank. Returns whether it
-- was done.

-- Take Sludge, as vanilla's ISGetCompost fills compost bags from a composter: into the part-filled
-- compost bag `item`, or a new one for the empty sandbag `item`.
local function takeSludge(character, digester, row, isoObject, item)
    local perUse = DigesterJobs.sludgePerUse()
    local uses = math.floor(digester.sludge / perUse)
    if item:getFullType() == DigesterJobs.COMPOST_BAG then
        uses = math.min(uses, item:getMaxUses() - item:getCurrentUses())
        if uses <= 0 then
            return false
        end
        item:setCurrentUses(item:getCurrentUses() + uses)
        syncItemFields(character, item)
    else
        local bag = instanceItem(DigesterJobs.COMPOST_BAG)
        uses = math.min(uses, bag:getMaxUses())
        if uses <= 0 then
            return false
        end
        RenewableEnergy.takeItem(character, item)
        bag:setCurrentUses(uses)
        RenewableEnergy.giveItems(character, bag)
    end
    digester.sludge = math.max(0, digester.sludge - uses * perUse)
    return true
end

local function vent(character, digester)
    digester.gas = 0
    if digester.indoors then
        digester.leakHours = math.max(digester.leakHours, 1)
    end
    return true
end

-- A new holder of the row's kind, empty.
local function newHolder(character, digester, row)
    digester.holder = row.holder
    digester.holderCondition = 100
    digester.gas = 0
    return true
end

local function upgrade(character, digester, row, isoObject)
    digester:upgrade(isoObject)
    return true
end

-- Fills `tank` as far as the row's fill goes.
local function fill(character, digester, row, isoObject, tank)
    local plain, scrubbed, perUse = DigesterJobs.fillUses(row.fill, digester, tank)
    if plain + scrubbed <= 0 then
        return false
    end
    tank:setCurrentUses(tank:getCurrentUses() + plain + scrubbed)
    syncItemFields(character, tank)
    local m3 = (plain + scrubbed) * perUse
    digester.gas = math.max(0, digester.gas - m3)
    if scrubbed > 0 then
        digester.scrubCO2 = math.max(0, digester.scrubCO2 - scrubbed * perUse)
        digester.scrubWool = math.max(0, digester.scrubWool - scrubbed * perUse)
    end
    if row.fill.endurancePerM3 then
        character:getStats():remove(CharacterStat.ENDURANCE, m3 * row.fill.endurancePerM3)
    end
    return true
end

local function fitScrubber(character, digester)
    digester.scrubber = true
    digester.scrubCO2 = 0
    digester.scrubWool = Digester.WOOL_M3
    return true
end

local function charge(character, digester, row)
    digester.scrubCO2 = Digester.SCRUB_M3[row.charge]
    return true
end

local function repackWool(character, digester)
    digester.scrubWool = Digester.WOOL_M3
    return true
end

local DO = {
    [DigesterJobs.TAKE_SLUDGE] = takeSludge,
    [DigesterJobs.VENT] = vent,
    [DigesterJobs.REPLACE_BAGS] = newHolder,
    [DigesterJobs.SEW_TARP] = newHolder,
    [DigesterJobs.UPGRADE] = upgrade,
    [DigesterJobs.FILL_PUMP] = fill,
    [DigesterJobs.FILL_COMPRESSOR] = fill,
    [DigesterJobs.FIT_SCRUBBER] = fitScrubber,
    [DigesterJobs.CHARGE_WATER] = charge,
    [DigesterJobs.CHARGE_ASH] = charge,
    [DigesterJobs.CHARGE_LIME] = charge,
    [DigesterJobs.REPACK_WOOL] = repackWool,
}

local function apply(character, job, digester, isoObject, item)
    local row = DigesterJobs.JOBS[job]
    if not DO[job](character, digester, row, isoObject, item) then
        return false
    end
    Materials.consume(character, DigesterJobs.materials(job))
    if row.xp then
        addXp(character, Perks[row.xp.perk], row.xp.amount)
    end
    return true
end

--- Does `job` for `character` at the digester `isoObject` once its timed action finished. `item` is
--- the job's bag or tank. Returns whether it was done.
function DigesterSystem.perform(character, job, isoObject, item)
    return ObjectSystem.perform(Digester, DigesterJobs, apply, character, job, isoObject, item)
end

--- Lights or puts out the gas heater `heater` for `character`, as DigesterSystem.perform does a
--- digester's job. Its digester is brought up to now first, so the time before counts at the
--- heater's old state. Returns whether it was done.
function DigesterSystem.performHeater(character, job, heater)
    local digester = GasHeater.digesterNear(heater)
    local record = digester and Digester.recordOf(digester)
    if record then
        record:advance(record:elapsedHours())
    end
    local done = not GasHeater.refusal(character, job, heater)
    if done then
        Materials.consume(character, GasHeater.materials(job))
        local lit = GasHeater.JOBS[job].lit
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

return DigesterSystem
