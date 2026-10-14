-- Helpers that several of the mod's modules share.
--
-- RenewableEnergy is the mod's one global table. The only other global is the timed action class
-- RenewableEnergyAction, which the game looks up by name. Every file that adds to the table
-- creates it first if no file has yet, so files may load in any order.

RenewableEnergy = RenewableEnergy or {}

--- The first object on `square` for which `matches(object)` is true, or nil. Takes a nil square.
function RenewableEnergy.findObjectOn(square, matches)
    local objects = square and square:getObjects()
    for i = 0, (objects and objects:size() or 0) - 1 do
        local object = objects:get(i)
        if matches(object) then
            return object
        end
    end
    return nil
end

--- Takes `item` from `character`: out of their hands and out of the container that holds it, and
--- tells the clients. Authority only.
function RenewableEnergy.takeItem(character, item)
    character:removeFromHands(item)
    local container = item:getContainer()
    if container then
        container:Remove(item)
        sendRemoveItemFromContainer(container, item)
    end
end

return RenewableEnergy
