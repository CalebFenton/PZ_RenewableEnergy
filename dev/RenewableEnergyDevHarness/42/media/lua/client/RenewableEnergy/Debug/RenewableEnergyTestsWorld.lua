require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
require "RenewableEnergy/Sprites"
local Stash = require "RenewableEnergy/StashHouses"

-- Stash house, world spawn, solar site, garden light and arrow board tests. See
-- RenewableEnergyTestLib.lua for how the runner works. Stash houses, world spawns, sites, garden
-- lights and the arrow board's panels, box and frame live on the authority, so the tests build and
-- read them through the handlers in RenewableEnergyTestServer*.lua, and check what players see
-- on this client's copies. What players do (opening the battery box, the mechanics window, the
-- repairs, washing, hitching and driving) goes through the vanilla actions and the mod's own.

local T = RenewableEnergyTest
local test, expect, expectNear, player = T.test, T.expect, T.expectNear, T.player

local Sprites = RenewableEnergy.Sprites

-- Stash houses ----------------------------------------------------------------------------------

-- StashSystem gives up without an error when the stash building isn't a building, prepares only a
-- building whose bounds strictly contain the building square (doBuildingStash), and stocks the
-- crate only if its square is in a room of that building, so a wrong coordinate is an empty house.
test("renewable_energy_world_stash_houses_resolve", {
    run = function(self) T.server(self, "stashHousesResolve") end,
    validate = function(self) T.expectNoFailures(self.server.stashHousesResolve) end,
})

-- Unless Stash Houses is at 1 (none), the stashes join the list StashSystem reads, once however
-- often the game loads.
test("renewable_energy_world_stashes_register_by_option", {
    run = function(self) T.server(self, "stashRegister") end,
    validate = function(self)
        local answer = self.server.stashRegister
        local results, expected = answer.results, answer.houses
        expect(not results[1].registered and results[1].count == 0, "Stash Houses 1 registered stashes")
        for _, mode in ipairs({ 2, 3, 4 }) do
            expect(results[mode].registered, "Stash Houses " .. mode .. " did not register")
            expect(results[mode].count == expected,
                "Stash Houses " .. mode .. " listed " .. results[mode].count .. " stashes, expected " .. expected)
        end
    end,
})

