require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/GasLine/GasKit"
require "RenewableEnergy/Wind"

-- Solar sites (World/SolarSites.lua): the tests arm a site's spots on the authority as the world
-- does when it rolls the site in (SolarSites.addSite), then let the world place them as their
-- chunks load (RenewableEnergyTestServerSolarSites.lua, ...SiteMap.lua). Near the start a trip
-- away and back unloads the chunk and loads it again, which only single player does.

local T = RenewableEnergyTest
local test, expect, player, serverCheck = T.test, T.expect, T.player, T.serverCheck

local Sprites = RenewableEnergy.Sprites
local Digester, Gasifier = RenewableEnergy.Digester, RenewableEnergy.Gasifier
local Wind, PowerBank = RenewableEnergy.Wind, RenewableEnergy.PowerBank

-- Game minutes to let pass once a spot's chunk is back: a spot that waits goes down at the next.
local SETTLE_MINUTES = 2
-- The longest a wait on the game clock may take, in frames; the test's time limit comes first.
local CLOCK_FRAMES = 1000000

local function waitGameMinutes(self, minutes)
    local till
    T.step(function() till = getGameTime():getWorldAgeHours() + minutes / 60 end)
    T.waitFor(self, function() return till ~= nil and getGameTime():getWorldAgeHours() >= till end,
        minutes .. " game minutes passing", CLOCK_FRAMES)
end

-- Queues a trip that unloads the chunk of `at` ({ x, y, z }) and loads it again, and a wait for
-- the minute after, when its waiting spots go down.
local function reloadChunk(self, home, at)
    T.awayAndBack(self, home, at.x, at.y, at.z)
    waitGameMinutes(self, SETTLE_MINUTES)
end

-- The spots siteArm armed, as the arguments of the handlers that read them.
local function armedSpots(self)
    return { spots = self.server.siteArm.spots }
end

-- A site goes down once, when its chunk loads, and its spot is forgotten, so loading the chunk
-- again places nothing. Its pump's pole mount holds as many modules as its kind says, at site
-- conditions, and players see it.
test("renewable_energy_world_site_placed_once", {
    spOnly = T.CHUNK_RELOAD_SP_ONLY,
    timeoutSeconds = 240,
    run = function(self)
        T.setMultiplier(self, T.VISIT_SPEED)
        local square = T.square(self, nil, "a free outdoor square")
        if not square then return end
        local home, at = T.at(player():getSquare()), T.at(square)
        T.server(self, "siteArm", { at = at })
        reloadChunk(self, home, at)
        T.server(self, "sitePlaced", armedSpots)
        T.serverInto(self, "first", "siteSpots", armedSpots)
        T.waitFor(self, function() return T.objectWithSprite(getSquare(at.x, at.y, at.z), Sprites.rack.metal.S) ~= nil end,
            "this client's copy of the site's rack")
        reloadChunk(self, home, at)
        T.server(self, "siteSpots", armedSpots)
    end,
    validate = function(self)
        T.expectNoFailures(self.server.sitePlaced)
        local first, again = self.first, self.server.siteSpots
        expect(first.waiting == 0, "the site's spot was not forgotten once placed")
        expect(again.objects == first.objects, "loading the chunk again left " .. again.objects
            .. " objects on the site's square, not " .. first.objects)
    end,
})

