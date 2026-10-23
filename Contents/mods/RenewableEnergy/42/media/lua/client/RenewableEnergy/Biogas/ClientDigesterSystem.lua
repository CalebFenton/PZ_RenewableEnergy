-- The digesters as a client sees them: each one's summary through the Global Object System (looped
-- back in single player), and the item filter on this client's copies of their hoppers.

require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/ClientObjects"

local Digester = RenewableEnergy.Digester

return RenewableEnergy.ClientObjects.define({
    name = "Digester", sprites = RenewableEnergy.Sprites.namesOf("digester"), owner = Digester, isObject = Digester.isDigester,
    adoptCopy = function(isoObject)
        Digester.adoptContainer(isoObject:getContainer())
    end,
    adoptContainer = Digester.adoptContainer,
})
