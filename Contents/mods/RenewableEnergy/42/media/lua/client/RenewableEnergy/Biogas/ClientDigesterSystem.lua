-- The digesters as a client sees them: each one's summary through the Global Object System (looped
-- back in single player), and the item filter on this client's copies of their hoppers.

require "RenewableEnergy/Sprites"
require "RenewableEnergy/Biogas/Digester"
local ClientObjects = require "cf_commonlib/ClientObjects"

local Digester, Sprites = RenewableEnergy.Digester, RenewableEnergy.Sprites

return ClientObjects.define({
    prefix = "RenewableEnergy_", name = "Digester", owner = Digester, isObject = Digester.isDigester,
    sprites = Sprites.namesOf("digester"), loadPriority = Sprites.LOAD_PRIORITY,
    adoptCopy = function(isoObject)
        Digester.adoptContainer(isoObject:getContainer())
    end,
    adoptContainer = Digester.adoptContainer,
})
