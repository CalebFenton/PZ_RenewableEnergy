require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Sprites"
-- The game's Java class zombie.core.stash.Stash, which the mod's module name would hide.
local EngineStash = Stash
local Stash = require "RenewableEnergy/StashHouses"

-- Stash house, world spawn, solar site, garden light and arrow board tests. See
-- RenewableEnergyTestLib.lua for how the runner works. Server Lua loads after client Lua, so
-- WorldSpawns, SolarSites, GardenLights, ArrowBoard and Distributions are looked up when a test
-- runs.

local test, expect, expectNear, player = RenewableEnergyTest.test, RenewableEnergyTest.expect,
    RenewableEnergyTest.expectNear, RenewableEnergyTest.player

local Sprites = RenewableEnergy.Sprites

-- A free square next to the character, to put a spawn on.
local function freeSquareNearPlayer()
    local here = player():getSquare()
    for _, direction in ipairs({ IsoDirections.N, IsoDirections.W, IsoDirections.S, IsoDirections.E,
                                 IsoDirections.NW, IsoDirections.NE, IsoDirections.SW, IsoDirections.SE }) do
        local square = here:getAdjacentSquare(direction)
        if square and square:isFree(false) then
            return square
        end
    end
    return nil
end

local function findObjectWithSprite(square, spriteName)
    local objects = square:getObjects()
    for i = objects:size() - 1, 0, -1 do
        local object = objects:get(i)
        if object:getTextureName() == spriteName then
            return object
        end
    end
    return nil
end

local function removeObject(self)
    if self.square and self.object then
        self.square:transmitRemoveItemFromSquare(self.object)
    end
end

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

