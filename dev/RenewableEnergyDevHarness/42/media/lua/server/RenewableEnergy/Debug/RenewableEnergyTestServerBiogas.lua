-- The authority's half of the biogas tests: the stink, the digesters, propane on the floor, and the
-- Global Object System records both digesters and gasifiers are (Helpers.recordAt), which the wood
-- gas tests drive too.
-- Only registers handlers, so a --stay rerun loads it again (RELOAD_FILES);
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

-- What the authority's copy of the character smells: its noxious smell moodle level and corpse
-- sickness rate; the corpses and moving objects on the square at x, y, z, which ghosts never join;
-- what is left of the filter of a worn gas mask, if any; and the corpse counts at which the game's
-- smell levels start (Stink.LEVEL_CORPSES), which a multiplayer client's Lua doesn't have.
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
    local levels = {}
    for i, count in ipairs(RenewableEnergy.Stink.LEVEL_CORPSES) do
        levels[i] = count
    end
    return {
        level = player:getMoodles():getMoodleLevel(MoodleType.NOXIOUS_SMELL),
        rate = player:getCorpseSicknessRate(),
        bodies = square and square:getDeadBodys():size() or -1,
        objects = square and square:getMovingObjects():size() or -1,
        mask = mask,
        levels = levels,
    }
end)

-- The stink score's edges (Digester.SMELL_SCORES): none just below the first, then each smell
-- level's corpses from its edge up to just below the next.
Helpers.check("digesterCorpsesFor", function(expect)
    local corpsesFor = RenewableEnergy.DigesterObject.corpsesFor
    local levels, scores = RenewableEnergy.Stink.LEVEL_CORPSES, RenewableEnergy.Digester.SMELL_SCORES
    local below = 0.001
    local function band(score, lowest, under)
        local corpses = corpsesFor(score)
        expect(corpses >= lowest and (not under or corpses < under),
            "a stink score of " .. score .. " smells like " .. corpses .. " corpses")
    end
    band(scores[1] - below, 0, 1)
    for i, score in ipairs(scores) do
        band(score, levels[i], levels[i + 1])
        if scores[i + 1] then
            band(scores[i + 1] - below, levels[i], levels[i + 1])
        end
    end
end)

-- Records (digesters and gasifiers) -----------------------------------------------------------------

-- Builds the record of kind `args.kind` on the Sprites[kind] tile `args.tile` at x, y, z as the
-- build menu does (Helpers.placeRecord). Taken away when the test ends, the way the game removes
-- it, found again by its place, since a chunk that unloaded and loaded meanwhile holds a new copy.
handler("recordPlace", function(player, args, defer)
    local thumpable, missing = Helpers.placeRecord(args.kind, args.tile, Helpers.squareAt(args))
    if not thumpable then return nil, missing end
    thumpable:transmitCompleteItemToClients()
    defer(function() Helpers.removeObject(select(2, Helpers.recordAt(args)) or thumpable) end)
    return {}
end)

-- Takes away, when the test ends, whatever record of kind `args.kind` the test builds at x, y, z by
-- other means (the build menu).
handler("recordTrack", function(player, args, defer)
    defer(function()
        local _, object = Helpers.recordAt(args)
        if object then
            Helpers.removeObject(object)
        end
    end)
    return {}
end)

-- Sets the record's fields `args.fields` as of now, and each field of `args.ago` ({ [field] =
-- hours }) to the world hour that many hours before now, then shows and sends what changed. Each
-- must be one of its SAVED_FIELDS, the record's state: a misspelled one would sit beside the field
-- the code reads, and change nothing.
handler("recordSet", function(player, args)
    local record, _, missing = Helpers.recordAt(args)
    if not record then return nil, missing end
    local saved = {}
    for _, field in ipairs(Helpers.RECORD_KINDS[args.kind].object().SAVED_FIELDS) do
        saved[field] = true
    end
    for _, fields in ipairs({ args.fields or {}, args.ago or {} }) do
        for key in pairs(fields) do
            if not saved[key] then
                return nil, "a saved field " .. tostring(key) .. " of a " .. args.kind
            end
        end
    end
    local now = getGameTime():getWorldAgeHours()
    for key, value in pairs(args.fields or {}) do
        record[key] = value
    end
    for key, hours in pairs(args.ago or {}) do
        record[key] = now - hours
    end
    record.lastHour = now
    record:afterChange()
    return {}
end)

