-- The authority's half of the stash house tests: the mod's stashes, StashSystem and the corpse
-- loot that drops their maps exist only where the authority runs them. Only registers handlers,
-- so a --stay rerun loads it again (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how these
-- handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Checks"
require "PZHarness/Fixtures"
require "RenewableEnergy/Sprites"
-- The game's Java class zombie.core.stash.Stash, which the mod's module name would hide.
local EngineStash = Stash
local Stash = require "RenewableEnergy/StashHouses"

local handler = PZHarness.serverHandler
local newCheck, countPairs = PZHarness.Checks.new, PZHarness.Fixtures.countPairs
local Sprites = RenewableEnergy.Sprites

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
