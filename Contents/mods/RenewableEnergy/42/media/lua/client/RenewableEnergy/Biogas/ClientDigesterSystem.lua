-- The digesters as a client sees them: each one's summary through the Global Object System (looped
-- back in single player).

local Digester = require "RenewableEnergy/Biogas/Digester"
local ClientObjects = require "cf_commonlib/ClientObjects"

return ClientObjects.define(Digester)
