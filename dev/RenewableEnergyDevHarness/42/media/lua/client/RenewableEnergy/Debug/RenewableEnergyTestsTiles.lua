require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "Moveables/ISMoveableSpriteProps"
require "Moveables/ISMoveableDefinitions"
require "RenewableEnergy/Biogas/Digester"

-- The mod's tiles (Sprites.lua) and how its objects move (Moveables.lua, PlaceTracker.lua): pictures,
-- overlays, tile properties, rotating, placing, picking up and scrapping.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect

local Sprites, Specs = RenewableEnergy.Sprites, RenewableEnergy.Specs
local PowerBank, SolarGardenLight = RenewableEnergy.PowerBank, RenewableEnergy.SolarGardenLight

local MATERIALS = { "wood", "metal" }

-- Every placed tile: the item picking it up gives and what Sprites.kindOf reports.
local PLACED = {
    { sprite = Sprites.flat, item = "RenewableEnergy.SolarFlat", kind = "flat" },
    { sprite = Sprites.failsafe, item = "RenewableEnergy.SolarFailsafe", kind = "failsafe" },
    { sprite = Sprites.cellCharger, item = RenewableEnergy.SolarCellCharger.ITEM, kind = "cellCharger" },
    { sprite = Sprites.gardenLight.off, item = SolarGardenLight.ITEM, kind = "gardenLight" },
    { sprite = Sprites.gardenLight.lit, item = SolarGardenLight.ITEM, kind = "gardenLight" },
}
for material, suffix in pairs({ wood = "Wood", metal = "Metal" }) do
    for _, mount in ipairs({ "wall", "rack" }) do
        local item = "RenewableEnergy.Solar" .. (mount == "wall" and "Wall" or "Rack") .. suffix
        for facing, sprite in pairs(Sprites[mount][material]) do
            table.insert(PLACED, { sprite = sprite, item = item, kind = mount, facing = facing, material = material })
        end
    end
    for _, tier in ipairs({ "Box", "Rack", "Bank" }) do
        local field = "battery" .. tier .. suffix
        for facing, sprite in pairs(Sprites[field]) do
            table.insert(PLACED, { sprite = sprite, item = "RenewableEnergy.Battery" .. tier .. suffix,
                kind = field, facing = facing, material = material })
        end
    end
end
-- The fixed tiles a save's banks may stand on (Sprites.fixedTiles), each as its turnable twin.
for fixed, twin in pairs(Sprites.fixedTiles) do
    for _, placed in ipairs(PLACED) do
        if placed.sprite == twin then
            table.insert(PLACED, { sprite = fixed, item = placed.item, kind = placed.kind, facing = placed.facing,
                material = placed.material })
            break
        end
    end
end

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

-- Every tile Sprites.lua names exists and has a picture in the pack.
test("renewable_energy_tiles_have_pictures", {
    validate = function()
        for name in pairs(TILES) do
            expect(getSprite(name) ~= nil, name .. " is not a tile in renewable_energy.tiles")
            expect(getTexture(name) ~= nil, name .. " has no picture in the pack")
        end
    end,
})

-- Each moveable item places the tile of its own kind and material, and each tile picks up as its
-- item (CustomItem).
test("renewable_energy_tiles_moveable_items_place_their_tiles", {
    validate = function()
        for _, placed in ipairs(PLACED) do
            local script = getScriptManager():getItem(placed.item)
            local kind, _, material = Sprites.kindOf(script and script:getWorldObjectSprite())
            expect(kind == placed.kind and material == placed.material, string.format("%s places a %s %s tile, expected %s %s",
                placed.item, tostring(material), tostring(kind), tostring(placed.material), placed.kind))
            local props = properties(placed.sprite)
            local customItem = props and props:get("CustomItem")
            expect(customItem == placed.item, placed.sprite .. " gives " .. tostring(customItem) .. ", expected " .. placed.item)
        end
    end,
})

