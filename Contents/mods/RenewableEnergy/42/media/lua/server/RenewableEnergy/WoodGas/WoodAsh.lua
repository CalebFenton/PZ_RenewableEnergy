if isClient() then return end

-- Clearing a burnt-out campfire's ashes gives Wood Ash, so it isn't only a gasifier's by-product.
-- Vanilla's Clear Ashes just deletes them (ISClearAshes.complete, which runs on the authority).

require "TimedActions/ISClearAshes"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/WoodGas/Gasifier"

local complete = ISClearAshes.complete
function ISClearAshes:complete()
    local done = complete(self)
    if done then
        RenewableEnergy.giveItems(self.character, RenewableEnergy.Gasifier.WOOD_ASH)
    end
    return done
end