-- A found stash map shows the stash's stamps and notes. A symbol the game doesn't define or a
-- note without a translation is dropped or shown as its key; the map is annotated where loot
-- makes it.
test("renewable_energy_world_stash_maps_annotated", {
    run = function(self) T.server(self, "stashMapsAnnotate") end,
    validate = function(self)
        local symbols = MapSymbolDefinitions.getInstance()
        for stashMap in pairs(Stash.descriptions) do
            local annotations = stashMap.annotations or {}
            expect(#annotations > 0, stashMap.name .. " has no annotations")
            for _, annotation in ipairs(annotations) do
                if annotation.symbol then
                    expect(symbols:getSymbolById(annotation.symbol) ~= nil,
                        stashMap.name .. ": unknown map symbol " .. annotation.symbol)
                else
                    expect(annotation.text and getTextOrNull(annotation.text) ~= nil,
                        stashMap.name .. ": untranslated note " .. tostring(annotation.text))
                end
            end
        end
        T.expectNoFailures(self.server.stashMapsAnnotate)
    end,
})

local RELIST_CASES = {
    { visited = false, read = false, relisted = true },
    { visited = true, read = false, relisted = false },
    { visited = false, read = true, relisted = false },
}

-- A house missing from StashSystem's possible stashes goes back on the list unless someone
-- entered it or read its map, so a map found later leads to a house still untouched. Each house
-- goes through every case and is put back as it was.
test("renewable_energy_world_unfound_stash_relisted", {
    run = function(self) T.server(self, "stashRelist", { cases = RELIST_CASES }) end,
    validate = function(self)
        for _, result in ipairs(self.server.stashRelist.results) do
            local case = RELIST_CASES[result.case]
            expect(result.relisted == case.relisted, string.format("%s, %s and %s, was %s", result.name,
                case.visited and "entered" or "never entered", case.read and "its map read" or "its map unread",
                result.relisted and "relisted" or "not relisted"))
        end
    end,
})

-- Stash Houses 3 and 4 stock the houses that have a knownOnStart chance, through the engine, and
-- only those; none of them may then show on the world map as a map already read.
test("renewable_energy_world_known_on_start_stocks_and_stays_hidden", {
    run = function(self) T.server(self, "stashKnownOnStart") end,
    validate = function(self)
        for name, house in pairs(self.server.stashKnownOnStart.houses) do
            expect(not house.read, name .. " is marked as read")
            expect(house.queued == house.hasChance,
                name .. (house.queued and " was stocked from the start" or " was not stocked from the start"))
        end
    end,
})

-- The prepper's map drops from survivalist and bandit corpses, whichever outfit variant they wear,
-- and every corpse list a map names exists.
test("renewable_energy_world_prepper_map_targets", {
    run = function(self) T.server(self, "prepperMapTargets") end,
    validate = function(self) T.expectNoFailures(self.server.prepperMapTargets) end,
})

-- A map item of the mod's own shows the area of its stash house, found or not: its Map id is the
-- stash name, which UI/MapDefinitions.lua draws. Vanilla town maps keep their own look.
test("renewable_energy_world_stash_map_items_draw_their_area", {
    validate = function()
        for stashMap in pairs(Stash.descriptions) do
            if string.find(stashMap.item, "^RenewableEnergy%.") then
                local map = instanceItem(stashMap.item)
                if expect(map ~= nil and instanceof(map, "MapItem"), stashMap.item .. " is not a map") then
                    expect(map:getMapID() == stashMap.name, stashMap.item .. " has Map id " .. tostring(map:getMapID()))
                end
                expect(type(LootMaps.Init[stashMap.name]) == "function", stashMap.name .. " has no map area")
            else
                expect(LootMaps.Init[stashMap.name] == nil, stashMap.name .. " overrides its town map's look")
            end
        end
    end,
})

-- With Stash Houses at 2 or 3 every stash's map goes into its outfits' corpse loot, once; at 1 or
-- 4 none does.
test("renewable_energy_world_stash_maps_in_corpse_loot", {
    run = function(self) T.server(self, "stashMapsInCorpseLoot") end,
    validate = function(self)
        for _, found in ipairs(self.server.stashMapsInCorpseLoot.found) do
            local wanted = (found.mode == 2 or found.mode == 3) and 1 or 0
            local label = "Stash Houses " .. found.mode .. ": " .. found.where
            expect(found.count == wanted, label .. " " .. found.count .. " times")
            expect(wanted == 0 or found.weight == found.rarity, label .. " at weight " .. tostring(found.weight))
        end
    end,
})

-- World spawns -----------------------------------------------------------------------------------

local MODULE = "RenewableEnergy.SolarModule"

local function inRange(value, range)
    return value >= range.min and value <= range.max
end

-- A tuned range read from the authority's WorldSpawns: the test checks spawns against it, so it
-- must itself be one a player can meet, from `lowest` up to `highest`.
local function expectSaneRange(range, what, lowest, highest)
    expect(range.min >= lowest and range.min <= range.max and range.max <= highest,
        what .. " runs from " .. range.min .. " to " .. range.max)
end

local function expectFoundCharges(charges, what)
    local range = RenewableEnergy.Specs.foundCharge
    for _, charge in ipairs(charges) do
        expect(inRange(charge, range), what .. " holds a battery at " .. charge .. ", expected " .. range.min .. " to " .. range.max)
    end
end

-- How many items this client's copy of the container on `square` (the first object of `sprite`)
-- holds, or nil without one.
local function copyItems(square, sprite)
    local object = T.objectWithSprite(square, sprite)
    local container = object and object:getContainer()
    return container and container:getItems():size()
end

-- Stock names of WorldSpawns.BANK_STOCK, one per bank tier.
local SPAWNED_BANKS = { "shed", "electronicsStorage", "powerYard" }

-- A bank appears stocked with era batteries at a part charge, explored so that neither its room's
-- loot nor loot respawn ever adds to it, and players see what it holds. Placing needs no player, as
-- on a dedicated server.
test("renewable_energy_world_bank_spawns_stocked", {
    sandbox = { LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        local squares = T.need(self, T.squares(self, #SPAWNED_BANKS, { indoors = true }), "free indoor squares for banks")
        if not squares then return end
        self.banks = {}
        for i, stockName in ipairs(SPAWNED_BANKS) do
            local square = squares[i]
            T.server(self, "worldBank", { x = square:getX(), y = square:getY(), z = square:getZ(), stock = stockName })
            T.step(function()
                local bank = self.server.worldBank
                bank.square, bank.stockName = square, stockName
                self.banks[i] = bank
                T.need(self, bank.placed, "a " .. stockName .. " bank")
            end)
        end
        T.server(self, "worldSpawnStock", { names = SPAWNED_BANKS })
        T.waitForCopy(function()
            for _, bank in ipairs(self.banks) do
                if copyItems(bank.square, bank.sprite) ~= bank.stock.items then
                    return false
                end
            end
            return true
        end)
        T.step(function()
            for _, bank in ipairs(self.banks) do
                bank.copyItems = copyItems(bank.square, bank.sprite)
            end
        end)
    end,
    validate = function(self)
        local stocks = self.server.worldSpawnStock.banks
        for _, bank in ipairs(self.banks) do
            local stock = stocks[bank.stockName]
            local what = "the " .. bank.stockName .. " bank"
            local count = #bank.stock.charges
            expect(bank.sprite == Sprites[stock.sprite], what .. " has the wrong tile")
            expect(bank.stock.explored, what .. " is not explored")
            expectSaneRange(stock.batteries, "the battery count of " .. what, 1, math.huge)
            expect(inRange(count, stock.batteries),
                count .. " batteries in " .. what .. ", expected " .. stock.batteries.min .. " to " .. stock.batteries.max)
            expectFoundCharges(bank.stock.charges, what)
            expect(bank.copyItems == bank.stock.items,
                "this client sees " .. tostring(bank.copyItems) .. " items in " .. what .. ", which holds " .. bank.stock.items)
        end
    end,
})

-- Banks only work indoors, so a world spawn never puts one on an outdoor square.
test("renewable_energy_world_bank_refused_outdoors", {
    run = function(self)
        local square = (T.need(self, T.squares(self, 1), "a free outdoor square") or {})[1]
        if not square then return end
        T.server(self, "worldBank", { x = square:getX(), y = square:getY(), z = square:getZ(), stock = "shed" })
    end,
    validate = function(self)
        expect(not self.server.worldBank.placed, "a bank was placed outdoors")
        expect(not self.server.worldBank.boxOnSquare, "a battery box stands outdoors")
    end,
})

-- Bank tiers whose tile is a battery box, which has no slot for a charge controller.
local BOX_TILES = { batteryBoxWood = true, batteryBoxMetal = true }

-- Over many banks, each part turns up about as often as BANK_STOCK says, and a battery box never
-- comes with a charge controller.
test("renewable_energy_world_bank_stock_rates", {
    sandbox = { LRMBatteries = 1, LRMMisc = 1 },
    run = function(self) T.server(self, "bankStockRates", { samples = 2000, boxTiles = BOX_TILES }) end,
    validate = function(self) T.expectNoFailures(self.server.bankStockRates) end,
})

-- At 0 the battery option leaves world banks empty of batteries.
test("renewable_energy_world_bank_stock_option_zero", {
    sandbox = { LRMBatteries = 0, LRMMisc = 0 },
    run = function(self) T.server(self, "bankStockCount", { times = 20 }) end,
    validate = function(self)
        local items = self.server.bankStockCount.items
        expect(items == 0, items .. " items in banks with the options at 0")
    end,
})

test("renewable_energy_world_crate_spawns_stocked", {
    sandbox = { LRMSolarPanels = 1, LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        local square = (T.need(self, T.squares(self, 1, { indoors = true }), "a free indoor square") or {})[1]
        if not square then return end
        T.server(self, "worldCrate", { x = square:getX(), y = square:getY(), z = square:getZ(), stock = "kit" })
        T.server(self, "worldSpawnStock", { names = {} })
        T.waitForCopy(function()
            local crate = self.server.worldCrate
            return not crate.container or copyItems(square, Sprites.crate) == crate.stock.items
        end)
        T.step(function()
            local copy = T.objectWithSprite(square, Sprites.crate)
            self.copyItems = copyItems(square, Sprites.crate)
            self.copyOverlay = copy ~= nil and copy:getOverlaySprite() ~= nil
        end)
    end,
    validate = function(self)
        local crate, ranges = self.server.worldCrate, self.server.worldSpawnStock
        if not expect(crate.container, "the crate has no container") then
            return
        end
        expect(crate.type == "RenewableEnergySolarBox", "the crate holds a " .. crate.type)
        expect(crate.stock.explored, "the crate is not explored")
        local conditions = crate.stock.modules
        expect(#conditions >= 1 and #conditions <= 2, #conditions .. " modules in the crate, expected 1 or 2")
        expectSaneRange(ranges.cracked, "a cracked module's condition", 1, 100)
        expectSaneRange(ranges.weathered, "a weathered module's condition", 1, 100)
        for _, condition in ipairs(conditions) do
            expect(inRange(condition, ranges.cracked) or inRange(condition, ranges.weathered), "a crate module is at condition " .. condition)
        end
        local charges = crate.stock.charges
        expect(#charges >= 1 and #charges <= 2, #charges .. " batteries in the crate, expected 1 or 2")
        expectFoundCharges(charges, "the crate")
        expect(crate.overlay, "the full crate shows no overlay")
        expect(self.copyItems == crate.stock.items,
            "this client sees " .. tostring(self.copyItems) .. " items in the crate, which holds " .. crate.stock.items)
        expect(self.copyOverlay, "this client's copy of the full crate shows no overlay")
    end,
})

-- Cracked modules -------------------------------------------------------------------------------

-- Farm storage shelves get cracked modules, at cracked conditions, and a bedroom's furniture
-- none. At the highest option every farm storage shelf gets one, so that nothing is left to
-- chance; at the default the chance is small but there.
test("renewable_energy_world_cracked_modules", {
    sandbox = { LRMSolarPanels = 100 },
    run = function(self) T.server(self, "crackedModules", { samples = 200 }) end,
    validate = function(self) T.expectNoFailures(self.server.crackedModules) end,
})

-- Solar sites -----------------------------------------------------------------------------------

-- A site goes down once when its chunk loads, and its spot is forgotten, so loading the chunk
-- again places nothing. Its pump's pole mount holds 1 or 2 modules at site conditions, and
-- players see it.
test("renewable_energy_world_site_placed_once", {
    run = function(self)
        local square = (T.need(self, T.squares(self, 1), "a free outdoor square") or {})[1]
        if not square then return end
        T.server(self, "sitePlacedOnce", { x = square:getX(), y = square:getY(), z = square:getZ() })
        T.waitForCopy(function() return T.objectWithSprite(square, Sprites.rack.metal.S) ~= nil end)
        T.step(function() self.copy = T.objectWithSprite(square, Sprites.rack.metal.S) end)
    end,
    validate = function(self)
        T.expectNoFailures(self.server.sitePlacedOnce)
        expect(self.copy ~= nil, "this client never saw the site's rack")
    end,
})

-- Every site's spots make sense on the map: banks and crates in a room (banks only work indoors),
-- panels outdoors, wall panels on a building's wall, garden lights at a building, arrow boards
-- outdoors with a facing; each site has a unique name, a known kind, and the spots its kind uses.
test("renewable_energy_world_sites_placed_sensibly", {
    run = function(self) T.server(self, "sitesPlacedSensibly") end,
    validate = function(self) T.expectNoFailures(self.server.sitesPlacedSensibly) end,
})

-- Garden lights ---------------------------------------------------------------------------------

-- A house rolled for garden lights is never rolled again: the roll is kept in the world's
-- ModData. Its lights stand outdoors on the ground near the house, charged, and players see them.
-- The house near the start was already rolled when its chunk loaded, so the test forgets that roll
-- first.
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
        T.waitForCopy(function() return copies() == #self.server.gardenLightsOnce.lights end)
        T.step(function() self.copies = copies() end)
    end,
    validate = function(self)
        local answer = self.server.gardenLightsOnce
        local count = answer.count
        -- The tuned count comes from the authority; a house that is rolled lights must get some.
        expect(count.min >= 1 and count.min <= count.max, "houses get " .. count.min .. " to " .. count.max .. " lights")
        expect(answer.first >= count.min and answer.first <= count.max, "the house got " .. answer.first .. " lights")
        expect(answer.rolled, "the house's roll was not kept")
        expect(answer.second == 0, "rolling the house again gave " .. answer.second .. " more lights")
        expect(#answer.lights == answer.first, #answer.lights .. " lights stand around the house, expected " .. answer.first)
        for _, light in ipairs(answer.lights) do
            local key = light.x .. "," .. light.y
            expect(light.outdoors, "a light stands indoors at " .. key)
            expectNear("a new light's charge", light.charge, answer.wh, 0.001)
        end
        expect(self.copies == #answer.lights, "this client sees " .. self.copies .. " of the " .. #answer.lights .. " new lights")
    end,
})

-- Frames to wait at each place for this client to load it, and at the start for it to load again.
-- Loading takes real time, so at an uncapped frame rate it takes many frames.
local VISIT_FRAMES = 6000
-- How long the server is given to roll the house at a place once this client has loaded it, and
-- how often it is asked.
local ROLL_MS, ROLL_POLL_MS = 60000, 250
-- Houses are rolled on the game minute after their surroundings load; a faster clock brings that
-- minute sooner.
local VISIT_SPEED = 10
-- How far around the start the squares must be loaded again before the next test: as far as
-- T.squares looks for free squares.
local HOME_RADIUS = 30

-- Whether every chunk within `radius` squares of the point is loaded: one square per chunk tells.
local function loadedAround(x, y, z, radius)
    for sx = x - radius, x + radius, 8 do
        for sy = y - radius, y + radius, 8 do
            if not getSquare(sx, sy, z) then
                return false
            end
        end
    end
    return getSquare(x + radius, y + radius, z) ~= nil
end

-- Lets the visits below move the character: a teleport from inside a timed action doesn't stick,
-- so OnTick makes the move that self.teleportTo(x, y, z) asks for. Puts the character back at the
-- start when the test ends, should a visit leave them elsewhere.
local function startVisits(self)
    local p = player()
    local start = { x = p:getX(), y = p:getY(), z = p:getZ() }
    T.defer(self, function()
        if math.abs(p:getX() - start.x) > 1 or math.abs(p:getY() - start.y) > 1 then
            p:teleportTo(start.x, start.y, start.z)
        end
    end)
    local target
    T.onTick(self, function()
        if target then
            p:teleportTo(target[1], target[2], target[3])
            target = nil
        end
    end)
    function self.teleportTo(x, y, z) target = { x, y, z } end
    return start
end

-- Queues a visit to `place` ({ x, y }): the character goes there, this client loads it, and the
-- authority is asked about the house nearest it until that house has been rolled for garden lights
-- or ROLL_MS pass. Leaves loaded, house, rolled and found (the neighbourhood) in `place`, and calls
-- done() from the queue when the visit is over, so that what comes next queues after it.
local function visitPlace(self, place, done)
    T.step(function() self.teleportTo(place[1] + 0.5, place[2] + 0.5, 0) end)
    T.waitUntil(function() return getSquare(place[1], place[2], 0) ~= nil end, VISIT_FRAMES)
    T.step(function()
        place.loaded = getSquare(place[1], place[2], 0) ~= nil
        local deadline = getTimestampMs() + ROLL_MS
        local function ask()
            T.server(self, "gardenLightsAt", { x = place[1], y = place[2], radius = 20 })
            T.step(function()
                local at = self.server.gardenLightsAt
                place.house, place.rolled, place.found = at.house, at.rolled, at.neighbourhood
                if not place.rolled and getTimestampMs() < deadline then
                    local again = getTimestampMs() + ROLL_POLL_MS
                    T.waitUntil(function() return getTimestampMs() >= again end, math.huge)
                    T.step(ask)
                else
                    done()
                end
            end)
        end
        ask()
    end)
end

-- Queues the character's way back to `start` ({ x, y, z }) and a wait for the squares around it
-- to load again; leaves in self.homeLoaded whether they did and in self.home where the character
-- ended up.
local function returnHome(self, start)
    local x, y = math.floor(start.x), math.floor(start.y)
    T.step(function() self.teleportTo(start.x, start.y, start.z) end)
    T.waitUntil(function() return loadedAround(x, y, start.z, HOME_RADIUS) end, VISIT_FRAMES)
    T.step(function()
        local p = player()
        self.homeLoaded = loadedAround(x, y, start.z, HOME_RADIUS)
        self.home = { x = p:getX(), y = p:getY(), z = p:getZ() }
    end)
end

-- The neighbourhood sets the chance: a rich street (Riverside's Rich loot zone) most, a trailer
-- park least, an ordinary street (the start, in Muldraugh) in between. A farmhouse counts as
-- ordinary. And a house far from the start is rolled once the character has been there. The
-- character visits each place in turn, staying until it has loaded and the authority has rolled
-- the house nearest it, and comes back once the start has loaded again.
test("renewable_energy_world_garden_light_neighbourhoods", {
    run = function(self)
        self.places = {
            { 6680, 5320, "rich" }, { 5370, 5945, "poor" }, { 7340, 5993, "ordinary" }, { 10835, 10144, "ordinary" },
        }
        T.setMultiplier(self, VISIT_SPEED)
        self.start = startVisits(self)
        -- Each visit queues the next from its last step.
        local function visit(i)
            if self.places[i] then
                visitPlace(self, self.places[i], function() visit(i + 1) end)
            else
                returnHome(self, self.start)
            end
        end
        visit(1)
    end,
    validate = function(self)
        for _, place in ipairs(self.places) do
            local where = place[1] .. "," .. place[2]
            if expect(place.loaded, where .. " never loaded") then
                expect(place.found == place[3], where .. " is " .. tostring(place.found) .. ", expected " .. place[3])
                if expect(place.house, "no house near " .. where) then
                    expect(place.rolled, "the house at " .. place.house .. " was never rolled for garden lights")
                end
            end
        end
        expect(self.homeLoaded, "the start never loaded again")
        local home, start = self.home or {}, self.start
        expect(home.z == start.z and math.abs(home.x - start.x) <= 1 and math.abs(home.y - start.y) <= 1,
            string.format("the character ended at %s,%s,%s, not back at the start", tostring(home.x), tostring(home.y),
                tostring(home.z)))
    end,
})

-- At 0 the Garden Lights option leaves every house without lights: the house near the start, rolled
-- again and again the way the world rolls it, never gets one. At the option's default an ordinary
-- street's chance would almost surely have given it some over this many rolls.
test("renewable_energy_world_garden_lights_option_zero", {
    sandbox = { GardenLights = 0 },
    run = function(self) T.server(self, "gardenLightsRolls", { rolls = 60 }) end,
    validate = function(self)
        local answer = self.server.gardenLightsRolls
        expect(answer.chance == 0, "houses get lights with chance " .. answer.chance .. " with the option at 0")
        expect(answer.placed == 0 and #answer.lights == 0,
            "with the option at 0 the rolls placed " .. answer.placed .. " lights, and " .. #answer.lights .. " stand around the house")
    end,
})

-- Arrow board -------------------------------------------------------------------------------------

local function isOpenGround(x, y, z)
    local square = getSquare(x, y, z)
    return square ~= nil and square:isOutside() and square:isFree(false) and not square:HasTree()
        and square:getVehicleContainer() == nil
end

-- The square nearest the character with open ground three squares across, from `ahead` squares
-- north of it to `behind` squares south, clear of the character: room for vehicles facing north.
local function openStrip(ahead, behind)
    local here = player():getSquare()
    local hx, hy, z = here:getX(), here:getY(), here:getZ()
    for radius = 1, 25 do
        for x, y in PZHarness.Fixtures.ring(hx, hy, radius) do
            local dx, dy = x - hx, y - hy
            local coversCharacter = math.abs(dx) <= 1 and -dy >= -ahead and -dy <= behind
            if not coversCharacter then
                local open = true
                for sx = x - 1, x + 1 do
                    for sy = y - ahead, y + behind do
                        open = open and isOpenGround(sx, sy, z)
                    end
                end
                if open then
                    return getSquare(x, y, z)
                end
            end
        end
    end
    return nil
end

-- The squares an arrow board takes north and south of its centre.
local TRAILER_AHEAD, TRAILER_BEHIND = 3, 3

local LEFT, RIGHT = "RenewableEnergyPanelLeft", "RenewableEnergyPanelRight"
local HOMEMADE = "RenewableEnergy.HomemadeSolarModule"
local BATTERY_BOX = "RenewableEnergyBatteryBox"
-- How long the server is given to show a change a client asked for.
local SERVER_MS = 15000

-- Queues an arrow board on open ground near the character, spawned by the authority with `args`
-- (see RenewableEnergyTestLibWorld.lua), and returns its T.placeVehicle handle.
local function spawnTrailer(self, args)
    local square = T.need(self, openStrip(TRAILER_AHEAD, TRAILER_BEHIND), "open ground for the arrow board")
    return square and T.placeVehicle(self, RenewableEnergy.ArrowBoard.SCRIPT, { square = square, args = args })
end

local function panelCondition(state, partId)
    local panel = state and state.panels[partId]
    return panel and panel.installed and panel.condition or nil
end

local function panelShown(state, partId)
    local panel = state and state.panels[partId]
    return panel and panel.shown or "?"
end

local function describePanels(state)
    local parts = {}
    for _, id in ipairs({ LEFT, RIGHT }) do
        table.insert(parts, string.format("%s at %s showing '%s'", id, tostring(panelCondition(state, id)), panelShown(state, id)))
    end
    return table.concat(parts, ", ")
end

-- Whether two states of the trailer have the same panels: modules, conditions and shown models.
local function samePanels(a, b)
    for _, id in ipairs({ LEFT, RIGHT }) do
        if panelCondition(a, id) ~= panelCondition(b, id) or panelShown(a, id) ~= panelShown(b, id) then
            return false
        end
    end
    return true
end

-- Queues a wait until this client's copy of the trailer shows the panels of the server's last
-- state, and leaves the copy's state in trailer.copy: what players see.
local function waitForPanelsCopy(trailer)
    T.waitForVehicleCopy(trailer, function(copy) return samePanels(copy, trailer.state) end)
    T.step(function() trailer.copy = T.copyState(trailer) end)
end

local function expectPanelsCopy(trailer)
    expect(samePanels(trailer.copy, trailer.state), "this client's copy shows " .. describePanels(trailer.copy)
        .. ", the server's " .. describePanels(trailer.state))
end

local function boxItems(state, fullType)
    local items = {}
    for _, item in ipairs(state and state.box and state.box.items or {}) do
        if not fullType or item.type == fullType then
            table.insert(items, item)
        end
    end
    return items
end

-- A spawned arrow board has a module on each panel, the first weathered and the second weathered
-- or cracked, each showing the model its condition calls for, to players too; its battery box
-- holds no modules, worn deep cycle batteries at a part charge, and at most one charge
-- controller; and the trailer turns up among junkyard and traffic jam vehicles.
test("renewable_energy_world_arrow_board_spawns_stocked", {
    sandbox = { LRMSolarPanels = 1, LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        self.trailer = spawnTrailer(self, { stocked = true })
        if not self.trailer then return end
        T.vehicleState(self, self.trailer)
        waitForPanelsCopy(self.trailer)
    end,
    validate = function(self)
        local ArrowBoard = RenewableEnergy.ArrowBoard
        for _, zone in ipairs({ "junkyard", "trafficjamn", "trafficjams" }) do
            expect(VehicleZoneDistribution[zone].vehicles[ArrowBoard.SCRIPT] ~= nil, "no arrow boards in " .. zone)
        end
        local state = self.trailer.state
        local left, right = panelCondition(state, LEFT), panelCondition(state, RIGHT)
        expect(left and left >= 60 and left <= 100, "its left panel's module is at " .. tostring(left))
        expect(right and (right >= 20 and right <= 50 or right >= 60 and right <= 100),
            "its right panel's module is at " .. tostring(right))
        expect(panelShown(state, LEFT) == "Whole", "its weathered left panel shows " .. panelShown(state, LEFT))
        local rightModel = right and right < 60 and "Cracked" or "Whole"
        expect(panelShown(state, RIGHT) == rightModel, "its right panel at " .. tostring(right) .. " shows " .. panelShown(state, RIGHT))
        expectPanelsCopy(self.trailer)
        if not expect(state.box ~= nil, "the arrow board has no battery box") then
            return
        end
        expect(#boxItems(state, MODULE) == 0, #boxItems(state, MODULE) .. " modules in the battery box")
        local batteries, charges = 0, {}
        for _, item in ipairs(boxItems(state)) do
            if item.charge then
                batteries = batteries + 1
                table.insert(charges, item.charge)
                -- Worn, but never better than a battery that has seen years of road work.
                expect(item.condition >= 0 and item.condition <= 80, "a battery in the box is at " .. item.condition .. "%")
            end
        end
        expect(batteries >= 4 and batteries <= 6, batteries .. " batteries in the battery box")
        expect(#boxItems(state, "RenewableEnergy.DeepCycleBattery") == batteries, "the battery box holds other batteries")
        expectFoundCharges(charges, "the battery box")
        local controllers = #boxItems(state, "RenewableEnergy.ChargeController")
        expect(controllers <= 1, "the battery box has " .. controllers .. " charge controllers")
    end,
})

-- A trailer spawned the plain way, as debug tools and the world's vehicle stories spawn vehicles,
-- which set every part's condition after its panels were stocked, keeps the stock conditions, and
-- each panel shows the model its condition calls for, to players too.
test("renewable_energy_world_arrow_board_plain_spawn_keeps_stock", {
    sandbox = { LRMSolarPanels = 1 },
    run = function(self)
        self.trailer = spawnTrailer(self, { recordStock = true })
        if not self.trailer then return end
        local trailer = self.trailer
        T.serverUntil(self, "arrowBoardStock", function() return T.vehicleArgs(trailer) end, function(reply)
            return panelCondition(reply.state, LEFT) == reply.stock[LEFT] and panelCondition(reply.state, RIGHT) == reply.stock[RIGHT]
        end)
        T.step(function()
            trailer.answer = self.server.arrowBoardStock
            trailer.state = trailer.answer.state
        end)
        waitForPanelsCopy(trailer)
    end,
    validate = function(self)
        local stock, state = self.trailer.answer.stock, self.trailer.state
        for _, id in ipairs({ LEFT, RIGHT }) do
            local condition = panelCondition(state, id)
            expect(stock[id] ~= nil and condition == stock[id],
                id .. " was stocked at " .. tostring(stock[id]) .. " and is at " .. tostring(condition))
            local model = condition and (RenewableEnergy.ArrowBoard.isCracked(condition) and "Cracked" or "Whole") or ""
            expect(panelShown(state, id) == model, id .. " at " .. tostring(condition) .. " shows '" .. panelShown(state, id) .. "'")
        end
        expectPanelsCopy(self.trailer)
    end,
})

-- A trailer from a save made before its panels were parts loads with them empty, and they get
-- their modules on that first load, once: panels taken off later stay off.
test("renewable_energy_world_arrow_board_old_trailer_gets_panels_once", {
    sandbox = { LRMSolarPanels = 1 },
    run = function(self)
        self.trailer = spawnTrailer(self)
        if not self.trailer then return end
        T.onVehicle(self, self.trailer, "arrowBoardOldPanels")
        T.step(function() self.trailer.state = self.trailer.answer.second end)
        waitForPanelsCopy(self.trailer)
    end,
    validate = function(self)
        local first, second = self.trailer.answer.first, self.trailer.answer.second
        local left, right = panelCondition(first, LEFT), panelCondition(first, RIGHT)
        expect(left and left >= 60, "the old trailer's left panel loaded with " .. tostring(left))
        expect(right ~= nil, "the old trailer's right panel loaded empty")
        expect(panelCondition(second, LEFT) == nil and panelCondition(second, RIGHT) == nil,
            "panels taken off came back on the next load")
        expect(panelShown(second, LEFT) == "" and panelShown(second, RIGHT) == "",
            "empty panels show " .. panelShown(second, LEFT) .. " and " .. panelShown(second, RIGHT))
        expectPanelsCopy(self.trailer)
    end,
})

-- Puts the character at the middle of one of the vehicle's areas: teleportTo rounds down to the
-- square's corner, which can fall outside a narrow area.
local function standIn(vehicle, area)
    local spot = vehicle:getAreaCenter(area)
    local p = player()
    p:teleportTo(spot:getX(), spot:getY(), vehicle:getZ())
    p:setX(spot:getX())
    p:setY(spot:getY())
end

-- Its battery box, unlocked, opens only with its lid open, from beside it, and takes a battery a
-- player puts in.
test("renewable_energy_world_arrow_board_battery_box_opens_with_lid", {
    instant = true,
    run = function(self)
        -- A spawned vehicle may lack parts, and the box opens freely without its lid.
        self.trailer = spawnTrailer(self, { repair = true })
        if not self.trailer then return end
        local trailer, p = self.trailer, player()
        -- Most trailers spawn with the box padlocked.
        T.onVehicle(self, trailer, "setTrailer", { lidOpen = false, lidLocked = false })
        T.waitForCopy(function() return not trailer.vehicle:getPartById("TrunkDoor"):getDoor():isLocked() end)
        T.give(self, "battery", { { type = "RenewableEnergy.DeepCycleBattery" } })
        T.step(function()
            -- A spawned trailer may come stocked, so count from what it already holds.
            self.before = #boxItems(trailer.state, "RenewableEnergy.DeepCycleBattery")
            local vehicle = trailer.vehicle
            local lid, box = vehicle:getPartById("TrunkDoor"), vehicle:getPartById(BATTERY_BOX)
            self.lid, self.box = lid, box
            if not (lid and lid:getDoor() and box and box:getItemContainer()) then return end
            standIn(vehicle, BATTERY_BOX)
            self.shutAccess = vehicle:canAccessContainer(box:getIndex(), p)
            -- What the trailer's menu does for Open Trunk.
            ISVehicleMenu.onOpenDoor(p, lid)
        end)
        T.waitForCopy(function() return self.lid and self.lid:getDoor() and self.lid:getDoor():isOpen() end)
        T.step(function()
            if not (self.lid and self.box) then return end
            self.openAccess = trailer.vehicle:canAccessContainer(self.box:getIndex(), p)
            ISTimedActionQueue.add(ISInventoryTransferAction:new(p, self.items.battery[1], p:getInventory(),
                self.box:getItemContainer()))
        end)
        T.awaitVehicleState(self, trailer, function(state)
            return #boxItems(state, "RenewableEnergy.DeepCycleBattery") > self.before
        end, SERVER_MS)
    end,
    validate = function(self)
        if not (expect(self.lid ~= nil and self.lid:getDoor() ~= nil, "the battery box has no lid")
                and expect(self.box ~= nil and self.box:getItemContainer() ~= nil, "the battery box holds nothing")) then
            return
        end
        expect(self.trailer.state.lid ~= nil and not self.trailer.state.lid.locked, "the battery box stayed locked")
        expect(not self.shutAccess, "the battery box opens with its lid shut")
        expect(self.trailer.state.lid.open, "opening the lid left it shut")
        expect(self.openAccess, "the battery box doesn't open beside it with its lid open")
        local after = #boxItems(self.trailer.state, "RenewableEnergy.DeepCycleBattery")
        expect(after == self.before + 1, "the battery box holds " .. after .. " deep cycles after one was put in, " .. self.before .. " before")
    end,
})

-- Whether this game draws the trailer's lid held still, open or shut, as T.lidPose reads it.
local function lidHeld(pose, open)
    return pose ~= nil and pose.clip ~= nil and not pose.playing and pose.open == (open and 1 or 0)
end

local function describeLid(pose)
    if not pose then
        return "no lid model"
    end
    return string.format("clip %s, %s, %s open", tostring(pose.clip), pose.playing and "swinging" or "still", tostring(pose.open))
end

-- The battery box lid swings open on its hinge when a player opens it and stays open, and swings
-- shut when they close it; it swings the same way in this game when someone else opens and closes
-- it, which vanilla shows only to the player who did (RenewableEnergy.ArrowBoard.swingLids). Each
-- swing passes the poses between shut and open, and the batteries come out only while it is open.
test("renewable_energy_world_arrow_board_lid_swings", {
    instant = true,
    run = function(self)
        self.trailer = spawnTrailer(self, { repair = true })
        if not self.trailer then return end
        local trailer, p = self.trailer, player()
        local LID = RenewableEnergy.ArrowBoard.LID
        T.onVehicle(self, trailer, "setTrailer", { lidOpen = false, lidLocked = false })
        T.waitForCopy(function()
            local door = trailer.vehicle:getPartById(LID):getDoor()
            return not door:isLocked() and not door:isOpen() and lidHeld(T.lidPose(trailer), false)
        end)
        T.step(function()
            self.shut = T.lidPose(trailer)
            standIn(trailer.vehicle, BATTERY_BOX)
        end)
        self.swings = {}
        -- Queues `act` and a wait until the lid stands held `open`, noting what it passed on the way.
        local function swing(name, open, act)
            local seen = { name = name, open = open }
            table.insert(self.swings, seen)
            T.step(act)
            T.waitForCopy(function()
                seen.pose = T.lidPose(trailer)
                if seen.pose and seen.pose.playing and seen.pose.open and seen.pose.open > 0.1 and seen.pose.open < 0.9 then
                    seen.between = true
                end
                return trailer.vehicle:getPartById(LID):getDoor():isOpen() == open and lidHeld(seen.pose, open)
            end)
            T.step(function()
                local vehicle = trailer.vehicle
                seen.access = vehicle:canAccessContainer(vehicle:getPartById(BATTERY_BOX):getIndex(), p)
            end)
        end
        -- What the trailer's menu does for Open Trunk and Close Trunk.
        swing("opening it", true, function() ISVehicleMenu.onOpenDoor(p, trailer.vehicle:getPartById(LID)) end)
        swing("closing it", false, function() ISVehicleMenu.onCloseDoor(p, trailer.vehicle:getPartById(LID)) end)
        swing("someone else opening it", true, function() T.onVehicle(self, trailer, "setTrailer", { lidOpen = true }) end)
        swing("someone else closing it", false, function() T.onVehicle(self, trailer, "setTrailer", { lidOpen = false }) end)
    end,
    validate = function(self)
        if not expect(lidHeld(self.shut, false), "the shut lid shows " .. describeLid(self.shut)) then
            return
        end
        expect(self.shut.clip == "Lid_closing", "the lid plays " .. tostring(self.shut.clip))
        for _, seen in ipairs(self.swings) do
            local ends = seen.open and "open" or "shut"
            expect(seen.between, seen.name .. " never swung the lid between shut and open")
            expect(lidHeld(seen.pose, seen.open), seen.name .. " left the lid showing " .. describeLid(seen.pose) .. ", not held " .. ends)
            expect(seen.access == seen.open, seen.name .. " left the batteries " .. (seen.access and "reachable" or "out of reach")
                .. " with the lid " .. ends)
        end
    end,
})

-- Queues putting the battery box's padlock on and its lid down, with what the box holds, and a
-- wait until this client's copy shows the lid locked; leaves the lid and the box in self.
local function padlockBox(self, trailer, box)
    T.onVehicle(self, trailer, "setTrailer", { lidOpen = false, lidLocked = true, box = box })
    T.waitForCopy(function()
        local lid = trailer.vehicle:getPartById("TrunkDoor")
        return lid and lid:getDoor() and lid:getDoor():isLocked() and not lid:getDoor():isOpen()
    end)
    T.step(function()
        self.lid, self.box = trailer.vehicle:getPartById("TrunkDoor"), trailer.vehicle:getPartById(BATTERY_BOX)
        standIn(trailer.vehicle, BATTERY_BOX)
    end)
end

-- A padlocked battery box stays shut when a player opens it as they would an unlocked one: the
-- trailer's Open Trunk tries the lock first, and nobody has the key. The refused unlock empties
-- the action queue (ISBaseTimedAction.stop), so it comes last and the checks read the copy here.
test("renewable_energy_world_arrow_board_locked_box_stays_shut", {
    instant = true,
    run = function(self)
        self.trailer = spawnTrailer(self, { repair = true })
        if not self.trailer then return end
        local trailer, p = self.trailer, player()
        padlockBox(self, trailer)
        T.step(function()
            self.canUnlock = trailer.vehicle:canUnlockDoor(self.lid, p)
            ISVehicleMenu.onOpenDoor(p, self.lid)
        end)
    end,
    validate = function(self)
        if not expect(self.lid ~= nil and self.box ~= nil, "the trailer has no lid or no battery box") then
            return
        end
        local door = self.lid:getDoor()
        expect(not self.canUnlock, "a character without a key can unlock the battery box")
        expect(door:isLocked() and not door:isOpen(), "opening the padlocked box left it "
            .. (door:isLocked() and "locked" or "unlocked") .. " and " .. (door:isOpen() and "open" or "shut"))
        expect(not self.trailer.vehicle:canAccessContainer(self.box:getIndex(), player()), "the padlocked box opens")
    end,
})

-- A padlocked battery box opens the way vanilla gets into a locked trunk without its key: the lid
-- comes off in the mechanics window with a wrench and vanilla's trunk lid skill, without its Basic
-- Mechanics recipe, and then a player takes the batteries out. Off, the lid shows no model. The
-- lid goes back on without the recipe too, unlocked and drawn shut, so the box shuts again. The
-- test reads canUninstallPart and canInstallPart itself, so in multiplayer the mechanics cheat can
-- shorten the actions, as with the panels.
test("renewable_energy_world_arrow_board_locked_box_opens_with_the_lid_off", {
    instant = true,
    run = function(self)
        self.trailer = spawnTrailer(self, { repair = true })
        if not self.trailer then return end
        local trailer, p = self.trailer, player()
        T.setPerk(self, Perks.Mechanics, 3)
        if isClient() then
            T.setMechanicsCheat(self, true)
        end
        T.give(self, "wrench", { { type = "Base.Wrench" } })
        padlockBox(self, trailer, { { type = "RenewableEnergy.DeepCycleBattery", charge = 0.5 } })
        T.waitForCopy(function() return self.box and self.box:getItemContainer():getItems():size() == 1 end)
        T.step(function()
            local vehicle = trailer.vehicle
            self.knewRecipe = p:isRecipeActuallyKnown("Basic Mechanics")
            self.lockedAccess = vehicle:canAccessContainer(self.box:getIndex(), p)
            self.canTakeOff = vehicle:canUninstallPart(p, self.lid)
            self.lidType = self.lid:getInventoryItem():getFullType()
            -- What the mechanics window does for Uninstall.
            ISVehiclePartMenu.onUninstallPart(p, self.lid)
        end)
        T.awaitVehicleState(self, trailer, function(state) return state.lid and not state.lid.installed end, SERVER_MS)
        T.waitForCopy(function() return self.lid and self.lid:getInventoryItem() == nil and T.copyState(trailer).lid.shown == "" end)
        T.step(function()
            self.lidOff = trailer.state
            self.lidOffCopy = { shown = T.copyState(trailer).lid.shown, pose = T.lidPose(trailer) }
            self.openAccess = trailer.vehicle:canAccessContainer(self.box:getIndex(), p)
            local battery = self.box:getItemContainer():getFirstType("RenewableEnergy.DeepCycleBattery")
            if battery then
                ISTimedActionQueue.add(ISInventoryTransferAction:new(p, battery, self.box:getItemContainer(), p:getInventory()))
            end
        end)
        T.awaitVehicleState(self, trailer, function(state) return #boxItems(state) == 0 end, SERVER_MS)
        T.waitForCopy(function() return p:getInventory():getFirstTypeRecurse("RenewableEnergy.DeepCycleBattery") ~= nil end)
        T.step(function()
            self.canPutBack = trailer.vehicle:canInstallPart(p, self.lid)
            local lid = p:getInventory():getFirstTypeRecurse(self.lidType)
            if lid then
                ISVehiclePartMenu.onInstallPart(p, self.lid, lid)
            end
        end)
        T.awaitVehicleState(self, trailer, function(state) return state.lid and state.lid.installed end, SERVER_MS)
        T.waitForCopy(function() return self.lid:getInventoryItem() ~= nil and lidHeld(T.lidPose(trailer), false) end)
        T.step(function()
            local door = self.lid:getDoor()
            self.lidBack = { installed = self.lid:getInventoryItem() ~= nil, locked = door:isLocked(), open = door:isOpen(),
                shown = T.copyState(trailer).lid.shown, pose = T.lidPose(trailer) }
        end)
    end,
    validate = function(self)
        if not expect(self.lid ~= nil and self.box ~= nil, "the trailer has no lid or no battery box") then
            return
        end
        expect(not self.knewRecipe, "the character knows Basic Mechanics, so the lid coming off proves nothing")
        expect(not self.lockedAccess, "the padlocked box opens with its lid on")
        expect(self.canTakeOff, "the mechanics window won't take the padlocked lid off")
        expect(self.lidOff and not self.lidOff.lid.installed, "the lid is still on the server's trailer")
        expect(self.openAccess, "the box doesn't open with its lid off")
        local off = self.lidOffCopy
        expect(off and off.shown == "" and off.pose == nil, "the lid taken off still shows '" .. tostring(off and off.shown)
            .. "', " .. describeLid(off and off.pose))
        expect(#boxItems(self.trailer.state) == 0, #boxItems(self.trailer.state) .. " items left in the box")
        expect(player():getInventory():getFirstTypeRecurse("RenewableEnergy.DeepCycleBattery") ~= nil,
            "the battery never reached the inventory")
        expect(self.canPutBack, "the mechanics window won't put the lid back on")
        local back = self.lidBack
        expect(back and back.installed and not back.locked and not back.open,
            "the lid put back is " .. (back and ((back.installed and "on" or "off") .. ", " .. (back.locked and "locked" or "unlocked")
                .. " and " .. (back.open and "open" or "shut")) or "unknown") .. ", expected on, unlocked and shut")
        expect(back and back.shown == "Default" and lidHeld(back.pose, false), "the lid put back shows '"
            .. tostring(back and back.shown) .. "', " .. describeLid(back and back.pose) .. ", expected Default held shut")
    end,
})

-- Its two 50 W panels charge the batteries in its box, the emptiest first: all of a pass goes to
-- the emptier battery while it has room, and once batteries fill, the rest goes unstored.
test("renewable_energy_world_arrow_board_panels_charge_the_emptiest_battery", {
    hour = 12,
    run = function(self)
        self.trailer = spawnTrailer(self)
        if not self.trailer then return end
        local trailer = self.trailer
        T.onVehicle(self, trailer, "setTrailer", {
            panels = { [LEFT] = { type = MODULE, condition = 100 }, [RIGHT] = { type = MODULE, condition = 100 } },
            box = { { type = "RenewableEnergy.DeepCycleBattery", charge = 0.6 }, { type = "RenewableEnergy.L16Battery", charge = 0.2 } },
        })
        T.onVehicle(self, trailer, "arrowBoardCharge", { hours = 1 })
        T.step(function() self.first = trailer.answer end)
        -- 21 Wh of room in the L-16 and 12.6 in the deep cycle: both fill, the rest is lost.
        T.onVehicle(self, trailer, "setTrailer", {
            box = { { type = "RenewableEnergy.DeepCycleBattery", charge = 0.99 }, { type = "RenewableEnergy.L16Battery", charge = 0.99 } },
        })
        T.onVehicle(self, trailer, "arrowBoardCharge", { hours = 1 })
        T.step(function() self.second = trailer.answer end)
    end,
    validate = function(self)
        -- The panels lie flat whichever way the trailer faces, so they see what a flat panel does.
        local hourWh = 100 * self.first.flatWh
        if not expect(hourWh > 34, "the sun at noon gives only " .. hourWh .. " Wh an hour, too little to fill both") then
            return
        end
        local deepCycle, l16 = boxItems(self.first.state)[1], boxItems(self.first.state)[2]
        expectNear("watt-hours stored in an hour", self.first.stored, hourWh, 0.001)
        expectNear("the emptier L-16's charge", l16.charge, 0.2 + hourWh / 2100, 0.0001)
        expectNear("the fuller deep cycle's charge", deepCycle.charge, 0.6, 0.0001)
        expectNear("watt-hours stored with little room", self.second.stored, 21 + 12.6, 0.01)
        local full = boxItems(self.second.state)
        expect(full[1].charge == 1 and full[2].charge == 1, "the batteries aren't full: " .. full[1].charge .. ", " .. full[2].charge)
    end,
})

-- Each installed panel makes its module's 50 W rating times its condition / 100: a whole module
-- and a half-cracked one make 75 W, a homemade module at 60 makes 30 W, and with no panels the
-- trailer stores nothing.
test("renewable_energy_world_arrow_board_charge_scales_with_panel_condition", {
    hour = 12,
    run = function(self)
        self.trailer = spawnTrailer(self)
        if not self.trailer then return end
        local trailer = self.trailer
        self.passes = {}
        local function pass(panels, box)
            T.onVehicle(self, trailer, "setTrailer", { panels = panels, box = box })
            T.onVehicle(self, trailer, "arrowBoardCharge", { hours = 1 })
            T.step(function() table.insert(self.passes, trailer.answer) end)
        end
        pass({ [LEFT] = { type = MODULE, condition = 100 }, [RIGHT] = { type = MODULE, condition = 50 } },
            { { type = "RenewableEnergy.L16Battery", charge = 0 } })
        pass({ [RIGHT] = {} })
        pass({ [LEFT] = { type = HOMEMADE, condition = 60 } })
        pass({ [LEFT] = {} })
    end,
    validate = function(self)
        local p = self.passes
        local flatWh = p[1].flatWh
        if not expect(flatWh > 0, "no sun at noon") then return end
        expectNear("watts of a whole and a half-cracked panel", p[1].watts, 75)
        expectNear("watt-hours they store in an hour", p[1].stored, 75 * flatWh, 0.001)
        expectNear("watts of the whole panel alone", p[2].watts, 50)
        expectNear("watts of a homemade module at 60", p[3].watts, 30)
        expectNear("watts with no panels", p[4].watts, 0)
        expectNear("watt-hours stored with no panels", p[4].stored, 0)
    end,
})

-- Taking a cracked panel off in the mechanics way gives the module at the panel's condition and
-- leaves no panel showing; putting another module on shows it, whole or cracked by its condition,
-- to players too. A multiplayer server times both actions in real time, so there the mechanics
-- cheat shortens them (T.setMechanicsCheat).
test("renewable_energy_world_arrow_board_panels_come_off_and_go_on", {
    instant = true,
    run = function(self)
        self.trailer = spawnTrailer(self)
        if not self.trailer then return end
        local trailer, p = self.trailer, player()
        T.setPerk(self, Perks.Mechanics, 2)
        T.setPerk(self, Perks.Electricity, 1)
        if isClient() then
            T.setMechanicsCheat(self, true)
        end
        T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = 35 } } })
        waitForPanelsCopy(trailer)
        T.give(self, "wrench", { { type = "Base.Wrench", equip = "primary" } })
        T.step(function()
            self.cracked = trailer.copy
            ISTimedActionQueue.add(ISUninstallVehiclePart:new(p, trailer.vehicle:getPartById(LEFT), 200))
        end)
        T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) == nil end, SERVER_MS)
        waitForPanelsCopy(trailer)
        T.waitForCopy(function() return p:getInventory():getFirstTypeRecurse(MODULE) ~= nil end)
        T.step(function()
            self.emptied, self.emptyCopy = trailer.state, trailer.copy
            local removed = p:getInventory():getFirstTypeRecurse(MODULE)
            self.removed = removed and removed:getCondition()
        end)
        T.give(self, "module", { { type = MODULE, condition = 90 } })
        T.step(function()
            -- Vanilla's install takes the time it is given even when actions are instant
            -- (ISInstallVehiclePart.new never asks getDuration), so the instant time is given.
            local time = p:isTimedActionInstant() and 1 or 200
            ISTimedActionQueue.add(ISInstallVehiclePart:new(p, trailer.vehicle:getPartById(LEFT), self.items.module[1], time))
        end)
        T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) ~= nil end, SERVER_MS)
        waitForPanelsCopy(trailer)
    end,
    validate = function(self)
        local state = self.trailer.state
        expect(panelShown(self.cracked, LEFT) == "Cracked", "this client's copy of a panel at 35 shows " .. panelShown(self.cracked, LEFT))
        expect(self.removed == 35, "the panel came off as " .. (self.removed and self.removed .. "%" or "nothing"))
        expect(panelCondition(self.emptied, LEFT) == nil and panelShown(self.emptied, LEFT) == "",
            "after taking it off the server's panel is at " .. tostring(panelCondition(self.emptied, LEFT)) .. " showing '"
            .. panelShown(self.emptied, LEFT) .. "'")
        expect(panelShown(self.emptyCopy, LEFT) == "", "this client's copy of the empty panel shows " .. panelShown(self.emptyCopy, LEFT))
        expect(panelCondition(state, LEFT) == 90, "the module went on at " .. tostring(panelCondition(state, LEFT)))
        expect(panelShown(state, LEFT) == "Whole", "a panel at 90 shows " .. panelShown(state, LEFT))
        expectPanelsCopy(self.trailer)
    end,
})

-- A panel is wired as well as bolted, so without Electrical 1 the mechanics window neither takes
-- one off nor puts one on, even with Mechanics 2 and a wrench, and a queued removal does nothing.
-- The refused removal empties the action queue, so it comes last and the checks read the copy.
test("renewable_energy_world_arrow_board_panels_need_electrical", {
    instant = true,
    run = function(self)
        self.trailer = spawnTrailer(self)
        if not self.trailer then return end
        local trailer, p = self.trailer, player()
        T.setPerk(self, Perks.Mechanics, 2)
        T.setPerk(self, Perks.Electricity, 0)
        T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = 90 }, [RIGHT] = {} } })
        waitForPanelsCopy(trailer)
        T.give(self, "kit", { { type = "Base.Wrench", equip = "primary" }, { type = MODULE, condition = 90 } })
        T.step(function()
            local vehicle = trailer.vehicle
            self.canTakeOff = vehicle:canUninstallPart(p, vehicle:getPartById(LEFT))
            self.canPutOn = vehicle:canInstallPart(p, vehicle:getPartById(RIGHT))
            ISTimedActionQueue.add(ISUninstallVehiclePart:new(p, vehicle:getPartById(LEFT), 200))
        end)
    end,
    validate = function(self)
        expect(not self.canTakeOff, "a panel comes off without Electrical")
        expect(not self.canPutOn, "a panel goes on without Electrical")
        local left = self.trailer.vehicle and self.trailer.vehicle:getPartById(LEFT)
        expect(left and left:getInventoryItem() ~= nil, "the panel came off without Electrical")
        expect(player():getInventory():getCountTypeRecurse(MODULE) == 1, "a module came off into the inventory")
    end,
})

-- The mechanics window offers to install an inventory item whose full type is in the part's item
-- types (ISVehicleMechanics, VehicleUtils.getItems), so each panel lists both modules as they are
-- named, without the mechanicType the game appends to a specific item; and repair() puts a module
-- back on an empty panel, where an appended name found no item.
test("renewable_energy_world_arrow_board_panels_take_real_modules", {
    run = function(self)
        self.trailer = spawnTrailer(self)
        if not self.trailer then return end
        T.onVehicle(self, self.trailer, "arrowBoardRepairAll")
    end,
    validate = function(self)
        local answer = self.trailer.answer
        for _, id in ipairs({ LEFT, RIGHT }) do
            local listed, types = answer.types[id], {}
            for _, fullType in ipairs(listed) do
                types[fullType] = true
            end
            expect(types[MODULE] and types[HOMEMADE], id .. " takes " .. table.concat(listed, ", "))
        end
        local left = answer.state.panels[LEFT]
        expect(left.installed and (left.type == MODULE or left.type == HOMEMADE),
            "repair() put " .. tostring(left.type or "nothing") .. " on the empty panel")
    end,
})

-- A crack, from a storm or a crash, takes 30 from a panel's module, as a storm takes from a module
-- on a mount, and shows it cracked, to players too; a storm cracks a trailer's panels as it would
-- flat panels.
test("renewable_energy_world_arrow_board_panels_crack", {
    sandbox = { StormDamage = true, StormDamageRate = 1000 },
    run = function(self)
        self.trailer = spawnTrailer(self)
        if not self.trailer then return end
        local trailer = self.trailer
        T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = 80 } } })
        T.onVehicle(self, trailer, "arrowBoardCrack", { part = LEFT })
        waitForPanelsCopy(trailer)
        T.step(function() self.crack = { state = trailer.state, copy = trailer.copy } end)
        T.onVehicle(self, trailer, "setTrailer", {
            panels = { [LEFT] = { type = MODULE, condition = 100 }, [RIGHT] = { type = MODULE, condition = 100 } },
        })
        -- A thousand hours at ten times the rate makes a crack all but certain.
        T.onVehicle(self, trailer, "arrowBoardStorm", { hours = 1000 })
        T.step(function()
            self.storm = trailer.answer
            T.setSandbox(self, "StormDamage", false)
        end)
        T.onVehicle(self, trailer, "arrowBoardStorm", { hours = 1000 })
        T.step(function() self.calm = trailer.answer end)
    end,
    validate = function(self)
        local crack = self.crack
        expect(panelCondition(crack.state, LEFT) == 50, "a crack left the panel at " .. tostring(panelCondition(crack.state, LEFT)))
        expect(panelShown(crack.state, LEFT) == "Cracked", "the cracked panel shows " .. panelShown(crack.state, LEFT))
        expect(panelShown(crack.copy, LEFT) == "Cracked", "this client's copy of the cracked panel shows " .. panelShown(crack.copy, LEFT))
        expect(self.storm.cracked == 2, "a long storm cracked " .. self.storm.cracked .. " panels, not both")
        local state = self.storm.state
        expect(panelCondition(state, LEFT) == 70 and panelCondition(state, RIGHT) == 70,
            "the storm left the panels at " .. tostring(panelCondition(state, LEFT)) .. " and " .. tostring(panelCondition(state, RIGHT)))
        expect(self.calm.cracked == 0, "a storm cracked panels with storm damage off")
    end,
})

