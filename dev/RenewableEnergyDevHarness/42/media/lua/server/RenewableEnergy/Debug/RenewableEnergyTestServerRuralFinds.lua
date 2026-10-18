-- The authority's half of the rural find tests (RenewableEnergy.RuralFinds): buildings are rolled
-- for finds only where the authority runs them. Only registers handlers, so a --stay rerun loads it
-- again (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler

local PAMPHLET = "RenewableEnergy.FemaPamphlet"

-- The building nearest the character within 60 squares, or nil. Any building does: the tests name
-- the finds to roll rather than relying on its rooms.
local function buildingNear(character)
    local x, y = math.floor(character:getX()), math.floor(character:getY())
    for r = 0, 60 do
        for sx, sy in PZHarness.Fixtures.ring(x, y, r) do
            local square = getSquare(sx, sy, 0)
            local building = square and square:getBuilding()
            if building then
                return building:getDef()
            end
        end
    end
    return nil
end

-- The containers of the building's lowest two levels (where RuralFinds leaves a pamphlet) and how
-- many pamphlets each holds.
local function pamphletsIn(def)
    local found = {}
    for z = 0, 1 do
        for x = def:getX(), def:getX2() - 1 do
            for y = def:getY(), def:getY2() - 1 do
                local square = getSquare(x, y, z)
                local objects = square and square:getObjects()
                for i = 0, (objects and objects:size() or 0) - 1 do
                    local container = objects:get(i):getContainer()
                    if container then
                        found[container] = container:getCountType(PAMPHLET)
                    end
                end
            end
        end
    end
    return found
end

local function pamphletTotal(def)
    local total = 0
    for _, count in pairs(pamphletsIn(def)) do
        total = total + count
    end
    return total
end

-- The building `def` with its roll forgotten, put back when the test ends along with anything the
-- test's rolls placed: the finds and the gasifier's pamphlet. With `pamphlet` the gasifier always
-- leaves one until then.
local function buildingToRoll(def, defer, pamphlet)
    local RuralFinds = RenewableEnergy.RuralFinds
    local store, key = ModData.getOrCreate(RuralFinds.MOD_DATA), RuralFinds.buildingKey(def)
    local roll = store[key]
    local pamphlets = pamphletsIn(def)
    local chance = RuralFinds.PAMPHLET_CHANCE
    if pamphlet then
        RuralFinds.PAMPHLET_CHANCE = 1
    end
    defer(function()
        RuralFinds.PAMPHLET_CHANCE = chance
        store[key] = roll
        for container in pairs(pamphletsIn(def)) do
            for _ = (pamphlets[container] or 0) + 1, container:getCountType(PAMPHLET) do
                local item = container:getFirstType(PAMPHLET)
                container:Remove(item)
                sendRemoveItemFromContainer(container, item)
            end
        end
    end)
    return def, function() store[key] = nil end
end

-- How far outside the building's bounds the square is, in squares (0 inside).
local function outside(def, x, y)
    local dx = math.max(def:getX() - x, x - (def:getX2() - 1), 0)
    local dy = math.max(def:getY() - y, y - (def:getY2() - 1), 0)
    return math.max(dx, dy)
end

-- Where each placed find stands; each is taken away when the test ends.
local function track(placed, defer, def)
    local positions = {}
    for kind, object in pairs(placed) do
        defer(function() Helpers.removeObject(object) end)
        local square = object:getSquare()
        local x, y = square:getX(), square:getY()
        positions[kind] = { x = x, y = y, z = square:getZ(), outdoors = square:isOutside() and square:getBuilding() == nil,
            out = def and outside(def, x, y) }
    end
    return positions
end

local function countKeys(entries)
    local n = 0
    for _ in pairs(entries) do
        n = n + 1
    end
    return n
end

-- The building near the character, its roll forgotten, is rolled for certain for the find
-- `args.kind`, then rolled again. Answers where the find stands, whether the roll was kept, how
-- many finds the second roll placed, and how many pamphlets the roll left in the building, the
-- gasifier's chance of one made certain.
handler("ruralFind", function(player, args, defer)
    local RuralFinds = RenewableEnergy.RuralFinds
    local near = buildingNear(player)
    if not near then
        return nil, "a building near the character on the server"
    end
    local def, forget = buildingToRoll(near, defer, true)
    local before = pamphletTotal(def)
    forget()
    local found = track(RuralFinds.roll(def, { args.kind }, true), defer, def)
    local pamphlets = pamphletTotal(def) - before
    local again = track(RuralFinds.roll(def, { args.kind }, true), defer, def)
    local rolled = RuralFinds.rolled(def)
    if not found[args.kind] then
        return nil, "a square for the " .. args.kind .. " by the building at " .. RuralFinds.buildingKey(def)
    end
    return { at = found[args.kind], kept = rolled ~= nil and rolled[args.kind] == true, again = countKeys(again),
        pamphlets = pamphlets }
end)

-- The building at x, y of the map, once its surroundings are loaded here, rolled the way the world
-- rolls it (its rooms pick the finds, the finds pick their squares) with its roll forgotten and
-- every chance made certain. Answers { ready = false } until loaded, then the finds its rooms
-- qualify it for, where each placed find stands and how many pamphlets it left. Everything is put
-- back before it answers, while the building is still loaded: the test moves on from it.
handler("ruralFindAt", function(_, args)
    local RuralFinds = RenewableEnergy.RuralFinds
    local square = getSquare(args.x, args.y, args.z or 0)
    local building = square and square:getBuilding()
    if not building then
        return { ready = false, why = square and "no building at the square" or "the square not loaded" }
    end
    local def = building:getDef()
    if not RuralFinds.surroundingsLoaded(def) then
        return { ready = false, why = "the squares around building " .. RuralFinds.buildingKey(def) .. " not loaded" }
    end
    local undo = {}
    local function defer(fn) table.insert(undo, fn) end
    local _, forget = buildingToRoll(def, defer, true)
    local before = pamphletTotal(def)
    forget()
    local found = track(RuralFinds.roll(def, nil, true), defer, def)
    local answer = { ready = true, qualifies = RuralFinds.findsFor(def), found = found, pamphlets = pamphletTotal(def) - before,
        reach = RuralFinds.REACH }
    for i = #undo, 1, -1 do
        undo[i]()
    end
    return answer
end)

-- The building near the character rolled `args.rolls` times for every find the way the world rolls
-- it, its roll forgotten before each. Answers each find's chance and how many the rolls placed.
handler("ruralFindsRolls", function(player, args, defer)
    local RuralFinds = RenewableEnergy.RuralFinds
    local near = buildingNear(player)
    if not near then
        return nil, "a building near the character on the server"
    end
    local def, forget = buildingToRoll(near, defer)
    local kinds, chances, placed = {}, {}, 0
    for kind in pairs(RuralFinds.FINDS) do
        table.insert(kinds, kind)
        chances[kind] = RuralFinds.chanceFor(kind)
    end
    for _ = 1, args.rolls do
        forget()
        placed = placed + countKeys(track(RuralFinds.roll(def, kinds, false), defer))
    end
    return { chances = chances, placed = placed }
end)

-- Empties the gasifier's filter at x, y, z, as a player taking out the spent packing would.
handler("ruralFindEmptyFilter", function(_, args)
    local _, object, missing = Helpers.recordAt({ kind = "gasifier", x = args.x, y = args.y, z = args.z })
    if not object then return nil, missing end
    local filter = RenewableEnergy.Gasifier.filterOf(object)
    local items = filter:getItems()
    for i = items:size() - 1, 0, -1 do
        local item = items:get(i)
        filter:Remove(item)
        sendRemoveItemFromContainer(filter, item)
    end
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
