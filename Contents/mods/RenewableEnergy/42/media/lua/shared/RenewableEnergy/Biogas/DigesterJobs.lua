-- The hands-on jobs at a digester: what each takes of the character and what refuses it. The menu
-- shows the same needs the authority checks, so they can't disagree; DigesterSystem does them.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Materials"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/WoodGas/Gasifier"

RenewableEnergy = RenewableEnergy or {}
local DigesterJobs = {}
RenewableEnergy.DigesterJobs = DigesterJobs

local Digester, Gasifier, Materials = RenewableEnergy.Digester, RenewableEnergy.Gasifier, RenewableEnergy.Materials

DigesterJobs.TAKE_SLUDGE = "TakeSludge"
DigesterJobs.VENT = "VentGas"
DigesterJobs.REPLACE_BAGS = "ReplaceBags"
DigesterJobs.SEW_TARP = "SewTarp"
DigesterJobs.UPGRADE = "Upgrade"
DigesterJobs.FILL_PUMP = "FillByPump"
DigesterJobs.FILL_COMPRESSOR = "FillByCompressor"
DigesterJobs.FIT_SCRUBBER = "FitScrubber"
DigesterJobs.CHARGE_WATER = "ChargeScrubberWater"
DigesterJobs.CHARGE_ASH = "ChargeScrubberAsh"
DigesterJobs.CHARGE_LIME = "ChargeScrubberLime"
DigesterJobs.REPACK_WOOL = "RepackWool"

DigesterJobs.SANDBAG = "Base.EmptySandbag"
DigesterJobs.COMPOST_BAG = "Base.CompostBag"
local STEEL_WOOL = "Base.SteelWool"

--- Sludge in one use of a compost bag.
function DigesterJobs.sludgePerUse()
    local script = getScriptManager():FindItem(DigesterJobs.COMPOST_BAG)
    return Digester.SLUDGE_PER_BAG * script:getUseDelta()
end

-- Whether `bag` takes sludge: an empty sandbag, or a compost bag with room.
local function takesSludge(bag)
    local fullType = bag:getFullType()
    return fullType == DigesterJobs.SANDBAG
        or (fullType == DigesterJobs.COMPOST_BAG and bag:getCurrentUses() < bag:getMaxUses())
end

--- The empty sandbag or part-filled compost bag the character would fill with sludge, or nil.
function DigesterJobs.sludgeBag(character)
    local inventory = character:getInventory()
    local bags = inventory:getAllTypeRecurse(DigesterJobs.COMPOST_BAG)
    for i = 0, bags:size() - 1 do
        if takesSludge(bags:get(i)) then
            return bags:get(i)
        end
    end
    return inventory:getFirstTypeRecurse(DigesterJobs.SANDBAG)
end

--- The propane tank the character would fill: the emptiest they carry, or nil.
function DigesterJobs.tankToFill(character)
    local tanks = character:getInventory():getAllTypeRecurse(Digester.TANK)
    local best
    for i = 0, tanks:size() - 1 do
        local tank = tanks:get(i)
        if not best or tank:getCurrentUses() < best:getCurrentUses() then
            best = tank
        end
    end
    return best
end

-- The whole uses of `tank` that make `share` of it. A tank holds whole uses, read back as a float
-- that may fall a hair short (InventoryItem.getCurrentUsesFloat), so fills count in uses.
local function usesAt(tank, share)
    return round(share / tank:getUseDelta())
end

