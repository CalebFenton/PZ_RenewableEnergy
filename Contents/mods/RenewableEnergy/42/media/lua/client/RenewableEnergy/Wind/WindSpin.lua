-- Turns the wind chargers this client can see, a cosmetic only it draws. Each charger is drawn as a
-- 3D model through a sprite model (Sprites.windModels), and the rotor turns by stepping the object
-- through models yawed a step apart (IsoObject.setSpriteModelName); animating keeps it out of the
-- cached chunk, so each step shows at once. An unbraked charger in a wind that can break its blades
-- strains audibly now and then, the warning to set the brake. The game's wind is the same on every
-- client, and a charger's brake is in its modData, so nothing needs sending.

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Wind"

local Specs, Sprites, Wind = RenewableEnergy.Specs, RenewableEnergy.Sprites, RenewableEnergy.Wind

local WindSpin = {}
RenewableEnergy.WindSpin = WindSpin

-- Turns a second: a slow start at the cut-in speed, faster with the wind, no faster than this.
local START_TPS, TPS_PER_KPH, MAX_TPS = 0.3, 0.04, 2
-- Seconds between a straining charger's sounds, at random between these.
local STRAIN_MIN_SECONDS, STRAIN_MAX_SECONDS = 6, 14

-- Wind charger objects this client has, and how far round each one is, in steps; and how many.
local chargers, tracked = {}, 0

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

-- A charger's turning state for the tile `name`, shown at its first step; nil for any other tile.
local function stateFor(name)
    local prefix, model = Sprites.windModelOf(name)
    if not prefix then return nil end
    local kind, _, material = Sprites.kindOf(name)
    return { sprite = name, spec = Specs.wind.turbines[kind], blades = Wind.bladesOf(kind, material),
        model = model, names = modelNames(prefix, model), phase = 0, shown = 0, strainIn = 0 }
end

--- Starts turning `object` if it is a wind charger: as its chunk loads, or as it is added to the
--- map (OnObjectAdded, which Wind.OnCreate fires for a charger built in single player).
function WindSpin.track(object)
    if chargers[object] then return end
    local state = stateFor(Sprites.nameOf(object))
    if not state then return end
    chargers[object] = state
    tracked = tracked + 1
    object:setSpriteModelName(state.names[1])
    object:setAnimating(true)
end

local function turnsPerSecond(spec, kph)
    if kph <= spec.cutInKph then
        return 0
    end
    return math.min(MAX_TPS, START_TPS + TPS_PER_KPH * (kph - spec.cutInKph))
end

local lastMs

-- Counts down to the charger's next strain sound while the wind can break its blades, and plays it.
local function strain(object, state, kph, seconds)
    if not Wind.canBreak(state.spec, state.blades, kph) then
        state.strainIn = 0
        return
    end
    state.strainIn = state.strainIn - seconds
    if state.strainIn <= 0 then
        state.strainIn = ZombRandFloat(STRAIN_MIN_SECONDS, STRAIN_MAX_SECONDS)
        object:getSquare():playSound(Specs.wind.blades[state.blades].strainSound)
    end
end

-- Each tick: drops the chargers gone from the map, and steps on those turning. A charger whose
-- tile changed, as Replace Blades with blades of another material changes it, here or from the
-- server, with no event for it, takes the new tile's models. A calm, braked or broken charger costs
-- only the checks that it is still there on the same tile.
local function spin()
    local now = getTimestampMs()
    local seconds = lastMs and (now - lastMs) / 1000 or 0
    lastMs = now
    if seconds <= 0 or tracked == 0 or isGamePaused() then return end
    local kph = getClimateManager():getWindspeedKph()
    for object, state in pairs(chargers) do
        local name = RenewableEnergy.onSquare(object) and Sprites.nameOf(object)
        if name and name ~= state.sprite then
            state = stateFor(name)
            if state then
                -- Replacing a key the walk has reached is allowed; adding one is not.
                chargers[object] = state
                object:setSpriteModelName(state.names[1])
            end
        end
        if not (name and state) then
            chargers[object] = nil
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
                strain(object, state, kph, seconds)
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