-- With Stash Houses at 2 or 3 the stashes join the list StashSystem reads, once however often the
-- game loads; at 1 they stay out of it. The test world runs at 1, so the list is put back after.
test("renewable_energy_world_stashes_register_by_option", {
    run = function(self)
        self.results = {}
        for _, mode in ipairs({ 1, 2, 3, 4 }) do
            SandboxVars.RenewableEnergy.StashMode = mode
            self.results[mode] = { registered = Stash.register() }
            Stash.register()
            local count = 0
            for _, description in ipairs(StashDescriptions) do
                if Stash.descriptions[description] then
                    count = count + 1
                end
            end
            self.results[mode].count = count
            for i = #StashDescriptions, 1, -1 do
                if Stash.descriptions[StashDescriptions[i]] then
                    table.remove(StashDescriptions, i)
                end
            end
        end
    end,
    sandbox = { StashMode = 1 },
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

-- Relisting a house makes newly found maps point at it again.
test("renewable_energy_world_unfound_stash_relisted", {
    validate = function()
        local possible = StashSystem.getPossibleStashes()
        for stashMap in pairs(Stash.descriptions) do
            for i = possible:size() - 1, 0, -1 do
                if possible:get(i):getName() == stashMap.name then
                    possible:remove(possible:get(i))
                end
            end
        end
        Stash.relistUnfound()
        local present = {}
        for i = 0, possible:size() - 1 do
            present[possible:get(i):getName()] = true
        end
        local metaGrid = getWorld():getMetaGrid()
        for stashMap in pairs(Stash.descriptions) do
            local room = metaGrid:getRoomAt(stashMap.buildingX, stashMap.buildingY, 0)
            local building = room and room:getBuilding()
            if building and not building:isHasBeenVisited() then
                expect(present[stashMap.name], stashMap.name .. " was not restored")
            end
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

local function hasPair(items, fullType, weight)
    for i = 1, #items - 1, 2 do
        if items[i] == fullType and items[i + 1] == weight then
            return true
        end
    end
    return false
end

-- With Stash Houses at 2 or 3 every stash's map goes into its outfits' corpse loot, once; at 1 or
-- 4 none does.
test("renewable_energy_world_stash_maps_in_corpse_loot", {
    run = function(self)
        local D = RenewableEnergy.Distributions
        self.found = {}
        for _, mode in ipairs({ 1, 2, 3, 4 }) do
            SandboxVars.RenewableEnergy.StashMode = mode
            D.apply()
            D.apply()
            local found = {}
            for stashMap, added in pairs(Stash.descriptions) do
                for _, target in ipairs(added.targets or {}) do
                    local items = SuburbsDistributions.all[target].items
                    local count = 0
                    for i = 1, #items - 1, 2 do
                        if items[i] == stashMap.item then
                            count = count + 1
                        end
                    end
                    found[stashMap.name .. " in " .. target] = { count = count, weight = hasPair(items, stashMap.item, added.rarity) }
                end
            end
            self.found[mode] = found
        end
    end,
    sandbox = { StashMode = 1 },
    validate = function(self)
        for mode, found in pairs(self.found) do
            local wanted = (mode == 2 or mode == 3) and 1 or 0
            for where, result in pairs(found) do
                expect(result.count == wanted, "Stash Houses " .. mode .. ": " .. where .. " " .. result.count .. " times")
                expect(wanted == 0 or result.weight, "Stash Houses " .. mode .. ": " .. where .. " has the wrong weight")
            end
        end
    end,
    cleanup = function()
        RenewableEnergy.Distributions.apply()
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

-- The closest free square indoors, where a bank may stand.
local function indoorSquareNearPlayer()
    local here = player():getSquare()
    for radius = 1, 40 do
        for dx = -radius, radius do
            for _, dy in ipairs({ -radius, radius }) do
                local square = getSquare(here:getX() + dx, here:getY() + dy, 0)
                if square and square:isFree(false) and RenewableEnergy.PowerBank.canPlaceBank(square)
                        and square:getObjects():size() <= 2 then
                    return square
                end
            end
        end
    end
    return nil
end

-- A bank appears stocked with era batteries at a part charge, explored so that neither its room's
-- loot nor loot respawn ever adds to it. Placing needs no player, as on a dedicated server.
for _, stockName in ipairs({ "shed", "electronicsStorage", "powerYard" }) do
    test("renewable_energy_world_bank_" .. stockName .. "_spawns_stocked", {
        sandbox = { LRMBatteries = 1, LRMMisc = 1 },
        run = function(self)
            self.square = indoorSquareNearPlayer()
            if self.square then
                self.object = RenewableEnergy.WorldSpawns.placeBank(self.square, stockName)
            end
        end,
        validate = function(self)
            if not expect(self.square ~= nil, "no free square indoors near the character") then
                return
            end
            local container = self.object and self.object:getContainer()
            if not expect(container ~= nil, "the bank has no container") then
                return
            end
            local stock = RenewableEnergy.WorldSpawns.BANK_STOCK[stockName]
            expect(instanceof(self.object, "IsoGenerator"), "the bank is no generator")
            expect(self.object:getTextureName() == Sprites[stock.sprite], "the bank has the wrong tile")
            expect(container:isExplored(), "the bank is not explored")
            local count, charges = countBatteries(container)
            expect(count >= stock.batteries.min and count <= stock.batteries.max,
                count .. " batteries in the bank, expected " .. stock.batteries.min .. " to " .. stock.batteries.max)
            expectFoundCharges(charges, "the bank")
        end,
        cleanup = removeObject,
    })
end

-- Banks only work indoors, so a world spawn never puts one on an outdoor square.
test("renewable_energy_world_bank_refused_outdoors", {
    run = function(self)
        self.square = freeSquareNearPlayer()
        if self.square and not self.square:isOutside() then
            self.square = nil
        end
        if self.square then
            self.object = RenewableEnergy.WorldSpawns.placeBank(self.square, "shed")
        end
    end,
    validate = function(self)
        if not expect(self.square ~= nil, "no free square outdoors next to the character") then
            return
        end
        expect(self.object == nil, "a bank was placed outdoors")
        expect(findObjectWithSprite(self.square, Sprites.batteryBoxWood) == nil, "a battery box stands outdoors")
    end,
    cleanup = removeObject,
})

-- Over many banks, each part turns up about as often as BANK_STOCK says, and never in a bank
-- without a slot for it: a box takes no controller.
test("renewable_energy_world_bank_stock_rates", {
    sandbox = { LRMBatteries = 1, LRMMisc = 1 },
    validate = function()
        local WorldSpawns = RenewableEnergy.WorldSpawns
        local container = ItemContainer.new("crate", nil, nil)
        for _, stockName in ipairs({ "shed", "farmStorage" }) do
            local stock = WorldSpawns.BANK_STOCK[stockName]
            local found, samples = { inverter = 0, controller = 0, charger = 0 }, 400
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
            for kind, count in pairs(found) do
                local part = stock[kind]
                expectNear(stockName .. " share holding a " .. kind, count / samples, part and part.chance or 0, 0.1)
            end
        end
        local box = RenewableEnergy.Specs.banks["RenewableEnergy.BatteryBoxWood"]
        expect(box.maxControllers == 0, "the battery box now takes controllers; update this test")
        container:removeAllItems()
    end,
})

-- At 0 the battery option leaves world banks empty of batteries.
test("renewable_energy_world_bank_stock_lrm_zero", {
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
        self.square = freeSquareNearPlayer()
        if self.square then
            self.object = RenewableEnergy.WorldSpawns.placeCrate(self.square, "kit")
        end
    end,
    validate = function(self)
        if not expect(self.square ~= nil, "no free square next to the character") then
            return
        end
        local container = self.object and self.object:getContainer()
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
        expect(self.object:getOverlaySprite() ~= nil, "the full crate shows no overlay")
    end,
    cleanup = removeObject,
})

-- Cracked modules -------------------------------------------------------------------------------

-- Farm storage shelves get cracked modules, at condition 20 to 50, and a bedroom's furniture
-- none. At the highest option every farm storage shelf gets one, so that nothing is left to
-- chance; at the default the chance is small but there.
test("renewable_energy_world_cracked_modules", {
    sandbox = { LRMSolarPanels = 100 },
    validate = function()
        local Distributions, WorldSpawns = RenewableEnergy.Distributions, RenewableEnergy.WorldSpawns
        local container = ItemContainer.new("crate", nil, nil)
        local samples = 200
        for _ = 1, samples do
            Distributions.addCrackedModules("farmstorage", "metal_shelves", container)
        end
        local conditions = moduleConditions(container)
        expect(#conditions == samples, #conditions .. " cracked modules on " .. samples .. " farm storage shelves")
        for _, condition in ipairs(conditions) do
            if not expect(inRange(condition, WorldSpawns.CRACKED), "a cracked module is at condition " .. condition) then
                break
            end
        end
        container:removeAllItems()
        for _ = 1, samples do
            Distributions.addCrackedModules("bedroom", "wardrobe", container)
            Distributions.addCrackedModules("garage", "fridge", container)
        end
        expect(container:getItems():size() == 0, container:getItems():size() .. " modules in bedrooms and garage fridges")
        SandboxVars.RenewableEnergy.LRMSolarPanels = 1
        local chance = Distributions.crackedModuleChance(Distributions.CRACKED_MODULE_ROOMS.garage)
        expect(chance > 0 and chance < 0.1, "a garage shelf holds a cracked module with chance " .. chance)
        container:removeAllItems()
    end,
})

-- Solar sites -----------------------------------------------------------------------------------

local function countWithSprite(square, spriteName)
    local count = 0
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        if objects:get(i):getTextureName() == spriteName then
            count = count + 1
        end
    end
    return count
end

-- A site goes down once when its chunk loads, and its spot is forgotten, so loading the chunk
-- again places nothing. Its pump's pole mount holds 1 or 2 modules at site conditions.
test("renewable_energy_world_site_placed_once", {
    run = function(self)
        self.square = freeSquareNearPlayer()
        if not (self.square and self.square:isOutside()) then
            self.square = nil
            return
        end
        local SolarSites = RenewableEnergy.SolarSites
        local x, y = self.square:getX(), self.square:getY()
        SolarSites.addSite({ kind = "stockTank", name = "test", panels = { { x, y, 0, "rackMetal", "S" } } })
        self.waiting = SolarSites.spotAt(x, y, 0) ~= nil
        SolarSites.placeChunk(math.floor(x / 8), math.floor(y / 8))
        self.leftOver = SolarSites.spotAt(x, y, 0) ~= nil
        SolarSites.placeChunk(math.floor(x / 8), math.floor(y / 8))
        self.object = findObjectWithSprite(self.square, Sprites.rack.metal.S)
    end,
    validate = function(self)
        if not expect(self.square ~= nil, "no free square outdoors next to the character") then
            return
        end
        expect(self.waiting, "the site kept no spot to place")
        expect(not self.leftOver, "the site's spot was not forgotten once placed")
        local racks = countWithSprite(self.square, Sprites.rack.metal.S)
        expect(racks == 1, racks .. " racks on the spot after loading its chunk twice")
        if not self.object then
            return
        end
        expect(self.object:getProperties():get("CustomItem") == "RenewableEnergy.SolarRackMetal",
            "the rack does not give back RenewableEnergy.SolarRackMetal")
        local modules = self.object:getModData()[RenewableEnergy.PowerBank.MODULES] or {}
        expect(#modules >= 1 and #modules <= 2, #modules .. " modules on the pump's mount, expected 1 or 2")
        for _, module in ipairs(modules) do
            expect(module.type == MODULE and isSiteCondition(module.condition),
                "the pump's mount holds " .. tostring(module.type) .. " at " .. tostring(module.condition))
        end
    end,
    cleanup = removeObject,
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

-- The closest house to the character.
local function nearbyHouse()
    local here = player():getSquare()
    for radius = 1, 60 do
        for dx = -radius, radius do
            for _, dy in ipairs({ -radius, radius }) do
                local square = getSquare(here:getX() + dx, here:getY() + dy, 0)
                local building = square and square:getBuilding()
                if building and building:getDef():isResidential() then
                    return building:getDef()
                end
            end
        end
    end
    return nil
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
        self.def = nearbyHouse()
        if not self.def then
            return
        end
        local store = ModData.getOrCreate(GardenLights.MOD_DATA)
        self.before = lightsAround(self.def)
        store[GardenLights.buildingKey(self.def)] = nil
        self.first = GardenLights.roll(self.def, true)
        self.rolled = GardenLights.isRolled(self.def)
        self.second = GardenLights.roll(self.def, true)
        self.after = lightsAround(self.def)
    end,
    validate = function(self)
        if not expect(self.def ~= nil, "no house near the character") then
            return
        end
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
    cleanup = function(self)
        for key, light in pairs(self.after or {}) do
            if not self.before[key] then
                light:getSquare():transmitRemoveItemFromSquare(light)
            end
        end
    end,
})

-- Ticks to stay at each place: the map's town and trailer park zones are only there once the
-- cell around a place has loaded, as it has when a house there is rolled, and houses roll on the
-- first game minute after their surroundings load. The last visit, home, lets the start load
-- again before the next test.
local VISIT_TICKS = 420

-- The house nearest the square, or nil.
local function houseNear(x, y)
    for radius = 0, 20 do
        for dx = -radius, radius do
            for _, dy in ipairs({ -radius, radius }) do
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

-- The neighbourhood sets the chance: a rich street (Riverside's Rich loot zone) most, a trailer
-- park least, an ordinary street (the start, in Muldraugh) in between. A farmhouse counts as
-- ordinary. And a house far from the start is rolled once the character has been there. The
-- character visits each place in turn and comes back; a teleport from inside a timed action
-- doesn't stick, so OnTick moves them.
test("renewable_energy_world_garden_light_neighbourhoods", {
    run = function(self)
        local p = player()
        self.home = { x = p:getX(), y = p:getY(), z = p:getZ() }
        self.places = {
            { 6680, 5320, "rich" }, { 5370, 5945, "poor" }, { 7340, 5993, "ordinary" }, { 10835, 10144, "ordinary" },
        }
        local count = #self.places
        local tick = 0
        local function onTick()
            tick = tick + 1
            local index = math.floor((tick - 1) / VISIT_TICKS) + 1
            local place = self.places[index]
            local step = (tick - 1) % VISIT_TICKS
            if step == 0 then
                if place then
                    p:teleportTo(place[1] + 0.5, place[2] + 0.5, 0)
                else
                    p:teleportTo(self.home.x, self.home.y, self.home.z)
                    Events.OnTick.Remove(onTick)
                end
            elseif place and step == VISIT_TICKS - 1 then
                place.loaded = getSquare(place[1], place[2], 0) ~= nil
                place.found = RenewableEnergy.GardenLights.neighbourhood(place[1], place[2])
                local house = houseNear(place[1], place[2])
                place.house = house and RenewableEnergy.GardenLights.buildingKey(house)
                place.rolled = house and RenewableEnergy.GardenLights.isRolled(house)
            end
        end
        Events.OnTick.Add(onTick)
        RenewableEnergyTest.wait((count + 1) * VISIT_TICKS + 60)
    end,
    validate = function(self)
        for _, place in ipairs(self.places or {}) do
            local where = place[1] .. "," .. place[2]
            if expect(place.loaded, where .. " never loaded") then
                expect(place.found == place[3], where .. " is " .. tostring(place.found) .. ", expected " .. place[3])
                if expect(place.house ~= nil, "no house near " .. where) then
                    expect(place.rolled, "the house at " .. place.house .. " was never rolled for garden lights")
                end
            end
        end
        local chance = RenewableEnergy.GardenLights.CHANCE
        expect(chance.rich > chance.ordinary and chance.ordinary > chance.poor, "the neighbourhood chances are out of order")
    end,
    cleanup = function(self)
        local p = player()
        if self.home and (math.abs(p:getX() - self.home.x) > 1 or math.abs(p:getY() - self.home.y) > 1) then
            p:teleportTo(self.home.x, self.home.y, self.home.z)
        end
    end,
})

-- At 0 the Garden Lights option leaves every house without lights.
test("renewable_energy_world_garden_lights_option_zero", {
    sandbox = { GardenLights = 0 },
    validate = function()
        local def = nearbyHouse()
        if expect(def ~= nil, "no house near the character") then
            expect(RenewableEnergy.GardenLights.chanceFor(def) == 0, "houses get lights with the option at 0")
        end
    end,
})

-- Arrow board -------------------------------------------------------------------------------------

local function isClearForVehicle(x, y, z)
    local square = getSquare(x, y, z)
    return square ~= nil and square:isOutside() and square:isFree(false) and not square:HasTree()
        and square:getVehicleContainer() == nil
end

-- The closest square with open ground three squares across and seven along, for the trailer.
local function openGround()
    local here = player():getSquare()
    for radius = 3, 25 do
        for dx = -radius, radius do
            for _, dy in ipairs({ -radius, radius }) do
                local x, y, z = here:getX() + dx, here:getY() + dy, 0
                local open = true
                for sx = x - 1, x + 1 do
                    for sy = y - 3, y + 3 do
                        open = open and isClearForVehicle(sx, sy, z)
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

-- A spawned arrow board's battery box holds its two modules (the first weathered, the second
-- weathered or cracked), 4 to 6 deep cycle batteries at a part charge, and a charge controller;
-- and the trailer joins the junkyard and traffic jam vehicles.
test("renewable_energy_world_arrow_board_battery_box", {
    sandbox = { LRMSolarPanels = 1, LRMBatteries = 1, LRMMisc = 1 },
    run = function(self)
        local square = openGround()
        self.vehicle = square and RenewableEnergy.ArrowBoard.spawn(square, "N")
    end,
    validate = function(self)
        local ArrowBoard, WorldSpawns = RenewableEnergy.ArrowBoard, RenewableEnergy.WorldSpawns
        for _, zone in ipairs({ "junkyard", "trafficjamn", "trafficjams", "trades" }) do
            expect(VehicleZoneDistribution[zone].vehicles[ArrowBoard.SCRIPT] ~= nil, "no arrow boards in " .. zone)
        end
        if not expect(self.vehicle ~= nil and self.vehicle:getId() ~= -1, "no room to spawn the arrow board") then
            return
        end
        local part = self.vehicle:getPartById(ArrowBoard.BATTERY_BOX)
        local container = part and part:getItemContainer()
        if not expect(container ~= nil, "the arrow board has no battery box") then
            return
        end
        local conditions = moduleConditions(container)
        expect(#conditions == ArrowBoard.STOCK.modules, #conditions .. " modules in the battery box")
        expect(conditions[1] == nil or inRange(conditions[1], WorldSpawns.WEATHERED), "its first module is at " .. tostring(conditions[1]))
        expect(conditions[2] == nil or isSiteCondition(conditions[2]), "its second module is at " .. tostring(conditions[2]))
        local count, charges = countBatteries(container)
        local range = ArrowBoard.STOCK.batteries
        expect(count >= range.min and count <= range.max, count .. " batteries in the battery box")
        expect(container:getCountType(ArrowBoard.STOCK.battery) == count, "the battery box holds other batteries")
        expectFoundCharges(charges, "the battery box")
        expect(container:getCountType(RenewableEnergy.Specs.controller) == 1, "the battery box has no charge controller")
    end,
    cleanup = function(self)
        if self.vehicle then
            self.vehicle:permanentlyRemove()
        end
    end,
})
