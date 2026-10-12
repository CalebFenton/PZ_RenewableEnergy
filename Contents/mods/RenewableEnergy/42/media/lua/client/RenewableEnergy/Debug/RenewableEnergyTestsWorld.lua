require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Sprites"
-- The game's Java class zombie.core.stash.Stash, which the mod's module name would hide.
local EngineStash = Stash
local Stash = require "RenewableEnergy/StashHouses"

-- Stash house, world spawn, solar site, garden light and arrow board tests. See
-- RenewableEnergyTestLib.lua for how the runner works. Server Lua loads after client Lua, so
-- WorldSpawns, SolarSites, GardenLights, ArrowBoard and Distributions are looked up when a test
-- runs.

local T = RenewableEnergyTest
local test, expect, expectNear, player = T.test, T.expect, T.expectNear, T.player

local Sprites = RenewableEnergy.Sprites

local function stashCount()
    local count = 0
    for _ in pairs(Stash.descriptions) do
        count = count + 1
    end
    return count
end

-- Stash houses ----------------------------------------------------------------------------------

-- StashSystem gives up without an error when the stash building isn't a building, prepares only a
-- building whose bounds strictly contain the building square (doBuildingStash), and stocks the
-- crate only if its square is in a room of that building, so a wrong coordinate is an empty house.
test("renewable_energy_world_stash_houses_resolve", {
    validate = function()
        local metaGrid = getWorld():getMetaGrid()
        for stashMap in pairs(Stash.descriptions) do
            local x, y = stashMap.buildingX, stashMap.buildingY
            local room = metaGrid:getRoomAt(x, y, 0)
            local building = room and room:getBuilding()
            if expect(building ~= nil, stashMap.name .. ": no building at its building coordinates") then
                expect(building:getX() < x and x < building:getX2() and building:getY() < y and y < building:getY2(),
                    stashMap.name .. ": the building square is on the edge of the building's bounds")
                for _, crate in ipairs(stashMap.containers) do
                    local crateRoom = metaGrid:getRoomAt(crate.contX, crate.contY, crate.contZ)
                    expect(crateRoom ~= nil and crateRoom:getBuilding() == building,
                        stashMap.name .. ": the crate square is not in a room of the building")
                    expect(crate.containerSprite == Sprites.crate and crate.containerType == "RenewableEnergySolarBox",
                        stashMap.name .. ": the crate is not the mod's solar crate")
                end
            end
            expect(stashMap.spawnTable == "RenewableEnergyStashCache"
                and SuburbsDistributions.RenewableEnergyStashCache.RenewableEnergySolarBox ~= nil,
                stashMap.name .. ": its spawn table has no solar crate loot")
        end
        expect(stashCount() == 4, stashCount() .. " Renewable Energy stashes, expected 4")
    end,
})

-- Takes the mod's houses out of StashDescriptions.
local function unregister()
    for i = #StashDescriptions, 1, -1 do
        if Stash.descriptions[StashDescriptions[i]] then
            table.remove(StashDescriptions, i)
        end
    end
end

-- Unless Stash Houses is at 1 (none), the stashes join the list StashSystem reads, once however
-- often the game loads.
test("renewable_energy_world_stashes_register_by_option", {
    run = function(self)
        -- Pushed before the option changes, so it runs once the world's option is back.
        T.defer(self, function()
            unregister()
            Stash.register()
        end)
        self.results = {}
        for _, mode in ipairs({ 1, 2, 3, 4 }) do
            unregister()
            T.setSandbox(self, "StashMode", mode)
            local registered = Stash.register()
            Stash.register()
            local count = 0
            for _, description in ipairs(StashDescriptions) do
                if Stash.descriptions[description] then
                    count = count + 1
                end
            end
            self.results[mode] = { registered = registered, count = count }
        end
    end,
    validate = function(self)
        local expected = stashCount()
        expect(not self.results[1].registered and self.results[1].count == 0, "Stash Houses 1 registered stashes")
        for _, mode in ipairs({ 2, 3, 4 }) do
            expect(self.results[mode].registered, "Stash Houses " .. mode .. " did not register")
            expect(self.results[mode].count == expected,
                "Stash Houses " .. mode .. " listed " .. self.results[mode].count .. " stashes, expected " .. expected)
        end
    end,
})

-- A found stash map shows the stash's stamps and notes. A symbol the game doesn't define or a
-- note without a translation is dropped or shown as its key.
test("renewable_energy_world_stash_maps_annotated", {
    validate = function()
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

            -- The engine's own load and annotate path, on a fresh copy of the stash so the
            -- world's stash state stays as it was.
            local engineStash = EngineStash.new(stashMap.name)
            engineStash:load(stashMap)
            local map = instanceItem(stashMap.item)
            if expect(map ~= nil and instanceof(map, "MapItem"), stashMap.name .. ": " .. stashMap.item .. " is not a map") then
                StashSystem.doStashItem(engineStash, map)
                expect(map:getStashMap() == stashMap.name, stashMap.name .. ": the map was not annotated")
            end
        end
        -- doStashItem takes the stash out of the possible list; this puts it back.
        Stash.relistUnfound()
    end,
})

