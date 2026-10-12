require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"

-- The Solar Garden Light: a cell on a stake that charges its little battery by day, and at
-- night lights a warm lamp for as long as the charge lasts.
--
-- The authority (single player or the server) keeps each light's charge in its modData and
-- swaps its tile between unlit and lit. Light sources exist only where the game draws, so every
-- client, and single player, gives each lit tile it sees a lamp of its own.
RenewableEnergy = RenewableEnergy or {}
local SolarGardenLight = {}
RenewableEnergy.SolarGardenLight = SolarGardenLight

local Sprites = RenewableEnergy.Sprites

SolarGardenLight.ITEM = "RenewableEnergy.SolarGardenLight"
-- Object modData: watt-hours in the light's battery. Picking the light up carries it along
-- (Moveables.lua).
SolarGardenLight.CHARGE_KEY = "RenewableEnergy_chargeWh"

-- A warm white, like the incandescent bulb of a 1993 garden light.
local LAMP_COLOR = { r = 1.0, g = 0.8, b = 0.55 }
-- MapObjects keeps one function per sprite and priority.
local LOAD_PRIORITY = 7

-- The places of the lights this side has seen: the authority charges them, the drawing side
-- lights them.
local places = {}
-- Drawing side: the lamp lit at each place, by place key.
local lamps = {}

local function placeKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

function SolarGardenLight.isLight(isoObject)
    return isoObject ~= nil and Sprites.kindOf(isoObject:getTextureName()) == "gardenLight"
end

function SolarGardenLight.isLit(isoObject)
    return isoObject:getTextureName() == Sprites.gardenLight.lit
end

--- Where a light may stand: on the ground outdoors, where the sun reaches it.
function SolarGardenLight.canPlaceOn(square)
    return square ~= nil and square:isOutside() and square:getZ() == 0
end

function SolarGardenLight.findOn(square)
    local objects = square and square:getObjects()
    for i = 0, objects and objects:size() - 1 or -1 do
        local object = objects:get(i)
        if SolarGardenLight.isLight(object) then
            return object
        end
    end
    return nil
end

function SolarGardenLight.getCharge(light)
    return light:getModData()[SolarGardenLight.CHARGE_KEY] or 0
end

-- Drawing side -----------------------------------------------------------------------------------

local function removeLamp(key)
    local lamp = lamps[key]
    if lamp then
        -- By object, as vanilla's lamps do: the cell drops it on its next lighting pass. By place
        -- it would clear its light at once, which the native lighting refuses.
        getCell():removeLamppost(lamp)
        lamps[key] = nil
    end
end

--- Gives a lit light its lamp and takes an unlit one's away. Not on a dedicated server, which
--- draws nothing.
function SolarGardenLight.syncLamp(light)
    if isServer() then
        return
    end
    local x, y, z = light:getX(), light:getY(), light:getZ()
    local key = placeKey(x, y, z)
    if not SolarGardenLight.isLit(light) then
        removeLamp(key)
        return
    end
    -- The cell drops the lamps of a chunk that unloads, so a lamp is looked for again.
    if lamps[key] and getCell():getLightSourceAt(x, y, z) == lamps[key] then
        return
    end
    local radius = RenewableEnergy.Specs.gardenLight.radius
    lamps[key] = getCell():addLamppost(x, y, z, LAMP_COLOR.r, LAMP_COLOR.g, LAMP_COLOR.b, radius)
end

-- Calls `fn` with every light this side has seen. A light whose square is unloaded, or that is
-- gone, is dropped with its lamp; MapObjects reports it again when its chunk loads.
local function forEachLight(fn)
    for key, place in pairs(places) do
        local light = SolarGardenLight.findOn(getCell():getGridSquare(place.x, place.y, place.z))
        if light then
            fn(light)
        else
            removeLamp(key)
            places[key] = nil
        end
    end
end

-- Authority --------------------------------------------------------------------------------------

local function setLit(light, lit)
    if SolarGardenLight.isLit(light) == lit then
        return
    end
    -- The tile's own sprite, with its properties; setSprite(name) would make a bare texture.
    light:setSprite(getSprite(lit and Sprites.gardenLight.lit or Sprites.gardenLight.off))
    if isServer() then
        light:transmitUpdatedSpriteToClients()
    end
    SolarGardenLight.syncLamp(light)
end

--- Runs a light for `hours` at the sun of the moment: by day its cell charges the battery, and
--- after sunset the lamp draws on it until it is empty. Authority only. Returns whether the
--- light is lit.
function SolarGardenLight.update(light, hours)
    local spec = RenewableEnergy.Specs.gardenLight
    local night = RenewableEnergy.Sun.elevation() <= 0
    local charge = SolarGardenLight.getCharge(light)
    if night then
        charge = math.max(0, charge - spec.nightWatts * hours)
    else
        charge = math.min(spec.wh, charge + RenewableEnergy.Sun.squareWatts(light:getSquare(), spec.watts) * hours)
    end
    light:getModData()[SolarGardenLight.CHARGE_KEY] = charge
    local lit = night and charge > 0
    setLit(light, lit)
    return lit
end

--- Runs every loaded light the authority has seen.
function SolarGardenLight.updateAll(hours)
    forEachLight(function(light)
        SolarGardenLight.update(light, hours)
    end)
end

-- Finding lights ---------------------------------------------------------------------------------

local function adopt(light)
    places[placeKey(light:getX(), light:getY(), light:getZ())] = { x = light:getX(), y = light:getY(), z = light:getZ() }
    SolarGardenLight.syncLamp(light)
end

MapObjects.OnLoadWithSprite({ Sprites.gardenLight.off, Sprites.gardenLight.lit }, adopt, LOAD_PRIORITY)

Events.OnObjectAdded.Add(function(isoObject)
    if SolarGardenLight.isLight(isoObject) then
        adopt(isoObject)
    end
end)

Events.OnObjectAboutToBeRemoved.Add(function(isoObject)
    if SolarGardenLight.isLight(isoObject) then
        removeLamp(placeKey(isoObject:getX(), isoObject:getY(), isoObject:getZ()))
    end
end)

-- The authority swaps the tile; the drawing side catches up with it, and with lights that went.
if not isServer() then
    Events.EveryOneMinute.Add(function()
        forEachLight(SolarGardenLight.syncLamp)
    end)
end

return SolarGardenLight
