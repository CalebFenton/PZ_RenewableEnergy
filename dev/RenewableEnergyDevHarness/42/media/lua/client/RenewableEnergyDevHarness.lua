-- Development only, not published; dev/run-debug-client.sh loads it with the shared harness mod
-- (dev/harness), which runs the modes it registers here. Every mode starts the Renewable Energy
-- debug scenario, prints its result lines to console.txt for run-debug-client.sh, and quits:
-- --test runs every renewable_energy_* test (on a dedicated server's client with --mp), --promo
-- and --art save art (RenewableEnergyDevPromo, RenewableEnergyDevArt), and --loot measures the
-- loot lists (RenewableEnergyLoot) and each town's modules and batteries
-- (RenewableEnergyDevTownReport).

require "PZHarness/Runner"
require "RenewableEnergy/Debug/RenewableEnergyDebugScenario"
require "RenewableEnergy/Debug/RenewableEnergyLoot"
local Promo = require "RenewableEnergyDevPromo"
local Art = require "RenewableEnergyDevArt"
local TownReport = require "RenewableEnergyDevTownReport"

-- Samples per list: enough to measure a rare drop to a fraction of a percentage point.
local LOOT_SAMPLES = 10000
-- Battery Bank Spawn's "None". At its default a room seen for the first time now and then gets a
-- stocked bank (WorldSpawns' OnSeeNewRoom), and one near the start puts a bank in reach of the
-- panels and banks the tests build. The spawn tests place their banks with WorldSpawns.placeBank.
local NO_ROOM_BANKS = 1
-- Garden Lights at 0. A house is rolled for lights on the game minute after its surroundings load
-- (BuildingWatch), so one at the edge of the area the tests use can grow lights during a test; at
-- 0 it is still rolled, without lights. The garden light tests promise a house its lights as a
-- solar site does, or set the option themselves.
local NO_HOUSE_LIGHTS = 0

local function reportLoot(_, done)
    print("RELootReport START")
    RenewableEnergy.Loot.printReport(LOOT_SAMPLES)
    TownReport.print()
    done()
end

PZHarness.register({
    scenario = "RenewableEnergyScenario",
    prefix = "renewable_energy_",
    modes = {
        -- Both wait on the lighting, the zoom, the UI and the vehicles rather than on frame
        -- counts, so they draw uncapped, and they shoot a clear day.
        promo = { uncapped = true, clearWeather = true, fastUI = true, run = Promo.capture },
        art = { uncapped = true, clearWeather = true, fastUI = true, run = Art.capture },
        loot = { run = reportLoot },
    },
    onStart = function(mode)
        if mode == "test" then
            SandboxVars.RenewableEnergy.BatteryBankSpawn = NO_ROOM_BANKS
            SandboxVars.RenewableEnergy.GardenLights = NO_HOUSE_LIGHTS
        end
    end,
})
