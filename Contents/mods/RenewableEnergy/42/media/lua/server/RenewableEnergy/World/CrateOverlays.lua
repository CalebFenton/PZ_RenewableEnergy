require "RenewableEnergy/Sprites"

-- The crate shows its modules while it holds 7 items or more and its closed lid below that, in any
-- room ("other"); ContainerOverlays reads tiles as { many items, few items }.
local Sprites = RenewableEnergy.Sprites

local overlayMap = { VERSION = 1 }
overlayMap[Sprites.crate] = {
    { name = "other", tiles = { Sprites.crateOverlays.full, Sprites.crateOverlays.closed } },
}

getContainerOverlays():addOverlays(overlayMap)
