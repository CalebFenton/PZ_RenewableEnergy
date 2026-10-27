-- What a payer (Payers) pays for: every switched-on appliance in its reach that it
-- pays for (Payers decides who, by `pays`), an unwired treadmill while a run draws power through it,
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
-- appliance, a treadmill or a generator, floor tiles included. A vanilla generator's scan doesn't
-- ask: its bill is vanilla's own total, so that mod bills a generator itself.

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

-- Whether a generator here, rather than the grid, would power `object`
-- (IsoGenerator.setSurroundingElectricity). With `gridGone`, as if the grid were down: whatever the
-- grid powers now counts too, since every grid check (ItemContainer.isObjectPowered) then fails.
local function offGrid(object, allowExterior, gridGone)
    return (gridGone or not ItemContainer.isObjectPowered(object, false))
        and (allowExterior or not object:getSquare():isOutside())
end

-- Positive native fuel demand when the engine would bill this generator, otherwise false.
local function generatorFuel(object, allowExterior, gridGone)
    local fuel = object:couldBePoweredByGenerator() and object:getGeneratorPowerConsumption()
    return fuel and fuel > 0 and offGrid(object, allowExterior, gridGone) and fuel
end

local function isRunningGenerator(object)
    return GeneratorReach.isVanillaGenerator(object) and object:isActivated()
end

--- What a payer on `square` pays for: each appliance in its reach for which `pays(object)` holds,
--- and the running generators, banks aside, that power its square (`generators`). With `gridGone`,
--- what is switched on in its reach whether or not the grid powers it now. A `vanilla` generator's
--- scan leaves out other mods' draws: vanilla bills those to it already.
---@param square IsoGridSquare the payer's square
function Loads.scan(square, pays, gridGone, vanilla)
    local load = Loads.new()
    local allowExterior = SandboxVars.AllowExteriorGenerator
    GeneratorReach.eachSquare(square:getX(), square:getY(), square:getZ(), function(scanned)
        local objects = scanned:getObjects()
        local i = scanned:getNextNonItemObjectIndex(0)
        while i ~= -1 do
            local object = objects:get(i)
            local fuel = generatorFuel(object, allowExterior, gridGone)
            if fuel then
                if pays(object) then
                    addAppliances(load, object, fuel)
                else
                    load.othersFuel = load.othersFuel + fuel
                end
            elseif Treadmill.isDrawing(object) and offGrid(object, allowExterior, gridGone) then
                if pays(object) then
                    Loads.add(load, "treadmill", Specs.wattsFromFuel(Treadmill.SPEC.drawFuel))
                end
            elseif isRunningGenerator(object) then
                table.insert(load.generators, object)
            elseif not vanilla then
                local kind, fuel = GeneratorReach.drawOf(object)
                if kind and offGrid(object, allowExterior, gridGone) and pays(object) then
                    Loads.add(load, kind, Specs.wattsFromFuel(fuel))
                end
            end
            i = scanned:getNextNonItemObjectIndex(i + 1)
        end
    end)
    return load
end

return Loads
