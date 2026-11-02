-- Development only, not published. The test library's settings, which the client and the
-- server both read (dev/harness/docs/adopting.md). Shared Lua loads before the mod's client and
-- server Lua, so the hooks look those modules up when they run.

require "PZHarness/Fixtures"
local Chance = require "cf_commonlib/Chance"
local Digester = require "RenewableEnergy/Biogas/Digester"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local Kinds = require "RenewableEnergy/Debug/RenewableEnergyTestKinds"

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
        return require("RenewableEnergy/Debug/RenewableEnergyDebug").isFreeSquare(square, indoors)
    end,
    remove = function(object, player)
        if PowerBank.isBank(object) then
            object:getSquare():transmitRemoveItemFromSquare(object)
            return true
        end
        -- Removing a digester clears its stink only at the next game minute (Stink.clear waits, for
        -- a record that goes as its chunk loads), by when the next test would smell it: settled now,
        -- the later clear finds nothing. Vanilla's removal then takes the digester.
        if Digester.isDigester(object) and not isClient() then
            local record = Digester.recordOf(object)
            if record then
                require("RenewableEnergy/Biogas/Stink").set(record:key(), record.x, record.y, record.z, 0)
            end
            return false
        end
        if not (Sources.kindOf(object) or Treadmill.isTreadmill(object) or Treadmill.isWiredTile(object)) then
            return false
        end
        -- A wired treadmill taken away drops its wire on its square (TreadmillSource.unwire), which
        -- the tests that follow would find lying about; unwired first, it goes to the character,
        -- whose inventory the next test empties.
        if Treadmill.isWiredTile(object) and not isClient() then
            require("RenewableEnergy/PowerBank/TreadmillSource").unwire(object, player)
        end
        -- Removing "safely" takes every tile of a whole multi-tile object, and refuses one tile of
        -- one placed alone (a treadmill's, a wind charger's), which then goes on its own.
        local square = object:getSquare()
        if square:transmitRemoveItemFromSquare(object) == -1 then
            square:transmitRemoveItemFromSquare(object, false)
        end
        return true
    end,
    spawnVehicle = function(script, square, facing, args, defer)
        return require("RenewableEnergy/Debug/RenewableEnergyTestServerTrailer").spawnVehicle(script, square, facing, args,
            defer)
    end,
    chance = function() return Chance end,
    records = Kinds.RECORDS,
    jobAction = function() return RenewableEnergyAction end,
})
