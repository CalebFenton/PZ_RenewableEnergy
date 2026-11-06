require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLight"

-- Garden lights the world puts around houses (World/GardenLights.lua), rolled on the authority
-- (RenewableEnergyTestServerGardenLights.lua). A solar site's promise of lights is
-- RenewableEnergyTestsSolarSites.lua's.

local T = RenewableEnergyTest
local test, expect, expectNear, expectEqual = T.test, T.expect, T.expectNear, T.expectEqual

-- The house near the start, rolled when its chunk loaded, is rolled again on either side of its
-- chance: with the Garden Lights option at 0 its chance is 0 and even the lowest roll gives none;
-- at 50 its chance is half its neighbourhood's (0.4 rich, 0.15 ordinary, 0.04 poor, times 50 /
-- 100), and a roll just under it gives it lights standing outdoors on the ground near the house,
-- charged, which players see, and a second roll gives none. Either way the roll is kept. The
-- option goes up last: above 0 a house whose surroundings load meanwhile can grow lights.
local OPTION = 50
test("renewable_energy_world_garden_lights_rolled_once_per_house", {
    sandbox = { GardenLights = 0 },
    run = function(self)
        T.read(self, "gardenLightsRoll", { roll = 0 }, "off")
        -- In its turn: single player sets an option at once, when it is queued.
        T.step(function() T.setSandbox(self, "GardenLights", OPTION) end)
        T.read(self, "gardenLightsRoll", { roll = "under" }, "hit")
        T.waitFor(self, function()
            for _, light in ipairs(self.reads.hit.lights) do
                if not SolarGardenLight.findOn(getSquare(light.x, light.y, light.z)) then
                    return false
                end
            end
            return true
        end, "this client's copies of the new lights")
    end,
    validate = function(self)
        local off, hit = self.reads.off, self.reads.hit
        expect(off.rolledBefore, "the house near the start wasn't rolled when its chunk loaded")
        expectEqual("the chance of lights with the option at 0", off.chance, 0)
        expectEqual("lights the lowest roll placed with the option at 0", off.first, 0)
        expectEqual("lights standing around the house with the option at 0", #off.lights, 0)
        expect(off.rolled, "the house's roll with the option at 0 wasn't kept")
        if not expect(hit.neighbourhoodChance ~= nil, "the house's neighbourhood " .. tostring(hit.neighbourhood) .. " has no chance") then
            return
        end
        expectNear("the " .. hit.neighbourhood .. " house's chance of lights with the option at " .. OPTION, hit.chance,
            hit.neighbourhoodChance * OPTION / 100, 1e-9)
        expect(T.inRange(hit.first, hit.count), "a roll under the chance gave the house " .. hit.first .. " lights")
        expect(hit.rolled, "the house's roll was not kept")
        expectEqual("lights rolling the house again gave", hit.second, 0)
        expectEqual("lights standing around the house", #hit.lights, hit.first)
        for _, light in ipairs(hit.lights) do
            expect(light.outdoors, "a light stands indoors at " .. light.x .. "," .. light.y)
            expectNear("a new light's charge", light.charge, SolarGardenLight.SPEC.wh, 0.001)
        end
    end,
})

-- A place of each neighbourhood, by the map's zones: a rich street (Riverside's Rich loot zone), a
-- trailer park and an ordinary street.
local NEIGHBOURHOODS = {
    { x = 6680, y = 5320, is = "rich" }, { x = 5370, y = 5945, is = "poor" }, { x = 7340, y = 5993, is = "ordinary" },
}

-- The map's zones set a house's neighbourhood. Some zones, the trailer park's among them, are
-- known only once their chunks load, so the character visits each place in turn until the
-- authority has loaded it, and comes back once the start has loaded again.
test("renewable_energy_world_garden_light_neighbourhoods", {
    run = function(self)
        T.startVisits(self)
        for _, place in ipairs(NEIGHBOURHOODS) do
            T.visitUntil(self, place.x, place.y, place.x .. "," .. place.y, "gardenLightsAt", { x = place.x, y = place.y },
                function(answer) return answer.loaded end)
        end
        T.returnHome(self)
    end,
    validate = function(self)
        for _, place in ipairs(NEIGHBOURHOODS) do
            local where = place.x .. "," .. place.y
            expectEqual(where .. "'s neighbourhood", self.reads[where].neighbourhood, place.is)
        end
    end,
})
