require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
local Digester = require "RenewableEnergy/Biogas/Digester"
local Gasifier = require "RenewableEnergy/WoodGas/Gasifier"
local GasKit = require "RenewableEnergy/GasLine/GasKit"
local Wind = require "RenewableEnergy/Wind"
local Squares = require "cf_commonlib/Squares"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local Sprites = require "RenewableEnergy/Sprites"

-- Solar sites (World/SolarSites.lua): the tests arm a site's spots on the authority as the world
-- does when it rolls the site in (SolarSites.addSite), then let the world place them as their
-- chunks load (RenewableEnergyTestServerSolarSites.lua, ...SiteMap.lua). Near the start a trip
-- away and back unloads the chunk and loads it again, which only single player does.

local T = RenewableEnergyTest
local test, expect, expectEqual, serverCheck = T.test, T.expect, T.expectEqual, T.serverCheck


-- Game minutes to let pass once a spot's chunk is back: a spot goes down by the next.
local SETTLE_MINUTES = 2
-- A wait on the game clock has no limit of its own: the test's time limit comes first.
local CLOCK_MS = math.huge

local function waitGameMinutes(self, minutes)
    local till
    T.step(function() till = getGameTime():getWorldAgeHours() + minutes / 60 end)
    T.waitFor(self, function() return till ~= nil and getGameTime():getWorldAgeHours() >= till end,
        minutes .. " game minutes passing", CLOCK_MS)
end

-- Queues a trip that unloads the chunk of `at` ({ x, y, z }) and loads it again, and a wait for
-- the minute after, when its waiting spots go down.
local function reloadAndSettle(self, at)
    T.reloadChunk(self, at)
    waitGameMinutes(self, SETTLE_MINUTES)
end

-- The spots siteArm armed, as the arguments of the handlers that read them.
local function armedSpots(self)
    return { spots = self.reads.arm.spots }
end

-- A site goes down once, when its chunk loads, and its spot is forgotten, so loading the chunk
-- again places nothing. Its pump's pole mount holds as many modules as its kind says, at site
-- conditions, and players see it.
test("renewable_energy_world_site_placed_once", {
    spOnly = T.CHUNK_RELOAD_SP_ONLY,
    timeoutSeconds = 2 * T.CHUNK_RELOAD_SECONDS,
    run = function(self)
        T.setMultiplier(self, T.VISIT_SPEED)
        local square = T.square(self, nil, "a free outdoor square")
        if not square then return end
        local at = T.at(square)
        T.read(self, "siteArm", { at = at }, "arm")
        reloadAndSettle(self, at)
        T.read(self, "sitePlaced", armedSpots, "placed")
        T.read(self, "siteSpots", armedSpots, "first")
        T.waitFor(self, function() return T.objectWithSprite(getSquare(at.x, at.y, at.z), Sprites.rack.metal.S) ~= nil end,
            "this client's copy of the site's rack")
        reloadAndSettle(self, at)
        T.read(self, "siteSpots", armedSpots, "again")
    end,
    validate = function(self)
        T.expectNoFailures(self.reads.placed)
        local first, again = self.reads.first, self.reads.again
        if expect(first.ready and again.ready, "the site's squares weren't loaded on the server: " .. tostring(first.why or again.why)) then
            expect(first.waiting == 0, "the site's spot was not forgotten once placed")
            expectEqual("objects on the site's square after loading the chunk again", again.objects, first.objects)
        end
    end,
})

