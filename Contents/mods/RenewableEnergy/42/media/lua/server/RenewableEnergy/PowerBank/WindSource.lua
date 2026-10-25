-- How a bank runs a wind charger (the "wind" family of RenewableEnergy.Sources) on the authority:
-- its output in the wind and its blades breaking in a gale. Sets a charger's brake and broken
-- blades on the object and on its bank's record alike.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Chance"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/StormNotice"
require "RenewableEnergy/Wind"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"

RenewableEnergy = RenewableEnergy or {}
local Chance, Specs, StormNotice, Wind = RenewableEnergy.Chance, RenewableEnergy.Specs, RenewableEnergy.StormNotice, RenewableEnergy.Wind
local PowerBank, Sources, Sprites = RenewableEnergy.PowerBank, RenewableEnergy.Sources, RenewableEnergy.Sprites

local WindSource = {}
RenewableEnergy.WindSource = WindSource

-- A charger losing more than this share of its watts to shelter says so in the status.
local SHELTERED_LOSS = 0.3
-- A charger losing at least this share to other chargers near it says so, when shelter doesn't:
-- a neighbour two squares off costs about this much (Wind.crowdShare).
local CROWDED_LOSS = 0.15

-- Whether `properties` (a tile's) carry a wall flag and no fence's: window and door frames
-- (WindowN, DoorWallN and their W twins) and see-through fences (WallNTrans, WallWTrans) carry no
-- WallN or WallW; fences that do, tall wooden fences and low walls, are told apart by their
-- Hoppable and TallHoppable flags, as vanilla's own wall checks tell them (IsoGridSquare, beside
-- its WallN tests).
local function isSolidWall(properties)
    return (properties:has(IsoFlagType.WallN) or properties:has(IsoFlagType.WallW) or properties:has(IsoFlagType.WallNW))
        and not (properties:has(IsoFlagType.HoppableN) or properties:has(IsoFlagType.HoppableW)
            or properties:has(IsoFlagType.TallHoppableN) or properties:has(IsoFlagType.TallHoppableW))
end

-- Whether `square` (nil for none) holds a solid wall. Its own flags are those of all its tiles
-- together, so a fence on one edge and a wall on another read as neither: each tile is checked,
-- once the square's flags show a wall there at all.
local function hasSolidWall(square)
    local properties = square and square:getProperties()
    if not (properties and (properties:has(IsoFlagType.WallN) or properties:has(IsoFlagType.WallW)
            or properties:has(IsoFlagType.WallNW))) then
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
-- no higher than the treetops (Specs.wind.treetopLevel), a building whose roof reaches the rotor
-- (a roof stands a level above its top floor), or a solid wall on the rotor's own level, the map's
-- or one a player built.
local function blocks(x, y, level)
    local ground = getSquare(x, y, 0)
    if not ground then
        return 0
    end
    if level <= Specs.wind.treetopLevel and ground:HasTree() then
        return 1
    end
    local building = ground:getBuilding()
    if building and building:getDef() and building:getDef():getMaxLevel() + 1 >= level then
        return 1
    end
    return hasSolidWall(level == 0 and ground or getSquare(x, y, level)) and 1 or 0
end

-- The share of the ring of squares around (x, y) on the ground, out to Specs.wind.shelterRadius,
-- that shelters the rotor of a turbine of `spec` standing on level `z`, which turns rotorAbove
-- levels higher: 0 in the open, 1 hemmed in. Shelter has no direction: the game's wind angle is a
-- screen-space value for weather effects (ClimateManager.getWindAngleDegrees), so every side counts.
local function shelterAt(spec, x, y, z)
    local radius = Specs.wind.shelterRadius
    local level = z + spec.rotorAbove
    local blocked, count = 0, 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance >= 1 and distance <= radius then
                -- Nearer obstacles count for more.
                local weight = 1 - (distance - 1) / radius
                blocked = blocked + weight * blocks(x + dx, y + dy, level)
                count = count + weight
            end
        end
    end
    return count > 0 and blocked / count or 0
end

-- The level the rotor of a charger of `kind` standing on level `z` turns on.
local function rotorLevel(kind, z)
    return z + Specs.wind.turbines[kind].rotorAbove
end

-- The share of its wind the rotor of a charger of `kind` at x, y, z loses to the other chargers
-- whose rotors turn on its level within Specs.wind.crowdRadius (Wind.crowding). They stand on that
-- level or the one below, as rotorAbove is 0 or 1. Only loaded ones count, as shelter does.
local function crowdingAt(kind, x, y, z)
    local radius, level = Specs.wind.crowdRadius, rotorLevel(kind, z)
    local distances = {}
    for floor = level - 1, level do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local distance = math.sqrt(dx * dx + dy * dy)
                local other = distance >= 1 and distance <= radius and Sources.findOn(getSquare(x + dx, y + dy, floor))
                local otherKind = other and Sources.kindOf(other)
                if otherKind and Sources.familyOf(otherKind) == "wind" and rotorLevel(otherKind, floor) == level then
                    table.insert(distances, distance)
                end
            end
        end
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

