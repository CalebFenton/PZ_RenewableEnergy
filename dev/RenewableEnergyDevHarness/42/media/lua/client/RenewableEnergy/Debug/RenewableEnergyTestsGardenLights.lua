require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"

-- Garden lights the world puts around houses (World/GardenLights.lua), rolled on the authority
-- (RenewableEnergyTestServerGardenLights.lua).

local T = RenewableEnergyTest
local test, expect, expectNear = T.test, T.expect, T.expectNear

-- A house rolled for garden lights is never rolled again: the roll is kept in the world's
-- ModData. A house a solar site promised lights gets them. They stand outdoors on the ground near
-- the house, charged, and players see them. The house near the start was already rolled when its
-- chunk loaded, so the test forgets that roll first.
test("renewable_energy_world_garden_lights_once_per_house", {
    run = function(self)
        T.server(self, "gardenLightsOnce")
        local function copies()
            local found = 0
            for _, light in ipairs(self.server.gardenLightsOnce.lights) do
                if RenewableEnergy.SolarGardenLight.findOn(getSquare(light.x, light.y, light.z)) then
                    found = found + 1
                end
            end
            return found
        end
        T.waitFor(self, function() return copies() == #self.server.gardenLightsOnce.lights end,
            "this client's copies of the new lights")
    end,
    validate = function(self)
        local answer = self.server.gardenLightsOnce
        local count = answer.count
        -- A house rolled for lights gets at least one.
        T.expectSaneRange(count, "a house's garden light count")
        expect(T.inRange(answer.first, count), "the house got " .. answer.first .. " lights")
        expect(answer.rolled, "the house's roll was not kept")
        expect(answer.second == 0, "rolling the house again gave " .. answer.second .. " more lights")
        expect(#answer.lights == answer.first, #answer.lights .. " lights stand around the house, expected " .. answer.first)
        for _, light in ipairs(answer.lights) do
            local key = light.x .. "," .. light.y
            expect(light.outdoors, "a light stands indoors at " .. key)
            expectNear("a new light's charge", light.charge, RenewableEnergy.Specs.gardenLight.wh, 0.001)
        end
    end,
})

-- A place of each neighbourhood, by the map's zones: a rich street (Riverside's Rich loot zone), a
-- trailer park, and two ordinary places, a farmhouse counting as one.
local NEIGHBOURHOODS = {
    { x = 6680, y = 5320, is = "rich" }, { x = 5370, y = 5945, is = "poor" }, { x = 7340, y = 5993, is = "ordinary" },
    { x = 10835, y = 10144, is = "ordinary" },
}

-- The neighbourhood a house is in sets its chance. Some zones, the trailer park's among them, are
-- known only once their chunks load, so the character visits each place in turn, staying until it
-- has loaded and the authority has rolled the house nearest it, and comes back once the start has
-- loaded again.
test("renewable_energy_world_garden_light_neighbourhoods", {
    run = function(self)
        self.found = {}
        T.startVisits(self)
        for i, place in ipairs(NEIGHBOURHOODS) do
            local where = place.x .. "," .. place.y
            T.visitUntil(self, place.x, place.y, where, "gardenLightsAt", { x = place.x, y = place.y, radius = 20 },
                function(answer) return answer.rolled end)
            T.step(function() self.found[i] = self.server.gardenLightsAt end)
        end
        T.returnHome(self)
    end,
    validate = function(self)
        for i, place in ipairs(NEIGHBOURHOODS) do
            local where, found = place.x .. "," .. place.y, self.found[i] or {}
            expect(found.neighbourhood == place.is, where .. " is " .. tostring(found.neighbourhood) .. ", expected " .. place.is)
            if expect(found.house, "no house near " .. where) then
                expect(found.rolled, "the house at " .. found.house .. " was never rolled for garden lights")
            end
        end
    end,
})

-- At 0 the Garden Lights option leaves every house without lights: the house near the start has
-- chance 0, and rolled with the lowest roll there is it gets none, and stays rolled.
test("renewable_energy_world_garden_lights_option_zero", {
    sandbox = { GardenLights = 0 },
    run = function(self) T.server(self, "gardenLightsRoll", { roll = 0 }) end,
    validate = function(self)
        local answer = self.server.gardenLightsRoll
        expect(answer.chance == 0, "houses get lights with chance " .. answer.chance .. " with the option at 0")
        expect(answer.placed == 0 and #answer.lights == 0,
            "with the option at 0 the roll placed " .. answer.placed .. " lights, and " .. #answer.lights .. " stand around the house")
        expect(answer.rolled, "the house's roll wasn't kept")
    end,
})
