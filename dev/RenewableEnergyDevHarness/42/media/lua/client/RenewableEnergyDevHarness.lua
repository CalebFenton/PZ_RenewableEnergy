-- Development only, not published; dev/run-debug-client.sh --test, --promo, --art and --loot load it.
-- It drives the vanilla debug tools the way you would by hand: the Renewable Energy debug
-- scenario starts from the main menu (with -debug and DebugScenario.ForceLaunch=true in
-- debug-options.ini). With --test, every renewable_energy_* test registered with the vanilla timed
-- action test runner runs (runTests) and "RETest DONE passed=<n> failed=<n>" goes to console.txt;
-- with --test --stay the game then stays open and reruns the tests on request (serveReruns). With
-- --promo, RenewableEnergyDevPromo saves the art for the README and prints "REPromo DONE". With
-- --art, RenewableEnergyDevArt saves close-ups of every item and tile and prints "REArt DONE". With
-- --loot, RenewableEnergy.Loot measures the loot and prints an "RELootReport" line for each list,
-- then the modules a thorough player finds in each town of RenewableEnergyDevTownCensus
-- (dev/loot/census.py), then "RELootReport DONE". Then the game quits. run-debug-client.sh reads
-- those lines from console.txt.

require "RenewableEnergy/Debug/RenewableEnergyDebugScenario"
require "RenewableEnergy/Debug/RenewableEnergyLoot"
require "ISUI/ISUIElement"
local Promo = require "RenewableEnergyDevPromo"
local Art = require "RenewableEnergyDevArt"

-- A run starts once one square in every chunk this many squares around the character has loaded,
-- or after SETTLE_MAX_TICKS ticks.
local LOADED_RADIUS = 40
local SETTLE_MAX_TICKS = 600
-- How long a test waits for the character's square to load after the last test took it far away.
local SQUARE_WAIT_MS = 10000
-- Samples per list: enough to measure a 2% chance to within about ±0.3 percentage points (95%).
local LOOT_SAMPLES = 10000
local TEST_PREFIX = "renewable_energy_"
-- With --stay, run-debug-client.sh writes this file in <cachedir>/Lua to rerun the tests; the game
-- looks for it every REQUEST_POLL_TICKS ticks and quits after STAY_IDLE_MS without one.
local REQUEST_FILE = "RenewableEnergyDevRerun.txt"
local REQUEST_POLL_TICKS = 15
local STAY_IDLE_MS = 10 * 60 * 1000
-- While --stay waits, the game draws only this many frames a second, so it doesn't keep a core busy.
local IDLE_FPS = 24

local scenario = debugScenarios.RenewableEnergyScenario
scenario.forceLaunch = true

-- Single player pauses when the window loses focus, and paused games don't tick, so the tests
-- would stop whenever someone switches to another window.
getCore():setOptionPauseOnFocusloss(false)

-- Name prefixes from TESTS (see run-debug-client.sh); empty runs every test of this mod.
local filters = {}

