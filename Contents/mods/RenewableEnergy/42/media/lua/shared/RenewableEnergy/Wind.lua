-- Wind chargers: output from the game's wind (ClimateManager.getWindspeedKph, no day/night cycle),
-- the power curve, height and shelter; plus the brake and broken-blade modData, written only on
-- the authority (WindSource).

local Sprites = require "RenewableEnergy/Sprites"
local Items = require "cf_commonlib/Items"
local Tiles = require "cf_commonlib/Tiles"

local Wind = {}
-- Entities.txt names its OnCreate by Lua path.
RenewableEnergy = RenewableEnergy or {}
RenewableEnergy.Wind = Wind

-- Wind chargers by kind: watts at ratedKph, starting at cutInKph, and the input slots each takes in
-- a bank. Game wind is ClimateManager's windPower × 120 km/h. The generator alone sets the power:
-- `blades` lists the blade materials (Wind.SPEC.blades) it takes, the first for a charger whose
-- sprite names none, and they decide only when it breaks. rotorAbove is how many levels above its
-- own the rotor turns (each mast charger's hub is a storey and a half up, art/models/wind.py), where
-- its shelter is counted. A turbine with furlKph swings its tail-hinged head out of strong wind and
-- holds furledShare of its rating, as a furling tail governs the rotor near its rated speed; turned
-- aside, its blades take less of the gale and break only furledBladeKph above their break speed.
-- propeller is the treadmill wind charger, alternator the homebuilt wind turbine (their names in
-- saved records and tiles from before they were renamed).
Wind.SPEC = {
    turbines = {
        scoop = { slots = 1, watts = 480, cutInKph = 8, ratedKph = 50, rotorAbove = 0 },
        propeller = { slots = 2, watts = 1600, cutInKph = 10, ratedKph = 40, rotorAbove = 1,
            blades = { "wood", "pipe", "steel" } },
        carAlternator = { slots = 2, watts = 2000, cutInKph = 10, ratedKph = 40, rotorAbove = 1,
            blades = { "wood", "pipe", "steel" } },
        alternator = { slots = 3, watts = 3200, cutInKph = 9, ratedKph = 40, rotorAbove = 1,
            furlKph = 55, furledShare = 0.85, furledBladeKph = 20, blades = { "steel", "wood", "pipe" } },
    },
    -- Blades by material: the item that makes and mends them, and the `broken` item a mend hands
    -- back; the wind above which unbraked they can break (Specs.storm), and their stormShare of the
    -- weakest blades' chance; the sound they make straining in that wind and breaking. Plastic pipe
    -- goes brittle and snaps first, carved wood flexes, and forged steel holds through all but the worst.
    blades = {
        pipe = { item = "RenewableEnergy.PipeBlades", broken = "RenewableEnergy.BrokenPipeBlades", breakKph = 60,
            stormShare = 1, strainSound = "WindowRattle", breakSound = "BreakObject" },
        wood = { item = "RenewableEnergy.WoodenBlades", broken = "RenewableEnergy.BrokenWoodenBlades", breakKph = 70,
            stormShare = 0.5, strainSound = "WoodDoorCreak", breakSound = "BreakBarricadePlank" },
        steel = { item = "RenewableEnergy.SteelBlades", broken = "RenewableEnergy.BrokenSteelBlades", breakKph = 90,
            stormShare = 0.25, strainSound = "WindowRattle", breakSound = "BreakBarricadeMetal" },
    },
    -- Share added per level above ground, capped at maxBonusLevel.
    heightBonusPerLevel = 0.15,
    maxBonusLevel = 3,
    -- Squares checked for shelter, and the share lost when fully hemmed in. Trees shelter a rotor
    -- turning on treetopLevel or lower: a mast charger standing on the ground or a first floor. A
    -- charger losing more than shelteredShare of its watts to shelter says so in its status.
    shelterRadius = 8,
    shelterLoss = 0.7,
    treetopLevel = 2,
    shelteredShare = 0.3,
    -- Another charger whose rotor turns on the same level within crowdRadius squares takes wind
    -- from this one, crowdLoss of it right beside it and less with each square further, none
    -- beyond: a rotor's wake takes a few rotor widths to fill back in, and these rotors are about
    -- two squares across (art/models/wind.py blade lengths). Each such neighbour takes its share
    -- of what the others leave. Not shelter: a mast and a turning rotor stop far less wind than a wall.
    crowdRadius = 3,
    crowdLoss = 0.25,
}
local SPEC = Wind.SPEC

-- Placed wind charger modData: its brake is on; its blades are broken.
Wind.BRAKED_KEY = "RenewableEnergy_braked"
Wind.BROKEN_KEY = "RenewableEnergy_bladesBroken"

-- A wind charger's kind is its tile's (Sprites.kindOf); every wind kind is a source as placed, so
-- this needs nothing of Sources, which reads SPEC.
local function chargerKind(isoObject)
    local kind, facing, material = Sprites.kindOfObject(isoObject)
    if kind and SPEC.turbines[kind] then
        return kind, facing, material
    end
    return nil
end

--- Whether `isoObject` is a placed wind charger.
function Wind.isCharger(isoObject)
    return chargerKind(isoObject) ~= nil
end

function Wind.isBraked(isoObject)
    return isoObject:getModData()[Wind.BRAKED_KEY] == true
end

function Wind.isBroken(isoObject)
    return isoObject:getModData()[Wind.BROKEN_KEY] == true
end

--- The blades (a Wind.SPEC.blades material) a wind charger of `kind` built of `material` (its
--- sprite's, Sprites.kindOf) turns: `material` if its kind takes those, else the first its kind
--- takes; nil for a kind without blades that break.
function Wind.bladesOf(kind, material)
    local spec = SPEC.turbines[kind]
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

--- The blades (a Wind.SPEC.blades material) of the placed wind charger `isoObject`, or nil.
function Wind.bladesOfObject(isoObject)
    local kind, _, material = chargerKind(isoObject)
    return Wind.bladesOf(kind, material)
end

--- The blades (a Wind.SPEC.blades material) the item `item` (nil for none) is, if a wind charger
--- of `kind` takes them; else nil.
function Wind.bladesOfItem(kind, item)
    local spec = SPEC.turbines[kind]
    if not (item and spec and spec.blades) then
        return nil
    end
    local fullType = item:getFullType()
    for _, material in ipairs(spec.blades) do
        if SPEC.blades[material].item == fullType then
            return material
        end
    end
    return nil
end

--- Whether a turbine of `spec` has turned its head out of a wind of `kph` (Wind.SPEC.turbines furlKph).
function Wind.furled(spec, kph)
    return spec.furlKph ~= nil and kph >= spec.furlKph
end

--- The watts a turbine of `spec` (Wind.SPEC.turbines) makes in a wind of `kph`, standing on level
--- `z` with `shelter` (0 open .. 1 walled in) around it and `crowding` (the share other chargers
--- take, Wind.crowding; nil for none): zero below cut-in, rising with the cube of the speed to its
--- rating at rated speed and flat above; furled, its furled share.
function Wind.watts(spec, kph, z, shelter, crowding)
    local wind = SPEC
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
--- squares away: Wind.SPEC.crowdLoss beside it, falling by a step each square out to none past
--- crowdRadius.
function Wind.crowdShare(distance)
    local wind = SPEC
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

--- The wind above which `blades` (a Wind.SPEC.blades material) left running on a turbine of
--- `spec` can break, or nil for none: their break speed, and furledBladeKph more on a turbine whose
--- tail swings it out of the gale before then.
function Wind.breakKph(spec, blades)
    local material = blades and SPEC.blades[blades]
    if not material then
        return nil
    end
    return material.breakKph + (spec.furlKph and spec.furledBladeKph or 0)
end

--- Whether a wind of `kph` can break `blades` (a Wind.SPEC.blades material, nil for none) left
--- running on a turbine of `spec`: above their break speed on it, where their chance starts
--- (Chance.stormStrength).
function Wind.canBreak(spec, blades, kph)
    local breakKph = Wind.breakKph(spec, blades)
    return breakKph ~= nil and kph > breakKph
end

--- Makes the wind charger `isoObject` the tile, and so the entity (Tiles.setEntityTile), of its
--- kind and facing with `material` blades (a Wind.SPEC.blades material). Returns whether its tile
--- changed; the caller sends it on, if anything need be sent.
function Wind.setBladesTile(isoObject, material)
    local kind, facing = chargerKind(isoObject)
    local tile = Sprites.windTileOf(kind, facing, material)
    if not tile or tile == isoObject:getSprite():getName() then
        return false
    end
    Tiles.setEntityTile(isoObject, tile)
    return true
end

-- One recipe builds each bladed kind with any blades it takes, always on its wood tile: this makes
-- the charger the tile of the blades the build took. Nothing is sent here: ISBuildIsoEntity sends
-- the object on after OnCreate. A charger the world builds (RuralFinds) has no recipe data and
-- keeps the tile it was given.
local function fitBuiltBlades(thumpable, data)
    local kind = chargerKind(thumpable)
    local blades = Items.firstConsumed(data, function(item)
        return Wind.bladesOfItem(kind, item) ~= nil
    end)
    if blades then
        Wind.setBladesTile(thumpable, Wind.bladesOfItem(kind, blades))
    end
end

--- The build menu's OnCreate for every wind charger, on the authority: fits the blades the build
--- took (fitBuiltBlades). Single player fires no OnObjectAdded for a built object, so this fires
--- it, as vanilla's TrapBO does, letting WindSpin start it turning. MP clients get
--- it from the server's AddItemToMapPacket.
function Wind.OnCreate(params)
    local thumpable = params.thumpable
    if thumpable then
        fitBuiltBlades(thumpable, params.craftRecipeData)
        triggerEvent("OnObjectAdded", thumpable)
    end
end

return Wind