--- The uses of `tank` a fill (a fill job's row.fill) would add now from a digester whose summary
--- (or record) is `summary`: unscrubbed gas up to the pump's share, and for a fill that takes
--- scrubbed gas, that beyond it. Returns the unscrubbed and the scrubbed uses, and the m³ in a use.
function DigesterJobs.fillUses(fill, summary, tank)
    local perUse = Digester.M3_PER_TANK * tank:getUseDelta()
    local filled, pumped = tank:getCurrentUses(), usesAt(tank, Digester.PUMP_FILL)
    local gasUses = math.floor(summary.gas / perUse)
    local plain = math.min(gasUses, math.max(0, pumped - filled))
    local scrubbed = 0
    if fill.scrubbed then
        local clean = math.floor(math.min(summary.scrubCO2 or 0, summary.scrubWool or 0) / perUse)
        scrubbed = math.max(0, math.min(gasUses - plain, tank:getMaxUses() - math.max(filled, pumped), clean))
    end
    return plain, scrubbed, perUse
end

local function fillAmount(fill, summary, tank)
    local plain, scrubbed, perUse = DigesterJobs.fillUses(fill, summary, tank)
    return (plain + scrubbed) * perUse
end

-- What refuses a job for the state of the digester, from its summary.
local function noGas(summary)
    return summary.gas <= 0 and "Tooltip_RenewableEnergy_NoGas" or nil
end

local function noScrubber(summary)
    return not summary.scrubber and "Tooltip_RenewableEnergy_NoScrubber" or nil
end

-- The row of a job that fills a propane tank, the job's item, from the holder: `fields` and what
-- every fill has. `fields.fill`: limit, the share of a full tank it stops at, and `full`, the key
-- that says so; scrubbed, whether it takes scrubbed gas beyond the pump's share; power, whether it
-- needs the square powered; minutesPerM3, its minutes per m³ moved, when that is more than
-- `baseMinutes`; endurancePerM3, what it costs the character.
local function fillJob(fields)
    local fill = fields.fill
    fields.blocker = noGas
    fields.minutes = function(digester, tank)
        local summary = Digester.currentSummary(digester)
        if not (summary and tank) then
            return fields.baseMinutes
        end
        return math.max(fields.baseMinutes, fillAmount(fill, summary, tank) * fill.minutesPerM3)
    end
    fields.check = function(character, summary, tank)
        if not (tank and tank:getFullType() == Digester.TANK and character:getInventory():containsRecursive(tank)) then
            return "Tooltip_RenewableEnergy_NeedsTank"
        end
        if fill.power then
            local square = character:getCurrentSquare()
            if not (square and square:haveElectricity()) then
                return "Tooltip_RenewableEnergy_NoPower"
            end
        end
        if fillAmount(fill, summary, tank) <= 0 then
            if tank:getCurrentUses() >= usesAt(tank, fill.limit) then
                return fill.full
            end
            return "Tooltip_RenewableEnergy_NeedsScrubbed"
        end
        return nil
    end
    return fields
end

-- Every job, by name:
-- - minutes: the in-game minutes it takes, or a function(digester, item) of them.
-- - blocker(summary): the state of the digester that refuses it, as a translation key, or nil.
--   hideBlocked: the menu leaves it out, rather than greyed, while its blocker refuses it, as it
--   belongs to another state of the digester.
-- - check(character, summary, item), if any: what refuses the item the character brings, the bag
--   or tank it fills.
-- - materials: what it takes of the character beyond that (RenewableEnergy.Materials).
-- - xp: what it gives on the authority. holder, charge, fill: what it does there.
-- - How it looks (RenewableEnergyGasAction): anim and LootPosition `position`, else "Loot"; heavy,
--   heavy work; sound while it runs. Vanilla has no pump stroke; a tire pump is worked kneeling at
--   a wheel. The rest are reached into at waist height.
DigesterJobs.JOBS = {
    [DigesterJobs.TAKE_SLUDGE] = {
        minutes = 10, position = "Mid", heavy = true,
        blocker = function(summary)
            return summary.sludge < DigesterJobs.sludgePerUse() and "Tooltip_RenewableEnergy_NoSludge" or nil
        end,
        check = function(character, summary, bag)
            if not (bag and character:getInventory():containsRecursive(bag) and takesSludge(bag)) then
                return "Tooltip_RenewableEnergy_NeedsSandbag"
            end
            return nil
        end,
    },
    [DigesterJobs.VENT] = { minutes = 1, position = "Mid", blocker = noGas },
    [DigesterJobs.REPLACE_BAGS] = {
        minutes = 15, position = "Mid", holder = "bags", hideBlocked = true,
        blocker = function(summary)
            return summary.holder ~= "bags" and "Tooltip_RenewableEnergy_NotBags" or nil
        end,
        materials = {
            { item = "Base.Garbagebag", need = 3 },
        },
    },
    [DigesterJobs.SEW_TARP] = {
        minutes = 60, anim = "SewingCloth", holder = "tarp", hideBlocked = true,
        -- Over bags, or a torn tarp.
        blocker = function(summary)
            if not Digester.HOLDERS[summary.holder].wearPerDay then
                return "Tooltip_RenewableEnergy_NotBags"
            end
            return summary.holder == "tarp" and not summary.torn and "Tooltip_RenewableEnergy_HasTarp" or nil
        end,
        materials = {
            { perk = "Tailoring", need = 2 },
            { tool = "SEWING_NEEDLE", item = "Base.Needle" },
            { item = "Base.Thread", need = 1, uses = true },
            { item = "Base.Tarp", need = 1 },
            { item = "Base.DuctTape", need = 2, uses = true },
        },
        xp = { perk = "Tailoring", amount = 10 },
    },
    [DigesterJobs.UPGRADE] = {
        minutes = 120, anim = CharacterActionAnims.Build, sound = "Hammering", heavy = true, hideBlocked = true,
        blocker = function(summary)
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
        baseMinutes = 5, anim = "VehicleWorkOnTire", heavy = true,
        materials = { { item = Digester.PUMP, keep = true } },
        fill = {
            limit = Digester.PUMP_FILL, full = "Tooltip_RenewableEnergy_PumpLimit",
            minutesPerM3 = Digester.PUMP_MINUTES_PER_M3, endurancePerM3 = Digester.PUMP_ENDURANCE_PER_M3,
        },
    }),
    [DigesterJobs.FILL_COMPRESSOR] = fillJob({
        baseMinutes = 2, position = "Mid",
        materials = { { item = Digester.COMPRESSOR, keep = true } },
        fill = {
            limit = 1, full = "Tooltip_RenewableEnergy_TankFull", scrubbed = true, power = true,
            minutesPerM3 = Digester.COMPRESSOR_MINUTES_PER_M3,
        },
    }),
    [DigesterJobs.FIT_SCRUBBER] = {
        minutes = 30, position = "Mid", hideBlocked = true,
        blocker = function(summary)
            return summary.scrubber and "Tooltip_RenewableEnergy_HasScrubber" or nil
        end,
        materials = {
            { perk = "Mechanics", need = 1 },
            { tag = "BUCKET", item = "Base.Bucket" },
            { item = "Base.Pipe", need = 1 },
            { item = "Base.RubberHose", need = 1 },
            { item = STEEL_WOOL, need = 1, uses = true },
        },
        xp = { perk = "Mechanics", amount = 10 },
    },
    -- `charge`: the alkali that goes in with the water (Digester.SCRUB_M3).
    [DigesterJobs.CHARGE_WATER] = {
        minutes = 5, position = "Mid", charge = "water", blocker = noScrubber,
        materials = { { water = Digester.SCRUB_WATER } },
    },
    [DigesterJobs.CHARGE_ASH] = {
        minutes = 5, position = "Mid", charge = "ash", blocker = noScrubber,
        materials = { { water = Digester.SCRUB_WATER }, { item = Gasifier.WOOD_ASH, need = 1 } },
    },
    [DigesterJobs.CHARGE_LIME] = {
        minutes = 5, position = "Mid", charge = "lime", blocker = noScrubber,
        materials = { { water = Digester.SCRUB_WATER }, { item = "Base.Quicklime", need = 1 } },
    },
    [DigesterJobs.REPACK_WOOL] = {
        minutes = 5, position = "Mid", blocker = noScrubber, hideBlocked = true,
        materials = { { item = STEEL_WOOL, need = 1, uses = true } },
    },
}

