-- The authority's half of what the tests do to the character: its XP, inventory and stats, which
-- the authority owns in multiplayer. Only registers handlers, so a --stay rerun loads it again
-- (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
local Items = require "cf_commonlib/Items"

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
        Items.removeItem(item)
    end
    return { taken = #items }
end)

-- The character as the authority has it: the stats `args.stats` (CharacterStat field names) in
-- `stats`, and the XP in the perks `args.perks` (Perks field names) in `xp`, by name.
handler("character", function(player, args)
    local stats, xp = player:getStats(), player:getXp()
    local reply = { stats = {}, xp = {} }
    for _, name in ipairs(args.stats or {}) do
        reply.stats[name] = stats:get(CharacterStat[name])
    end
    for _, name in ipairs(args.perks or {}) do
        reply.xp[name] = xp:getXP(Perks[name])
    end
    return reply
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
