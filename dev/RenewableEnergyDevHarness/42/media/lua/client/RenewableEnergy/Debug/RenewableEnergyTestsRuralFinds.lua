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

-- Each find, how this client tells its object, and the Global Object System record kind it keeps
-- its state in, if any.
local FINDS = {
    { kind = "wind", isObject = Wind.isCharger },
    { kind = "digester", isObject = Digester.isDigester, record = "digester" },
    { kind = "gasifier", isObject = Gasifier.isGasifier, record = "gasifier" },
}

-- The building near the start, rolled for every find for certain, keeps its roll, gets each find
-- outdoors in the state it is found in, and rolled again gets nothing more: the old wind charger
-- braked with its blades broken; the barrel digester in one of the drums, its bags torn, cold and
-- sour, and re-bagged it is mended and eats manure; the primitive gasifier with its ash pit full
-- and its filter packing all tarred. The wind and wood gas suites mend the same objects.
test("renewable_energy_world_rural_finds_found_worn", {
    instant = true,
    run = function(self)
        local kinds = {}
        for i, find in ipairs(FINDS) do
            kinds[i] = find.kind
        end
        T.server(self, "ruralFindsRoll", { kinds = kinds })
        self.finds = {}
        T.step(function()
            for _, find in ipairs(FINDS) do
                local at = T.need(self, self.server.ruralFindsRoll.found[find.kind],
                    "a square for the " .. find.kind .. " by the building near the start")
                if not at then return end
                self.finds[find.kind] = T.at(at, { square = getSquare(at.x, at.y, at.z), kind = find.record })
            end
        end)
        T.waitFor(self, function()
            for _, find in ipairs(FINDS) do
                local handle = self.finds[find.kind]
                local object = Squares.findObjectOn(handle.square, find.isObject)
                handle.object = object and (not find.record or T.recordSummary(handle)) and object or nil
                if not handle.object then
                    return false
                end
            end
            return true
        end, "this client's copies of the finds")
        T.step(function()
            local charger, digester = self.finds.wind.object, self.finds.digester
            self.charger = { broken = Wind.isBroken(charger), braked = Wind.isBraked(charger) }
            self.digester = T.recordSummary(digester)
            self.drum = digester.object:getSprite():getName()
            -- Its drum's entity, or each load of it logs "Invalid SpriteConfig object!".
            local config = digester.object:getSpriteConfig()
            self.configValid = config ~= nil and config:isValid()
            T.readRecord(self, self.finds.gasifier, "gasifier")
            T.giveMaterials(self, "bags", DigesterJobs.materials(T.player(), DigesterJobs.FIT_BAGS))
            T.actionJob(self, "digester", digester, DigesterJobs.FIT_BAGS)
            T.batch(function()
                T.fillRecord(self, digester, { hopper = { { type = "Base.Dung_Cow", count = 1 } } })
                T.runDigester(self, digester, 2, 30)
                T.readRecord(self, digester, "fed")
            end)
        end)
    end,
    validate = function(self)
        local answer = self.server.ruralFindsRoll
        for _, find in ipairs(FINDS) do
            expect(answer.found[find.kind].outdoors, "the " .. find.kind .. " stands indoors")
            expect(answer.kept and answer.kept[find.kind], "the building's roll for the " .. find.kind .. " was not kept")
        end
        T.expectEqual("finds rolling the building again placed", answer.again, 0)
        expect(self.charger.broken, "the wind charger was found with whole blades")
        expect(self.charger.braked, "the wind charger was found unbraked")
        local drums = {}
        for _, tile in pairs(Sprites.digester.barrel) do
            drums[tile] = true
        end
        expect(drums[self.drum], "the digester stands on " .. tostring(self.drum) .. ", not a drum's tile")
        expect(self.configValid, "the found digester's SpriteConfig refused its " .. tostring(self.drum) .. " tile")
        local digester = self.digester
        T.expectEqual("the found digester's tier", digester.tier, "barrel")
        expect(digester.torn and digester.sour and not digester.started, "the digester wasn't found torn, sour and not started")
        local fed = self.reads.fed
        -- New bags, worn only by the two hours since; the summary rounds the condition.
        local wear = (Digester.HOLDERS[fed.holder].wearPerDay or 0) * 2 / 24
        expect(not fed.torn and fed.holderCondition >= 100 - wear - 0.5,
            "Fit Garbage Bags didn't mend the found digester: condition " .. tostring(fed.holderCondition))
        T.expectEqual("manure left in the re-bagged digester's hopper", fed.hopperItems, 0)
        expect(fed.potential > 0, "the re-bagged digester ate no manure")
        local gasifier = self.reads.gasifier
        T.expectEqual("the found gasifier's tier", gasifier.tier, "primitive")
        T.expectEqual("the found gasifier's ash", gasifier.ash, Gasifier.ASH_FULL)
        T.expectEqual("clean packing in the found gasifier", gasifier.clean, 0)
        expect(gasifier.tarry > 0, "the gasifier was found with no tarry packing")
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

-- A find's chance follows the Solar Sites option, at whose default of 75 each find's odds are 1 in
-- its `odds`: the building near the start, rolled for one find at a time with Solar Sites at its
-- highest, 100, gets it on a roll just under 100 / 75 / odds and not at it (the handler works the
-- edge out from the odds alone, not the mod's chance). At 0 the option leaves rural buildings
-- without finds, even on the lowest roll there is.
test("renewable_energy_world_rural_finds_chance_follows_option", {
    run = function(self)
        local trials = {}
        for _, find in ipairs(FINDS) do
            table.insert(trials, { kind = find.kind, option = 100, roll = "under", finds = 1 })
            table.insert(trials, { kind = find.kind, option = 100, roll = "at", finds = 0 })
            table.insert(trials, { kind = find.kind, option = 0, roll = 0, finds = 0 })
        end
        self.trials = trials
        T.read(self, "ruralFindsEdges", { trials = trials }, "edges")
    end,
    validate = function(self)
        for i, trial in ipairs(self.trials) do
            T.expectEqual(string.format("%s finds with Solar Sites at %d on a roll %s", trial.kind, trial.option,
                type(trial.roll) == "string" and trial.roll .. " its chance" or "of " .. trial.roll), self.reads.edges.placed[i], trial.finds)
        end
    end,
})

-- Vanilla's barns, farm storerooms and survivalist camps are dressed with the mod's magazines,
-- pamphlet and charger, the biogas and wind magazines weighted up.
serverCheck("renewable_energy_world_rural_clutter", "ruralClutter")
