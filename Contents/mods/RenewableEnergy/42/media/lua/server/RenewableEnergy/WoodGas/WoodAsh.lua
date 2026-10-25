-- Clearing a burnt-out campfire's ashes gives Wood Ash, so it isn't only a gasifier's by-product.
-- Vanilla's Clear Ashes just deletes them (ISClearAshes.complete, which runs on the authority).

if isClient() then return end

require "TimedActions/ISClearAshes"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/WoodGas/Gasifier"
local Items = require "cf_commonlib/Items"

local vanillaClearAshesComplete = ISClearAshes.complete
function ISClearAshes:complete()
    local done = vanillaClearAshesComplete(self)
    if done then
        Items.giveItems(self.character, RenewableEnergy.Gasifier.WOOD_ASH)
    end
    return done
end
