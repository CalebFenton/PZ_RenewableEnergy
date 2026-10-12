-- What a bank powers: every switched-on appliance in its reach, in watts (design §2.4).
--
-- The engine says whether an object draws power (getGeneratorPowerConsumption is 0 when it
-- is off) but its figures are fuel rates, so each kind of appliance gets its 1993 wattage
-- from Specs.loads. The reach is the engine's own for every generator: one radius from
-- the GeneratorTileRange sandbox option and GeneratorVerticalPowerRange floors up and down
-- (IsoGenerator.setSurroundingElectricity), on squares the grid doesn't power.

if isClient() then return end

require "RenewableEnergy/Specs"

local Loads = {}

local LOADS = RenewableEnergy.Specs.loads

-- Specs.loads names of what an object draws now, called with each one.
local function eachLoad(object, add)
    if instanceof(object, "IsoStove") then
        add(object:isMicrowave() and "microwave" or "range")
    elseif instanceof(object, "IsoLightSwitch") then
        add("light")
    elseif instanceof(object, "IsoTelevision") then
        add("television")
    elseif instanceof(object, "IsoRadio") then
        add("radio")
    elseif instanceof(object, "IsoCarBatteryCharger") then
        add("batteryCharger")
    elseif instanceof(object, "IsoClothingWasher") then
        add("washer")
    elseif instanceof(object, "IsoClothingDryer") then
        add("dryer")
    elseif instanceof(object, "IsoCombinationWasherDryer") then
        add(object:isModeDryer() and "dryer" or "washer")
    elseif instanceof(object, "IsoStackedWasherDryer") then
        if object:isWasherActivated() then add("washer") end
        if object:isDryerActivated() then add("dryer") end
    elseif object:getPipedFuelAmount() <= 0 and object:getContainerByType("fridge") and object:getContainerByType("freezer") then
        add("fridgeFreezer")
    elseif object:getPipedFuelAmount() <= 0 and object:getContainerByEitherType("fridge", "freezer") then
        add("fridge")
    else
        add("other", object:getGeneratorPowerConsumption() * LOADS.other.wattsPerConsumption)
    end
end

--- A new, empty load for Loads.add.
function Loads.new()
    return { watts = 0, motors = {}, volts240 = false, counts = {} }
end

--- Add an appliance of Specs.loads kind `name` to `load`.
function Loads.add(load, name, watts)
    local spec = LOADS[name]
    watts = watts or spec.watts
    load.watts = load.watts + watts
    load.counts[name] = (load.counts[name] or 0) + 1
    if spec.volts == 240 then
        load.volts240 = true
    end
    if spec.surge then
        table.insert(load.motors, { watts = watts, surge = spec.surge })
    end
end

-- Objects the engine would bill a generator here for (IsoGenerator.setSurroundingElectricity).
local function drawsFromGenerator(object, allowExterior)
    return object:couldBePoweredByGenerator()
        and object:getGeneratorPowerConsumption() > 0
        and not ItemContainer.isObjectPowered(object, false)
        and (allowExterior or not object:getSquare():isOutside())
end

--- Everything switched on within a bank's reach.
---@param square IsoGridSquare the bank's square
function Loads.scan(square)
    local load = Loads.new()
    local radius = SandboxVars.GeneratorTileRange
    local levels = SandboxVars.GeneratorVerticalPowerRange
    local allowExterior = SandboxVars.AllowExteriorGenerator
    local cx, cy, cz = square:getX(), square:getY(), square:getZ()
    local cell = square:getCell()
    local function add(name, watts)
        Loads.add(load, name, watts)
    end
    for z = math.max(-32, cz - levels), math.min(31, cz + levels) do
        for x = cx - radius, cx + radius do
            for y = cy - radius, cy + radius do
                local scanned = IsoUtils.DistanceToSquared(x + 0.5, y + 0.5, cx + 0.5, cy + 0.5) <= radius * radius
                    and cell:getGridSquare(x, y, z)
                if scanned then
                    local objects = scanned:getObjects()
                    for i = 0, objects:size() - 1 do
                        local object = objects:get(i)
                        if drawsFromGenerator(object, allowExterior) then
                            eachLoad(object, add)
                        end
                    end
                end
            end
        end
    end
    return load
end

--- The draw while the motors start: one of them, or all of them at once when power comes
--- back, each with a random start-up surge from its Specs.loads range.
function Loads.surgeWatts(load, allMotors)
    local motors = load.motors
    if #motors == 0 then
        return load.watts
    end
    local function extra(motor)
        return ZombRandFloat(motor.surge.min, motor.surge.max) - motor.watts
    end
    if allMotors then
        local total = load.watts
        for _, motor in ipairs(motors) do
            total = total + extra(motor)
        end
        return total
    end
    return load.watts + extra(motors[ZombRand(#motors) + 1])
end

return Loads
