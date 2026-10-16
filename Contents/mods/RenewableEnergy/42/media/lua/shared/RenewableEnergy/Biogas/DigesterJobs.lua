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

DigesterJobs.SANDBAG = "Base.EmptySandbag"
DigesterJobs.COMPOST_BAG = "Base.CompostBag"
local GARBAGE_BAG = "Base.Garbagebag"

-- In-game minutes each job takes.
DigesterJobs.MINUTES = {
    [DigesterJobs.TAKE_SLUDGE] = 10,
    [DigesterJobs.VENT] = 1,
    [DigesterJobs.REPLACE_BAGS] = 15,
    [DigesterJobs.SEW_TARP] = 60,
    [DigesterJobs.UPGRADE] = 120,
}

-- What each job takes beyond the state of the digester. `uses` counts uses of a drainable; `types`
-- lets any of several items count toward one need.
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
}

-- XP each job gives on the authority.
local XP = {
    [DigesterJobs.SEW_TARP] = { perk = "Tailoring", amount = 10 },
    [DigesterJobs.UPGRADE] = { perk = "Woodwork", amount = 30 },
}

local function notBroken(item)
    return not item:isBroken()
end

local function haveOf(character, material)
    local inventory = character:getInventory()
    if material.perk then
        return character:getPerkLevel(Perks[material.perk])
    elseif material.tool then
        return inventory:containsTagEvalRecurse(ItemTag[material.tool], notBroken) and 1 or 0
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
        local need = { have = haveOf(character, material), need = material.need or 1 }
        if material.perk then
            need.kind, need.perk = "skill", Perks[material.perk]
        elseif material.tool then
            need.kind, need.tool, need.item = "tool", material.tool, material.item
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

-- Sludge in one use of a compost bag.
local function sludgePerUse()
    local script = getScriptManager():FindItem(DigesterJobs.COMPOST_BAG)
    return Digester.SLUDGE_PER_BAG * script:getUseDelta()
end

--- The state of the digester that refuses `job`, as a translation key, or nil. `summary` is the
--- digester's (Digester.summaryOf).
function DigesterJobs.blocker(job, summary)
    if job == DigesterJobs.TAKE_SLUDGE then
        return summary.sludge < sludgePerUse() and "Tooltip_RenewableEnergy_NoSludge" or nil
    elseif job == DigesterJobs.VENT then
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
    end
    return nil
end

--- What refuses `character` doing `job` at the digester whose summary is `summary`: a blocker key,
--- "short" when they lack a need, or nil. `item` is the bag a Take Sludge fills.
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
    end
    return RenewableEnergy.firstUnmet(DigesterJobs.needs(character, job)) and "short" or nil
end

-- Authority --------------------------------------------------------------------------------------

local function useMaterials(character, job)
    local inventory = character:getInventory()
    for _, material in ipairs(MATERIALS[job] or {}) do
        if material.uses then
            local left = material.need
            local items = inventory:getAllTypeRecurse(material.item)
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                while left > 0 and item:getCurrentUses() > 0 do
                    item:UseAndSync()
                    left = left - 1
                end
            end
        elseif material.item and not material.tool then
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
--- needs were checked. Authority only. Returns whether it was done.
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
    end
    local xp = XP[job]
    if xp then
        addXp(character, Perks[xp.perk], xp.amount)
    end
    return true
end

return DigesterJobs
