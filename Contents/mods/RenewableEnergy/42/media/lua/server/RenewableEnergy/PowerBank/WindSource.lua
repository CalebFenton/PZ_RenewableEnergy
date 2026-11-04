-- How a bank runs a wind charger (the "wind" family of Sources) on the authority:
-- its output in the wind and its blades breaking in a gale. Sets a charger's brake and broken
-- blades on the object and on its bank's record alike.

if isClient() then return end

local Utilities = require "RenewableEnergy/Utilities"
local StormChance = require "RenewableEnergy/StormChance"
local Specs = require "RenewableEnergy/Specs"
local StormNotice = require "RenewableEnergy/StormNotice"
local Wind = require "RenewableEnergy/Wind"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local Sources = require "RenewableEnergy/PowerBank/Sources"
local Chance = require "cf_commonlib/Chance"

local WindSource = {}

-- A charger losing at least this share to other chargers near it says so, when shelter doesn't.
local CROWDED_LOSS = 0.15

local function hasWallFlag(properties)
    return properties:has(IsoFlagType.WallN) or properties:has(IsoFlagType.WallW) or properties:has(IsoFlagType.WallNW)
end

-- Whether `properties` (a tile's) carry a wall flag and no fence's: window and door frames
-- (WindowN, DoorWallN and their W twins) and see-through fences (WallNTrans, WallWTrans) carry no
-- WallN or WallW; fences that do, tall wooden fences and low walls, are told apart by their
-- Hoppable and TallHoppable flags, as vanilla's own wall checks tell them (IsoGridSquare, beside
-- its WallN tests).
local function isSolidWall(properties)
    return hasWallFlag(properties)
        and not (properties:has(IsoFlagType.HoppableN) or properties:has(IsoFlagType.HoppableW)
            or properties:has(IsoFlagType.TallHoppableN) or properties:has(IsoFlagType.TallHoppableW))
end

-- Whether `square` (nil for none) holds a solid wall. Its own flags are those of all its tiles
-- together, so a fence on one edge and a wall on another read as neither: each tile is checked,
-- once the square's flags show a wall there at all.
local function hasSolidWall(square)
    local properties = square and square:getProperties()
    if not (properties and hasWallFlag(properties)) then
        return false
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local tile = objects:get(i):getProperties()
        if tile and isSolidWall(tile) then
            return true
        end
    end
    return false
end

-- Whether the column at (x, y) shelters a rotor turning on level `level`: a tree while the rotor is
-- no higher than the treetops (Wind.SPEC.treetopLevel), a building whose roof reaches the rotor
-- (a roof stands a level above its top floor), or a solid wall on the rotor's own level, the map's
-- or one a player built.
local function blocks(x, y, level)
    local ground = getSquare(x, y, 0)
    if not ground then
        return 0
    end
    if level <= Wind.SPEC.treetopLevel and ground:HasTree() then
        return 1
    end
    local building = ground:getBuilding()
    if building and building:getDef() and building:getDef():getMaxLevel() + 1 >= level then
        return 1
    end
    return hasSolidWall(level == 0 and ground or getSquare(x, y, level)) and 1 or 0
end

-- The offsets of the ring of squares from 1 to a radius around one, { dx, dy, distance } each, by
-- radius: worked out once, as the radii are constants.
local rings = {}

-- Calls fn(dx, dy, distance) for each offset of the ring of squares from 1 to `radius` around one.
local function eachInRing(radius, fn)
    local ring = rings[radius]
    if not ring then
        ring = {}
        for dx = -radius, radius do
            for dy = -radius, radius do
                local distance = math.sqrt(dx * dx + dy * dy)
                if distance >= 1 and distance <= radius then
                    table.insert(ring, { dx, dy, distance })
                end
            end
        end
        rings[radius] = ring
    end
    for _, offset in ipairs(ring) do
        fn(offset[1], offset[2], offset[3])
    end
end

