-- What the authority's test handlers (RenewableEnergyTestServer*.lua, through
-- PZHarness.Test.server) share. Banks, stash houses, world spawns, sites, garden lights, loot and
-- the arrow board's parts exist or change only where the authority runs them. Single player runs
-- the handlers in the same Lua state, so the tests use them in both modes. Server Lua loads after
-- client Lua, and the mod's server files are empty on a multiplayer client, so the handlers look
-- the mod up when they run. Every answer is plain values, which cross the network; checks that
-- only read the authority's state answer { failures = { message, ... } }, which the test expects
-- to be empty (RenewableEnergyTest.expectNoFailures).
--
-- Named to sort before the handler files, so that a --stay rerun loads it again (RELOAD_FILES)
-- before the files that require it.

local Helpers = {}

--- The square at `args` ({ x, y, z }), or nil when there is none or it isn't loaded here.
function Helpers.squareAt(args)
    return args and args.x and getSquare(args.x, args.y, args.z)
end

--- Removes a tile object the way the game does, so the mod's removal handlers run.
function Helpers.removeObject(object)
    if object:getObjectIndex() == -1 then
        return
    end
    if RenewableEnergy.PowerBank.isBank(object) then
        RenewableEnergy.PowerBank.remove(object)
    else
        object:getSquare():transmitRemoveItemFromSquare(object)
    end
end

--- The names of the overlays an object's tile shows, in drawing order.
function Helpers.overlaysOf(object)
    local names = {}
    local attached = object and object:getAttachedAnimSprite()
    for i = 0, (attached and attached:size() or 0) - 1 do
        table.insert(names, attached:get(i):getName())
    end
    return names
end

return Helpers
