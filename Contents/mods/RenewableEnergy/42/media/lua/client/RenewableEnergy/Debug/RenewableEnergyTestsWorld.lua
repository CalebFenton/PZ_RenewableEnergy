require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Sprites"
-- The game's Java class zombie.core.stash.Stash, which the mod's module name would hide.
local EngineStash = Stash
local Stash = require "RenewableEnergy/StashDescriptions"

-- Stash house and world spawn tests. See RenewableEnergyTestLib.lua for how the runner works.
-- Server Lua loads after client Lua, so WorldSpawns, FixedSpawns and Distributions are looked up
-- when a test runs.

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
-- stash name, which RenewableEnergyMapDefinitions draws. Vanilla town maps keep their own look.
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

-- A bank appears stocked with era batteries at a part charge, explored so that neither its room's
-- loot nor loot respawn ever adds to it. Placing needs no player, as on a dedicated server.
for _, spriteKey in ipairs({ "batteryBox", "batteryBank" }) do
    test("renewable_energy_world_" .. spriteKey .. "_spawns_stocked", {
        sandbox = { LRMBatteries = 1, LRMMisc = 1 },
        run = function(self)
            self.square = freeSquareNearPlayer()
            if self.square then
                self.object = RenewableEnergy.WorldSpawns.placeBank(self.square, spriteKey)
            end
        end,
        validate = function(self)
            if not expect(self.square ~= nil, "no free square next to the character") then
                return
            end
            local container = self.object and self.object:getContainer()
            if not expect(container ~= nil, "the bank has no container") then
                return
            end
            expect(instanceof(self.object, "IsoGenerator"), "the bank is no generator")
            expect(self.object:getTextureName() == Sprites[spriteKey], "the bank has the wrong tile")
            expect(container:isExplored(), "the bank is not explored")
            local stock = RenewableEnergy.WorldSpawns.BANK_STOCK[spriteKey].batteries
            local count, charges = countBatteries(container)
            expect(count >= stock.min and count <= stock.max,
                count .. " batteries in the bank, expected " .. stock.min .. " to " .. stock.max)
            expectFoundCharges(charges, "the bank")
        end,
        cleanup = removeObject,
    })
end

-- Over many banks, inverters turn up about as often as BANK_STOCK says, and a box never gets a
-- controller, which it has no slot for.
test("renewable_energy_world_bank_stock_rates", {
    sandbox = { LRMBatteries = 1, LRMMisc = 1 },
    validate = function()
        local WorldSpawns = RenewableEnergy.WorldSpawns
        local container = ItemContainer.new("crate", nil, nil)
        for _, spriteKey in ipairs({ "batteryBox", "batteryBank" }) do
            local stock = WorldSpawns.BANK_STOCK[spriteKey]
            local inverters, controllers, samples = 0, 0, 400
            for _ = 1, samples do
                container:removeAllItems()
                WorldSpawns.stockBank(container, spriteKey)
                local items = container:getItems()
                for i = 0, items:size() - 1 do
                    local fullType = items:get(i):getFullType()
                    if RenewableEnergy.Specs.inverters[fullType] then
                        inverters = inverters + 1
                    elseif RenewableEnergy.Specs.controllers[fullType] then
                        controllers = controllers + 1
                    end
                end
            end
            expectNear(spriteKey .. " share holding an inverter", inverters / samples, stock.inverter.chance, 0.1)
            if stock.controller then
                expectNear(spriteKey .. " share holding a controller", controllers / samples, stock.controller.chance, 0.1)
            else
                expect(controllers == 0, spriteKey .. " got " .. controllers .. " controllers")
            end
        end
        container:removeAllItems()
    end,
})

-- At 0 the battery option leaves world banks empty of batteries.
test("renewable_energy_world_bank_stock_lrm_zero", {
    sandbox = { LRMBatteries = 0, LRMMisc = 0 },
    validate = function()
        local container = ItemContainer.new("crate", nil, nil)
        for _ = 1, 20 do
            RenewableEnergy.WorldSpawns.stockBank(container, "batteryBank")
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
            self.object = RenewableEnergy.WorldSpawns.placeCrate(self.square)
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
        local modules = container:getCountType("RenewableEnergy.SolarModule")
        expect(modules >= 2 and modules <= 4, modules .. " modules in the crate, expected 2 to 4")
        local _, charges = countBatteries(container)
        expect(#charges >= 1 and #charges <= 2, #charges .. " batteries in the crate, expected 1 or 2")
        expectFoundCharges(charges, "the crate")
        expect(self.object:getOverlaySprite() ~= nil, "the full crate shows no overlay")
    end,
    cleanup = removeObject,
})

-- A fixed panel spot puts down the same object a player's placing would: the mount tile, which
-- gives back its item when picked up.
test("renewable_energy_world_fixed_panel_placed", {
    run = function(self)
        self.square = freeSquareNearPlayer()
        if self.square then
            RenewableEnergy.FixedSpawns.place(self.square, "rack", "S")
            self.object = findObjectWithSprite(self.square, Sprites.rack.S)
        end
    end,
    validate = function(self)
        if not expect(self.square ~= nil, "no free square next to the character") then
            return
        end
        if expect(self.object ~= nil, "no rack on the square") then
            expect(self.object:getProperties():get("CustomItem") == "RenewableEnergy.SolarRack",
                "the rack does not give back RenewableEnergy.SolarRack")
        end
    end,
    cleanup = removeObject,
})

-- Every fixed crate spot of the map is in a room, where the crate's loot belongs. Every panel spot
-- is outdoors, names a mount tile, and a wall panel hangs on a building: south-facing on the wall
-- of the room north of its square, east-facing on the room to the west.
test("renewable_energy_world_fixed_spots_placed_sensibly", {
    validate = function()
        local metaGrid = getWorld():getMetaGrid()
        local crates, panels = 0, 0
        for _, spot in ipairs(RenewableEnergy.FixedSpawns.spots()) do
            local x, y, z, kind, facing = spot[1], spot[2], spot[3], spot[4], spot[5]
            local where = kind .. " spot " .. x .. "," .. y .. "," .. z
            if kind == "crate" then
                crates = crates + 1
                expect(metaGrid:getRoomAt(x, y, z) ~= nil, where .. " is in no room")
            else
                panels = panels + 1
                local sprite = Sprites[kind]
                expect(sprite ~= nil and (facing == nil) == (type(sprite) == "string"), where .. " names no mount tile")
                expect(metaGrid:getRoomAt(x, y, z) == nil, where .. " is indoors")
                if kind == "wall" then
                    local wallX, wallY = x - (facing == "E" and 1 or 0), y - (facing == "S" and 1 or 0)
                    expect(metaGrid:getRoomAt(wallX, wallY, z) ~= nil, where .. " has no building behind it")
                end
            end
        end
        expect(crates > 0 and panels > 0, "this map has " .. crates .. " crate and " .. panels .. " panel spots")
    end,
})