-- The level the rotor of a charger of `kind` standing on level `z` turns on.
local function rotorLevel(kind, z)
    return z + Wind.SPEC.turbines[kind].rotorAbove
end

-- The share of the ring of squares around (x, y) on the ground, out to Wind.SPEC.shelterRadius,
-- that shelters the rotor of a charger of `kind` standing on level `z`: 0 in the open, 1 hemmed
-- in. Shelter has no direction: the game's wind angle is a screen-space value for weather effects
-- (ClimateManager.getWindAngleDegrees), so every side counts.
local function shelterAt(kind, x, y, z)
    local radius, level = Wind.SPEC.shelterRadius, rotorLevel(kind, z)
    local blocked, count = 0, 0
    eachInRing(radius, function(dx, dy, distance)
        -- Nearer obstacles count for more.
        local weight = 1 - (distance - 1) / radius
        blocked = blocked + weight * blocks(x + dx, y + dy, level)
        count = count + weight
    end)
    return count > 0 and blocked / count or 0
end

-- The share of its wind the rotor of a charger of `kind` at x, y, z loses to the other chargers
-- whose rotors turn on its level within Wind.SPEC.crowdRadius (Wind.crowding). They stand on that
-- level or the one below, as rotorAbove is 0 or 1. Only loaded ones count, as shelter does.
local function crowdingAt(kind, x, y, z)
    local radius, level = Wind.SPEC.crowdRadius, rotorLevel(kind, z)
    local distances = {}
    for floor = level - 1, level do
        eachInRing(radius, function(dx, dy, distance)
            local other = Sources.findOn(getSquare(x + dx, y + dy, floor))
            local otherKind = other and Sources.kindOf(other)
            if otherKind and Sources.familyOf(otherKind) == "wind" and rotorLevel(otherKind, floor) == level then
                table.insert(distances, distance)
            end
        end)
    end
    return Wind.crowding(distances)
end

local function setFlag(isoObject, key, on)
    isoObject:getModData()[key] = on or nil
    isoObject:transmitModData()
end

--- Sets the brake of the wind charger `isoObject`, and of `source`, its bank's record, if it feeds
--- one (else nil).
function WindSource.setBraked(isoObject, braked, source)
    setFlag(isoObject, Wind.BRAKED_KEY, braked)
    if source then
        source.braked = braked
    end
end

--- Marks the blades of the wind charger `isoObject` broken or whole, and of `source`, its bank's
--- record, if it feeds one (else nil).
function WindSource.setBroken(isoObject, broken, source)
    setFlag(isoObject, Wind.BROKEN_KEY, broken)
    if source then
        source.broken = broken
    end
end

--- Fits blades of `material` (Wind.SPEC.blades), which its kind takes, to the wind charger
--- `isoObject`, and to `source`, its bank's record, if it feeds one (else nil). Blades of another
--- material than it turns make it that material's tile (Wind.setBladesTile), on every side.
function WindSource.fitBlades(isoObject, material, source)
    if source then
        source.blades = material
    end
    if Wind.bladesOfObject(isoObject) == material or not Wind.setBladesTile(isoObject, material) then return end
    isoObject:transmitUpdatedSpriteToClients()
    -- After the tile, as DigesterObject:upgrade sends it: a client's SpriteConfig checks its new
    -- script against the tile it shows. Single player has no other copy.
    if isServer() then
        isoObject:sendSyncEntity(nil)
    end
end

-- The blades of the charger `source` (a Wind.SPEC.blades material, nil for none): the record's,
-- else, for a record from before it kept them, the first its kind takes.
local function bladesOf(source)
    return source.blades or Wind.bladesOf(source.kind)
end

-- The chance that a wind charger left running through `hours` of a wind of `kph` breaks its
-- blades, at their stormShare and the wind's strength over their break speed on it
-- (StormChance.stormStrength), scaled by the StormDamage options: none while braked or broken
-- already.
local function breakChance(source, kph, hours)
    local spec, blades = Wind.SPEC.turbines[source.kind], bladesOf(source)
    if source.braked or source.broken or not Wind.canBreak(spec, blades, kph) then
        return 0
    end
    return StormChance.stormDamage(StormChance.stormPerHour(Wind.SPEC.blades[blades].stormShare),
        hours * StormChance.stormStrength(Wind.breakKph(spec, blades), kph))