-- Sprites.kindOf names every placed tile's kind, facing and material; every tile Sprites.lua names
-- is either placed or an overlay, never both; a vanilla tile has no kind.
test("renewable_energy_tiles_kind_of_reads_every_placed_tile", {
    validate = function()
        for _, placed in ipairs(PLACED) do
            local kind, facing, material = Sprites.kindOf(placed.sprite)
            expect(kind == placed.kind and facing == placed.facing and material == placed.material,
                string.format("kindOf(%s) is %s %s %s, expected %s %s %s", placed.sprite, tostring(kind), tostring(facing),
                    tostring(material), placed.kind, tostring(placed.facing), tostring(placed.material)))
        end
        for name in pairs(TILES) do
            local kind, overlay = Sprites.kindOf(name) ~= nil, Sprites.isOverlay(name)
            expect(kind ~= overlay, name .. (kind and " has a kind and counts as an overlay" or " has no kind and isn't an overlay"))
        end
        expect(Sprites.kindOf("carpentry_01_16") == nil, "a vanilla crate has a kind")
    end,
})

-- Whether each tile of `set`, a tile name by facing, turns to every other of the set with the
-- placing cursor.
local function expectTurns(set, what)
    for facing, name in pairs(set) do
        local faces = ISMoveableSpriteProps.new(name):getFaces()
        for otherFacing, otherName in pairs(set) do
            expect(faces[otherFacing] == otherName, string.format("%s (%s %s) turns %s to %s, expected %s",
                name, what, facing, otherFacing, tostring(faces[otherFacing]), otherName))
        end
    end
end

-- The placing cursor turns a rack through all four facings and a wall panel between its two,
-- without turning wood into metal.
test("renewable_energy_tiles_mounts_rotate", {
    validate = function()
        for _, mount in ipairs({ "rack", "wall" }) do
            for _, material in ipairs(MATERIALS) do
                expectTurns(Sprites[mount][material], material .. " " .. mount)
            end
        end
    end,
})

