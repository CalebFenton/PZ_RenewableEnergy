-- Development only, not published; dev/run-debug-client.sh loads it with the shared harness mod
-- (dev/harness), which runs the modes it registers here. Every mode starts the Renewable Energy
-- debug scenario, prints its result lines to console.txt for run-debug-client.sh, and quits:
-- --test runs every renewable_energy_* test (on a dedicated server's client with --mp), --promo
-- and --art save art (RenewableEnergyDevPromo, RenewableEnergyDevArt), and --loot measures the
-- loot lists and each town's module and battery haul (RenewableEnergyDevTownCensus).

require "PZHarness/Runner"
require "RenewableEnergy/Debug/RenewableEnergyDebugScenario"
require "RenewableEnergy/Debug/RenewableEnergyLoot"
local Promo = require "RenewableEnergyDevPromo"
local Art = require "RenewableEnergyDevArt"

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

local function share(fraction)
    return string.format("%.2f%% (1 in %.0f)", fraction * 100, 1 / fraction)
end

-- A module haul as "modules (watts as found / repaired)".
local function hauled(haul)
    local watts = RenewableEnergy.Specs.modules[RenewableEnergy.Specs.factoryModule].watts / 100
    return string.format("%.1f (%.0f / %.0f W)", haul.count, haul.condition * watts, haul.repaired * watts)
end

local function reportModules(census)
    local report = RenewableEnergy.Loot.moduleReport(census)
    print("RELootReport modules a thorough player finds, as count (watts as found / after Seal Cracked Module)")
    for _, town in ipairs(report.towns) do
        print(string.format("RELootReport modules in %s: room loot %s, cracked %s, world crates %s, beside world banks %s, vehicles %s, sites %s; total %s",
            town.name, hauled(town.listed), hauled(town.cracked), hauled(town.crates), hauled(town.besideBanks),
            hauled(town.vehicles), hauled(town.sites), hauled(town.total)))
    end
    for _, site in ipairs(report.sites) do
        print(string.format("RELootReport modules at site %s (%s): %s when placed, %.0f%% of worlds", site.name, site.kind,
            hauled(site.haul), site.chance * 100))
    end
    print(string.format("RELootReport modules: arrow boards per map: %.1f from vehicle zones, %.1f at sites",
        report.arrowBoards.zones, report.arrowBoards.sites))
    return report
end

-- A battery haul as "batteries (kWh as found)".
local function stored(haul)
    return string.format("%.1f (%.1f kWh)", haul.count, haul.wh / 1000)
end

local function reportBatteries(census, modules)
    local Loot = RenewableEnergy.Loot
    local options = SandboxVars.RenewableEnergy
    local report = Loot.batteryReport(census)
    print(string.format("RELootReport batteries a thorough player finds, as count (kWh as found); Battery Bank Spawn %d, Solar Sites %d%%",
        options.BatteryBankSpawn, options.SolarSites))
    for _, town in ipairs(report.towns) do
        print(string.format("RELootReport batteries in %s: room loot %s, world banks %.1f holding %s, kit crates %s, vehicles %s, sites %s; total %s; car batteries in room loot %.1f",
            town.name, stored(town.listed), town.bankCount, stored(town.banks), stored(town.crates), stored(town.vehicles),
            stored(town.sites), stored(town.total), town.cars))
        local rooms = {}
        for roomName, placed in pairs(town.banksByRoom) do
            table.insert(rooms, string.format("%s %.1f", roomName, placed))
        end
        table.sort(rooms)
        print(string.format("RELootReport world banks in %s by room: %s", town.name, table.concat(rooms, ", ")))
    end
    local names = {}
    for name in pairs(report.stocks) do
        table.insert(names, name)
    end
    table.sort(names)
    for _, name in ipairs(names) do
        print(string.format("RELootReport batteries in a %s bank: %s", name, stored(report.stocks[name])))
    end
    local sticks = Loot.yardsticks()
    for _, month in ipairs({ "july", "december" }) do
        local wh = sticks.moduleWh[month]
        print(string.format("RELootReport yardstick: a new module banks a day in mid-%s, average (clear): flat %.0f (%.0f), south rack %.0f (%.0f), south wall %.0f (%.0f) Wh at Sunlight Multiplier %.2f",
            month, wh.flat.average, wh.flat.clear, wh.rack.average, wh.rack.clear, wh.wall.average, wh.wall.clear, sticks.sunlight))
    end
    local appliances = {}
    for name, watts in pairs(sticks.applianceW) do
        table.insert(appliances, string.format("%s %.0f", name, watts))
    end
    table.sort(appliances)
    print("RELootReport yardstick: appliance watts as a bank bills them: " .. table.concat(appliances, ", "))
    local function years(nights) return nights and string.format("%.1f", nights / 365) or "never" end
    local lives = {}
    for _, life in ipairs(sticks.batteryLife) do
        table.insert(lives, string.format("%s %s (%s)", life.fullType:match("[^.]+$"), years(life.half), years(life.quarter)))
    end
    print(string.format("RELootReport yardstick: years a new battery lasts to half capacity under a nightly load of half (a quarter) its new capacity, at Battery Wear %d%%: %s",
        sticks.batteryWear, table.concat(lives, ", ")))
    for i, town in ipairs(report.towns) do
        local newModules = modules.towns[i].total.condition / 100
        print(string.format("RELootReport power in %s: batteries store %.1f kWh; modules as found are %.1f new ones, banking %.1f kWh a day on south racks in July, %.1f in December",
            town.name, town.total.wh / 1000, newModules, newModules * sticks.moduleWh.july.rack.average / 1000,
            newModules * sticks.moduleWh.december.rack.average / 1000))
    end
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
    local census = require "RenewableEnergyDevTownCensus"
    reportBatteries(census, reportModules(census))
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
