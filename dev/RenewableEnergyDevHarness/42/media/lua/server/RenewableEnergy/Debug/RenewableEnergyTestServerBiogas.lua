-- The authority's half of the biogas tests: digesters and their stink live where the authority
-- runs them. Only registers handlers, so a --stay rerun loads it again (RELOAD_FILES);
-- RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler

-- Stink ------------------------------------------------------------------------------------------

-- Makes the source `args.key` at x, y, z smell like `args.count` corpses (RenewableEnergy.Stink),
-- until the test ends. Answers how many its chunk counts now.
handler("stinkSet", function(player, args, defer)
    local Stink = RenewableEnergy.Stink
    Stink.set(args.key, args.x, args.y, args.z, args.count)
    defer(function() Stink.set(args.key, args.x, args.y, args.z, 0) end)
    return { counted = Stink.counted(args.key) }
end)

-- What the authority's copy of the character smells: its corpse sickness rate, its noxious smell
-- moodle level and food sickness; the corpses on the square at x, y, z, which ghosts never join;
-- and what is left of the filter of a worn gas mask, if any.
handler("stinkRead", function(player, args)
    local square = getSquare(args.x, args.y, args.z)
    local mask
    local worn = player:getWornItems()
    for i = 0, worn:size() - 1 do
        local item = worn:getItemByIndex(i)
        if item and item:hasTag(ItemTag.GAS_MASK) then
            mask = item:getUsedDelta()
        end
    end
    return {
        rate = player:getCorpseSicknessRate(),
        level = player:getMoodles():getMoodleLevel(MoodleType.NOXIOUS_SMELL),
        sickness = player:getStats():get(CharacterStat.FOOD_SICKNESS),
        bodies = square and square:getDeadBodys():size() or -1,
        objects = square and square:getMovingObjects():size() or -1,
        mask = mask,
    }
end)

-- Digesters -------------------------------------------------------------------------------------

local function digesterAt(args)
    local square = Helpers.squareAt(args)
    local object = square and RenewableEnergy.findObjectOn(square, RenewableEnergy.Digester.isDigester)
    local record = object and RenewableEnergy.Digester.recordOf(object)
    if not record then
        return nil, nil, "a digester at " .. tostring(args.x) .. "," .. tostring(args.y)
    end
    return record, object
end

-- Builds a digester of the Sprites.digester tile `args.tile` ("barrel.steel", "insulated", ...)
-- at x, y, z, as the build menu does (ISBuildIsoEntity:create): a thumpable on the square, then the
-- entity's OnCreate. Taken away when the test ends, the way the game removes it, found again by its
-- place, since a chunk that unloaded and loaded meanwhile holds a new copy.
handler("digesterPlace", function(player, args, defer)
    local square = Helpers.squareAt(args)
    if not square then
        return nil, "a loaded square for a digester"
    end
    local sprite = RenewableEnergy.Sprites.digester
    for part in string.gmatch(args.tile, "[^.]+") do
        sprite = sprite[part]
    end
    local thumpable = IsoThumpable.new(getCell(), square, sprite, false, nil)
    square:AddSpecialObject(thumpable)
    RenewableEnergy.DigesterSystem.OnCreate({ thumpable = thumpable })
    thumpable:transmitCompleteItemToClients()
    defer(function()
        local _, object = digesterAt(args)
        if object then
            Helpers.removeObject(object)
        end
    end)
    return {}
end)

-- Sets the record's fields `args.fields` (DigesterObject.SAVED_FIELDS), then shows and sends what
-- changed.
handler("digesterSet", function(player, args)
    local record, _, missing = digesterAt(args)
    if not record then return nil, missing end
    for key, value in pairs(args.fields) do
        record[key] = value
    end
    record.lastHour = getGameTime():getWorldAgeHours()
    record:afterChange()
    return {}
end)

-- Puts `args.items` ({ type, count, rotten }) in the digester's hopper, past its filter, as a
-- player's transfer would.
handler("digesterFill", function(player, args)
    local _, object, missing = digesterAt(args)
    if not object then return nil, missing end
    local container = object:getContainer()
    for _, entry in ipairs(args.items) do
        for _ = 1, entry.count or 1 do
            local item = container:AddItem(entry.type)
            if item and entry.rotten then
                item:setAge(item:getOffAgeMax() + 1)
            end
            sendAddItemToContainer(container, item)
        end
    end
    return {}
end)

