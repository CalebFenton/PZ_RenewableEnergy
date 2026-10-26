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
require "PZHarness/Fixtures"
local Items = require "cf_commonlib/Items"
local Squares = require "cf_commonlib/Squares"

local Helpers = {}
local need, Fixtures = PZHarness.need, PZHarness.Fixtures

-- The game's roll, kept while a test sets its own; and the rolls tests set, so that setting one
-- over another still keeps the game's.
local gameRoll
local setRolls = setmetatable({}, { __mode = "k" })

--- Sets what Chance.roll gives until the test ends: `rolls` a number, every roll; or a list, the
--- next rolls in order, and an error once they run out, so a draw the test didn't expect shows.
--- The error puts the game's roll back first, so the draws after it, a pass's or a tick's, roll
--- as usual. Returns the function that puts the game's roll back; Fixtures.deferOnce
--- says when it runs.
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
    return Fixtures.deferOnce(defer, function() Chance.roll = gameRoll end)
end

--- Runs fn(...) with the rolls `rolls` (Helpers.forceRolls), then puts the game's roll back.
--- Returns what fn returns.
function Helpers.withRolls(defer, rolls, fn, ...)
    local restore = Helpers.forceRolls(defer, rolls)
    local results = { fn(...) }
    restore()
    return unpack(results)
end

--- Runs run(trial) for each of `trials` with the rolls rollsOf(trial) gives (Helpers.withRolls).
--- Returns what each run returned, in order.
function Helpers.eachTrial(defer, trials, rollsOf, run)
    local results = {}
    for i, trial in ipairs(trials) do
        results[i] = Helpers.withRolls(defer, rollsOf(trial), run, trial)
    end
    return results
end

--- The loaded square at `at` ({ x, y, z }), or the handler ends as missing it.
function Helpers.squareAt(at)
    return need(Fixtures.squareAt(at), "the square " .. tostring(at and at.x) .. "," .. tostring(at and at.y) .. ","
        .. tostring(at and at.z) .. " loaded on the server")
end

--- The server's record of the bank at `position` ({ x, y, z }), loaded or not, or the handler ends
--- as missing it.
function Helpers.bankRecord(position)
    return need(position and RenewableEnergy.PowerBank.serverSystem:getLuaObjectAt(position.x, position.y, position.z),
        "the bank's record on the server")
end

--- The server's record of the bank at `position` and its tile, or the handler ends as missing them.
function Helpers.bankAt(position)
    local record = Helpers.bankRecord(position)
    return record, need(record:getIsoObject(), "the bank's tile on the server")
end

--- The vehicle `args` names ({ id, x, y, z }: RenewableEnergyTest.vehicleArgs; single player
--- finds it by the squares around x, y, z), or the handler ends as missing it when there is none or
--- it has been taken out of the world.
function Helpers.vehicleAt(args)
    local vehicle = args and Fixtures.vehicleById(args.id, args)
    return need(vehicle and not vehicle:isRemovedFromWorld() and vehicle,
        "vehicle " .. tostring(args and args.id) .. " on the server")
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

--- `roll` as a trial gives it: "under" or "at" for just under or at `chance`, worked out here so
--- the roll is exactly the chance, else the number itself.
function Helpers.trialRoll(roll, chance)
    return roll == "under" and chance - Helpers.UNDER or roll == "at" and chance or roll
end

--- Whether `value` lies in `range` ({ min, max }), both ends included.
function Helpers.inRange(value, range)
    return value >= range.min and value <= range.max
end

--- The conditions the WorldSpawns wear profile `wear` gives a find, from its lowest roll to its
--- highest: no better than new.
function Helpers.wearRange(wear)
    return { min = wear.mean - wear.halfWidth, max = math.min(100, wear.mean + wear.halfWidth) }
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
            Items.removeItem(item)
            taken = taken + 1
        end
    end
end

