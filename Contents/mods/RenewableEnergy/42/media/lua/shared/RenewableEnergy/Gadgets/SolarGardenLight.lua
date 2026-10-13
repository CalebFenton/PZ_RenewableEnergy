require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"

-- The Solar Garden Light: a cell on a stake that charges its little battery by day, and at
-- night lights its bulb for as long as the charge lasts.
--
-- The authority (single player or the server) keeps each light's charge and bulb in its modData
-- and swaps its tile between unlit and lit. Light sources exist only where the game draws, so
-- every client, and single player, gives each lit tile it sees a lamp of its own, in its bulb's
-- colour. A server tells its clients when a light's lamp changes, so they draw it at once.
RenewableEnergy = RenewableEnergy or {}
local SolarGardenLight = {}
RenewableEnergy.SolarGardenLight = SolarGardenLight

local Sprites = RenewableEnergy.Sprites

SolarGardenLight.ITEM = "RenewableEnergy.SolarGardenLight"
-- Object modData: watt-hours in the light's battery. Picking the light up carries it along
-- (Moveables.lua).
SolarGardenLight.CHARGE_KEY = "RenewableEnergy_chargeWh"
-- Object and item modData: the full type of the bulb in the light. Unset means the plain bulb
-- every light comes with, so the lights in saves from before the mod had bulbs, and every one
-- spawned since, hold one without being touched. Picking the light up carries it along too.
SolarGardenLight.BULB_KEY = "RenewableEnergy_bulb"
SolarGardenLight.PLAIN_BULB = "Base.LightBulb"
-- BULB_KEY of a light whose bulb was taken out.
SolarGardenLight.NO_BULB = "none"

-- Vanilla's bulbs, the plain one and the coloured ones, whose scripts give their colour.
SolarGardenLight.BULBS = {}
for _, colour in ipairs({ "", "Red", "Green", "Blue", "Yellow", "Cyan", "Magenta", "Orange", "Pink", "Purple" }) do
    SolarGardenLight.BULBS["Base.LightBulb" .. colour] = true
end

-- The plain bulb's warm white, like the incandescent bulb of a 1993 garden light. Its script
-- gives no colour, which is white.
local LAMP_COLOR = { r = 1.0, g = 0.8, b = 0.55 }
-- MapObjects keeps one function per sprite and priority.
local LOAD_PRIORITY = 7
-- The server's word to its clients that a light's lamp changed: the tile and the bulb's modData
-- reach them on their own, and a client would otherwise only catch up at its next game minute.
local COMMAND_MODULE, LAMP_COMMAND = "RenewableEnergyGardenLight", "lamp"

-- The places of the lights this side has seen: the authority charges them, the drawing side
-- lights them.
local places = {}
-- Drawing side: the lamp lit at each place, by place key, as { source, bulb }.
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
    return RenewableEnergy.findObjectOn(square, SolarGardenLight.isLight)
end

function SolarGardenLight.getCharge(light)
    return light:getModData()[SolarGardenLight.CHARGE_KEY] or 0
end

function SolarGardenLight.isBulb(item)
    return item ~= nil and SolarGardenLight.BULBS[item:getFullType()] == true
end

--- The full type of the bulb in `holder`, a placed light or its item, or nil if it has none.
function SolarGardenLight.getBulb(holder)
    local bulb = holder:getModData()[SolarGardenLight.BULB_KEY]
    if bulb == nil then
        return SolarGardenLight.PLAIN_BULB
    end
    return bulb ~= SolarGardenLight.NO_BULB and bulb or nil
end

-- The colour the lamp of `bulb` is given. The native lighting doubles a lamp's colour and clips
-- it at 1 (LightingJNI.checkLights), so given its bulb's own colour a lamp washes out toward
-- white: the warm plain bulb would shine pure white. It gets half of it instead.
local function lampColor(bulb)
    if bulb == SolarGardenLight.PLAIN_BULB then
        return LAMP_COLOR.r / 2, LAMP_COLOR.g / 2, LAMP_COLOR.b / 2
    end
    local script = getScriptManager():FindItem(bulb)
    return script:getColorRed() / 2, script:getColorGreen() / 2, script:getColorBlue() / 2
end

-- Drawing side -----------------------------------------------------------------------------------

local function removeLamp(key)
    local lamp = lamps[key]
    if lamp then
        -- By object, as vanilla's lamps do: the cell drops it on its next lighting pass. By place
        -- it would clear its light at once, which the native lighting refuses.
        getCell():removeLamppost(lamp.source)
        lamps[key] = nil
    end
end

-- Gives the place x, y, z a lamp in the colour of `bulb`, or none if `bulb` is nil.
local function drawLamp(x, y, z, bulb)
    local key = placeKey(x, y, z)
    if not bulb then
        removeLamp(key)
        return
    end
    local lamp = lamps[key]
    -- The cell drops the lamps of a chunk that unloads, so a lamp is looked for again.
    if lamp and getCell():getLightSourceAt(x, y, z) == lamp.source then
        if lamp.bulb ~= bulb then
            -- Another bulb went in while the light stayed lit. The lamp takes its colour, as a
            -- vanilla lamp does when its bulb changes (IsoLightSwitch.setPrimaryR), and the next
            -- lighting pass hands it to the native lighting.
            local r, g, b = lampColor(bulb)
            lamp.source:setR(r)
            lamp.source:setG(g)
            lamp.source:setB(b)
            lamp.bulb = bulb
        end
        return
    end
    local r, g, b = lampColor(bulb)
    lamps[key] = { source = getCell():addLamppost(x, y, z, r, g, b, RenewableEnergy.Specs.gardenLight.radius), bulb = bulb }
