-- How the mod's own map items draw (LootMaps.callLua looks them up by stash name first, then by
-- the item's Map id; the two are the same). Each shows only its stash house's mapArea
-- (Stash.lua), in the style of vanilla's stash maps. Houses drawn on vanilla town maps have
-- no mapArea and keep the town map's own look.

require "ISUI/Maps/ISMapDefinitions"
require "RenewableEnergy/Stash"

local function drawArea(area)
    return function(mapUI)
        MapUtils.initDirectoryMapData(mapUI, LootMaps.DEFAULT_MAP_DIRECTORY)
        -- V3 carries the text layers; the street and place names are missing without them.
        MapUtils.initDefaultStyleV3(mapUI)
        mapUI.javaObject:getAPIv1():setBoundsInSquares(area[1], area[2], area[3], area[4])
        MapUtils.overlayPaper(mapUI)
    end
end

for mapId, area in pairs(RenewableEnergy.Stash.mapAreas) do
    LootMaps.Init[mapId] = drawArea(area)
end
