require "TimedActions/ISInventoryTransferAction"
---@class RenewableEnergy
require "RenewableEnergy/Utilities"
require "RenewableEnergy/PowerBank/PowerBank"

-- A bank's parts come out only by being unwired, which gives back the wire. The container's
-- AcceptItemFunction governs only what goes in, and the engine asks nothing of Lua before an item
-- leaves (IsoObject.isRemoveItemAllowedFromContainer is Java's alone), so the player's own
-- transfers are refused here: dragging, Grab and Loot All all run ISInventoryTransferAction.
-- World spawns and the server's wiring move items without it.

local PowerBank = RenewableEnergy.PowerBank

-- Whether `item` sits wired into a bank's container.
local function isWiredIn(item, container)
    return item ~= nil and container ~= nil and PowerBank.isBank(container:getParent()) and container:contains(item)
end

local vanillaIsValid = ISInventoryTransferAction.isValid

function ISInventoryTransferAction:isValid()
    if isWiredIn(self.item, self.srcContainer) then
        HaloTextHelper.addBadText(self.character, getText("IGUI_RenewableEnergy_UnwireToRemove"))
        return false
    end
    return vanillaIsValid(self)
end
