-- The authority's half of the tests (PZHarness.Test.server): fixtures only the server's bank system
-- can build, and its records, which a multiplayer client holds only copies of. Single player runs
-- them in the same Lua state, so tests use them in both modes. Server Lua loads after client Lua,
-- and the mod's server files are empty on a multiplayer client, so the handlers look the mod up
-- when they run. Only registers handlers, so a --stay rerun loads it again (RELOAD_FILES).

require "PZHarness/ServerHandlers"

-- A bank of Sprites field `args.kind` on the square at `args.x`, `args.y`, `args.z`, holding the
-- full types `args.items`, its batteries full, filled straight into its container as world spawns
-- do. Answers with the bank's position; removed when the test ends.
PZHarness.serverHandler("placeBank", function(_, args, defer)
    local PowerBank, Battery = RenewableEnergy.PowerBank, RenewableEnergy.Battery
    local square = getSquare(args.x, args.y, args.z)
    if not square then
        return nil, "the bank's square loaded on the server"
    end
    local bank = PowerBank.place(square, RenewableEnergy.Sprites[args.kind], -1)
    defer(function()
        if bank:getObjectIndex() ~= -1 then
            PowerBank.remove(bank)
        end
    end)
    local container = bank:getContainer()
    for _, fullType in ipairs(args.items or {}) do
        local item = container:AddItem(fullType)
        if item and Battery.isBattery(item) then
            Battery.setCharge(item, 1)
        end
    end
    local position = PowerBank.positionOf(bank)
    PowerBank.perform(nil, "refresh", { bank = position })
    if not PowerBank.serverSystem:getLuaObjectOnSquare(square) then
        return nil, "a bank the server's bank system registered"
    end
    return position
end)

-- The server's record of the bank at `args`: whether there is one, whether it is on, its name.
PZHarness.serverHandler("bankState", function(_, args)
    local record = RenewableEnergy.PowerBank.serverSystem:getLuaObjectAt(args.x, args.y, args.z)
    return { found = record ~= nil, on = record ~= nil and record.on == true, name = record and record.name or "" }
end)
