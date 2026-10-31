require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyTestLibCraft"
local Specs = require "RenewableEnergy/Specs"
local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLight"
require "Moveables/ISMoveableDefinitions"
local Digester = require "RenewableEnergy/Biogas/Digester"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local SolarCellCharger = require "RenewableEnergy/Gadgets/SolarCellCharger"
local Sprites = require "RenewableEnergy/Sprites"
local Squares = require "cf_commonlib/Squares"

-- The mod's tiles (Sprites.lua) and how its objects move (Moveables.lua, cf_commonlib PlaceTracker): kinds,
-- overlays, tile properties, rotating, placing, picking up and scrapping. That every tile exists
-- and has a picture is the static check's (dev/check/sprite_tiles.py's tile-picture).

local T = RenewableEnergyTest
local test, expect, expectEqual = T.test, T.expect, T.expectEqual

local MATERIALS = { "wood", "metal" }

-- The items placed and picked up whole on any square: wall panels need a wall, and banks stand
-- only indoors and are the power tests' business.
local PLACED = { "RenewableEnergy.SolarFlat", "RenewableEnergy.SolarFailsafe", SolarCellCharger.ITEM,
    SolarGardenLight.ITEM, "RenewableEnergy.SolarRackWood", "RenewableEnergy.SolarRackMetal" }

-- Every tile Sprites.lua names, as a key or a value at any depth: placed tiles and overlays.
local TILES = {}
local function addTiles(value)
    if type(value) == "table" then
        for key, inner in pairs(value) do
            addTiles(key)
            addTiles(inner)
        end
    elseif type(value) == "string" and value:match("^renewable_energy_0%d_%d+$") then
        TILES[value] = true
    end
end
addTiles(Sprites)

local function properties(spriteName)
    local sprite = getSprite(spriteName)
    return sprite and sprite:getProperties()
end

-- Every tile Sprites.lua names is either a placed tile with a kind or an overlay, never both, so a
-- tile added to Sprites.lua without its place in kindOf or isOverlay fails here.
test("renewable_energy_tiles_are_placed_or_overlays", {
    validate = function()
        for name in pairs(TILES) do
            local kind, overlay = Sprites.kindOf(name) ~= nil, Sprites.isOverlay(name)
            expect(kind ~= overlay, name .. (kind and " has a kind and counts as an overlay" or " has no kind and isn't an overlay"))
        end
    end,
})

-- Whether each tile of `set`, a tile name by facing, turns to every other of the set with the
-- placing cursor.
local function expectTurns(set, what)
    for facing, name in pairs(set) do
        local faces = ISMoveableSpriteProps.new(name):getFaces()
        for otherFacing, otherName in pairs(set) do
            expectEqual(string.format("what %s (%s %s) turns %s to", name, what, facing, otherFacing), faces[otherFacing], otherName)
        end
    end
end

-- The placing cursor turns a rack through all four facings and a wall panel between its two,
-- without turning wood into metal, and every bank and the gas heater through all four facings, as
-- the game's furniture, each staying the same bank, and a lit heater lit.
test("renewable_energy_tiles_rotate", {
    validate = function()
        for _, mount in ipairs({ "rack", "wall" }) do
            for _, material in ipairs(MATERIALS) do
                expectTurns(Sprites[mount][material], material .. " " .. mount)
            end
        end
        for field in pairs(Sprites.bankFill) do
            expectTurns(Sprites[field], field)
        end
        for state, set in pairs(Sprites.gasHeater) do
            expectTurns(set, state .. " gas heater")
        end
    end,
})

