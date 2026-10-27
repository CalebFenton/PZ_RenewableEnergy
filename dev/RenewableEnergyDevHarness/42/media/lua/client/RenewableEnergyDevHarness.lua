-- Development only, not published; dev/run-debug-client.sh loads it with the shared harness mod
-- (dev/harness), which runs the modes it registers here. Every mode starts the Renewable Energy
-- debug scenario, prints its result lines to console.txt for run-debug-client.sh, and quits:
-- --test runs every renewable_energy_* test (on a dedicated server's client with --mp), --promo
-- and --art save art (RenewableEnergyDevPromo, RenewableEnergyDevArt), and --loot measures the
-- loot lists (RenewableEnergyLoot) and each town's modules and batteries
-- (RenewableEnergyDevTownReport).

require "PZHarness/Runner"
require "RenewableEnergy/Debug/RenewableEnergyDebugScenario"
local Loot = require "RenewableEnergy/Debug/RenewableEnergyLoot"
local Promo = require "RenewableEnergyDevPromo"
local Art = require "RenewableEnergyDevArt"
local TownReport = require "RenewableEnergyDevTownReport"

-- Samples per list: enough to measure a rare drop to a fraction of a percentage point.
local LOOT_SAMPLES = 10000

local function reportLoot(_, done)
    local mark = PZHarness.run.mark
    print(mark .. " START")
    Loot.printReport(LOOT_SAMPLES, mark)
    TownReport.print(LOOT_SAMPLES, mark)
    done()
end

PZHarness.register({
    scenario = "RenewableEnergyScenario",
    prefix = "renewable_energy_",
    modes = {
        -- Both wait on the lighting, the zoom, the UI and the vehicles rather than on frame
        -- counts, and shoot a clear day.
        promo = { capture = true, run = Promo.capture },
        art = { capture = true, run = Art.capture },
        loot = { run = reportLoot },
    },
})
