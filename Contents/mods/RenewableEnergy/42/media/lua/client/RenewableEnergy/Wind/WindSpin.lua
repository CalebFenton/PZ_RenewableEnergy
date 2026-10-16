-- Turns the wind chargers this client can see, a cosmetic only it draws. Each charger is drawn as a
-- 3D model through a sprite model (Sprites.windModels), and the rotor turns by stepping the object
-- through models yawed a step apart (IsoObject.setSpriteModelName); animating keeps it out of the
-- cached chunk, so each step shows at once. The game's wind is the same on every client, and a
-- charger's brake is in its modData, so nothing needs sending.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Wind"

local Specs, Sprites, Wind = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Wind

local WindSpin = {}
RenewableEnergy.WindSpin = WindSpin

-- Turns a second: a slow start at the cut-in speed, faster with the wind, no faster than this.
local START_TPS, TPS_PER_KPH, MAX_TPS = 0.3, 0.04, 2

-- Wind charger objects this client has, and how far round each one is, in steps; and how many.
local turbines, tracked = {}, 0

-- Each sprite model prefix's model names by step + 1, so a step builds no string.
local MODEL_NAMES = {}

local function modelNames(prefix, model)
    local names = MODEL_NAMES[prefix]
    if not names then
        names = {}
        for step = 0, model.steps - 1 do
            names[step + 1] = prefix .. step
        end
        MODEL_NAMES[prefix] = names
    end
    return names
end

--- Starts turning `object` if it is a wind charger: as its chunk loads, or as it is added to the
--- map (OnObjectAdded, which Wind.OnCreate fires for a charger built in single player).
function WindSpin.track(object)
    if turbines[object] then return end
    local name = Sprites.nameOf(object)
    local prefix, model = Sprites.windModelOf(name)
    if not prefix then return end
    local names = modelNames(prefix, model)
    turbines[object] = { spec = Specs.wind.turbines[Sprites.kindOf(name)], model = model, names = names, phase = 0, shown = 0 }
    tracked = tracked + 1
    object:setSpriteModelName(names[1])
    object:setAnimating(true)
end

local function turnsPerSecond(spec, kph)
    if kph <= spec.cutInKph then
        return 0
    end
    return math.min(MAX_TPS, START_TPS + TPS_PER_KPH * (kph - spec.cutInKph))
end

local lastMs

-- Each tick: drops the chargers gone from the map, and steps on those turning. A calm, braked or
-- broken charger costs only the check that it is still there.
local function spin()
    local now = getTimestampMs()
    local seconds = lastMs and (now - lastMs) / 1000 or 0
    lastMs = now
    if seconds <= 0 or tracked == 0 or isGamePaused() then return end
    local kph = getClimateManager():getWindspeedKph()
    for object, state in pairs(turbines) do
        if not RenewableEnergy.onSquare(object) then
            turbines[object] = nil
            tracked = tracked - 1
        else
            local turns = turnsPerSecond(state.spec, kph)
            if turns > 0 and not (Wind.isBraked(object) or Wind.isBroken(object)) then
                local model = state.model
                state.phase = (state.phase + turns * model.stepsPerTurn * seconds) % model.steps
                local step = math.floor(state.phase)
                if step ~= state.shown then
                    state.shown = step
                    object:setSpriteModelName(state.names[step + 1])
                end
            end
        end
    end
end

for kind in pairs(Sprites.windModels) do
    MapObjects.OnLoadWithSprite(Sprites.namesOf(kind), WindSpin.track, Sprites.LOAD_PRIORITY)
end
Events.OnObjectAdded.Add(WindSpin.track)
Events.OnTick.Add(spin)

return WindSpin