-- A fixed tile a save's bank or heater may stand on (Sprites.fixedTiles) is the same bank as its
-- turnable twin, shows the same overlays and picks up as an item that places the twin; an item
-- that still carries the fixed tile places the twin too.
test("renewable_energy_tiles_fixed_tiles_work_as_their_twins", {
    spOnly = "it places with the moveables code on this client, which is the authority only in single player",
    run = function(self)
        local square = T.square(self, { indoors = true }, "a free indoor square for a heater")
        if not square then return end
        local fixed
        for name, twin in pairs(Sprites.fixedTiles) do
            fixed = twin == Sprites.gasHeater.off.S and name or fixed
        end
        ISMoveableSpriteProps.new(fixed):placeMoveableInternal(T.player(), square, instanceItem("RenewableEnergy.GasHeater"), fixed)
        self.twin, self.fixed = T.objectWithSprite(square, Sprites.gasHeater.off.S), T.objectWithSprite(square, fixed)
        for _, placed in ipairs({ self.twin, self.fixed }) do
            T.track(self, placed)
        end
    end,
    validate = function(self)
        expect(self.twin ~= nil and self.fixed == nil, "an item carrying the fixed heater tile placed "
            .. (self.fixed and "the fixed tile" or "no heater"))
        local batteries = { T.L16 }
        for fixed, twin in pairs(Sprites.fixedTiles) do
            expect(PowerBank.bankOfSprite(fixed) == PowerBank.bankOfSprite(twin), fixed .. " is another bank than " .. twin)
            local shown, twinShown = Sprites.bankOverlays(fixed, batteries, 0.5), Sprites.bankOverlays(twin, batteries, 0.5)
            expectEqual("what " .. fixed .. " shows", table.concat(shown, ","), table.concat(twinShown, ","))
            local item = ISMoveableSpriteProps.new(fixed):instanceItem()
            expectEqual("the item " .. fixed .. " picks up as", item and item:getFullType(), properties(twin):get("CustomItem"))
            expectEqual("the tile the item " .. fixed .. " picks up as places", item and item:getWorldSprite(), twin)
        end
    end,
})

