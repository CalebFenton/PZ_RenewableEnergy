-- The crate shows its modules while it holds enough items for vanilla's "many items" overlay
-- (ContainerOverlays.updateContainerOverlaySprite) and its closed lid below that, in any room
-- ("other"); ContainerOverlays reads tiles as { many items, few items }.

require "RenewableEnergy/Sprites"

local Sprites = RenewableEnergy.Sprites

local overlayMap = { VERSION = 1 }
overlayMap[Sprites.crate] = {
    { name = "other", tiles = { Sprites.crateOverlays.full, Sprites.crateOverlays.closed } },
}

getContainerOverlays():addOverlays(overlayMap)