-- A spot whose square holds something now, as a player's things or a grown tree would, stays and
-- is tried again each time its chunk loads: a wind farm whose charger's square holds a work table
-- places nothing, neither charger nor bank; with the table gone, the next load places both, the
-- charger braked with its blades broken and wired to a plugged-in rack of tired batteries.
test("renewable_energy_world_site_waits_for_a_free_square", {
    spOnly = T.CHUNK_RELOAD_SP_ONLY,
    timeoutSeconds = 240,
    sandbox = { LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        T.setMultiplier(self, T.VISIT_SPEED)
        local bank = T.square(self, { indoors = true }, "a free indoor square for the bank")
        if not bank then return end
        local home = T.at(player():getSquare())
        T.server(self, "siteArm", { bank = T.at(bank), block = true })
        T.step(function()
            local at = self.server.siteArm.at
            reloadChunk(self, home, at)
            T.serverInto(self, "blocked", "siteSpots", armedSpots)
            T.server(self, "siteUnblock", at)
            reloadChunk(self, home, at)
            T.server(self, "sitePlaced", armedSpots)
            T.waitFor(self, function()
                return RenewableEnergy.findObjectOn(getSquare(at.x, at.y, at.z), Wind.isCharger) ~= nil
            end, "this client's copy of the wind charger")
        end)
    end,
    validate = function(self)
        local blocked = self.blocked
        expect(blocked.waiting == 1, "the blocked wind charger's spot was " .. (blocked.waiting == 0 and "forgotten" or "kept "
            .. blocked.waiting .. " times"))
        expect(blocked.placed == 0, "the blocked site put " .. blocked.placed .. " objects on its squares")
        T.expectNoFailures(self.server.sitePlaced)
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
        T.server(self, "siteRolledOnce", { squares = at })
    end,
    validate = function(self) T.expectNoFailures(self.server.siteRolledOnce) end,
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
        return RenewableEnergy.findObjectOn(getSquare(x, y, z), matches) ~= nil
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
            return on(spot.x, spot.y, spot.z, isSource) and on(spot.toX, spot.toY, spot.toZ, RenewableEnergy.GasKit.hasKit)
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
        self.visits = {}
        T.serverInto(self, "armed", "sitesArm", { names = names })
        for i, place in ipairs(VISITED_SITES) do
            local name, x, y = place[1], place[2], place[3]
            local visit = {}
            self.visits[i] = visit
            local function args() return { name = name, spots = self.armed[name].spots } end
            T.visitUntil(self, x, y, name, "siteVisit", args, function(answer)
                visit.placing = answer
                return answer.ready and answer.waiting == 0
            end)
            T.server(self, "siteVisited", args)
            T.step(function() visit.check = self.server.siteVisited end)
            T.waitFor(self, function() return siteCopiesArrived(self.armed[name].spots) end,
                "this client's copies of what " .. name .. " put down")
            T.server(self, "siteClear", args)
        end
        T.returnHome(self)
    end,
    validate = function(self)
        for i, place in ipairs(VISITED_SITES) do
            local name, visit, armed = place[1], self.visits[i], self.armed[place[1]]
            local placing = visit.placing
            if expect(placing and placing.ready, name .. " never loaded on the server: " .. tostring(placing and placing.why)) then
                expect(placing.waiting == 0, name .. ": " .. placing.waiting .. " spots never went down (the log says why)")
                T.expectNoFailures(visit.check)
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
        T.server(self, "gardenLightsForgetHouse", { x = x, y = y })
        T.server(self, "sitesArm", { names = { name } })
        T.step(function() self.edge = T.need(self, edgeOfLoaded(self.server.gardenLightsForgetHouse), "a side of the house its reach crosses") end)
        T.step(function() self.teleportTo(self.edge.x + 0.5, self.edge.y + 0.5, 0) end)
        T.waitFor(self, function() return getSquare(x, y, 0) ~= nil end, "the house loaded at the edge", T.CHUNK_FRAMES)
        waitGameMinutes(self, SETTLE_MINUTES)
        T.serverInto(self, "atEdge", "gardenLightsHouse", { x = x, y = y })
        T.visitUntil(self, x, y, name, "gardenLightsHouse", { x = x, y = y }, function(answer) return answer.rolled end)
        local function args() return { name = name, spots = self.server.sitesArm[name].spots } end
        T.server(self, "siteVisited", args)
        T.server(self, "gardenLightsClearHouse", { x = x, y = y })
        T.server(self, "siteClear", args)
        T.returnHome(self)
    end,
    validate = function(self)
        local atEdge, atHouse = self.atEdge, self.server.gardenLightsHouse
        if expect(atEdge.loaded and not atEdge.surroundings, "standing at the edge, the house loaded " .. tostring(atEdge.loaded)
            .. " and its surroundings " .. tostring(atEdge.surroundings)) then
            expect(atEdge.promised and not atEdge.rolled and atEdge.lights == 0, "while its surroundings weren't loaded the house held "
                .. (atEdge.promised and "" or "no ") .. "saved promise, rolled " .. tostring(atEdge.rolled) .. ", with "
                .. atEdge.lights .. " lights")
        end
        expect(atHouse.rolled and atHouse.placed >= 1 and atHouse.placed <= atHouse.count.max and atHouse.lights == atHouse.placed,
            "the promised house was rolled " .. tostring(atHouse.rolled) .. " for " .. atHouse.placed .. " lights, and "
            .. atHouse.lights .. " stand around it")
        T.expectNoFailures(self.server.siteVisited)
    end,
})
