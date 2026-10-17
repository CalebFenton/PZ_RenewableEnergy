-- Helpers that several of the mod's modules share.
--
-- RenewableEnergy is the mod's one global table. The other globals are the timed action classes
-- (RenewableEnergy*Action), which the game looks up by name. Every file that adds to the table
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

--- Takes `count` items of `fullType` from `character`'s inventory, bags included. Authority only.
function RenewableEnergy.takeItems(character, fullType, count)
    if count <= 0 then return end
    local items = character:getInventory():getSomeTypeRecurse(fullType, count)
    for i = 0, items:size() - 1 do
        RenewableEnergy.takeItem(character, items:get(i))
    end
end

--- Gives `character` `count` (default 1) of `itemOrType`, an item or a full type, dropping on
--- their square what doesn't fit (Actions.addOrDropItem, which also syncs). Authority only.
function RenewableEnergy.giveItems(character, itemOrType, count)
    for _ = 1, count or 1 do
        local item = type(itemOrType) == "string" and instanceItem(itemOrType) or itemOrType
        Actions.addOrDropItem(character, item)
    end
end

function RenewableEnergy.notBroken(item)
    return not item:isBroken()
end

--- Whether `character` carries a working tool with `tag` (an ItemTag value), bags included.
function RenewableEnergy.hasWorkingTool(character, tag)
    return character:getInventory():containsTagEvalRecurse(tag, RenewableEnergy.notBroken)
end

--- `value` rounded to `places` decimal places (default 0).
function RenewableEnergy.round(value, places)
    local scale = 10 ^ (places or 0)
    return math.floor(value * scale + 0.5) / scale
end