local TOWING_CAR = "Base.OffRoad"
-- How far ahead of the car, and behind the trailer, the strip they stand on runs, in squares:
-- the car is pushed a few squares north.
local STRIP_AHEAD, STRIP_BEHIND = 7, 9
-- Frames to wait for the pair to join the cell and come to rest, to settle on the hitch, and to
-- be pulled along. The physics runs in real time, so at an uncapped frame rate each takes many
-- frames.
local VEHICLE_FRAMES = 3000
-- How close, in squares, the coupler sits on the hitch once the hitch has pulled the trailer in,
-- and how slow, in squares a second, the pair then rolls once it has settled.
local ON_HITCH, SETTLED_SPEED = 0.1, 0.2

local function hitchGap(car, trailer)
    local hitch = car:getTowingWorldPos("trailer", Vector3f.new())
    local coupler = trailer:getTowedByWorldPos("trailer", Vector3f.new())
    if not (hitch and coupler) then
        return math.huge
    end
    return math.sqrt((hitch:x() - coupler:x()) ^ 2 + (hitch:y() - coupler:y()) ^ 2)
end

local function inCell(vehicle)
    return getCell():getVehicles():contains(vehicle)
end

-- Queues a car and an arrow board on a strip of open ground, the trailer behind the car, both
-- whole, the trailer set up with `trailerArgs` if given (see the setTrailer handler), and a wait
-- until the game moves them. Leaves the handles in self.car and self.trailer and returns the strip
-- the car stands on, or nil without one.
local function createTowingPair(self, trailerArgs)
    local strip = T.need(self, openStrip(STRIP_AHEAD, STRIP_BEHIND), "open ground for a car and the arrow board")
    if not strip then return nil end
    local x, y, z = strip:getX(), strip:getY(), strip:getZ()
    local car = T.placeVehicle(self, TOWING_CAR, { square = strip, args = { repair = true } })
    local trailer = T.placeVehicle(self, RenewableEnergy.ArrowBoard.SCRIPT,
        { square = getSquare(x, y + 5, z), args = { repair = true } })
    self.car, self.trailer = car, trailer
    if trailerArgs then
        T.onVehicle(self, trailer, "setTrailer", trailerArgs)
    end
    -- The game moves, and checks the hitch of, only vehicles that have joined the cell. Single
    -- player then lets them settle where they dropped; a multiplayer client runs no physics for
    -- vehicles no player here drives or tows, so they never come to rest there.
    T.waitUntil(function()
        return inCell(car.vehicle) and inCell(trailer.vehicle)
            and (isClient() or car.vehicle:isAtRest() and trailer.vehicle:isAtRest())
    end, VEHICLE_FRAMES)
    return strip
