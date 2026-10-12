-- Development only, not published; dev/run-debug-client.sh --test, --promo, --art and --loot load it.
-- It drives the vanilla debug tools the way you would by hand: the Renewable Energy debug
-- scenario starts from the main menu (with -debug and DebugScenario.ForceLaunch=true in
-- debug-options.ini). With --test, every renewable_energy_* test runs from Debug menu > Dev > Unit Tests >
-- Timed Actions, a screenshot goes to <cachedir>/Screenshots, and "RETest DONE passed=<n>
-- failed=<n>" goes to console.txt. With --promo, RenewableEnergyDevPromo saves the art for the README and
-- prints "REPromo DONE". With --art, RenewableEnergyDevArt saves close-ups of every item and tile and
-- prints "REArt DONE". With --loot, RenewableEnergy.Loot measures the loot and prints an "RELootReport"
-- line for each list, then the modules a thorough player finds in each town of
-- RenewableEnergyDevTownCensus (dev/loot/census.py), then "RELootReport DONE". Then the game quits.
-- run-debug-client.sh reads those lines from console.txt.

require "RenewableEnergy/Debug/RenewableEnergyDebugScenario"
require "RenewableEnergy/Debug/RenewableEnergyTests"
require "RenewableEnergy/Debug/RenewableEnergyTestsPower"
require "RenewableEnergy/Debug/RenewableEnergyTestsClient"
require "RenewableEnergy/Debug/RenewableEnergyTestsWorld"
require "RenewableEnergy/Debug/RenewableEnergyTestsLoot"
require "RenewableEnergy/Debug/RenewableEnergyTestsGadgets"
require "RenewableEnergy/Debug/RenewableEnergyLoot"
require "DebugUIs/DebugMenu/UnitTests/UnitTestsDebug"
local Promo = require "RenewableEnergyDevPromo"
local Art = require "RenewableEnergyDevArt"

-- Ticks after the scenario starts before a run begins, so the world around the character loads.
local SETTLE_TICKS = 180
-- Samples per list: enough to measure a 2% chance to within about ±0.3 percentage points (95%).
local LOOT_SAMPLES = 10000
local TEST_PREFIX = "renewable_energy_"

local scenario = debugScenarios.RenewableEnergyScenario
scenario.forceLaunch = true

-- Single player pauses when the window loses focus, and paused games don't tick, so the tests
-- would stop whenever someone switches to another window.
getCore():setOptionPauseOnFocusloss(false)

-- Name prefixes from TESTS (see run-debug-client.sh); empty runs every test of this mod.
local filters = {}

local function selected(name)
    if string.sub(name, 1, #TEST_PREFIX) ~= TEST_PREFIX then
        return false
    end
    if #filters == 0 then
        return true
    end
    for _, prefix in ipairs(filters) do
        if string.sub(name, 1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function testNames()
    local result = {}
    for name in pairs(TimedActionTests.getTests()) do
        if selected(name) then
            table.insert(result, name)
        end
    end
    table.sort(result)
    return result
end

-- Once every test in `names` has a result label, takes a screenshot of the results, prints the
-- counts and quits.
local function reportWhenDone(names)
    local success, fail = getText("IGUI_UnitTests_Success"), getText("IGUI_UnitTests_Fail")
    local function check()
        local passed, failed = 0, 0
        for _, name in ipairs(names) do
            local label = UnitTestsTimedActionsPanelTestResults[name].resultLabel.name
            if string.sub(label, 1, #success) == success then
                passed = passed + 1
            elseif string.sub(label, 1, #fail) == fail then
                failed = failed + 1
            else
                return
            end
        end
        Events.OnTick.Remove(check)
        local step = 0
        local function screenshot()
            step = step + 1
            if step == 10 then
                getCore():TakeFullScreenshot("renewable_energy_tests.png")
            elseif step == 20 then
                Events.OnTick.Remove(screenshot)
                print("RETest DONE passed=" .. passed .. " failed=" .. failed)
                getCore():quitToDesktop()
            end
        end
        Events.OnTick.Add(screenshot)
    end
    Events.OnTick.Add(check)
end

local function runTests()
    -- runOne fails on the panel's result labels unless the panel is open.
    UnitTestsDebug.OnOpenPanel()
    local names = testNames()
    print("RETest START " .. #names)
    for _, name in ipairs(names) do
        TimedActionTests.runOne(name)
    end
    reportWhenDone(names)
end

-- run-debug-client.sh writes the mode to <cachedir>/Lua/RenewableEnergyDevHarness.txt, and the
-- TESTS prefixes on the next line.
local function readMode()
    local reader = getFileReader("RenewableEnergyDevHarness.txt", false)
    if not reader then
        return "test"
    end
    local mode = reader:readLine()
    local tests = reader:readLine()
    reader:close()
    for prefix in string.gmatch(tests or "", "[^,%s]+") do
        table.insert(filters, prefix)
    end
    return mode
end

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
        print(string.format("RELootReport modules at site %s (%s): %s when placed", site.name, site.kind, hauled(site.haul)))
    end
    print(string.format("RELootReport modules: sites are placed at %.0f%%; arrow boards per map: %.1f from vehicle zones, %.1f at road works",
        report.siteChance * 100, report.arrowBoards.zones, report.arrowBoards.roadWorks))
end

local function reportLoot()
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
    print("RELootReport DONE")
    getCore():quitToDesktop()
end

local function quitWhenDone(mark)
    return function()
        print(mark .. " DONE")
        getCore():quitToDesktop()
    end
end

local RUNS = {
    test = runTests,
    loot = reportLoot,
    promo = function() Promo.capture(quitWhenDone("REPromo")) end,
    art = function() Art.capture(quitWhenDone("REArt")) end,
}

-- Runs `run` once the scenario has had SETTLE_TICKS ticks.
local function afterSettling(run)
    local ticks = 0
    local function onTick()
        ticks = ticks + 1
        if ticks >= SETTLE_TICKS then
            Events.OnTick.Remove(onTick)
            run()
        end
    end
    Events.OnTick.Add(onTick)
end

local originalOnStart = scenario.onStart
scenario.onStart = function()
    originalOnStart()
    afterSettling(RUNS[readMode()] or runTests)
end
