-- What the authority's test handlers (RenewableEnergyTestServer*.lua, through
-- PZHarness.Test.server) share. They build and read what exists or changes only where the authority
-- runs it. Single player runs the handlers in the same Lua state, so the tests use them in both
-- modes. Server Lua loads after client Lua, and the mod's server files are empty on a multiplayer
-- client, so the handlers look the mod up when they run. Every answer is plain values, which cross
-- the network.
--
-- Named to sort before the handler files, so that a --stay rerun loads it again (RELOAD_FILES)
-- before the files that require it.

require "PZHarness/ServerHandlers"
require "PZHarness/Checks"
require "PZHarness/Fixtures"

local Helpers = {}

--- Registers the server check `name`, which only reads the authority's state and answers
--- { failures = { message, ... } }, which the test expects to be empty
--- (RenewableEnergyTest.expectNoFailures). `fn(expect, expectNear, player, args, defer)` records
--- what it finds wrong through the PZHarness.Checks.new pair; it may instead return what is
--- missing, which fails the test as a handler's `nil, missing` does.
function Helpers.check(name, fn)
    PZHarness.serverHandler(name, function(player, args, defer)
        local expect, expectNear, failures = PZHarness.Checks.new()
        local missing = fn(expect, expectNear, player, args, defer)
        if missing then
            return nil, missing
        end
        return { failures = failures }
    end)
end

--- Defers `undo` for a handler that changes shared state, and returns the function that runs it
--- now, which the handler calls when done. Being deferred too, it still runs when the handler
--- throws first (the harness unwinds a failed call at once). It runs once either way.
function Helpers.deferOnce(defer, undo)
    local done = false
    local function once()
        if done then
            return
        end
        done = true
        undo()
    end
    defer(once)
    return once
end

--- Saves the mod's sandbox options `names` for a handler that changes them, and returns the
--- function that puts them back and then calls `reapply`, if given, to rebuild what the game made
--- from them; Helpers.deferOnce says when it runs.
function Helpers.saveOptions(defer, names, reapply)
    local options, saved = SandboxVars.RenewableEnergy, {}
    for _, name in ipairs(names) do
        saved[name] = options[name]
    end
    return Helpers.deferOnce(defer, function()
        for _, name in ipairs(names) do
            options[name] = saved[name]
        end
        if reapply then
            reapply()
        end
    end)
end

-- The game's roll, kept while a test sets its own; and the rolls tests set, so that setting one
-- over another still keeps the game's.
local gameRoll
local setRolls = setmetatable({}, { __mode = "k" })

