-- The digesters on the authority (RenewableEnergy.ObjectSystem), and the jobs players do at them
-- and at their gas heaters, whose rules are DigesterJobs' and GasHeater's.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/ObjectSystem"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/DigesterJobs"
require "RenewableEnergy/Biogas/GasHeater"
require "RenewableEnergy/Biogas/DigesterObject"
local Items = require "cf_commonlib/Items"
local Tiles = require "cf_commonlib/Tiles"
local LibObjectSystem = require "cf_commonlib/ObjectSystem"

RenewableEnergy = RenewableEnergy or {}
local Digester, DigesterJobs, GasHeater = RenewableEnergy.Digester, RenewableEnergy.DigesterJobs, RenewableEnergy.GasHeater
local ObjectSystem, Sprites, DigesterObject = RenewableEnergy.ObjectSystem, RenewableEnergy.Sprites, RenewableEnergy.DigesterObject

local DigesterSystem = ObjectSystem.define({
    name = "Digester", kind = "digester", owner = Digester, Object = DigesterObject, isObject = Digester.isDigester,
})
RenewableEnergy.DigesterSystem = DigesterSystem

-- A barrel digester is the entity of the barrel it was built from, which the build menu builds on
-- the Metal Drum's. Swapped before the record reads the tile, and before ISBuildIsoEntity:create
-- sends the object, so clients get it whole.
local onCreate = DigesterSystem.OnCreate
function DigesterSystem.OnCreate(params)
    local thumpable = params.thumpable
    local barrel = thumpable and Items.firstConsumed(params.craftRecipeData, function(item)
        return Sprites.digester.barrel[item:getType()] ~= nil
    end)
    if barrel then
        Tiles.setEntityTile(thumpable, Sprites.digester.barrel[barrel:getType()])
    end
    onCreate(params)
end

-- Take Sludge, as vanilla's ISGetCompost fills compost bags from a composter: into the part-filled
-- compost bag `item`, or a new one for the empty sandbag `item`.
local function takeSludge(character, record, row, isoObject, item)
    local perUse = DigesterJobs.sludgePerUse()
    local uses = math.floor(record.sludge / perUse)
    if item:getFullType() == DigesterJobs.COMPOST_BAG then
        uses = math.min(uses, item:getMaxUses() - item:getCurrentUses())
        if uses <= 0 then
            return false
        end
        item:setCurrentUses(item:getCurrentUses() + uses)
        item:syncItemFields()
    else
        local bag = instanceItem(DigesterJobs.COMPOST_BAG)
        uses = math.min(uses, bag:getMaxUses())
        if uses <= 0 then
            return false
        end
        Items.takeItem(character, item)
        bag:setCurrentUses(uses)
        Items.giveItems(character, bag)
    end
    record.sludge = math.max(0, record.sludge - uses * perUse)
    return true
end

local function vent(character, record)
    record.gas = 0
    if record.indoors then
        record.leakHours = math.max(record.leakHours, 1)
    end
    return true
end

-- A new holder of the row's kind, empty.
local function newHolder(character, record, row)
    record.holder = row.holder
    record.holderCondition = 100
    record.gas = 0
    return true
end

local function upgrade(character, record, row, isoObject)
    record:upgrade(isoObject)
    return true
end

-- Fills `tank` as far as the row's fill goes.
local function fill(character, record, row, isoObject, tank)
    local plain, scrubbed, perUse = DigesterJobs.fillUses(row.fill, record, tank)
    if plain + scrubbed <= 0 then
        return false
    end
    tank:setCurrentUses(tank:getCurrentUses() + plain + scrubbed)
    tank:syncItemFields()
    local m3 = (plain + scrubbed) * perUse
    record:takeGas(m3)
    if scrubbed > 0 then
        record.scrubCO2 = math.max(0, record.scrubCO2 - scrubbed * perUse)
        record.scrubWool = math.max(0, record.scrubWool - scrubbed * perUse)
    end
    if row.fill.endurancePerM3 then
        character:getStats():remove(CharacterStat.ENDURANCE, m3 * row.fill.endurancePerM3)
    end
    return true
end

local function fitScrubber(character, record)
    record.scrubber = true
    record.scrubCO2 = 0
    record.scrubWool = Digester.WOOL_M3
    return true
end

local function charge(character, record, row)
    record.scrubCO2 = Digester.SCRUB_M3[row.charge]
    return true
end

local function repackWool(character, record)
    record.scrubWool = Digester.WOOL_M3
    return true
end

-- What each job does to the digester's record `record` (its tile `isoObject`) beyond taking its
-- materials, by its row of DigesterJobs.JOBS. `item` is the job's bag or tank. Returns whether it
-- was done.
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

--- The authority's side of the jobs at a digester (Jobs.perform), whose `with` is the job's bag
--- or tank.
DigesterSystem.jobSite = LibObjectSystem.jobSite(Digester, DO)

--- The authority's side of the jobs at a gas heater (Jobs.perform), which light it or put it
--- out. They work on the record of the digester it warms, if any, brought up to now first, so the
--- time before counts at the heater's old state.
DigesterSystem.heaterSite = {
    open = function(heater)
        local digester = GasHeater.digesterNear(heater)
        return digester and DigesterSystem.jobSite.open(digester) or nil
    end,
    act = function(character, job, record, row, heater)
        if record then
            record:setHeaterLit(heater, row.lit)
        else
            DigesterObject.showHeaterLit(heater, row.lit)
        end
        return true
    end,
    tell = DigesterSystem.jobSite.tell,
}

return DigesterSystem
