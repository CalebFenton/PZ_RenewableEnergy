require "RenewableEnergy/Sprites"

-- Stash houses: buildings of the Muldraugh, KY map that the game's StashSystem stocks with a crate
-- of solar gear, once someone reads an annotated map leading there or, for some, from the first
-- day, as the Stash Houses option chooses. StashSystem reads StashDescriptions on the server and
-- in single player; Distributions.lua puts the mod's own map items into corpse loot.

RenewableEnergy = RenewableEnergy or {}
local Stash = {}
RenewableEnergy.Stash = Stash

-- Values of the StashMode sandbox option.
local StashMode = { NONE = 1, MAPS = 2, MAPS_AND_STOCKED = 3, STOCKED = 4 }

-- Description (the table StashSystem reads) -> what only the mod uses: knownOnStart, the percent
-- chance that the house is stocked from the start; rarity, the map item's weight in the corpse
-- loot lists named by targets.
Stash.descriptions = {}

-- The room definition that stocks a stash house (Distributions.lua) and the crate it brings.
local SPAWN_TABLE = "RenewableEnergyStashCache"
local CRATE_TYPE = "RenewableEnergySolarBox"
-- Vanilla's name for a map that has been drawn on.
local ANNOTATED_MAP = "Stash_AnnotedMap"

local PENCIL = { 0.2, 0.2, 0.24 }
local RED_MARKER = { 0.62, 0.1, 0.08 }

-- The corpse loot of every survivalist and bandit outfit, early, mid and late game.
local SURVIVALISTS_AND_BANDITS = {
    "Outfit_Survivalist", "Outfit_Survivalist_Mid", "Outfit_Survivalist_Late",
    "Outfit_Survivalist02", "Outfit_Survivalist02_Mid", "Outfit_Survivalist02_Late",
    "Outfit_Survivalist03", "Outfit_Survivalist03_Mid", "Outfit_Survivalist03_Late",
    "Outfit_Survivalist04", "Outfit_Survivalist04_Mid", "Outfit_Survivalist04_Late",
    "Outfit_Survivalist05", "Outfit_Survivalist05_Mid", "Outfit_Survivalist05_Late",
    "Outfit_Bandit", "Outfit_Bandit_Early", "Outfit_Bandit_Mid", "Outfit_Bandit_Late",
}

-- buildingX, buildingY: a ground floor square well inside the house; StashSystem finds the
-- building through it, and doBuildingStash only matches a building whose bounds strictly contain
-- it. crateX, crateY, crateZ: an empty floor square in one of the house's rooms, since only
-- containers in its rooms are stocked. map: the item that leads there; a mod item is a map of just
-- mapArea, the squares west, north, east and south it shows, which corpses in `mapCorpses` carry at
-- `mapWeight`, a vanilla town map is found wherever vanilla puts it. Marks are drawn on the map: a
-- symbol of MapSymbolDefinitions, or note n, whose text is the translation Stash_<name>_<n>.
local HOUSES = {
    -- A prepper's farmhouse off Crowcall Road, south of Rosewood, with a bunker under its shed.
    -- Only survivalists and bandits carry its map and it is never stocked from the start: the
    -- hardest house to find, and the best defended.
    {
        name = "RenewableEnergy_CrowcallRoad",
        map = "RenewableEnergy.CrowcallRoadMap",
        mapArea = { 7860, 12250, 8099, 12449 },
        buildingX = 7984, buildingY = 12342,
        crateX = 7985, crateY = 12341, crateZ = 0,
        barricades = 90,
        traps = "1-3",
        mapWeight = 0.1,
        mapCorpses = SURVIVALISTS_AND_BANDITS,
        marks = {
            { symbol = "X", x = 7984, y = 12342, color = RED_MARKER },
            { note = 1, x = 7993, y = 12331 },
            { symbol = "Lock", x = 7968, y = 12335 },
            { note = 2, x = 7896, y = 12322 },
            { symbol = "Trap", x = 7980, y = 12351 },
            { note = 3, x = 7988, y = 12355 },
        },
    },
    -- A mobile home at the Dixie trailer park, between Muldraugh and West Point, kept going on
    -- RV panels. Anyone may have its map, campers more often.
    {
        name = "RenewableEnergy_DixieTrailerPark",
        map = "RenewableEnergy.DixieTrailerParkMap",
        mapArea = { 11560, 8730, 11799, 8929 },
        buildingX = 11713, buildingY = 8794,
        crateX = 11714, crateY = 8789, crateZ = 0,
        zombies = 3,
        barricades = 70,
        knownOnStart = 90,
        mapWeight = 0.6,
        mapCorpses = { "inventoryfemale", "inventorymale", "Outfit_Camper" },
        marks = {
            { symbol = "X", x = 11714, y = 8792, color = RED_MARKER },
            { symbol = "Sun", x = 11722, y = 8784 },
            { note = 1, x = 11728, y = 8774 },
            { symbol = "Question", x = 11612, y = 8843 },
            { note = 2, x = 11630, y = 8855 },
            { symbol = "Skull", x = 11600, y = 8765 },
            { note = 3, x = 11612, y = 8740 },
        },
    },
    -- The barn of a farm on Soretoe Road, Rosewood, that ran its well pump and fences off solar and
    -- kept the spares there. Drawn on Rosewood town maps.
    {
        name = "RenewableEnergy_SoretoeRoadFarm",
        map = "Base.RosewoodMap",
        buildingX = 8064, buildingY = 11905,
        crateX = 8065, crateY = 11902, crateZ = 0,
        barricades = 30,
        knownOnStart = 90,
        marks = {
            { symbol = "X", x = 8064, y = 11905, color = RED_MARKER },
            { symbol = "Lightning", x = 8052, y = 11893 },
            { note = 1, x = 8078, y = 11892 },
            { symbol = "Cow", x = 8030, y = 11935 },
        },
    },
    -- An electrician's shop on Oak Street, West Point, who sold and fitted solar to the farms
    -- around town. Drawn on West Point town maps.
    {
        name = "RenewableEnergy_OakStreetElectric",
        map = "Base.WestpointMap",
        buildingX = 12130, buildingY = 6810,
        crateX = 12134, crateY = 6821, crateZ = 0,
        zombies = 3,
        barricades = 50,
        knownOnStart = 90,
        marks = {
            { symbol = "X", x = 12131, y = 6816, color = RED_MARKER },
            { symbol = "Lightning", x = 12124, y = 6800 },
            { note = 1, x = 12146, y = 6806 },
            { note = 2, x = 12146, y = 6824 },
        },
    },
}

