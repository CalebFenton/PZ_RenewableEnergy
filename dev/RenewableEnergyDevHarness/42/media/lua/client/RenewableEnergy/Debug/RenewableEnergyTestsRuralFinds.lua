require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"
local DigesterJobs = require "RenewableEnergy/Biogas/DigesterJobs"
local Wind = require "RenewableEnergy/Wind"
local Squares = require "cf_commonlib/Squares"
local Digester = require "RenewableEnergy/Biogas/Digester"
local Gasifier = require "RenewableEnergy/WoodGas/Gasifier"
local Sprites = require "RenewableEnergy/Sprites"

-- Rural finds (World/RuralFinds.lua): wind chargers, digesters and gasifiers the world leaves by
-- rural buildings, rolled on the authority (RenewableEnergyTestServerRuralFinds.lua).

local T = RenewableEnergyTest
local test, expect, serverCheck = T.test, T.expect, T.serverCheck


-- Each rural find test rolls the building near the start for that find for certain and checks the
-- state it is found in; rolled again, the building gets nothing more. The wind and wood gas suites
-- mend the same objects.

-- Queues the roll of the find `kind` and a wait for this client's copy of it, `isObject` telling
-- it, with its summary when `recordKind` names a Global Object System record ("digester",
-- "gasifier"); the handle { x, y, z, square, kind, object } lands in self.find.
local function rollFind(self, kind, isObject, recordKind)
    T.server(self, "ruralFindsRoll", { kinds = { kind } })
    T.step(function()
        local at = T.need(self, self.server.ruralFindsRoll.found[kind],
            "a square for the " .. kind .. " by the building near the start")
        self.find = at and T.at(at, { square = getSquare(at.x, at.y, at.z), kind = recordKind })
    end)
    T.waitFor(self, function()
        local find = self.find
        local object = Squares.findObjectOn(find.square, isObject)
        find.object = object and (not recordKind or T.recordSummary(find)) and object or nil
        return find.object ~= nil
    end, "this client's copy of the " .. kind)
end

-- Expects the RuralFinds.FINDS kind `kind` that rollFind rolled to stand outdoors with its roll
-- kept, and the building's second roll to have placed nothing.
local function expectKept(self, kind)
    local answer = self.server.ruralFindsRoll
    expect(answer.found[kind].outdoors, "the " .. kind .. " stands indoors")
    expect(answer.kept and answer.kept[kind], "the building's roll for the " .. kind .. " was not kept")
    T.expectEqual("finds rolling the building again placed", answer.again, 0)
end

-- The old wind charger is found braked with its blades broken.
test("renewable_energy_world_rural_wind_charger", {
    instant = true,
    run = function(self)
        rollFind(self, "wind", Wind.isCharger)
        T.step(function()
            self.found = { broken = Wind.isBroken(self.find.object), braked = Wind.isBraked(self.find.object) }
        end)
    end,
    validate = function(self)
        expectKept(self, "wind")
        expect(self.found.broken, "the wind charger was found with whole blades")
        expect(self.found.braked, "the wind charger was found unbraked")
    end,
})

-- The barrel digester is found in one of the drums, its bags torn, cold and sour. Re-bagged it is
-- mended and eats manure.
test("renewable_energy_world_rural_digester", {
    instant = true,
    run = function(self)
        rollFind(self, "digester", Digester.isDigester, "digester")
        T.step(function()
            local find = self.find
            self.found = T.recordSummary(find)
            self.drum = find.object:getSprite():getName()
            -- Its drum's entity, or each load of it logs "Invalid SpriteConfig object!".
            local config = find.object:getSpriteConfig()
            self.configValid = config ~= nil and config:isValid()
            T.giveMaterials(self, "bags", DigesterJobs.materials(T.player(), DigesterJobs.FIT_BAGS))
            T.actionJob(self, "digester", find, DigesterJobs.FIT_BAGS)
            T.batch(function()
                T.fillRecord(self, find, { hopper = { { type = "Base.Dung_Cow", count = 2 } } })
                T.runDigester(self, find, 2, 30)
                T.readRecord(self, find, "fed")
            end)
        end)
    end,
    validate = function(self)
        expectKept(self, "digester")
        local drums = {}
        for _, tile in pairs(Sprites.digester.barrel) do
            drums[tile] = true
        end
        expect(drums[self.drum], "the digester stands on " .. tostring(self.drum) .. ", not a drum's tile")
        expect(self.configValid, "the found digester's SpriteConfig refused its " .. tostring(self.drum) .. " tile")
        local found = self.found
        T.expectEqual("the found digester's tier", found.tier, "barrel")
        expect(found.torn and found.sour and not found.started, "the digester wasn't found torn, sour and not started")
        local fed = self.reads.fed
        -- New bags, worn only by the two hours since; the summary rounds the condition.
        local wear = (Digester.HOLDERS[fed.holder].wearPerDay or 0) * 2 / 24
        expect(not fed.torn and fed.holderCondition >= 100 - wear - 0.5,
            "Fit Garbage Bags didn't mend the found digester: condition " .. tostring(fed.holderCondition))
        T.expectEqual("manure left in the re-bagged digester's hopper", fed.hopperItems, 0)
        expect(fed.potential > 0, "the re-bagged digester ate no manure")
    end,
})

