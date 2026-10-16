-- Turns the wind chargers this client can see, a cosmetic only it draws. Each charger is drawn as a
-- 3D model through a sprite model (Sprites.windModels), and the rotor turns by stepping the object
-- through models yawed a step apart (IsoObject.setSpriteModelName); animating keeps it out of the
-- cached chunk, so each step shows at once. The game's wind is the same on every client, and a
-- charger's brake is in its modData, so nothing needs sending.

require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Wind"

local Specs, Sprites, Wind = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Wind

local WindSpin = {}
RenewableEnergy.WindSpin = WindSpin

-- Turns a second: a slow start at the cut-in speed, faster with the wind, no faster than this.
local START_TPS, TPS_PER_KPH, MAX_TPS = 0.3, 0.04, 2

-- Wind charger objects this client has, and how far round each one is, in steps.
local turbines = {}

--- Starts turning `object` if it is a wind charger: as its chunk loads, or as it is added to the
--- map (OnObjectAdded, which Wind.OnCreate fires for a charger built in single player).
function WindSpin.track(object)
    if turbines[object] then return end
    local name = Sprites.nameOf(object)
    local prefix, model = Sprites.windModelOf(name)
    if not prefix then return end
    turbines[object] = { spec = Specs.wind.turbines[Sprites.kindOf(name)], model = model, prefix = prefix, phase = 0, shown = 0 }
    object:setSpriteModelName(prefix .. "0")
    object:setAnimating(true)
end

local function turnsPerSecond(spec, kph)
    if kph <= spec.cutInKph then
        return 0
    end
    return math.min(MAX_TPS, START_TPS + TPS_PER_KPH * (kph - spec.cutInKph))
end

local lastMs

local function spin()
    local now = getTimestampMs()
    local seconds = lastMs and (now - lastMs) / 1000 or 0
    lastMs = now
    if seconds <= 0 or isGamePaused() then return end
    local kph = getClimateManager():getWindspeedKph()
    for object, state in pairs(turbines) do
        if object:getObjectIndex() == -1 then
            turbines[object] = nil
        elseif not (Wind.isBraked(object) or Wind.isBroken(object)) then
            local model = state.model
            state.phase = (state.phase + turnsPerSecond(state.spec, kph) * model.stepsPerTurn * seconds) % model.steps
            local step = math.floor(state.phase)
            if step ~= state.shown then
                state.shown = step
                object:setSpriteModelName(state.prefix .. step)
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
