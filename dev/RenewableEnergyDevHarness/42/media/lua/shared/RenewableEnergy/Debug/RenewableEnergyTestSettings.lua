-- Development only, not published. The test library's settings, which the client and the
-- server both read (dev/harness/docs/adopting.md). Shared Lua loads before the mod's client and
-- server Lua, so the hooks look those modules up when they run.

require "PZHarness/Fixtures"

PZHarness.registerTests({
    -- Daylight, so crafting and wiring can see and panels have sun.
    hour = 10,
    -- The perks the mod's actions and recipes read or train: each test gets their levels back, so
    -- XP from repeated crafts (REPEAT=n) can't level one up and fail the leak check.
    perks = { Perks.Electricity, Perks.MetalWelding, Perks.Woodwork, Perks.Mechanics, Perks.Blacksmith,
        Perks.Carving, Perks.Farming, Perks.Glassmaking, Perks.Masonry, Perks.Pottery, Perks.Tailoring,
        Perks.Fitness, Perks.Sprinting },
    sandbox = "RenewableEnergy",
    recipePrefix = "RenewableEnergy_",
    isFreeSquare = function(square, indoors)
        return RenewableEnergy.Debug.isFreeSquare(square, indoors)
    end,
    remove = function(object)
        if not RenewableEnergy.PowerBank.isBank(object) then
            return false
        end
        object:getSquare():transmitRemoveItemFromSquare(object)
        return true
    end,
    spawnVehicle = function(script, square, facing, args)
        return require("RenewableEnergy/Debug/RenewableEnergyTestServerTrailer").spawnVehicle(script, square, facing, args)
    end,
})
