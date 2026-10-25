require "RenewableEnergy/Debug/RenewableEnergyTestLibWorld"
local Stash = require "RenewableEnergy/Stash"

-- Stash houses (Stash.lua, StashHouses.lua, MapDefinitions.lua): registered, stocked and mapped on
-- the authority (RenewableEnergyTestServerStash.lua).

local T = RenewableEnergyTest
local test, expect, serverCheck = T.test, T.expect, T.serverCheck

-- Every stash house resolves to a building and a room StashSystem can stock.
serverCheck("renewable_energy_world_stash_houses_resolve", "stashHousesResolve")

-- Unless Stash Houses is at None, the stashes join the list StashSystem reads, once however often
-- the game loads.
test("renewable_energy_world_stash_register_by_option", {
    run = function(self) T.server(self, "stashRegister") end,
    validate = function(self)
        local answer = self.server.stashRegister
        local results, expected = answer.results, answer.houses
        for name, mode in pairs(Stash.MODE) do
            local result, on = results[mode], mode ~= Stash.MODE.NONE
            expect(result.registered == on, "Stash Houses " .. name .. (on and " did not register" or " registered"))
            expect(result.count == (on and expected or 0),
                "Stash Houses " .. name .. " listed " .. result.count .. " stashes, expected " .. (on and expected or 0))
        end
    end,
})

-- A found stash map shows the stash's stamps and notes. A symbol the game doesn't define or a
-- note without a translation is dropped or shown as its key; the map is annotated where loot
-- makes it.
test("renewable_energy_world_stash_maps_annotated", {
    run = function(self) T.server(self, "stashMapsAnnotate") end,
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
        end
        T.expectNoFailures(self.server.stashMapsAnnotate)
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
    run = function(self) T.server(self, "stashRelist", { cases = RELIST_CASES }) end,
    validate = function(self)
        for _, result in ipairs(self.server.stashRelist.results) do
            local case = RELIST_CASES[result.case]
            expect(result.relisted == case.relisted, string.format("%s, %s and %s, was %s", result.name,
                case.visited and "entered" or "never entered", case.read and "its map read" or "its map unread",
                result.relisted and "relisted" or "not relisted"))
        end
    end,
})

-- Stash Houses 3 and 4 stock the houses that have a knownOnStart chance, through the engine, and
-- only those; none of them may then show on the world map as a map already read.
test("renewable_energy_world_stash_known_on_start_stocks_and_stays_hidden", {
    run = function(self) T.server(self, "stashKnownOnStart") end,
    validate = function(self)
        for name, house in pairs(self.server.stashKnownOnStart.houses) do
            expect(not house.read, name .. " is marked as read")
            expect(house.queued == house.hasChance,
                name .. (house.queued and " was stocked from the start" or " was not stocked from the start"))
        end
    end,
})

-- The prepper's map drops from every survivalist and bandit outfit, and every loot list a map
-- names exists (prepperMapTargets says why each matters).
serverCheck("renewable_energy_world_stash_prepper_map_targets", "prepperMapTargets")

-- A map item of the mod's own shows the area of its stash house, found or not: its Map id is the
-- stash name, which UI/MapDefinitions.lua draws. Vanilla town maps keep their own look.
test("renewable_energy_world_stash_map_items_draw_their_area", {
    validate = function()
        for stashMap in pairs(Stash.descriptions) do
            if string.find(stashMap.item, "^RenewableEnergy%.") then
                local map = instanceItem(stashMap.item)
                if expect(map ~= nil and instanceof(map, "MapItem"), stashMap.item .. " is not a map") then
                    expect(map:getMapID() == stashMap.name, stashMap.item .. " has Map id " .. tostring(map:getMapID()))
                end
                expect(type(LootMaps.Init[stashMap.name]) == "function", stashMap.name .. " has no map area")
            else
                expect(LootMaps.Init[stashMap.name] == nil, stashMap.name .. " overrides its town map's look")
            end
        end
    end,
})

-- Under the Stash Houses settings that hand out maps, every stash's map goes into each of its loot
-- lists once, at the weight it gives there; under the others none does.
test("renewable_energy_world_stash_maps_in_corpse_loot", {
    run = function(self) T.server(self, "stashMapsInCorpseLoot") end,
    validate = function(self)
        local MODE = Stash.MODE
        for _, found in ipairs(self.server.stashMapsInCorpseLoot.found) do
            local wanted = (found.mode == MODE.MAPS or found.mode == MODE.MAPS_AND_STOCKED) and 1 or 0
            local label = "Stash Houses " .. found.mode .. ": " .. found.where
            expect(found.count == wanted, label .. " " .. found.count .. " times")
            expect(wanted == 0 or found.weight == found.rarity, label .. " at weight " .. tostring(found.weight))
        end
    end,
})
