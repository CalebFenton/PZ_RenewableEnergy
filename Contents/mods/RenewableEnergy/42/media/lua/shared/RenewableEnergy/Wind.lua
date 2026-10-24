-- Wind chargers: output from the game's wind (ClimateManager.getWindspeedKph, no day/night cycle),
-- the power curve, height and shelter; plus the brake and broken-blade modData, written only on
-- the authority (RenewableEnergy.WindSource).

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

--- The blades (a Specs.wind.blades material) a wind charger of `kind` built of `material` (its
--- sprite's, Sprites.kindOf) turns: `material` if its kind takes those, else the first its kind
--- takes; nil for a kind without blades that break.
function Wind.bladesOf(kind, material)
    local spec = Specs.wind.turbines[kind]
    local blades = spec and spec.blades
    if not blades then
        return nil
    end
    for _, each in ipairs(blades) do
        if each == material then
            return material
        end
    end
    return blades[1]
end

--- The blades (a Specs.wind.blades material) of the placed wind charger `isoObject`, or nil.
function Wind.bladesOfObject(isoObject)
    local kind, _, material = Sources.kindOf(isoObject)
    return Wind.bladesOf(kind, material)
end

--- The blades (a Specs.wind.blades material) the item `item` (nil for none) is, if a wind charger
--- of `kind` takes them; else nil.
function Wind.bladesOfItem(kind, item)
    local spec = Specs.wind.turbines[kind]
    if not (item and spec and spec.blades) then
        return nil
    end
    local fullType = item:getFullType()
    for _, material in ipairs(spec.blades) do
        if Specs.wind.blades[material].item == fullType then
            return material
        end
    end
    return nil
end

--- Why the blades `item` can't go on the wind charger `isoObject` now, or nil if they can: "not
--- broken" while its blades are whole, "no blades" when `item` (nil for none) isn't blades its
--- kind takes (Specs.wind.turbines blades). Blades of another material it takes swap it to them.
function Wind.bladesRefusal(isoObject, item)
    if not Wind.isBroken(isoObject) then
        return "not broken"
    end
    if not Wind.bladesOfItem(Sources.kindOf(isoObject), item) then
        return "no blades"
    end
    return nil
end

--- Whether a turbine of `spec` has turned its head out of a wind of `kph` (Specs.wind.turbines furlKph).
function Wind.furled(spec, kph)
    return spec.furlKph ~= nil and kph >= spec.furlKph
end

--- The watts a turbine of `spec` (Specs.wind.turbines) makes in a wind of `kph`, standing on level
--- `z` with `shelter` (0 open .. 1 walled in) around it and `crowding` (the share other chargers
--- take, Wind.crowding; nil for none): zero below cut-in, rising with the cube of the speed to its
--- rating at rated speed and flat above; furled, its furled share.
function Wind.watts(spec, kph, z, shelter, crowding)
    local wind = Specs.wind
    if kph <= spec.cutInKph then
        return 0
    end
    local share = math.min(1, (kph - spec.cutInKph) / (spec.ratedKph - spec.cutInKph)) ^ 3
    if Wind.furled(spec, kph) then
        share = spec.furledShare
    end
    local height = 1 + wind.heightBonusPerLevel * math.min(math.max(z, 0), wind.maxBonusLevel)
    return spec.watts * share * height * (1 - wind.shelterLoss * shelter) * (1 - (crowding or 0))
end

--- The share of its wind a charger loses to another whose rotor turns on its level `distance`
--- squares away: Specs.wind.crowdLoss beside it, falling by a step each square out to none past
--- crowdRadius.
function Wind.crowdShare(distance)
    local wind = Specs.wind
    if distance > wind.crowdRadius then
        return 0
    end
    return wind.crowdLoss * (wind.crowdRadius + 1 - math.max(distance, 1)) / wind.crowdRadius
end

--- The share of its wind a charger loses to neighbours at `distances` (a list of squares away):
--- each takes its share of what the nearer ones left.
function Wind.crowding(distances)
    local left = 1
    for _, distance in ipairs(distances) do
        left = left * (1 - Wind.crowdShare(distance))
    end
    return 1 - left
end

--- The wind above which `blades` (a Specs.wind.blades material) left running on a turbine of
--- `spec` can break, or nil for none: their break speed, and furledBladeKph more on a turbine whose
--- tail swings it out of the gale before then.
function Wind.breakKph(spec, blades)
    local material = blades and Specs.wind.blades[blades]
    if not material then
        return nil
    end
    return material.breakKph + (spec.furlKph and spec.furledBladeKph or 0)
end

--- Whether a wind of `kph` can break `blades` (a Specs.wind.blades material, nil for none) left
--- running on a turbine of `spec`: above their break speed on it, where their chance starts
--- (Chance.stormStrength).
function Wind.canBreak(spec, blades, kph)
    local breakKph = Wind.breakKph(spec, blades)
    return breakKph ~= nil and kph > breakKph
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
