-- The gasifiers as a client sees them: each one's summary through the Global Object System (looped
-- back in single player), and the item filters on this client's copies of their containers.

require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/ClientObjects"

local Gasifier = RenewableEnergy.Gasifier

return RenewableEnergy.ClientObjects.define({
    name = "Gasifier", sprites = RenewableEnergy.Sprites.namesOf("gasifier"), owner = Gasifier, isObject = Gasifier.isGasifier,
    adoptCopy = Gasifier.adoptContainers, adoptContainer = Gasifier.adoptContainer,
})
