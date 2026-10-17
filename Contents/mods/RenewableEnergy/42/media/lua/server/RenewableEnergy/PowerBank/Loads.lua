-- What a bank powers: every switched-on appliance in its reach, in watts, an unwired treadmill
-- while a run draws power through it, and the running generators whose reach covers the bank.
--
-- The engine says whether an object draws power and how much: getGeneratorPowerConsumption reads
-- the appliance's own switch, powered or not, so a bank that cut its power still sees what would
-- draw when it comes back, and its figure, generator fuel an hour, comes to watts at
-- Specs.wattsPerFuel. The reach is the engine's own for every generator: one radius
-- from the GeneratorTileRange sandbox option and GeneratorVerticalPowerRange floors up and down
-- (IsoGenerator.setSurroundingElectricity), on squares the grid doesn't power. A generator
-- powers a square exactly when the square is in that reach of the generator
-- (IsoGenerator.isPoweringSquare), so the same scan finds the generators powering the bank.
--
-- The engine knows nothing of a treadmill's draw: a run says when it draws (Treadmill.isDrawing),
-- and it is billed on the same squares as an appliance.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Treadmill"

RenewableEnergy = RenewableEnergy or {}
local Loads = {}
RenewableEnergy.Loads = Loads

local Specs = RenewableEnergy.Specs
local WATTS_PER_FUEL = Specs.wattsPerFuel
local PowerBank, Treadmill = RenewableEnergy.PowerBank, RenewableEnergy.Treadmill

-- The kind of an object with a fridge or freezer container, as vanilla bills it: by its
-- containers alone, so a mini fridge with its ice box is a fridge-freezer.
local function fridgeKind(object)
    if object:getContainerByType("fridge") and object:getContainerByType("freezer") then
        return "fridgeFreezer"
    end
    return "fridge"
end

-- The kind the status lists `object` as (StatusWindow's LOAD_KINDS).
local function kindOf(object)
    if instanceof(object, "IsoStove") then
        return object:isMicrowave() and "microwave" or "range"
    elseif instanceof(object, "IsoLightSwitch") then
        return "light"
    elseif instanceof(object, "IsoTelevision") then
        return "television"
    elseif instanceof(object, "IsoRadio") then
        return "radio"
    elseif instanceof(object, "IsoCarBatteryCharger") then
        return "batteryCharger"
    elseif instanceof(object, "IsoClothingWasher") then
        return "washer"
    elseif instanceof(object, "IsoClothingDryer") then
        return "dryer"
    elseif instanceof(object, "IsoCombinationWasherDryer") then
        return object:isModeDryer() and "dryer" or "washer"
    elseif object:getPipedFuelAmount() <= 0 and object:getContainerByEitherType("fridge", "freezer") then
        return fridgeKind(object)
    end
    return "other"
end

-- Adds to `load` each appliance `object` runs now, at vanilla's figure for it.
local function addAppliances(load, object)
    local watts = object:getGeneratorPowerConsumption() * WATTS_PER_FUEL
    if instanceof(object, "IsoStackedWasherDryer") then
        -- Vanilla bills the two halves together, the same for each.
        local washer, dryer = object:isWasherActivated(), object:isDryerActivated()
        local halves = (washer and 1 or 0) + (dryer and 1 or 0)
        if washer then Loads.add(load, "washer", watts / halves) end
        if dryer then Loads.add(load, "dryer", watts / halves) end
    else
        Loads.add(load, kindOf(object), watts)
    end
end

--- A new, empty load for Loads.add: `watts` it takes, and per kind its count and watts.
function Loads.new()
    return { watts = 0, kinds = {}, generators = {} }
end

--- Add an appliance of kind `name` (StatusWindow's LOAD_KINDS) drawing `watts` to `load`.
function Loads.add(load, name, watts)
    load.watts = load.watts + watts
    local kind = load.kinds[name] or { count = 0, watts = 0 }
    kind.count = kind.count + 1
    kind.watts = kind.watts + watts
    load.kinds[name] = kind
end

local function byWattsDescending(a, b)
    return a.watts > b.watts
end

--- The load by kind, biggest first: { { kind, count, watts }, ... }.
function Loads.byKind(load)
    local list = {}
    for name, kind in pairs(load.kinds) do
        table.insert(list, { kind = name, count = kind.count, watts = kind.watts })
    end
    table.sort(list, byWattsDescending)
    return list
end

-- Whether a generator here, rather than the grid, would power `object`
-- (IsoGenerator.setSurroundingElectricity).
local function offGrid(object, allowExterior)
    return not ItemContainer.isObjectPowered(object, false)
        and (allowExterior or not object:getSquare():isOutside())
end

-- Objects the engine would bill a generator here for (IsoGenerator.setSurroundingElectricity).
local function drawsFromGenerator(object, allowExterior)
    return object:couldBePoweredByGenerator()
        and object:getGeneratorPowerConsumption() > 0
        and offGrid(object, allowExterior)
end

local function isRunningGenerator(object)
    return instanceof(object, "IsoGenerator") and object:isActivated() and not PowerBank.isBank(object)
end

--- Everything switched on within a bank's reach, treadmills that runs draw through among them, and
--- the running generators, banks aside, that power the bank's square.
---@param square IsoGridSquare the bank's square
function Loads.scan(square)
    local load = Loads.new()
    local allowExterior = SandboxVars.AllowExteriorGenerator
    RenewableEnergy.eachSquareInGeneratorReach(square, function(scanned)
        local objects = scanned:getObjects()
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            if drawsFromGenerator(object, allowExterior) then
                addAppliances(load, object)
            elseif Treadmill.isDrawing(object) and offGrid(object, allowExterior) then
                Loads.add(load, "treadmill", Specs.treadmill.drawFuel * WATTS_PER_FUEL)
            elseif isRunningGenerator(object) then
                table.insert(load.generators, object)
            end
        end
    end)
    return load
end

return Loads