end

-- Queues the character getting in at the wheel of self.car through the driver's door, and a wait
-- until they sit there.
local function enterDriver(self)
    local p, car = player(), self.car
    T.step(function()
        local outside = car.vehicle:getPassengerPosition(0, "outside")
        local door = car.vehicle:getWorldPos(outside:getOffset(), Vector3f.new())
        p:teleportTo(door:x(), door:y(), p:getZ())
        ISTimedActionQueue.add(ISEnterVehicle:new(p, car.vehicle, 0))
    end)
    T.waitUntil(function() return car.vehicle:isDriver(p) end, VEHICLE_FRAMES)
end

-- Queues lining up self.car and self.trailer as a player does: tow points within a square and the
-- pair parallel, facing north. Do it after a driver gets in, since from then on the driver's client
-- moves the car and the server's place for it no longer counts.
local function alignTowPoints(self)
    local car, trailer = self.car, self.trailer
    T.server(self, "lineUpTrailer", function()
        return { car = T.vehicleArgs(car), trailer = T.vehicleArgs(trailer), facing = "N" }
    end)
    -- And this client's copies, which take the server's places only when it next sends them.
    T.step(function() T.lineUpTrailer(car.vehicle, trailer.vehicle, "N") end)
    T.waitUntil(function() return hitchGap(car.vehicle, trailer.vehicle) < 1 end, VEHICLE_FRAMES)
