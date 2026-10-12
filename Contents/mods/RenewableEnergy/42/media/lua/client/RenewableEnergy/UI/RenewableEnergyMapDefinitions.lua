require "ISUI/Maps/ISMapDefinitions"

-- How the mod's own map items draw (LootMaps.callLua looks them up by stash name first, then by
-- the item's Map id; the two are the same). Each shows only the few hundred squares around its
-- stash house, in the style of vanilla's stash maps. Houses drawn on vanilla town maps keep the
-- town map's own look, so they have no entry here.

-- Area of each map, in squares: west, north, east, south.
local AREAS = {
    RenewableEnergy_CrowcallRoad = { 7860, 12250, 8099, 12449 },
    RenewableEnergy_DixieTrailerPark = { 11560, 8730, 11799, 8929 },
}

local function drawArea(area)
    return function(mapUI)
        MapUtils.initDirectoryMapData(mapUI, LootMaps.DEFAULT_MAP_DIRECTORY)
        -- V3 carries the text layers; the street and place names are missing without them.
        MapUtils.initDefaultStyleV3(mapUI)
        mapUI.javaObject:getAPIv1():setBoundsInSquares(area[1], area[2], area[3], area[4])
        MapUtils.overlayPaper(mapUI)
    end
end

for mapId, area in pairs(AREAS) do
    LootMaps.Init[mapId] = drawArea(area)
end
