-- The hands-on jobs at a digester: what each takes of the character and what refuses it. The menu
-- shows the same needs the authority checks, so they can't disagree (RenewableEnergy.firstUnmet);
-- the authority does them (server/RenewableEnergy/Biogas/DigesterSystem.lua).

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

-- In-game minutes each job takes; filling a tank takes Digester's minutes per m³ moved instead.
DigesterJobs.MINUTES = {
    [DigesterJobs.TAKE_SLUDGE] = 10,
    [DigesterJobs.VENT] = 1,
    [DigesterJobs.REPLACE_BAGS] = 15,
    [DigesterJobs.SEW_TARP] = 60,
    [DigesterJobs.UPGRADE] = 120,
    [DigesterJobs.FILL_PUMP] = 5,
    [DigesterJobs.FILL_COMPRESSOR] = 2,
    [DigesterJobs.FIT_SCRUBBER] = 30,
    [DigesterJobs.CHARGE_WATER] = 5,
    [DigesterJobs.CHARGE_ASH] = 5,
    [DigesterJobs.CHARGE_LIME] = 5,
    [DigesterJobs.REPACK_WOOL] = 5,
}

-- What each job's scrubber charge is: the alkali that goes in with the water.
DigesterJobs.CHARGES = { [DigesterJobs.CHARGE_WATER] = "water", [DigesterJobs.CHARGE_ASH] = "ash", [DigesterJobs.CHARGE_LIME] = "lime" }

