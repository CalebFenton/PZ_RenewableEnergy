-- What a payer (Payers) pays for: every switched-on appliance in its reach that it
-- pays for (Payers decides who), an unwired treadmill while a run draws power through it,
-- and the running generators whose reach covers the payer.
--
-- getGeneratorPowerConsumption reads the appliance's own switch, powered or not, so a bank that
-- cut its power still sees what would draw when it comes back. Its figure is generator fuel an
-- hour, which Specs.wattsFromFuel turns into watts. The reach is the engine's own for every
-- generator (IsoGenerator.setSurroundingElectricity), on squares the grid doesn't power. A
-- generator powers a square exactly when the square is in that reach
-- (IsoGenerator.isPoweringSquare), so the same scan finds the generators powering the bank.
--
-- The engine knows nothing of a treadmill's draw: a run says when it draws (Treadmill.isDrawing),
-- and it is billed on the same squares as an appliance. Nor of another mod's appliances, such as
-- Enhanced Irrigation's Pump Houses: the mod says what each draws (GeneratorReach.addDraw), and
-- they are billed the same way. It is asked of every placed object in reach that isn't a vanilla
-- appliance, a treadmill or a generator, floor tiles included. A vanilla generator doesn't count
-- those (Loads.counts): its bill is vanilla's own total, so that mod bills a generator itself.

if isClient() then return end

local Specs = require "RenewableEnergy/Specs"
local Treadmill = require "RenewableEnergy/PowerBank/Treadmill"
local GeneratorReach = require "cf_commonlib/GeneratorReach"

local Loads = {}

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
    elseif object:getContainerByEitherType("fridge", "freezer") then
        return fridgeKind(object)
    end
    return "other"
end

-- Adds to `load` each appliance `object` runs now, at vanilla's figure for it.
local function addAppliances(load, object, fuel)
    local watts = Specs.wattsFromFuel(fuel)
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

--- A new, empty load: the `watts` it takes, per kind its count and watts, the running generators
--- found, and `othersFuel`, vanilla's bill for the appliances in reach that others pay for.
function Loads.new()
    return { watts = 0, kinds = {}, generators = {}, othersFuel = 0 }
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

-- Whether the grid powers `object` now (ItemContainer.isObjectPowered), so a generator wouldn't.
local function onGrid(object)
    return ItemContainer.isObjectPowered(object, false)
end

-- A generator may power `object` where it stands (IsoGenerator.setSurroundingElectricity).
local function mayPower(object, allowExterior)
    return allowExterior or not object:getSquare():isOutside()
end

local function isRunningGenerator(object)
    return GeneratorReach.isVanillaGenerator(object) and object:isActivated()
end

--- Each draw in the reach of a payer on `square`, as `fn(draw)`, and each running generator there,
--- banks aside, as `onGenerator(generator)`: those power the payer's square. A draw is { object,
--- x, y, z, index (its object index on its square), watts, fuel (vanilla's bill an hour for an
--- appliance; nil for a treadmill or another mod's draw), kind (a treadmill's or another mod's),
--- onGrid (whether the grid powers it now) }.
---@param square IsoGridSquare the payer's square
function Loads.eachDraw(square, fn, onGenerator)
    local allowExterior = SandboxVars.AllowExteriorGenerator
    GeneratorReach.eachSquare(square:getX(), square:getY(), square:getZ(), function(scanned)
        local objects = scanned:getObjects()
        local x, y, z = scanned:getX(), scanned:getY(), scanned:getZ()
        local i = scanned:getNextNonItemObjectIndex(0)
        while i ~= -1 do
            local object = objects:get(i)
            local fuel = object:couldBePoweredByGenerator() and object:getGeneratorPowerConsumption()
            local draw
            if fuel and fuel > 0 then
                draw = { fuel = fuel, watts = Specs.wattsFromFuel(fuel) }
            elseif Treadmill.isDrawing(object) then
                draw = { kind = "treadmill", watts = Specs.wattsFromFuel(Treadmill.SPEC.drawFuel) }
            elseif isRunningGenerator(object) then
                onGenerator(object)
            else
                local kind, modFuel = GeneratorReach.drawOf(object)
                draw = kind and { kind = kind, watts = Specs.wattsFromFuel(modFuel) }
            end
            if draw and mayPower(object, allowExterior) then
                draw.object, draw.x, draw.y, draw.z, draw.index = object, x, y, z, i
                draw.onGrid = onGrid(object)
                fn(draw)
            end
            i = scanned:getNextNonItemObjectIndex(i + 1)
        end
    end)
end

--- Whether a payer counts `draw` at all: with `gridGone`, what the grid powers too, since every
--- grid check then fails; a `vanilla` generator leaves out other mods' draws, which vanilla bills
--- it already (that mod bills a generator itself).
function Loads.counts(draw, gridGone, vanilla)
    return (gridGone or not draw.onGrid) and not (vanilla and draw.kind and draw.kind ~= "treadmill")
end

--- Adds `draw` (Loads.eachDraw) to `load`, at vanilla's figure for an appliance.
function Loads.addDraw(load, draw)
    if draw.fuel then
        addAppliances(load, draw.object, draw.fuel)
    else
        Loads.add(load, draw.kind, draw.watts)
    end
end

return Loads