end

-- Queues hitching self.trailer to self.car the way a player does, with vanilla's action, and a
-- wait until the hitch has pulled the trailer in and the pair has settled. Leaves in
-- self.hitchedAt a real time just after the hitch was made; a hitch that never forms fails the
-- test.
local function attachTrailer(self)
    local p, car, trailer = player(), self.car, self.trailer
    T.step(function()
        ISTimedActionQueue.add(ISAttachTrailerToVehicle:new(p, car.vehicle, trailer.vehicle, "trailer", "trailer"))
    end)
    -- The action hitches as it starts, so the hitch is older than its time since this. A test that
    -- tows runs instantly: at its real length the action would take two seconds, as long as the
    -- game spares a fresh hitch from snapping.
    T.step(function() self.hitchedAt = getTimestampMs() end)
    -- The hitch pulls the trailer in over the next physics steps.
    T.waitUntil(function()
        return trailer.vehicle:getVehicleTowedBy() == car.vehicle and hitchGap(car.vehicle, trailer.vehicle) < ON_HITCH
            and car.vehicle:getSpeed2D() < SETTLED_SPEED and trailer.vehicle:getSpeed2D() < SETTLED_SPEED
    end, VEHICLE_FRAMES)
    T.step(function()
        local hitched = trailer.vehicle:getVehicleTowedBy() == car.vehicle
        T.need(self, hitched, string.format("the trailer hitched to the car (driving %s, tow points %.2f apart)",
            tostring(car.vehicle:isDriver(p)), hitchGap(car.vehicle, trailer.vehicle)))
    end)
