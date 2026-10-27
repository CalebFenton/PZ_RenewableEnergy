-- The digesters on the authority (ObjectSystem), and the jobs players do at them
-- and at their gas heaters, whose rules are DigesterJobs' and GasHeater's.

if isClient() then return end

local Digester = require "RenewableEnergy/Biogas/Digester"
local DigesterJobs = require "RenewableEnergy/Biogas/DigesterJobs"
local GasHeater = require "RenewableEnergy/Biogas/GasHeater"
local DigesterObject = require "RenewableEnergy/Biogas/DigesterObject"
local Sprites = require "RenewableEnergy/Sprites"
local Action = require "RenewableEnergy/TimedActions/RenewableEnergyAction"
local Items = require "cf_commonlib/Items"
local Tiles = require "cf_commonlib/Tiles"
local LibObjectSystem = require "cf_commonlib/ObjectSystem"

-- Its OnCreate is the build menu's (scripts/RenewableEnergy/Entities.txt).
local DigesterSystem = LibObjectSystem.define(Digester, { Object = DigesterObject, loadOnCreate = true })
RenewableEnergy = RenewableEnergy or {}
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
-- compost bag `item`, or a new one for the empty sack `item`.
local function takeSludge(character, record, row, isoObject, item)
    local uses = DigesterJobs.sludgeUses(item, record.sludge)
    if uses <= 0 then
        return false
    end
    if item:getFullType() == DigesterJobs.COMPOST_BAG then
        item:setCurrentUses(item:getCurrentUses() + uses)
        item:syncItemFields()
    else
        local bag = instanceItem(DigesterJobs.COMPOST_BAG)
        Items.takeItem(character, item)
        bag:setCurrentUses(uses)
        Items.giveItems(character, bag)
    end
    record.sludge = math.max(0, record.sludge - uses * DigesterJobs.sludgePerUse())
    return true
end

local function vent(character, record)
    record.gas = 0
    if record.indoors then
        record.leakHours = math.max(record.leakHours, 1)
    end
    return true
end

-- Takes the holder off: one with an item (Digester.HOLDERS) comes back to the character with its
-- wear as the item's condition, rounded up so a holder not yet torn doesn't come back broken.
local function takeOffHolder(character, record)
    local fullType = Digester.HOLDERS[record.holder].item
    if fullType then
        local item = instanceItem(fullType)
        item:setCondition(math.ceil(record.holderCondition / 100 * item:getConditionMax()))
        Items.giveItems(character, item)
    end
    record.holder = "none"
    record.holderCondition = 0
end

-- Puts the row's holder on in place of the one there: new garbage bags, or the Tarp Gas Bag `item`
-- at its condition; with the row's holder "none", only takes it off.
local function fitHolder(character, record, row, isoObject, item)
    takeOffHolder(character, record)
    record.holder = row.holder
    if item then
        Items.takeItem(character, item)
        record.holderCondition = 100 * item:getCondition() / item:getConditionMax()
    elseif row.holder ~= "none" then
        record.holderCondition = 100
    end
    return true
end

local function upgrade(character, record, row, isoObject)
    takeOffHolder(character, record)
    record:upgrade(isoObject)
    return true
end

-- Fills `vessel`, a tank, torch or bottle, as far as the row's fill goes.
local function fill(character, record, row, isoObject, vessel)
    local plain, scrubbed, perUse = DigesterJobs.fillUses(row.fill, record, vessel)
    if plain + scrubbed <= 0 then
        return false
    end
    vessel:setCurrentUses(vessel:getCurrentUses() + plain + scrubbed)
    vessel:syncItemFields()
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
    record.scrubSponge = 0
    return true
end

-- Refills the water with the row's charge, or the packing: out comes an Iron Sponge packed before,
-- spent, with the packings it had left as its condition, or nothing once that was its last; in
-- goes steel wool or the Iron Sponge `sponge`, whose condition the scrubber keeps.
local function refill(character, record, row, isoObject, sponge)
    if row.charge then
        record.scrubCO2 = Digester.SCRUB_M3[row.charge]
        return true
    end
    if (record.scrubSponge or 0) > 1 then
        local spent = instanceItem(Digester.SPENT_SPONGE)
        spent:setCondition(record.scrubSponge)
        Items.giveItems(character, spent)
    end
    record.scrubSponge = 0
    if sponge then
        Items.takeItem(character, sponge)
        record.scrubSponge = sponge:getCondition()
    end
    record.scrubWool = Digester.WOOL_M3
    return true
end

-- What each job does to the digester's record `record` (its tile `isoObject`) beyond taking its
-- materials, by its row of DigesterJobs.JOBS, with `item` the item it works with. Returns whether
-- it was done.
local DO = {
    [DigesterJobs.TAKE_SLUDGE] = takeSludge,
    [DigesterJobs.VENT] = vent,
    [DigesterJobs.FIT_BAGS] = fitHolder,
    [DigesterJobs.FIT_TARP] = fitHolder,
    [DigesterJobs.TAKE_OFF_BAG] = fitHolder,
    [DigesterJobs.UPGRADE] = upgrade,
    [DigesterJobs.FILL_PUMP] = fill,
    [DigesterJobs.FILL_COMPRESSOR] = fill,
    [DigesterJobs.FIT_SCRUBBER] = fitScrubber,
    [DigesterJobs.REFILL_WATER] = refill,
    [DigesterJobs.REFILL_ASH] = refill,
    [DigesterJobs.REFILL_LIME] = refill,
    [DigesterJobs.REFILL_WOOL] = refill,
    [DigesterJobs.REFILL_SPONGE] = refill,
}

--- The authority's side of the jobs at a digester (Jobs.perform), whose `with` is the job's item.
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

Action.serve({ digester = DigesterSystem.jobSite, heater = DigesterSystem.heaterSite })

return DigesterSystem