-- A mark as StashSystem draws it (StashAnnotation.fromLua). Notes start at their point and are
-- centred on it vertically, so they read left to right from where they are written.
local function annotation(houseName, mark)
    local color = mark.color or PENCIL
    local drawn = { x = mark.x, y = mark.y, r = color[1], g = color[2], b = color[3] }
    if mark.note then
        drawn.text = "Stash_" .. houseName .. "_" .. mark.note
        drawn.anchorX, drawn.anchorY = 0, 0.5
    else
        drawn.symbol = mark.symbol
    end
    return drawn
end

-- The description StashSystem reads (Stash.load), for one house.
local function describe(house)
    local description = {
        name = house.name,
        type = "Map",
        item = house.map,
        customName = ANNOTATED_MAP,
        buildingX = house.buildingX,
        buildingY = house.buildingY,
        spawnTable = SPAWN_TABLE,
        zombies = house.zombies,
        barricades = house.barricades,
        -- StashSystem places max - min of them (doSpecificBuildingProperties).
        traps = house.traps,
        containers = { {
            containerType = CRATE_TYPE,
            containerSprite = RenewableEnergy.Sprites.crate,
            contX = house.crateX, contY = house.crateY, contZ = house.crateZ,
        } },
        annotations = {},
    }
    for _, mark in ipairs(house.marks) do
        table.insert(description.annotations, annotation(house.name, mark))
    end
    return description
end

-- Stash name -> the mapArea of its mod map item, for the map's drawing (MapDefinitions.lua).
Stash.mapAreas = {}

for _, house in ipairs(HOUSES) do
    Stash.descriptions[describe(house)] = {
        knownOnStart = house.knownOnStart,
        rarity = house.mapWeight,
        targets = house.mapCorpses,
    }
    Stash.mapAreas[house.name] = house.mapArea
end

--- Whether the Stash Houses option puts the maps into corpse loot.
function Stash.mapsInLoot()
    local mode = SandboxVars.RenewableEnergy.StashMode
    return mode == StashMode.MAPS or mode == StashMode.MAPS_AND_STOCKED
end

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

--- Adds the houses to StashDescriptions, once however often it is called, unless the Stash Houses
--- option leaves them out. Returns whether the option uses them.
function Stash.register()
    if SandboxVars.RenewableEnergy.StashMode == StashMode.NONE then
        return false
    end
    StashDescriptions = StashDescriptions or {}
    local present = {}
    for _, description in ipairs(StashDescriptions) do
        present[description] = true
    end
    for description in pairs(Stash.descriptions) do
        if not present[description] then
            table.insert(StashDescriptions, description)
        end
    end
    return true
end

-- Stocking needs StashSystem to know the houses, which it does by the first tick of the game.
local function stockOnFirstTick()
    Events.OnTick.Remove(stockOnFirstTick)
    Stash.stockFromStart()
end

-- OnLoadedMapZones follows StashSystem.load on every side. A multiplayer client keeps no stash
-- state.
local function onLoadedMapZones()
    if not isClient() then
        Stash.relistUnfound()
    end
end

-- StashSystem.init reads StashDescriptions after OnInitGlobalModData (IsoWorld.init), by which
-- time the save's sandbox options are loaded.
local function onInitGlobalModData(isNewGame)
    if not Stash.register() then
        return
    end
    Events.OnLoadedMapZones.Add(onLoadedMapZones)
    if isNewGame and not isClient() and SandboxVars.RenewableEnergy.StashMode ~= StashMode.MAPS then
        Events.OnTick.Add(stockOnFirstTick)
    end
end

Events.OnInitGlobalModData.Add(onInitGlobalModData)

return Stash