local function isPossibleStash(name)
    local possible = StashSystem.getPossibleStashes()
    for i = 0, possible:size() - 1 do
        if possible:get(i):getName() == name then
            return true
        end
    end
    return false
end

local function removePossibleStash(name)
    local possible = StashSystem.getPossibleStashes()
    for i = possible:size() - 1, 0, -1 do
        if possible:get(i):getName() == name then
            possible:remove(possible:get(i))
        end
    end
end

local RELIST_CASES = {
    { visited = false, read = false, relisted = true },
    { visited = true, read = false, relisted = false },
    { visited = false, read = true, relisted = false },
}

-- A house missing from StashSystem's possible stashes goes back on the list unless someone
-- entered it or read its map, so a map found later leads to a house still untouched. Each house
-- goes through every case and is put back as it was.
test("renewable_energy_world_unfound_stash_relisted", {
    run = function(self)
        local metaGrid = getWorld():getMetaGrid()
        local houses = {}
        for stashMap in pairs(Stash.descriptions) do
            local room = metaGrid:getRoomAt(stashMap.buildingX, stashMap.buildingY, 0)
            local building = T.need(self, room and room:getBuilding(), "the building of " .. stashMap.name)
            table.insert(houses, { name = stashMap.name, building = building })
        end
        if not T.need(self, #houses > 0, "a stash house") or #self.missing > 0 then return end
        local possible, alreadyRead = StashSystem.getPossibleStashes(), StashSystem.getAlreadyReadMap()
        local savedPossible = {}
        for i = 0, possible:size() - 1 do
            table.insert(savedPossible, possible:get(i))
        end
        self.results = {}
        for _, house in ipairs(houses) do
            local name, building = house.name, house.building
            local visited, read = building:isHasBeenVisited(), alreadyRead:contains(name)
            for _, case in ipairs(RELIST_CASES) do
                removePossibleStash(name)
                building:setHasBeenVisited(case.visited)
                alreadyRead:remove(name)
                if case.read then
                    alreadyRead:add(name)
                end
                Stash.relistUnfound()
                table.insert(self.results, { name = name, case = case, relisted = isPossibleStash(name) })
            end
            building:setHasBeenVisited(visited)
            alreadyRead:remove(name)
            if read then
                alreadyRead:add(name)
            end
        end
        -- Last, since marking a house visited drops it from the list.
        possible:clear()
        for _, stash in ipairs(savedPossible) do
            possible:add(stash)
        end
    end,
    validate = function(self)
        for _, result in ipairs(self.results) do
            local case = result.case
            expect(result.relisted == case.relisted, string.format("%s, %s and %s, was %s", result.name,
                case.visited and "entered" or "never entered", case.read and "its map read" or "its map unread",
                result.relisted and "relisted" or "not relisted"))
        end
    end,
})

local function descriptionNamed(name)
    for stashMap, added in pairs(Stash.descriptions) do
        if stashMap.name == name then
            return stashMap, added
        end
    end
    return nil
end

-- Stash Houses 3 and 4 stock the houses that have a knownOnStart chance, through the engine, and
-- only those; none of them may then show on the world map as a map already read. The test world
-- runs at Stash Houses 1, so the engine is handed the houses for the test, every chance is made
-- certain, and StashSystem's possible list, which isStashBuilding also reads, is emptied of them
-- so that what it reports afterwards is the stocking queue alone.
test("renewable_energy_world_known_on_start_stocks_and_stays_hidden", {
    run = function(self)
        local all, possible = StashSystem.getAllStashes(), StashSystem.getPossibleStashes()
        self.added, self.chances = {}, {}
        for stashMap, added in pairs(Stash.descriptions) do
            if not StashSystem.getStash(stashMap.name) then
                local engineStash = EngineStash.new(stashMap.name)
                engineStash:load(stashMap)
                all:add(engineStash)
                table.insert(self.added, engineStash)
            end
            self.chances[added] = added.knownOnStart
            added.knownOnStart = added.knownOnStart and 100
        end
        for i = possible:size() - 1, 0, -1 do
            if descriptionNamed(possible:get(i):getName()) then
                possible:remove(possible:get(i))
            end
        end
        Stash.stockFromStart()
        local metaGrid = getWorld():getMetaGrid()
        self.queued, self.read = {}, {}
        for stashMap in pairs(Stash.descriptions) do
            local room = metaGrid:getRoomAt(stashMap.buildingX, stashMap.buildingY, 0)
            self.queued[stashMap.name] = room ~= nil and StashSystem.isStashBuilding(room:getBuilding())
            self.read[stashMap.name] = StashSystem.getAlreadyReadMap():contains(stashMap.name)
        end
    end,
    validate = function(self)
        for stashMap, added in pairs(Stash.descriptions) do
            local name = stashMap.name
            expect(not self.read[name], name .. " is marked as read")
            expect(self.queued[name] == (self.chances[added] ~= nil),
                name .. (self.queued[name] and " was stocked from the start" or " was not stocked from the start"))
        end
    end,
    cleanup = function(self)
        for added, chance in pairs(self.chances or {}) do
            added.knownOnStart = chance
        end
        for _, engineStash in ipairs(self.added or {}) do
            StashSystem.getAllStashes():remove(engineStash)
        end
        Stash.relistUnfound()
    end,
})

-- The prepper's map drops from survivalist and bandit corpses, whichever outfit variant they wear,
-- and every corpse list a map names exists.
test("renewable_energy_world_prepper_map_targets", {
    validate = function()
        local all = SuburbsDistributions.all
        for stashMap, added in pairs(Stash.descriptions) do
            for _, target in ipairs(added.targets or {}) do
                expect(all[target] ~= nil and all[target].items ~= nil, stashMap.name .. ": no loot list " .. target)
            end
        end
        local _, prepper = descriptionNamed("RenewableEnergy_CrowcallRoad")
        if not expect(prepper ~= nil, "no Crowcall Road stash") then
            return
        end
        local targets = {}
        for _, target in ipairs(prepper.targets) do
            targets[target] = true
        end
        for key in pairs(all) do
            if string.find(key, "^Outfit_Survivalist") or string.find(key, "^Outfit_Bandit") then
                expect(targets[key], "the Crowcall Road map does not drop from " .. key)
            end
        end
    end,
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
    run = function(self)
        local D = RenewableEnergy.Distributions
        -- Pushed before the option changes, so the loot is rebuilt once the world's option is back.
        T.defer(self, D.apply)
        self.found = {}
        for _, mode in ipairs({ 1, 2, 3, 4 }) do
            T.setSandbox(self, "StashMode", mode)
            D.apply()
            D.apply()
            for stashMap, added in pairs(Stash.descriptions) do
                for _, target in ipairs(added.targets or {}) do
                    local count, weight = T.countPairs(SuburbsDistributions.all[target].items, stashMap.item)
                    table.insert(self.found, {
                        mode = mode, where = stashMap.name .. " in " .. target, count = count, weight = weight, rarity = added.rarity,
                    })
                end
            end
        end
    end,
    validate = function(self)
        for _, found in ipairs(self.found) do
            local wanted = (found.mode == 2 or found.mode == 3) and 1 or 0
            local label = "Stash Houses " .. found.mode .. ": " .. found.where
            expect(found.count == wanted, label .. " " .. found.count .. " times")
            expect(wanted == 0 or found.weight == found.rarity, label .. " at weight " .. tostring(found.weight))
        end
    end,
})

-- World spawns -----------------------------------------------------------------------------------

local MODULE = "RenewableEnergy.SolarModule"

local function countBatteries(container)
    local count, charges = 0, {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if RenewableEnergy.Battery.isBattery(item) then
            count = count + 1
            table.insert(charges, RenewableEnergy.Battery.getCharge(item))
        end
    end
    return count, charges
end

local function expectFoundCharges(charges, what)
    local range = RenewableEnergy.Specs.foundCharge
    for _, charge in ipairs(charges) do
        expect(charge >= range.min and charge <= range.max,
            what .. " holds a battery at " .. charge .. ", expected " .. range.min .. " to " .. range.max)
    end
end

local function inRange(value, range)
    return value >= range.min and value <= range.max
end

-- Whether a module's condition is one a site, crate or arrow board gives: cracked or weathered.
local function isSiteCondition(condition)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    return inRange(condition, WorldSpawns.CRACKED) or inRange(condition, WorldSpawns.WEATHERED)
end

local function moduleConditions(container)
    local conditions = {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        if items:get(i):getFullType() == MODULE then
            table.insert(conditions, items:get(i):getCondition())
        end
    end
    return conditions
end

-- Stock names of WorldSpawns.BANK_STOCK, one per bank tier.
local SPAWNED_BANKS = { "shed", "electronicsStorage", "powerYard" }

-- A bank appears stocked with era batteries at a part charge, explored so that neither its room's
-- loot nor loot respawn ever adds to it. Placing needs no player, as on a dedicated server.
test("renewable_energy_world_bank_spawns_stocked", {
    sandbox = { LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        local squares = T.need(self, T.squares(self, #SPAWNED_BANKS, { indoors = true }), "free indoor squares for banks")
        if not squares then return end
        self.banks = {}
        for i, stockName in ipairs(SPAWNED_BANKS) do
            local bank = RenewableEnergy.WorldSpawns.placeBank(squares[i], stockName)
            if not T.need(self, bank, "a " .. stockName .. " bank") then return end
            self.banks[stockName] = T.track(self, bank)
        end
    end,
    validate = function(self)
        for stockName, bank in pairs(self.banks) do
            local stock = RenewableEnergy.WorldSpawns.BANK_STOCK[stockName]
            local container = bank:getContainer()
            local what = "the " .. stockName .. " bank"
            expect(bank:getTextureName() == Sprites[stock.sprite], what .. " has the wrong tile")
            expect(container:isExplored(), what .. " is not explored")
            local count, charges = countBatteries(container)
            expect(inRange(count, stock.batteries),
                count .. " batteries in " .. what .. ", expected " .. stock.batteries.min .. " to " .. stock.batteries.max)
            expectFoundCharges(charges, what)
        end
    end,
})

-- Banks only work indoors, so a world spawn never puts one on an outdoor square.
test("renewable_energy_world_bank_refused_outdoors", {
    run = function(self)
        self.square = (T.need(self, T.squares(self, 1), "a free outdoor square") or {})[1]
        if not self.square then return end
        local bank = RenewableEnergy.WorldSpawns.placeBank(self.square, "shed")
        self.placed = bank ~= nil
        if bank then
            T.track(self, bank)
        end
    end,
    validate = function(self)
        expect(not self.placed, "a bank was placed outdoors")
        expect(T.objectWithSprite(self.square, Sprites.batteryBoxWood) == nil, "a battery box stands outdoors")
    end,
})

-- Bank tiers whose tile is a battery box, which has no slot for a charge controller.
local BOX_TILES = { batteryBoxWood = true, batteryBoxMetal = true }

-- Over many banks, each part turns up about as often as BANK_STOCK says, and a battery box never
-- comes with a charge controller.
test("renewable_energy_world_bank_stock_rates", {
    sandbox = { LRMBatteries = 1, LRMMisc = 1 },
    validate = function()
        local WorldSpawns = RenewableEnergy.WorldSpawns
        local container = ItemContainer.new("crate", nil, nil)
        local samples = 400
        local function partCounts(stockName)
            local found = { inverter = 0, controller = 0, charger = 0 }
            for _ = 1, samples do
                container:removeAllItems()
                WorldSpawns.stockBank(container, stockName)
                local items = container:getItems()
                for i = 0, items:size() - 1 do
                    local kind = RenewableEnergy.PowerBank.partKind(items:get(i):getFullType())
                    if found[kind] then
                        found[kind] = found[kind] + 1
                    end
                end
            end
            return found
        end
        for stockName, stock in pairs(WorldSpawns.BANK_STOCK) do
            local found = partCounts(stockName)
            if stockName == "shed" or stockName == "farmStorage" then
                for kind, count in pairs(found) do
                    local part = stock[kind]
                    expectNear(stockName .. " share holding a " .. kind, count / samples, part and part.chance or 0, 0.1)
                end
            end
            if BOX_TILES[stock.sprite] then
                expect(found.controller == 0, found.controller .. " of " .. samples .. " " .. stockName .. " battery boxes hold a charge controller")
            end
        end
        container:removeAllItems()
    end,
})

-- At 0 the battery option leaves world banks empty of batteries.
test("renewable_energy_world_bank_stock_option_zero", {
    sandbox = { LRMBatteries = 0, LRMMisc = 0 },
    validate = function()
        local container = ItemContainer.new("crate", nil, nil)
        for _ = 1, 20 do
            RenewableEnergy.WorldSpawns.stockBank(container, "electronicsStorage")
        end
        expect(container:getItems():size() == 0, container:getItems():size() .. " items in banks with the options at 0")
        container:removeAllItems()
    end,
})

test("renewable_energy_world_crate_spawns_stocked", {
    sandbox = { LRMSolarPanels = 1, LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        local square = (T.need(self, T.squares(self, 1, { indoors = true }), "a free indoor square") or {})[1]
        if not square then return end
        self.crate = T.track(self, RenewableEnergy.WorldSpawns.placeCrate(square, "kit"))
    end,
    validate = function(self)
        local container = self.crate:getContainer()
        if not expect(container ~= nil, "the crate has no container") then
            return
        end
        expect(container:getType() == "RenewableEnergySolarBox", "the crate holds a " .. container:getType())
        expect(container:isExplored(), "the crate is not explored")
        local conditions = moduleConditions(container)
        expect(#conditions >= 1 and #conditions <= 2, #conditions .. " modules in the crate, expected 1 or 2")
        for _, condition in ipairs(conditions) do
            expect(isSiteCondition(condition), "a crate module is at condition " .. condition)
        end
        local _, charges = countBatteries(container)
        expect(#charges >= 1 and #charges <= 2, #charges .. " batteries in the crate, expected 1 or 2")
        expectFoundCharges(charges, "the crate")
        expect(self.crate:getOverlaySprite() ~= nil, "the full crate shows no overlay")
    end,
})

-- Cracked modules -------------------------------------------------------------------------------

-- Farm storage shelves get cracked modules, at condition 20 to 50, and a bedroom's furniture
-- none. At the highest option every farm storage shelf gets one, so that nothing is left to
-- chance; at the default the chance is small but there.
test("renewable_energy_world_cracked_modules", {
    sandbox = { LRMSolarPanels = 100 },
    run = function(self)
        local Distributions = RenewableEnergy.Distributions
        local container = ItemContainer.new("crate", nil, nil)
        self.samples = 200
        for _ = 1, self.samples do
            Distributions.addCrackedModules("farmstorage", "metal_shelves", container)
        end
        self.conditions = moduleConditions(container)
        container:removeAllItems()
        for _ = 1, self.samples do
            Distributions.addCrackedModules("bedroom", "wardrobe", container)
            Distributions.addCrackedModules("garage", "fridge", container)
        end
        self.elsewhere = container:getItems():size()
        container:removeAllItems()
        T.setSandbox(self, "LRMSolarPanels", 1)
        self.defaultChance = Distributions.crackedModuleChance(Distributions.CRACKED_MODULE_ROOMS.garage)
    end,
    validate = function(self)
        expect(#self.conditions == self.samples, #self.conditions .. " cracked modules on " .. self.samples .. " farm storage shelves")
        for _, condition in ipairs(self.conditions) do
            if not expect(inRange(condition, RenewableEnergy.WorldSpawns.CRACKED), "a cracked module is at condition " .. condition) then
                break
            end
        end
        expect(self.elsewhere == 0, self.elsewhere .. " modules in bedrooms and garage fridges")
        expect(self.defaultChance > 0 and self.defaultChance < 0.1, "a garage shelf holds a cracked module with chance " .. self.defaultChance)
    end,
})

-- Solar sites -----------------------------------------------------------------------------------

-- A site goes down once when its chunk loads, and its spot is forgotten, so loading the chunk
-- again places nothing. Its pump's pole mount holds 1 or 2 modules at site conditions.
test("renewable_energy_world_site_placed_once", {
    run = function(self)
        local square = (T.need(self, T.squares(self, 1), "a free outdoor square") or {})[1]
        if not square then return end
        local SolarSites = RenewableEnergy.SolarSites
        local x, y, z = square:getX(), square:getY(), square:getZ()
        local chunkX, chunkY = math.floor(x / 8), math.floor(y / 8)
        SolarSites.addSite({ kind = "stockTank", name = "test", panels = { { x, y, z, "rackMetal", "S" } } })
        self.waiting = SolarSites.spotAt(x, y, z) ~= nil
        SolarSites.placeChunk(chunkX, chunkY)
        self.leftOver = SolarSites.spotAt(x, y, z) ~= nil
        local objects = square:getObjects():size()
        SolarSites.placeChunk(chunkX, chunkY)
        self.addedAgain = square:getObjects():size() - objects
        self.rack = T.need(self, T.objectWithSprite(square, Sprites.rack.metal.S), "the site's rack on its spot")
        if self.rack then
            T.track(self, self.rack)
        end
    end,
    validate = function(self)
        expect(self.waiting, "the site kept no spot to place")
        expect(not self.leftOver, "the site's spot was not forgotten once placed")
        expect(self.addedAgain == 0, "loading the chunk again added " .. self.addedAgain .. " objects to the spot")
        expect(self.rack:getProperties():get("CustomItem") == "RenewableEnergy.SolarRackMetal",
            "the rack does not give back RenewableEnergy.SolarRackMetal")
        local modules = self.rack:getModData()[RenewableEnergy.PowerBank.MODULES] or {}
        expect(#modules >= 1 and #modules <= 2, #modules .. " modules on the pump's mount, expected 1 or 2")
        for _, module in ipairs(modules) do
            expect(module.type == MODULE and isSiteCondition(module.condition),
                "the pump's mount holds " .. tostring(module.type) .. " at " .. tostring(module.condition))
        end
    end,
})

-- Every site's spots make sense on the map: banks and crates in a room (banks only work indoors),
-- panels outdoors, wall panels on a building's wall, garden lights at a building, arrow boards
-- outdoors; and each site has the spots its kind uses.
test("renewable_energy_world_sites_placed_sensibly", {
    validate = function()
        local SolarSites = RenewableEnergy.SolarSites
        local metaGrid = getWorld():getMetaGrid()
        local sites = SolarSites.sites()
        expect(#sites > 0, "this map has no solar sites")
        for _, site in ipairs(sites) do
            local kind = SolarSites.KINDS[site.kind]
            if expect(kind ~= nil, site.name .. " is of no known kind " .. tostring(site.kind)) then
                for _, panel in ipairs(site.panels or {}) do
                    local x, y, z, mount, facing = panel[1], panel[2], panel[3], panel[4], panel[5]
                    local where = site.name .. " panel at " .. x .. "," .. y .. "," .. z
                    local kindOf = Sprites.kindOf(SolarSites.mountSprite(mount, facing))
                    expect(kindOf == "flat" or kindOf == "wall" or kindOf == "rack", where .. " names no mount tile")
                    expect(metaGrid:getRoomAt(x, y, z) == nil, where .. " is indoors")
                    if mount == "wallMetal" then
                        expect(metaGrid:getRoomAt(x, y - 1, z) ~= nil, where .. " has no building wall behind it")
                    end
                end
                if kind.panels then
                    expect(#(site.panels or {}) >= kind.panels.min, site.name .. " has too few panel spots")
                end
                for _, field in ipairs({ "bank", "crate" }) do
                    if kind[field] then
                        local spot = site[field]
                        expect(spot ~= nil and metaGrid:getRoomAt(spot[1], spot[2], spot[3]) ~= nil,
                            site.name .. "'s " .. field .. " is in no room")
                    end
                end
                if kind.gardenLights then
                    expect(site.house ~= nil and metaGrid:getRoomAt(site.house[1], site.house[2], 0) ~= nil,
                        site.name .. "'s garden lights are at no building")
                end
                if site.arrowBoard then
                    local spot = site.arrowBoard
                    expect(metaGrid:getRoomAt(spot[1], spot[2], spot[3]) == nil and IsoDirections[spot[4]] ~= nil,
                        site.name .. "'s arrow board is indoors or faces nowhere")
                end
            end
        end
    end,
})

-- Garden lights ---------------------------------------------------------------------------------

-- The house nearest the square within `radius`, or nil.
local function houseNear(x, y, radius)
    for r = 0, radius do
        for dx = -r, r do
            for _, dy in ipairs({ -r, r }) do
                local square = getSquare(x + dx, y + dy, 0)
                local building = square and square:getBuilding()
                if building and building:getDef():isResidential() then
                    return building:getDef()
                end
            end
        end
    end
    return nil
end

local function houseNearCharacter()
    local here = player():getSquare()
    return houseNear(here:getX(), here:getY(), 60)
end

-- The garden lights around a house, by square key.
local function lightsAround(def)
    local found = {}
    local SolarGardenLight = RenewableEnergy.SolarGardenLight
    for x = def:getX() - 5, def:getX2() + 5 do
        for y = def:getY() - 5, def:getY2() + 5 do
            local light = SolarGardenLight.findOn(getSquare(x, y, 0))
            if light then
                found[x .. "," .. y] = light
            end
        end
    end
    return found
end

local function size(map)
    local count = 0
    for _ in pairs(map) do
        count = count + 1
    end
    return count
end

-- A house rolled for garden lights is never rolled again: the roll is kept in the world's
-- ModData. Its lights stand outdoors on the ground near the house, charged. The house near the
-- start was already rolled when its chunk loaded, so the test forgets that roll first.
test("renewable_energy_world_garden_lights_once_per_house", {
    run = function(self)
        local GardenLights = RenewableEnergy.GardenLights
        local def = T.need(self, houseNearCharacter(), "a house near the character")
        if not def then return end
        local store, key = ModData.getOrCreate(GardenLights.MOD_DATA), GardenLights.buildingKey(def)
        local roll = store[key]
        T.defer(self, function() store[key] = roll end)
        self.before = lightsAround(def)
        store[key] = nil
        self.first = GardenLights.roll(def, true)
        self.rolled = GardenLights.isRolled(def)
        self.second = GardenLights.roll(def, true)
        self.after = lightsAround(def)
        for squareKey, light in pairs(self.after) do
            if not self.before[squareKey] then
                T.track(self, light)
            end
        end
    end,
    validate = function(self)
        local count = RenewableEnergy.GardenLights.COUNT
        expect(self.first >= count.min and self.first <= count.max, "the house got " .. self.first .. " lights")
        expect(self.rolled, "the house's roll was not kept")
        expect(self.second == 0, "rolling the house again gave " .. self.second .. " more lights")
        local added = size(self.after) - size(self.before)
        expect(added == self.first, added .. " lights stand around the house, expected " .. self.first)
        for key, light in pairs(self.after) do
            if not self.before[key] then
                local square = light:getSquare()
                expect(square:isOutside() and square:getRoom() == nil and square:getZ() == 0, "a light stands indoors at " .. key)
                expectNear("a new light's charge", RenewableEnergy.SolarGardenLight.getCharge(light),
                    RenewableEnergy.Specs.gardenLight.wh, 0.001)
            end
        end
    end,
})

-- Frames to wait at each place for it to load and its house to be rolled, and at the start for
-- it to load again. Loading takes real time, so at an uncapped frame rate it takes many frames.
local VISIT_FRAMES = 6000
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

-- The neighbourhood sets the chance: a rich street (Riverside's Rich loot zone) most, a trailer
-- park least, an ordinary street (the start, in Muldraugh) in between. A farmhouse counts as
-- ordinary. And a house far from the start is rolled once the character has been there. The
-- character visits each place in turn, staying until it has loaded and the house nearest it has
-- been rolled, and comes back once the start has loaded again. A teleport from inside a timed
-- action doesn't stick, so OnTick moves them.
test("renewable_energy_world_garden_light_neighbourhoods", {
    run = function(self)
        local GardenLights = RenewableEnergy.GardenLights
        local p = player()
        local homeX, homeY, homeZ = p:getX(), p:getY(), p:getZ()
        self.places = {
            { 6680, 5320, "rich" }, { 5370, 5945, "poor" }, { 7340, 5993, "ordinary" }, { 10835, 10144, "ordinary" },
        }
        T.setMultiplier(self, VISIT_SPEED)
        T.defer(self, function()
            if math.abs(p:getX() - homeX) > 1 or math.abs(p:getY() - homeY) > 1 then
                p:teleportTo(homeX, homeY, homeZ)
            end
        end)
        local index, frames = 0, 0
        local function leave()
            index, frames = index + 1, 0
            local place = self.places[index]
            if place then
                p:teleportTo(place[1] + 0.5, place[2] + 0.5, 0)
            else
                p:teleportTo(homeX, homeY, homeZ)
            end
        end
        T.onTick(self, function()
            if self.done then return end
            frames = frames + 1
            local place = self.places[index]
            if index == 0 then
                leave()
            elseif place then
                place.loaded = getSquare(place[1], place[2], 0) ~= nil
                place.house = place.house or (place.loaded and houseNear(place[1], place[2], 20))
                place.rolled = place.house and GardenLights.isRolled(place.house)
                if place.rolled or frames >= VISIT_FRAMES then
                    place.found = GardenLights.neighbourhood(place[1], place[2])
                    leave()
                end
            else
                self.homeLoaded = loadedAround(math.floor(homeX), math.floor(homeY), homeZ, HOME_RADIUS)
                self.done = self.homeLoaded or frames >= VISIT_FRAMES
            end
        end)
        T.waitUntil(function() return self.done end, (#self.places + 2) * VISIT_FRAMES)
    end,
    validate = function(self)
        for _, place in ipairs(self.places) do
            local where = place[1] .. "," .. place[2]
            if expect(place.loaded, where .. " never loaded") then
                expect(place.found == place[3], where .. " is " .. tostring(place.found) .. ", expected " .. place[3])
                if expect(place.house, "no house near " .. where) then
                    expect(place.rolled, "the house at " .. RenewableEnergy.GardenLights.buildingKey(place.house)
                        .. " was never rolled for garden lights")
                end
            end
        end
        expect(self.homeLoaded, "the start never loaded again")
    end,
})

-- At 0 the Garden Lights option leaves every house without lights.
test("renewable_energy_world_garden_lights_option_zero", {
    sandbox = { GardenLights = 0 },
    validate = function()
        local def = houseNearCharacter()
        if expect(def ~= nil, "no house near the character") then
            expect(RenewableEnergy.GardenLights.chanceFor(def) == 0, "houses get lights with the option at 0")
        end
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
    for radius = 1, 25 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local onRing = math.max(math.abs(dx), math.abs(dy)) == radius
                local coversCharacter = math.abs(dx) <= 1 and -dy >= -ahead and -dy <= behind
                if onRing and not coversCharacter then
                    local x, y, z = here:getX() + dx, here:getY() + dy, here:getZ()
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
    end
    return nil
end

-- The squares an arrow board takes north and south of its centre.
local TRAILER_AHEAD, TRAILER_BEHIND = 3, 3

-- A spawned arrow board's battery box holds its panels' modules, the first weathered and the
-- second weathered or cracked, deep cycle batteries at a part charge, and a charge controller;
-- and the trailer turns up among junkyard, traffic jam and tradesmen's vehicles.
test("renewable_energy_world_arrow_board_spawns_stocked", {
    sandbox = { LRMSolarPanels = 1, LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        local square = T.need(self, openStrip(TRAILER_AHEAD, TRAILER_BEHIND), "open ground for the arrow board")
        if not square then return end
        -- Only a vehicle in the world gets an id (BaseVehicle.createPhysics).
        local trailer = RenewableEnergy.ArrowBoard.spawn(square, "N")
        self.trailer = T.need(self, trailer and trailer:getId() ~= -1 and T.track(self, trailer), "room to spawn the arrow board")
    end,
    validate = function(self)
        local ArrowBoard, WorldSpawns = RenewableEnergy.ArrowBoard, RenewableEnergy.WorldSpawns
        for _, zone in ipairs({ "junkyard", "trafficjamn", "trafficjams", "trades" }) do
            expect(VehicleZoneDistribution[zone].vehicles[ArrowBoard.SCRIPT] ~= nil, "no arrow boards in " .. zone)
        end
        local part = self.trailer:getPartById(ArrowBoard.BATTERY_BOX)
        local container = part and part:getItemContainer()
        if not expect(container ~= nil, "the arrow board has no battery box") then
            return
        end
        local conditions = moduleConditions(container)
        expect(#conditions == ArrowBoard.STOCK.modules, #conditions .. " modules in the battery box")
        expect(conditions[1] == nil or inRange(conditions[1], WorldSpawns.WEATHERED), "its first module is at " .. tostring(conditions[1]))
        expect(conditions[2] == nil or isSiteCondition(conditions[2]), "its second module is at " .. tostring(conditions[2]))
        local count, charges = countBatteries(container)
        expect(inRange(count, ArrowBoard.STOCK.batteries), count .. " batteries in the battery box")
        expect(container:getCountType(ArrowBoard.STOCK.battery) == count, "the battery box holds other batteries")
        expectFoundCharges(charges, "the battery box")
        expect(container:getCountType(RenewableEnergy.Specs.controller) == 1, "the battery box has no charge controller")
    end,
})

-- Its battery box opens only with its lid open, from beside it, and takes a battery.
test("renewable_energy_world_arrow_board_battery_box_opens_with_lid", {
    run = function(self)
        local ArrowBoard = RenewableEnergy.ArrowBoard
        local square = T.need(self, openStrip(TRAILER_AHEAD, TRAILER_BEHIND), "open ground for the arrow board")
        self.trailer = square and T.vehicle(self, ArrowBoard.SCRIPT, { square = square })
        if not self.trailer then return end
        -- A spawned vehicle may lack parts, and the box opens freely without its lid.
        self.trailer:repair()
        local spot = T.need(self, self.trailer:getAreaCenter(ArrowBoard.BATTERY_BOX), "the battery box's area")
        if not spot then return end
        player():teleportTo(spot:getX(), spot:getY(), square:getZ())
    end,
    validate = function(self)
        local p = player()
        local lid, box = self.trailer:getPartById("TrunkDoor"), self.trailer:getPartById(RenewableEnergy.ArrowBoard.BATTERY_BOX)
        local container = box and box:getItemContainer()
        if not (expect(lid ~= nil and lid:getDoor() ~= nil, "the battery box has no lid")
                and expect(container ~= nil, "the battery box holds nothing")) then
            return
        end
        expect(not lid:getDoor():isLocked(), "the battery box starts locked")
        expect(not self.trailer:canAccessContainer(box:getIndex(), p), "the battery box opens with its lid shut")
        lid:getDoor():setOpen(true)
        expect(self.trailer:canAccessContainer(box:getIndex(), p), "the battery box doesn't open beside it with its lid open")
        -- A spawned trailer may come stocked, so count from what it already holds.
        local before = container:getCountType("RenewableEnergy.DeepCycleBattery")
        container:AddItem("RenewableEnergy.DeepCycleBattery")
        expect(container:getCountType("RenewableEnergy.DeepCycleBattery") == before + 1, "the battery box doesn't take a battery")
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
-- A car with nobody at the wheel holds its brakes, so each push has to beat them.
local PUSH_IMPULSE = 6000
-- The car is pushed whenever it rolls slower than this, in squares a second, until the trailer
-- has followed it TOW_SQUARES. Pushed every frame, it would speed off the open strip, and a crash
-- snaps a hitch more than two seconds old (Bullet.onVehicleConstraintImpulse).
local PUSH_SPEED = 5
local TOW_SQUARES = 2

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

-- How far the trailer has moved since it settled on the hitch, in squares.
local function towedSquares(self)
    return math.sqrt((self.trailer:getX() - self.start.x) ^ 2 + (self.trailer:getY() - self.start.y) ^ 2)
end

-- It spawns, a vanilla car hitches it as the game's own attachTrailer command does, and when the
-- car is pushed north the trailer follows, still on the hitch.
test("renewable_energy_world_arrow_board_towed_by_car", {
    run = function(self)
        local strip = T.need(self, openStrip(STRIP_AHEAD, STRIP_BEHIND), "open ground for a car and the arrow board")
        if not strip then return end
        local x, y, z = strip:getX(), strip:getY(), strip:getZ()
        local car = T.vehicle(self, TOWING_CAR, { square = strip })
        local trailer = car and T.vehicle(self, RenewableEnergy.ArrowBoard.SCRIPT, { square = getSquare(x, y + 5, z) })
        if not trailer then return end
        self.car, self.trailer = car, trailer
        -- A spawned vehicle may lack wheels or have flat tyres.
        car:repair()
        trailer:repair()
        -- The game moves, and checks the hitch of, only vehicles that have joined the cell.
        T.waitUntil(function()
            return inCell(car) and inCell(trailer) and car:isAtRest() and trailer:isAtRest()
        end, VEHICLE_FRAMES)
        T.step(function()
            local p = player()
            car:addPointConstraint(p, trailer, "trailer", "trailer")
            -- Out of the car's way; the runner puts the character back.
            p:teleportTo(x + 3.5, y + 2.5, z)
        end)
        -- The hitch pulls the trailer in over the next physics steps.
        T.waitUntil(function()
            return hitchGap(car, trailer) < ON_HITCH and car:getSpeed2D() < SETTLED_SPEED and trailer:getSpeed2D() < SETTLED_SPEED
        end, VEHICLE_FRAMES)
        T.step(function()
            self.start = { x = trailer:getX(), y = trailer:getY() }
        end)
        T.waitUntil(function()
            if towedSquares(self) >= TOW_SQUARES then
                return true
            end
            if car:getSpeed2D() < PUSH_SPEED then
                car:applyImpulseGeneric(car:getX(), car:getY(), car:getZ(), 0, -1, 0, PUSH_IMPULSE)
            end
            return false
        end, VEHICLE_FRAMES)
    end,
    validate = function(self)
        expect(self.trailer:getVehicleTowedBy() == self.car, "the trailer is not hitched to the car")
        local moved = towedSquares(self)
        expect(moved >= TOW_SQUARES, string.format("the trailer moved %.2f squares behind the pushed car", moved))
        local gap = hitchGap(self.car, self.trailer)
        expect(gap < ON_HITCH, string.format("the trailer's coupler is %.2f squares off the car's hitch", gap))
    end,
})
