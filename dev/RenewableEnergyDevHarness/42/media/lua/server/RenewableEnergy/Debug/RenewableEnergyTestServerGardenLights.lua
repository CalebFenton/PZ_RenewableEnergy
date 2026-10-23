-- The authority's half of the garden light tests: houses are rolled for lights only where the
-- authority runs them. Only registers handlers, so a --stay rerun loads it again (RELOAD_FILES);
-- RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler
local removePlaced = PZHarness.Fixtures.removePlaced

-- Squares out from a house's bounds searched for its lights: the end of a path from a door, the
-- farthest out a light may stand.
local LIGHT_MARGIN = 5

-- The house nearest the square within `radius`, or nil.
local function houseNear(x, y, radius)
    for r = 0, radius do
        for sx, sy in PZHarness.Fixtures.ring(x, y, r) do
            local square = getSquare(sx, sy, 0)
            local building = square and square:getBuilding()
            if building and building:getDef():isResidential() then
                return building:getDef()
            end
        end
    end
    return nil
end

-- The garden lights around a house, by square key.
local function lightsAround(def)
    local found = {}
    local SolarGardenLight = RenewableEnergy.SolarGardenLight
    for x = def:getX() - LIGHT_MARGIN, def:getX2() + LIGHT_MARGIN do
        for y = def:getY() - LIGHT_MARGIN, def:getY2() + LIGHT_MARGIN do
            local light = SolarGardenLight.findOn(getSquare(x, y, 0))
            if light then
                found[x .. "," .. y] = light
            end
        end
    end
    return found
end

-- Forgets the house's garden light roll until the test ends, so that it can be rolled or promised
-- lights again.
local function forgetRoll(def, defer)
    local store, key = ModData.getOrCreate(RenewableEnergy.GardenLights.MOD_DATA), RenewableEnergy.BuildingWatch.key(def)
    local roll = store[key]
    defer(function() store[key] = roll end)
    store[key] = nil
end

-- The house near the character, with its roll forgotten (its chunk loading rolled it), and its
-- lights as they stood before. Nil without a house.
local function houseToRoll(player, defer)
    local def = houseNear(math.floor(player:getX()), math.floor(player:getY()), 60)
    if not def then
        return nil
    end
    forgetRoll(def, defer)
    return def, lightsAround(def)
end

-- The lights around the house that `before` didn't have: their squares, whether each stands
-- outdoors on the ground, and their charge. They are removed when the test ends.
local function newLights(def, before, defer)
    local lights = {}
    for squareKey, light in pairs(lightsAround(def)) do
        if not before[squareKey] then
            defer(function() removePlaced(light) end)
            local square = light:getSquare()
            table.insert(lights, {
                x = square:getX(), y = square:getY(), z = square:getZ(),
                outdoors = square:isOutside() and square:getRoom() == nil and square:getZ() == 0,
                charge = RenewableEnergy.SolarGardenLight.getCharge(light),
            })
        end
    end
    return lights
end

-- The house near the character, its roll forgotten and promised lights as a solar site promises
-- them, is rolled for garden lights twice. Answers how many lights each roll gave, whether the
-- roll was kept, and the new lights.
handler("gardenLightsOnce", function(player, _, defer)
    local GardenLights = RenewableEnergy.GardenLights
    local def, before = houseToRoll(player, defer)
    if not def then
        return nil, "a house near the character on the server"
    end
    GardenLights.promise(def)
    local first = GardenLights.roll(def)
    local rolled = GardenLights.isRolled(def)
    local second = GardenLights.roll(def)
    return { first = first, rolled = rolled, second = second, lights = newLights(def, before, defer),
        count = GardenLights.COUNT, wh = RenewableEnergy.Specs.gardenLight.wh }
end)

-- At the square at `args`: whether it is loaded, the house nearest it within `args.radius`, whether
-- that house was rolled for garden lights, and the neighbourhood.
handler("gardenLightsAt", function(_, args)
    local GardenLights = RenewableEnergy.GardenLights
    local loaded = getSquare(args.x, args.y, 0) ~= nil
    local def = loaded and houseNear(args.x, args.y, args.radius)
    return {
        loaded = loaded,
        house = def and RenewableEnergy.BuildingWatch.key(def) or nil,
        rolled = def and GardenLights.isRolled(def) or false,
        neighbourhood = GardenLights.neighbourhood(args.x, args.y),
    }
end)

-- The building of the map at x, y, loaded or not.
local function buildingAt(args)
    return getWorld():getMetaGrid():getBuildingAt(args.x, args.y)
end

-- The house at x, y of the map, its roll forgotten until the test ends, so that a solar site can
-- promise it lights. Answers its bounds, x2 and y2 past its last squares, and how far around it
-- must load before it is rolled.
handler("gardenLightsForgetHouse", function(_, args, defer)
    local def = buildingAt(args)
    if not def then
        return nil, "a building at " .. args.x .. "," .. args.y
    end
    forgetRoll(def, defer)
    return { x = def:getX(), y = def:getY(), x2 = def:getX2(), y2 = def:getY2(), reach = RenewableEnergy.BuildingWatch.REACH }
end)

-- The house at x, y of the map: whether its square there is loaded here and every chunk around it
-- that it waits for, whether its garden light roll holds a solar site's promise or a roll, how
-- many lights its roll placed, and how many stand around it.
handler("gardenLightsHouse", function(_, args)
    local GardenLights = RenewableEnergy.GardenLights
    local def = buildingAt(args)
    if not def then
        return nil, "a building at " .. args.x .. "," .. args.y
    end
    local roll = ModData.getOrCreate(GardenLights.MOD_DATA)[RenewableEnergy.BuildingWatch.key(def)]
    local rolled = GardenLights.isRolled(def)
    return {
        loaded = getSquare(args.x, args.y, 0) ~= nil, surroundings = RenewableEnergy.BuildingWatch.surroundingsLoaded(def),
        promised = roll == GardenLights.PROMISED, rolled = rolled, lights = Helpers.count(lightsAround(def)),
        placed = rolled and roll or 0,
        count = GardenLights.COUNT,
    }
end)

-- Takes away the garden lights around the house at x, y of the map, while it is loaded: the test
-- moves on.
handler("gardenLightsClearHouse", function(_, args)
    local def = buildingAt(args)
    if not def then
        return nil, "a building at " .. args.x .. "," .. args.y
    end
    for _, light in pairs(lightsAround(def)) do
        removePlaced(light)
    end
    return {}
end)

-- The house near the character, its roll forgotten, rolled once the way the world rolls it at the
-- save's options, the roll set to `args.roll`. Answers its chance, how many lights the roll gave,
-- whether the roll was kept, and the new lights around it.
handler("gardenLightsRoll", function(player, args, defer)
    local GardenLights = RenewableEnergy.GardenLights
    local def, before = houseToRoll(player, defer)
    if not def then
        return nil, "a house near the character on the server"
    end
    local restoreRoll = Helpers.forceRolls(defer, { args.roll })
    local placed = GardenLights.roll(def)
    restoreRoll()
    return { chance = GardenLights.chanceFor(def), placed = placed, rolled = GardenLights.isRolled(def),
        lights = newLights(def, before, defer) }
end)