end

-- No roll when the blades can't break, so a test's set rolls go only to chances that can come up.
local function breaks(source, kph, hours)
    local chance = breakChance(source, kph, hours)
    return chance > 0 and Chance.hit(chance)
end

--- A newly connected wind charger's record: its broken blades as the object has them, the rest as
--- WindSource.reconcile reads them. A charger teaches its wiring the first time a player connects
--- it; the world wires a site's charger with no player (SolarSites), which leaves the lesson to the
--- one who rewires it.
function WindSource.connect(player, source, isoObject)
    source.broken = Wind.isBroken(isoObject)
    WindSource.reconcile(source, isoObject)
    if player and Utilities.teachOnce(player, isoObject, Panel.CONNECTED_ONCE_KEY, Perks.Electricity,
        Specs.connectXp * Sources.slotsOf(source.kind)) then
        isoObject:transmitModData()
    end
end

-- Its broken blades are the record's, which a gale may break while the object is unloaded, and go
-- to the object when it is loaded.
local function showBroken(source, object)
    if Wind.isBroken(object) ~= (source.broken == true) then
        WindSource.setBroken(object, source.broken == true, source)
    end
end

--- Brings the record `source` and its loaded charger `object` into step: its brake and blades are
--- the object's (setBraked sets both), its broken blades the record's (showBroken), and its
--- shelter and crowding are counted again, since trees, buildings, walls and chargers around it
--- change.
function WindSource.reconcile(source, object)
    source.braked = Wind.isBraked(object)
    source.blades = Wind.bladesOfObject(object)
    source.shelter = shelterAt(source.kind, source.x, source.y, source.z)
    source.crowding = crowdingAt(source.kind, source.x, source.y, source.z)
    showBroken(source, object)
end

--- The charger's output over the pass, and why it makes nothing or little: in a gale that can
--- break its blades, braked, broken, calm, furled, sheltered or crowded. Blades breaking tell the
--- players in earshot (StormNotice).
function WindSource.update(source, object, inSlot, hours, context)
    local spec = Wind.SPEC.turbines[source.kind]
    if object then
        WindSource.reconcile(source, object)
    end
    if breaks(source, context.windKph, hours) then
        source.broken = true
        StormNotice.tell(bladesOf(source), source.x, source.y, source.z)
        if object then
            showBroken(source, object)
        end
    end
    local watts = Wind.watts(spec, context.windKph, source.z, source.shelter or 0, source.crowding)
    source.watts = (inSlot and not source.braked and not source.broken) and watts or 0
    if not (source.braked or source.broken) and Wind.canBreak(spec, bladesOf(source), context.windKph) then
        source.reason = "gale"
    elseif not inSlot then
        source.reason = "noController"
    elseif source.braked then
        source.reason = "braked"
    elseif source.broken then
        source.reason = "broken"
    elseif context.windKph <= spec.cutInKph then
        source.reason = "calm"
    elseif Wind.furled(spec, context.windKph) then
        source.reason = "furled"
    elseif (source.shelter or 0) * Wind.SPEC.shelterLoss > Wind.SPEC.shelteredShare then
        source.reason = "sheltered"
    elseif (source.crowding or 0) >= CROWDED_LOSS then
        source.reason = "crowded"
    else
        source.reason = nil
    end
end

--- The charger's part of its status entry: its brake, blades, shelter and crowding.
function WindSource.status(entry, source)
    entry.braked, entry.broken = source.braked == true, source.broken == true
    entry.shelterPct = round(100 * (source.shelter or 0))
    entry.crowdingPct = round(100 * (source.crowding or 0))
end

return WindSource
