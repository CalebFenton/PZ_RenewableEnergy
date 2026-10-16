if isClient() then return end

-- Clearing a burnt-out campfire's ashes gives Wood Ash, so it isn't only a gasifier's by-product.
-- Vanilla's Clear Ashes just deletes them (ISClearAshes.complete, which runs on the authority).

require "TimedActions/ISClearAshes"

local WOOD_ASH = "RenewableEnergy.WoodAsh"

local complete = ISClearAshes.complete
function ISClearAshes:complete()
    local done = complete(self)
    if done then
        local inventory = self.character:getInventory()
        local ash = inventory:AddItem(WOOD_ASH)
        if ash then
            sendAddItemToContainer(inventory, ash)
        end
    end
    return done
end