local function startsWith(text, prefix)
    return string.sub(text, 1, #prefix) == prefix
end

local function setFilters(tests)
    filters = {}
    for prefix in string.gmatch(tests or "", "[^,%s]+") do
        table.insert(filters, prefix)
    end
end

local function selected(name)
    if not startsWith(name, TEST_PREFIX) then
        return false
    end
    if #filters == 0 then
        return true
    end
    for _, prefix in ipairs(filters) do
        if startsWith(name, prefix) then
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

-- Runs the selected tests one after another with the resets of the debug menu's runner (RunTest
-- and OnTick in vanilla Tests/TimedActionsTests.lua, whose locals Lua can't reach): before each
-- test full health, an empty inventory, nothing worn or held, ISBuildMenu.cheat off and the test's
-- name said aloud; validate() once the action queue is empty; then the cheat back and the
-- character back on the square the test started on. Vanilla pauses a second after every test so
-- you can read the result; here the next test starts on the next tick, or once the character's
-- square has loaded again after a test that went far (at most SQUARE_WAIT_MS). Calls onDone() at
-- the end.
local function runTests(onDone)
    local names = testNames()
    local tests = TimedActionTests.getTests()
    print("RETest START " .. #names)
    local passed, failed, index, ticks = 0, 0, 0, 0
    local startedMs = getTimestampMs()
    local doneMs = startedMs
    local current, player, square, wasCheat
    local function onTick()
        ticks = ticks + 1
        if current then
            if ISTimedActionQueue.getTimedActionQueue(player).queue[1] then
                return
            end
            if not current.validate or current:validate() then
                passed = passed + 1
            else
                failed = failed + 1
            end
            current = nil
            doneMs = getTimestampMs()
            ISBuildMenu.cheat = wasCheat
            if square and player:getCurrentSquare() ~= square then
                player:teleportTo(square:getX() + 0.5, square:getY() + 0.5, square:getZ())
                player:setCurrent(square)
            end
            return
        end
        player = getSpecificPlayer(0)
        if not player:getCurrentSquare() and getTimestampMs() - doneMs < SQUARE_WAIT_MS then
            return
        end
        index = index + 1
        local name = names[index]
        if not name then
            Events.OnTick.Remove(onTick)
            local seconds = (getTimestampMs() - startedMs) / 1000
            print(string.format("RETest TIME %.1f s, %d frames (%.0f a second)", seconds, ticks, ticks / math.max(seconds, 0.001)))
            print("RETest DONE passed=" .. passed .. " failed=" .. failed)
            onDone()
            return
        end
        current = tests[name]
        print("TEST: " .. name)
        square = player:getCurrentSquare()
        player:getBodyDamage():RestoreToFullHealth()
        player:getInventory():removeAllItems()
        player:clearWornItems()
        player:setPrimaryHandItem(nil)
        player:setSecondaryHandItem(nil)
        player:Say(name)
        wasCheat = ISBuildMenu.cheat
        ISBuildMenu.cheat = false
        current:run()
    end
    Events.OnTick.Add(onTick)
end

-- The request run-debug-client.sh writes to REQUEST_FILE: an id, the TESTS prefixes, then the Lua
-- files to run again, the test library first. Nil if there is none.
local function readRequest()
    local reader = getFileReader(REQUEST_FILE, false)
    if not reader then
        return nil
    end
    local request = { id = reader:readLine(), tests = reader:readLine(), files = {} }
    local line = reader:readLine()
    while line do
        table.insert(request.files, line)
        line = reader:readLine()
    end
    reader:close()
    return request
end

-- What the kept game shows on screen and prints while it waits for a request, so whoever watches
-- the window can tell an idle game from a stuck one.
local IDLE_TEXT = "RETest IDLE waiting for the next --test --stay run (quits after " .. STAY_IDLE_MS / 60000 .. " minutes)"

local IdleNote = ISUIElement:derive("RenewableEnergyDevIdleNote")

function IdleNote:render()
    self:drawText(IDLE_TEXT, 0, 0, 1, 1, 0.4, 1, UIFont.Large)
end

-- Runs the tests again for every new request until STAY_IDLE_MS pass without one. reloadLuaFile
-- runs a file again but ignores its Events.*.Add calls (LuaCompiler.rewriteEvents), which suits
-- the test files: they only register tests. Every test of this mod is unregistered first, so a
-- test that was renamed or deleted doesn't run again.
local function serveReruns()
    local performance = getPerformance()
    local fps, uncapped = performance:getFramerate(), performance:isFramerateUncapped()
    local note = IdleNote:new(40, 40, getCore():getScreenWidth() - 80, 40)
    note:initialise()
    local handled
    local waitingSince, ticks = getTimestampMs(), 0
    local onTick
    local function idle()
        performance:setFramerateUncapped(false)
        performance:setFramerate(IDLE_FPS)
        print(IDLE_TEXT)
        note:addToUIManager()
        waitingSince = getTimestampMs()
        Events.OnTick.Add(onTick)
    end
    onTick = function()
        ticks = ticks + 1
        if ticks % REQUEST_POLL_TICKS ~= 0 then
            return
        end
        if getTimestampMs() - waitingSince > STAY_IDLE_MS then
            Events.OnTick.Remove(onTick)
            print("RETest STAY ends: no request for " .. STAY_IDLE_MS / 60000 .. " minutes")
            getCore():quitToDesktop()
            return
        end
        local request = readRequest()
        if not request or not request.id or request.id == handled then
            return
        end
        handled = request.id
        Events.OnTick.Remove(onTick)
        note:removeFromUIManager()
        performance:setFramerate(fps)
        performance:setFramerateUncapped(uncapped)
        print("RETest RUN " .. request.id)
        local tests = TimedActionTests.getTests()
        local registered = {}
        for name in pairs(tests) do
            if startsWith(name, TEST_PREFIX) then
                table.insert(registered, name)
            end
        end
        for _, name in ipairs(registered) do
            tests[name] = nil
        end
        for _, file in ipairs(request.files) do
            reloadLuaFile(file)
        end
        setFilters(request.tests)
        runTests(idle)
    end
    idle()
end

-- run-debug-client.sh writes the mode to <cachedir>/Lua/RenewableEnergyDevHarness.txt, the TESTS
-- prefixes on the next line and "stay" on the third for --stay.
local function readMode()
    local reader = getFileReader("RenewableEnergyDevHarness.txt", false)
    if not reader then
        return "test", false
    end
    local mode = reader:readLine()
    setFilters(reader:readLine())
    local stay = reader:readLine() == "stay"
    reader:close()
    return mode, stay
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

local function quit()
    getCore():quitToDesktop()
end

-- `stay` is true for --test --stay.
local RUNS = {
    test = function(stay) runTests(stay and serveReruns or quit) end,
    loot = reportLoot,
    promo = function() Promo.capture(quitWhenDone("REPromo")) end,
    art = function() Art.capture(quitWhenDone("REArt")) end,
}

local function worldLoaded()
    local square = getSpecificPlayer(0):getCurrentSquare()
    if not square then
        return false
    end
    local cell, x, y = getCell(), square:getX(), square:getY()
    for dx = -LOADED_RADIUS, LOADED_RADIUS, 8 do
        for dy = -LOADED_RADIUS, LOADED_RADIUS, 8 do
            if not cell:getGridSquare(x + dx, y + dy, 0) then
                return false
            end
        end
    end
    return true
end

-- Runs `run` once the world around the character has loaded.
local function afterSettling(run)
    local ticks = 0
    local function onTick()
        ticks = ticks + 1
        if worldLoaded() or ticks >= SETTLE_MAX_TICKS then
            Events.OnTick.Remove(onTick)
            print("Dev Harness: starting after " .. ticks .. " ticks")
            run()
        end
    end
    Events.OnTick.Add(onTick)
end

local mode, stay = readMode()
-- Game time per second doesn't depend on the frame rate (FPSTracking), so more frames a second only
-- shorten what is counted in ticks: the tests' waits for the game to apply a change, and from here
-- on the world loading. Measured on an M3 Max, uncapped draws about 260 frames a second against 60.
-- The option can't do it: Core.loadOptions resets uncappedFPS to false and frameRate to 60. --art
-- and --promo keep 60, because their captures wait fixed tick counts for walking and lighting.
if mode == "test" then
    getPerformance():setFramerateUncapped(true)
end

local originalOnStart = scenario.onStart
scenario.onStart = function()
    originalOnStart()
    local run = RUNS[mode] or RUNS.test
    afterSettling(function() run(stay) end)
end
