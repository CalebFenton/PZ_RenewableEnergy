-- The gasifiers as a client sees them: each one's summary through the Global Object System (looped
-- back in single player), and the item filters on this client's copies of their containers.

local Sprites = require "RenewableEnergy/Sprites"
local Gasifier = require "RenewableEnergy/WoodGas/Gasifier"
local ClientObjects = require "cf_commonlib/ClientObjects"

return ClientObjects.define({
    prefix = "RenewableEnergy_", name = "Gasifier", owner = Gasifier, isObject = Gasifier.isGasifier,
    sprites = Sprites.namesOf("gasifier"), loadPriority = Sprites.LOAD_PRIORITY,
    adoptCopy = Gasifier.adoptContainers, adoptContainer = Gasifier.adoptContainer,
})
