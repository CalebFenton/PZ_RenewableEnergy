if isClient() then
    return
end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Sun"
require "RenewableEnergy/Gadgets/SolarGardenLight"

-- The Solar Garden Light on the authority, the one writer of its charge, bulb and tile: the
-- night and day GadgetCharging's pass runs, and the bulb jobs from a timed action's complete().
local SolarGardenLight = RenewableEnergy.SolarGardenLight
local Specs, Sprites, Sun = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Sun

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
        sendServerCommand(SolarGardenLight.COMMAND_MODULE, SolarGardenLight.LAMP_COMMAND,
            { x = light:getX(), y = light:getY(), z = light:getZ(), bulb = SolarGardenLight.lampBulb(light) })
    end
end

-- Runs a light for `hours` under `sky` (Sun.skyNow): by day its cell charges the battery, and after
-- sunset its bulb draws on it until it is empty; a light without a bulb draws nothing.
-- `bulbChanged` says its bulb has just changed, so that its lamp's colour reaches the clients even
-- if it stays lit.
local function run(light, hours, sky, bulbChanged)
    local spec = Specs.gardenLight
    local night = sky.up <= 0
    local bulb = SolarGardenLight.getBulb(light) ~= nil
    local charge = SolarGardenLight.getCharge(light)
    if not night then
        charge = math.min(spec.wh, charge + Sun.squareWatts(light:getSquare(), spec.watts, sky) * hours)
    elseif bulb then
        charge = math.max(0, charge - spec.nightWatts * hours)
    end
    light:getModData()[SolarGardenLight.CHARGE_KEY] = charge
    setLit(light, night and bulb and charge > 0, bulbChanged)
end

-- Puts `bulb` (nil for none) in the light, tells the clients, and lights or darkens it at once.
local function setBulb(light, bulb)
    light:getModData()[SolarGardenLight.BULB_KEY] = bulb or SolarGardenLight.NO_BULB
    light:transmitModData()
    run(light, 0, Sun.skyNow(), true)
end

--- Takes the bulb out of `light` and gives it to `character`. Returns whether it did.
function SolarGardenLight.removeBulb(character, light)
    local bulb = SolarGardenLight.getBulb(light)
    if not bulb then
        return false
    end
    setBulb(light, nil)
    RenewableEnergy.giveItems(character, bulb)
    return true
end

--- Takes the bulb `item` from `character` and puts it in `light`, which has none. Returns
--- whether it did.
function SolarGardenLight.addBulb(character, light, item)
    if SolarGardenLight.getBulb(light) or not SolarGardenLight.isBulb(item) then
        return false
    end
    RenewableEnergy.takeItem(character, item)
    setBulb(light, item:getFullType())
    return true
end

--- Runs every loaded light the authority has seen.
function SolarGardenLight.updateAll(hours)
    local sky = Sun.skyNow()
    SolarGardenLight.eachLoaded(function(light)
        run(light, hours, sky, false)
    end)
end

return SolarGardenLight
