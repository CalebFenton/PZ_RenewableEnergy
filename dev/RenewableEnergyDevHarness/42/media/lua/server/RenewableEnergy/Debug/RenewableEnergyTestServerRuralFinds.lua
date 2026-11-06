-- The authority's half of the rural find tests (RenewableEnergy.RuralFinds): buildings are rolled
-- for finds only where the authority runs them.

require "PZHarness/ServerHandlers"
require "PZHarness/ServerChecks"
require "PZHarness/Fixtures"
require "PZHarness/Rolls"
require "PZHarness/ServerRecords"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"
local Kinds = require "RenewableEnergy/Debug/RenewableEnergyTestKinds"
local BuildingWatch = require "RenewableEnergy/World/BuildingWatch"
local RuralFinds = require "RenewableEnergy/World/RuralFinds"

local handler, need, saveOptions = PZHarness.serverHandler, PZHarness.need, PZHarness.Fixtures.saveOptions

-- Forgets the building's rural find roll so that it can be rolled again, and when the test ends
-- puts the roll back and takes out the reading the test's rolls left (the gasifier's pamphlet,
-- the digester's magazine).
local function forgetRoll(def, defer)
    local before = {}
    for _, fullType in ipairs({ RuralFinds.PAMPHLET, RuralFinds.BIOGAS_MAGAZINE }) do
        before[fullType] = Helpers.readingIn(def, fullType)
    end
    defer(function()
        for fullType, held in pairs(before) do
            Helpers.takeReadingSince(def, fullType, held)
        end
    end)
    Helpers.forgetBuildingRoll(RuralFinds.MOD_DATA, def, defer)
end

-- How far outside the building's bounds the square at x, y is, in squares (0 inside).
local function distanceOutside(def, x, y)
    return math.max(def:getX() - x, x - (def:getX2() - 1), def:getY() - y, y - (def:getY2() - 1), 0)
end

-- Where each placed find stands and how far out from the building `def`; each is taken away when
-- the test ends.
local function track(placed, defer, def)
    local positions = {}
    for kind, object in pairs(placed) do
        defer(function() PZHarness.Fixtures.removePlaced(object) end)
        local square = object:getSquare()
        local x, y = square:getX(), square:getY()
        positions[kind] = { x = x, y = y, z = square:getZ(), outdoors = square:isOutside() and square:getBuilding() == nil,
            out = distanceOutside(def, x, y) }
    end
    return positions
end

-- The building at x, y of the map: { ready = false, why } until the world has rolled it, which it
-- does once the building's surroundings have loaded here. Then the finds the world's roll gave it
-- and those standing by it, and, rolled again with its roll forgotten and every roll at 0 (the
-- world rolled it, so Solar Sites is above 0 and every chance hits), so that every find it
-- qualifies for gets a square, the finds its rooms qualify it for, where each placed find stands,
-- how far out each kind may stand, and how many pamphlets and biogas magazines it left.
-- Everything that second roll did is put back before it answers, while the building is still
-- loaded: the test moves on from it.
handler("ruralFindAt", function(_, args, testDefer)
    local square = getSquare(args.x, args.y, args.z or 0)
    local building = square and square:getBuilding()
    if not building then
        return { ready = false, why = square and "no building at the square" or "the square not loaded" }
    end
    local def = building:getDef()
    local worldRoll = Helpers.buildingRoll(RuralFinds.MOD_DATA, def)
    if not worldRoll then
        return { ready = false, why = "the world never rolled the building at " .. BuildingWatch.key(def) }
    end
    local world = {}
    for kind in pairs(worldRoll) do
        table.insert(world, kind)
    end
    local standing, reach = {}, {}
    for kind, find in pairs(RuralFinds.FINDS) do
        standing[kind], reach[kind] = Helpers.findsAround(def, kind), find.reach
    end
    local undo = {}
    local function defer(fn) table.insert(undo, fn) end
    local undoNow = PZHarness.Fixtures.deferOnce(testDefer, function()
        for i = #undo, 1, -1 do
            undo[i]()
        end
    end)
    forgetRoll(def, defer)
    local pamphlets = Helpers.readingTotal(def, RuralFinds.PAMPHLET)
    local magazines = Helpers.readingTotal(def, RuralFinds.BIOGAS_MAGAZINE)
    local found = track(PZHarness.Rolls.with(defer, 0, RuralFinds.roll, def), defer, def)
    local answer = { ready = true, world = world, standing = standing, qualifies = RuralFinds.findsFor(def), found = found,
        pamphlets = Helpers.readingTotal(def, RuralFinds.PAMPHLET) - pamphlets,
        magazines = Helpers.readingTotal(def, RuralFinds.BIOGAS_MAGAZINE) - magazines,
        reach = reach }
    undoNow()
    return answer
end)