end

-- The bulb a light's lamp shines with, or nil if it has no lamp.
local function lampBulb(light)
    return SolarGardenLight.isLit(light) and SolarGardenLight.getBulb(light) or nil
end

--- Gives a lit light a lamp in its bulb's colour and takes an unlit one's away. Not on a
--- dedicated server, which draws nothing.
function SolarGardenLight.syncLamp(light)
    if isServer() then
        return
    end
    -- A client can get the bulb's removal before the unlit tile that follows it, hence the bulb
    -- and the tile both.
    drawLamp(light:getX(), light:getY(), light:getZ(), lampBulb(light))
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

-- Swaps the tile to lit or unlit and gives the light the lamp that goes with it here and, on a
-- server, on every client, when the tile or the bulb (`bulbChanged`) changed.
local function setLit(light, lit, bulbChanged)
    local changed = SolarGardenLight.isLit(light) ~= lit
    if changed then
        -- The tile's own sprite, with its properties; setSprite(name) would make a bare texture.
        light:setSprite(getSprite(lit and Sprites.gardenLight.lit or Sprites.gardenLight.off))
        if isServer() then
            light:transmitUpdatedSpriteToClients()
        end
    end
    -- Also when the tile stays lit, since its bulb may have changed.
    SolarGardenLight.syncLamp(light)
    if isServer() and (changed or bulbChanged) then
        sendServerCommand(COMMAND_MODULE, LAMP_COMMAND,
            { x = light:getX(), y = light:getY(), z = light:getZ(), bulb = lampBulb(light) })
    end
end

--- Runs a light for `hours` at the sun of the moment: by day its cell charges the battery, and
--- after sunset its bulb draws on it until it is empty. A light without a bulb draws nothing.
--- `bulbChanged` says its bulb has just changed, so that its lamp's colour reaches the clients
--- even if it stays lit. Authority only. Returns whether the light is lit.
function SolarGardenLight.update(light, hours, bulbChanged)
    local spec = RenewableEnergy.Specs.gardenLight
    local night = RenewableEnergy.Sun.elevation() <= 0
    local bulb = SolarGardenLight.getBulb(light) ~= nil
    local charge = SolarGardenLight.getCharge(light)
    if not night then
        charge = math.min(spec.wh, charge + RenewableEnergy.Sun.squareWatts(light:getSquare(), spec.watts) * hours)
    elseif bulb then
        charge = math.max(0, charge - spec.nightWatts * hours)
    end
    light:getModData()[SolarGardenLight.CHARGE_KEY] = charge
    local lit = night and bulb and charge > 0
    setLit(light, lit, bulbChanged)
    return lit
end

-- Puts `bulb` (nil for none) in the light, tells the clients, and lights or darkens it at once.
local function setBulb(light, bulb)
    light:getModData()[SolarGardenLight.BULB_KEY] = bulb or SolarGardenLight.NO_BULB
    light:transmitModData()
    SolarGardenLight.update(light, 0, true)
end

--- Takes the bulb out of `light` and gives it to `character`. Authority only, from a timed
--- action's complete(). Returns whether it did.
function SolarGardenLight.removeBulb(character, light)
    local bulb = SolarGardenLight.getBulb(light)
    if not bulb then
        return false
    end
    setBulb(light, nil)
    Actions.addOrDropItem(character, instanceItem(bulb))
    return true
end

--- Takes the bulb `item` from `character` and puts it in `light`, which has none. Authority only,
--- from a timed action's complete(). Returns whether it did.
function SolarGardenLight.addBulb(character, light, item)
    if SolarGardenLight.getBulb(light) or not SolarGardenLight.isBulb(item) then
        return false
    end
    character:removeFromHands(item)
    local container = item:getContainer()
    if container then
        container:Remove(item)
        sendRemoveItemFromContainer(container, item)
    end
    setBulb(light, item:getFullType())
    return true
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
-- A multiplayer client also draws what its server says a lamp became, at once, before the tile
-- and the bulb's modData may have reached its copy of the light.
if not isServer() then
    Events.EveryOneMinute.Add(function()
        forEachLight(SolarGardenLight.syncLamp)
    end)
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= COMMAND_MODULE or command ~= LAMP_COMMAND then
            return
        end
        local square = getCell():getGridSquare(args.x, args.y, args.z)
        if SolarGardenLight.findOn(square) then
            places[placeKey(args.x, args.y, args.z)] = { x = args.x, y = args.y, z = args.z }
            drawLamp(args.x, args.y, args.z, args.bulb)
        end
    end)
end

return SolarGardenLight
