-- The hands-on jobs at a digester: what each takes of the character and what refuses it
-- (cf_commonlib's Jobs). DigesterSystem does them.

local RenewableEnergy = require "RenewableEnergy/Utilities"
local Digester = require "RenewableEnergy/Biogas/Digester"
local Gasifier = require "RenewableEnergy/WoodGas/Gasifier"
local Items = require "cf_commonlib/Items"
local Jobs = require "cf_commonlib/Jobs"
local Tables = require "cf_commonlib/Tables"

local DigesterJobs = {}
RenewableEnergy.DigesterJobs = DigesterJobs

DigesterJobs.TAKE_SLUDGE = "TakeSludge"
DigesterJobs.VENT = "VentGas"
DigesterJobs.FIT_BAGS = "FitGarbageBags"
DigesterJobs.FIT_TARP = "FitTarpGasBag"
DigesterJobs.TAKE_OFF_BAG = "TakeOffGasBag"
DigesterJobs.UPGRADE = "Upgrade"
DigesterJobs.FILL_PUMP = "FillByPump"
DigesterJobs.FILL_COMPRESSOR = "FillByCompressor"
DigesterJobs.FIT_SCRUBBER = "FitScrubber"
DigesterJobs.REFILL_WATER = "RefillScrubberWater"
DigesterJobs.REFILL_ASH = "RefillScrubberAsh"
DigesterJobs.REFILL_LIME = "RefillScrubberLime"
DigesterJobs.REFILL_WOOL = "RefillScrubberWool"
DigesterJobs.REFILL_SPONGE = "RefillScrubberSponge"

DigesterJobs.COMPOST_BAG = "Base.CompostBag"
local STEEL_WOOL = "Base.SteelWool"
-- The water a scrubber charge takes, named in litres in the tooltip.
local SCRUB_WATER = { water = Digester.SCRUB_WATER, labelKey = "IGUI_RenewableEnergy_WaterLitres" }

--- Sludge in one use of a compost bag.
function DigesterJobs.sludgePerUse()
    local script = getScriptManager():FindItem(DigesterJobs.COMPOST_BAG)
    return Digester.SLUDGE_PER_BAG * script:getUseDelta()
end

--- The uses of compost `bag` would take from `sludge`: as many as it has room for, a new compost
--- bag's for an empty sack, or 0 when it isn't either.
function DigesterJobs.sludgeUses(bag, sludge)
    local room
    if bag:getFullType() == DigesterJobs.COMPOST_BAG then
        room = bag:getMaxUses() - bag:getCurrentUses()
    elseif bag:hasTag(ItemTag.HOLD_COMPOST) and bag:getInventory():isEmpty() then
        room = round(1 / getScriptManager():FindItem(DigesterJobs.COMPOST_BAG):getUseDelta())
    else
        return 0
    end
    return math.min(room, math.floor(sludge / DigesterJobs.sludgePerUse()))
end

-- Whether `bag` takes sludge: an empty sack, as vanilla's composter takes (every kind it tags as
-- holding compost), or a compost bag with room.
local function takesSludge(bag)
    return DigesterJobs.sludgeUses(bag, math.huge) > 0
end

--- The part-filled compost bags, then the empty sacks, the character could fill with sludge, as
--- vanilla's Get Compost lists them.
function DigesterJobs.sludgeBags(character)
    local inventory = character:getInventory()
    local bags = Tables.fromList(inventory:getAllTypeRecurse(DigesterJobs.COMPOST_BAG), takesSludge)
    return Tables.fromList(inventory:getAllEvalRecurse(takesSludge), function(sack)
        return sack:getFullType() ~= DigesterJobs.COMPOST_BAG
    end, bags)
end

--- The Tarp Gas Bags the character carries.
function DigesterJobs.tarpBags(character)
    return Tables.fromList(character:getInventory():getAllTypeRecurse(Digester.HOLDERS.tarp.item))
end