-- A spot whose square holds something now, as a player's things or a grown tree would, stays and
-- is tried again each time its chunk loads: a wind farm whose charger's square holds a work table
-- places nothing, neither charger nor bank; with the table gone, the next load places both, the
-- charger braked with its blades broken and wired to a plugged-in rack of tired batteries.
test("renewable_energy_world_site_waits_for_a_free_square", {
    spOnly = T.CHUNK_RELOAD_SP_ONLY,
    timeoutSeconds = 2 * T.CHUNK_RELOAD_SECONDS,
    sandbox = { LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        T.setMultiplier(self, T.VISIT_SPEED)
        local bank = T.square(self, { indoors = true }, "a free indoor square for the bank")
        if not bank then return end
        T.read(self, "siteArm", { bank = T.at(bank), block = true }, "arm")
        T.step(function()
            local at = self.reads.arm.at
            reloadAndSettle(self, at)
            T.read(self, "siteSpots", armedSpots, "blocked")
            T.server(self, "removeAt", T.at(at, { sprite = PZHarness.Fixtures.WORK_TABLE_SPRITE }))
            reloadAndSettle(self, at)
            T.read(self, "sitePlaced", armedSpots, "placed")
            T.waitFor(self, function()
                return Squares.findObjectOn(getSquare(at.x, at.y, at.z), Wind.isCharger) ~= nil
            end, "this client's copy of the wind charger")
        end)
    end,
    validate = function(self)
        local blocked = self.reads.blocked
        if expect(blocked.ready, "the site's squares weren't loaded on the server: " .. tostring(blocked.why)) then
            expectEqual("times the blocked wind charger's spot was kept", blocked.waiting, 1)
            expectEqual("objects the blocked site put on its squares", blocked.placed, 0)
        end
        T.expectNoFailures(self.reads.placed)
    end,
})

-- Every site's spots make sense on the map, and every site name a world rolled stays one.
serverCheck("renewable_energy_world_sites_placed_sensibly", "sitesPlacedSensibly")

-- A world rolls each site once by its name: a world saved while every site was rolled at once
-- gets a site added since, once, and never those it rolled then; the option at 0 still keeps a new
-- site out.
test("renewable_energy_world_site_rolled_once", {
    run = function(self)
        local squares = T.need(self, T.squares(self, 3), "free outdoor squares for the sites' spots")
        if not squares then return end
        local at = {}
        for i, square in ipairs(squares) do
            at[i] = T.at(square)
        end
        T.read(self, "siteRolledOnce", { squares = at }, "rolled")
    end,
    validate = function(self) T.expectNoFailures(self.reads.rolled) end,
})

-- The homestead sites and the outlying towns' solar sites, each with a square of it to go to.
-- `farm`: its find stands by a building whose own roll could give it one (a barn, a cow barn);
-- the prepper's gasifier stands by a house, and only hunting shacks roll gasifiers.
local VISITED_SITES = {
    { "Farm south-east of Echo Creek", 3742, 11120, farm = true },
    { "Farm west of Ekron", 252, 9808, farm = true },
    { "Dairy farm south of Ekron", 886, 10377, farm = true },
    { "Survivalist cabin north of Echo Creek", 3379, 9686 },
    { "Pasture north-west of Ekron", 562, 9629 },
    { "Pasture south of Echo Creek", 3721, 11285 },
    { "Pasture south-east of Fallas Lake", 7456, 8466 },
    { "Trailer in the woods north of March Ridge", 10345, 12405 },
}

-- Whether this client has its copies of what the armed spots `spots` put down, as far as a
-- client sees them: the mounts, banks and crates, a wind charger and its bank, a gas source and
-- its kitted generator. A pamphlet lies in a container whose contents a client gets on opening it,
-- and garden lights are a promise.
local function siteCopiesArrived(spots)
    local function on(x, y, z, matches)
        return Squares.findObjectOn(getSquare(x, y, z), matches) ~= nil
    end
    local function isMount(object)
        local kind = Sprites.kindOfObject(object)
        return kind == "flat" or kind == "wall" or kind == "rack"
    end
    local function isSource(object)
        return Digester.isDigester(object) or Gasifier.isGasifier(object)
    end
    local function isCrate(object)
        return Sprites.nameOf(object) == Sprites.crate
    end
    local seen = {
        panel = function(spot) return on(spot.x, spot.y, spot.z, isMount) end,
        bank = function(spot) return on(spot.x, spot.y, spot.z, PowerBank.isBank) end,
        crate = function(spot) return on(spot.x, spot.y, spot.z, isCrate) end,
        windCharger = function(spot)
            return on(spot.x, spot.y, spot.z, Wind.isCharger) and on(spot.toX, spot.toY, spot.toZ, PowerBank.isBank)
        end,
        gasLine = function(spot)
            return on(spot.x, spot.y, spot.z, isSource) and on(spot.toX, spot.toY, spot.toZ, GasKit.hasKit)
        end,
    }
    for _, spot in ipairs(spots) do
        if seen[spot.what] and not seen[spot.what](spot) then
            return false
        end
    end
    return true
end

-- The world places these sites when the character first gets there, through the chunk loads that
-- bring their spots in: armed as a world that rolled them in arms them, every spot goes down, each
-- as its kind leaves it (worn finds, wired banks, kitted generators, stocked mounts), on the
-- squares the map files gave them, which pass the same checks as any square a spot goes to in a
-- save, trees and plants the game grows included. Players see what went down. A homestead's find
-- counts as the find of the buildings it stands by, and a wind charger's of its bank's barn, from
-- the moment the site is armed, so that their own rolls give the farm no second one. The character
-- visits each site in turn and comes back once the start has loaded again.
test("renewable_energy_world_sites_placed_on_visit", {
    -- Many far visits and the way back, each waiting on loading.
    timeoutSeconds = 600,
    sandbox = { LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        local names = {}
        for i, place in ipairs(VISITED_SITES) do
            names[i] = place[1]
        end
        T.startVisits(self)
        T.read(self, "sitesArm", { names = names }, "armed")
        for _, place in ipairs(VISITED_SITES) do
            local name, x, y = place[1], place[2], place[3]
            local function args() return { name = name, spots = self.reads.armed[name].spots } end
            T.visitUntil(self, x, y, name, "siteSpots", args, function(answer)
                return answer.ready and answer.waiting == 0
            end)
            T.read(self, "siteVisited", args, name .. " checked")
            T.waitFor(self, function() return siteCopiesArrived(self.reads.armed[name].spots) end,
                "this client's copies of what " .. name .. " put down")
            T.server(self, "siteClear", args)
        end
        T.returnHome(self)
    end,
    validate = function(self)
        for _, place in ipairs(VISITED_SITES) do
            local name = place[1]
            local placing, armed = self.reads[name], self.reads.armed[name]
            if expect(placing.ready, name .. " never loaded on the server: " .. tostring(placing.why)) then
                expect(placing.waiting == 0, name .. ": " .. placing.waiting .. " spots never went down (the log says why)")
                T.expectNoFailures(self.reads[name .. " checked"])
            end
            if armed.find then
                local buildings = 0
                for key, finds in pairs(armed.claimed) do
                    buildings = buildings + 1
                    local has = false
                    for _, kind in ipairs(finds) do
                        has = has or kind == armed.find
                    end
                    expect(has, name .. ": the building at " .. key .. " doesn't count the site's " .. armed.find .. " as its find")
                end
                expect(buildings > 0 or not place.farm, name .. ": no building by its " .. armed.find .. " could have one")
            end
        end
    end,
})

-- A farm whose site promises its house garden lights, and the square of the house. No other test
-- goes there, so nothing the world placed earlier stands on its squares.
local PROMISED_HOUSE = { "Farm east of Rosewood", 8470, 11552 }

-- A square to stand on from which the house ({ x, y, x2, y2, reach }, x2 and y2 past its last
-- squares) is loaded while a chunk around it that its roll waits for is not: the house's first or
-- last chunk on one side at the edge of this client's loaded area, on a side where its reach
-- crosses into the next chunk. Nil when no side does, or the house doesn't fit the area.
local function edgeOfLoaded(house)
    local size = 8
    local width = math.floor(getCell():getChunkMap(0):getWidthInTiles() / size)
    local half = math.floor(width / 2)
    local function chunk(v) return math.floor(v / size) end
    local first = { x = chunk(house.x), y = chunk(house.y) }
    local last = { x = chunk(house.x2 - 1), y = chunk(house.y2 - 1) }
    if last.x - first.x >= width or last.y - first.y >= width then
        return nil
    end
    local middle = { x = chunk(math.floor((house.x + house.x2) / 2)), y = chunk(math.floor((house.y + house.y2) / 2)) }
    local function at(cx, cy) return { x = cx * size + size / 2, y = cy * size + size / 2 } end
    if chunk(house.x - house.reach) < first.x then
        return at(first.x + half, middle.y)
    elseif chunk(house.x2 + house.reach) > last.x then
        return at(last.x - width + 1 + half, middle.y)
    elseif chunk(house.y - house.reach) < first.y then
        return at(middle.x, first.y + half)
    elseif chunk(house.y2 + house.reach) > last.y then
        return at(middle.x, last.y - width + 1 + half)
    end
    return nil
end

-- A site's promise of garden lights outlives a quit while its house waits for its surroundings:
-- the promise is saved with the house's garden light roll as soon as the house's chunk loads,
-- before the house is rolled. The character stands where the house is at the edge of the loaded
-- area, so that the house loads and its surroundings don't, then goes to the house, which gets
-- its lights for certain, Garden Lights at 0 or not.
test("renewable_energy_world_site_garden_lights_promised", {
    spOnly = "a multiplayer server loads chunks of its own around a character, not this client's area",
    timeoutSeconds = 300,
    run = function(self)
        local name, x, y = PROMISED_HOUSE[1], PROMISED_HOUSE[2], PROMISED_HOUSE[3]
        T.startVisits(self)
        T.read(self, "gardenLightsForgetHouse", { x = x, y = y }, "house")
        T.read(self, "sitesArm", { names = { name } }, "armed")
        T.step(function()
            self.edge = T.need(self, edgeOfLoaded(self.reads.house), "a side of the house its reach crosses")
        end)
        T.step(function() self.teleportTo(self.edge.x + 0.5, self.edge.y + 0.5, 0) end)
        T.waitFor(self, function() return getSquare(x, y, 0) ~= nil end, "the house loaded at the edge", T.CHUNK_MS)
        waitGameMinutes(self, SETTLE_MINUTES)
        T.read(self, "gardenLightsHouse", { x = x, y = y }, "atEdge")
        T.visitUntil(self, x, y, name, "gardenLightsHouse", { x = x, y = y }, function(answer) return answer.rolled end)
        local function args() return { name = name, spots = self.reads.armed[name].spots } end
        T.read(self, "siteVisited", args, "visited")
        T.server(self, "gardenLightsClearHouse", { x = x, y = y })
        T.server(self, "siteClear", args)
        T.returnHome(self)
    end,
    validate = function(self)
        local atEdge, atHouse = self.reads.atEdge, self.reads[PROMISED_HOUSE[1]]
        if expect(atEdge.loaded and not atEdge.surroundings, "standing at the edge, the house loaded " .. tostring(atEdge.loaded)
            .. " and its surroundings " .. tostring(atEdge.surroundings)) then
            expect(atEdge.promised and not atEdge.rolled and atEdge.lights == 0, "while its surroundings weren't loaded the house held "
                .. (atEdge.promised and "" or "no ") .. "saved promise, rolled " .. tostring(atEdge.rolled) .. ", with "
                .. atEdge.lights .. " lights")
        end
        expect(atHouse.rolled and atHouse.placed >= 1 and atHouse.placed <= atHouse.count.max and atHouse.lights == atHouse.placed,
            "the promised house was rolled " .. tostring(atHouse.rolled) .. " for " .. atHouse.placed .. " lights, and "
            .. atHouse.lights .. " stand around it")
        T.expectNoFailures(self.reads.visited)
    end,
})
