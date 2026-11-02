require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
local Stash = require "RenewableEnergy/Stash"

-- Stash houses (Stash.lua, StashStocking.lua, MapDefinitions.lua): registered, stocked and mapped on
-- the authority (RenewableEnergyTestServerStash.lua). Where their maps drop is the loot tests'.

local T = RenewableEnergyTest
local test, expect, expectEqual, serverCheck = T.test, T.expect, T.expectEqual, T.serverCheck

-- Every stash house resolves to a building and a room StashSystem can stock.
serverCheck("renewable_energy_world_stash_houses_resolve", "stashHousesResolve")

-- Unless Stash Houses is at None, the stashes join the list StashSystem reads.
test("renewable_energy_world_stash_register_by_option", {
    run = function(self) T.read(self, "stashRegister", nil, "register") end,
    validate = function(self)
        local answer = self.reads.register
        local results, expected = answer.results, answer.houses
        for name, mode in pairs(Stash.MODE) do
            local on = mode ~= Stash.MODE.NONE
            expectEqual("the stashes Stash Houses " .. name .. " listed", results[mode], on and expected or 0)
        end
    end,
})

-- A found stash map shows the stash's stamps and notes, and a map item of the mod's own the area
-- of its stash house, found or not: its Map id is the stash name, which UI/MapDefinitions.lua
-- draws, while vanilla town maps keep their own look. A symbol the game doesn't define or a note
-- without a translation is dropped or shown as its key; the engine annotates the map where loot
-- makes it.
test("renewable_energy_world_stash_maps_show_their_house", {
    run = function(self) T.read(self, "stashMapsAnnotate", nil, "annotate") end,
    validate = function(self)
        local symbols = MapSymbolDefinitions.getInstance()
        for stashMap in pairs(Stash.descriptions) do
            local annotations = stashMap.annotations or {}
            expect(#annotations > 0, stashMap.name .. " has no annotations")
            for _, annotation in ipairs(annotations) do
                if annotation.symbol then
                    expect(symbols:getSymbolById(annotation.symbol) ~= nil,
                        stashMap.name .. ": unknown map symbol " .. annotation.symbol)
                else
                    expect(annotation.text and getTextOrNull(annotation.text) ~= nil,
                        stashMap.name .. ": untranslated note " .. tostring(annotation.text))
                end
            end
            if string.find(stashMap.item, "^RenewableEnergy%.") then
                local map = instanceItem(stashMap.item)
                if expect(map ~= nil and instanceof(map, "MapItem"), stashMap.item .. " is not a map") then
                    expectEqual(stashMap.item .. "'s Map id", map:getMapID(), stashMap.name)
                end
                expect(type(LootMaps.Init[stashMap.name]) == "function", stashMap.name .. " has no map area")
            else
                expect(LootMaps.Init[stashMap.name] == nil, stashMap.name .. " overrides its town map's look")
            end
        end
        T.expectNoFailures(self.reads.annotate)
    end,
})

local RELIST_CASES = {
    { visited = false, read = false, relisted = true },
    { visited = true, read = false, relisted = false },
    { visited = false, read = true, relisted = false },
}

-- A house missing from StashSystem's possible stashes goes back on the list unless someone
-- entered it or read its map, so a map found later leads to a house still untouched. Each house
-- goes through every case and is put back as it was.
test("renewable_energy_world_stash_unfound_relisted", {
    run = function(self) T.read(self, "stashRelist", { cases = RELIST_CASES }, "relist") end,
    validate = function(self)
        for _, result in ipairs(self.reads.relist.results) do
            local case = RELIST_CASES[result.case]
            expect(result.relisted == case.relisted, string.format("%s, %s and %s, was %s", result.name,
                case.visited and "entered" or "never entered", case.read and "its map read" or "its map unread",
                result.relisted and "relisted" or "not relisted"))
        end
    end,
})

-- Stash Houses 3 and 4 stock the houses that have a knownOnStart chance, through the engine, and
-- only those; none of them may then show on the world map as a map already read. The engine's
-- stocking queue can't be read or emptied from Lua, so a house the world's own first tick already
-- queued reads as queued here whatever this roll did.
test("renewable_energy_world_stash_known_on_start_stocks_and_stays_hidden", {
    run = function(self) T.read(self, "stashKnownOnStart", nil, "knownOnStart") end,
    validate = function(self)
        for name, house in pairs(self.reads.knownOnStart.houses) do
            expect(not house.read, name .. " is marked as read")
            expect(house.queued == house.hasChance,
                name .. (house.queued and " was stocked from the start" or " was not stocked from the start"))
        end
    end,
})
