-- The hands-on jobs at a digester: what each takes of the character, what refuses it, and, on the
-- authority, what it does. The menu shows the same needs the authority checks, so they can't
-- disagree (RenewableEnergy.firstUnmet).

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Biogas/Digester"

RenewableEnergy = RenewableEnergy or {}
local DigesterJobs = {}
RenewableEnergy.DigesterJobs = DigesterJobs

local Digester, Sprites = RenewableEnergy.Digester, RenewableEnergy.Sprites

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
local GARBAGE_BAG = "Base.Garbagebag"
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
local CHARGES = { [DigesterJobs.CHARGE_WATER] = "water", [DigesterJobs.CHARGE_ASH] = "ash", [DigesterJobs.CHARGE_LIME] = "lime" }

-- What each job takes beyond the state of the digester. `uses` counts uses of a drainable, `types`
-- lets any of several items count toward one need, `tag` counts items with an ItemTag, `water`
-- counts litres of water in any container, and `keep` is an item the job needs but keeps.
local MATERIALS = {
    [DigesterJobs.REPLACE_BAGS] = {
        { item = GARBAGE_BAG, need = 3 },
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
        { item = "Base.HayTuft", types = { "Base.HayTuft", "Base.Straw2" }, need = 10 },
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
        { item = "RenewableEnergy.WoodAsh", need = 1 },
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
local XP = {
    [DigesterJobs.SEW_TARP] = { perk = "Tailoring", amount = 10 },
    [DigesterJobs.UPGRADE] = { perk = "Woodwork", amount = 30 },
    [DigesterJobs.FIT_SCRUBBER] = { perk = "Mechanics", amount = 10 },
}

local function notBroken(item)
    return not item:isBroken()
end

-- The containers of water the character carries, most first.
local function waterSources(character)
    local list = {}
    local sources = character:getInventory():getAllWaterFluidSources(false)
    for i = 0, sources:size() - 1 do
        table.insert(list, sources:get(i))
    end
    table.sort(list, function(a, b)
        return a:getFluidContainer():getAmount() > b:getFluidContainer():getAmount()
    end)
    return list
end

local function haveOf(character, material)
    local inventory = character:getInventory()
    if material.perk then
        return character:getPerkLevel(Perks[material.perk])
    elseif material.tool then
        return inventory:containsTagEvalRecurse(ItemTag[material.tool], notBroken) and 1 or 0
    elseif material.tag then
        return inventory:getCountTagRecurse(ItemTag[material.tag])
    elseif material.water then
        local litres = 0
        for _, item in ipairs(waterSources(character)) do
            litres = litres + item:getFluidContainer():getAmount()
        end
        return math.floor(litres * 10) / 10
    elseif material.uses then
        return inventory:getUsesTypeRecurse(material.item)
    end
    local have = 0
    for _, fullType in ipairs(material.types or { material.item }) do
        have = have + inventory:getCountTypeRecurse(fullType)
    end
    return have
end

--- What `job` takes of `character`, as needs (RenewableEnergy.firstUnmet, RenewableEnergy.Needs).
function DigesterJobs.needs(character, job)
    local needs = {}
    for _, material in ipairs(MATERIALS[job] or {}) do
        local need = { have = haveOf(character, material), need = material.water or material.need or 1 }
        if material.perk then
            need.kind, need.perk = "skill", Perks[material.perk]
        elseif material.tool then
            need.kind, need.tool, need.item = "tool", material.tool, material.item
        elseif material.water then
            -- A key, not the text: the server reads needs too and has no IG_UI translations.
            need.kind, need.labelKey = "water", "IGUI_RenewableEnergy_WaterLitres"
        else
            need.kind, need.item = "item", material.item
            if material.types then
                local names = {}
                for _, fullType in ipairs(material.types) do
                    table.insert(names, getItemNameFromFullType(fullType))
                end
                need.label = table.concat(names, " / ")
            end
        end
        table.insert(needs, need)
    end
    return needs
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

-- Sludge in one use of a compost bag.
local function sludgePerUse()
    local script = getScriptManager():FindItem(DigesterJobs.COMPOST_BAG)
    return Digester.SLUDGE_PER_BAG * script:getUseDelta()
end

-- Gas a tank holds per use of it.
local function m3PerUse(tank)
    return Digester.M3_PER_TANK * tank:getUseDelta()
end

--- How far `job` fills `tank`: the share of a full tank it stops at.
function DigesterJobs.fillLimit(job)
    return job == DigesterJobs.FILL_PUMP and Digester.PUMP_FILL or 1
end

--- The gas, in m³, a fill of `tank` would move now from a digester whose summary is `summary`:
--- unscrubbed up to the pump's share, and scrubbed beyond it for the compressor.
function DigesterJobs.fillAmount(job, summary, tank)
    local filled = tank:getCurrentUsesFloat()
    local plain = math.max(0, Digester.PUMP_FILL - filled) * Digester.M3_PER_TANK
    local gas = summary.gas
    local m3 = math.min(gas, plain)
    if job == DigesterJobs.FILL_COMPRESSOR then
        local scrubbed = math.min(summary.scrubCO2 or 0, summary.scrubWool or 0)
        local above = (1 - math.max(filled, Digester.PUMP_FILL)) * Digester.M3_PER_TANK
        m3 = m3 + math.min(gas - m3, above, scrubbed)
    end
    return math.max(0, m3)
end

--- In-game minutes `job` takes at the digester whose summary is `summary`; `item` is the job's tank
--- or bag.
function DigesterJobs.minutesFor(job, summary, item)
    local minutes = DigesterJobs.MINUTES[job]
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
        return summary.sludge < sludgePerUse() and "Tooltip_RenewableEnergy_NoSludge" or nil
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
    elseif CHARGES[job] or job == DigesterJobs.REPACK_WOOL then
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
        if tank:getCurrentUsesFloat() >= DigesterJobs.fillLimit(job) then
            return job == DigesterJobs.FILL_PUMP and "Tooltip_RenewableEnergy_PumpLimit" or "Tooltip_RenewableEnergy_TankFull"
        end
        return "Tooltip_RenewableEnergy_NeedsScrubbed"
    end
    return nil
end

--- What refuses `character` doing `job` at the digester whose summary is `summary`: a blocker key,
--- "short" when they lack a need, or nil. `item` is the bag a Take Sludge fills or the tank a fill
--- fills.
function DigesterJobs.refusal(character, job, summary, item)
    if not summary or not DigesterJobs.MINUTES[job] then
        return "Tooltip_RenewableEnergy_NoDigester"
    end
    local blocker = DigesterJobs.blocker(job, summary)
    if blocker then
        return blocker
    end
    if job == DigesterJobs.TAKE_SLUDGE then
        local inventory = character:getInventory()
        if not (item and inventory:containsRecursive(item)) then
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

-- Authority --------------------------------------------------------------------------------------

local function useWater(character, litres)
    local left = litres
    for _, item in ipairs(waterSources(character)) do
        local fluid = item:getFluidContainer()
        local take = math.min(left, fluid:getAmount())
        if take > 0 then
            fluid:removeFluid(take, false)
            syncItemFields(character, item)
            left = left - take
        end
        if left <= 0 then
            return
        end
    end
end

local function useMaterials(character, job)
    local inventory = character:getInventory()
    for _, material in ipairs(MATERIALS[job] or {}) do
        if material.water then
            useWater(character, material.water)
        elseif material.uses then
            local left = material.need
            local items = inventory:getAllTypeRecurse(material.item)
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                while left > 0 and item:getCurrentUses() > 0 do
                    item:UseAndSync()
                    left = left - 1
                end
            end
        elseif material.tag then
            local item = inventory:getFirstTagEvalRecurse(ItemTag[material.tag], notBroken)
            if item then
                RenewableEnergy.takeItem(character, item)
            end
        elseif material.item and not material.tool and not material.keep then
            local left = material.need
            for _, fullType in ipairs(material.types or { material.item }) do
                local items = inventory:getSomeTypeRecurse(fullType, left)
                for i = 0, items:size() - 1 do
                    RenewableEnergy.takeItem(character, items:get(i))
                    left = left - 1
                end
            end
        end
    end
end

-- Take Sludge, as vanilla's ISGetCompost fills compost bags from a composter.
local function takeSludge(character, digester, item)
    local perUse = sludgePerUse()
    local usesPerBag = math.floor(1 / getScriptManager():FindItem(DigesterJobs.COMPOST_BAG):getUseDelta() + 0.5)
    local uses = math.floor(digester.sludge / perUse)
    local bag = item
    if item:getFullType() == DigesterJobs.COMPOST_BAG then
        uses = math.min(uses, usesPerBag - item:getCurrentUses())
        item:setCurrentUses(item:getCurrentUses() + uses)
        syncItemFields(character, item)
    else
        uses = math.min(uses, usesPerBag)
        RenewableEnergy.takeItem(character, item)
        bag = instanceItem(DigesterJobs.COMPOST_BAG)
        bag:setCurrentUses(uses)
        character:getInventory():AddItem(bag)
        sendAddItemToContainer(character:getInventory(), bag)
    end
    if uses <= 0 then
        return false
    end
    digester.sludge = math.max(0, digester.sludge - uses * perUse)
    return true
end

-- Fills `tank` from the digester as far as `job` goes. Returns the m³ moved.
local function fillTank(character, job, digester, tank)
    local summary = { gas = digester.gas, scrubCO2 = digester.scrubCO2, scrubWool = digester.scrubWool }
    local perUse = m3PerUse(tank)
    local uses = math.floor(DigesterJobs.fillAmount(job, summary, tank) / perUse)
    if uses <= 0 then
        return 0
    end
    local m3 = uses * perUse
    local plain = math.max(0, Digester.PUMP_FILL - tank:getCurrentUsesFloat()) * Digester.M3_PER_TANK
    local scrubbed = math.max(0, m3 - plain)
    tank:setCurrentUses(tank:getCurrentUses() + uses)
    syncItemFields(character, tank)
    digester.gas = math.max(0, digester.gas - m3)
    if scrubbed > 0 then
        digester.scrubCO2 = math.max(0, digester.scrubCO2 - scrubbed)
        digester.scrubWool = math.max(0, digester.scrubWool - scrubbed)
    end
    return m3
end

local function upgrade(digester, isoObject)
    digester.tier = "insulated"
    digester.material = nil
    digester.holder = "drum"
    digester.holderCondition = 100
    digester.gas = math.min(digester.gas, Digester.HOLDERS.drum.capacity)
    -- The tile's own sprite, with its properties; setSprite(name) would make a bare texture.
    isoObject:setSprite(getSprite(Sprites.digester.insulated))
    local container = isoObject:getContainer()
    if container then
        container:setCapacity(tonumber(isoObject:getProperties():get("ContainerCapacity")) or container:getCapacity())
    end
    if isServer() then
        isoObject:transmitUpdatedSpriteToClients()
    end
end

--- Does `job` at the digester (its record `digester` and tile `isoObject`) for `character`, whose
--- needs were checked. `item` is the job's bag or tank. Authority only. Returns whether it was done.
function DigesterJobs.apply(character, job, digester, isoObject, item)
    if job == DigesterJobs.TAKE_SLUDGE then
        if not takeSludge(character, digester, item) then
            return false
        end
    elseif job == DigesterJobs.VENT then
        digester.gas = 0
        if digester.indoors then
            digester.leakHours = math.max(digester.leakHours, 1)
        end
    elseif job == DigesterJobs.REPLACE_BAGS or job == DigesterJobs.SEW_TARP then
        useMaterials(character, job)
        digester.holder = job == DigesterJobs.SEW_TARP and "tarp" or "bags"
        digester.holderCondition = 100
        digester.gas = 0
    elseif job == DigesterJobs.UPGRADE then
        useMaterials(character, job)
        upgrade(digester, isoObject)
    elseif job == DigesterJobs.FILL_PUMP or job == DigesterJobs.FILL_COMPRESSOR then
        local m3 = fillTank(character, job, digester, item)
        if m3 <= 0 then
            return false
        end
        if job == DigesterJobs.FILL_PUMP then
            character:getStats():remove(CharacterStat.ENDURANCE, m3 * Digester.PUMP_ENDURANCE_PER_M3)
        end
    elseif job == DigesterJobs.FIT_SCRUBBER then
        useMaterials(character, job)
        digester.scrubber = true
        digester.scrubCO2 = 0
        digester.scrubWool = Digester.WOOL_M3
    elseif CHARGES[job] then
        useMaterials(character, job)
        digester.scrubCO2 = Digester.SCRUB_M3[CHARGES[job]]
    elseif job == DigesterJobs.REPACK_WOOL then
        useMaterials(character, job)
        digester.scrubWool = Digester.WOOL_M3
    end
    local xp = XP[job]
    if xp then
        addXp(character, Perks[xp.perk], xp.amount)
    end
    return true
end

return DigesterJobs
