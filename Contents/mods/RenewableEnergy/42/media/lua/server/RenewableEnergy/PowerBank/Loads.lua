-- What a bank powers: every switched-on appliance in its reach, in watts, and
-- the running generators whose reach covers the bank.
--
-- The engine says whether an object draws power (getGeneratorPowerConsumption reads the
-- appliance's own switch, powered or not, so a bank that cut its power still sees what would
-- draw when it comes back) but its figures are fuel rates, so each kind of appliance gets its
-- 1993 wattage from Specs.loads. The reach is the engine's own for every generator: one radius
-- from the GeneratorTileRange sandbox option and GeneratorVerticalPowerRange floors up and down
-- (IsoGenerator.setSurroundingElectricity), on squares the grid doesn't power. A generator
-- powers a square exactly when the square is in that reach of the generator
-- (IsoGenerator.isPoweringSquare), so the same scan finds the generators powering the bank.

if isClient() then return end

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/PowerBank"

RenewableEnergy = RenewableEnergy or {}
local Loads = {}
RenewableEnergy.Loads = Loads

local LOADS = RenewableEnergy.Specs.loads
local PowerBank = RenewableEnergy.PowerBank

local function isMiniFridge(object)
    local properties = object:getProperties()
    return properties ~= nil and properties:get("GroupName") == "Mini"
end

-- The Specs.loads kind of an object with a fridge or freezer container.
local function fridgeKind(object)
    if object:getContainerByType("fridge") then
        if isMiniFridge(object) then
            return "miniFridge"
        elseif object:getContainerByType("freezer") then
            return "fridgeFreezer"
        end
    end
    return "fridge"
end

-- Adds to `load` each appliance `object` runs now.
local function addAppliances(load, object)
    if instanceof(object, "IsoStove") then
        Loads.add(load, object:isMicrowave() and "microwave" or "range")
    elseif instanceof(object, "IsoLightSwitch") then
        Loads.add(load, "light")
    elseif instanceof(object, "IsoTelevision") then
        Loads.add(load, "television")
    elseif instanceof(object, "IsoRadio") then
        Loads.add(load, "radio")
    elseif instanceof(object, "IsoCarBatteryCharger") then
        Loads.add(load, "batteryCharger")
    elseif instanceof(object, "IsoClothingWasher") then
        Loads.add(load, "washer")
    elseif instanceof(object, "IsoClothingDryer") then
        Loads.add(load, "dryer")
    elseif instanceof(object, "IsoCombinationWasherDryer") then
        Loads.add(load, object:isModeDryer() and "dryer" or "washer")
    elseif instanceof(object, "IsoStackedWasherDryer") then
        if object:isWasherActivated() then Loads.add(load, "washer") end
        if object:isDryerActivated() then Loads.add(load, "dryer") end
    elseif object:getPipedFuelAmount() <= 0 and object:getContainerByEitherType("fridge", "freezer") then
        Loads.add(load, fridgeKind(object))
    else
        Loads.add(load, "other", object:getGeneratorPowerConsumption() * LOADS.other.wattsPerConsumption)
    end
end

--- A new, empty load for Loads.add: `watts` the inverters must carry, `averageWatts` the energy
--- it takes, and per Specs.loads kind its count and watts.
function Loads.new()
    return { watts = 0, averageWatts = 0, kinds = {}, generators = {} }
end

--- Add an appliance of Specs.loads kind `name` to `load`.
function Loads.add(load, name, watts)
    local spec = LOADS[name]
    watts = watts or spec.watts
    load.watts = load.watts + watts
    load.averageWatts = load.averageWatts + watts * (spec.duty or 1)
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

-- Objects the engine would bill a generator here for (IsoGenerator.setSurroundingElectricity).
local function drawsFromGenerator(object, allowExterior)
    return object:couldBePoweredByGenerator()
        and object:getGeneratorPowerConsumption() > 0
        and not ItemContainer.isObjectPowered(object, false)
        and (allowExterior or not object:getSquare():isOutside())
end

local function isRunningGenerator(object)
    return instanceof(object, "IsoGenerator") and object:isActivated() and not PowerBank.isBank(object)
end

--- Everything switched on within a bank's reach, and the running generators, banks aside,
--- that power the bank's square.
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
            elseif isRunningGenerator(object) then
                table.insert(load.generators, object)
            end
        end
    end)
    return load
end

return Loads
