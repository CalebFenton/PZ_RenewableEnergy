-- What the authority's world test handlers (RenewableEnergyTestServer*.lua, through
-- PZHarness.Test.server) share beyond the harness's server helpers and RenewableEnergyTestKinds:
-- the containers they empty and the buildings the world's rolls fill. Single player runs the
-- handlers in the same Lua state, so the tests use them in both modes. Every answer is plain
-- values, which cross the network.
--
-- Named to sort before the handler files, so that a --stay rerun loads it again (RELOAD_FILES)
-- before the files that require it.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
local Items = require "cf_commonlib/Items"
local Kinds = require "RenewableEnergy/Debug/RenewableEnergyTestKinds"
local BuildingWatch = require "RenewableEnergy/World/BuildingWatch"

local Helpers = {}
local Fixtures = PZHarness.Fixtures

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

--- The roll of the building `def` that the ModData table `modDataName` holds (by BuildingWatch.key).
function Helpers.buildingRoll(modDataName, def)
    return ModData.getOrCreate(modDataName)[BuildingWatch.key(def)]
end

--- Keeps the roll of the building `def` that the ModData table `modDataName` holds (by
--- BuildingWatch.key) as it stands now, and puts it back when the test ends.
function Helpers.keepBuildingRoll(modDataName, def, defer)
    local store, key = ModData.getOrCreate(modDataName), BuildingWatch.key(def)
    local saved = store[key]
    if type(saved) == "table" then
        local copy = {}
        for field, value in pairs(saved) do
            copy[field] = value
        end
        saved = copy
    end
    defer(function() store[key] = saved end)
end

--- Forgets the roll of the building `def` that the ModData table `modDataName` holds until the
--- test ends (Helpers.keepBuildingRoll), so that it can be rolled again.
function Helpers.forgetBuildingRoll(modDataName, def, defer)
    Helpers.keepBuildingRoll(modDataName, def, defer)
    ModData.getOrCreate(modDataName)[BuildingWatch.key(def)] = nil
end

--- How many ground squares within BuildingWatch.REACH of the building `def` hold a `kind`
--- (Kinds.findOn), leaving out the square `except` ({ x, y }), if given.
function Helpers.findsAround(def, kind, except)
    local count = 0
    BuildingWatch.eachSquare(def, BuildingWatch.REACH, 0, function(_, x, y)
        if not (except and x == except[1] and y == except[2]) and Kinds.findOn({ x = x, y = y, z = 0, kind = kind }) then
            count = count + 1
        end
    end)
    return count
end

--- How many of `fullType` each container and each floor holds on the levels of the building `def`
--- that RuralFinds.leaveReading fills: { [container or square] = count }.
function Helpers.readingIn(def, fullType)
    local found = {}
    for z = 0, BuildingWatch.HIGHEST_LEVEL do
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

return Helpers
