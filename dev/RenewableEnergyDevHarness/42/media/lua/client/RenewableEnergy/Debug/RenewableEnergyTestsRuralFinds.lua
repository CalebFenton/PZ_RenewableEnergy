require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"
require "RenewableEnergy/Biogas/DigesterJobs"
require "RenewableEnergy/WoodGas/GasifierJobs"
require "RenewableEnergy/Wind"
local Squares = require "cf_commonlib/Squares"

-- Rural finds (World/RuralFinds.lua): wind chargers, digesters and gasifiers the world leaves by
-- rural buildings, rolled on the authority (RenewableEnergyTestServerRuralFinds.lua).

local T = RenewableEnergyTest
local test, expect, serverCheck = T.test, T.expect, T.serverCheck

local Sprites = RenewableEnergy.Sprites
local Digester, DigesterJobs = RenewableEnergy.Digester, RenewableEnergy.DigesterJobs
local Gasifier, GasifierJobs = RenewableEnergy.Gasifier, RenewableEnergy.GasifierJobs
local Wind, PowerBank = RenewableEnergy.Wind, RenewableEnergy.PowerBank

-- Each rural find test rolls the building near the start for that find for certain, mends it
-- with the usual jobs and sees it work; rolled again, the building gets nothing more.

-- Queues the roll of the find `kind` and a wait for this client's copy of it, `isObject` telling
-- it, with its summary when `recordKind` names a Global Object System record ("digester",
-- "gasifier"); the handle { x, y, z, square, kind, object } lands in self.find.
local function rollFind(self, kind, isObject, recordKind)
    T.server(self, "ruralFind", { kind = kind })
    T.step(function()
        local at = self.server.ruralFind.at
        self.find = T.at(at, { square = getSquare(at.x, at.y, at.z), kind = recordKind })
    end)
    T.waitFor(self, function()
        local find = self.find
        local object = Squares.findObjectOn(find.square, isObject)
        -- T.recordSummary reads the handle's object.
        find.object = object
        find.object = object and (not recordKind or T.recordSummary(find)) and object or nil
        return find.object ~= nil
    end, "this client's copy of the " .. kind)
end

local function expectKept(self, kind)
    local answer = self.server.ruralFind
    expect(answer.at.outdoors, "the " .. kind .. " stands indoors")
    expect(answer.kept, "the building's roll for the " .. kind .. " was not kept")
    expect(answer.again == 0, "rolling the building again placed " .. answer.again .. " more finds")
end

-- The old wind charger is found braked with its blades broken. With blades fitted, wired to a bank
-- and its brake off, it turns in the wind.
test("renewable_energy_world_rural_wind_charger", {
    instant = true,
    run = function(self)
        rollFind(self, "wind", Wind.isCharger)
        T.step(function()
            local find = self.find
            self.found = { broken = Wind.isBroken(find.object), braked = Wind.isBraked(find.object) }
            local bank = T.bank(self, "batteryRackWood", { "Base.CarBattery1", "RenewableEnergy.PlugInInverter",
                "RenewableEnergy.ChargeController" }, { near = find.square })
            if not bank then return end
            T.performInto(self, "connected", "connectSource", { bank = bank.position, source = T.at(find) })
            T.give(self, "blades", { { type = "RenewableEnergy.WoodenBlades" } })
            -- Replacing the blades takes light to see by, and the square the character was moved to
            -- out here lights up some frames after they arrive.
            T.goNextTo(self, find.square)
            T.waitFor(self, function() return not T.player():tooDarkToRead() end, "light where the character stands")
            T.doJob(self, find.square, function()
                return RenewableEnergyAction:new(T.player(), RenewableEnergyAction.REPLACE_BLADES, find.object,
                    nil, nil, self.items.blades[1])
            end)
            T.waitFor(self, function() return not Wind.isBroken(find.object) end, "this client's copy of the new blades")
            T.batch(function()
                T.perform(self, "setBrake", { source = T.at(find), braked = false })
                T.bankPass(self, bank, 0, { windKph = 30 })
                T.step(function() self.mended = bank.state end)
            end)
        end)
    end,
    validate = function(self)
        expectKept(self, "wind charger")
        expect(self.found.broken and self.found.braked, "the wind charger was found with broken " .. tostring(self.found.broken)
            .. ", braked " .. tostring(self.found.braked))
        if not expect(self.connected and self.connected.ok, "the bank refused the wind charger: "
            .. tostring(self.connected and self.connected.reason)) then return end
        local turning
        for _, source in ipairs(self.mended and self.mended.status.sources or {}) do
            if PowerBank.samePosition(source, self.find) then
                turning = source
            end
        end
        expect(turning ~= nil and turning.watts > 0, "mended, wired and unbraked in a 30 km/h wind it made nothing")
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
            T.giveMaterials(self, "bags", DigesterJobs.materials(T.player(), DigesterJobs.REPLACE_BAGS))
            T.gasJob(self, "digester", find, DigesterJobs.REPLACE_BAGS)
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
        expect(found.tier == "barrel" and found.torn and found.sour and not found.started,
            "the digester was found " .. tostring(found.tier) .. ", torn " .. tostring(found.torn) .. ", sour "
            .. tostring(found.sour) .. ", started " .. tostring(found.started))
        local fed = self.reads.fed
        -- New bags, worn only by the two hours since; the summary rounds the condition.
        local wear = (Digester.HOLDERS[fed.holder].wearPerDay or 0) * 2 / 24
        expect(not fed.torn and fed.holderCondition >= 100 - wear - 0.5,
            "Replace Bags didn't mend the found digester: condition " .. tostring(fed.holderCondition))
        expect(fed.hopperItems == 0 and fed.potential > 0, "the re-bagged digester left " .. tostring(fed.hopperItems)
            .. " manure in its hopper, potential " .. tostring(fed.potential))
    end,
})

