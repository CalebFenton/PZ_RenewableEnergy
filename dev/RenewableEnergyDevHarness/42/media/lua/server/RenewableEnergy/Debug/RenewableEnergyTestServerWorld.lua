-- The authority's half of the world, trailer, tile and loot tests (PZHarness.Test.server): stash
-- houses, world spawns, solar sites, garden lights and loot exist only where the authority runs
-- them (single player, or the server, whose loot tables alone hold the mod's entries), and the
-- arrow board's panels, box and frame change only there. Single player runs these handlers in the
-- same Lua state, so the tests use them in both modes. Server Lua loads after client Lua, and the
-- mod's server files are empty on a multiplayer client, so the handlers look the mod up when they
-- run. Every answer is plain values, which cross the network.
--
-- Checks that only read the authority's state answer { failures = { message, ... } }, which the
-- test expects to be empty (RenewableEnergyTest.expectNoFailures). The module's helpers serve the
-- client's half too, which requires this file when a test runs, since it loads after client Lua.
-- Only registers handlers, so a --stay rerun loads it again (RELOAD_FILES).

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Debug/RenewableEnergyLoot"
-- The game's Java class zombie.core.stash.Stash, which the mod's module name would hide.
local EngineStash = Stash
local Stash = require "RenewableEnergy/StashHouses"

local handler = PZHarness.serverHandler
local objectWithSprite, countPairs = PZHarness.Fixtures.objectWithSprite, PZHarness.Fixtures.countPairs
local Sprites = RenewableEnergy.Sprites

local World = {}

local MODULE = "RenewableEnergy.SolarModule"

-- A check's findings: expect(condition, message) records the message when the condition fails,
-- as the test library's expect does, and the handler answers with the list.
local function newCheck()
    local failures = {}
    local function expect(condition, message)
        if not condition then
            table.insert(failures, message)
        end
        return condition
    end
    local function expectNear(label, actual, expected, tolerance)
        return expect(type(actual) == "number" and math.abs(actual - expected) <= (tolerance or 0.0001),
            label .. " is " .. tostring(actual) .. ", expected " .. expected)
    end
    return expect, expectNear, failures
end

local function squareAt(args)
    return args and args.x and getSquare(args.x, args.y, args.z)
end

-- Removes a tile object the way the game does, so the mod's removal handlers run.
local function removeObject(object)
    if object:getObjectIndex() == -1 then
        return
    end
    if RenewableEnergy.PowerBank.isBank(object) then
        RenewableEnergy.PowerBank.remove(object)
    else
        object:getSquare():transmitRemoveItemFromSquare(object)
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

local function batteryCharges(container)
    local charges = {}
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        if RenewableEnergy.Battery.isBattery(items:get(i)) then
            table.insert(charges, RenewableEnergy.Battery.getCharge(items:get(i)))
        end
    end
    return charges
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

-- Stash houses ----------------------------------------------------------------------------------

local function stashCount()
    local count = 0
    for _ in pairs(Stash.descriptions) do
        count = count + 1
    end
    return count
end

-- StashSystem gives up without an error when the stash building isn't a building, prepares only a
-- building whose bounds strictly contain the building square (doBuildingStash), and stocks the
-- crate only if its square is in a room of that building, so a wrong coordinate is an empty house.
handler("stashHousesResolve", function()
    local expect, _, failures = newCheck()
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
    return { failures = failures }
end)

-- Takes the mod's houses out of StashDescriptions.
local function unregister()
    for i = #StashDescriptions, 1, -1 do
        if Stash.descriptions[StashDescriptions[i]] then
            table.remove(StashDescriptions, i)
        end
    end
end

-- Registers the houses at each Stash Houses option, twice, and answers by option what register
-- returned and how many of the mod's houses StashDescriptions then lists, with how many it has.
handler("stashRegister", function()
    local options = SandboxVars.RenewableEnergy
    local saved = options.StashMode
    local results = {}
    for _, mode in ipairs({ 1, 2, 3, 4 }) do
        unregister()
        options.StashMode = mode
        local registered = Stash.register()
        Stash.register()
        local count = 0
        for _, description in ipairs(StashDescriptions) do
            if Stash.descriptions[description] then
                count = count + 1
            end
        end
        results[mode] = { registered = registered, count = count }
    end
    options.StashMode = saved
    unregister()
    Stash.register()
    return { results = results, houses = stashCount() }
end)

-- The engine's own load and annotate path, which a found map takes, on a fresh copy of each stash
-- so the world's stash state stays as it was.
handler("stashMapsAnnotate", function()
    local expect, _, failures = newCheck()
    for stashMap in pairs(Stash.descriptions) do
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
    return { failures = failures }
end)

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

-- Puts each house through Stash.relistUnfound in every case of `args.cases` ({ visited, read }),
-- then back as it was. Answers { name, case, relisted } for each, in order.
handler("stashRelist", function(_, args)
    local metaGrid = getWorld():getMetaGrid()
    local houses = {}
    for stashMap in pairs(Stash.descriptions) do
        local room = metaGrid:getRoomAt(stashMap.buildingX, stashMap.buildingY, 0)
        local building = room and room:getBuilding()
        if not building then
            return nil, "the building of " .. stashMap.name
        end
        table.insert(houses, { name = stashMap.name, building = building })
    end
    if #houses == 0 then
        return nil, "a stash house"
    end
    local possible, alreadyRead = StashSystem.getPossibleStashes(), StashSystem.getAlreadyReadMap()
    local savedPossible = {}
    for i = 0, possible:size() - 1 do
        table.insert(savedPossible, possible:get(i))
    end
    local results = {}
    for _, house in ipairs(houses) do
        local name, building = house.name, house.building
        local visited, read = building:isHasBeenVisited(), alreadyRead:contains(name)
        for i, case in ipairs(args.cases) do
            removePossibleStash(name)
            building:setHasBeenVisited(case.visited)
            alreadyRead:remove(name)
            if case.read then
                alreadyRead:add(name)
            end
            Stash.relistUnfound()
            table.insert(results, { name = name, case = i, relisted = isPossibleStash(name) })
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
    return { results = results }
end)

local function descriptionNamed(name)
    for stashMap, added in pairs(Stash.descriptions) do
        if stashMap.name == name then
            return stashMap, added
        end
    end
    return nil
end

-- Stash.stockFromStart with the engine handed the houses, every knownOnStart chance made certain
-- and StashSystem's possible list, which isStashBuilding also reads, emptied of them, so that what
-- it reports afterwards is the stocking queue alone. Answers by house whether it was queued for
-- stocking, marked as read, and has a chance at all; then puts everything back.
handler("stashKnownOnStart", function()
    local all, possible = StashSystem.getAllStashes(), StashSystem.getPossibleStashes()
    local added, chances = {}, {}
    for stashMap, extra in pairs(Stash.descriptions) do
        if not StashSystem.getStash(stashMap.name) then
            local engineStash = EngineStash.new(stashMap.name)
            engineStash:load(stashMap)
            all:add(engineStash)
            table.insert(added, engineStash)
        end
        chances[extra] = extra.knownOnStart
        extra.knownOnStart = extra.knownOnStart and 100
    end
    for i = possible:size() - 1, 0, -1 do
        if descriptionNamed(possible:get(i):getName()) then
            possible:remove(possible:get(i))
        end
    end
    Stash.stockFromStart()
    local metaGrid = getWorld():getMetaGrid()
    local houses = {}
    for stashMap, extra in pairs(Stash.descriptions) do
        local room = metaGrid:getRoomAt(stashMap.buildingX, stashMap.buildingY, 0)
        houses[stashMap.name] = {
            queued = room ~= nil and StashSystem.isStashBuilding(room:getBuilding()),
            read = StashSystem.getAlreadyReadMap():contains(stashMap.name),
            hasChance = chances[extra] ~= nil,
        }
    end
    for extra, chance in pairs(chances) do
        extra.knownOnStart = chance
    end
    for _, engineStash in ipairs(added) do
        all:remove(engineStash)
    end
    Stash.relistUnfound()
    return { houses = houses }
end)

-- The prepper's map drops from survivalist and bandit corpses, whichever outfit variant they wear,
-- and every corpse list a map names exists.
handler("prepperMapTargets", function()
    local expect, _, failures = newCheck()
    local all = SuburbsDistributions.all
    for stashMap, added in pairs(Stash.descriptions) do
        for _, target in ipairs(added.targets or {}) do
            expect(all[target] ~= nil and all[target].items ~= nil, stashMap.name .. ": no loot list " .. target)
        end
    end
    local _, prepper = descriptionNamed("RenewableEnergy_CrowcallRoad")
    if not expect(prepper ~= nil, "no Crowcall Road stash") then
        return { failures = failures }
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
    return { failures = failures }
end)

-- The corpse loot at each Stash Houses option: for every stash and outfit list, how often its map
-- is listed and at what weight, against the stash's rarity.
handler("stashMapsInCorpseLoot", function()
    local D = RenewableEnergy.Distributions
    local options = SandboxVars.RenewableEnergy
    local saved = options.StashMode
    local found = {}
    for _, mode in ipairs({ 1, 2, 3, 4 }) do
        options.StashMode = mode
        D.apply()
        D.apply()
        for stashMap, added in pairs(Stash.descriptions) do
            for _, target in ipairs(added.targets or {}) do
                local count, weight = countPairs(SuburbsDistributions.all[target].items, stashMap.item)
                table.insert(found, {
                    mode = mode, where = stashMap.name .. " in " .. target, count = count, weight = weight, rarity = added.rarity,
                })
            end
        end
    end
    options.StashMode = saved
    D.apply()
    return { found = found }
end)

-- World spawns -----------------------------------------------------------------------------------

-- What a world spawn left in `container`: its batteries' charges, its modules' conditions and how
-- many items it holds.
local function stockOf(container)
    return {
        charges = batteryCharges(container), modules = moduleConditions(container),
        items = container:getItems():size(), explored = container:isExplored(),
    }
end

-- WorldSpawns.placeBank with BANK_STOCK[args.stock] on the square at `args`, as a room seen for the
-- first time places one. Answers whether it placed one, its tile and stock, and whether a battery
-- box stands on the square. Removed when the test ends.
handler("worldBank", function(_, args, defer)
    local square = squareAt(args)
    if not square then
        return nil, "the bank's square loaded on the server"
    end
    local bank = RenewableEnergy.WorldSpawns.placeBank(square, args.stock)
    if bank then
        defer(function() removeObject(bank) end)
    end
    local answer = { placed = bank ~= nil, boxOnSquare = objectWithSprite(square, Sprites.batteryBoxWood) ~= nil }
    if bank then
        answer.sprite = bank:getTextureName()
        answer.stock = stockOf(bank:getContainer())
    end
    return answer
end)

-- Over many banks, each part turns up about as often as BANK_STOCK says, and a battery box never
-- comes with a charge controller.
handler("bankStockRates", function(_, args)
    local expect, expectNear, failures = newCheck()
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local container = ItemContainer.new("crate", nil, nil)
    local samples = args.samples
    -- Found batteries are sent to the clients that see them, and a server can't send an item of a
    -- container that isn't in the world; the parts' rates don't depend on the batteries.
    local options = SandboxVars.RenewableEnergy
    local batteries = options.LRMBatteries
    options.LRMBatteries = 0
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
        if args.boxTiles[stock.sprite] then
            expect(found.controller == 0, found.controller .. " of " .. samples .. " " .. stockName .. " battery boxes hold a charge controller")
        end
    end
    container:removeAllItems()
    options.LRMBatteries = batteries
    return { failures = failures }
end)

-- How many items `args.times` electronics storage banks get at the save's options.
handler("bankStockCount", function(_, args)
    local container = ItemContainer.new("crate", nil, nil)
    for _ = 1, args.times do
        RenewableEnergy.WorldSpawns.stockBank(container, "electronicsStorage")
    end
    local count = container:getItems():size()
    container:removeAllItems()
    return { items = count }
end)

-- WorldSpawns.placeCrate with CRATE_STOCK[args.stock] on the square at `args`. Answers its
-- container type, stock and overlay. Removed when the test ends.
handler("worldCrate", function(_, args, defer)
    local square = squareAt(args)
    if not square then
        return nil, "the crate's square loaded on the server"
    end
    local crate = RenewableEnergy.WorldSpawns.placeCrate(square, args.stock)
    defer(function() removeObject(crate) end)
    local container = crate:getContainer()
    if not container then
        return { container = false }
    end
    return { container = true, type = container:getType(), stock = stockOf(container), overlay = crate:getOverlaySprite() ~= nil }
end)

-- Farm storage shelves get cracked modules, at condition 20 to 50, and a bedroom's furniture
-- none, at the save's Solar Panels loot option; at the option's default the chance is small but
-- there.
handler("crackedModules", function(_, args)
    local expect, _, failures = newCheck()
    local Distributions = RenewableEnergy.Distributions
    local container = ItemContainer.new("crate", nil, nil)
    for _ = 1, args.samples do
        Distributions.addCrackedModules("farmstorage", "metal_shelves", container)
    end
    local conditions = moduleConditions(container)
    container:removeAllItems()
    for _ = 1, args.samples do
        Distributions.addCrackedModules("bedroom", "wardrobe", container)
        Distributions.addCrackedModules("garage", "fridge", container)
    end
    local elsewhere = container:getItems():size()
    container:removeAllItems()
    local options = SandboxVars.RenewableEnergy
    local saved = options.LRMSolarPanels
    options.LRMSolarPanels = 1
    local defaultChance = Distributions.crackedModuleChance(Distributions.CRACKED_MODULE_ROOMS.garage)
    options.LRMSolarPanels = saved
    expect(#conditions == args.samples, #conditions .. " cracked modules on " .. args.samples .. " farm storage shelves")
    for _, condition in ipairs(conditions) do
        if not expect(inRange(condition, RenewableEnergy.WorldSpawns.CRACKED), "a cracked module is at condition " .. condition) then
            break
        end
    end
    expect(elsewhere == 0, elsewhere .. " modules in bedrooms and garage fridges")
    expect(defaultChance > 0 and defaultChance < 0.1, "a garage shelf holds a cracked module with chance " .. defaultChance)
    return { failures = failures }
end)

-- What WorldSpawns stocks, which only the authority loads: for each BANK_STOCK name of
-- `args.names` its tile (a Sprites field) and battery count range, and the module conditions of
-- crates.
handler("worldSpawnStock", function(_, args)
    local WorldSpawns = RenewableEnergy.WorldSpawns
    local banks = {}
    for _, name in ipairs(args.names) do
        local stock = WorldSpawns.BANK_STOCK[name]
        banks[name] = { sprite = stock.sprite, batteries = { min = stock.batteries.min, max = stock.batteries.max } }
    end
    return { banks = banks, cracked = WorldSpawns.CRACKED, weathered = WorldSpawns.WEATHERED }
end)

-- Solar sites -----------------------------------------------------------------------------------

-- A site goes down once when its chunk loads, and its spot is forgotten, so loading the chunk
-- again places nothing. Its pump's pole mount holds 1 or 2 modules at site conditions. The site
-- has one spot, a metal rack facing south on the square at `args`; the rack is removed when the
-- test ends.
handler("sitePlacedOnce", function(_, args, defer)
    local expect, _, failures = newCheck()
    local square = squareAt(args)
    if not square then
        return nil, "the site's square loaded on the server"
    end
    local SolarSites = RenewableEnergy.SolarSites
    local x, y, z = args.x, args.y, args.z
    local chunkX, chunkY = math.floor(x / 8), math.floor(y / 8)
    SolarSites.addSite({ kind = "stockTank", name = "test", panels = { { x, y, z, "rackMetal", "S" } } })
    local waiting = SolarSites.spotAt(x, y, z) ~= nil
    SolarSites.placeChunk(chunkX, chunkY)
    local leftOver = SolarSites.spotAt(x, y, z) ~= nil
    local objects = square:getObjects():size()
    SolarSites.placeChunk(chunkX, chunkY)
    local addedAgain = square:getObjects():size() - objects
    local rack = objectWithSprite(square, Sprites.rack.metal.S)
    if not rack then
        return nil, "the site's rack on its spot"
    end
    defer(function() removeObject(rack) end)
    expect(waiting, "the site kept no spot to place")
    expect(not leftOver, "the site's spot was not forgotten once placed")
    expect(addedAgain == 0, "loading the chunk again added " .. addedAgain .. " objects to the spot")
    expect(rack:getProperties():get("CustomItem") == "RenewableEnergy.SolarRackMetal",
        "the rack does not give back RenewableEnergy.SolarRackMetal")
    local modules = rack:getModData()[RenewableEnergy.PowerBank.MODULES] or {}
    expect(#modules >= 1 and #modules <= 2, #modules .. " modules on the pump's mount, expected 1 or 2")
    for _, module in ipairs(modules) do
        expect(module.type == MODULE and isSiteCondition(module.condition),
            "the pump's mount holds " .. tostring(module.type) .. " at " .. tostring(module.condition))
    end
    return { failures = failures }
end)

-- Every site's spots make sense on the map: banks and crates in a room (banks only work indoors),
-- panels outdoors, wall panels on a building's wall, garden lights at a building, arrow boards
-- outdoors; and each site has the spots its kind uses.
handler("sitesPlacedSensibly", function()
    local expect, _, failures = newCheck()
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
    return { failures = failures }
end)

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

local function houseNearCharacter(character)
    return houseNear(math.floor(character:getX()), math.floor(character:getY()), 60)
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

-- The house near the character is rolled for garden lights twice, after its first roll, which its
-- chunk loading made, is forgotten: the first roll is certain. Answers how many lights each roll
-- gave, whether the roll was kept, and every new light's square, whether it stands outdoors on the
-- ground and its charge; the roll is put back and the lights removed when the test ends.
handler("gardenLightsOnce", function(player, _, defer)
    local GardenLights = RenewableEnergy.GardenLights
    local def = houseNearCharacter(player)
    if not def then
        return nil, "a house near the character on the server"
    end
    local store, key = ModData.getOrCreate(GardenLights.MOD_DATA), GardenLights.buildingKey(def)
    local roll = store[key]
    defer(function() store[key] = roll end)
    local before = lightsAround(def)
    store[key] = nil
    local first = GardenLights.roll(def, true)
    local rolled = GardenLights.isRolled(def)
    local second = GardenLights.roll(def, true)
    local lights = {}
    for squareKey, light in pairs(lightsAround(def)) do
        if not before[squareKey] then
            defer(function() removeObject(light) end)
            local square = light:getSquare()
            table.insert(lights, {
                x = square:getX(), y = square:getY(), z = square:getZ(),
                outdoors = square:isOutside() and square:getRoom() == nil and square:getZ() == 0,
                charge = RenewableEnergy.SolarGardenLight.getCharge(light),
            })
        end
    end
    return { first = first, rolled = rolled, second = second, lights = lights, count = GardenLights.COUNT,
        wh = RenewableEnergy.Specs.gardenLight.wh }
end)

-- At the square at `args`: whether it is loaded, the house nearest it within `args.radius`, whether
-- that house was rolled for garden lights, and the neighbourhood.
handler("gardenLightsAt", function(_, args)
    local GardenLights = RenewableEnergy.GardenLights
    local loaded = getSquare(args.x, args.y, 0) ~= nil
    local def = loaded and houseNear(args.x, args.y, args.radius)
    return {
        loaded = loaded,
        house = def and GardenLights.buildingKey(def) or nil,
        rolled = def and GardenLights.isRolled(def) or false,
        neighbourhood = GardenLights.neighbourhood(args.x, args.y),
    }
end)

-- The chance the house near the character gets lights, at the save's options.
handler("gardenLightsChance", function(player)
    local def = houseNearCharacter(player)
    if not def then
        return nil, "a house near the character on the server"
    end
    return { chance = RenewableEnergy.GardenLights.chanceFor(def) }
end)

-- Vehicles ----------------------------------------------------------------------------------------

local vehicleById = PZHarness.Fixtures.vehicleById

-- The conditions the panels of trailers spawned with `args.recordStock` got as they were stocked,
-- by vehicle id: { [partId] = condition }.
local stockedPanels = {}

-- T.placeVehicle's spawn: an arrow board through ArrowBoard.spawn when `args.stocked`, as the world
-- spawns one; with `args.recordStock` the harness's plain addVehicleDebug, recording its panels'
-- stock conditions (arrowBoardStock); else the harness's spawn; whole when `args.repair`.
PZHarness.serverSettings = PZHarness.serverSettings or {}
function PZHarness.serverSettings.spawnVehicle(script, square, facing, args)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    local vehicle
    if args and args.stocked then
        vehicle = ArrowBoard.spawn(square, facing)
    elseif args and args.recordStock then
        -- Stocking rolls a condition for each panel in turn, left first.
        local WorldSpawns, rolled = RenewableEnergy.WorldSpawns, {}
        local weathered, cracked = WorldSpawns.weatheredCondition, WorldSpawns.crackedCondition
        local function recording(roll)
            return function()
                local condition = roll()
                table.insert(rolled, condition)
                return condition
            end
        end
        WorldSpawns.weatheredCondition, WorldSpawns.crackedCondition = recording(weathered), recording(cracked)
        vehicle = addVehicleDebug(script, IsoDirections[facing], nil, square)
        WorldSpawns.weatheredCondition, WorldSpawns.crackedCondition = weathered, cracked
        stockedPanels[vehicle:getId()] = { [ArrowBoard.PANELS[1]] = rolled[1], [ArrowBoard.PANELS[2]] = rolled[2] }
    elseif args and args.repair then
        vehicle = addVehicleDebug(script, IsoDirections[facing], nil, square)
    end
    if vehicle and args.repair then
        vehicle:repair()
    end
    return vehicle
end

-- What each panel part shows: the ids of its part models in the vehicle's model list. Read by
-- reflection (debug only), since nothing exposes the list to Lua.
local function fieldValue(object, name)
    for i = 0, getNumClassFields(object) - 1 do
        local field = getClassField(object, i)
        if tostring(field):match("%." .. name .. "$") then
            return getClassFieldVal(object, field)
        end
    end
    return nil
end

--- The models a part of `vehicle` shows, sorted and joined with commas.
function World.shownModels(vehicle, partId)
    local part, shown = vehicle:getPartById(partId), {}
    local models = fieldValue(vehicle, "models")
    for i = 0, models:size() - 1 do
        local info = models:get(i)
        if fieldValue(info, "part") == part then
            table.insert(shown, fieldValue(info, "scriptModel"):getId())
        end
    end
    table.sort(shown)
    return table.concat(shown, ",")
end

-- A part's installed item and its condition, or none.
local function partState(vehicle, partId)
    local part = vehicle:getPartById(partId)
    local item = part and part:getInventoryItem()
    return { installed = item ~= nil, type = item and item:getFullType(), condition = item and part:getCondition() }
end

--- What the tests read of a vehicle on either side: each panel's module, condition and shown
--- models, the frame's parts, what the battery box holds, the lid, the towing car's id and where
--- the vehicle is.
function World.vehicleState(vehicle)
    local ArrowBoard = RenewableEnergy.ArrowBoard
    local state = {
        id = vehicle:getId(), x = vehicle:getX(), y = vehicle:getY(), atRest = vehicle:isAtRest(),
        up = vehicle:getUpVectorDot(), panels = {}, frame = {}, blood = {},
        towedBy = vehicle:getVehicleTowedBy() and vehicle:getVehicleTowedBy():getId() or nil,
        colorSat = vehicle:getColorSaturation(), colorVal = vehicle:getColorValue(),
    }
    if not ArrowBoard.isTrailer(vehicle) then
        return state
    end
    for _, id in ipairs(ArrowBoard.PANELS) do
        state.panels[id] = partState(vehicle, id)
        state.panels[id].shown = World.shownModels(vehicle, id)
    end
    for _, frame in ipairs(ArrowBoard.FRAME) do
        state.frame[frame.id] = partState(vehicle, frame.id)
        state.frame[frame.id].category = vehicle:getPartById(frame.id):getCategory()
    end
    for _, side in ipairs({ "Front", "Rear", "Left", "Right" }) do
        state.blood[side] = vehicle:getBloodIntensity(side)
    end
    local box = vehicle:getPartById(ArrowBoard.BATTERY_BOX)
    local container = box and box:getItemContainer()
    if container then
        state.box = { items = {} }
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            table.insert(state.box.items, { type = item:getFullType(), id = item:getID(), condition = item:getCondition(),
                charge = RenewableEnergy.Battery.isBattery(item) and RenewableEnergy.Battery.getCharge(item) or nil })
        end
    end
    local lid = vehicle:getPartById("TrunkDoor")
    local door = lid and lid:getDoor()
    if door then
        state.lid = { open = door:isOpen(), locked = door:isLocked() }
    end
    return state
end

-- The vehicle of `args` ({ id, x, y, z }: RenewableEnergyTest.vehicleArgs; single player finds it
-- by the squares around x, y, z), or nil and what is missing.
local function vehicleArg(args)
    local vehicle = vehicleById(args.id, args)
    if not vehicle or vehicle:isRemovedFromWorld() then
        return nil, "vehicle " .. tostring(args.id) .. " on the server"
    end
    return vehicle
end

handler("vehicleState", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    return { state = World.vehicleState(vehicle) }
end)

-- The stock conditions of the panels of a trailer spawned with `args.recordStock`, and its state.
handler("arrowBoardStock", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    local stock = stockedPanels[vehicle:getId()]
    if not stock then
        return nil, "the stock conditions of vehicle " .. tostring(args.id)
    end
    return { stock = stock, state = World.vehicleState(vehicle) }
end)

-- Puts a module of spec.type at spec.condition on the panel, or takes it off for a spec without a
-- type, as the mechanics window's install does, and shows it.
local function putPanel(vehicle, partId, spec)
    local part = vehicle:getPartById(partId)
    local item = spec.type and instanceItem(spec.type)
    part:setInventoryItem(item)
    if item then
        part:setCondition(spec.condition)
    end
    vehicle:transmitPartItem(part)
    vehicle:transmitPartCondition(part)
    RenewableEnergy.ArrowBoard.showPanel(part)
end

-- Sets up the trailer `args.id` on the authority, in this order: whole if `args.repair`; each
-- panel of `args.panels` ({ [partId] = { type, condition } }, an empty table taking the module
-- off); each frame part of `args.frame` ({ [partId] = condition }); the battery box emptied and
-- filled with `args.box` ({ { type, charge } }) if given; the blood of `args.blood` ({ [side] =
-- intensity }); the lid open or shut if `args.lidOpen` is set. Answers its state.
handler("setTrailer", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    local ArrowBoard = RenewableEnergy.ArrowBoard
    if args.repair then
        vehicle:repair()
    end
    for partId, spec in pairs(args.panels or {}) do
        putPanel(vehicle, partId, spec)
    end
    for partId, condition in pairs(args.frame or {}) do
        local part = vehicle:getPartById(partId)
        part:setCondition(condition)
        vehicle:transmitPartCondition(part)
    end
    if args.box then
        local container = vehicle:getPartById(ArrowBoard.BATTERY_BOX):getItemContainer()
        local items = container:getItems()
        for i = items:size() - 1, 0, -1 do
            local item = items:get(i)
            container:Remove(item)
            sendRemoveItemFromContainer(container, item)
        end
        for _, spec in ipairs(args.box) do
            local item = container:AddItem(spec.type)
            if spec.charge then
                RenewableEnergy.Battery.setCharge(item, spec.charge)
            end
            sendAddItemToContainer(container, item)
        end
    end
    for side, intensity in pairs(args.blood or {}) do
        vehicle:setBloodIntensity(side, intensity)
    end
    if args.lidOpen ~= nil then
        local lid = vehicle:getPartById("TrunkDoor")
        lid:getDoor():setOpen(args.lidOpen)
        vehicle:transmitPartDoor(lid)
    end
    return { state = World.vehicleState(vehicle) }
end)

-- `args.hours` of the trailer's panels charging its box at the sun of the moment. Answers the
-- watt-hours stored, the panels' rating, what a flat watt of panel makes in an hour now, and the
-- trailer's state.
handler("arrowBoardCharge", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    local ArrowBoard = RenewableEnergy.ArrowBoard
    local watts = ArrowBoard.panelWatts(vehicle)
    local stored = ArrowBoard.charge(vehicle, args.hours)
    return { stored = stored, watts = watts, flatWh = RenewableEnergy.Sun.panelWatts(1, "flat"),
        state = World.vehicleState(vehicle) }
end)

-- A crack on the panel `args.part`. Answers the trailer's state.
handler("arrowBoardCrack", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    RenewableEnergy.ArrowBoard.crackPanel(vehicle, vehicle:getPartById(args.part))
    return { state = World.vehicleState(vehicle) }
end)

-- `args.hours` of thunderstorm over the trailer at the save's storm options. Answers how many
-- panels cracked and the trailer's state.
handler("arrowBoardStorm", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    local cracked = RenewableEnergy.ArrowBoard.stormCrack(vehicle, args.hours)
    return { cracked = cracked, state = World.vehicleState(vehicle) }
end)

-- The trailer loads as one from a save made before its panels were parts: empty panels and no
-- record of stocking them, then the panels' init. Then its panels are taken off and it loads
-- again. Answers its state after each load.
handler("arrowBoardOldPanels", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    local ArrowBoard = RenewableEnergy.ArrowBoard
    local function load()
        for _, id in ipairs(ArrowBoard.PANELS) do
            ArrowBoard.initPanel(vehicle, vehicle:getPartById(id))
        end
    end
    local function empty()
        for _, id in ipairs(ArrowBoard.PANELS) do
            putPanel(vehicle, id, {})
        end
    end
    empty()
    vehicle:getModData().RenewableEnergy_panelsStocked = nil
    load()
    local first = World.vehicleState(vehicle)
    empty()
    load()
    return { first = first, second = World.vehicleState(vehicle) }
end)

-- The trailer loads as one from a save made before its frame was parts: frame parts empty and the
-- random colour of `args.hsv`, then the frame's init. Answers its state and its script's forced
-- colour.
handler("arrowBoardOldFrame", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    vehicle:setColorHSV(args.hsv[1], args.hsv[2], args.hsv[3])
    for _, frame in ipairs(RenewableEnergy.ArrowBoard.FRAME) do
        local part = vehicle:getPartById(frame.id)
        part:setInventoryItem(nil)
        RenewableEnergy.ArrowBoard.initFrame(vehicle, part)
    end
    local script = vehicle:getScript()
    return { state = World.vehicleState(vehicle), forcedSat = script:getForcedSat(), forcedVal = script:getForcedVal() }
end)

-- The game's own crash damage on the vehicle: `args.amount`, to the front if `args.front`.
-- Answers its state.
handler("vehicleCrash", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    vehicle:crash(args.amount, args.front)
    return { state = World.vehicleState(vehicle) }
end)

-- The item types each panel takes, then the left panel emptied and the trailer repaired. Answers
-- the types and the trailer's state.
handler("arrowBoardRepairAll", function(_, args)
    local vehicle, missing = vehicleArg(args)
    if not vehicle then
        return nil, missing
    end
    local types = {}
    for _, id in ipairs(RenewableEnergy.ArrowBoard.PANELS) do
        local list = vehicle:getPartById(id):getItemType()
        types[id] = {}
        for i = 0, list:size() - 1 do
            table.insert(types[id], list:get(i))
        end
    end
    putPanel(vehicle, RenewableEnergy.ArrowBoard.PANELS[1], {})
    vehicle:repair()
    return { types = types, state = World.vehicleState(vehicle) }
end)

-- Turns the car `args.car` and the trailer `args.trailer` (each RenewableEnergyTest.vehicleArgs) square to
-- `args.facing` and puts the trailer's coupler on the car's tow bar
-- (PZHarness.Fixtures.lineUpTrailer), on the authority, which sends the clients their new places.
handler("lineUpTrailer", function(_, args)
    local car, trailer = vehicleArg(args.car), vehicleArg(args.trailer)
    if not (car and trailer) then
        return nil, "the car and the trailer on the server"
    end
    PZHarness.Fixtures.lineUpTrailer(car, trailer, args.facing)
    return {}
end)

-- What the game gives the character for an Electricity award of `args.xp`, through the call
-- CraftRecipe.addXP makes, and its Electricity XP after.
handler("electricityAward", function(player, args)
    local xp = player:getXp()
    local before = xp:getXP(Perks.Electricity)
    xp:AddXP(Perks.Electricity, args.xp, true, true, false, false)
    return { gained = xp:getXP(Perks.Electricity) - before, xp = xp:getXP(Perks.Electricity) }
end)

-- The character's inventory ---------------------------------------------------------------------

-- Empties the fluid container of the character's item `args.id`, fills it with `args.liters` of
-- `args.fluid` (a fluid name, none when nil), and sends the item to the character's client.
handler("refillFluid", function(player, args)
    local item = player:getInventory():getItemById(args.id)
    local fluids = item and item:getFluidContainer()
    if not fluids then
        return nil, "the character's fluid container " .. tostring(args.id) .. " on the server"
    end
    fluids:Empty()
    if args.fluid then
        fluids:addFluid(args.fluid, args.liters)
    end
    item:syncItemFields()
    return {}
end)

-- Takes the character's items of `args.ids`, or all of type `args.type`, out of the inventory, as
-- the server takes an item, which the client then loses too.
handler("takeItems", function(player, args)
    local inventory = player:getInventory()
    local items = {}
    for _, id in ipairs(args.ids or {}) do
        table.insert(items, inventory:getItemById(id))
    end
    if args.type then
        local all = inventory:getAllTypeRecurse(args.type)
        for i = 0, all:size() - 1 do
            table.insert(items, all:get(i))
        end
    end
    for _, item in ipairs(items) do
        local container = item:getContainer()
        container:Remove(item)
        sendRemoveItemFromContainer(container, item)
    end
    return { taken = #items }
end)

-- What the character carries, bags included: for each type of `args.types` its items { id,
-- condition, uses (the fraction left), modData }, and in `fluids` the litres of each fluid of
-- `args.fluids` (Fluid field names) in all the character's fluid containers.
handler("carried", function(player, args)
    local inventory = player:getInventory()
    local items = {}
    for _, fullType in ipairs(args.types or {}) do
        items[fullType] = {}
        local all = inventory:getAllTypeRecurse(fullType)
        for i = 0, all:size() - 1 do
            local item = all:get(i)
            table.insert(items[fullType], { id = item:getID(), condition = item:getCondition(),
                uses = item:getCurrentUsesFloat(), modData = item:getModData() })
        end
    end
    local fluids = {}
    local all = inventory:getItems()
    for _, name in ipairs(args.fluids or {}) do
        fluids[name] = 0
        for i = 0, all:size() - 1 do
            local container = all:get(i):getFluidContainer()
            if container then
                fluids[name] = fluids[name] + container:getSpecificFluidAmount(Fluid[name])
            end
        end
    end
    return { items = items, fluids = fluids, total = inventory:getItems():size() }
end)

-- Tiles ------------------------------------------------------------------------------------------

local function overlaysOf(object)
    local names = {}
    local attached = object:getAttachedAnimSprite()
    for i = 0, (attached and attached:size() or 0) - 1 do
        table.insert(names, attached:get(i):getName())
    end
    return names
end

-- The panel drawn as `args.sprite` on the square at `args`, changed by `args.change`, if given: its
-- modules replaced by `change.modules` and, with `change.snow`, snow laid on it first; then its
-- cracks shown as the mod shows them. Answers its overlays in drawing order.
handler("panelCracks", function(_, args)
    local PowerBank = RenewableEnergy.PowerBank
    local panel = objectWithSprite(squareAt(args), args.sprite)
    if not panel then
        return nil, "the panel " .. tostring(args.sprite) .. " on the server"
    end
    local change = args.change
    if change then
        if change.snow then
            panel:addAttachedAnimSpriteByName(Sprites.snow.flat)
        end
        panel:getModData()[PowerBank.MODULES] = change.modules
        if isServer() then
            panel:transmitModData()
        end
    end
    PowerBank.showCracks(panel)
    return { overlays = overlaysOf(panel) }
end)

-- The modData key `args.key` of the object drawn as `args.sprite` on the square at `args`.
handler("objectModData", function(_, args)
    local object = objectWithSprite(squareAt(args), args.sprite)
    if not object then
        return nil, "the placed " .. tostring(args.sprite) .. " on the server"
    end
    return { value = object:getModData()[args.key] }
end)

-- Learning -------------------------------------------------------------------------------------

-- The recipes the character has learned whose names start with `args.prefix`, as a set.
handler("knownRecipes", function(player, args)
    local known, list = {}, player:getKnownRecipes()
    for i = 0, list:size() - 1 do
        local name = list:get(i)
        if string.sub(name, 1, #args.prefix) == args.prefix then
            known[name] = true
        end
    end
    return { known = known }
end)

-- Forgets that the character read the literature `args.title`, whose cooldown would make reading
-- it again teach nothing.
handler("forgetLiterature", function(player, args)
    player:getReadLiterature():remove(args.title)
    return {}
end)

-- Loot -------------------------------------------------------------------------------------------

local function distributions(expect)
    local D = RenewableEnergy.Distributions
    return expect(D ~= nil, "RenewableEnergy.Distributions did not load") and D
end

-- Calls fn(items, path) for every items list of every room, bag, procedural and vehicle table.
local function forEachItemsList(fn)
    local seen = {}
    local function walk(t, path, depth)
        if seen[t] or depth > 6 then
            return
        end
        seen[t] = true
        if type(t.items) == "table" then
            fn(t.items, path)
        end
        for key, value in pairs(t) do
            if type(value) == "table" and key ~= "items" and key ~= "procList" then
                walk(value, path .. "." .. tostring(key), depth + 1)
            end
        end
    end
    walk(SuburbsDistributions, "SuburbsDistributions", 0)
    walk(ProceduralDistributions.list, "ProceduralDistributions", 0)
    walk(VehicleDistributions, "VehicleDistributions", 0)
end

-- The first room and container type whose procList names each ProceduralDistributions list.
local function procListUsers()
    local users = {}
    for roomName, room in pairs(SuburbsDistributions) do
        if type(room) == "table" and room.rolls == nil then
            for containerType, containerTable in pairs(room) do
                if type(containerTable) == "table" and type(containerTable.procList) == "table" then
                    for _, choice in ipairs(containerTable.procList) do
                        if choice.name and not users[choice.name] then
                            users[choice.name] = { room = roomName, container = containerType }
                        end
                    end
                end
            end
        end
    end
    return users
end

-- The VehicleDistributions tables some vehicle's Normal or Specific distribution fills from.
local function vehicleTablesInUse()
    local used = {}
    local function addSet(set)
        for _, containerTable in pairs(set or {}) do
            if type(containerTable) == "table" then
                used[containerTable] = true
            end
        end
    end
    for _, vehicle in pairs(VehicleDistributions[1]) do
        addSet(vehicle.Normal)
        for _, specific in ipairs(vehicle.Specific or {}) do
            addSet(specific)
        end
    end
    return used
end

-- The spawn tables of every stash house, vanilla's and the mod's.
local function stashSpawnTables()
    local tables = { RenewableEnergyStashCache = true }
    for _, description in ipairs(StashDescriptions or {}) do
        if description.spawnTable then
            tables[description.spawnTable] = true
        end
    end
    return tables
end

local function checkSubList(expect, where, name, stashTables)
    local room, container = string.match(name, "^([^.]+)%.(.+)$")
    local containerTable = room and SuburbsDistributions[room] and SuburbsDistributions[room][container]
    if not expect(containerTable ~= nil and not containerTable.procedural, where .. ": not a plain container table") then
        return
    end
    -- Corpses roll SuburbsDistributions.all.Outfit_<outfit> (ItemPickerJava.fillContainer).
    expect(stashTables[room] or (room == "all" and string.find(container, "^Outfit_") ~= nil),
        where .. ": neither a stash house nor a corpse rolls it")
    expect(ItemPickerJava.getItemContainer(room, container, nil, false) ~= nil, where .. ": the game has no " .. name)
end

-- Every entry names an item that exists, since the game drops an unknown item silently, and sits
-- once in a list the game rolls: a room's procList, a vehicle's container, a stash house's spawn
-- table or a corpse's outfit list.
handler("lootListsInUse", function()
    local expect, _, failures = newCheck()
    local D = distributions(expect)
    if not D then
        return { failures = failures }
    end
    local procUsers = procListUsers()
    local vehicleTables = vehicleTablesInUse()
    local stashTables = stashSpawnTables()
    for _, spec in ipairs(D.items) do
        expect(getScriptManager():FindItem(spec.fullType) ~= nil, spec.fullType .. " is no item")
        for _, entry in ipairs(spec.entries) do
            local reference = entry[2]
            local where = spec.fullType .. " in " .. reference
            local items = D.resolveItemList(reference)
            if expect(items ~= nil, where .. ": no such list") then
                expect(countPairs(items, spec.fullType) == 1, where .. ": not listed exactly once")
            end
            local kind, name = string.match(reference, "^(%a+):(.+)$")
            if kind == "proc" then
                local listName = string.gsub(name, "%.junk$", "")
                local user = procUsers[listName]
                if expect(user ~= nil, where .. ": no room picks " .. listName) then
                    expect(ItemPickerJava.getItemContainer(user.room, user.container, listName, false) ~= nil,
                        where .. ": the game has no " .. user.room .. "." .. user.container .. " -> " .. listName)
                end
            elseif kind == "veh" then
                expect(VehicleDistributions[name] ~= nil and vehicleTables[VehicleDistributions[name]] == true,
                    where .. ": no vehicle fills from it")
            elseif kind == "sub" then
                checkSubList(expect, where, name, stashTables)
            else
                expect(false, where .. ": unknown kind of list")
            end
        end
    end
    return { failures = failures }
end)

-- Every list actually hands out every item it lists, through the game's own rolls. The loot
-- rarity options are at their maximum, so a few rolls are enough even for the rarest entries.
handler("lootItemsSpawn", function()
    local expect, _, failures = newCheck()
    if not distributions(expect) then
        return { failures = failures }
    end
    local Loot = RenewableEnergy.Loot
    local targets = Loot.targets()
    Loot.withMeasureOptions(function()
        local function build()
            return Loot.tablesFor(targets, false)
        end
        Loot.withLoot(100, build, function(parsed)
            local container = Loot.newContainer(nil)
            for i, target in ipairs(targets) do
                local list = parsed["t" .. i]
                if expect(list ~= nil, target.reference .. ": the game didn't parse it") then
                    local missing, remaining = {}, 0
                    for fullType in pairs(target.items) do
                        missing[fullType] = true
                        remaining = remaining + 1
                    end
                    for _ = 1, 200 do
                        for fullType in pairs(Loot.rollOnce(list, container)) do
                            if missing[fullType] then
                                missing[fullType] = nil
                                remaining = remaining - 1
                            end
                        end
                        if remaining == 0 then
                            break
                        end
                    end
                    for fullType in pairs(missing) do
                        expect(false, fullType .. " never spawned from " .. target.reference)
                    end
                end
            end
        end)
    end)
    return { failures = failures }
end)

-- Sum of an item's weights in vanilla lists: the mod's own kit and stock lists don't count,
-- since they are rolled only in a few store rooms.
local function vanillaWeight(D, fullType)
    local total = 0
    for _, spec in ipairs(D.items) do
        if spec.fullType == fullType then
            for _, entry in ipairs(spec.entries) do
                if not string.find(entry[2], "RenewableEnergy") then
                    total = total + entry[1]
                end
            end
        end
    end
    return total
end

-- Each ladder of `args.ladders` turns up less often at each step.
handler("lootLaterStagesRarer", function(_, args)
    local expect, _, failures = newCheck()
    local D = distributions(expect)
    if not D then
        return { failures = failures }
    end
    for _, ladder in ipairs(args.ladders) do
        for i = 2, #ladder do
            local earlier, later = vanillaWeight(D, ladder[i - 1]), vanillaWeight(D, ladder[i])
            expect(earlier > later, ladder[i] .. " (" .. later .. ") is not rarer than " .. ladder[i - 1] .. " (" .. earlier .. ")")
        end
    end
    return { failures = failures }
end)

-- Whether `list` has every vanilla item of `vanilla`; the mod's own entries differ between them.
local function listsContainAll(list, vanilla)
    for i = 1, #vanilla.items - 1, 2 do
        local fullType = vanilla.items[i]
        if not string.find(fullType, "^RenewableEnergy%.") and countPairs(list.items, fullType) == 0 then
            return false
        end
    end
    return true
end

-- The utility vans keep every vanilla builder's item and get the mod's own truck bed; trailers
-- can roll a camper's.
handler("lootVehicleTables", function()
    local expect, _, failures = newCheck()
    local byVehicle = VehicleDistributions[1]
    local vanillaBed = VehicleDistributions.ConstructionWorkerTruckBed
    for vehicle, listName in pairs({ VanKnoxCom = "RenewableEnergyTelecomTruckBed", VanDeerValley = "RenewableEnergyUtilityTruckBed" }) do
        local list = VehicleDistributions[listName]
        local normal = byVehicle[vehicle] and byVehicle[vehicle].Normal
        if expect(list ~= nil and normal ~= nil, vehicle .. " or " .. listName .. " is missing") then
            expect(normal.TruckBed == list, vehicle .. " does not fill its truck bed from " .. listName)
            expect(normal.GloveBox == VehicleDistributions.ConstructionWorker.GloveBox, vehicle .. " lost its glove box loot")
            expect(listsContainAll(list, vanillaBed), listName .. " lacks vanilla builder's items")
        end
    end
    local trailerTrunk = VehicleDistributions.RenewableEnergyCamperTrailerTrunk
    for _, trailer in ipairs({ "Trailer", "TrailerCover" }) do
        local found = false
        for _, specific in ipairs(byVehicle[trailer].Specific) do
            found = found or specific.TrailerTrunk == trailerTrunk
        end
        expect(found, trailer .. " never rolls the camper trailer loot")
    end
    expect(trailerTrunk ~= nil and listsContainAll(trailerTrunk, VehicleDistributions.CamperTruckBed),
        "the camper trailer lacks the camper's vanilla items")
    return { failures = failures }
end)

-- Each loot rarity option scales the weights of its items in every list, the mod's own lists
-- included, for each row of `args.rows`. At 0 it takes its items out of every list rather than
-- leaving them at weight 0, because ItemPickerJava adds the zombie density bonus to every weight,
-- so they would still spawn in towns; the other options' items stay. Applying the options again,
-- as a second load does, replaces the entries instead of adding more.
handler("lootRarityOptions", function(_, args)
    local expect, expectNear, failures = newCheck()
    local D = distributions(expect)
    if not D then
        return { failures = failures }
    end
    local options = SandboxVars.RenewableEnergy
    local saved = {}
    for option in pairs(args.rows[1]) do
        saved[option] = options[option]
    end
    for _, row in ipairs(args.rows) do
        local label = string.format("at %s/%s/%s", row.LRMSolarPanels, row.LRMBatteries, row.LRMMisc)
        for option, value in pairs(row) do
            options[option] = value
        end
        D.apply()
        D.apply()
        local removed = {}
        for _, spec in ipairs(D.items) do
            local multiplier = row[spec.option]
            if multiplier == 0 then
                removed[spec.fullType] = true
            else
                for _, entry in ipairs(spec.entries) do
                    local where = label .. ": " .. spec.fullType .. " in " .. entry[2]
                    local items = D.resolveItemList(entry[2])
                    local count, weight = 0, nil
                    if items then
                        count, weight = countPairs(items, spec.fullType)
                    end
                    if expect(count == 1, where .. " " .. count .. " times") then
                        expectNear(where .. " weight", weight, entry[1] * multiplier)
                    end
                end
            end
        end
        forEachItemsList(function(items, path)
            for i = 1, #items - 1, 2 do
                if removed[items[i]] then
                    expect(false, label .. ": " .. items[i] .. " is still in " .. path)
                end
            end
        end)
    end
    for option, value in pairs(saved) do
        options[option] = value
    end
    D.apply()
    return { failures = failures }
end)

-- Batteries that rooms, vehicles and corpses hand out hold a part charge, once: a refill of the
-- container by loot respawn leaves a battery already there alone. The container is the character's
-- inventory, which the runner empties before each test: a found battery's charge is sent to the
-- clients that see it, and a server can send no item of a container outside the world.
handler("lootFoundBatteries", function(player)
    local expect, expectNear, failures = newCheck()
    local D = distributions(expect)
    if not D then
        return { failures = failures }
    end
    local Battery = RenewableEnergy.Battery
    local range = RenewableEnergy.Specs.foundCharge
    local container = player:getInventory()
    local bag = container:AddItem("Base.Bag_DuffelBag")
    local loose = container:AddItem("RenewableEnergy.DeepCycleBattery")
    local bagged = bag and bag:getInventory():AddItem("RenewableEnergy.L16Battery")
    local wire = container:AddItem("Base.ElectricWire")
    if not expect(loose ~= nil and bagged ~= nil and wire ~= nil, "could not build the container") then
        return { failures = failures }
    end
    for _, item in ipairs({ bag, loose, wire }) do
        sendAddItemToContainer(container, item)
    end
    D.chargeFoundBatteries(container)
    for _, battery in ipairs({ loose, bagged }) do
        local charge = Battery.getCharge(battery)
        expect(charge >= range.min and charge <= range.max,
            battery:getFullType() .. " holds " .. charge .. ", expected " .. range.min .. " to " .. range.max)
    end
    Battery.setCharge(loose, 1)
    D.chargeFoundBatteries(container)
    expectNear("a stored battery's charge after a second fill", Battery.getCharge(loose), 1)
    container:removeAllItems()
    return { failures = failures }
end)

-- Up to `wanted` loaded squares near the character in rooms that have a loot distribution, one per
-- room type, and one square outside any room.
local function sampleSquares(character, wanted)
    local squares, roomNames = {}, {}
    local cell = getCell()
    local px, py = math.floor(character:getX()), math.floor(character:getY())
    for dx = -60, 60 do
        for dy = -60, 60 do
            local square = cell:getGridSquare(px + dx, py + dy, 0)
            local room = square and square:getRoom()
            local name = room and room:getName()
            if name and not roomNames[name] and #squares < wanted and SuburbsDistributions[name] then
                roomNames[name] = true
                table.insert(squares, square)
            end
        end
    end
    local outside = RenewableEnergy.Loot.squareOutsideRooms(character)
    if outside then
        table.insert(squares, outside)
    end
    return squares
end

-- Loot respawn refills an explored, looted container that isn't an IsoThumpable by calling
-- ItemPickerJava.fillContainer(container, nil) (LootRespawn.respawnInContainer). A player's battery
-- bank is an IsoGenerator; if any room handed its container type a loot list, a bank someone took a
-- battery out of would refill with free batteries every respawn. The objects of `args.containers`
-- ({ { sprite, type } }) are built from the tiles, as placing them does, but never added to the
-- square.
handler("lootPlayerContainers", function(player, args)
    local expect, _, failures = newCheck()
    local squares = sampleSquares(player, 4)
    if not expect(#squares >= 2, "no loaded room near the character") then
        return { failures = failures }
    end
    for _, square in ipairs(squares) do
        local room = square:getRoom()
        local where = room and room:getName() or "outside"
        for _, spec in ipairs(args.containers) do
            local sprite = Sprites[spec.sprite]
            local object = IsoObject.new(square, sprite, spec.type)
            object:createContainersFromSpriteProperties()
            local container = object:getContainer()
            if expect(container ~= nil and container:getType() == spec.type, sprite .. " gives no " .. spec.type .. " container") then
                container:setExplored(true)
                container:setHasBeenLooted(true)
                for _ = 1, 20 do
                    ItemPickerJava.fillContainer(container, nil)
                end
                local count = container:getItems():size()
                expect(count == 0, "respawn put " .. count .. " items into a " .. spec.type .. " in " .. where)
                container:removeAllItems()
            end
        end
    end
    return { failures = failures }
end)

return World