-- What each job takes beyond the state of the digester (RenewableEnergy.Materials).
DigesterJobs.MATERIALS = {
    [DigesterJobs.REPLACE_BAGS] = {
        { item = "Base.Garbagebag", need = 3 },
    },
    [DigesterJobs.SEW_TARP] = {
        { perk = "Tailoring", need = 2 },
        { tool = "SEWING_NEEDLE", item = "Base.Needle" },
        { item = "Base.Thread", need = 1, uses = true },
        { item = "Base.Tarp", need = 1 },
        { item = "Base.DuctTape", need = 2, uses = true },
    },
    [DigesterJobs.UPGRADE] = {
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
    [DigesterJobs.FILL_PUMP] = {
        { item = Digester.PUMP, keep = true },
    },
    [DigesterJobs.FILL_COMPRESSOR] = {
        { item = Digester.COMPRESSOR, keep = true },
    },
    [DigesterJobs.FIT_SCRUBBER] = {
        { perk = "Mechanics", need = 1 },
        { tag = "BUCKET", item = "Base.Bucket" },
        { item = "Base.Pipe", need = 1 },
        { item = "Base.RubberHose", need = 1 },
        { item = STEEL_WOOL, need = 1, uses = true },
    },
    [DigesterJobs.CHARGE_WATER] = {
        { water = Digester.SCRUB_WATER },
    },
    [DigesterJobs.CHARGE_ASH] = {
        { water = Digester.SCRUB_WATER },
        { item = Gasifier.WOOD_ASH, need = 1 },
    },
    [DigesterJobs.CHARGE_LIME] = {
        { water = Digester.SCRUB_WATER },
        { item = "Base.Quicklime", need = 1 },
    },
    [DigesterJobs.REPACK_WOOL] = {
        { item = STEEL_WOOL, need = 1, uses = true },
    },
}

-- XP each job gives on the authority.
DigesterJobs.XP = {
    [DigesterJobs.SEW_TARP] = { perk = "Tailoring", amount = 10 },
    [DigesterJobs.UPGRADE] = { perk = "Woodwork", amount = 30 },
    [DigesterJobs.FIT_SCRUBBER] = { perk = "Mechanics", amount = 10 },
}

-- How each job looks (RenewableEnergyGasAction). Vanilla has no pump stroke; a tire pump is worked
-- kneeling at a wheel. The rest are reached into at waist height.
local LOOT_MID = { anim = "Loot", position = "Mid" }
DigesterJobs.LOOK = {
    [DigesterJobs.TAKE_SLUDGE] = { anim = "Loot", position = "Mid", heavy = true },
    [DigesterJobs.UPGRADE] = { anim = CharacterActionAnims.Build, sound = "Hammering", heavy = true },
    [DigesterJobs.SEW_TARP] = { anim = "SewingCloth" },
    [DigesterJobs.FILL_PUMP] = { anim = "VehicleWorkOnTire", heavy = true },
}
for job in pairs(DigesterJobs.MINUTES) do
    DigesterJobs.LOOK[job] = DigesterJobs.LOOK[job] or LOOT_MID
end

DigesterJobs.isTarget = Digester.isDigester

--- What `job` takes of `character`, as needs (RenewableEnergy.firstUnmet, RenewableEnergy.Needs).
function DigesterJobs.needs(character, job)
    return Materials.needs(character, DigesterJobs.MATERIALS[job])
end

--- The empty sandbag or part-filled compost bag the character would fill with sludge, or nil.
function DigesterJobs.sludgeBag(character)
    local inventory = character:getInventory()
    local bags = inventory:getAllTypeRecurse(DigesterJobs.COMPOST_BAG)
    for i = 0, bags:size() - 1 do
        local bag = bags:get(i)
        if bag:getCurrentUsesFloat() < 1 then
            return bag
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
        if not best or tank:getCurrentUsesFloat() < best:getCurrentUsesFloat() then
            best = tank
        end
    end
    return best
end

--- Sludge in one use of a compost bag.
function DigesterJobs.sludgePerUse()
    local script = getScriptManager():FindItem(DigesterJobs.COMPOST_BAG)
    return Digester.SLUDGE_PER_BAG * script:getUseDelta()
end

--- How far `job` fills a tank: the share of a full tank it stops at.
function DigesterJobs.fillLimit(job)
    return job == DigesterJobs.FILL_PUMP and Digester.PUMP_FILL or 1
end

-- The whole uses of `tank` that make `share` of it. A tank holds whole uses, read back as a float
-- that may fall a hair short (InventoryItem.getCurrentUsesFloat), so fills count in uses.
local function usesAt(tank, share)
    return RenewableEnergy.round(share / tank:getUseDelta())
end

--- The uses of `tank` a fill by `job` would add now from a digester whose summary (or record) is
--- `summary`: unscrubbed gas up to the pump's share, and for the compressor scrubbed gas beyond it.
--- Returns the unscrubbed and the scrubbed uses, and the m³ in a use.
function DigesterJobs.fillUses(job, summary, tank)
    local perUse = Digester.M3_PER_TANK * tank:getUseDelta()
    local filled, pumped = tank:getCurrentUses(), usesAt(tank, Digester.PUMP_FILL)
    local gasUses = math.floor(summary.gas / perUse)
    local plain = math.min(gasUses, math.max(0, pumped - filled))
    local scrubbed = 0
    if job == DigesterJobs.FILL_COMPRESSOR then
        local clean = math.floor(math.min(summary.scrubCO2 or 0, summary.scrubWool or 0) / perUse)
        scrubbed = math.max(0, math.min(gasUses - plain, usesAt(tank, 1) - math.max(filled, pumped), clean))
    end
    return plain, scrubbed, perUse
end

--- The gas, in m³, a fill of `tank` by `job` would move now (DigesterJobs.fillUses).
function DigesterJobs.fillAmount(job, summary, tank)
    local plain, scrubbed, perUse = DigesterJobs.fillUses(job, summary, tank)
    return (plain + scrubbed) * perUse
end

--- In-game minutes `job` takes at `digester`; `item` is the job's tank or bag.
function DigesterJobs.minutesFor(job, digester, item)
    local minutes = DigesterJobs.MINUTES[job]
    local summary = Digester.currentSummary(digester)
    if summary and item and (job == DigesterJobs.FILL_PUMP or job == DigesterJobs.FILL_COMPRESSOR) then
        local perM3 = job == DigesterJobs.FILL_PUMP and Digester.PUMP_MINUTES_PER_M3 or Digester.COMPRESSOR_MINUTES_PER_M3
        minutes = math.max(minutes, DigesterJobs.fillAmount(job, summary, item) * perM3)
    end
    return minutes
end

--- The state of the digester that refuses `job`, as a translation key, or nil. `summary` is the
--- digester's (Digester.summaryOf).
function DigesterJobs.blocker(job, summary)
    if job == DigesterJobs.TAKE_SLUDGE then
        return summary.sludge < DigesterJobs.sludgePerUse() and "Tooltip_RenewableEnergy_NoSludge" or nil
    elseif job == DigesterJobs.VENT or job == DigesterJobs.FILL_PUMP or job == DigesterJobs.FILL_COMPRESSOR then
        return summary.gas <= 0 and "Tooltip_RenewableEnergy_NoGas" or nil
    elseif job == DigesterJobs.REPLACE_BAGS then
        return summary.holder ~= "bags" and "Tooltip_RenewableEnergy_NotBags" or nil
    elseif job == DigesterJobs.SEW_TARP then
        if summary.holder == "tarp" and not summary.torn then
            return "Tooltip_RenewableEnergy_HasTarp"
        end
        return (summary.holder ~= "bags" and summary.holder ~= "tarp") and "Tooltip_RenewableEnergy_NotBags" or nil
    elseif job == DigesterJobs.UPGRADE then
        return summary.tier ~= "barrel" and "Tooltip_RenewableEnergy_NotBarrel" or nil
    elseif job == DigesterJobs.FIT_SCRUBBER then
        return summary.scrubber and "Tooltip_RenewableEnergy_HasScrubber" or nil
    elseif DigesterJobs.CHARGES[job] or job == DigesterJobs.REPACK_WOOL then
        return not summary.scrubber and "Tooltip_RenewableEnergy_NoScrubber" or nil
    end
    return nil
end

--- What keeps `character` from filling `tank` by `job` at a digester whose summary is `summary`,
--- as a translation key, or nil.
function DigesterJobs.fillRefusal(character, job, summary, tank)
    if not (tank and tank:getFullType() == Digester.TANK and character:getInventory():containsRecursive(tank)) then
        return "Tooltip_RenewableEnergy_NeedsTank"
    end
    if job == DigesterJobs.FILL_COMPRESSOR then
        local square = character:getCurrentSquare()
        if not (square and square:haveElectricity()) then
            return "Tooltip_RenewableEnergy_NoPower"
        end
    end
    if DigesterJobs.fillAmount(job, summary, tank) <= 0 then
        if tank:getCurrentUses() >= usesAt(tank, DigesterJobs.fillLimit(job)) then
            return job == DigesterJobs.FILL_PUMP and "Tooltip_RenewableEnergy_PumpLimit" or "Tooltip_RenewableEnergy_TankFull"
        end
        return "Tooltip_RenewableEnergy_NeedsScrubbed"
    end
    return nil
end

--- What refuses `character` doing `job` at the digester whose summary is `summary`: a blocker key,
--- "short" when they lack a need, or nil. `item` is the bag a Take Sludge fills or the tank a fill
--- fills.
function DigesterJobs.refusalFor(character, job, summary, item)
    if not summary or not DigesterJobs.MINUTES[job] then
        return "Tooltip_RenewableEnergy_NoDigester"
    end
    local blocker = DigesterJobs.blocker(job, summary)
    if blocker then
        return blocker
    end
    if job == DigesterJobs.TAKE_SLUDGE then
        if not (item and character:getInventory():containsRecursive(item)) then
            return "short"
        end
        local fullType = item:getFullType()
        if fullType ~= DigesterJobs.SANDBAG and not (fullType == DigesterJobs.COMPOST_BAG and item:getCurrentUsesFloat() < 1) then
            return "short"
        end
    elseif job == DigesterJobs.FILL_PUMP or job == DigesterJobs.FILL_COMPRESSOR then
        local refusal = DigesterJobs.fillRefusal(character, job, summary, item)
        if refusal then
            return refusal
        end
    end
    return RenewableEnergy.firstUnmet(DigesterJobs.needs(character, job)) and "short" or nil
end

--- refusalFor at `digester` as this side knows it now.
function DigesterJobs.refusal(character, job, digester, item)
    return DigesterJobs.refusalFor(character, job, Digester.currentSummary(digester), item)
end

return DigesterJobs