--- The items in `container` (nil for none) as plain values, in container order: { type, id,
--- condition, uses, charge (a battery's) }.
function Helpers.itemsOf(container)
    local Battery, list = RenewableEnergy.Battery, {}
    local items = container and container:getItems()
    for i = 0, (items and items:size() or 0) - 1 do
        local item = items:get(i)
        table.insert(list, { type = item:getFullType(), id = item:getID(), condition = item:getCondition(),
            uses = item:getCurrentUsesFloat(), charge = Battery.isBattery(item) and Battery.getCharge(item) or nil })
    end
    return list
end

--- The items lying on `squares` (a list), as a set of their world objects, each to its square.
function Helpers.worldItems(squares)
    local found = {}
    for _, square in ipairs(squares) do
        local objects = square:getWorldObjects()
        for i = 0, objects:size() - 1 do
            found[objects:get(i)] = square
        end
    end
    return found
end

--- The keys of the set `now` that the set `before` lacks, as a list.
function Helpers.newSince(before, now)
    local new = {}
    for key in pairs(now) do
        if not before[key] then
            table.insert(new, key)
        end
    end
    return new
end

--- The def of the building nearest x, y on the ground level, within `radius` squares, that
--- `accept(def)`, if given, takes; nil if there is none.
function Helpers.buildingNear(x, y, radius, accept)
    for r = 0, radius do
        for sx, sy in Fixtures.ring(x, y, r) do
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

--- The roll of the building `def` that the ModData table `modDataName` holds (by BuildingWatch.key).
function Helpers.buildingRoll(modDataName, def)
    return ModData.getOrCreate(modDataName)[RenewableEnergy.BuildingWatch.key(def)]
end

--- Keeps the roll of the building `def` that the ModData table `modDataName` holds (by
--- BuildingWatch.key) as it stands now, and puts it back when the test ends. Returns the table and
--- the building's key, for a caller that forgets the roll.
function Helpers.keepBuildingRoll(modDataName, def, defer)
    local store, key = ModData.getOrCreate(modDataName), RenewableEnergy.BuildingWatch.key(def)
    local saved = store[key]
    if type(saved) == "table" then
        local copy = {}
        for field, value in pairs(saved) do
            copy[field] = value
        end
        saved = copy
    end
    defer(function() store[key] = saved end)
    return store, key
end

--- How many ground squares within BuildingWatch.REACH of the building `def` hold an object that
--- `isFind(object)` takes, leaving out the square `except` ({ x, y }), if given.
function Helpers.findsAround(def, isFind, except)
    local reach, count = RenewableEnergy.BuildingWatch.REACH, 0
    for x = def:getX() - reach, def:getX2() + reach - 1 do
        for y = def:getY() - reach, def:getY2() + reach - 1 do
            if not (except and x == except[1] and y == except[2]) and Squares.findObjectOn(getSquare(x, y, 0), isFind) then
                count = count + 1
            end
        end
    end
    return count
end

--- How many of `fullType` each container and each floor holds on the levels of the building `def`
--- that RuralFinds.leaveReading fills: { [container or square] = count }.
function Helpers.readingIn(def, fullType)
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
                        Fixtures.removePlaced(object)
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

-- What each kind of object the tests find by kind (Helpers.findOn) is: the mod's own lookup on a
-- square, or a test on each object.
local FIND = {
    bank = function(square) return RenewableEnergy.PowerBank.findOn(square) end,
    source = function(square) return RenewableEnergy.Sources.findOn(square) end,
    charger = function(square) return Squares.findObjectOn(square, RenewableEnergy.SolarCellCharger.isCharger) end,
    gardenLight = function(square) return RenewableEnergy.SolarGardenLight.findOn(square) end,
    treadmill = function(square) return RenewableEnergy.Treadmill.findOn(square) end,
    wiredTreadmill = function(square) return Squares.findObjectOn(square, RenewableEnergy.Treadmill.isWiredTile) end,
    generator = function(square) return Squares.findObjectOn(square, RenewableEnergy.isGenerator) end,
}
for name, kind in pairs(KINDS) do
    FIND[name] = function(square) return Squares.findObjectOn(square, kind.isObject) end
end

--- The object on the square at `at` ({ x, y, z }) drawn as `at.sprite`, else of the kind `at.kind`
--- (a FIND key), or nil, also while the square isn't loaded.
function Helpers.findOn(at)
    local square = Fixtures.squareAt(at)
    if at.sprite then
        return Fixtures.objectWithSprite(square, at.sprite)
    end
    return FIND[at.kind](square)
end

--- Helpers.findOn's object, or the handler ends as missing it.
function Helpers.find(at)
    return need(Helpers.findOn(at), "a " .. tostring(at.sprite or at.kind) .. " at " .. tostring(at.x) .. ","
        .. tostring(at.y) .. "," .. tostring(at.z) .. " on the server")
end

--- The record of kind `args.kind` at x, y, z and its tile, or the handler ends as missing them.
function Helpers.recordAt(args)
    local object = Helpers.find(args)
    return need(KINDS[args.kind].owner().recordOf(object), "the record of the " .. args.kind .. " on the server"), object
end

--- Builds a record of RECORD_KINDS kind `kind` on the Sprites[kind] tile `tile` (a dotted path:
--- "barrel.MetalDrum", "standard") on `square` as the build menu does, through the builder rural
--- finds use (WorldSpawns.buildEntity), which sends it to the clients. Returns the thumpable.
function Helpers.placeRecord(kind, tile, square)
    local sprite = RenewableEnergy.Sprites[kind]
    for part in string.gmatch(tile, "[^.]+") do
        sprite = sprite and sprite[part]
    end
    need(type(sprite) == "string", "the " .. kind .. " tile " .. tostring(tile))
    return RenewableEnergy.WorldSpawns.buildEntity(square, sprite, KINDS[kind].system().OnCreate)
end

--- The record of kind `kind` as plain values: its saved fields, its kind's extras and, while its
--- tile is loaded (`object`), its building's toxicity, tile, overlays and the summary this side
--- builds.
function Helpers.recordState(kind, record, object)
    local spec = KINDS[kind]
    local state = Fixtures.fieldsOf(record, spec.object().SAVED_FIELDS)
    state.loaded = object ~= nil
    if object then
        local building = object:getSquare():getBuilding()
        state.toxic = building ~= nil and building:isToxic()
        state.sprite = object:getSprite():getName()
        state.overlays = Fixtures.overlaysOf(object)
        state.summary = spec.owner().currentSummary(object)
    end
    spec.extras(record, object, state)
    return state
end

return Helpers
