-- Development only, not published; dev/run-debug-client.sh loads it with the shared harness mod
-- (dev/harness), which runs the modes it registers here. Every mode starts the Renewable Energy
-- debug scenario. With --test the harness runs every renewable_energy_* test and prints
-- "RETest DONE passed=<n> failed=<n> skipped=<n>"; with --test --mp it runs them on a client
-- joined to a dedicated server. With --promo, RenewableEnergyDevPromo saves the art for the README
-- and prints "REPromo DONE". With --art, RenewableEnergyDevArt saves close-ups of every item and
-- tile and prints "REArt DONE". With --loot, RenewableEnergy.Loot measures the loot and prints an
-- "RELootReport" line for each list, then the modules a thorough player finds in each town of
-- RenewableEnergyDevTownCensus (dev/loot/census.py), then "RELootReport DONE". Then the game
-- quits. run-debug-client.sh reads those lines from console.txt.

require "PZHarness/Runner"
require "RenewableEnergy/Debug/RenewableEnergyDebugScenario"
require "RenewableEnergy/Debug/RenewableEnergyLoot"
local Promo = require "RenewableEnergyDevPromo"
local Art = require "RenewableEnergyDevArt"

-- Samples per list: enough to measure a 2% chance to within about ±0.3 percentage points (95%).
local LOOT_SAMPLES = 10000
-- Battery Bank Spawn's "None". At its default a room seen for the first time now and then gets a
-- stocked bank (WorldSpawns' OnSeeNewRoom), and one near the start puts a bank in reach of the
-- panels and banks the tests build. The spawn tests place their banks with WorldSpawns.placeBank.
local NO_ROOM_BANKS = 1
-- Garden Lights at 0. A house is rolled for lights on the game minute after its surroundings load
-- (GardenLights.rollLoaded), so one at the edge of the area the tests use can grow lights during a
-- test; at 0 it is still rolled, without lights. The garden light tests roll with `always` or set
-- the option themselves.
local NO_HOUSE_LIGHTS = 0

local function share(fraction)
    return string.format("%.2f%% (1 in %.0f)", fraction * 100, 1 / fraction)
end

-- A module haul as "modules (watts as found / repaired)".
local function hauled(haul)
    local watts = RenewableEnergy.Specs.modules[RenewableEnergy.Specs.factoryModule].watts / 100
    return string.format("%.1f (%.0f / %.0f W)", haul.count, haul.condition * watts, haul.repaired * watts)
end

local function reportModules()
    local report = RenewableEnergy.Loot.moduleReport(require "RenewableEnergyDevTownCensus")
    print("RELootReport modules a thorough player finds, as count (watts as found / after Repair Cracked Module)")
    for _, town in ipairs(report.towns) do
        print(string.format("RELootReport modules in %s: room loot %s, cracked %s, world crates %s, vehicles %s, sites %s; total %s",
            town.name, hauled(town.listed), hauled(town.cracked), hauled(town.crates), hauled(town.vehicles),
            hauled(town.sites), hauled(town.total)))
    end
    for _, site in ipairs(report.sites) do
        print(string.format("RELootReport modules at site %s (%s): %s when placed, %.0f%% of worlds", site.name, site.kind,
            hauled(site.haul), site.chance * 100))
    end
    print(string.format("RELootReport modules: arrow boards per map: %.1f from vehicle zones, %.1f at sites",
        report.arrowBoards.zones, report.arrowBoards.sites))
end

local function reportLoot(_, done)
    print("RELootReport START")
    local report = RenewableEnergy.Loot.report(LOOT_SAMPLES)
    print(string.format("RELootReport settings: Other loot %.2f, Recipe Resources %.2f, loot rarity options 1, no zombie density bonus",
        report.settings.other, report.settings.recipeResource))
    for _, entry in ipairs(report) do
        local fullTypes = {}
        for fullType in pairs(entry.expected) do
            table.insert(fullTypes, fullType)
        end
        for fullType in pairs(entry.items) do
            if not entry.expected[fullType] then
                table.insert(fullTypes, fullType)
            end
        end
        table.sort(fullTypes)
        local parts = {}
        for _, fullType in ipairs(fullTypes) do
            local measured = entry.items[fullType]
            local text = measured and share(measured.share) or "none"
            if measured and measured.perContainer >= 1.05 then
                text = text .. string.format(", %.1f each", measured.perContainer)
            end
            -- Drops the module, so vanilla items the world entries count read the same way.
            table.insert(parts, (string.gsub(fullType, "^[^.]+%.", "")) .. " " .. text)
        end
        print(string.format("RELootReport %s [%s, %d samples]: %s", entry.label, entry.reference, entry.samples,
            #parts > 0 and table.concat(parts, "; ") or "nothing"))
    end
    reportModules()
    done()
end

PZHarness.register({
    scenario = "RenewableEnergyScenario",
    prefix = "renewable_energy_",
    modes = {
        -- Both wait on the lighting, the zoom, the UI and the vehicles rather than on frame
        -- counts, so they draw uncapped, and they shoot a clear day.
        promo = { uncapped = true, clearWeather = true, fastUI = true, run = Promo.capture },
        art = { uncapped = true, clearWeather = true, fastUI = true, run = function(_, done) Art.capture(done) end },
        loot = { run = reportLoot },
    },
    onStart = function(mode)
        if mode == "test" then
            SandboxVars.RenewableEnergy.BatteryBankSpawn = NO_ROOM_BANKS
            SandboxVars.RenewableEnergy.GardenLights = NO_HOUSE_LIGHTS
        end
    end,
})
