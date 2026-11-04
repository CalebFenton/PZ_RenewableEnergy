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

-- Adds to `load` each appliance `object` runs now, at vanilla's figure for it, `elsewhere` or not.
local function addAppliances(load, object, fuel, elsewhere)
    local watts = Specs.wattsFromFuel(fuel)
    if instanceof(object, "IsoStackedWasherDryer") then
        -- Vanilla bills the two halves together, the same for each.
        local washer, dryer = object:isWasherActivated(), object:isDryerActivated()
        local halves = (washer and 1 or 0) + (dryer and 1 or 0)
        if washer then Loads.add(load, "washer", watts / halves, elsewhere) end
        if dryer then Loads.add(load, "dryer", watts / halves, elsewhere) end
    else
        Loads.add(load, kindOf(object), watts, elsewhere)
    end
end

-- The building `square` stands in, by its id, or nil outdoors.
local function buildingOf(square)
    local building = square and square:getBuilding()
    return building and building:getID()
end

--- A new, empty load of the payer at `at` ({ x, y, z }; nil for one made up): the `watts` it takes,
--- per kind its count and watts, the running generators found, `othersFuel`, vanilla's bill for the
--- appliances in reach that others pay for, and `elsewhere`, the share of `watts` that stands in
--- other buildings than the payer's, with its own kinds and the place of the nearest.
function Loads.new(at)
    return { watts = 0, kinds = {}, generators = {}, othersFuel = 0, at = at,
        home = at and buildingOf(getSquare(at.x, at.y, at.z)), elsewhere = { watts = 0, kinds = {} } }
end

--- Add an appliance of kind `name` (StatusWindow's LOAD_KINDS) drawing `watts` to `load`, in
--- another building if `elsewhere`.
function Loads.add(load, name, watts, elsewhere)
    load.watts = load.watts + watts
    local group = load
    if elsewhere then
        group = load.elsewhere
        group.watts = group.watts + watts
    end
    local kind = group.kinds[name] or { count = 0, watts = 0 }
    kind.count = kind.count + 1
    kind.watts = kind.watts + watts
    group.kinds[name] = kind
end

local function byWattsDescending(a, b)
    return a.watts > b.watts
end

--- The load, or its `elsewhere` share, by kind, biggest first: { { kind, count, watts }, ... }.
function Loads.byKind(load)
    local list = {}
    for name, kind in pairs(load.kinds) do
        table.insert(list, { kind = name, count = kind.count, watts = kind.watts })
    end
    table.sort(list, byWattsDescending)
    return list
end

--- The watts `load` takes for the kind `name`, in whatever building.
function Loads.kindW(load, name)
    local here, elsewhere = load.kinds[name], load.elsewhere.kinds[name]
    return (here and here.watts or 0) + (elsewhere and elsewhere.watts or 0)
end

--- What of the load stands in other buildings, for the status: { watts, byKind (Loads.byKind),
--- x, y, z of the nearest }; nil if nothing does.
function Loads.elsewhere(load)
    local elsewhere = load.elsewhere
    if elsewhere.watts <= 0 then
        return nil
    end
    return { watts = elsewhere.watts, byKind = Loads.byKind(elsewhere), x = elsewhere.x, y = elsewhere.y, z = elsewhere.z }
end

-- Whether the grid powers `object` now (ItemContainer.isObjectPowered), so a generator wouldn't.
local function onGrid(object)
    return ItemContainer.isObjectPowered(object, false)
end

local function isRunningGenerator(object)
    return GeneratorReach.isVanillaGenerator(object) and object:isActivated()
end

--- Each draw in the reach of a payer on `square`, as `fn(draw)`, and each running generator there,
--- banks aside, as `onGenerator(generator)`: those power the payer's square. A draw is { object,
--- x, y, z, index (its object index on its square), watts, fuel (vanilla's bill an hour for an
--- appliance; nil for a treadmill or another mod's draw), kind (a treadmill's or another mod's),
--- onGrid (whether the grid powers it now), building (the id of the building it stands in, nil
--- outdoors) }.
---@param square IsoGridSquare the payer's square
function Loads.eachDraw(square, fn, onGenerator)
    local allowExterior = SandboxVars.AllowExteriorGenerator
    GeneratorReach.eachSquare(square:getX(), square:getY(), square:getZ(), function(scanned)
        local objects = scanned:getObjects()
        local x, y, z = scanned:getX(), scanned:getY(), scanned:getZ()
        -- Whether a generator may power what stands here (IsoGenerator.setSurroundingElectricity).
        local mayPower = allowExterior or not scanned:isOutside()
        local i = scanned:getNextNonItemObjectIndex(0)
        while i ~= -1 do
            local object = objects:get(i)
            local fuel = mayPower and object:couldBePoweredByGenerator() and object:getGeneratorPowerConsumption()
            local draw
            if fuel and fuel > 0 then
                draw = { fuel = fuel, watts = Specs.wattsFromFuel(fuel) }
            elseif mayPower and Treadmill.isDrawing(object) then
                draw = { kind = "treadmill", watts = Specs.wattsFromFuel(Treadmill.SPEC.drawFuel) }
            elseif isRunningGenerator(object) then
                onGenerator(object)
            elseif mayPower then
                local kind, modFuel = GeneratorReach.drawOf(object)
                draw = kind and { kind = kind, watts = Specs.wattsFromFuel(modFuel) }
            end
            if draw then
                draw.object, draw.x, draw.y, draw.z, draw.index = object, x, y, z, i
                draw.onGrid, draw.building = onGrid(object), buildingOf(scanned)
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

-- Notes `draw` as the nearest of `load`'s other buildings' draws if it is, by tiles, each level
-- counting as one, as Payers measures; of draws as near, the first.
local function noteNearest(load, draw)
    local elsewhere, at = load.elsewhere, load.at
    local dx, dy, dz = draw.x - at.x, draw.y - at.y, draw.z - at.z
    local distance = dx * dx + dy * dy + dz * dz
    if not elsewhere.distance or distance < elsewhere.distance then
        elsewhere.distance, elsewhere.x, elsewhere.y, elsewhere.z = distance, draw.x, draw.y, draw.z
    end
end

--- Adds `draw` (Loads.eachDraw) to `load`, at vanilla's figure for an appliance. A draw in another
--- building than the payer's goes in its `elsewhere` share; one outdoors counts as the payer's own.
--- A vanilla generator in the same spot bills both alike, so the bank does: the split only tells
--- the player where the load is.
function Loads.addDraw(load, draw)
    local elsewhere = draw.building ~= nil and draw.building ~= load.home
    if elsewhere then
        noteNearest(load, draw)
    end
    if draw.fuel then
        addAppliances(load, draw.object, draw.fuel, elsewhere)
    else
        Loads.add(load, draw.kind, draw.watts, elsewhere)
    end
end

return Loads
