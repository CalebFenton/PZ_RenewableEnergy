-- Development only, not published; dev/run-debug-client.sh --test, --promo, --art and --loot load it.
-- It drives the vanilla debug tools the way you would by hand: the Renewable Energy debug
-- scenario starts from the main menu (with -debug and DebugScenario.ForceLaunch=true in
-- debug-options.ini). With --test, every renewable_energy_* test runs from Debug menu > Dev > Unit Tests >
-- Timed Actions, a screenshot goes to <cachedir>/Screenshots, and "RETest DONE passed=<n>
-- failed=<n>" goes to console.txt. With --promo, RenewableEnergyDevPromo saves the art for the README and
-- prints "REPromo DONE". With --art, RenewableEnergyDevArt saves close-ups of every item and tile and
-- prints "REArt DONE". With --loot, RenewableEnergyLoot measures the loot and prints an "RELootReport"
-- line for each list, then "RELootReport DONE". Then the game quits.
require "RenewableEnergy/Debug/RenewableEnergyDebugScenario"
require "RenewableEnergy/Debug/RenewableEnergyTests"
require "RenewableEnergy/Debug/RenewableEnergyTestsPower"
require "RenewableEnergy/Debug/RenewableEnergyTestsClient"
require "RenewableEnergy/Debug/RenewableEnergyTestsWorld"
require "RenewableEnergy/Debug/RenewableEnergyTestsLoot"
require "RenewableEnergy/Debug/RenewableEnergyTestsGadgets"
require "RenewableEnergy/Debug/RenewableEnergyLoot"
require "DebugUIs/DebugMenu/UnitTests/UnitTestsDebug"
require "RenewableEnergyDevPromo"
require "RenewableEnergyDevArt"

local SETTLE_TICKS = 180
-- Samples per list: enough to measure a 2% chance to within about ±0.3 percentage points (95%).
local LOOT_SAMPLES = 10000

local scenario = debugScenarios.RenewableEnergyScenario
scenario.forceLaunch = true

-- Single player pauses when the window loses focus, and paused games don't tick, so the tests
-- would stop whenever someone switches to another window.
getCore():setOptionPauseOnFocusloss(false)

local names = {}
-- Name prefixes from TESTS (see run-debug-client.sh); empty runs every test of this mod.
local filters = {}

local function selected(name)
    if string.sub(name, 1, 17) ~= "renewable_energy_" then
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

local function reportWhenDone()
    local success, fail = getText("IGUI_UnitTests_Success"), getText("IGUI_UnitTests_Fail")
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
    Events.OnTick.Remove(reportWhenDone)
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

local ticks = 0
local function startTests()
    ticks = ticks + 1
    if ticks < SETTLE_TICKS then
        return
    end
    Events.OnTick.Remove(startTests)
    -- runOne fails on the panel's result labels unless the panel is open.
    UnitTestsDebug.OnOpenPanel()
    names = testNames()
    print("RETest START " .. #names)
    for _, name in ipairs(names) do
        TimedActionTests.runOne(name)
    end
    Events.OnTick.Add(reportWhenDone)
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

local function reportLoot()
    ticks = ticks + 1
    if ticks < SETTLE_TICKS then
        return
    end
    Events.OnTick.Remove(reportLoot)
    print("RELootReport START")
    local report = RenewableEnergyLoot.report(LOOT_SAMPLES)
    print(string.format("RELootReport settings: Other loot %.2f, Recipe Resources %.2f, loot rarity options 1, no zombie density bonus",
        report.settings.other, report.settings.recipeResource))
    for _, entry in ipairs(report) do
        local names = {}
        for fullType in pairs(entry.expected) do
            table.insert(names, fullType)
        end
        for fullType in pairs(entry.items) do
            if not entry.expected[fullType] then
                table.insert(names, fullType)
            end
        end
        table.sort(names)
        local parts = {}
        for _, fullType in ipairs(names) do
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
    print("RELootReport DONE")
    getCore():quitToDesktop()
end

local function capturePromo()
    ticks = ticks + 1
    if ticks < SETTLE_TICKS then
        return
    end
    Events.OnTick.Remove(capturePromo)
    RenewableEnergyDevPromo.capture(function()
        print("REPromo DONE")
        getCore():quitToDesktop()
    end)
end

local function captureArt()
    ticks = ticks + 1
    if ticks < SETTLE_TICKS then
        return
    end
    Events.OnTick.Remove(captureArt)
    RenewableEnergyDevArt.capture(function()
        print("REArt DONE")
        getCore():quitToDesktop()
    end)
end

local originalOnStart = scenario.onStart
scenario.onStart = function()
    originalOnStart()
    local mode = readMode()
    if mode == "loot" then
        Events.OnTick.Add(reportLoot)
    elseif mode == "promo" then
        Events.OnTick.Add(capturePromo)
    elseif mode == "art" then
        Events.OnTick.Add(captureArt)
    else
        Events.OnTick.Add(startTests)
    end
end
