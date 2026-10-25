-- The authority's half of the rural find tests (RenewableEnergy.RuralFinds): buildings are rolled
-- for finds only where the authority runs them. Only registers handlers, so a --stay rerun loads it
-- again (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/ServerChecks"
require "PZHarness/Fixtures"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler

-- Forgets the building's rural find roll so that it can be rolled again, and when the test ends
-- puts the roll back and takes out the reading the test's rolls left (the gasifier's pamphlet,
-- the digester's magazine).
local function forgetRoll(def, defer)
    local RuralFinds, before = RenewableEnergy.RuralFinds, {}
    local store, key = Helpers.keepBuildingRoll(RuralFinds.MOD_DATA, def, defer)
    for _, fullType in ipairs({ RuralFinds.PAMPHLET, RuralFinds.BIOGAS_MAGAZINE }) do
        before[fullType] = Helpers.readingIn(def, fullType)
    end
    defer(function()
        for fullType, held in pairs(before) do
            Helpers.takeReadingSince(def, fullType, held)
        end
    end)
    store[key] = nil
end

-- Where each placed find stands, and with `def` how far out from it; each is taken away when the
-- test ends.
local function track(placed, defer, def)
    local positions = {}
    for kind, object in pairs(placed) do
        defer(function() PZHarness.Fixtures.removePlaced(object) end)
        local square = object:getSquare()
        local x, y = square:getX(), square:getY()
        positions[kind] = { x = x, y = y, z = square:getZ(), outdoors = square:isOutside() and square:getBuilding() == nil,
            out = def and RenewableEnergy.RuralFinds.distanceOutside(def, x, y) }
    end
    return positions
end

-- The building near the character, its roll forgotten, is rolled for the find `args.kind` with
-- every roll at 0, which hits at any Solar Sites above 0, then rolled again. Answers where the find
-- stands, whether the roll was kept and how many finds the second roll placed.
handler("ruralFind", function(player, args, defer)
    local RuralFinds = RenewableEnergy.RuralFinds
    local def = Helpers.buildingNear(math.floor(player:getX()), math.floor(player:getY()), 60)
    if not def then
        return nil, "a building near the character on the server"
    end
    forgetRoll(def, defer)
    local restoreRoll = Helpers.forceRolls(defer, 0)
    local found = track(RuralFinds.roll(def, { args.kind }), defer, def)
    local again = track(RuralFinds.roll(def, { args.kind }), defer, def)
    restoreRoll()
    local rolled = RuralFinds.rolled(def)
    if not found[args.kind] then
        return nil, "a square for the " .. args.kind .. " by the building at " .. RenewableEnergy.BuildingWatch.key(def)
    end
    return { at = found[args.kind], kept = rolled ~= nil and rolled[args.kind] == true, again = Helpers.count(again) }
end)

-- The building at x, y of the map: { ready = false, why } until the world has rolled it, which it
-- does once the building's surroundings have loaded here. Then the finds the world's roll gave it
-- and those standing by it, and, rolled again with its roll forgotten and every roll at 0 (the
-- world rolled it, so Solar Sites is above 0 and every chance hits), so that every find it
-- qualifies for gets a square, the finds its rooms qualify it for, where each placed find stands,
-- how far out each kind may stand, and how many pamphlets and biogas magazines it left.
-- Everything that second roll did is put back before it answers, while the building is still
-- loaded: the test moves on from it.
handler("ruralFindAt", function(_, args, testDefer)
    local RuralFinds = RenewableEnergy.RuralFinds
    local square = getSquare(args.x, args.y, args.z or 0)
    local building = square and square:getBuilding()
    if not building then
        return { ready = false, why = square and "no building at the square" or "the square not loaded" }
    end
    local def = building:getDef()
    local worldRoll = RuralFinds.rolled(def)
    if not worldRoll then
        return { ready = false, why = "the world never rolled the building at " .. RenewableEnergy.BuildingWatch.key(def) }
    end
    local world = {}
    for kind in pairs(worldRoll) do
        table.insert(world, kind)
    end
    local standing, reach = {}, {}
    for kind, find in pairs(RuralFinds.FINDS) do
        standing[kind], reach[kind] = Helpers.findsAround(def, find.is), find.reach
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
    local restoreRoll = Helpers.forceRolls(defer, 0)
    local found = track(RuralFinds.roll(def), defer, def)
    restoreRoll()
    local answer = { ready = true, world = world, standing = standing, qualifies = RuralFinds.findsFor(def), found = found,
        pamphlets = Helpers.readingTotal(def, RuralFinds.PAMPHLET) - pamphlets,
        magazines = Helpers.readingTotal(def, RuralFinds.BIOGAS_MAGAZINE) - magazines,
        reach = reach }
    undoNow()
    return answer
end)

-- The building near the character, its roll forgotten, rolled once for every find the way the
-- world rolls it, every roll set to `args.roll`. Answers each find's chance and how many the roll
-- placed.
handler("ruralFindsRoll", function(player, args, defer)
    local RuralFinds = RenewableEnergy.RuralFinds
    local def = Helpers.buildingNear(math.floor(player:getX()), math.floor(player:getY()), 60)
    if not def then
        return nil, "a building near the character on the server"
    end
    forgetRoll(def, defer)
    local kinds, chances = {}, {}
    for kind in pairs(RuralFinds.FINDS) do
        table.insert(kinds, kind)
        chances[kind] = RuralFinds.chanceFor(kind)
    end
    local restoreRoll = Helpers.forceRolls(defer, args.roll)
    local placed = Helpers.count(track(RuralFinds.roll(def, kinds), defer))
    restoreRoll()
    return { chances = chances, placed = placed }
end)

-- Empties the gasifier's filter at x, y, z, as a player taking out the spent packing would.
handler("ruralFindEmptyFilter", function(_, args)
    local _, object, missing = Helpers.recordAt({ kind = "gasifier", x = args.x, y = args.y, z = args.z })
    if not object then return nil, missing end
    Helpers.emptyContainer(RenewableEnergy.Gasifier.filterOf(object))
    return {}
end)

-- Vanilla's barn, farm storeroom and survivalist camp story clutter lists hold the mod's additions,
-- each as many times as vanilla's adder puts an item in for every time RuralFinds.CLUTTER lists it.
PZHarness.checkHandler("ruralClutter", function(expect)
    local RuralFinds = RenewableEnergy.RuralFinds
    local base = getWorld():getRandomizedWorldBase()
    for getter, items in pairs(RuralFinds.CLUTTER) do
        local list = base[getter](base)
        for item, count in pairs(RuralFinds.wanted(items)) do
            local once = ArrayList.new()
            StoryTables.addItemToClutterTable(once, item)
            local held = RuralFinds.countIn(list, item)
            expect(held == count * once:size(), getter .. " holds " .. item .. " " .. held .. " times, not "
                .. count .. " × " .. once:size())
        end
    end
end)