end

-- Queues a hitched car and arrow board (createTowingPair, with `opts.trailer`). With `opts.drive`
-- the character gets in at the wheel first, so the hitch is fresh when the test goes on; else they
-- stand beside the car's tow bar. Leaves self.car, self.trailer and self.hitchedAt.
local function towingPair(self, opts)
    opts = opts or {}
    local strip = createTowingPair(self, opts.trailer)
    if not strip then return end
    if opts.drive then
        enterDriver(self)
    end
    alignTowPoints(self)
    if not opts.drive then
        -- Beside the car's tow bar, out of the trailer's way; the runner puts the character back.
        T.step(function() player():teleportTo(strip:getX() + 2.5, strip:getY() + 3.5, strip:getZ()) end)
    end
    attachTrailer(self)
end

-- A push each frame, small enough that a frame adds only a few km/h, and the speeds a crash's jolt
-- and a bump's stop pushing at. The game applies a push for the frame's length of physics time
-- (BaseVehicle.applyAccumulatedImpulsesFromHitObjectsToPhysics), so one push gives a different
-- speed at each frame rate; pushing up to a measured speed doesn't. Even at 60 frames a second
-- the crash's push takes well under the watcher's quarter second.
local PUSH, CRASH_KMH, BUMP_KMH = 1000, 35, 6

