-- Turns the wind chargers this client can see, a cosmetic only it draws. Each charger is drawn as a
-- 3D model through a sprite model (scripts/RenewableEnergy/SpriteModels.txt), and the rotor turns
-- by stepping the object through models yawed a step apart (IsoObject.setSpriteModelName);
-- animating keeps it out of the cached chunk, so each step shows at once. The game's wind is the
-- same on every client, and a charger's brake is in its modData, so nothing needs sending.

require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/PowerBank/PowerBank"

local Specs, Sprites, PowerBank = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.PowerBank

local WindSpin = {}
RenewableEnergy.WindSpin = WindSpin

-- Sprite models by kind: the name before the step number, and how many steps make the turn back
-- to where it started (the scoop rotor looks the same every half turn).
local MODELS = {
    scoop = { name = "RenewableEnergy.ScoopRotor", steps = 6, stepsPerTurn = 12 },
}
-- Turns a second: a slow start at the cut-in speed, faster with the wind, no faster than this.
local START_TPS, TPS_PER_KPH, MAX_TPS = 0.3, 0.04, 2
-- MapObjects keeps one function per sprite and priority.
local LOAD_PRIORITY = 6

-- Wind charger objects this client has, and how far round each one is, in steps.
local turbines = {}

--- Starts turning `object` if it is a wind charger. A charger built in single player comes here
--- from its OnCreate (RenewableEnergy.Wind.OnCreate), since single player fires no OnObjectAdded.
function WindSpin.track(object)
    local kind = PowerBank.sourceKind(object)
    local model = kind and MODELS[kind]
    if not model or turbines[object] then return end
    turbines[object] = { kind = kind, model = model, phase = 0, shown = 0 }
    object:setSpriteModelName(model.name .. "0")
    object:setAnimating(true)
end

local function turnsPerSecond(kind, kph)
    local spec = Specs.wind.turbines[kind]
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
        elseif not PowerBank.isBraked(object) then
            local model = state.model
            state.phase = (state.phase + turnsPerSecond(state.kind, kph) * model.stepsPerTurn * seconds) % model.steps
            local step = math.floor(state.phase)
            if step ~= state.shown then
                state.shown = step
                object:setSpriteModelName(model.name .. step)
            end
        end
    end
end

MapObjects.OnLoadWithSprite(Sprites.windScoop, WindSpin.track, LOAD_PRIORITY)
Events.OnObjectAdded.Add(WindSpin.track)
Events.OnTick.Add(spin)

return WindSpin