-- Runs the digester `args.hours` in hour steps at the air temperature `args.air` (°C), feeding
-- from its hopper as its pass does, without moving the clock.
handler("digesterRun", function(player, args)
    local record, object, missing = digesterAt(args)
    if not record then return nil, missing end
    local container = object:getContainer()
    local left = args.hours
    while left > 0 do
        local step = math.min(1, left)
        record:meter(step, container)
        record:step(step, args.air)
        left = left - step
    end
    record:snapshotHopper(container)
    record.lastHour = getGameTime():getWorldAgeHours()
    record:afterChange()
    return {}
end)

-- The record as plain values, plus what only the authority sees: the ghosts its stink counts, its
-- building's toxicity, its overlays and its hopper's items.
handler("digesterRead", function(player, args)
    local record, object, missing = digesterAt(args)
    if not record then return nil, missing end
    local state = {}
    for _, key in ipairs(RenewableEnergy.DigesterObject.SAVED_FIELDS) do
        if type(record[key]) ~= "table" then
            state[key] = record[key]
        end
    end
    local building = object:getSquare():getBuilding()
    state.capacity = record:capacity()
    state.torn = record:isTorn()
    state.stink = record:stinkScore()
    state.ghosts = RenewableEnergy.Stink.counted(record:key())
    state.toxic = building ~= nil and building:isToxic()
    state.sprite = object:getSprite():getName()
    state.overlays = Helpers.overlaysOf(object)
    state.containerCapacity = object:getContainer():getCapacity()
    state.hopperItems = object:getContainer():getItems():size()
    state.summary = record:buildSummary()
    return state
end)

-- Brings the digester at x, y, z up to now as its pass does, as though `args.hours` had passed
-- since its last pass, loaded or not. Answers what it holds by its record alone.
handler("digesterCatchUp", function(player, args)
    local record = RenewableEnergy.Digester.serverSystem:getLuaObjectAt(args.x, args.y, args.z)
    if not record then
        return nil, "a digester record at " .. args.x .. "," .. args.y
    end
    record.lastHour = getGameTime():getWorldAgeHours() - args.hours
    record:update()
    local eaten = 0
    for _ in pairs(record.eaten) do
        eaten = eaten + 1
    end
    return { loaded = record:getIsoObject() ~= nil, hopper = #record.hopper, eaten = eaten, potential = record.potential }
end)

-- Gas lines -------------------------------------------------------------------------------------

local function generatorOn(args)
    local square = Helpers.squareAt(args)
    local generator = square and RenewableEnergy.findObjectOn(square, RenewableEnergy.GasKit.isGenerator)
    if not generator then
        return nil, "a generator at " .. tostring(args.x) .. "," .. tostring(args.y)
    end
    return generator
end

-- The generator at x, y, z: whether it runs, its fuel, its kit's state and overlays, and whether
-- the pass lists it.
handler("gasRead", function(player, args)
    local generator, missing = generatorOn(args)
    if not generator then return nil, missing end
    local GasKit = RenewableEnergy.GasKit
    local state = GasKit.stateOf(generator)
    local copy
    if state then
        copy = {}
        for key, value in pairs(state) do
            if type(value) ~= "table" then
                copy[key] = value
            end
        end
        copy.connected = state.source ~= nil
    end
    local key = generator:getX() .. "," .. generator:getY() .. "," .. generator:getZ()
    return {
        running = generator:isActivated(), fuel = generator:getFuel(), state = copy,
        listed = ModData.getOrCreate(RenewableEnergy.GasLines.MOD_DATA)[key] ~= nil,
        overlays = Helpers.overlaysOf(generator),
    }
end)

-- Sets the generator's fuel (`args.fuel`, as pouring petrol in does) and switches it on or off
-- (`args.running`), as a player does.
handler("gasGenerator", function(player, args)
    local generator, missing = generatorOn(args)
    if not generator then return nil, missing end
    if args.fuel then
        generator:setFuel(args.fuel)
    end
    if args.running ~= nil then
        generator:setActivated(args.running)
    end
    return {}
end)

-- Runs the gas pass as though `args.hours` had passed since the generator's last.
handler("gasPass", function(player, args)
    local generator, missing = generatorOn(args)
    if not generator then return nil, missing end
    local state = RenewableEnergy.GasKit.stateOf(generator)
    if state then
        state.lastHour = getGameTime():getWorldAgeHours() - args.hours
    end
    RenewableEnergy.GasLines.updateAll()
    return {}
end)

-- Sets the watts a generator carries on gas to `args.watts` until the test ends.
handler("gasCap", function(player, args, defer)
    local GasKit = RenewableEnergy.GasKit
    local cap = GasKit.CAP_W
    GasKit.CAP_W = args.watts
    defer(function() GasKit.CAP_W = cap end)
    return {}
end)
