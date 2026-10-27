-- The gasifiers as a client sees them: each one's summary through the Global Object System (looped
-- back in single player).

local Gasifier = require "RenewableEnergy/WoodGas/Gasifier"
local ClientObjects = require "cf_commonlib/ClientObjects"

return ClientObjects.define(Gasifier)