-- How long, in real milliseconds, a hitch holds whatever jolts it (Bullet.onVehicleConstraintImpulse),
-- and a push that snaps an older hitch in its first frames, well before the trailer has sped up by
-- a crash's worth.
local FRESH_HITCH_MS, SNAP_PUSH = 2000, 5000

-- The game cracks the panels of a trailer jolted as hard as a crash, and leaves them be after a
-- bump: the side that runs the trailer's physics watches its velocity, which is the client of the
-- player driving the car that tows it, and asks the server to crack them (in single player it
-- cracks them itself). The jolt is a push on the trailer while it is hitched to the character's
-- car, soon enough after hitching that the hitch holds, or with `snap` late enough that the jolt
-- snaps the hitch, which the watcher then follows for a moment longer: two cases, each a jolt of
-- its own.
local function crashTest(name, targetKmh, expected, snap)
    test(name, {
        instant = true,
        run = function(self)
            towingPair(self, { drive = true, trailer = {
                box = {}, panels = { [LEFT] = { type = MODULE, condition = 90 }, [RIGHT] = { type = MODULE, condition = 90 } },
            } })
            if not self.trailer then return end
            local trailer = self.trailer
            if snap then
                T.waitUntil(function() return getTimestampMs() - self.hitchedAt > FRESH_HITCH_MS end, VEHICLE_FRAMES)
            end
            self.peak = 0
            -- Until the car has stopped, so that the next test doesn't begin with the character at
            -- the wheel of a moving car, and the trailer too while hitched, so that a crack a bump
            -- caused would show; a trailer the jolt set loose coasts on for a while.
            T.waitUntil(function()
                local vehicle = trailer.vehicle
                local speed = math.abs(vehicle:getCurrentSpeedKmHour())
                if not self.pushed then
                    if speed >= targetKmh then
                        self.pushed = true
                    else
                        vehicle:applyImpulseGeneric(vehicle:getX(), vehicle:getY(), vehicle:getZ(), 0, -1, 0, snap and SNAP_PUSH or PUSH)
                    end
                end
                self.peak = math.max(self.peak, speed)
                if not self.snapSpeed and vehicle:getVehicleTowedBy() == nil then
                    self.snapSpeed = speed
                    self.hitchAgeMs = getTimestampMs() - self.hitchedAt
                end
                return self.pushed and self.car.vehicle:isAtRest() and (self.snapSpeed ~= nil or vehicle:isAtRest())
            end, 6000)
            T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) ~= 90 end,
                expected == 90 and 0 or SERVER_MS)
        end,
        validate = function(self)
            local state = self.trailer.state
            if snap then
                expect(self.snapSpeed ~= nil, string.format("the jolt to %.1f km/h left the trailer hitched", self.peak))
            else
                expect(self.snapSpeed == nil, string.format("the jolt snapped a hitch over %s ms old at %s km/h",
                    tostring(self.hitchAgeMs), tostring(self.snapSpeed)))
            end
            expect(panelCondition(state, LEFT) == expected and panelCondition(state, RIGHT) == expected,
                string.format("a jolt to %.1f km/h%s left the panels at %s and %s", self.peak,
                    self.snapSpeed and string.format(", snapping the hitch at %.1f,", self.snapSpeed) or "",
                    tostring(panelCondition(state, LEFT)), tostring(panelCondition(state, RIGHT))))
        end,
    })
end
crashTest("renewable_energy_world_arrow_board_crash_cracks_panels", CRASH_KMH, 60)
crashTest("renewable_energy_world_arrow_board_bump_leaves_panels", BUMP_KMH, 90)
crashTest("renewable_energy_world_arrow_board_crash_snapping_the_hitch_cracks_panels", CRASH_KMH, 60, true)

-- The server takes a crash only from the player driving the car that tows the trailer: anyone
-- else's crash command, here the character's while standing beside the hitched pair, cracks
-- nothing.
test("renewable_energy_world_arrow_board_crash_command_needs_the_driver", {
    mpOnly = "single player cracks the panels where it watches the trailer; only a multiplayer client sends the crash command",
    instant = true,
    run = function(self)
        towingPair(self, { trailer = { panels = { [LEFT] = { type = MODULE, condition = 90 } } } })
        if not self.trailer then return end
        T.step(function()
            sendClientCommand(player(), "RenewableEnergyArrowBoard", "crashed", { vehicle = self.trailer.id, car = self.car.id })
        end)
        -- The command and a state request go out in order, so the state is read after the
        -- command was handled.
        T.vehicleState(self, self.trailer)
    end,
    validate = function(self)
        local left = panelCondition(self.trailer.state, LEFT)
        expect(left == 90, "a crash command from a player not driving left the panel at " .. tostring(left))
    end,
})

-- Repair Cracked Panel takes Repair Cracked Module's screwdriver (kept), glass pane, epoxy and
-- electric wire, needs its Electricity 3 and gives its XP, and adds 30 to the panel's module up
-- to the factory module's 80.
local function repairTest(name, from, to)
    test(name, {
        instant = true,
        run = function(self)
            self.trailer = spawnTrailer(self)
            if not self.trailer then return end
            local trailer, p = self.trailer, player()
            T.setPerk(self, Perks.Electricity, 3)
            T.onVehicle(self, trailer, "setTrailer", { panels = { [LEFT] = { type = MODULE, condition = from } } })
            waitForPanelsCopy(trailer)
            T.give(self, "inputs", { { type = "Base.Screwdriver" }, { type = "Base.GlassPanel" }, { type = "Base.Epoxy" },
                { type = "Base.ElectricWire" } })
            -- The XP the authority's character has before and after; a client's copy can still be
            -- getting XP the test before gave.
            T.server(self, "electricityAward", { xp = 0 })
            T.step(function()
                self.epoxyUses = self.items.inputs[3]:getCurrentUses()
                self.xp = self.server.electricityAward.xp
                ISTimedActionQueue.add(RenewableEnergyAction:new(p, RenewableEnergyAction.REPAIR_PANEL, nil, nil, trailer.vehicle,
                    nil, nil, LEFT))
            end)
            T.awaitVehicleState(self, trailer, function(state) return panelCondition(state, LEFT) ~= from end, SERVER_MS)
            T.count(self, "left", { "Base.Screwdriver", "Base.GlassPanel", "Base.ElectricWire", "Base.Epoxy" })
            T.server(self, "electricityAward", { xp = 0 })
            T.step(function() self.gainedXp = self.server.electricityAward.xp - self.xp end)
            -- What the game gives this character for the recipe's xpAward, through the call
            -- CraftRecipe.addXP makes.
            T.server(self, "electricityAward", { xp = RenewableEnergy.Recipes.moduleRepairRecipe():getXPAward(0):getAmount() })
            waitForPanelsCopy(trailer)
        end,
        validate = function(self)
            -- The queue empties when an action fails, which skips the steps after it.
            local left = self.counts.left or {}
            local condition = panelCondition(self.trailer.state, LEFT)
            expect(condition == to, "the repair took the panel from " .. from .. " to " .. tostring(condition))
            expectPanelsCopy(self.trailer)
            expect(left["Base.Screwdriver"] == 1, "the repair used up the screwdriver")
            expect(left["Base.GlassPanel"] == 0, "the repair left the glass pane")
            expect(left["Base.ElectricWire"] == 0, "the repair left the wire")
            local epoxy = player():getInventory():getFirstTypeRecurse("Base.Epoxy")
            local epoxyLeft = epoxy and epoxy:getCurrentUses() or 0
            expect(epoxyLeft == (self.epoxyUses or 0) - 1, "the epoxy went from " .. tostring(self.epoxyUses) .. " uses to " .. epoxyLeft)
            expect(self.gainedXp and self.gainedXp > 0, "the repair gave no Electricity XP")
            local award = self.server.electricityAward
            expectNear("Electricity XP from the repair", self.gainedXp, award and award.gained or -1, 0.01)
        end,
    })
end
repairTest("renewable_energy_world_arrow_board_repair_mends_a_cracked_panel", 35, 65)
repairTest("renewable_energy_world_arrow_board_repair_stops_at_80", 55, 80)

-- The car is pushed whenever it rolls slower than this, in squares a second, until the trailer
-- has followed it TOW_SQUARES. Pushed every frame, it would speed off the open strip, and a crash
-- snaps a hitch more than two seconds old (Bullet.onVehicleConstraintImpulse).
local PUSH_SPEED = 5
local TOW_SQUARES = 2
-- A car with nobody at the wheel holds its brakes, so each push has to beat them.
local PUSH_IMPULSE = 6000

-- It spawns, a vanilla car hitches it with the game's own action, and when the car is pushed north
-- the trailer follows, still on the hitch, on the server too.
test("renewable_energy_world_arrow_board_towed_by_car", {
    instant = true,
    run = function(self)
        towingPair(self)
        if not self.trailer then return end
        local car, trailer = self.car, self.trailer
        local function towed()
            local vehicle = trailer.vehicle
            return math.sqrt((vehicle:getX() - self.start.x) ^ 2 + (vehicle:getY() - self.start.y) ^ 2)
        end
        T.step(function()
            self.start = { x = trailer.vehicle:getX(), y = trailer.vehicle:getY() }
        end)
        T.waitUntil(function()
            if towed() >= TOW_SQUARES then
                return true
            end
            local vehicle = car.vehicle
            if vehicle:getSpeed2D() < PUSH_SPEED then
                vehicle:applyImpulseGeneric(vehicle:getX(), vehicle:getY(), vehicle:getZ(), 0, -1, 0, PUSH_IMPULSE)
            end
            return false
        end, VEHICLE_FRAMES)
        T.step(function()
            self.moved = towed()
            self.gap = hitchGap(car.vehicle, trailer.vehicle)
            self.towedBy = trailer.vehicle:getVehicleTowedBy() == car.vehicle
        end)
        T.awaitVehicleState(self, trailer, function(state)
            return math.sqrt((state.x - self.start.x) ^ 2 + (state.y - self.start.y) ^ 2) >= TOW_SQUARES
        end, SERVER_MS)
    end,
    validate = function(self)
        if not expect(self.moved ~= nil, "the pair was never pushed: the queue emptied before") then
            return
        end
        expect(self.towedBy, "the trailer is not hitched to the car")
        expect(self.moved >= TOW_SQUARES, string.format("the trailer moved %.2f squares behind the pushed car", self.moved))
        expect(self.gap < ON_HITCH, string.format("the trailer's coupler is %.2f squares off the car's hitch", self.gap))
        local state = self.trailer.state
        expect(state.towedBy == self.car.id, "the server's trailer is towed by " .. tostring(state.towedBy) .. ", not the car")
        local moved = math.sqrt((state.x - self.start.x) ^ 2 + (state.y - self.start.y) ^ 2)
        expect(moved >= TOW_SQUARES, string.format("the server's trailer moved %.2f squares", moved))
    end,
})

