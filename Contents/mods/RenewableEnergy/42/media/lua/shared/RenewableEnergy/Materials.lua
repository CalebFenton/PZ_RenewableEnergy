-- What a job takes of the character, written once as data (a materials list) and read two ways:
-- as needs, which the menu shows and the refusal checks (RenewableEnergy.firstUnmet), and, on the
-- authority, as what the job uses up. Reading both from one list keeps them from disagreeing.
--
-- A material is one of:
--   { perk = "Name", need = level }           a skill level (Perks[Name])
--   { tool = "TAG", item = fullType }         a working tool with an ItemTag, `item` naming it in
--                                             the tooltip; `useOne` takes one use of it, as a match
--   { tag = "TAG", item = fullType }          an item with an ItemTag, taken
--   { water = litres }                        water in any carried container, poured out
--   { item = fullType, need = n }             items of a type, taken; `types` lets any of several
--                                             types count, `uses` counts and takes uses of a
--                                             drainable, `keep` needs it but takes nothing

require "RenewableEnergy/Utilities"

RenewableEnergy = RenewableEnergy or {}
local Materials = {}
RenewableEnergy.Materials = Materials

-- Lighting a fire takes one use of a match or lighter, as a campfire does.
Materials.FIRE_STARTER = { tool = "START_FIRE", item = "Base.Matches", useOne = true }

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
        return RenewableEnergy.hasWorkingTool(character, ItemTag[material.tool]) and 1 or 0
    elseif material.tag then
        return inventory:getCountTagEvalRecurse(ItemTag[material.tag], RenewableEnergy.notBroken)
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

--- What `list` takes of `character`, as needs (RenewableEnergy.firstUnmet, RenewableEnergy.Needs).
function Materials.needs(character, list)
    local needs = {}
    for _, material in ipairs(list or {}) do
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

local function pourWater(character, litres)
    local left = litres
    for _, item in ipairs(waterSources(character)) do
        local fluid = item:getFluidContainer()
        local take = math.min(left, fluid:getAmount())
        if take > 0 then
            fluid:removeFluid(take, false)
            item:syncItemFields()
            left = left - take
        end
        if left <= 0 then
            return
        end
    end
end

local function useUses(character, fullType, count)
    local left = count
    local items = character:getInventory():getAllTypeRecurse(fullType)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        while left > 0 and item:getCurrentUses() > 0 do
            item:UseAndSync()
            left = left - 1
        end
    end
end

--- Takes from `character` what `list` uses up, once its needs were checked. Authority only.
function Materials.consume(character, list)
    local inventory = character:getInventory()
    for _, material in ipairs(list or {}) do
        if material.water then
            pourWater(character, material.water)
        elseif material.tool then
            local tool = material.useOne and inventory:getFirstTagEvalRecurse(ItemTag[material.tool], RenewableEnergy.notBroken)
            if tool and instanceof(tool, "DrainableComboItem") then
                tool:UseAndSync()
            end
        elseif material.tag then
            local item = inventory:getFirstTagEvalRecurse(ItemTag[material.tag], RenewableEnergy.notBroken)
            if item then
                RenewableEnergy.takeItem(character, item)
            end
        elseif material.uses then
            useUses(character, material.item, material.need)
        elseif material.item and not material.keep then
            local left = material.need or 1
            for _, fullType in ipairs(material.types or { material.item }) do
                local take = math.min(left, inventory:getCountTypeRecurse(fullType))
                RenewableEnergy.takeItems(character, fullType, take)
                left = left - take
            end
        end
    end
end

return Materials