-- The primitive gasifier is found with its ash pit full and its filter packing all tarred. Cleaned
-- out and repacked with hay, it lights and runs at its full share.
test("renewable_energy_world_rural_gasifier", {
    instant = true,
    run = function(self)
        rollFind(self, "gasifier", Gasifier.isGasifier, "gasifier")
        T.step(function()
            local find = self.find
            T.readRecord(self, find, "found")
            T.giveMaterials(self, "shovel", GasifierJobs.materials(T.player(), GasifierJobs.CLEAN_ASH))
            T.gasJob(self, "gasifier", find, GasifierJobs.CLEAN_ASH)
            T.batch(function()
                T.server(self, "ruralFindEmptyFilter", T.at(find))
                T.fillRecord(self, find, { hopper = { { type = "Base.Plank", count = 3 } }, filter = { { type = "Base.HayTuft", count = 5 } } })
            end)
            T.waitForSummary(self, find, function(summary) return summary.hopperKg > 0 and summary.ash == 0 end,
                "this client's summary of the cleaned, stocked gasifier")
            T.lightGasifier(self, find)
            T.readRecord(self, find, "lit")
        end)
    end,
    validate = function(self)
        expectKept(self, "gasifier")
        local found, lit = self.reads.found, self.reads.lit
        expect(found.tier == "primitive" and found.ash == Gasifier.ASH_FULL and found.clean == 0 and found.tarry > 0,
            "the gasifier was found " .. tostring(found.tier) .. ", ash " .. tostring(found.ash) .. ", "
            .. tostring(found.clean) .. " clean and " .. tostring(found.tarry) .. " tarry packing")
        expect(lit.lit, "the cleaned gasifier didn't light")
        expect(Gasifier.outputShare(lit.ash, lit.clean) == 1,
            "cleaned and repacked it runs at " .. Gasifier.outputShare(lit.ash, lit.clean) .. " of its output")
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
        self.answers = {}
        for i, place in ipairs(RURAL_PLACES) do
            local where = place[1] .. "," .. place[2]
            T.visitUntil(self, place[1], place[2], where, "ruralFindAt", { x = place[1], y = place[2], z = place[3] }, function(answer)
                self.answers[i] = answer
                return answer.ready
            end)
        end
        T.returnHome(self)
    end,
    validate = function(self)
        for i, place in ipairs(RURAL_PLACES) do
            local where, answer = place[1] .. "," .. place[2], self.answers[i]
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
                    expect((qualifies[kind] or false) == (place.finds[kind] or false),
                        "the building at " .. where .. (place.finds[kind] and " doesn't qualify" or " qualifies") .. " for the " .. kind)
                end
                for kind in pairs(place.finds) do
                    local at = answer.found[kind]
                    if expect(at, "rolled for certain, the building at " .. where .. " got no " .. kind) then
                        expect(at.outdoors and at.z == 0, "the " .. kind .. " by " .. where .. " stands indoors at " .. at.x .. "," .. at.y)
                        expect(at.out >= (kind == "wind" and 2 or 1) and at.out <= answer.reach[kind],
                            "the " .. kind .. " by " .. where .. " stands " .. at.out .. " squares out from the building")
                    end
                end
                if place.pamphlet then
                    expect(answer.pamphlets == 1, "the shack at " .. where .. " got " .. answer.pamphlets .. " pamphlets, not 1")
                end
                if place.magazine then
                    expect(answer.magazines == 1, "the building at " .. where .. " got " .. answer.magazines .. " biogas magazines, not 1")
                end
            end
        end
    end,
})

-- At 0 the Solar Sites option leaves rural buildings without finds: every find has chance 0, and
-- the building near the start, rolled for every find with the lowest roll there is, gets none.
test("renewable_energy_world_rural_finds_option_zero", {
    sandbox = { SolarSites = 0 },
    run = function(self) T.server(self, "ruralFindsRoll", { roll = 0 }) end,
    validate = function(self)
        local answer = self.server.ruralFindsRoll
        for kind, chance in pairs(answer.chances) do
            expect(chance == 0, "the " .. kind .. " has chance " .. chance .. " with the option at 0")
        end
        expect(answer.placed == 0, "with the option at 0 the roll placed " .. answer.placed .. " finds")
    end,
})

-- Vanilla's barns, farm storerooms and survivalist camps are dressed with the mod's magazines,
-- pamphlet and charger, the biogas and wind magazines weighted up.
serverCheck("renewable_energy_world_rural_clutter", "ruralClutter")
