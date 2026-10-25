-- The gasifiers as a client sees them: each one's summary through the Global Object System (looped
-- back in single player), and the item filters on this client's copies of their containers.

require "RenewableEnergy/Sprites"
require "RenewableEnergy/WoodGas/Gasifier"
local ClientObjects = require "cf_commonlib/ClientObjects"

local Gasifier, Sprites = RenewableEnergy.Gasifier, RenewableEnergy.Sprites

return ClientObjects.define({
    prefix = "RenewableEnergy_", name = "Gasifier", owner = Gasifier, isObject = Gasifier.isGasifier,
    sprites = Sprites.namesOf("gasifier"), loadPriority = Sprites.LOAD_PRIORITY,
    adoptCopy = Gasifier.adoptContainers, adoptContainer = Gasifier.adoptContainer,
})