--- What `job` takes (RenewableEnergy.Materials).
function DigesterJobs.materials(job)
    return DigesterJobs.JOBS[job].materials or {}
end

--- What `job` takes of `character`, as needs (RenewableEnergy.firstUnmet, RenewableEnergy.Needs).
function DigesterJobs.needs(character, job)
    return Materials.needs(character, DigesterJobs.materials(job))
end

--- The state of the digester that refuses `job`, as a translation key, or nil. `summary` is the
--- digester's (Digester.currentSummary).
function DigesterJobs.blocker(job, summary)
    return DigesterJobs.JOBS[job].blocker(summary)
end

--- What refuses the bag or tank `item` that `character` brings to `job` at a digester whose summary
--- is `summary`, as a translation key, or nil.
function DigesterJobs.check(character, job, summary, item)
    local check = DigesterJobs.JOBS[job].check
    return check and check(character, summary, item) or nil
end

--- What refuses `character` doing `job` at `digester` as this side knows it now: a translation
--- key, "short" when they lack a need, or nil. `item` is the bag a Take Sludge fills or the tank a
--- fill fills.
function DigesterJobs.refusal(character, job, digester, item)
    local summary = Digester.currentSummary(digester)
    if not (summary and DigesterJobs.JOBS[job]) then
        return "Tooltip_RenewableEnergy_NoDigester"
    end
    return DigesterJobs.blocker(job, summary)
        or DigesterJobs.check(character, job, summary, item)
        or (RenewableEnergy.firstUnmet(DigesterJobs.needs(character, job)) and "short")
        or nil
end

return DigesterJobs