-- How long a freshly spawned vehicle is given to fall onto its wheels before it counts as at rest:
-- it can read as at rest before its physics has run.
local SETTLE_MS = 1000

-- Unhitched and left on its own, it comes to rest on its wheels and coupler, as vanilla's Trailer
-- does (up vector dot 0.989, about 8.5 degrees nose down). Without its physics shapes it rests on
-- the chassis box's front edge at 0.897.
test("renewable_energy_world_arrow_board_stands_alone", {
    spOnly = "a dedicated server runs no vehicle physics and a client only those it drives, tows or bumps, so nothing settles a trailer left alone",
    run = function(self)
        self.trailer = spawnTrailer(self)
        if not self.trailer then return end
        local spawnedMs
        T.step(function() spawnedMs = getTimestampMs() end)
        T.waitUntil(function()
            local vehicle = self.trailer.vehicle
            return getTimestampMs() - spawnedMs > SETTLE_MS and inCell(vehicle) and vehicle:isAtRest()
        end, VEHICLE_FRAMES)
    end,
    validate = function(self)
        local vehicle = self.trailer.vehicle
        expect(vehicle:isAtRest(), "it never came to rest")
        local up = vehicle:getUpVectorDot()
        expect(up > 0.98, string.format("it came to rest tipped over (up vector dot %.3f)", up))
    end,
})

local FRAME_FRONT, FRAME_BACK = "EngineDoor", "TruckBed"

local function frameCondition(state, partId)
    local part = state and state.frame[partId]
    return part and part.installed and part.condition or nil
end

-- The game's own crash damage, which a car's crash passes on to the trailer it tows
-- (BaseVehicle.crash), dents the front of the frame in a front crash and the back in a rear one;
-- the mechanics window lists neither part.
test("renewable_energy_world_arrow_board_frame_dents_in_crashes", {
    run = function(self)
        self.trailer = spawnTrailer(self, { repair = true })
        if not self.trailer then return end
        local trailer = self.trailer
        T.onVehicle(self, trailer, "vehicleCrash", { amount = 40, front = true })
        T.step(function() self.front = trailer.state end)
        T.onVehicle(self, trailer, "vehicleCrash", { amount = 40, front = false })
    end,
    validate = function(self)
        for _, id in ipairs({ FRAME_FRONT, FRAME_BACK }) do
            local part = self.front.frame[id]
            expect(part ~= nil and part.category == "nodisplay", id .. " shows in the mechanics window")
        end
        local front, back = frameCondition(self.front, FRAME_FRONT), frameCondition(self.front, FRAME_BACK)
        expect(front and front < 100, "a front crash left the front of the frame at " .. tostring(front))
        expect(back == 100, "a front crash took the back of the frame to " .. tostring(back))
        back = frameCondition(self.trailer.state, FRAME_BACK)
        expect(back and back < 100, "a rear crash left the back of the frame at " .. tostring(back))
    end,
})

-- A trailer from a save made before its frame was parts loads with them empty and the random
-- colour it spawned with, and gets a frame and the script's colour on that load.
test("renewable_energy_world_arrow_board_old_trailer_gets_frame", {
    run = function(self)
        self.trailer = spawnTrailer(self)
        if not self.trailer then return end
        T.onVehicle(self, self.trailer, "arrowBoardOldFrame", { hsv = { 0.3, 0.9, 0.8 } })
    end,
    validate = function(self)
        local answer = self.trailer.answer
        for _, frame in ipairs(RenewableEnergy.ArrowBoard.FRAME) do
            expect(frameCondition(answer.state, frame.id) ~= nil, "the old trailer's " .. frame.id .. " loaded empty")
        end
        expect(answer.state.colorSat == answer.forcedSat and answer.state.colorVal == answer.forcedVal,
            string.format("the old trailer kept its colour, saturation %.2f and value %.2f", answer.state.colorSat, answer.state.colorVal))
    end,
})

-- Vanilla's wash action offers each side of the trailer and washes its blood off from the side's
-- area: Front by the coupler, Rear behind the deck, Left and Right beside it.
local WASH_AREAS = { { side = "Front", area = "Engine" }, { side = "Rear", area = "TruckBed" },
    { side = "Left", area = "SeatLeft" }, { side = "Right", area = "SeatRight" } }
local WASH_BLOOD = 0.2

test("renewable_energy_world_arrow_board_washes", {
    instant = true,
    run = function(self)
        self.trailer = spawnTrailer(self)
        if not self.trailer then return end
        local trailer, p = self.trailer, player()
        T.give(self, "bucket", { { type = "Base.Bucket" } })
        self.offered, self.left = {}, {}
        -- Each side's wash is queued once the one before has finished, behind it.
        local function washSide(i)
            local wash = WASH_AREAS[i]
            local blood = {}
            for _, other in ipairs(WASH_AREAS) do
                blood[other.side] = other == wash and WASH_BLOOD or 0
            end
            T.onVehicle(self, trailer, "setTrailer", { blood = blood })
            T.server(self, "refillFluid", function() return { id = self.items.bucket[1]:getID(), fluid = "Water", liters = 10 } end)
            T.waitForCopy(function() return trailer.vehicle:getBloodIntensity(wash.side) > 0 end)
            T.step(function()
                local vehicle = trailer.vehicle
                local area = ISWashVehicle.hasBlood(vehicle) and ISWashVehicle.chooseArea(p, vehicle)
                self.offered[wash.side] = area and area.id .. " at " .. area.area or "nothing"
                standIn(vehicle, wash.area)
                ISTimedActionQueue.add(ISWashVehicle:new(p, vehicle, wash.side, wash.area))
            end)
            T.awaitVehicleState(self, trailer, function(state) return state.blood[wash.side] <= 0 end, SERVER_MS)
            T.step(function()
                self.left[wash.side] = trailer.state.blood[wash.side]
                if WASH_AREAS[i + 1] then
                    washSide(i + 1)
                end
            end)
        end
        washSide(1)
    end,
    validate = function(self)
        for _, wash in ipairs(WASH_AREAS) do
            local expected = wash.side .. " at " .. wash.area
            expect(self.offered[wash.side] == expected, "blood on " .. wash.side .. " offered " .. tostring(self.offered[wash.side]))
            expect(self.left[wash.side] == 0, "washing " .. wash.side .. " left " .. tostring(self.left[wash.side]))
        end
    end,
})

-- Repair Frame offers each dented end of the frame, and the sheet metal fix it offers, vanilla's
-- welding, walks there and welds it whole at high skill; a whole frame offers nothing.
test("renewable_energy_world_arrow_board_frame_welds", {
    instant = true,
    run = function(self)
        self.trailer = spawnTrailer(self, { repair = true })
        if not self.trailer then return end
        local trailer = self.trailer
        T.setPerk(self, Perks.MetalWelding, 10)
        T.setPerk(self, Perks.Mechanics, 10)
        T.onVehicle(self, trailer, "setTrailer", { frame = { [FRAME_FRONT] = 20, [FRAME_BACK] = 45 } })
        T.waitForVehicleCopy(trailer, function(copy)
            return frameCondition(copy, FRAME_FRONT) == 20 and frameCondition(copy, FRAME_BACK) == 45
        end)
        -- A spare sheet metal: on a multiplayer client vanilla's fix action checks for the sheet
        -- metal (ISFixVehiclePartAction.isValid) after the server's weld has taken the last one,
        -- and stops, which empties the queue and drops the test's later steps. The weld itself
        -- has happened on the server.
        T.give(self, "tools", { { type = "Base.BlowTorch" }, { type = "Base.SheetMetal", count = 3 } })
        self.labels = {}
        -- The frame's options, and under each the first fix: one sheet metal.
        local function frameOptions()
            local context = ISContextMenu.get(0, 0, 0)
            RenewableEnergy.Menu.addFrameRepairOptions(0, context, trailer.vehicle)
            local found = {}
            for _, option in ipairs(context.options) do
                local submenu = option.subOption and context:getSubMenu(option.subOption)
                table.insert(found, { name = option.name, fix = submenu and submenu.options[1] })
            end
            return found
        end
        local function weld(option, area)
            standIn(trailer.vehicle, area)
            local fix = option.fix
            fix.onSelect(fix.target, fix.param1, fix.param2, fix.param3, fix.param4)
        end
        T.step(function()
            local offered = frameOptions()
            for _, option in ipairs(offered) do
                table.insert(self.labels, option.name)
            end
            if not T.need(self, #offered == 2 and offered[1].fix and offered[2].fix or nil, "a fix under each frame option") then
                return
            end
            weld(offered[1], "Engine")
            T.awaitVehicleState(self, trailer, function(state) return frameCondition(state, FRAME_FRONT) == 100 end, SERVER_MS)
            T.waitForVehicleCopy(trailer, function(copy) return frameCondition(copy, FRAME_FRONT) == 100 end)
            T.step(function()
                weld(frameOptions()[1], "TruckBed")
                T.awaitVehicleState(self, trailer, function(state) return frameCondition(state, FRAME_BACK) == 100 end, SERVER_MS)
                T.waitForVehicleCopy(trailer, function(copy) return frameCondition(copy, FRAME_BACK) == 100 end)
                T.count(self, "left", { "Base.SheetMetal" })
                T.step(function()
                    self.afterRepair = #frameOptions()
                end)
            end)
        end)
    end,
    validate = function(self)
        local front = getText("ContextMenu_RenewableEnergy_RepairFrame", getText("IGUI_RenewableEnergy_FrameFront"), 20)
        local back = getText("ContextMenu_RenewableEnergy_RepairFrame", getText("IGUI_RenewableEnergy_FrameBack"), 45)
        expect(self.labels[1] == front and self.labels[2] == back, "the menu offered " .. table.concat(self.labels, ", "))
        local state = self.trailer.state
        expect(frameCondition(state, FRAME_FRONT) == 100 and frameCondition(state, FRAME_BACK) == 100,
            "welding left the frame at " .. tostring(frameCondition(state, FRAME_FRONT)) .. " and "
            .. tostring(frameCondition(state, FRAME_BACK)))
        local left = self.counts.left and self.counts.left["Base.SheetMetal"]
        expect(left == 1, "welding left " .. tostring(left) .. " of 3 sheet metal")
        expect(self.afterRepair == 0, "a whole frame offers " .. tostring(self.afterRepair) .. " repairs")
    end,
})
