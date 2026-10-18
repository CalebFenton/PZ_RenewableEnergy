require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
require "RenewableEnergy/Sprites"
local Stash = require "RenewableEnergy/StashHouses"

-- World systems that live on the authority: stash houses (StashHouses.lua, MapDefinitions.lua),
-- world spawns (WorldSpawns.lua, Distributions.lua), solar sites, garden lights and rural finds
-- (World/*). Arrow boards are in RenewableEnergyTestsArrowBoard.lua.

local T = RenewableEnergyTest
local test, expect, expectNear, player, serverCheck = T.test, T.expect, T.expectNear, T.player, T.serverCheck

local Sprites = RenewableEnergy.Sprites

-- Stash houses ----------------------------------------------------------------------------------

-- StashSystem gives up without an error when the stash building isn't a building, prepares only a
-- building whose bounds strictly contain the building square (doBuildingStash), and stocks the
-- crate only if its square is in a room of that building, so a wrong coordinate is an empty house.
serverCheck("renewable_energy_world_stash_houses_resolve", "stashHousesResolve")

-- Unless Stash Houses is at None, the stashes join the list StashSystem reads, once however often
-- the game loads.
test("renewable_energy_world_stashes_register_by_option", {
    run = function(self) T.server(self, "stashRegister") end,
    validate = function(self)
        local answer = self.server.stashRegister
        local results, expected = answer.results, answer.houses
        for name, mode in pairs(Stash.MODE) do
            local result, on = results[mode], mode ~= Stash.MODE.NONE
            expect(result.registered == on, "Stash Houses " .. name .. (on and " did not register" or " registered"))
            expect(result.count == (on and expected or 0),
                "Stash Houses " .. name .. " listed " .. result.count .. " stashes, expected " .. (on and expected or 0))
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
-- and lies in vanilla's prepper caches; campers' glove boxes hold the trailer park's; and every
-- loot list a map names exists.
serverCheck("renewable_energy_world_prepper_map_targets", "prepperMapTargets")

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

-- Under the Stash Houses settings that hand out maps, every stash's map goes into each of its loot
-- lists once, at the weight it gives there; under the others none does.
test("renewable_energy_world_stash_maps_in_corpse_loot", {
    run = function(self) T.server(self, "stashMapsInCorpseLoot") end,
    validate = function(self)
        local MODE = Stash.MODE
        for _, found in ipairs(self.server.stashMapsInCorpseLoot.found) do
            local wanted = (found.mode == MODE.MAPS or found.mode == MODE.MAPS_AND_STOCKED) and 1 or 0
            local label = "Stash Houses " .. found.mode .. ": " .. found.where
            expect(found.count == wanted, label .. " " .. found.count .. " times")
            expect(wanted == 0 or found.weight == found.rarity, label .. " at weight " .. tostring(found.weight))
        end
    end,
})

-- World spawns -----------------------------------------------------------------------------------

local MODULE = RenewableEnergy.Specs.factoryModule

-- A tuned range read from the authority's WorldSpawns: the test checks spawns against it, so it
-- must itself be one a player can meet, from `lowest` up to `highest`.
local function expectSaneRange(range, what, lowest, highest)
    expect(range.min >= lowest and range.min <= range.max and range.max <= highest,
        what .. " runs from " .. range.min .. " to " .. range.max)
end

-- This client's copy of the first object of `sprite` on `square`, and how many items its
-- container holds (nil without one).
local function copyOf(square, sprite)
    local object = T.objectWithSprite(square, sprite)
    local container = object and object:getContainer()
    return object, container and container:getItems():size()
end

-- Stock names of WorldSpawns.BANK_STOCK, one per bank tier.
local SPAWNED_BANKS = { "shed", "electronicsStorage", "powerYard" }

-- A bank appears stocked with era batteries at a part charge, explored so that neither its room's
-- loot nor loot respawn ever adds to it, and players see what it holds. It was installed, so it is
-- connected, unlike one a player places. Placing needs no player, as on a dedicated server.
test("renewable_energy_world_bank_spawns_stocked", {
    sandbox = { LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        local squares = T.need(self, T.squares(self, #SPAWNED_BANKS, { indoors = true }), "free indoor squares for banks")
        if not squares then return end
        self.banks = {}
        T.batch(function()
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
        end)
        T.waitFor(self, function()
            for _, bank in ipairs(self.banks) do
                if select(2, copyOf(bank.square, bank.sprite)) ~= bank.stock.items then
                    return false
                end
            end
            return true
        end, "this client's copies of the banks with all they hold")
    end,
    validate = function(self)
        local stocks = self.server.worldSpawnStock.banks
        for _, bank in ipairs(self.banks) do
            local stock = stocks[bank.stockName]
            local what = "the " .. bank.stockName .. " bank"
            local count = #bank.stock.charges
            expect(bank.sprite == Sprites[stock.sprite], what .. " has the wrong tile")
            expect(bank.stock.explored, what .. " is not explored")
            local copy = copyOf(bank.square, bank.sprite)
            expect(copy ~= nil and copy:isConnected(), what .. " isn't connected on this client")
            expectSaneRange(stock.batteries, "the battery count of " .. what, 1, math.huge)
            expect(T.inRange(count, stock.batteries),
                count .. " batteries in " .. what .. ", expected " .. stock.batteries.min .. " to " .. stock.batteries.max)
            T.expectFoundCharges(bank.stock.charges, what)
        end
    end,
})

-- A room seen for the first time never puts a bank on an outdoor square: the world spawn honours
-- the indoors-only rule that placement by a player also obeys (the bank tests cover that rule).
test("renewable_energy_world_bank_spawn_refused_outdoors", {
    run = function(self)
        local square = T.square(self, nil, "a free outdoor square")
        if not square then return end
        T.server(self, "worldBank", { x = square:getX(), y = square:getY(), z = square:getZ(), stock = "shed" })
    end,
    validate = function(self)
        expect(not self.server.worldBank.placed, "a bank was placed outdoors")
        expect(not self.server.worldBank.boxOnSquare, "a bank's tile stands outdoors")
    end,
})

-- Bank tiers whose tile is a battery box, which has no slot for a charge controller.
local BOX_TILES = { batteryBoxWood = true, batteryBoxMetal = true }

-- Over many banks, each part turns up about as often as BANK_STOCK says, and a battery box never
-- comes with a charge controller.
serverCheck("renewable_energy_world_bank_stock_rates", "bankStockRates", { samples = 2000, boxTiles = BOX_TILES },
    { LRMBatteries = 1, LRMMisc = 1 })

-- With the battery and misc loot options at 0, world banks spawn empty.
test("renewable_energy_world_bank_stock_option_zero", {
    sandbox = { LRMBatteries = 0, LRMMisc = 0 },
    run = function(self) T.server(self, "bankStockCount", { times = 20 }) end,
    validate = function(self)
        local items = self.server.bankStockCount.items
        expect(items == 0, items .. " items in banks with the options at 0")
    end,
})

-- The item count from which vanilla's container overlays show a container full rather than
-- holding a few items (ContainerOverlays.updateContainerOverlaySprite).
local FEW_ITEMS = 7

-- A crate appears stocked with modules at cracked or weathered conditions and batteries at a part
-- charge, as many as CRATE_STOCK's kit says, explored, showing its full or closed lid by how much
-- it holds, and players see what it holds and its lid.
test("renewable_energy_world_crate_spawns_stocked", {
    sandbox = { LRMSolarPanels = 1, LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        local square = T.square(self, { indoors = true }, "a free indoor square")
        if not square then return end
        T.batch(function()
            T.server(self, "worldCrate", { x = square:getX(), y = square:getY(), z = square:getZ(), stock = "kit" })
            T.server(self, "worldSpawnStock", { names = {}, crate = "kit" })
        end)
        T.waitFor(self, function()
            local crate = self.server.worldCrate
            local copy, items = copyOf(square, Sprites.crate)
            local overlay = copy and copy:getOverlaySprite()
            return items == crate.stock.items and overlay ~= nil and overlay:getName() == crate.overlay
        end, "this client's copy of the crate with all it holds and its lid")
    end,
    validate = function(self)
        local crate, ranges = self.server.worldCrate, self.server.worldSpawnStock
        local lines = ranges.crate
        expect(crate.stock.explored, "the crate is not explored")
        local conditions = crate.stock.modules
        expect(T.inRange(#conditions, lines[MODULE]), #conditions .. " modules in the crate")
        expectSaneRange(ranges.cracked, "a cracked module's condition", 1, 100)
        expectSaneRange(ranges.weathered, "a weathered module's condition", 1, 100)
        for _, condition in ipairs(conditions) do
            expect(T.inRange(condition, ranges.cracked) or T.inRange(condition, ranges.weathered), "a crate module is at condition " .. condition)
        end
        local charges = crate.stock.charges
        expect(T.inRange(#charges, lines["RenewableEnergy.DeepCycleBattery"]), #charges .. " batteries in the crate")
        T.expectFoundCharges(charges, "the crate")
        local overlays = Sprites.crateOverlays
        local lid = crate.stock.items < FEW_ITEMS and overlays.closed or overlays.full
        expect(crate.overlay == lid, "the crate holding " .. crate.stock.items .. " items shows " .. tostring(crate.overlay))
    end,
})

-- Cracked modules -------------------------------------------------------------------------------

-- Farm storage shelves get cracked modules, at cracked conditions, and a bedroom's furniture
-- none. At the highest option every farm storage shelf gets one, so that nothing is left to
-- chance; at the default the chance is small but there.
serverCheck("renewable_energy_world_cracked_modules", "crackedModules", { samples = 200 }, { LRMSolarPanels = 100 })

-- Solar sites -----------------------------------------------------------------------------------

-- A site goes down once when its chunk loads, and its spot is forgotten, so loading the chunk
-- again places nothing. Its pump's pole mount holds as many modules as its kind says, at site
-- conditions, and players see it.
test("renewable_energy_world_site_placed_once", {
    run = function(self)
        local square = T.square(self, nil, "a free outdoor square")
        if not square then return end
        T.server(self, "sitePlacedOnce", { x = square:getX(), y = square:getY(), z = square:getZ() })
        T.waitFor(self, function() return T.objectWithSprite(square, Sprites.rack.metal.S) ~= nil end,
            "this client's copy of the site's rack")
    end,
    validate = function(self) T.expectNoFailures(self.server.sitePlacedOnce) end,
})

-- Every site's spots make sense on the map: banks and crates in a room (banks only work indoors),
-- panels outdoors, wall panels on a building's wall, garden lights at a building, arrow boards
-- outdoors with a facing; each site has a unique name, a known kind, and the spots its kind uses.
serverCheck("renewable_energy_world_sites_placed_sensibly", "sitesPlacedSensibly")

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
        T.waitFor(self, function() return copies() == #self.server.gardenLightsOnce.lights end,
            "this client's copies of the new lights")
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
    end,
})

-- Frames to wait at each place for this client to load it, and at the start for it to load again.
-- Loading takes real time, so at an uncapped frame rate it takes many frames.
local VISIT_FRAMES = 6000
-- How long the server is given to roll the house at a place once this client has loaded it.
local ROLL_MS = 60000
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
-- or ROLL_MS pass. Leaves house, rolled and found (the neighbourhood) in `place`.
local function visitPlace(self, place)
    local where = place[1] .. "," .. place[2]
    T.step(function() self.teleportTo(place[1] + 0.5, place[2] + 0.5, 0) end)
    T.waitFor(self, function() return getSquare(place[1], place[2], 0) ~= nil end, where .. " loaded on this client", VISIT_FRAMES)
    T.serverUntil(self, "gardenLightsAt", { x = place[1], y = place[2], radius = 20 }, function(at) return at.rolled end, ROLL_MS)
    T.step(function()
        local at = self.server.gardenLightsAt
        place.house, place.rolled, place.found = at.house, at.rolled, at.neighbourhood
    end)
end

-- Queues the character's way back to `start` ({ x, y, z }) and a wait for the squares around it
-- to load again; leaves in self.home where the character ended up.
local function returnHome(self, start)
    local x, y = math.floor(start.x), math.floor(start.y)
    T.step(function() self.teleportTo(start.x, start.y, start.z) end)
    T.waitFor(self, function() return loadedAround(x, y, start.z, HOME_RADIUS) end, "the start loaded again", VISIT_FRAMES)
    T.step(function()
        local p = player()
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
        for _, place in ipairs(self.places) do
            visitPlace(self, place)
        end
        returnHome(self, self.start)
    end,
    validate = function(self)
        for _, place in ipairs(self.places) do
            local where = place[1] .. "," .. place[2]
            expect(place.found == place[3], where .. " is " .. tostring(place.found) .. ", expected " .. place[3])
            if expect(place.house, "no house near " .. where) then
                expect(place.rolled, "the house at " .. place.house .. " was never rolled for garden lights")
            end
        end
        local home, start = self.home, self.start
        expect(home.z == start.z and math.abs(home.x - start.x) <= 1 and math.abs(home.y - start.y) <= 1,
            string.format("the character ended at %s,%s,%s, not back at the start", home.x, home.y, home.z))
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

-- Rural finds --------------------------------------------------------------------------------------

-- Each rural find test rolls the building near the start for that find for certain, mends it
-- with the usual jobs and sees it work; rolled again, the building gets nothing more.

require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"
require "RenewableEnergy/Biogas/DigesterJobs"
require "RenewableEnergy/WoodGas/GasifierJobs"
require "RenewableEnergy/Wind"
local Digester, DigesterJobs = RenewableEnergy.Digester, RenewableEnergy.DigesterJobs
local Gasifier, GasifierJobs = RenewableEnergy.Gasifier, RenewableEnergy.GasifierJobs
local Wind, PowerBank = RenewableEnergy.Wind, RenewableEnergy.PowerBank

-- Queues the roll of the find `kind` and a wait for this client's copy of it, `isObject` telling
-- it, with its summary when `recordKind` names a Global Object System record ("digester",
-- "gasifier"); the handle { x, y, z, square, kind, object } lands in self.find.
local function rollFind(self, kind, isObject, recordKind)
    T.server(self, "ruralFind", { kind = kind })
    T.step(function()
        local at = self.server.ruralFind.at
        self.find = { x = at.x, y = at.y, z = at.z, square = getSquare(at.x, at.y, at.z), kind = recordKind }
    end)
    T.waitFor(self, function()
        local find = self.find
        local object = RenewableEnergy.findObjectOn(find.square, isObject)
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
            T.perform(self, "connectSource", { bank = bank.position, source = T.at(find) })
            T.step(function() self.connected = self.server.perform end)
            T.give(self, "blades", { { type = "RenewableEnergy.WoodenBlades" } })
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
            T.giveMaterials(self, "bags", DigesterJobs.materials(DigesterJobs.REPLACE_BAGS))
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
        for _, tile in pairs(RenewableEnergy.Sprites.digester.barrel) do
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
            T.giveMaterials(self, "shovel", GasifierJobs.materials(GasifierJobs.CLEAN_ASH))
            T.gasJob(self, "gasifier", find, GasifierJobs.CLEAN_ASH)
            T.batch(function()
                T.server(self, "ruralFindEmptyFilter", T.at(find))
                T.fillRecord(self, find, { hopper = { { type = "Base.Plank", count = 3 } }, filter = { { type = "Base.HayTuft", count = 5 } } })
            end)
            T.waitForSummary(self, find, function(summary) return summary.hopperKg > 0 and summary.ash == 0 end,
                "this client's summary of the cleaned, stocked gasifier")
            T.step(function()
                T.giveMaterials(self, "light", GasifierJobs.materials(GasifierJobs.LIGHT, T.recordSummary(find)))
            end)
            T.gasJob(self, "gasifier", find, GasifierJobs.LIGHT)
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

-- Real buildings rolled the way the world rolls them: their rooms pick the finds and each find its
-- square, outdoors on the ground within RuralFinds.REACH of the building (the wind charger needs
-- open ground around it, so at least 2 out). The barn west of Muldraugh gets the
-- wind charger and digester; the hunting shack west of Riverside the gasifier and a pamphlet; the
-- deer stand, whose one room is on level 1 (`z`), the gasifier on the ground.
local RURAL_PLACES = {
    { 10469, 10121, 0, finds = { wind = true, digester = true } },
    { 7067, 8632, 0, finds = { gasifier = true }, pamphlet = true },
    { 7917, 8176, 1, finds = { gasifier = true } },
}

test("renewable_energy_world_rural_finds_real_buildings", {
    -- Three far visits and the way back, each waiting on loading.
    timeoutSeconds = 180,
    run = function(self)
        T.setMultiplier(self, VISIT_SPEED)
        self.start = startVisits(self)
        for _, place in ipairs(RURAL_PLACES) do
            local where = place[1] .. "," .. place[2]
            T.step(function() self.teleportTo(place[1] + 0.5, place[2] + 0.5, 0) end)
            T.waitFor(self, function() return getSquare(place[1], place[2], 0) ~= nil end, where .. " loaded on this client", VISIT_FRAMES)
            T.serverUntil(self, "ruralFindAt", { x = place[1], y = place[2], z = place[3] }, function(at)
                place.answer = at
                return at.ready
            end, ROLL_MS)
        end
        returnHome(self, self.start)
    end,
    validate = function(self)
        for _, place in ipairs(RURAL_PLACES) do
            local where, answer = place[1] .. "," .. place[2], place.answer
            if expect(answer and answer.ready, "the building at " .. where .. " never loaded on the server: "
                .. tostring(answer and answer.why)) then
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
                        expect(at.out >= (kind == "wind" and 2 or 1) and at.out <= answer.reach,
                            "the " .. kind .. " by " .. where .. " stands " .. at.out .. " squares out from the building")
                    end
                end
                if place.pamphlet then
                    expect(answer.pamphlets == 1, "the shack at " .. where .. " got " .. answer.pamphlets .. " pamphlets, not 1")
                end
            end
        end
    end,
})

-- At 0 the Solar Sites option leaves rural buildings without finds: the building near the start,
-- rolled for every find again and again the way the world rolls it, never gets one.
test("renewable_energy_world_rural_finds_option_zero", {
    sandbox = { SolarSites = 0 },
    run = function(self) T.server(self, "ruralFindsRolls", { rolls = 60 }) end,
    validate = function(self)
        local answer = self.server.ruralFindsRolls
        for kind, chance in pairs(answer.chances) do
            expect(chance == 0, "the " .. kind .. " has chance " .. chance .. " with the option at 0")
        end
        expect(answer.placed == 0, "with the option at 0 the rolls placed " .. answer.placed .. " finds")
    end,
})

-- Vanilla's barns and survivalist camps are dressed with the mod's magazines, pamphlet and charger.
serverCheck("renewable_energy_world_rural_clutter", "ruralClutter")
