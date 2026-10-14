-- What the authority's test handlers (RenewableEnergyTestServer*.lua, through
-- PZHarness.Test.server) share. They build and read what exists or changes only where the authority
-- runs it. Single player runs the handlers in the same Lua state, so the tests use them in both
-- modes. Server Lua loads after client Lua, and the mod's server files are empty on a multiplayer
-- client, so the handlers look the mod up when they run. Every answer is plain values, which cross
-- the network.
--
-- Named to sort before the handler files, so that a --stay rerun loads it again (RELOAD_FILES)
-- before the files that require it.

require "PZHarness/ServerHandlers"
require "PZHarness/Checks"
require "PZHarness/Fixtures"

local Helpers = {}

--- Registers the server check `name`, which only reads the authority's state and answers
--- { failures = { message, ... } }, which the test expects to be empty
--- (RenewableEnergyTest.expectNoFailures). `fn(expect, expectNear, player, args, defer)` records
--- what it finds wrong through the PZHarness.Checks.new pair; it may instead return what is
--- missing, which fails the test as a handler's `nil, missing` does.
function Helpers.check(name, fn)
    PZHarness.serverHandler(name, function(player, args, defer)
        local expect, expectNear, failures = PZHarness.Checks.new()
        local missing = fn(expect, expectNear, player, args, defer)
        if missing then
            return nil, missing
        end
        return { failures = failures }
    end)
end

--- Saves the mod's sandbox options `names` for a handler that changes them, and returns the
--- function that puts them back and then calls `reapply`, if given, to rebuild what the game made
--- from them. The handler calls it when done; it is also deferred, so that a handler that throws
--- first still puts them back (the harness unwinds a failed call at once). It runs once.
function Helpers.saveOptions(defer, names, reapply)
    local options, saved, restored = SandboxVars.RenewableEnergy, {}, false
    for _, name in ipairs(names) do
        saved[name] = options[name]
    end
    local function restore()
        if restored then
            return
        end
        restored = true
        for _, name in ipairs(names) do
            options[name] = saved[name]
        end
        if reapply then
            reapply()
        end
    end
    defer(restore)
    return restore
end

--- The square at `args` ({ x, y, z }), or nil when there is none or it isn't loaded here.
function Helpers.squareAt(args)
    return args and args.x and getSquare(args.x, args.y, args.z)
end

--- The vehicle `args` names ({ id, x, y, z }: RenewableEnergyTest.vehicleArgs; single player
--- finds it by the squares around x, y, z), or nil and what is missing when there is none or it
--- has been taken out of the world.
function Helpers.vehicleAt(args)
    local vehicle = args and PZHarness.Fixtures.vehicleById(args.id, args)
    if not vehicle or vehicle:isRemovedFromWorld() then
        return nil, "vehicle " .. tostring(args and args.id) .. " on the server"
    end
    return vehicle
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