--- Fits blades of `material` (Specs.wind.blades), which its kind takes, to the wind charger
--- `isoObject`, and to `source`, its bank's record, if it feeds one (else nil). Blades of another
--- material than it turns make it that material's tile for its facing, and so that tile's entity
--- (RenewableEnergy.setEntityTile), on every side.
function WindSource.fitBlades(isoObject, material, source)
    if source then
        source.blades = material
    end
    if Wind.bladesOfObject(isoObject) == material then return end
    local kind, facing = Sources.kindOf(isoObject)
    local tile = Sprites.windTileOf(kind, facing, material)
    if not tile then return end
    RenewableEnergy.setEntityTile(isoObject, tile)
    isoObject:transmitUpdatedSpriteToClients()
    -- After the tile, as DigesterObject:upgrade sends it: a client's SpriteConfig checks its new
    -- script against the tile it shows. Single player has no other copy.
    if isServer() then
        isoObject:sendSyncEntity(nil)
    end
end

-- The blades of the charger `source` (a Specs.wind.blades material, nil for none): the record's,
-- else, for a record from before it kept them, the first its kind takes.
local function bladesOf(source)
    return source.blades or Wind.bladesOf(source.kind)
end

-- The chance that a wind charger left running through `hours` of a wind of `kph` breaks its
-- blades, at their stormShare and the wind's strength over their break speed on it
-- (Chance.stormStrength), scaled by the StormDamage options: none while braked or broken already.
local function breakChance(source, kph, hours)
    local spec, blades = Specs.wind.turbines[source.kind], bladesOf(source)
    if source.braked or source.broken or not Wind.canBreak(spec, blades, kph) then
        return 0
    end
    return Chance.stormDamage(Chance.stormPerHour(Specs.wind.blades[blades].stormShare),
        hours * Chance.stormStrength(Wind.breakKph(spec, blades), kph))
end

-- No roll when the blades can't break, so a test's set rolls go only to chances that can come up.
local function breaks(source, kph, hours)
    local chance = breakChance(source, kph, hours)
    return chance > 0 and Chance.hit(chance)
end

--- A newly connected wind charger's record: its brake, blades and broken blades as the object has
--- them, and its shelter. A charger teaches its wiring the first time a player connects it; the
--- world wires a site's charger with no player (SolarSites), which leaves the lesson to the one who
--- rewires it.
function WindSource.connect(player, source, isoObject, _, material)
    source.braked = Wind.isBraked(isoObject)
    source.broken = Wind.isBroken(isoObject)
    source.blades = Wind.bladesOf(source.kind, material)
    source.shelter = shelterAt(Specs.wind.turbines[source.kind], source.x, source.y, source.z)
    source.crowding = crowdingAt(source.kind, source.x, source.y, source.z)
    if player and RenewableEnergy.teachOnce(player, isoObject, PowerBank.CONNECTED_ONCE_KEY, Perks.Electricity,
        Specs.connectXp * Sources.slotsOf(source.kind)) then
        isoObject:transmitModData()
    end
end

--- The charger's output over the pass, and why it makes nothing or little: in a gale that can
--- break its blades, braked, broken, calm, furled, sheltered or crowded. Its brake and blades are
--- the object's while it is loaded (setBraked sets both); its broken blades are the record's, which
--- a gale may break while the object is unloaded, and go to the object when it is loaded. Its
--- shelter and crowding are counted again then, since trees, buildings, walls and chargers around
--- it change. Blades breaking tell the players in earshot (StormNotice).
function WindSource.update(source, object, inSlot, hours, context)
    local spec = Specs.wind.turbines[source.kind]
    if object then
        source.braked = Wind.isBraked(object)
        source.blades = Wind.bladesOfObject(object)
        source.shelter = shelterAt(spec, source.x, source.y, source.z)
        source.crowding = crowdingAt(source.kind, source.x, source.y, source.z)
    end
    if breaks(source, context.windKph, hours) then
        source.broken = true
        StormNotice.tell(bladesOf(source), source.x, source.y, source.z)
    end
    if object and Wind.isBroken(object) ~= (source.broken == true) then
        WindSource.setBroken(object, source.broken == true, source)
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
    elseif (source.shelter or 0) * Specs.wind.shelterLoss > SHELTERED_LOSS then
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
