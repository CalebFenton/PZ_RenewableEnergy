-- The Solar Garden Light: a cell on a stake that charges its little battery by day, and at
-- night lights its bulb for as long as the charge lasts.
--
-- The authority (single player or the server) keeps each light's charge and bulb in its modData
-- and swaps its tile between unlit and lit (server/RenewableEnergy/Gadgets/SolarGardenLightServer.lua).
-- Light sources exist only where the game draws, so every client, and single player, gives each
-- lit tile it sees a lamp of its own, in its bulb's colour (this file). A server tells its clients
-- when a light's lamp changes, so they draw it at once.

local RenewableEnergy = require "RenewableEnergy/Utilities"
local PlaceTracker = require "RenewableEnergy/PlaceTracker"
local Specs = require "RenewableEnergy/Specs"
local Sprites = require "RenewableEnergy/Sprites"
local Jobs = require "cf_commonlib/Jobs"
local Squares = require "cf_commonlib/Squares"

local SolarGardenLight = {}
RenewableEnergy.SolarGardenLight = SolarGardenLight

SolarGardenLight.ITEM = "RenewableEnergy.SolarGardenLight"
-- Object modData: watt-hours in the light's battery. Picking the light up carries it along
-- (Moveables.lua).
SolarGardenLight.CHARGE_KEY = "RenewableEnergy_chargeWh"
-- Object and item modData: the full type of the bulb in the light. Unset means the plain bulb
-- every light comes with, so a light saved or spawned without the key holds one. Picking the
-- light up carries it along too.
SolarGardenLight.BULB_KEY = "RenewableEnergy_bulb"
SolarGardenLight.PLAIN_BULB = "Base.LightBulb"
-- BULB_KEY of a light whose bulb was taken out.
SolarGardenLight.NO_BULB = "none"

-- Vanilla's bulbs, the plain one and the coloured ones, whose scripts give their colour.
local BULBS = {}
for _, colour in ipairs({ "", "Red", "Green", "Blue", "Yellow", "Cyan", "Magenta", "Orange", "Pink", "Purple" }) do
    BULBS[SolarGardenLight.PLAIN_BULB .. colour] = true
end

-- The server's word to its clients that a light's lamp changed, with { x, y, z, bulb }: the tile
-- and the bulb's modData reach them on their own, and a client would otherwise only catch up at
-- its next game minute.
SolarGardenLight.COMMAND_MODULE, SolarGardenLight.LAMP_COMMAND = "RenewableEnergyGardenLight", "lamp"

-- The plain bulb's warm white, like the incandescent bulb of a 1993 garden light. Its script
-- gives no colour, which is white.
local LAMP_COLOR = { r = 1.0, g = 0.8, b = 0.55 }

-- Drawing side: the lamp lit at each place, by place key.
local lamps = {}

function SolarGardenLight.isLight(isoObject)
    return Sprites.kindOfObject(isoObject) == "gardenLight"
end

function SolarGardenLight.isLit(isoObject)
    return Sprites.nameOf(isoObject) == Sprites.gardenLight.lit
end

--- Where a light may stand: on the ground outdoors, where the sun reaches it.
function SolarGardenLight.canPlaceOn(square)
    return square ~= nil and square:isOutside() and square:getZ() == 0
end

function SolarGardenLight.findOn(square)
    return Squares.findObjectOn(square, SolarGardenLight.isLight)
end

function SolarGardenLight.getChargeWh(light)
    return light:getModData()[SolarGardenLight.CHARGE_KEY] or 0
end

function SolarGardenLight.isBulb(item)
    return item ~= nil and BULBS[item:getFullType()] == true
end

--- The full type of the bulb in `holder`, a placed light or its item, or nil if it has none.
function SolarGardenLight.getBulb(holder)
    local bulb = holder:getModData()[SolarGardenLight.BULB_KEY]
    if bulb == nil then
        return SolarGardenLight.PLAIN_BULB
    end
    return bulb ~= SolarGardenLight.NO_BULB and bulb or nil
end

--- The bulb a light's lamp shines with, or nil if it has no lamp.
function SolarGardenLight.lampBulb(light)
    return SolarGardenLight.isLit(light) and SolarGardenLight.getBulb(light) or nil
end

SolarGardenLight.REMOVE_BULB = "RemoveBulb"
SolarGardenLight.ADD_BULB = "AddBulb"

-- The jobs at a light, by name (cf_commonlib's Jobs), each as long as vanilla's for a lamp's bulb
-- at the default day length (ISLightActions), and named as vanilla names them; `with` is the bulb
-- Add Light Bulb puts in. SolarGardenLightServer does them.
SolarGardenLight.JOBS = {
    [SolarGardenLight.REMOVE_BULB] = {
        minutes = 1, label = "ContextMenu_RemoveLightbulb",
        blocker = function(character, light) return not SolarGardenLight.getBulb(light) and "no bulb" or nil end,
    },
    [SolarGardenLight.ADD_BULB] = {
        minutes = 1, label = "ContextMenu_AddLightbulb",
        blocker = function(character, light) return SolarGardenLight.getBulb(light) and "has a bulb" or nil end,
        with = SolarGardenLight.isBulb, withMissing = "ContextMenu_AddLightbulb_RequiresBulb",
    },
}

Jobs.define(SolarGardenLight, {
    subjectOf = function(light) return SolarGardenLight.isLight(light) and light or nil end, missing = "no light",
})

-- Drawing side

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
    local key = PlaceTracker.key(x, y, z)
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
    lamps[key] = { source = getCell():addLamppost(x, y, z, r, g, b, Specs.gardenLight.radius), bulb = bulb }
end

--- Gives a lit light a lamp in its bulb's colour and takes an unlit one's away. Not on a
--- dedicated server, which draws nothing.
function SolarGardenLight.syncLamp(light)
    if isServer() then
        return
    end
    -- A client can get the bulb's removal before the unlit tile that follows it, hence the bulb
    -- and the tile both.
    drawLamp(light:getX(), light:getY(), light:getZ(), SolarGardenLight.lampBulb(light))
end

-- The lights this side has seen: the authority runs them, the drawing side lights them. A light
-- that goes takes its lamp with it.
local lights = PlaceTracker.new({
    sprites = { Sprites.gardenLight.off, Sprites.gardenLight.lit },
    matches = SolarGardenLight.isLight,
    onFound = SolarGardenLight.syncLamp,
    onLost = removeLamp,
})

--- Calls `fn(light)` for every loaded light this side has seen.
function SolarGardenLight.eachLoaded(fn)
    lights:each(fn)
end

-- The authority swaps the tile; the drawing side catches up with it, and with lights that went.
-- A multiplayer client also draws what its server says a lamp became, at once, before the tile
-- and the bulb's modData may have reached its copy of the light.
if not isServer() then
    Events.EveryOneMinute.Add(function()
        lights:each(SolarGardenLight.syncLamp)
    end)
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= SolarGardenLight.COMMAND_MODULE or command ~= SolarGardenLight.LAMP_COMMAND then
            return
        end
        local square = getCell():getGridSquare(args.x, args.y, args.z)
        local light = SolarGardenLight.findOn(square)
        if light then
            lights:add(light)
            drawLamp(args.x, args.y, args.z, args.bulb)
        end
    end)
end

return SolarGardenLight