--- The Iron Sponge the character would pack a scrubber with: the one with the most packings left,
--- or nil.
function DigesterJobs.spongeToPack(character)
    local sponges, best = character:getInventory():getAllTypeRecurse(Digester.IRON_SPONGE), nil
    for i = 0, sponges:size() - 1 do
        local sponge = sponges:get(i)
        if not best or sponge:getCondition() > best:getCondition() then
            best = sponge
        end
    end
    return best
end

--- What the character could fill (Digester.FILL_SHARES): the emptiest they carry of each kind, a
--- propane tank, a blowtorch and a lantern bottle, in that order.
function DigesterJobs.toFill(character)
    local inventory, found = character:getInventory(), {}
    for _, fullType in ipairs({ Digester.TANK, Digester.TORCH, Digester.BOTTLE }) do
        local items, best = inventory:getAllTypeRecurse(fullType), nil
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if not best or item:getCurrentUsesFloat() < best:getCurrentUsesFloat() then
                best = item
            end
        end
        if best then
            table.insert(found, best)
        end
    end
    return found
end

-- The whole uses of `vessel` that make `share` of it. It holds whole uses, read back as a float
-- that may fall a hair short (InventoryItem.getCurrentUsesFloat), so fills count in uses.
local function usesAt(vessel, share)
    return round(share / vessel:getUseDelta())
end

