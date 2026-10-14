-- Development only, not published. The test library's settings, which the client and the
-- server both read (dev/harness/docs/adopting.md). Shared Lua loads before the mod's client and
-- server Lua, so the hooks look those modules up when they run.

require "PZHarness/Fixtures"

PZHarness.registerTests({
    -- Daylight, so crafting and wiring can see and panels have sun.
    hour = 10,
    -- The perks the mod's actions and recipes read.
    perks = { Perks.Electricity, Perks.MetalWelding, Perks.Woodwork },
    sandbox = "RenewableEnergy",
    recipePrefix = "RenewableEnergy_",
    isFreeSquare = function(square, indoors)
        return RenewableEnergy.Debug.isFreeSquare(square, indoors)
    end,
    remove = function(object)
        if not RenewableEnergy.PowerBank.isBank(object) then
            return false
        end
        RenewableEnergy.PowerBank.remove(object)
        return true
    end,
    spawnVehicle = function(script, square, facing, args)
        return require("RenewableEnergy/Debug/RenewableEnergyTestServerTrailer").spawnVehicle(script, square, facing, args)
    end,
})
