-- The authority's half of what the tests do to the character: its XP, inventory and stats, which
-- the authority owns in multiplayer. Only registers handlers, so a --stay rerun loads it again
-- (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"

local handler = PZHarness.serverHandler

-- What the game gives the character for an Electricity award of `args.xp`, through the AddXP call
-- CraftRecipe.addXP makes outside a server.
handler("electricityAward", function(player, args)
    local xp = player:getXp()
    local before = xp:getXP(Perks.Electricity)
    xp:AddXP(Perks.Electricity, args.xp, true, true, false, false)
    return { gained = xp:getXP(Perks.Electricity) - before }
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
