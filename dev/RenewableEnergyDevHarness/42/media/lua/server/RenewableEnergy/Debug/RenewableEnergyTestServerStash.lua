-- The authority's half of the stash house tests: the mod's stashes, StashSystem and the corpse
-- loot that drops their maps exist only where the authority runs them. Only registers handlers,
-- so a --stay rerun loads it again (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how these
-- handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
require "RenewableEnergy/Sprites"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"
-- The game's Java class zombie.core.stash.Stash, which the mod's module name would hide.
local EngineStash = Stash
local Stash = require "RenewableEnergy/Stash"

local handler, check, saveOptions = PZHarness.serverHandler, Helpers.check, Helpers.saveOptions
local deferOnce = Helpers.deferOnce
local countPairs = PZHarness.Fixtures.countPairs
local Sprites = RenewableEnergy.Sprites

-- StashSystem gives up without an error when the stash building isn't a building, prepares only a
-- building whose bounds strictly contain the building square (doBuildingStash), and stocks the
-- crate only if its square is in a room of that building, so a wrong coordinate is an empty house.
-- The crate is the mod's, and the house's spawn table has loot for its container type.
check("stashHousesResolve", function(expect)
    local metaGrid = getWorld():getMetaGrid()
    for stashMap in pairs(Stash.descriptions) do
        local x, y = stashMap.buildingX, stashMap.buildingY
        local building = Stash.buildingOf(stashMap)
        local spawnTable = SuburbsDistributions[stashMap.spawnTable]
        if expect(building ~= nil, stashMap.name .. ": no building at its building coordinates") then
            expect(building:getX() < x and x < building:getX2() and building:getY() < y and y < building:getY2(),
                stashMap.name .. ": the building square is on the edge of the building's bounds")
            for _, crate in ipairs(stashMap.containers) do
                local crateRoom = metaGrid:getRoomAt(crate.contX, crate.contY, crate.contZ)
                expect(crateRoom ~= nil and crateRoom:getBuilding() == building,
                    stashMap.name .. ": the crate square is not in a room of the building")
                expect(crate.containerSprite == Sprites.crate, stashMap.name .. ": the crate is not the mod's solar crate")
                expect(spawnTable ~= nil and spawnTable[crate.containerType] ~= nil,
                    stashMap.name .. ": its spawn table " .. tostring(stashMap.spawnTable) .. " has no loot for "
                    .. tostring(crate.containerType))
            end
        end
    end
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
handler("stashRegister", function(_, _, defer)
    local options = SandboxVars.RenewableEnergy
    local restoreOptions = saveOptions(defer, { "StashMode" }, function()
        unregister()
        Stash.register()
    end)
    local results = {}
    for _, mode in pairs(Stash.MODE) do
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
    restoreOptions()
    return { results = results, houses = Helpers.count(Stash.descriptions) }
end)

-- The engine's own load and annotate path, which a found map takes, on a fresh copy of each stash
-- so the world's stash state stays as it was.
check("stashMapsAnnotate", function(expect)
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

-- Marks the stash `name` read or not in StashSystem's already-read map.
local function setRead(name, read)
    local alreadyRead = StashSystem.getAlreadyReadMap()
    alreadyRead:remove(name)
    if read then
        alreadyRead:add(name)
    end
end

-- Puts each house through Stash.relistUnfound in every case of `args.cases` ({ visited, read }),
-- then back as it was. Answers { name, case, relisted } for each, in order.
handler("stashRelist", function(_, args, defer)
    local possible, alreadyRead = StashSystem.getPossibleStashes(), StashSystem.getAlreadyReadMap()
    local houses = {}
    for stashMap in pairs(Stash.descriptions) do
        local building = Stash.buildingOf(stashMap)
        if not building then
            return nil, "the building of " .. stashMap.name
        end
        table.insert(houses, { name = stashMap.name, building = building,
            visited = building:isHasBeenVisited(), read = alreadyRead:contains(stashMap.name) })
    end
    if #houses == 0 then
        return nil, "a stash house"
    end
    local savedPossible = {}
    for i = 0, possible:size() - 1 do
        table.insert(savedPossible, possible:get(i))
    end
    local restore = deferOnce(defer, function()
        for _, house in ipairs(houses) do
            house.building:setHasBeenVisited(house.visited)
            setRead(house.name, house.read)
        end
        -- Last, since marking a house visited drops it from the list.
        possible:clear()
        for _, stash in ipairs(savedPossible) do
            possible:add(stash)
        end
    end)
    local results = {}
    for _, house in ipairs(houses) do
        local name, building = house.name, house.building
        for i, case in ipairs(args.cases) do
            removePossibleStash(name)
            building:setHasBeenVisited(case.visited)
            setRead(name, case.read)
            Stash.relistUnfound()
            table.insert(results, { name = name, case = i, relisted = isPossibleStash(name) })
        end
    end
    restore()
    return { results = results }
end)

-- Stash.stockFromStart with the engine handed the houses, every roll at 0 so that each house with
-- a knownOnStart chance is stocked, and StashSystem's possible list, which isStashBuilding also
-- reads, emptied of them, so that what it reports afterwards is the stocking queue alone. Answers
-- by house whether it was queued for stocking, marked as read, and has a chance at all; then puts
-- everything back.
handler("stashKnownOnStart", function(_, _, defer)
    local all, alreadyRead = StashSystem.getAllStashes(), StashSystem.getAlreadyReadMap()
    local added, read = {}, {}
    local restore = deferOnce(defer, function()
        for _, engineStash in ipairs(added) do
            all:remove(engineStash)
        end
        -- stockFromStart unmarks a house it stocks, even one read before.
        for name, wasRead in pairs(read) do
            setRead(name, wasRead)
        end
        Stash.relistUnfound()
    end)
    for stashMap in pairs(Stash.descriptions) do
        read[stashMap.name] = alreadyRead:contains(stashMap.name)
        if not StashSystem.getStash(stashMap.name) then
            local engineStash = EngineStash.new(stashMap.name)
            engineStash:load(stashMap)
            all:add(engineStash)
            table.insert(added, engineStash)
        end
        removePossibleStash(stashMap.name)
    end
    local restoreRoll = Helpers.forceRolls(defer, 0)
    Stash.stockFromStart()
    restoreRoll()
    local houses = {}
    for stashMap, extra in pairs(Stash.descriptions) do
        local building = Stash.buildingOf(stashMap)
        houses[stashMap.name] = {
            queued = building ~= nil and StashSystem.isStashBuilding(building),
            read = alreadyRead:contains(stashMap.name),
            hasChance = (extra.knownOnStart or 0) > 0,
        }
    end
    restore()
    return { houses = houses }
end)

-- The prepper's map drops from survivalist and bandit corpses, whichever outfit variant they wear,
-- and turns up in vanilla's prepper crates and survivor bag; campers' glove boxes hold the trailer
-- park's; and every loot list a map names exists.
check("prepperMapTargets", function(expect)
    local D = RenewableEnergy.Distributions
    local lists = {}
    for stashMap, added in pairs(Stash.descriptions) do
        lists[stashMap.name] = {}
        for _, entry in ipairs(added.loot or {}) do
            expect(D.resolveItemList(entry[2]) ~= nil, stashMap.name .. ": no loot list " .. entry[2])
            lists[stashMap.name][entry[2]] = true
        end
    end
    local prepper = lists.RenewableEnergy_CrowcallRoad
    if not expect(prepper ~= nil, "no Crowcall Road stash") then
        return
    end
    for key in pairs(SuburbsDistributions.all) do
        if string.find(key, "^Outfit_Survivalist") or string.find(key, "^Outfit_Bandit") then
            expect(prepper["sub:all." .. key], "the Crowcall Road map does not drop from " .. key)
        end
    end
    for _, cache in ipairs({ "sub:SurvivorCache1.SurvivorCrate", "sub:SurvivorCache2.SurvivorCrate", "sub:Bag_SurvivorBag" }) do
        expect(prepper[cache], "the Crowcall Road map is not in " .. cache)
    end
    local trailerPark = lists.RenewableEnergy_DixieTrailerPark
    expect(trailerPark ~= nil and trailerPark["veh:CamperGloveBox"], "the Dixie Trailer Park map is not in camper glove boxes")
end)

-- The loot at each Stash Houses option: for every stash and loot list, how often its map is listed
-- and at what weight, against the weight the stash gives it there.
handler("stashMapsInCorpseLoot", function(_, _, defer)
    local D = RenewableEnergy.Distributions
    local options = SandboxVars.RenewableEnergy
    local restoreOptions = saveOptions(defer, { "StashMode" }, D.apply)
    local found = {}
    for _, mode in pairs(Stash.MODE) do
        options.StashMode = mode
        D.apply()
        D.apply()
        for stashMap, added in pairs(Stash.descriptions) do
            for _, entry in ipairs(added.loot or {}) do
                local count, weight = countPairs(D.resolveItemList(entry[2]), stashMap.item)
                table.insert(found, {
                    mode = mode, where = stashMap.name .. " in " .. entry[2], count = count, weight = weight, rarity = entry[1],
                })
            end
        end
    end
    restoreOptions()
    return { found = found }
end)
