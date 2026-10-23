-- The authority's half of the rural find tests (RenewableEnergy.RuralFinds): buildings are rolled
-- for finds only where the authority runs them. Only registers handlers, so a --stay rerun loads it
-- again (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler

local PAMPHLET = "RenewableEnergy.FemaPamphlet"

-- Forgets the building's rural find roll so that it can be rolled again, and when the test ends
-- puts the roll back and takes out the pamphlets the test's rolls left (the gasifier's).
local function forgetRoll(def, defer)
    local store, key = ModData.getOrCreate(RenewableEnergy.RuralFinds.MOD_DATA), RenewableEnergy.BuildingWatch.key(def)
    local roll = store[key]
    local pamphlets = Helpers.pamphletsIn(def)
    defer(function()
        store[key] = roll
        for container, count in pairs(Helpers.pamphletsIn(def)) do
            Helpers.emptyContainer(container, PAMPHLET, count - (pamphlets[container] or 0))
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

-- The finds of each kind standing within BuildingWatch.REACH of the building, by kind.
local function findsAround(def)
    local reach, counts = RenewableEnergy.BuildingWatch.REACH, {}
    for kind, find in pairs(RenewableEnergy.RuralFinds.FINDS) do
        counts[kind] = 0
        for x = def:getX() - reach, def:getX2() + reach - 1 do
            for y = def:getY() - reach, def:getY2() + reach - 1 do
                if RenewableEnergy.findObjectOn(getSquare(x, y, 0), find.is) then
                    counts[kind] = counts[kind] + 1
                end
            end
        end
    end
    return counts
end

-- The building at x, y of the map: { ready = false, why } until the world has rolled it, which it
-- does once the building's surroundings have loaded here. Then the finds the world's roll gave it
-- and those standing by it, and, rolled again with its roll forgotten and every roll at 0 (the
-- world rolled it, so Solar Sites is above 0 and every chance hits), so that every find it
-- qualifies for gets a square, the finds its rooms qualify it for, where each placed find stands
-- and how many pamphlets it left. Everything that second roll did is put back before it answers,
-- while the building is still loaded: the test moves on from it.
handler("ruralFindAt", function(_, args)
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
    local standing = findsAround(def)
    local undo = {}
    local function defer(fn) table.insert(undo, fn) end
    forgetRoll(def, defer)
    local before = Helpers.pamphletTotal(def)
    local restoreRoll = Helpers.forceRolls(defer, 0)
    local found = track(RuralFinds.roll(def), defer, def)
    restoreRoll()
    local answer = { ready = true, world = world, standing = standing, qualifies = RuralFinds.findsFor(def), found = found,
        pamphlets = Helpers.pamphletTotal(def) - before, reach = RenewableEnergy.BuildingWatch.REACH }
    for i = #undo, 1, -1 do
        undo[i]()
    end
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

-- Vanilla's barn and survivalist camp story clutter lists hold the mod's additions.
Helpers.check("ruralClutter", function(expect)
    local base = getWorld():getRandomizedWorldBase()
    for getter, items in pairs(RenewableEnergy.RuralFinds.CLUTTER) do
        local list = base[getter](base)
        for _, item in ipairs(items) do
            expect(list:contains(item), getter .. " lacks " .. item)
        end
    end
end)
