-- The authority's half of what the tests do to the character: its XP, inventory and stats, which
-- the authority owns in multiplayer. Only registers handlers, so a --stay rerun loads it again
-- (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"

local handler = PZHarness.serverHandler

-- What the game gives the character for an Electricity award of `args.xp`, through the AddXP call
-- CraftRecipe.addXP makes outside a server.
handler("electricityAward", function(player, args)
    local xp = player:getXp()
    local before = xp:getXP(Perks.Electricity)
    xp:AddXP(Perks.Electricity, args.xp, true, true, false, false)
    return { gained = xp:getXP(Perks.Electricity) - before }
end)

-- Empties the fluid container of every carried item of full type `args.type`, fills it with
-- `args.liters` of `args.fluid` (a fluid name, none when nil), and sends the item to the
-- character's client.
handler("refillFluid", function(player, args)
    local items, all = {}, player:getInventory():getAllTypeRecurse(args.type)
    for i = 0, all:size() - 1 do
        if all:get(i):getFluidContainer() then
            table.insert(items, all:get(i))
        end
    end
    if #items == 0 then
        return nil, "the character's fluid container " .. tostring(args.type) .. " on the server"
    end
    for _, item in ipairs(items) do
        local fluids = item:getFluidContainer()
        fluids:Empty()
        if args.fluid then
            fluids:addFluid(args.fluid, args.liters)
        end
        item:syncItemFields()
    end
    return {}
end)

-- Takes the character's items of `args.ids`, or all of type `args.type`, out of the inventory, as
-- the server takes an item, which the client then loses too.
handler("takeItems", function(player, args)
    local inventory = player:getInventory()
    local items = {}
    for _, id in ipairs(args.ids or {}) do
        table.insert(items, inventory:getItemById(id))
    end
    if args.type then
        local all = inventory:getAllTypeRecurse(args.type)
        for i = 0, all:size() - 1 do
            table.insert(items, all:get(i))
        end
    end
    for _, item in ipairs(items) do
        local container = item:getContainer()
        container:Remove(item)
        sendRemoveItemFromContainer(container, item)
    end
    return { taken = #items }
end)

-- Sets vanilla's repair count of the character's items of `args.type` to `args.repaired`, as a
-- repair does, which the clients then see too.
handler("setRepaired", function(player, args)
    local all = player:getInventory():getAllTypeRecurse(args.type)
    for i = 0, all:size() - 1 do
        all:get(i):setHaveBeenRepaired(args.repaired)
        all:get(i):syncItemFields()
    end
    return { set = all:size() }
end)

-- What the character carries: for each type of `args.types` its items, bags included, { id,
-- condition, uses (the fraction left), repaired (vanilla's repair count), modData }; in `fluids`
-- the litres of each fluid of `args.fluids` (Fluid field names, or a modded fluid's name) in the
-- fluid containers of its main inventory; and in `total` how many items its main inventory holds.
handler("carried", function(player, args)
    local inventory = player:getInventory()
    local items = {}
    for _, fullType in ipairs(args.types or {}) do
        items[fullType] = {}
        local all = inventory:getAllTypeRecurse(fullType)
        for i = 0, all:size() - 1 do
            local item = all:get(i)
            table.insert(items[fullType], { id = item:getID(), condition = item:getCondition(),
                uses = item:getCurrentUsesFloat(), repaired = item:getHaveBeenRepaired(), modData = item:getModData() })
        end
    end
    local fluids = {}
    local carried = inventory:getItems()
    for _, name in ipairs(args.fluids or {}) do
        fluids[name] = 0
        for i = 0, carried:size() - 1 do
            local container = carried:get(i):getFluidContainer()
            if container then
                fluids[name] = fluids[name] + container:getSpecificFluidAmount(Fluid[name] or Fluid.Get(name))
            end
        end
    end
    return { items = items, fluids = fluids, total = carried:size() }
end)

-- The character's stats `args.stats` (CharacterStat field names) as the authority has them, in
-- `values` by name.
handler("characterStats", function(player, args)
    local values, stats = {}, player:getStats()
    for _, name in ipairs(args.stats or {}) do
        values[name] = stats:get(CharacterStat[name])
    end
    return { values = values }
end)

-- Sets the character's stat `args.stat` to `args.value` on the authority, and sends it, until the
-- test ends, when it is put back.
handler("setCharacterStatUntilEnd", function(player, args, defer)
    local stat = CharacterStat[args.stat]
    local stats = player:getStats()
    local function send()
        if isServer() then
            syncPlayerStats(player, SyncPlayerStatsPacket.getBitMaskForStat(stat))
        end
    end
    local before = stats:get(stat)
    stats:set(stat, args.value)
    send()
    defer(function()
        stats:set(stat, before)
        send()
    end)
    return {}
end)

-- The character's XP in the perk `args.perk` (a Perks field name) as the authority has it.
handler("perkXp", function(player, args)
    return { value = player:getXp():getXP(Perks[args.perk]) }
end)

-- Whether the character knows each of `names`, by name, judged by the recipe as the crafting menus
-- judge it, which counts its MetaRecipe.
local function knownOf(player, names)
    local known, scripts = {}, getScriptManager()
    for _, name in ipairs(names) do
        known[name] = player:isRecipeActuallyKnown(scripts:getCraftRecipe(name))
    end
    return known
end

-- Whether the authority's copy of the character knows each of `args.names`, in `known` by name.
handler("recipesKnown", function(player, args)
    return { known = knownOf(player, args.names) }
end)

-- The server's half of T.knowRecipes: the character knows (`args.known`) or forgets `args.names`,
-- and when the test ends knows exactly what it knew before, including what a level up taught.
handler("knowRecipes", function(player, args, defer)
    local Fixtures = PZHarness.Fixtures
    local saved = Fixtures.knownRecipes(player)
    if args.known then
        Fixtures.learnRecipes(player, args.names)
    else
        Fixtures.forgetRecipes(player, args.names)
    end
    defer(function()
        local known = player:getKnownRecipes()
        known:clear()
        for _, name in ipairs(saved) do
            known:add(name)
        end
    end)
    return {}
end)

-- Forgets `args.forget`, sets the levels `args.levels` (perk id -> level), each at the XP that starts
-- it, then awards the XP that takes `args.perk` one level up, as the authority awards a timed
-- action's XP: the game levels the perk up and fires LevelPerk. The perks setting puts the levels
-- back when the test ends, knowRecipes the recipes. Answers the level before and after.
handler("levelUp", function(player, args)
    local Fixtures = PZHarness.Fixtures
    Fixtures.forgetRecipes(player, args.forget)
    Fixtures.setPerkLevels(player, args.levels)
    local perk = Perks.FromString(args.perk)
    local before = player:getPerkLevel(perk)
    local next = PerkFactory.getPerk(perk):getTotalXpForLevel(before + 1)
    addXpNoMultiplier(player, perk, next - player:getXp():getXP(perk) + 1)
    return { before = before, after = player:getPerkLevel(perk) }
end)

-- Sets the levels `args.levels` (perk id -> level) with no level up, so no LevelPerk teaches
-- anything: a character who earned them before the mod, or its AutoLearn check, was added. The
-- perks setting puts them back when the test ends. Answers what it knows of `args.names`.
handler("setLevelsQuietly", function(player, args)
    PZHarness.Fixtures.setPerkLevels(player, args.levels)
    return { known = knownOf(player, args.names) }
end)
