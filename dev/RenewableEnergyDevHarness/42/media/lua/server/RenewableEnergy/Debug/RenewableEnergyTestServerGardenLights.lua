-- The authority's half of the garden light tests: houses are rolled for lights only where the
-- authority runs them.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
require "PZHarness/Rolls"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"
local Kinds = require "RenewableEnergy/Debug/RenewableEnergyTestKinds"
local BuildingWatch = require "RenewableEnergy/World/BuildingWatch"
local GardenLights = require "RenewableEnergy/World/GardenLights"
local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLight"

local handler, need = PZHarness.serverHandler, PZHarness.need
local removePlaced = PZHarness.Fixtures.removePlaced

local function isHouse(def)
    return def:isResidential()
end

-- The garden lights within GardenLights.REACH of a house, as a set.
local function lightsAround(def)
    local found = {}
    local reach = GardenLights.REACH
    for x = def:getX() - reach, def:getX2() + reach do
        for y = def:getY() - reach, def:getY2() + reach do
            local light = SolarGardenLight.findOn(getSquare(x, y, 0))
            if light then
                found[light] = true
            end
        end
    end
    return found
end

-- The house near the character, its roll forgotten (its chunk loading rolled it), is rolled for
-- garden lights the way the world rolls it, then again: with `args.promise`, after promising it
-- lights as a solar site does; else with the roll set to `args.roll`. Answers its chance, how many
-- lights each roll gave, whether the first roll was kept, and the new lights: their squares,
-- whether each stands outdoors on the ground, and their charge. They are removed when the test
-- ends.
handler("gardenLightsRoll", function(player, args, defer)
    local def = need(PZHarness.Fixtures.buildingNear(math.floor(player:getX()), math.floor(player:getY()), 60, isHouse),
        "a house near the character on the server")
    Helpers.forgetBuildingRoll(GardenLights.MOD_DATA, def, defer)
    local before = lightsAround(def)
    if args.promise then
        GardenLights.promise(def)
    end
    local first = args.promise and GardenLights.roll(def) or PZHarness.Rolls.with(defer, { args.roll }, GardenLights.roll, def)
    local answer = { chance = GardenLights.chanceFor(def), first = first, rolled = GardenLights.isRolled(def),
        second = GardenLights.roll(def), lights = {}, count = GardenLights.COUNT }
    for i, light in ipairs(PZHarness.Fixtures.newSince(before, lightsAround(def))) do
        defer(function() removePlaced(light) end)
        local square = light:getSquare()
        answer.lights[i] = {
            x = square:getX(), y = square:getY(), z = square:getZ(),
            outdoors = square:isOutside() and square:getRoom() == nil and square:getZ() == 0,
            charge = SolarGardenLight.getChargeWh(light),
        }
    end
    return answer
end)

-- At the square at `args`: whether it is loaded, the house nearest it within `args.radius`, whether
-- that house was rolled for garden lights, and the neighbourhood.
handler("gardenLightsAt", function(_, args)
    local loaded = getSquare(args.x, args.y, 0) ~= nil
    local def = loaded and PZHarness.Fixtures.buildingNear(args.x, args.y, args.radius, isHouse)
    return {
        loaded = loaded,
        house = def and BuildingWatch.key(def) or nil,
        rolled = def and GardenLights.isRolled(def) or false,
        neighbourhood = GardenLights.neighbourhood(args.x, args.y),
    }
end)

-- The building of the map at x, y, loaded or not, or the handler ends as missing it.
local function houseAt(args)
    return need(getWorld():getMetaGrid():getBuildingAt(args.x, args.y), "a building at " .. args.x .. "," .. args.y)
end

-- The house at x, y of the map, its roll forgotten until the test ends, so that a solar site can
-- promise it lights. Answers its bounds, x2 and y2 past its last squares, and how far around it
-- must load before it is rolled.
handler("gardenLightsForgetHouse", function(_, args, defer)
    local def = houseAt(args)
    Helpers.forgetBuildingRoll(GardenLights.MOD_DATA, def, defer)
    return { x = def:getX(), y = def:getY(), x2 = def:getX2(), y2 = def:getY2(), reach = GardenLights.REACH }
end)

-- The house at x, y of the map: whether its square there is loaded here and every chunk around it
-- that it waits for, whether its garden light roll holds a solar site's promise or a roll, how
-- many lights its roll placed, and how many stand around it.
handler("gardenLightsHouse", function(_, args)
    local def = houseAt(args)
    local roll = ModData.getOrCreate(GardenLights.MOD_DATA)[BuildingWatch.key(def)]
    local rolled = GardenLights.isRolled(def)
    return {
        loaded = getSquare(args.x, args.y, 0) ~= nil,
        surroundings = BuildingWatch.surroundingsLoaded(def, GardenLights.REACH),
        promised = roll == GardenLights.PROMISED, rolled = rolled, lights = Kinds.count(lightsAround(def)),
        placed = rolled and roll or 0,
        count = GardenLights.COUNT,
    }
end)

-- Takes away the garden lights around the house at x, y of the map, while it is loaded: the test
-- moves on.
handler("gardenLightsClearHouse", function(_, args)
    for light in pairs(lightsAround(houseAt(args))) do
        removePlaced(light)
    end
    return {}
end)