-- Each battery in a bank shows in its own slot as its type, and the meter climbs with the charge
-- through every level, from the lowest empty to the highest full. A bank's tile in every facing is
-- that bank, and shows that facing's overlays; facing N or W, away from the camera, its meter
-- shows none.
test("renewable_energy_tiles_bank_overlays", {
    validate = function()
        local levels
        for itemType, bank in pairs(Specs.banks) do
            local cars = {}
            for i = 1, bank.maxBatteries + 1 do
                cars[i] = T.CAR_BATTERY
            end
            for _, facing in ipairs({ "S", "E", "N", "W" }) do
                local tile = Sprites[bank.sprite][facing]
                local what = itemType .. " facing " .. facing
                local found = PowerBank.bankOfSprite(tile)
                expect(found ~= nil and found.fullType == itemType and found.spec == bank,
                    tostring(tile) .. " is not the " .. what)
                local fill = Sprites.bankFill[bank.sprite][facing]
                if expect(fill ~= nil, what .. " has no battery overlays") then
                    local meter = fill.meter
                    expect((meter ~= nil) == (facing == "S" or facing == "E"),
                        what .. (meter and " shows a meter it hides" or " shows no meter"))
                    levels = levels or (meter and #meter)
                    for look, slots in pairs(fill.batteries) do
                        expectEqual(string.format("%s's %s battery slots", what, look), #slots, bank.maxBatteries)
                    end
                    local shown = meter and 1 or 0
                    local full = Sprites.bankOverlays(tile, cars, 1)
                    expect(#full == bank.maxBatteries + shown and full[bank.maxBatteries] == fill.batteries.car[bank.maxBatteries]
                        and (not meter or full[#full] == meter[#meter]), "an overfull " .. what .. " shows " .. table.concat(full, ", "))
                    local mixed = Sprites.bankOverlays(tile, { T.L16, T.DEEP_CYCLE }, 0)
                    expect(#mixed == 2 + shown and mixed[1] == fill.batteries.l16[1] and mixed[2] == fill.batteries.deepCycle[2]
                        and (not meter or mixed[3] == meter[1]), "an empty L-16 and deep-cycle in " .. what .. " show "
                        .. table.concat(mixed, ", "))
                    expect(#Sprites.bankOverlays(tile, {}, 1) == 0, "an empty " .. what .. " shows overlays")
                end
            end
        end
        if not levels then return end
        local seen, last, falls = {}, Sprites.meterLevel(0), nil
        expectEqual("the meter level of no charge", last, 1)
        for percent = 0, 100 do
            local level = Sprites.meterLevel(percent / 100)
            falls = falls or (level < last and percent)
            seen[level], last = true, level
        end
        expect(not falls, "the meter drops a level at " .. tostring(falls) .. "% charge")
        expectEqual("the meter level of a full charge", last, levels)
        for level = 1, levels do
            expect(seen[level], "no charge shows meter level " .. level)
        end
    end,
})

-- Dismantling a bank, in any facing, gives parts back: its material names a scrap definition
-- whose items exist. The definition is in shared Lua, because scrapping completes on the server.
test("renewable_energy_tiles_bank_scraps_to_parts", {
    validate = function()
        for field in pairs(Sprites.bankFill) do
            for facing, tile in pairs(Sprites[field]) do
                local what = field .. " facing " .. facing
                local props = ISMoveableSpriteProps.new(tile)
                expect(props.canScrap, what .. " can't be dismantled")
                local def = ISMoveableDefinitions:getInstance().getScrapDefinition(props.material)
                if expect(def ~= nil, what .. "'s material " .. tostring(props.material) .. " has no scrap definition") then
                    for _, entries in ipairs({ def.returnItemsStatic or {}, def.returnItems or {} }) do
                        for _, entry in ipairs(entries) do
                            expect(getScriptManager():FindItem(entry.returnItem) ~= nil,
                                "dismantling " .. what .. " gives " .. tostring(entry.returnItem) .. ", no item")
                        end
                    end
                end
            end
        end
    end,
})

-- Whether `square` and the squares around it are free, room for any appliance of up to two tiles
-- to stand with a tile on `square`.
local function roomAround(square)
    return not Squares.eachAround(square:getX(), square:getY(), square:getZ(), 1, function(near)
        return not near:isFree(false) or nil
    end)
end

-- Registers test `name`, placing each case's whole object anew and dismantling it by its tile as
-- the server's character does, at the case's `perk` level and forced roll, and expecting the case's
-- count of `fullType` from it. `premise`, if given, checks the tiles first. Each case: what is
-- scrapped, the tile, the level, the roll and the count.
local function scrapTest(name, perk, fullType, cases, premise)
    test(name, {
        run = function(self)
            local square = T.square(self, { accept = roomAround }, "a free square with free squares around it")
            if not square then return end
            for _, case in ipairs(cases) do
                T.step(function() T.setPerk(self, perk, case[3]) end)
                T.forceRoll(self, case[4])
                T.server(self, "placeWhole", T.at(square, { sprite = case[2] }))
                T.read(self, "scrapItems", T.at(square, { sprite = case[2], type = fullType }), case[1])
            end
        end,
        validate = function(self)
            if premise then premise() end
            for _, case in ipairs(cases) do
                local result = self.reads[case[1]]
                expect(result.scrapped, case[1] .. " wasn't dismantled")
                expectEqual(fullType .. " " .. case[1] .. " gave", result.count, case[5])
            end
        end,
    })
end

-- Cutting up a vanilla fridge gives its compressor, which a digester needs to fill propane tanks,
-- on a roll under the character's chance, and one only, though vanilla scraps each of its tiles:
-- 10% at Metalworking 0, 10% more a level, so certain at 9. A stove, which vanilla also cuts up as
-- a Fridge, has none.
-- The wide two-door fridge, two tiles.
local FRIDGE, STOVE = "appliances_refrigeration_01_18", "appliances_cooking_01_0"
scrapTest("renewable_energy_tiles_fridge_scraps_to_compressor", Perks.MetalWelding, Digester.COMPRESSOR, {
    { "a fridge at Metalworking 0, rolling just under 10%", FRIDGE, 0, 0.1 - T.UNDER, 1 },
    { "a fridge at Metalworking 0, rolling 10%", FRIDGE, 0, 0.1, 0 },
    { "a fridge at Metalworking 4, rolling just under 50%", FRIDGE, 4, 0.5 - T.UNDER, 1 },
    { "a stove, on the lowest roll", STOVE, 9, 0, 0 },
}, function()
    expect(getSprite(FRIDGE):getSpriteGrid() ~= nil, "the fridge is one tile, so nothing shows it gives one compressor, not one a tile")
    expect(ISMoveableSpriteProps.new(STOVE).material == "Fridge", "the stove isn't cut up as a Fridge")
end)

-- Dismantling a vanilla microwave gives its transformer, which the homemade inverters are wound on,
-- on a roll under vanilla's chance for the microwave's Electric scrap: 20% at Electricity 0, 10%
-- more a level, so certain at 8. A stove has none.
local MICROWAVE = "appliances_cooking_01_24"
scrapTest("renewable_energy_tiles_microwave_scraps_to_transformer", Perks.Electricity, "RenewableEnergy.MicrowaveTransformer", {
    { "a microwave at Electricity 0, rolling just under 20%", MICROWAVE, 0, 0.2 - T.UNDER, 1 },
    { "a microwave at Electricity 0, rolling 20%", MICROWAVE, 0, 0.2, 0 },
    { "a microwave at Electricity 4, rolling just under 60%", MICROWAVE, 4, 0.6 - T.UNDER, 1 },
    { "a stove, on the lowest roll", STOVE, 10, 0, 0 },
})

-- The tiles' PickUpTool and PlaceTool, Electrician, are a screwdriver and some Electricity.
local function electrician(self)
    T.setPerk(self, Perks.Electricity, 10)
    T.give(self, "screwdriver", { { type = "Base.Screwdriver" } })
end

-- What an item keeps in its modData from item to placed object and back.
local MODULES = {
    { type = "RenewableEnergy.HomemadeSolarModule", condition = 41 },
    { type = "RenewableEnergy.SolarModule", condition = 72, mounted = true, connected = true },
}
local CARRIED = {
    ["RenewableEnergy.SolarRackWood"] = { key = Panel.MODULES_KEY, value = MODULES },
    ["RenewableEnergy.SolarFlat"] = { key = Panel.MODULES_KEY, value = { MODULES[1] } },
    [SolarGardenLight.ITEM] = { key = SolarGardenLight.CHARGE_KEY, value = 2.5 },
}

local function describe(value)
    if type(value) ~= "table" then
        return tostring(value)
    end
    local parts = {}
    for _, module in ipairs(value) do
        table.insert(parts, tostring(module.type) .. "@" .. tostring(module.condition)
            .. (module.mounted and " mounted" or "") .. (module.connected and " connected" or ""))
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- Placed and picked up as a player does, each item of PLACED comes back as that one item, with its
-- modData (CARRIED).
test("renewable_energy_tiles_place_and_pick_up", {
    instant = true,
    run = function(self)
        local square = T.square(self, { bare = true }, "a free outdoor square")
        if not square then return end
        electrician(self)
        self.results = {}
        -- Placing and picking up hold back the calls after them, so what goes out early is the
        -- clear-out after each count and the next item's give, which the square's checks don't see.
        T.batch(function()
            for _, item in ipairs(PLACED) do
                local sprite = getScriptManager():getItem(item):getWorldObjectSprite()
                local carried = CARRIED[item]
                local result = { what = sprite .. " (" .. item .. ")", item = item, expected = carried and describe(carried.value) }
                table.insert(self.results, result)
                local handle = T.placeAsPlayer(self, square, item, sprite, carried and { [carried.key] = carried.value })
                if carried then
                    T.read(self, "PZHarness.objectModData", T.at(square, { sprite = sprite, key = carried.key }), item)
                end
                T.pickUpAsPlayer(self, handle, sprite)
                T.readCarried(self, { item })
                T.step(function()
                    local items = T.carriedItems(self, item)
                    result.removed = T.objectWithSprite(square, sprite) == nil
                    result.returned, result.items = #items, self.reads.carried.total
                    result.pickedUpData = carried and describe(items[1] and items[1].modData[carried.key])
                end)
                T.takeItems(self, nil, item)
            end
        end)
    end,
    validate = function(self)
        for _, r in ipairs(self.results) do
            expect(r.removed, r.what .. " was not picked up")
            -- The screwdriver stays.
            expectEqual("items carried after picking up " .. r.what .. ", the screwdriver too", r.items, 2)
            expectEqual("copies of " .. r.item .. " picking up " .. r.what .. " gave back", r.returned, 1)
            if r.expected then
                expectEqual("what placed " .. r.what .. " holds", describe(self.reads[r.item].value), r.expected)
                expectEqual("what picked-up " .. r.what .. " holds", r.pickedUpData, r.expected)
            end
        end
    end,
})

-- Queues placing a new `itemType` on `square` as the moveables cursor does once turned to
-- `facing`: the action names the item's own tile and the facing, and places that facing's tile
-- (ISMoveablesAction.new). T.placeAsPlayer can't, since it names the tile it places as the item's.
local function placeTurned(self, square, itemType, facing)
    local key = "turned" .. facing
    T.give(self, key, { { type = itemType } })
    T.step(function()
        local p, item = T.player(), self.items[key][1]
        local sprite = item:getWorldSprite()
        T.standNextTo(square)
        if T.need(self, ISMoveableSpriteProps.new(sprite):walkToAndEquip(p, square, "place", sprite), "a way to place a " .. itemType) then
            ISTimedActionQueue.add(ISMoveablesAction:new(p, square, "place", sprite, nil, facing, item, nil))
        end
    end)
end

-- Placed by a player in each facing the cursor turns it to, a bank stands in that facing as a
-- working bank, and picks up as its one item again.
test("renewable_energy_tiles_turned_banks_place_and_pick_up", {
    instant = true,
    run = function(self)
        local squares = T.need(self, T.squares(self, 3, { indoors = true }), "three free indoor squares for banks")
        if not squares then return end
        electrician(self)
        self.results = {}
        local item = "RenewableEnergy.BatteryRackWood"
        for i, facing in ipairs({ "E", "N", "W" }) do
            local square, tile = squares[i], Sprites.batteryRackWood[facing]
            local result = { facing = facing }
            table.insert(self.results, result)
            placeTurned(self, square, item, facing)
            T.waitFor(self, function()
                local bank = PowerBank.findOn(square)
                return bank ~= nil and Sprites.nameOf(bank) == tile and PowerBank.summaryOf(bank) ~= nil
            end, "this client's copy of the bank placed facing " .. facing .. ", working")
            -- Taken away when the test ends if the pick-up leaves it.
            T.server(self, "PZHarness.trackPlaced", T.at(square, { sprite = tile }))
            T.pickUpAsPlayer(self, square, tile)
            T.readCarried(self, { item })
            T.step(function()
                result.removed = T.objectWithSprite(square, tile) == nil
                result.returned, result.items = #T.carriedItems(self, item), self.reads.carried.total
            end)
            T.takeItems(self, nil, item)
        end
    end,
    validate = function(self)
        for _, r in ipairs(self.results) do
            local what = "the bank facing " .. r.facing
            expect(r.removed, what .. " was not picked up")
            -- The screwdriver stays.
            expectEqual("items carried after picking up " .. what .. ", the screwdriver too", r.items, 2)
            expectEqual("banks picking up " .. what .. " gave back", r.returned, 1)
        end
    end,
})

-- The cursor takes a table for a battery box, not for a rack, and the box goes down on the
-- tabletop as a working bank.
test("renewable_energy_tiles_battery_box_on_a_table", {
    spOnly = "it places with the moveables code on this client, which is the authority only in single player",
    run = function(self)
        local square = T.square(self, { indoors = true }, "a free indoor square for a table")
        if not square then return end
        electrician(self)
        T.placeTile(self, square, PZHarness.Fixtures.WORK_TABLE_SPRITE)
        T.step(function()
            local box, rack = Sprites.batteryBoxWood.S, Sprites.batteryRackWood.S
            local item = instanceItem("RenewableEnergy.BatteryBoxWood")
            self.boxFits = ISMoveableSpriteProps.new(box):canPlaceMoveable(T.player(), square, item)
            self.rackFits = ISMoveableSpriteProps.new(rack):canPlaceMoveable(T.player(), square, instanceItem("RenewableEnergy.BatteryRackWood"))
            ISMoveableSpriteProps.new(box):placeMoveableInternal(T.player(), square, item, box)
            local bank = PowerBank.findOn(square)
            T.track(self, bank or T.objectWithSprite(square, box))
            self.height = bank and bank:getRenderYOffset()
        end)
    end,
    validate = function(self)
        expect(self.boxFits, "the cursor refuses a battery box on a table")
        expect(not self.rackFits, "the cursor takes a battery rack on a table")
        expect(self.height ~= nil, "the box placed on the table isn't a working bank")
        expect((self.height or 0) > 0, "the bank stands on the floor under the table, at height " .. tostring(self.height))
    end,
})

-- A bank turned to face E or W shows its batteries, and facing E its meter, with that facing's
-- overlays, on the authority and on this client.
test("renewable_energy_tiles_turned_banks_show_their_overlays", {
    run = function(self)
        self.banks = {}
        for _, facing in ipairs({ "E", "W" }) do
            local bank = T.bank(self, "batteryRackWood", { T.L16, T.L16 }, { charge = 0.5, facing = facing, near = self.banks[1] })
            if not bank then return end
            bank.facing = facing
            table.insert(self.banks, bank)
            T.readRecord(self, bank)
            T.waitFor(self, function()
                return bank.state ~= nil and table.concat(T.overlaysOf(bank.object), ",") == table.concat(bank.state.overlays, ",")
            end, "this client's copy of the overlays of the bank facing " .. facing)
        end
    end,
    validate = function(self)
        for _, bank in ipairs(self.banks) do
            local tile = Sprites.batteryRackWood[bank.facing]
            local expected = Sprites.bankOverlays(tile, { T.L16, T.L16 }, bank.state.charge)
            local what = "the bank facing " .. bank.facing
            expectEqual("the tile of " .. what, Sprites.nameOf(bank.object), tile)
            expectEqual("what " .. what .. " shows", table.concat(bank.state.overlays, ","), table.concat(expected, ","))
        end
    end,
})

-- A module just below each Specs.crackLooks threshold shows that look's cracks over its own slot,
-- one at the light threshold shows whole, repair clears them, and snow stays drawn over cracks
-- added under it; this client matches.
local HEAVY_AT = T.conditionAt(T.FACTORY_MODULE, Specs.crackLooks.heavyBelow) - 1
local LIGHT_AT = T.conditionAt(T.FACTORY_MODULE, Specs.crackLooks.lightBelow) - 1
local WHOLE_AT = LIGHT_AT + 1
local HEAVY, LIGHT, SNOW = Sprites.cracks.heavy, Sprites.cracks.light, Sprites.snow
local CRACKED = {
    { name = "flatHeavy", sprite = Sprites.flat, modules = T.factoryModules(HEAVY_AT), shows = HEAVY.flat[1],
        what = "a flat panel just below the heavy cracks" },
    { name = "flatLight", sprite = Sprites.flat, modules = T.factoryModules(LIGHT_AT), shows = LIGHT.flat[1],
        what = "a flat panel just below the light cracks" },
    { name = "flatWhole", sprite = Sprites.flat, modules = T.factoryModules(WHOLE_AT), shows = "", what = "a flat panel at the light cracks" },
    { name = "rackUpper", sprite = Sprites.rack.metal.W, modules = T.factoryModules(100, HEAVY_AT), shows = HEAVY.rack.metal.W[2],
        what = "a metal rack facing west with its upper module cracked" },
    { name = "rackBoth", sprite = Sprites.rack.wood.E, modules = T.factoryModules(LIGHT_AT, HEAVY_AT),
        shows = LIGHT.rack.wood.E[1] .. "," .. HEAVY.rack.wood.E[2],
        what = "a wooden rack facing east with its lower module lightly and its upper heavily cracked" },
    -- A wall panel needs a wall to be placed against, so this one is a bare tile.
    { name = "wall", sprite = Sprites.wall.wood.E, modules = T.factoryModules(LIGHT_AT), shows = LIGHT.wall.wood.E[1],
        what = "a lightly cracked wooden wall panel facing east" },
    { name = "repaired", sprite = Sprites.flat, modules = T.factoryModules(HEAVY_AT),
        change = { modules = T.factoryModules(WHOLE_AT) }, shows = "", what = "a cracked flat panel repaired to whole" },
    { name = "snowed", sprite = Sprites.flat, modules = T.factoryModules(100),
        change = { modules = T.factoryModules(HEAVY_AT), snow = true }, shows = HEAVY.flat[1] .. "," .. SNOW.flat,
        what = "a snowed-on flat panel cracked under the snow" },
}

test("renewable_energy_tiles_cracked_modules_show", {
    run = function(self)
        -- Every case has a panel of its own, which the other cases' calls leave alone.
        T.batch(function()
            for _, case in ipairs(CRACKED) do
                local panel = T.panel(self, case.sprite, { modules = case.modules })
                if not panel then return end
                T.read(self, "panelCracks", T.at(panel, { sprite = case.sprite, change = case.change }), case.name)
                T.waitFor(self, function()
                    return table.concat(T.overlaysOf(T.objectWithSprite(panel.square, case.sprite)), ",")
                        == table.concat(self.reads[case.name].overlays, ",")
                end, "this client's overlays of " .. case.what)
            end
        end)
    end,
    validate = function(self)
        for _, case in ipairs(CRACKED) do
            local server = table.concat(self.reads[case.name].overlays, ",")
            expectEqual("what " .. case.what .. " shows", server, case.shows)
        end
    end,
})