--- Sets what Chance.roll gives until the test ends: `rolls` a number, every roll; or a list, the
--- next rolls in order, and an error once they run out, so a draw the test didn't expect shows.
--- The error puts the game's roll back first, so the draws after it, a pass's or a tick's, roll
--- as usual. Returns the function that puts the game's roll back; Helpers.deferOnce says when it
--- runs.
function Helpers.forceRolls(defer, rolls)
    local Chance = RenewableEnergy.Chance
    if not setRolls[Chance.roll] then
        gameRoll = Chance.roll
    end
    local drawn = 0
    local roll = type(rolls) == "number" and function() return rolls end or function()
        drawn = drawn + 1
        if rolls[drawn] == nil then
            Chance.roll = gameRoll
            error("a roll past the " .. #rolls .. " the test set")
        end
        return rolls[drawn]
    end
    setRolls[roll] = true
    Chance.roll = roll
    return Helpers.deferOnce(defer, function() Chance.roll = gameRoll end)
end

--- The square at `args` ({ x, y, z }), or nil when there is none or it isn't loaded here.
function Helpers.squareAt(args)
    return args and args.x and getSquare(args.x, args.y, args.z)
end

--- The vehicle `args` names ({ id, x, y, z }: RenewableEnergyTest.vehicleArgs; single player
--- finds it by the squares around x, y, z), or nil and what is missing when there is none or it
--- has been taken out of the world.
function Helpers.vehicleAt(args)
    local vehicle = args and PZHarness.Fixtures.vehicleById(args.id, args)
    if not vehicle or vehicle:isRemovedFromWorld() then
        return nil, "vehicle " .. tostring(args and args.id) .. " on the server"
    end
    return vehicle
end

--- The names of the overlays an object's tile shows, in drawing order.
function Helpers.overlaysOf(object)
    local names = {}
    local attached = object and object:getAttachedAnimSprite()
    for i = 0, (attached and attached:size() or 0) - 1 do
        table.insert(names, attached:get(i):getName())
    end
    return names
end

--- The fields `keys` of `source` that aren't tables, as plain values for an answer.
function Helpers.plainFields(source, keys)
    local fields = {}
    for _, key in ipairs(keys) do
        if type(source[key]) ~= "table" then
            fields[key] = source[key]
        end
    end
    return fields
end

--- How many keys `entries` holds; 0 for nil.
function Helpers.count(entries)
    local n = 0
    for _ in pairs(entries or {}) do
        n = n + 1
    end
    return n
end

--- How far under a chance a roll still comes in under it.
Helpers.UNDER = 1e-9

--- Whether `value` lies in `range` ({ min, max }), both ends included.
function Helpers.inRange(value, range)
    return value >= range.min and value <= range.max
end

--- Takes `count` (default all) items of `fullType` (default any type) out of `container` and
--- tells the clients.
function Helpers.emptyContainer(container, fullType, count)
    local items, taken = container:getItems(), 0
    for i = items:size() - 1, 0, -1 do
        if count and taken >= count then
            return
        end
        local item = items:get(i)
        if not fullType or item:getFullType() == fullType then
            container:Remove(item)
            sendRemoveItemFromContainer(container, item)
            taken = taken + 1
        end
    end
end

--- The def of the building nearest x, y on the ground level, within `radius` squares, that
--- `accept(def)`, if given, takes; nil if there is none.
function Helpers.buildingNear(x, y, radius, accept)
    for r = 0, radius do
        for sx, sy in PZHarness.Fixtures.ring(x, y, r) do
            local square = getSquare(sx, sy, 0)
            local building = square and square:getBuilding()
            local def = building and building:getDef()
            if def and (not accept or accept(def)) then
                return def
            end
        end
    end
    return nil
end

local PAMPHLET = "RenewableEnergy.FemaPamphlet"

--- How many of `fullType` (default the pamphlet) each container and each floor holds on the levels
--- of the building `def` that RuralFinds.leaveReading fills: { [container or square] = count }.
function Helpers.readingIn(def, fullType)
    fullType = fullType or PAMPHLET
    local found = {}
    for z = 0, RenewableEnergy.BuildingWatch.HIGHEST_LEVEL do
        for x = def:getX(), def:getX2() - 1 do
            for y = def:getY(), def:getY2() - 1 do
                local square = getSquare(x, y, z)
                local objects = square and square:getObjects()
                for i = 0, (objects and objects:size() or 0) - 1 do
                    local container = objects:get(i):getContainer()
                    if container then
                        found[container] = container:getCountType(fullType)
                    end
                end
                local onFloor = 0
                local items = square and square:getWorldObjects()
                for i = 0, (items and items:size() or 0) - 1 do
                    if items:get(i):getItem():getFullType() == fullType then
                        onFloor = onFloor + 1
                    end
                end
                if onFloor > 0 then
                    found[square] = onFloor
                end
            end
        end
    end
    return found
end

--- All of Helpers.readingIn's `fullType` together.
function Helpers.readingTotal(def, fullType)
    local total = 0
    for _, count in pairs(Helpers.readingIn(def, fullType)) do
        total = total + count
    end
    return total
end

--- Takes out of the building `def` the `fullType` that wasn't there in `before` (Helpers.readingIn).
function Helpers.takeReadingSince(def, fullType, before)
    for holder, count in pairs(Helpers.readingIn(def, fullType)) do
        local extra = count - (before[holder] or 0)
        if extra > 0 then
            if instanceof(holder, "IsoGridSquare") then
                local items = holder:getWorldObjects()
                for i = items:size() - 1, 0, -1 do
                    local object = items:get(i)
                    if extra > 0 and object:getItem():getFullType() == fullType then
                        if isServer() then
                            holder:transmitRemoveItemFromSquare(object)
                        end
                        holder:removeWorldObject(object)
                        extra = extra - 1
                    end
                end
            else
                Helpers.emptyContainer(holder, fullType, extra)
            end
        end
    end
end

-- The kinds of Global Object System record the tests build and drive (RenewableEnergyTestLibGas.lua):
-- the shared module that owns the tile and which tiles are its, the server object and system, the
-- containers by the names the tests use, and what a read adds to the saved fields, from the record
-- and, while loaded, its tile: a digester's adds the air its square has now (`air`).
local KINDS = {
    digester = {
        owner = function() return RenewableEnergy.Digester end,
        isObject = function(object) return RenewableEnergy.Digester.isDigester(object) end,
        object = function() return RenewableEnergy.DigesterObject end,
        system = function() return RenewableEnergy.DigesterSystem end,
        containers = function(object) return { hopper = object:getContainer() } end,
        extras = function(record, object, state)
            state.capacity = record:capacity()
            state.torn = record:isTorn()
            state.acidLimit = record:acidLimit()
            state.ghosts = RenewableEnergy.Stink.counted(record:key())
            state.eaten = Helpers.count(record.eaten)
            state.snapshot = #record.hopper
            if object then
                state.containerCapacity = object:getContainer():getCapacity()
                state.hopperItems = object:getContainer():getItems():size()
                state.air = getClimateManager():getAirTemperatureForSquare(object:getSquare())
            end
        end,
    },
    gasifier = {
        owner = function() return RenewableEnergy.Gasifier end,
        isObject = function(object) return RenewableEnergy.Gasifier.isGasifier(object) end,
        object = function() return RenewableEnergy.GasifierObject end,
        system = function() return RenewableEnergy.GasifierSystem end,
        containers = function(object)
            local Gasifier = RenewableEnergy.Gasifier
            return { hopper = Gasifier.hopperOf(object), filter = Gasifier.filterOf(object) }
        end,
        extras = function(record, object, state)
            if object then
                local Gasifier = RenewableEnergy.Gasifier
                state.hopperKg = Gasifier.hopperKg(Gasifier.hopperOf(object))
                state.containers = object:getContainerCount()
                state.clean, state.tarry = Gasifier.filterCounts(Gasifier.filterOf(object))
            end
        end,
    },
}
Helpers.RECORD_KINDS = KINDS

--- The record of kind `args.kind` at x, y, z and its tile, or nil, nil and what is missing.
function Helpers.recordAt(args)
    local kind = KINDS[args.kind]
    if not kind then
        return nil, nil, "a record kind " .. tostring(args.kind)
    end
    local square = Helpers.squareAt(args)
    local object = square and RenewableEnergy.findObjectOn(square, kind.isObject)
    local record = object and kind.owner().recordOf(object)
    if not record then
        return nil, nil, "a " .. args.kind .. " at " .. tostring(args.x) .. "," .. tostring(args.y)
    end
    return record, object
end

--- Builds a record of RECORD_KINDS kind `kind` on the Sprites[kind] tile `tile` (a dotted path:
--- "barrel.MetalDrum", "standard") on `square` as the build menu does, through the builder rural
--- finds use (WorldSpawns.buildEntity), which sends it to the clients. Returns the thumpable, or nil and
--- what is missing.
function Helpers.placeRecord(kind, tile, square)
    local spec = KINDS[kind]
    if not (spec and square) then
        return nil, "a loaded square for a " .. tostring(kind)
    end
    local sprite = RenewableEnergy.Sprites[kind]
    for part in string.gmatch(tile, "[^.]+") do
        sprite = sprite and sprite[part]
    end
    if type(sprite) ~= "string" then
        return nil, "the " .. kind .. " tile " .. tostring(tile)
    end
    return RenewableEnergy.WorldSpawns.buildEntity(square, sprite, spec.system().OnCreate)
end

--- The record of kind `kind` as plain values: its saved fields, its kind's extras and, while its
--- tile is loaded (`object`), its building's toxicity, tile, overlays and the summary this side
--- builds.
function Helpers.recordState(kind, record, object)
    local spec = KINDS[kind]
    local state = Helpers.plainFields(record, spec.object().SAVED_FIELDS)
    state.loaded = object ~= nil
    if object then
        local building = object:getSquare():getBuilding()
        state.toxic = building ~= nil and building:isToxic()
        state.sprite = object:getSprite():getName()
        state.overlays = Helpers.overlaysOf(object)
        state.summary = spec.owner().currentSummary(object)
    end
    spec.extras(record, object, state)
    return state
end

return Helpers
