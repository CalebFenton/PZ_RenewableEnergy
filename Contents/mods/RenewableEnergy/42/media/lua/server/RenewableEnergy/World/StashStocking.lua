if isClient() then
    return
end

require "RenewableEnergy/StashHouses"

-- The authority's part of the stash houses (shared StashHouses.lua): stocking some from the start
-- and listing them again in older saves. A multiplayer client keeps no stash state.

local Stash = RenewableEnergy.Stash

--- Stocks each house that rolls its knownOnStart chance. StashSystem.prepareBuildingStash also
--- records the stash as a map already read, and the world map draws every such entry as a found
--- map (ISWorldMap.renderStashMaps), which would give the house away on day one.
function Stash.stockFromStart()
    local alreadyRead = StashSystem.getAlreadyReadMap()
    for description, extra in pairs(Stash.descriptions) do
        if extra.knownOnStart and ZombRand(100) < extra.knownOnStart then
            StashSystem.prepareBuildingStash(description.name)
            alreadyRead:remove(description.name)
        end
    end
end

--- Puts each house back among StashSystem's possible stashes if it is missing there, nobody has
--- read its map and nobody has entered it, so that a map found later leads to it.
---
--- IsoWorld.init fills the possible stashes from StashDescriptions and then replaces them with
--- the list the save stored. A world saved before the option was turned on, or before a house was
--- added, has none of them there, so their maps would drop with nothing drawn on them.
function Stash.relistUnfound()
    local possible = StashSystem.getPossibleStashes()
    local listed = {}
    for i = 0, possible:size() - 1 do
        listed[possible:get(i):getName()] = true
    end
    local alreadyRead = StashSystem.getAlreadyReadMap()
    local metaGrid = getWorld():getMetaGrid()
    for description in pairs(Stash.descriptions) do
        local name = description.name
        if not listed[name] and not alreadyRead:contains(name) then
            local room = metaGrid:getRoomAt(description.buildingX, description.buildingY, 0)
            local building = room and room:getBuilding()
            if building and not building:isHasBeenVisited() then
                possible:add(StashBuilding.new(name, description.buildingX, description.buildingY))
            end
        end
    end
end

-- Stocking needs StashSystem to know the houses, which it does by the first tick of the game. The
-- handler removes itself, so it runs that one tick only.
local function stockOnFirstTick()
    Events.OnTick.Remove(stockOnFirstTick)
    Stash.stockFromStart()
end

-- After the shared file's handler has registered the houses. OnLoadedMapZones follows
-- StashSystem.load.
local function onInitGlobalModData(isNewGame)
    if not Stash.enabled() then
        return
    end
    Events.OnLoadedMapZones.Add(Stash.relistUnfound)
    if isNewGame and Stash.stockedFromStart() then
        Events.OnTick.Add(stockOnFirstTick)
    end
end

Events.OnInitGlobalModData.Add(onInitGlobalModData)
