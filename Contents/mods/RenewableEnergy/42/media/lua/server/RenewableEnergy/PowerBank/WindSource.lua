-- How a bank runs a wind charger (the "wind" family of RenewableEnergy.Sources) on the authority:
-- its output in the wind and its blades breaking in a gale. Sets a charger's brake and broken
-- blades on the object and on its bank's record alike.

if isClient() then return end

require "RenewableEnergy/Chance"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Wind"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Sources"

RenewableEnergy = RenewableEnergy or {}
local Chance, Specs, Wind = RenewableEnergy.Chance, RenewableEnergy.Specs, RenewableEnergy.Wind
local PowerBank, Sources = RenewableEnergy.PowerBank, RenewableEnergy.Sources

local WindSource = {}
RenewableEnergy.WindSource = WindSource

-- A charger losing more than this share of its watts to shelter says so in the status.
local SHELTERED_LOSS = 0.3

-- Whether the column at (x, y) shelters a turbine on level `z`: a tree near the ground, a building
-- at least as tall, or a solid wall on the turbine's level, the map's or one a player built. See-through
-- walls (windows, wire fences) and low fences let the wind through.
local function blocks(x, y, z)
    local ground = getSquare(x, y, 0)
    if not ground then
        return 0
    end
    if z <= 1 and ground:HasTree() then
        return 1
    end
    local building = ground:getBuilding()
    if building and building:getDef() and building:getDef():getMaxLevel() >= z then
        return 1
    end
    local square = z == 0 and ground or getSquare(x, y, z)
    local properties = square and square:getProperties()
    if properties and (properties:has(IsoFlagType.WallN) or properties:has(IsoFlagType.WallW)
            or properties:has(IsoFlagType.WallNW)) then
        return 1
    end
    return 0
end

-- The share of the ring of squares around (x, y) on the ground, out to Specs.wind.shelterRadius,
-- that shelters a turbine on level `z`: 0 in the open, 1 hemmed in. Shelter has no direction: the
-- game's wind angle is a screen-space value for weather effects (ClimateManager.getWindAngleDegrees),
-- so every side counts.
local function shelterAt(x, y, z)
    local radius = Specs.wind.shelterRadius
    local blocked, count = 0, 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance >= 1 and distance <= radius then
                -- Nearer obstacles count for more.
                local weight = 1 - (distance - 1) / radius
                blocked = blocked + weight * blocks(x + dx, y + dy, z)
                count = count + weight
            end
        end
    end
    return count > 0 and blocked / count or 0
end

local function setFlag(isoObject, key, on)
    isoObject:getModData()[key] = on or nil
    isoObject:transmitModData()
end

--- Sets the brake of the wind charger `isoObject`, and of `source`, its bank's record, if it feeds
--- one (else nil).
function WindSource.setBraked(isoObject, braked, source)
    setFlag(isoObject, Wind.BRAKED, braked)
    if source then
        source.braked = braked
    end
end

--- Marks the blades of the wind charger `isoObject` broken or whole, and of `source`, its bank's
--- record, if it feeds one (else nil).
function WindSource.setBroken(isoObject, broken, source)
    setFlag(isoObject, Wind.BROKEN, broken)
    if source then
        source.broken = broken
    end
end

-- The chance that a wind charger left running through `hours` of a wind of `kph` breaks its
-- blades, at its kind's chance (Specs.wind.turbines breakPerHour) scaled by the StormDamage
-- options: none while braked or broken already.
local function breakChance(source, kph, hours)
    local spec = Specs.wind.turbines[source.kind]
    if source.braked or source.broken or not Wind.canBreak(spec, kph) then
        return 0
    end
    return Chance.stormDamage(spec.breakPerHour, hours)
end

-- No roll when the blades can't break, so a test's set rolls go only to chances that can come up.
local function breaks(source, kph, hours)
    local chance = breakChance(source, kph, hours)
    return chance > 0 and Chance.hit(chance)
end

--- A newly connected wind charger's record: its brake and blades as the object has them, and its
--- shelter. A charger teaches its wiring the first time a player connects it; the world wires a
--- site's charger with no player (SolarSites), which leaves the lesson to the one who rewires it.
function WindSource.connect(player, source, isoObject)
    source.braked = Wind.isBraked(isoObject)
    source.broken = Wind.isBroken(isoObject)
    source.shelter = shelterAt(source.x, source.y, source.z)
    if player and RenewableEnergy.teachOnce(player, isoObject, PowerBank.CONNECTED_ONCE, Perks.Electricity,
        Specs.connectXp * Sources.slotsOf(source.kind)) then
        isoObject:transmitModData()
    end
end

--- The charger's output over the pass, and why it makes nothing or little: braked, broken, calm,
--- furled or sheltered. Its brake is the object's while it is loaded (setBraked sets both); its
--- broken blades are the record's, which a gale may break while the object is unloaded, and go to
--- the object when it is loaded. Its shelter is counted again then, since trees, buildings and
--- walls around it change.
function WindSource.update(source, object, inSlot, hours, context)
    if object then
        source.braked = Wind.isBraked(object)
        source.shelter = shelterAt(source.x, source.y, source.z)
    end
    if breaks(source, context.windKph, hours) then
        source.broken = true
    end
    if object and Wind.isBroken(object) ~= (source.broken == true) then
        WindSource.setBroken(object, source.broken == true, source)
    end
    local spec = Specs.wind.turbines[source.kind]
    local watts = Wind.watts(spec, context.windKph, source.z, source.shelter or 0)
    source.watts = (inSlot and not source.braked and not source.broken) and watts or 0
    if not inSlot then
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
    else
        source.reason = nil
    end
end

--- The charger's part of its status entry: its brake, blades and shelter.
function WindSource.status(entry, source)
    entry.braked, entry.broken = source.braked == true, source.broken == true
    entry.shelterPct = round(100 * (source.shelter or 0))
end

return WindSource
