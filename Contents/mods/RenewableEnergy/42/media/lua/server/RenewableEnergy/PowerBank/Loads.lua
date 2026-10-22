-- What a source pays for: every switched-on appliance in its reach that no running source is
-- nearer to (RenewableEnergy.Payers), an unwired treadmill while a run draws power through it,
-- and the running generators whose reach covers the source.
--
-- getGeneratorPowerConsumption reads the appliance's own switch, powered or not, so a bank that
-- cut its power still sees what would draw when it comes back. Its figure is generator fuel an
-- hour, which Specs.wattsPerFuel turns into watts. The reach is the engine's own for every
-- generator (IsoGenerator.setSurroundingElectricity), on squares the grid doesn't power. A
-- generator powers a square exactly when the square is in that reach
-- (IsoGenerator.isPoweringSquare), so the same scan finds the generators powering the bank.
--
-- The engine knows nothing of a treadmill's draw: a run says when it draws (Treadmill.isDrawing),
-- and it is billed on the same squares as an appliance.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/PowerBank/Treadmill"
require "RenewableEnergy/PowerBank/Payers"

RenewableEnergy = RenewableEnergy or {}
local Loads = {}
RenewableEnergy.Loads = Loads

local Specs = RenewableEnergy.Specs
local WATTS_PER_FUEL = Specs.wattsPerFuel
local PowerBank, Treadmill, Payers = RenewableEnergy.PowerBank, RenewableEnergy.Treadmill, RenewableEnergy.Payers

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

--- What `payer` (a Payers source on `square`) pays for among `sources` (Payers.running), and the
--- running generators, banks aside, that power its square.
---@param square IsoGridSquare the payer's square
function Loads.scan(square, payer, sources)
    local load = Loads.new()
    local allowExterior = SandboxVars.AllowExteriorGenerator
    local sharers = Payers.sharers(payer, sources)
    local function pays(object)
        return #sharers == 1 or Payers.payerAt(sharers, object:getX(), object:getY(), object:getZ()) == payer
    end
    RenewableEnergy.eachSquareInGeneratorReach(square, function(scanned)
        local objects = scanned:getObjects()
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            if drawsFromGenerator(object, allowExterior) then
                if pays(object) then
                    addAppliances(load, object)
                else
                    load.othersFuel = load.othersFuel + object:getGeneratorPowerConsumption()
                end
            elseif Treadmill.isDrawing(object) and offGrid(object, allowExterior) then
                if pays(object) then
                    Loads.add(load, "treadmill", Specs.treadmill.drawFuel * WATTS_PER_FUEL)
                end
            elseif isRunningGenerator(object) then
                Payers.track(object)
                table.insert(load.generators, object)
            end
        end
    end)
    return load
end

return Loads
