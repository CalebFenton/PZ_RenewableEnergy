-- The authority's half of the tile tests: placed panels, their modData, and scrapping. Only registers
-- handlers, so a --stay rerun loads it again (RELOAD_FILES); RenewableEnergyTestHelpers.lua says
-- how these handlers work.

require "PZHarness/ServerHandlers"
require "RenewableEnergy/Sprites"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler
local objectAt, overlaysOf = Helpers.objectAt, Helpers.overlaysOf
local Sprites = RenewableEnergy.Sprites

-- The panel drawn as `args.sprite` on the square at `args`, changed by `args.change`, if given: its
-- modules replaced by `change.modules` and, with `change.snow`, snow laid on it first; then its
-- cracks shown as the mod shows them. Answers its overlays in drawing order.
handler("panelCracks", function(_, args)
    local PanelSource = RenewableEnergy.PanelSource
    local panel, missing = objectAt(args)
    if not panel then
        return nil, missing
    end
    local change = args.change
    if change then
        if change.snow then
            panel:addAttachedAnimSpriteByName(Sprites.snow.flat)
        end
        PanelSource.writeModules(panel, change.modules)
    end
    PanelSource.showCracks(panel)
    return { overlays = overlaysOf(panel) }
end)

-- The modData key `args.key` of the object drawn as `args.sprite` on the square at `args`.
handler("objectModData", function(_, args)
    local object, missing = objectAt(args)
    if not object then
        return nil, missing
    end
    return { value = object:getModData()[args.key] }
end)

-- What cutting up the tile `args.sprite` gives the authority's character, where scrapping
-- completes (ISMoveableSpriteProps.getScrapItemsList): the clicked tile's items, or another tile's
-- of the same object if `args.otherTile`. Answers the count of `args.type` among the usable items.
handler("scrapItems", function(player, args)
    local props = ISMoveableSpriteProps.new(args.sprite)
    if args.otherTile then
        props.scrappingMainTile = false
    end
    local items = props:getScrapItemsList(player)
    local count = 0
    for _, fullType in ipairs(items and items.usable or {}) do
        count = count + (fullType == args.type and 1 or 0)
    end
    return { count = count }
end)