--- Whether two values are the same, tables by what they hold, at any depth. Summaries compare
--- so, to send only what changed.
function RenewableEnergy.sameValue(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for key, value in pairs(a) do
        if not RenewableEnergy.sameValue(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

--- An action advances by GameTime.getMultiplier() each tick (BaseAction.update), and in the same
--- tick the clock advances getMultiplier() / (2 * minutesPerDay) in-game minutes (GameTime.update),
--- so one in-game minute is 2 * minutesPerDay units at any frame rate or game speed.
function RenewableEnergy.unitsPerMinute()
    return 2 * getGameTime():getMinutesPerDay()
end

--- Whether `object` is still in the world, rather than a copy left behind by a removal or a
--- chunk reload.
function RenewableEnergy.onSquare(object)
    return object ~= nil and object:getObjectIndex() ~= -1
end

--- Whether `character` stands within `reach` squares on each axis of the middle of `target`'s
--- square, on its level: where the menu walked them for a job there (luautils.walkAdj), with room
--- for drift and a client's lag. A vehicle `target` gets `reach` past half its longest side, round
--- its middle, as the menu walks the character to one of its areas
--- (ISPathFindAction.pathToVehicleArea). The authority checks it before doing a job.
function RenewableEnergy.withinReach(character, target, reach)
    if instanceof(target, "BaseVehicle") then
        local extents = target:getScript():getExtents()
        local around = math.max(extents:x(), extents:z()) / 2 + reach
        return IsoUtils.DistanceTo(character:getX(), character:getY(), target:getX(), target:getY()) <= around
            and math.abs(character:getZ() - target:getZ()) < 1
    end
    local square = target:getSquare()
    return square ~= nil and math.abs(character:getX() - (square:getX() + 0.5)) <= reach
        and math.abs(character:getY() - (square:getY() + 0.5)) <= reach
        and math.abs(character:getZ() - square:getZ()) < 1
end

-- The map's lowest and highest levels (IsoChunk.getGridSquare).
local LOWEST_LEVEL, HIGHEST_LEVEL = -32, 31

--- Whether the square x, y, z is in a generator's reach of `origin` (an IsoGridSquare or an
--- IsoObject on one): GeneratorTileRange squares between square middles and
--- GeneratorVerticalPowerRange levels, as IsoGenerator.isPoweringSquare measures it. That one reads
--- copies of the options taken only as a generator is built, so this reads the options.
function RenewableEnergy.inGeneratorReach(origin, x, y, z)
    local radius, levels = SandboxVars.GeneratorTileRange, SandboxVars.GeneratorVerticalPowerRange
    local dx, dy, dz = x - origin:getX(), y - origin:getY(), z - origin:getZ()
    return z >= LOWEST_LEVEL and z <= HIGHEST_LEVEL and math.abs(dz) <= levels and dx * dx + dy * dy <= radius * radius
end

--- Calls `fn(square)` for every loaded square in a generator's reach of `origin`
--- (RenewableEnergy.inGeneratorReach).
function RenewableEnergy.eachSquareInGeneratorReach(origin, fn)
    local radius, levels = SandboxVars.GeneratorTileRange, SandboxVars.GeneratorVerticalPowerRange
    local cx, cy, cz = origin:getX(), origin:getY(), origin:getZ()
    local cell = getCell()
    local radiusSquared = radius * radius
    for z = math.max(LOWEST_LEVEL, cz - levels), math.min(HIGHEST_LEVEL, cz + levels) do
        for x = cx - radius, cx + radius do
            local dxSquared = (x - cx) * (x - cx)
            for y = cy - radius, cy + radius do
                local square = dxSquared + (y - cy) * (y - cy) <= radiusSquared and cell:getGridSquare(x, y, z)
                if square then
                    fn(square)
                end
            end
        end
    end
end

--- Shows `wanted` (a list of sprite names, in drawing order) as the overlays of the kind
--- `isKind(name)` tells on `isoObject`, and sends the tile on when that changes it. Authority only.
function RenewableEnergy.showOverlays(isoObject, isKind, wanted)
    local attached = isoObject:getAttachedAnimSprite()
    local count = attached and attached:size() or 0
    local shown = {}
    for i = 0, count - 1 do
        local name = attached:get(i):getName()
        if isKind(name) then
            table.insert(shown, name)
        end
    end
    if RenewableEnergy.sameValue(shown, wanted) then return end
    for i = count - 1, 0, -1 do
        if isKind(attached:get(i):getName()) then
            isoObject:RemoveAttachedAnim(i)
        end
    end
    for _, name in ipairs(wanted) do
        isoObject:addAttachedAnimSpriteByName(name)
    end
    isoObject:transmitUpdatedSpriteToClients()
end

--- Shows `wanted` (a sprite name, or nil for none) as the one overlay of the kind `isKind(name)`
--- tells on `isoObject`, as showOverlays does.
function RenewableEnergy.showOverlay(isoObject, isKind, wanted)
    RenewableEnergy.showOverlays(isoObject, isKind, wanted and { wanted } or {})
end

--- The game entity script whose SpriteConfig names the tile `spriteName`, or nil: what an object
--- on that tile is, found as vanilla's MORainCollectorBarrel finds it.
function RenewableEnergy.tileEntity(spriteName)
    local info = SpriteConfigManager.getObjectInfoFromSprite(spriteName)
    return info and info:getScript():getParent()
end

--- Shows the entity `isoObject` as the tile `spriteName` and makes it that tile's entity
--- (tileEntity). A SpriteConfig takes only its own entity's tiles: one left on another tile is
--- disowned with a warning wherever the object loads, on each client and after each reload
--- (SpriteConfig.initObjectInfo). Authority only; the caller sends the object on.
function RenewableEnergy.setEntityTile(isoObject, spriteName)
    -- The tile's own sprite, with its properties; setSprite(name) would make a bare texture.
    isoObject:setSprite(getSprite(spriteName))
    local script = RenewableEnergy.tileEntity(spriteName)
    if not script or isoObject:getEntityScript() == script then return end
    -- By type, as removing one shifts the others' indexes; CreateIsoObjectEntity wants none left.
    local types = {}
    for i = 0, isoObject:componentSize() - 1 do
        table.insert(types, isoObject:getComponentForIndex(i):getComponentType())
    end
    for _, componentType in ipairs(types) do
        GameEntityFactory.RemoveComponentType(isoObject, componentType)
    end
    GameEntityFactory.CreateIsoObjectEntity(isoObject, script, true)
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