-- The primitive gasifier is found with its ash pit full and its filter packing all tarred.
test("renewable_energy_world_rural_gasifier", {
    instant = true,
    run = function(self)
        rollFind(self, "gasifier", Gasifier.isGasifier, "gasifier")
        T.step(function() T.readRecord(self, self.find, "found") end)
    end,
    validate = function(self)
        expectKept(self, "gasifier")
        local found = self.reads.found
        T.expectEqual("the found gasifier's tier", found.tier, "primitive")
        T.expectEqual("the found gasifier's ash", found.ash, Gasifier.ASH_FULL)
        T.expectEqual("clean packing in the found gasifier", found.clean, 0)
        expect(found.tarry > 0, "the gasifier was found with no tarry packing")
    end,
})

-- Real buildings the world rolls when the character gets there, through the chunk loads that bring
-- them in and their surroundings: the world's roll is kept, and each find it gave stands by the
-- building. Rolled again for certain, with every find it qualifies for, their rooms pick the finds
-- and each find its square, outdoors on the ground within BuildingWatch.REACH of the building (the
-- wind charger needs open ground around it), and the gasifier and digester leave their reading in
-- the building. In order: the barn west of Muldraugh, the hunting shack west of Riverside, the deer
-- stand, whose one room is above ground (`z`) while its find is not, a farm storage shed without a
-- barn, and a pigsty.
local RURAL_PLACES = {
    { 10469, 10121, 0, finds = { wind = true, digester = true }, magazine = true },
    { 7067, 8632, 0, finds = { gasifier = true }, pamphlet = true },
    { 7917, 8176, 1, finds = { gasifier = true } },
    { 7350, 8519, 0, finds = { wind = true } },
    { 6605, 8894, 0, finds = { digester = true }, magazine = true },
}

test("renewable_energy_world_rural_finds_real_buildings", {
    -- Several far visits and the way back, each waiting on loading.
    timeoutSeconds = 240,
    run = function(self)
        T.startVisits(self)
        for _, place in ipairs(RURAL_PLACES) do
            T.visitUntil(self, place[1], place[2], place[1] .. "," .. place[2], "ruralFindAt",
                { x = place[1], y = place[2], z = place[3] }, function(answer) return answer.ready end)
        end
        T.returnHome(self)
    end,
    validate = function(self)
        for _, place in ipairs(RURAL_PLACES) do
            local where = place[1] .. "," .. place[2]
            local answer = self.reads[where]
            if expect(answer and answer.ready, "the building at " .. where .. " was never rolled by the world: "
                .. tostring(answer and answer.why)) then
                for _, kind in ipairs(answer.world) do
                    expect(answer.standing[kind] >= 1, "the world's roll gave the building at " .. where .. " a " .. kind
                        .. " that stands nowhere by it")
                end
                local qualifies = {}
                for _, kind in ipairs(answer.qualifies) do
                    qualifies[kind] = true
                end
                for _, kind in ipairs({ "wind", "digester", "gasifier" }) do
                    T.expectEqual("whether the building at " .. where .. " qualifies for the " .. kind,
                        qualifies[kind] or false, place.finds[kind] or false)
                end
                for kind in pairs(place.finds) do
                    local at = answer.found[kind]
                    if expect(at, "rolled for certain, the building at " .. where .. " got no " .. kind) then
                        expect(at.outdoors, "the " .. kind .. " by " .. where .. " stands indoors at " .. at.x .. "," .. at.y)
                        T.expectEqual("the level of the " .. kind .. " by " .. where, at.z, 0)
                        expect(at.out >= (kind == "wind" and 2 or 1) and at.out <= answer.reach[kind],
                            "the " .. kind .. " by " .. where .. " stands " .. at.out .. " squares out from the building")
                    end
                end
                if place.pamphlet then
                    T.expectEqual("pamphlets in the shack at " .. where, answer.pamphlets, 1)
                end
                if place.magazine then
                    T.expectEqual("biogas magazines in the building at " .. where, answer.magazines, 1)
                end
            end
        end
    end,
})

-- At 0 the Solar Sites option leaves rural buildings without finds: every find has chance 0, and
-- the building near the start, rolled for every find with the lowest roll there is, gets none.
test("renewable_energy_world_rural_finds_option_zero", {
    sandbox = { SolarSites = 0 },
    run = function(self) T.server(self, "ruralFindsRoll", {}) end,
    validate = function(self)
        local answer = self.server.ruralFindsRoll
        for kind, chance in pairs(answer.chances) do
            T.expectEqual("the " .. kind .. "'s chance with the option at 0", chance, 0)
        end
        T.expectEqual("finds the roll placed with the option at 0", answer.placed, 0)
    end,
})

-- Vanilla's barns, farm storerooms and survivalist camps are dressed with the mod's magazines,
-- pamphlet and charger, the biogas and wind magazines weighted up.
serverCheck("renewable_energy_world_rural_clutter", "ruralClutter")
