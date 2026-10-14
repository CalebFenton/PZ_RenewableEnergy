-- The authority's half of the garden light tests: houses are rolled for lights only where the
-- authority runs them. Only registers handlers, so a --stay rerun loads it again (RELOAD_FILES);
-- RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler
local removeObject = Helpers.removeObject

-- Squares out from a house's bounds searched for its lights: past GardenLights' local REACH, the
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

local function houseNearCharacter(character)
    return houseNear(math.floor(character:getX()), math.floor(character:getY()), 60)
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

-- The house near the character, its lights as they stand and a function that forgets its roll,
-- which its chunk loading made, so that it can be rolled again. The roll is put back when the test
-- ends. Answers nil without a house.
local function houseToRoll(player, defer)
    local def = houseNearCharacter(player)
    if not def then
        return nil
    end
    local GardenLights = RenewableEnergy.GardenLights
    local store, key = ModData.getOrCreate(GardenLights.MOD_DATA), GardenLights.buildingKey(def)
    local roll = store[key]
    defer(function() store[key] = roll end)
    return def, lightsAround(def), function() store[key] = nil end
end

-- The lights around the house that `before` didn't have: their squares, whether each stands
-- outdoors on the ground, and their charge. They are removed when the test ends.
local function newLights(def, before, defer)
    local lights = {}
    for squareKey, light in pairs(lightsAround(def)) do
        if not before[squareKey] then
            defer(function() removeObject(light) end)
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

-- The house near the character is rolled for garden lights twice, after its first roll is
-- forgotten: the first roll is certain. Answers how many lights each roll gave, whether the roll
-- was kept, and the new lights.
handler("gardenLightsOnce", function(player, _, defer)
    local GardenLights = RenewableEnergy.GardenLights
    local def, before, forget = houseToRoll(player, defer)
    if not def then
        return nil, "a house near the character on the server"
    end
    forget()
    local first = GardenLights.roll(def, true)
    local rolled = GardenLights.isRolled(def)
    local second = GardenLights.roll(def, true)
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
        house = def and GardenLights.buildingKey(def) or nil,
        rolled = def and GardenLights.isRolled(def) or false,
        neighbourhood = GardenLights.neighbourhood(args.x, args.y),
    }
end)

-- The house near the character rolled `args.rolls` times the way the world rolls it, its roll
-- forgotten before each, at the save's options. Answers its chance, how many lights the rolls
-- gave, and the new lights around it.
handler("gardenLightsRolls", function(player, args, defer)
    local GardenLights = RenewableEnergy.GardenLights
    local def, before, forget = houseToRoll(player, defer)
    if not def then
        return nil, "a house near the character on the server"
    end
    local placed = 0
    for _ = 1, args.rolls do
        forget()
        placed = placed + GardenLights.roll(def, false)
    end
    return { chance = GardenLights.chanceFor(def), placed = placed, lights = newLights(def, before, defer) }
end)
