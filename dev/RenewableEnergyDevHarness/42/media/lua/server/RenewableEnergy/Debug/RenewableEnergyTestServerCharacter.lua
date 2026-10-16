-- The authority's half of what the tests do to the character: its XP, inventory, recipes and
-- reading, which the authority owns in multiplayer. Only registers handlers, so a --stay rerun
-- loads it again (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"

local handler = PZHarness.serverHandler

-- What the game gives the character for an Electricity award of `args.xp`, through the call
-- CraftRecipe.addXP makes, and its Electricity XP after.
handler("electricityAward", function(player, args)
    local xp = player:getXp()
    local before = xp:getXP(Perks.Electricity)
    xp:AddXP(Perks.Electricity, args.xp, true, true, false, false)
    return { gained = xp:getXP(Perks.Electricity) - before, xp = xp:getXP(Perks.Electricity) }
end)

-- Empties the fluid container of the character's item `args.id`, fills it with `args.liters` of
-- `args.fluid` (a fluid name, none when nil), and sends the item to the character's client.
handler("refillFluid", function(player, args)
    local item = player:getInventory():getItemById(args.id)
    local fluids = item and item:getFluidContainer()
    if not fluids then
        return nil, "the character's fluid container " .. tostring(args.id) .. " on the server"
    end
    fluids:Empty()
    if args.fluid then
        fluids:addFluid(args.fluid, args.liters)
    end
    item:syncItemFields()
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

-- What the character carries: for each type of `args.types` its items, bags included, { id,
-- condition, uses (the fraction left), modData }; in `fluids` the litres of each fluid of
-- `args.fluids` (Fluid field names, or a modded fluid's name) in the fluid containers of its main inventory; and in `total`
-- how many items its main inventory holds.
handler("carried", function(player, args)
    local inventory = player:getInventory()
    local items = {}
    for _, fullType in ipairs(args.types or {}) do
        items[fullType] = {}
        local all = inventory:getAllTypeRecurse(fullType)
        for i = 0, all:size() - 1 do
            local item = all:get(i)
            table.insert(items[fullType], { id = item:getID(), condition = item:getCondition(),
                uses = item:getCurrentUsesFloat(), modData = item:getModData() })
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

-- The recipes the character has learned whose names start with `args.prefix`, as a set.
handler("knownRecipes", function(player, args)
    local known, list = {}, player:getKnownRecipes()
    for i = 0, list:size() - 1 do
        local name = list:get(i)
        if string.sub(name, 1, #args.prefix) == args.prefix then
            known[name] = true
        end
    end
    return { known = known }
end)

-- Forgets that the character read the literature `args.title`, whose cooldown would make reading
-- it again teach nothing.
handler("forgetLiterature", function(player, args)
    player:getReadLiterature():remove(args.title)
    return {}
end)

-- Forgets the recipes `args.names` until the test ends, when the character knows them again.
handler("forgetRecipesUntilEnd", function(player, args, defer)
    PZHarness.Fixtures.forgetRecipes(player, args.names)
    defer(function() PZHarness.Fixtures.learnRecipes(player, args.names) end)
    return {}
end)

-- The character's stat `args.stat` (a CharacterStat field name) as the authority has it.
handler("characterStat", function(player, args)
    return { value = player:getStats():get(CharacterStat[args.stat]) }
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