-- The building near the character on the server.
local function buildingNear(player)
    return need(PZHarness.Fixtures.buildingNear(math.floor(player:getX()), math.floor(player:getY()), 60),
        "a building near the character on the server")
end

-- The building near the character, its roll forgotten, is rolled for the finds `args.kinds` the
-- way the world rolls it, then again, every roll at 0, which hits any chance above 0. Answers
-- where each find the first roll placed stands, which finds the roll kept, and how many finds the
-- second roll placed.
handler("ruralFindsRoll", function(player, args, defer)
    local def = buildingNear(player)
    forgetRoll(def, defer)
    local found, again = PZHarness.Rolls.with(defer, 0, function()
        return track(RuralFinds.roll(def, args.kinds), defer, def), track(RuralFinds.roll(def, args.kinds), defer, def)
    end)
    return { found = found, kept = Helpers.buildingRoll(RuralFinds.MOD_DATA, def), again = Kinds.count(again) }
end)

-- The Solar Sites value at which a find's chance is 1 in its `odds` (the option's default).
local SITES_AT_ODDS = 75

-- For each of `args.trials` ({ kind, option, roll }), the building near the character, its roll
-- forgotten, rolled for the one find `kind` with Solar Sites at `option` and every roll at `roll`:
-- a number, or "under" or "at" option / SITES_AT_ODDS / the find's odds, worked out here rather
-- than by the mod's chanceFor. Answers how many finds each trial placed, each taken away before
-- the next.
handler("ruralFindsEdges", function(player, args, defer)
    local def = buildingNear(player)
    local restoreOptions = saveOptions(defer, { "SolarSites" })
    local placed = {}
    for i, trial in ipairs(args.trials) do
        forgetRoll(def, defer)
        SandboxVars.RenewableEnergy.SolarSites = trial.option
        local edge = trial.option / SITES_AT_ODDS / RuralFinds.FINDS[trial.kind].odds
        local found = PZHarness.Rolls.with(defer, PZHarness.Rolls.trialRoll(trial.roll, edge), RuralFinds.roll, def, { trial.kind })
        placed[i] = Kinds.count(found)
        for _, object in pairs(found) do
            PZHarness.Fixtures.removePlaced(object)
        end
    end
    restoreOptions()
    return { placed = placed }
end)

-- How many times the Java list holds `item`.
local function countIn(list, item)
    local count = 0
    for i = 0, list:size() - 1 do
        if list:get(i) == item then
            count = count + 1
        end
    end
    return count
end

-- Vanilla's barn, farm storeroom and survivalist camp story clutter lists hold the mod's additions,
-- each as many times as vanilla's adder puts an item in for every time RuralFinds.CLUTTER lists it.
PZHarness.checkHandler("ruralClutter", function(_, _, expectEqual)
    local base = getWorld():getRandomizedWorldBase()
    for getter, items in pairs(RuralFinds.CLUTTER) do
        local list = base[getter](base)
        local listed = {}
        for _, item in ipairs(items) do
            listed[item] = (listed[item] or 0) + 1
        end
        for item, count in pairs(listed) do
            local once = ArrayList.new()
            StoryTables.addItemToClutterTable(once, item)
            local held = countIn(list, item)
            expectEqual("the times " .. getter .. " holds " .. item, held, count * once:size())
        end
    end
end)
