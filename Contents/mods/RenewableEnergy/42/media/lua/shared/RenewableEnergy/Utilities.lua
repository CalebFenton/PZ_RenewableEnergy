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

--- Shows `wanted` (a sprite name, or nil for none) as the one overlay of the kind `isKind(name)`
--- tells on `isoObject`, and sends the tile on when that changes it. Authority only.
function RenewableEnergy.showOverlay(isoObject, isKind, wanted)
    local attached = isoObject:getAttachedAnimSprite()
    local count = attached and attached:size() or 0
    local shown
    for i = 0, count - 1 do
        local name = attached:get(i):getName()
        if isKind(name) then
            shown = name
        end
    end
    if shown == wanted then return end
    for i = count - 1, 0, -1 do
        if isKind(attached:get(i):getName()) then
            isoObject:RemoveAttachedAnim(i)
        end
    end
    if wanted then
        isoObject:addAttachedAnimSpriteByName(wanted)
    end
    isoObject:transmitUpdatedSpriteToClients()
end

-- A job's needs are a list of what it takes of the character, each { kind, have, need } with
-- what it names: `perk` for a skill, `tool` (an ItemTag field) for a tool, `item` (a full type)
-- for an item counted by type, `input` (an InputScript) for a recipe's input, `recipe` for a
-- recipe to know (have 1 when known). The same list refuses the job and tells the menu what it
-- lacks, so the two can't disagree.

--- The first of `needs` the character is short of, or nil when they have them all.
function RenewableEnergy.firstUnmet(needs)
    for _, need in ipairs(needs) do
        if need.have < need.need then
            return need
        end
    end
    return nil
end

return RenewableEnergy
