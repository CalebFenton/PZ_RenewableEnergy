-- Wind chargers: output from the game's wind (ClimateManager.getWindspeedKph, no day/night cycle),
-- the power curve, height and shelter; plus the brake and broken-blade modData, which only the
-- authority's RenewableEnergy.WindSource writes.
--
-- Shelter has no direction: the game's wind angle is a screen-space value for weather effects
-- (ClimateManager.getWindAngleDegrees), so every side counts.

require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/Sources"

RenewableEnergy = RenewableEnergy or {}
local Wind = {}
RenewableEnergy.Wind = Wind

local Specs, Sources = RenewableEnergy.Specs, RenewableEnergy.Sources

-- Placed wind charger modData: its brake is on; its blades are broken.
Wind.BRAKED = "RenewableEnergy_braked"
Wind.BROKEN = "RenewableEnergy_bladesBroken"

--- Whether `isoObject` is a placed wind charger.
function Wind.isCharger(isoObject)
    return Sources.familyOf(Sources.kindOf(isoObject)) == "wind"
end

function Wind.isBraked(isoObject)
    return isoObject:getModData()[Wind.BRAKED] == true
end

function Wind.isBroken(isoObject)
    return isoObject:getModData()[Wind.BROKEN] == true
end

--- Why the blades `item` can't go on the wind charger `isoObject` now, or nil if they can: "not
--- broken" while its blades are whole, "no blades" when `item` (nil for none) isn't blades that
--- fit it (Specs.wind.turbines blades).
function Wind.bladesRefusal(isoObject, item)
    if not Wind.isBroken(isoObject) then
        return "not broken"
    elseif not (item and Sources.bladesFor(Sources.kindOf(isoObject))[item:getFullType()]) then
        return "no blades"
    end
    return nil
end

--- Whether a turbine of `spec` has turned its head out of a wind of `kph` (Specs.wind.turbines furlKph).
function Wind.furled(spec, kph)
    return spec.furlKph ~= nil and kph >= spec.furlKph
end

--- The watts a turbine of `spec` (Specs.wind.turbines) makes in a wind of `kph`, standing on level
--- `z` with `shelter` (0 open .. 1 walled in) around it: zero below cut-in, rising with the cube of
--- the speed to its rating at rated speed and flat above; furled, its furled share.
function Wind.watts(spec, kph, z, shelter)
    local wind = Specs.wind
    if kph <= spec.cutInKph then
        return 0
    end
    local share = math.min(1, (kph - spec.cutInKph) / (spec.ratedKph - spec.cutInKph)) ^ 3
    if Wind.furled(spec, kph) then
        share = spec.furledShare
    end
    local height = 1 + wind.heightBonusPerLevel * math.min(math.max(z, 0), wind.maxBonusLevel)
    return spec.watts * share * height * (1 - wind.shelterLoss * shelter)
end

--- Whether wind of `kph` can break a turbine of `spec` left running (only specs with breakKph can).
function Wind.canBreak(spec, kph)
    return spec.breakKph ~= nil and kph >= spec.breakKph
end

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

--- The share of the ring of squares around (x, y) on the ground, out to Specs.wind.shelterRadius,
--- that shelters a turbine on level `z`: 0 in the open, 1 hemmed in.
function Wind.shelterAt(x, y, z)
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

--- The build menu's OnCreate for every wind charger, on the authority. Single player fires no
--- OnObjectAdded for a built object, so this fires it, as vanilla's TrapBO does, letting
--- RenewableEnergy.WindSpin start it turning. MP clients get it from the server's AddItemToMapPacket.
function Wind.OnCreate(params)
    if params.thumpable then
        triggerEvent("OnObjectAdded", params.thumpable)
    end
end

return Wind