-- The placing cursor turns every bank and the gas heater through all four facings, as the game's
-- furniture, each staying the same bank, and a lit heater lit.
test("renewable_energy_tiles_banks_and_heater_rotate", {
    validate = function()
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
        local batteries = { "RenewableEnergy.L16Battery" }
        for fixed, twin in pairs(Sprites.fixedTiles) do
            expect(PowerBank.bankOfSprite(fixed) == PowerBank.bankOfSprite(twin), fixed .. " is another bank than " .. twin)
            local shown, twinShown = Sprites.bankOverlays(fixed, batteries, 0.5), Sprites.bankOverlays(twin, batteries, 0.5)
            expect(table.concat(shown, ",") == table.concat(twinShown, ","), fixed .. " shows " .. table.concat(shown, ",")
                .. ", its twin " .. table.concat(twinShown, ","))
            local item = ISMoveableSpriteProps.new(fixed):instanceItem()
            expect(item ~= nil and item:getFullType() == properties(twin):get("CustomItem") and item:getWorldSprite() == twin,
                fixed .. " picks up as " .. tostring(item and item:getFullType()) .. " placing "
                    .. tostring(item and item:getWorldSprite()) .. ", expected its twin " .. twin)
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
        local L16, DEEP_CYCLE = "RenewableEnergy.L16Battery", "RenewableEnergy.DeepCycleBattery"
        for itemType, bank in pairs(Specs.banks) do
            local cars = {}
            for i = 1, bank.maxBatteries + 1 do
                cars[i] = "Base.CarBattery1"
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
                        expect(#slots == bank.maxBatteries, string.format("%s shows up to %d %s batteries but holds %d",
                            what, #slots, look, bank.maxBatteries))
                    end
                    local shown = meter and 1 or 0
                    local full = Sprites.bankOverlays(tile, cars, 1)
                    expect(#full == bank.maxBatteries + shown and full[bank.maxBatteries] == fill.batteries.car[bank.maxBatteries]
                        and (not meter or full[#full] == meter[#meter]), "an overfull " .. what .. " shows " .. table.concat(full, ", "))
                    local mixed = Sprites.bankOverlays(tile, { L16, DEEP_CYCLE }, 0)
                    expect(#mixed == 2 + shown and mixed[1] == fill.batteries.l16[1] and mixed[2] == fill.batteries.deepCycle[2]
                        and (not meter or mixed[3] == meter[1]), "an empty L-16 and deep-cycle in " .. what .. " show "
                        .. table.concat(mixed, ", "))
                    expect(#Sprites.bankOverlays(tile, {}, 1) == 0, "an empty " .. what .. " shows overlays")
                end
            end
        end
        if not levels then return end
        local seen, last, falls = {}, Sprites.meterLevel(0), nil
        expect(last == 1, "no charge shows meter level " .. last)
        for percent = 0, 100 do
            local level = Sprites.meterLevel(percent / 100)
            falls = falls or (level < last and percent)
            seen[level], last = true, level
        end
        expect(not falls, "the meter drops a level at " .. tostring(falls) .. "% charge")
        expect(last == levels, "a full charge shows meter level " .. last .. " of " .. levels)
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

-- Registers test `name`, scrapping each case's tile on the server at the case's `perk` level and
-- forced roll, and expecting the case's count of `fullType` among the usable items. `premise`
-- checks the tiles first. Each case: what is scrapped, the tile, the level, the roll, the count
-- and whether it is another tile of the object.
local function scrapTest(name, perk, fullType, cases, premise)
    test(name, {
        run = function(self)
            self.counts = {}
            for i, case in ipairs(cases) do
                T.step(function() T.setPerk(self, perk, case[3]) end)
                T.forceRoll(self, case[4])
                T.server(self, "scrapItems", { sprite = case[2], otherTile = case[6], type = fullType })
                T.step(function() self.counts[i] = self.server.scrapItems.count end)
            end
        end,
        validate = function(self)
            premise()
            for i, case in ipairs(cases) do
                expect(self.counts[i] == case[5], case[1] .. " gave " .. tostring(self.counts[i]) .. " " .. fullType
                    .. ", expected " .. case[5])
            end
        end,
    })
end

-- Cutting up a vanilla fridge gives its compressor, which a digester needs to fill propane tanks,
-- on a roll under the character's chance, at most one, and only for the clicked tile, not again
-- for the others vanilla scraps along with it: 10% at Metalworking 0, 10% more a level, so certain
-- at 9. A stove, which vanilla also cuts up as a Fridge, has none.
local FRIDGE, STOVE = "appliances_refrigeration_01_0", "appliances_cooking_01_0"
scrapTest("renewable_energy_tiles_fridge_scraps_to_compressor", Perks.MetalWelding, RenewableEnergy.Digester.COMPRESSOR, {
    { "a fridge at Metalworking 0, rolling just under 10%", FRIDGE, 0, 0.1 - T.UNDER, 1 },
    { "a fridge at Metalworking 0, rolling 10%", FRIDGE, 0, 0.1, 0 },
    { "a fridge at Metalworking 4, rolling just under 50%", FRIDGE, 4, 0.5 - T.UNDER, 1 },
    { "a fridge at Metalworking 4, rolling 50%", FRIDGE, 4, 0.5, 0 },
    { "a fridge at Metalworking 9, on the highest roll", FRIDGE, 9, 1 - T.UNDER, 1 },
    { "a fridge's other tile, on the lowest roll", FRIDGE, 9, 0, 0, true },
    { "a stove, on the lowest roll", STOVE, 9, 0, 0 },
}, function()
    local stove = ISMoveableSpriteProps.new(STOVE)
    expect(stove.canScrap and stove.material == "Fridge", "the stove can't be cut up, or isn't cut up as a Fridge")
end)

-- Dismantling a vanilla microwave gives its transformer, which the homemade inverters are wound on,
-- on a roll under vanilla's chance for the microwave's Electric scrap: 20% at Electricity 0, 10%
-- more a level, so certain at 8. A stove has none.
local MICROWAVE = "appliances_cooking_01_24"
scrapTest("renewable_energy_tiles_microwave_scraps_to_transformer", Perks.Electricity, "RenewableEnergy.MicrowaveTransformer", {
    { "a microwave at Electricity 0, rolling just under 20%", MICROWAVE, 0, 0.2 - T.UNDER, 1 },
    { "a microwave at Electricity 0, rolling 20%", MICROWAVE, 0, 0.2, 0 },
    { "a microwave at Electricity 4, rolling just under 60%", MICROWAVE, 4, 0.6 - T.UNDER, 1 },
    { "a microwave at Electricity 4, rolling 60%", MICROWAVE, 4, 0.6, 0 },
    { "a microwave at Electricity 8, on the highest roll", MICROWAVE, 8, 1 - T.UNDER, 1 },
    { "a stove, on the lowest roll", STOVE, 10, 0, 0 },
}, function()
    expect(ISMoveableSpriteProps.new(MICROWAVE).canScrap, "the microwave can't be dismantled")
end)

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
    ["RenewableEnergy.SolarRackWood"] = { key = PowerBank.MODULES_KEY, value = MODULES },
    ["RenewableEnergy.SolarFlat"] = { key = PowerBank.MODULES_KEY, value = { MODULES[1] } },
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

-- Placed and picked up as a player does, each item's tile comes back as that one item, with its
-- modData (CARRIED). Wall panels and banks are left out.
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
            for _, placed in ipairs(PLACED) do
                local script = getScriptManager():getItem(placed.item)
                -- Banks stand only indoors, and placing them by hand is the power tests' business.
                if placed.kind ~= "wall" and not PowerBank.bankOfSprite(placed.sprite)
                    and script and script:getWorldObjectSprite() == placed.sprite then
                    local carried = CARRIED[placed.item]
                    local result = { placed = placed, expected = carried and describe(carried.value) }
                    table.insert(self.results, result)
                    local handle = T.placeAsPlayer(self, square, placed.item, placed.sprite, carried and { [carried.key] = carried.value })
                    if carried then
                        T.server(self, "objectModData", T.at(square, { sprite = placed.sprite, key = carried.key }))
                        T.step(function() result.placedData = describe(self.server.objectModData.value) end)
                    end
                    T.pickUpAsPlayer(self, handle, placed.sprite)
                    T.readCarried(self, { placed.item })
                    T.step(function()
                        local items = T.carriedItems(self, placed.item)
                        result.removed = T.objectWithSprite(square, placed.sprite) == nil
                        result.returned, result.items = #items, self.server.carried.total
                        result.pickedUpData = carried and describe(items[1] and items[1].modData[carried.key])
                    end)
                    T.server(self, "takeItems", { type = placed.item })
                end
            end
        end)
    end,
    validate = function(self)
        expect(#self.results > 0, "no item places one of the tiles")
        local kept = {}
        for _, r in ipairs(self.results) do
            local what = r.placed.sprite .. " (" .. r.placed.item .. ")"
            expect(r.removed, what .. " was not picked up")
            -- The screwdriver stays.
            expect(r.returned == 1 and r.items == 2,
                what .. " gave back " .. tostring(r.items and r.items - 1) .. " items, " .. tostring(r.returned) .. " of them " .. r.placed.item)
            if r.expected then
                kept[r.placed.item] = true
                expect(r.placedData == r.expected, "placed " .. what .. " holds " .. tostring(r.placedData) .. ", expected " .. r.expected)
                expect(r.pickedUpData == r.expected, "picked-up " .. what .. " holds " .. tostring(r.pickedUpData)
                    .. ", expected " .. r.expected)
            end
        end
        for fullType in pairs(CARRIED) do
            expect(kept[fullType], fullType .. " places no tile of its own, so nothing checked what it keeps")
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
                result.returned, result.items = #T.carriedItems(self, item), self.server.carried.total
            end)
            T.server(self, "takeItems", { type = item })
        end
    end,
    validate = function(self)
        expect(#self.results == 3, "placed " .. #self.results .. " of the three banks")
        for _, r in ipairs(self.results) do
            local what = "the bank facing " .. r.facing
            expect(r.removed, what .. " was not picked up")
            -- The screwdriver stays.
            expect(r.returned == 1 and r.items == 2,
                what .. " gave back " .. tostring(r.items and r.items - 1) .. " items, " .. tostring(r.returned) .. " of them its own")
        end
    end,
})

-- A bank turned to face E or W shows its batteries, and facing E its meter, with that facing's
-- overlays, on the authority and on this client.
local L16 = T.L16
test("renewable_energy_tiles_turned_banks_show_their_overlays", {
    run = function(self)
        self.banks = {}
        for _, facing in ipairs({ "E", "W" }) do
            local bank = T.bank(self, "batteryRackWood", { L16, L16 }, { charge = 0.5, facing = facing, near = self.banks[1] })
            if not bank then return end
            bank.facing = facing
            table.insert(self.banks, bank)
            T.bankState(self, bank)
            T.waitFor(self, function()
                return bank.state ~= nil and T.overlays(bank.object) == table.concat(bank.state.overlays, ",")
            end, "this client's copy of the overlays of the bank facing " .. facing)
        end
    end,
    validate = function(self)
        for _, bank in ipairs(self.banks) do
            local tile = Sprites.batteryRackWood[bank.facing]
            local expected = Sprites.bankOverlays(tile, { L16, L16 }, bank.state.charge)
            local shown = table.concat(bank.state.overlays, ",")
            expect(Sprites.nameOf(bank.object) == tile, "the bank facing " .. bank.facing .. " stands as " .. tostring(Sprites.nameOf(bank.object)))
            expect(#expected == (bank.facing == "E" and 3 or 2) and shown == table.concat(expected, ","),
                "the bank facing " .. bank.facing .. " shows " .. shown .. ", expected " .. table.concat(expected, ","))
        end
    end,
})

-- A module just below each Specs.crackLooks threshold shows that look's cracks over its own slot,
-- one at the light threshold shows whole, repair clears them, and snow stays drawn over cracks
-- added under it; this client matches.
local HEAVY_AT = T.conditionAt(Specs.factoryModule, Specs.crackLooks.heavyBelow) - 1
local LIGHT_AT = T.conditionAt(Specs.factoryModule, Specs.crackLooks.lightBelow) - 1
local WHOLE_AT = LIGHT_AT + 1
local HEAVY, LIGHT, SNOW = Sprites.cracks.heavy, Sprites.cracks.light, Sprites.snow
local CRACKED = {
    { name = "flatHeavy", sprite = Sprites.flat, modules = T.factoryModules(HEAVY_AT), shows = HEAVY.flat,
        what = "a flat panel just below the heavy cracks" },
    { name = "flatLight", sprite = Sprites.flat, modules = T.factoryModules(LIGHT_AT), shows = LIGHT.flat,
        what = "a flat panel just below the light cracks" },
    { name = "flatWhole", sprite = Sprites.flat, modules = T.factoryModules(WHOLE_AT), shows = "", what = "a flat panel at the light cracks" },
    { name = "rackUpper", sprite = Sprites.rack.metal.W, modules = T.factoryModules(100, HEAVY_AT), shows = HEAVY.rack.metal.W[2],
        what = "a metal rack facing west with its upper module cracked" },
    { name = "rackBoth", sprite = Sprites.rack.wood.E, modules = T.factoryModules(LIGHT_AT, HEAVY_AT),
        shows = LIGHT.rack.wood.E[1] .. "," .. HEAVY.rack.wood.E[2],
        what = "a wooden rack facing east with its lower module lightly and its upper heavily cracked" },
    -- A wall panel needs a wall to be placed against, so this one is a bare tile.
    { name = "wall", sprite = Sprites.wall.wood.E, modules = T.factoryModules(LIGHT_AT), shows = LIGHT.wall.wood.E,
        what = "a lightly cracked wooden wall panel facing east" },
    { name = "repaired", sprite = Sprites.flat, modules = T.factoryModules(HEAVY_AT),
        change = { modules = T.factoryModules(WHOLE_AT) }, shows = "", what = "a cracked flat panel repaired to whole" },
    { name = "snowed", sprite = Sprites.flat, modules = T.factoryModules(100),
        change = { modules = T.factoryModules(HEAVY_AT), snow = true }, shows = HEAVY.flat .. "," .. SNOW.flat,
        what = "a snowed-on flat panel cracked under the snow" },
}

test("renewable_energy_tiles_cracked_modules_show", {
    run = function(self)
        self.shown = {}
        -- Every case has a panel of its own, which the other cases' calls leave alone.
        T.batch(function()
            for _, case in ipairs(CRACKED) do
                local panel = T.panel(self, case.sprite, { modules = case.modules })
                if not panel then return end
                local at = panel.position
                T.server(self, "panelCracks", T.at(at, { sprite = case.sprite, change = case.change }))
                T.waitFor(self, function()
                    return T.overlays(T.objectWithSprite(panel.square, case.sprite)) == table.concat(self.server.panelCracks.overlays, ",")
                end, "this client's overlays of " .. case.what)
                T.step(function()
                    self.shown[case.name] = {
                        server = table.concat(self.server.panelCracks.overlays, ","),
                        client = T.overlays(T.objectWithSprite(panel.square, case.sprite)),
                    }
                end)
            end
        end)
    end,
    validate = function(self)
        for _, case in ipairs(CRACKED) do
            local shown = self.shown[case.name] or {}
            expect(shown.server == case.shows, case.what .. " shows '" .. tostring(shown.server) .. "'")
            expect(shown.client == shown.server, "this client's copy of " .. case.what .. " shows '" .. tostring(shown.client) .. "'")
        end
    end,
})