-- Puts `args.items` ({ [container name] = { { type, count, rotten } } }, the names of
-- Helpers.RECORD_KINDS) in the record's containers, past their filters, as a player's transfer
-- would: the record hears of it only in its next pass.
handler("recordFill", function(player, args)
    local _, object, missing = Helpers.recordAt(args)
    if not object then return nil, missing end
    local containers = Helpers.RECORD_KINDS[args.kind].containers(object)
    for name, entries in pairs(args.items) do
        local container = containers[name]
        if not container then
            return nil, "a " .. name .. " on the " .. args.kind
        end
        for _, entry in ipairs(entries) do
            for _ = 1, entry.count or 1 do
                local item = container:AddItem(entry.type)
                if item and entry.rotten then
                    item:setAge(item:getOffAgeMax() + 1)
                end
                if item then
                    sendAddItemToContainer(container, item)
                end
            end
        end
    end
    return {}
end)

-- Brings the record of kind `args.kind` at x, y, z up to now as its pass does, as though
-- `args.hours` had passed since its last, its chunk loaded or not. Answers its state
-- (Helpers.recordState), from the record alone while unloaded.
handler("recordAge", function(player, args)
    local kind = Helpers.RECORD_KINDS[args.kind]
    local record = kind and kind.owner().recordAt(args.x, args.y, args.z)
    if not record then
        return nil, "a " .. tostring(args.kind) .. " record at " .. args.x .. "," .. args.y
    end
    record.lastHour = getGameTime():getWorldAgeHours() - args.hours
    record:update()
    return Helpers.recordState(args.kind, record, record:getIsoObject())
end)

-- The record's state (Helpers.recordState).
handler("recordRead", function(player, args)
    local record, object, missing = Helpers.recordAt(args)
    if not record then return nil, missing end
    return Helpers.recordState(args.kind, record, object)
end)

-- Takes the record's tile away the way the game does, as a sledgehammer or a pickup would.
handler("recordRemove", function(player, args)
    local _, object, missing = Helpers.recordAt(args)
    if not object then return nil, missing end
    Helpers.removeObject(object)
    return {}
end)

-- Digesters -------------------------------------------------------------------------------------

-- Runs the digester at x, y, z for `args.hours` at the air temperature `args.air` (°C), feeding
-- from its hopper as its pass does, without moving the clock.
handler("digesterRun", function(player, args)
    local record, object, missing = Helpers.recordAt({ kind = "digester", x = args.x, y = args.y, z = args.z })
    if not record then return nil, missing end
    record:run(args.hours, object:getContainer(), args.air)
    record.lastHour = getGameTime():getWorldAgeHours()
    record:afterChange()
    return {}
end)

-- Has the job `args.job` of the job module RenewableEnergy[args.module] (DigesterJobs, GasHeater,
-- ...) give `args.amount` XP of the perk `args.perk` once done, until the test ends: for a job
-- whose row names none, to see whether its feature gives what its row says.
handler("gasJobXp", function(player, args, defer)
    local Jobs = RenewableEnergy[args.module]
    local row = Jobs and Jobs.JOBS and Jobs.JOBS[args.job]
    if not row then
        return nil, "the job " .. tostring(args.job) .. " of " .. tostring(args.module)
    end
    local was = row.xp
    row.xp = { perk = args.perk, amount = args.amount }
    defer(function() row.xp = was end)
    return {}
end)

-- Propane --------------------------------------------------------------------------------------

-- Drops an `args.type` holding `args.uses` (its share of full) on the floor of the square at x, y,
-- z, as a player dropping it does, for everyone to see. Taken away when the test ends.
handler("floorItem", function(player, args, defer)
    local square = Helpers.squareAt(args)
    local item = square and instanceItem(args.type)
    if not item then
        return nil, "a loaded square and an item " .. tostring(args.type)
    end
    if args.uses then
        item:setCurrentUsesFloat(args.uses)
    end
    square:AddWorldInventoryItem(item, 0.5, 0.5, 0)
    defer(function()
        local world = item:getWorldItem()
        if world and world:getSquare() then
            world:getSquare():transmitRemoveItemFromSquare(world)
        end
    end)
    return {}
end)