--- The uses of `vessel`, a tank, torch or bottle, a fill (a fill job's row.fill) would add now
--- from a digester whose summary (or record) is `summary`: unscrubbed gas up to the pump's share,
--- and for a fill that takes scrubbed gas, that beyond it. Returns the unscrubbed and the scrubbed
--- uses, and the m³ in a use.
function DigesterJobs.fillUses(fill, summary, vessel)
    local perUse = Digester.M3_PER_TANK * Digester.FILL_SHARES[vessel:getFullType()] * vessel:getUseDelta()
    local filled, pumped = vessel:getCurrentUses(), usesAt(vessel, Digester.PUMP_FILL)
    local gasUses = math.floor(summary.gas / perUse)
    local plain = math.min(gasUses, math.max(0, pumped - filled))
    local scrubbed = 0
    if fill.scrubbed then
        local clean = math.floor(Digester.scrubLeft(summary) / perUse)
        scrubbed = math.max(0, math.min(gasUses - plain, vessel:getMaxUses() - math.max(filled, pumped), clean))
    end
    return plain, scrubbed, perUse
end

local function fillAmount(fill, summary, vessel)
    local plain, scrubbed, perUse = DigesterJobs.fillUses(fill, summary, vessel)
    return (plain + scrubbed) * perUse
end

-- What refuses a job for the state of the digester, from its summary.
local function noGas(character, summary)
    return summary.gas <= 0 and "Tooltip_RenewableEnergy_NoGas" or nil
end

local function noScrubber(character, summary)
    return not summary.scrubber and "Tooltip_RenewableEnergy_NoScrubber" or nil
end

-- A gas bag goes on or comes off a barrel only once its gas is out.
local function bagBlocker(character, summary)
    if not Digester.TIERS[summary.tier].gasBag then
        return "Tooltip_RenewableEnergy_NoGasBags"
    end
    return summary.gas > 0 and "Tooltip_RenewableEnergy_VentFirst" or nil
end

-- Completes the row of a job that fills `with`, a tank, torch or bottle, from the holder.
-- `fields.fill`: limit, the share of it a fill stops at, and `full`, the key that says it got
-- there; scrubbed, it takes scrubbed gas beyond the pump's share; power, it needs the square
-- powered; minutesPerM3, its minutes per m³ moved, at least `fields.baseMinutes` in all;
-- endurancePerM3, what each m³ costs the character.
local function fillJob(fields)
    local fill = fields.fill
    fields.blocker = noGas
    fields.minutes = function(digester, vessel)
        local summary = Digester.currentSummary(digester)
        if not (summary and vessel) then
            return fields.baseMinutes
        end
        return math.max(fields.baseMinutes, fillAmount(fill, summary, vessel) * fill.minutesPerM3)
    end
    fields.withRefusal = function(character, summary, vessel)
        if not Jobs.carries(character, vessel, function(item) return Digester.FILL_SHARES[item:getFullType()] ~= nil end) then
            return "Tooltip_RenewableEnergy_NeedsVessel"
        end
        if fill.power and not Digester.compressorPowered(character) then
            return "Tooltip_RenewableEnergy_NoPower"
        end
        if fillAmount(fill, summary, vessel) <= 0 then
            if vessel:getCurrentUses() >= usesAt(vessel, fill.limit) then
                return fill.full
            end
            return "Tooltip_RenewableEnergy_NeedsScrubbed"
        end
        return nil
    end
    return fields
end

-- Every job, by name (Jobs.define), read against the digester's summary
-- (Digester.currentSummary), with `with` the item it works with, which its materials leave out.
-- holder, charge and fill say what it does on the authority. Vanilla has no pump stroke; a tire
-- pump is worked kneeling at a wheel. The rest are reached into at waist height.
DigesterJobs.JOBS = {
    [DigesterJobs.TAKE_SLUDGE] = {
        minutes = 10, position = "Mid", metabolics = Metabolics.HeavyWork, tooltip = "Tooltip_RenewableEnergy_TakeSludge",
        blocker = function(character, summary)
            return summary.sludge < DigesterJobs.sludgePerUse() and "Tooltip_RenewableEnergy_NoSludge" or nil
        end,
        withRefusal = function(character, summary, bag)
            return not Jobs.carries(character, bag, takesSludge) and "Tooltip_RenewableEnergy_NeedsSack" or nil
        end,
    },
    [DigesterJobs.VENT] = { minutes = 1, position = "Mid", tooltip = "Tooltip_RenewableEnergy_VentGas", blocker = noGas },
    [DigesterJobs.FIT_BAGS] = {
        minutes = 15, position = "Mid", holder = "bags", tooltip = "Tooltip_RenewableEnergy_FitGarbageBags",
        blocker = bagBlocker,
        materials = {
            { item = "Base.Garbagebag", need = 3 },
        },
    },
    [DigesterJobs.FIT_TARP] = {
        minutes = 15, position = "Mid", holder = "tarp", tooltip = "Tooltip_RenewableEnergy_FitTarpGasBag",
        blocker = bagBlocker,
        withRefusal = function(character, summary, bag)
            return not Jobs.carries(character, bag, Items.ofType(Digester.HOLDERS.tarp.item))
                and "Tooltip_RenewableEnergy_NeedsTarpGasBag" or nil
        end,
    },
    [DigesterJobs.TAKE_OFF_BAG] = {
        minutes = 10, position = "Mid", holder = "none", tooltip = "Tooltip_RenewableEnergy_TakeOffGasBag",
        blocker = function(character, summary)
            if summary.holder == "none" then
                return "Tooltip_RenewableEnergy_NoGasBag"
            end
            return bagBlocker(character, summary)
        end,
    },
    [DigesterJobs.UPGRADE] = {
        minutes = 120, anim = CharacterActionAnims.Build, sound = "Hammering", metabolics = Metabolics.HeavyWork,
        hideBlocked = true, tooltip = "Tooltip_RenewableEnergy_Upgrade",
        blocker = function(character, summary)
            return not Digester.TIERS[summary.tier].upgrade and "Tooltip_RenewableEnergy_NotBarrel" or nil
        end,
        materials = {
            { perk = "Woodwork", need = 4 },
            { perk = "Mechanics", need = 2 },
            { tool = "HAMMER", item = "Base.Hammer" },
            { tool = "SAW", item = "Base.Saw" },
            { item = "Base.MetalDrum", need = 1 },
            { item = "Base.Plank", need = 6 },
            { item = "Base.Nails", need = 12 },
            { item = "Base.Tarp", need = 1 },
            { item = Gasifier.HAY[1], types = Gasifier.HAY, need = 10 },
        },
        xp = { perk = "Woodwork", amount = 30 },
    },
    [DigesterJobs.FILL_PUMP] = fillJob({
        baseMinutes = 5, anim = "VehicleWorkOnTire", metabolics = Metabolics.HeavyWork, tooltip = "Tooltip_RenewableEnergy_FillByPump",
        materials = { { item = Digester.PUMP, keep = true } },
        fill = {
            limit = Digester.PUMP_FILL, full = "Tooltip_RenewableEnergy_PumpLimit",
            minutesPerM3 = Digester.PUMP_MINUTES_PER_M3, endurancePerM3 = Digester.PUMP_ENDURANCE_PER_M3,
        },
    }),
    [DigesterJobs.FILL_COMPRESSOR] = fillJob({
        baseMinutes = 2, position = "Mid", tooltip = "Tooltip_RenewableEnergy_FillByCompressor",
        materials = { { item = Digester.COMPRESSOR, keep = true } },
        fill = {
            limit = 1, full = "Tooltip_RenewableEnergy_Full", scrubbed = true, power = true,
            minutesPerM3 = Digester.COMPRESSOR_MINUTES_PER_M3,
        },
    }),
    [DigesterJobs.FIT_SCRUBBER] = {
        minutes = 30, position = "Mid", tooltip = "Tooltip_RenewableEnergy_FitScrubber",
        blocker = function(character, summary)
            return summary.scrubber and "Tooltip_RenewableEnergy_HasScrubber" or nil
        end,
        materials = {
            { perk = "Mechanics", need = 1 },
            { tag = "BUCKET", item = "Base.Bucket" },
            { item = "Base.Pipe", need = 1 },
            { item = "Base.RubberHose", need = 1 },
            { item = STEEL_WOOL, uses = 1 },
        },
        xp = { perk = "Mechanics", amount = 10 },
    },
    -- `charge`: the alkali that goes in with the water (Digester.SCRUB_M3); a row without one
    -- refills the packing, with steel wool or the Iron Sponge `with`. The water and the packing wear
    -- out apart, so each is refilled on its own.
    [DigesterJobs.REFILL_WATER] = {
        minutes = 5, position = "Mid", charge = "water", blocker = noScrubber,
        tooltip = "Tooltip_RenewableEnergy_RefillScrubberWater",
        materials = { SCRUB_WATER },
    },
    [DigesterJobs.REFILL_ASH] = {
        minutes = 5, position = "Mid", charge = "ash", blocker = noScrubber,
        tooltip = "Tooltip_RenewableEnergy_RefillScrubberAsh",
        materials = { SCRUB_WATER, { item = Gasifier.WOOD_ASH, need = 1 } },
    },
    [DigesterJobs.REFILL_LIME] = {
        minutes = 5, position = "Mid", charge = "lime", blocker = noScrubber,
        tooltip = "Tooltip_RenewableEnergy_RefillScrubberLime",
        materials = { SCRUB_WATER, { item = "Base.Quicklime", need = 1 } },
    },
    [DigesterJobs.REFILL_WOOL] = {
        minutes = 5, position = "Mid", blocker = noScrubber,
        tooltip = "Tooltip_RenewableEnergy_RefillScrubberWool",
        materials = { { item = STEEL_WOOL, uses = 1 } },
    },
    [DigesterJobs.REFILL_SPONGE] = {
        minutes = 5, position = "Mid", blocker = noScrubber,
        tooltip = "Tooltip_RenewableEnergy_RefillScrubberSponge",
        withRefusal = function(character, summary, sponge)
            return not Jobs.carries(character, sponge, Items.ofType(Digester.IRON_SPONGE))
                and "Tooltip_RenewableEnergy_NeedsIronSponge" or nil
        end,
    },
}

Jobs.define(DigesterJobs, {
    subjectOf = Digester.currentSummary, missing = "Tooltip_RenewableEnergy_NoDigester",
})

return DigesterJobs
