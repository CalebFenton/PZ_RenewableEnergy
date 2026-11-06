require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Debug/RenewableEnergyTestLibCraft"
require "RenewableEnergy/Debug/RenewableEnergyTestLibGas"
local Specs = require "RenewableEnergy/Specs"
local SolarGardenLight = require "RenewableEnergy/Gadgets/SolarGardenLight"
require "Moveables/ISMoveableDefinitions"
local Digester = require "RenewableEnergy/Biogas/Digester"
local Panel = require "RenewableEnergy/PowerBank/Panel"
local Recipes = require "RenewableEnergy/Recipes"
local PowerBank = require "RenewableEnergy/PowerBank/PowerBank"
local SolarCellCharger = require "RenewableEnergy/Gadgets/SolarCellCharger"
local Sprites = require "RenewableEnergy/Sprites"
local Squares = require "cf_commonlib/Squares"
local Wind = require "RenewableEnergy/Wind"
local BuiltScrap = require "RenewableEnergy/Moveables/BuiltScrap"

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
        self.twin, self.fixed = PZHarness.Fixtures.objectWithSprite(square, Sprites.gasHeater.off.S), PZHarness.Fixtures.objectWithSprite(square, fixed)
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

-- Whether `square` and the squares around it are free, room for any appliance of up to two tiles
-- to stand with a tile on `square`.
local function roomAround(square)
    return not Squares.eachAround(square:getX(), square:getY(), square:getZ(), 1, function(near)
        return not near:isFree(false) or nil
    end)
end

-- Registers test `name`, dismantling in each case a new object as the server's character does,
-- clicking its tile `case.sprite`, at `case.level` of `case.perk`, and expecting `case.gives`,
-- counts by full type, or a function that answers them; with `case.only`, nothing else. `case.place(self)`
-- places it and returns its handle; without it the whole
-- object of `case.sprite` goes on a square with room around it. Every roll is `case.roll`, or
-- with `case.chanceOf`, a scrap material, just "under" or "at" the character's vanilla chance
-- for that material, worked out on the authority; with `case.vanillaRoll`, every roll vanilla's
-- own scrap draws is that. `premise`, if given, checks the tiles first.
local function dismantleTest(name, cases, premise)
    test(name, {
        instant = true,
        run = function(self)
            local roomy
            for _, case in ipairs(cases) do
                local handle
                if case.place then
                    handle = case.place(self)
                else
                    roomy = roomy or T.square(self, { accept = roomAround }, "a free square with free squares around it")
                    handle = roomy and T.at(roomy)
                    if handle then
                        T.server(self, "placeWhole", T.at(roomy, { sprite = case.sprite }))
                    end
                end
                if not handle then return end
                T.step(function() T.setPerk(self, case.perk, case.level) end)
                if not case.chanceOf then
                    T.forceRoll(self, case.roll)
                end
                T.read(self, "scrapItems", T.at(handle, { sprite = case.sprite, chanceOf = case.chanceOf,
                    roll = case.chanceOf and case.roll or nil, vanillaRoll = case.vanillaRoll }), case.label)
            end
        end,
        validate = function(self)
            if premise then premise() end
            for _, case in ipairs(cases) do
                local result = self.reads[case.label]
                expect(result.scrapped, case.label .. " wasn't dismantled")
                local gives = type(case.gives) == "function" and case.gives() or case.gives
                for fullType, count in pairs(gives) do
                    expectEqual(fullType .. " " .. case.label .. " gave", result.counts[fullType] or 0, count)
                end
                if case.only then
                    for fullType, count in pairs(result.counts) do
                        expect(gives[fullType] ~= nil, case.label .. " gave " .. count .. " " .. fullType .. " besides its own parts")
                    end
                end
            end
        end,
    })
end

-- Cutting up a vanilla fridge gives its compressor, which a digester needs to fill propane tanks,
-- and dismantling a microwave its transformer, which the homemade inverters are wound on: each on
-- a roll under vanilla's own chance for the tile's scrap material, which rises with the level,
-- and one only, though vanilla scraps each tile of the wide fridge. A stove, which vanilla also
-- cuts up as a Fridge, has neither.
-- The wide two-door fridge, two tiles.
local FRIDGE, MICROWAVE, STOVE = "appliances_refrigeration_01_18", "appliances_cooking_01_24", "appliances_cooking_01_0"
local TRANSFORMER = "RenewableEnergy.MicrowaveTransformer"
dismantleTest("renewable_energy_tiles_appliances_scrap_to_parts", {
    { label = "a fridge at Metalworking 0, rolling just under its chance", sprite = FRIDGE, perk = Perks.MetalWelding,
        level = 0, chanceOf = "Fridge", roll = "under", gives = { [Digester.COMPRESSOR] = 1 } },
    { label = "a fridge at Metalworking 0, rolling its chance", sprite = FRIDGE, perk = Perks.MetalWelding,
        level = 0, chanceOf = "Fridge", roll = "at", gives = { [Digester.COMPRESSOR] = 0 } },
    { label = "a fridge at Metalworking 4, rolling just under its chance", sprite = FRIDGE, perk = Perks.MetalWelding,
        level = 4, chanceOf = "Fridge", roll = "under", gives = { [Digester.COMPRESSOR] = 1 } },
    { label = "a microwave at Electricity 0, rolling just under its chance", sprite = MICROWAVE, perk = Perks.Electricity,
        level = 0, chanceOf = "Electric", roll = "under", gives = { [TRANSFORMER] = 1 } },
    { label = "a microwave at Electricity 0, rolling its chance", sprite = MICROWAVE, perk = Perks.Electricity,
        level = 0, chanceOf = "Electric", roll = "at", gives = { [TRANSFORMER] = 0 } },
    { label = "a microwave at Electricity 4, rolling just under its chance", sprite = MICROWAVE, perk = Perks.Electricity,
        level = 4, chanceOf = "Electric", roll = "under", gives = { [TRANSFORMER] = 1 } },
    { label = "a stove, on the lowest roll", sprite = STOVE, perk = Perks.MetalWelding, level = 10, roll = 0,
        gives = { [Digester.COMPRESSOR] = 0, [TRANSFORMER] = 0 } },
}, function()
    expect(getSprite(FRIDGE):getSpriteGrid() ~= nil, "the fridge is one tile, so nothing shows it gives one compressor, not one a tile")
    expect(ISMoveableSpriteProps.new(STOVE).material == "Fridge", "the stove isn't cut up as a Fridge")
end)

local function dome(self)
    return T.placeRecord(self, "digester", "dome")
end

-- A barrel digester on an orange barrel with every fitting: a worn tarp bag, a scrubber packed
-- with an Iron Sponge, a compressor.
local function fittedBarrel(self)
    local handle = T.placeRecord(self, "digester", "barrel.Mov_OrangeBarrel")
    if handle then
        T.setRecord(self, handle, { holder = "tarp", holderCondition = 60, scrubber = true, scrubSponge = 3, compressor = true })
    end
    return handle
end

local CHARGER = Sprites.windCharger.propeller.wood.S

local function charger(broken, sprite)
    return function(self)
        local square = T.square(self, {}, "a free outdoor square for a wind charger")
        return square and T.placeTile(self, square, sprite or CHARGER, { [Wind.BROKEN_KEY] = broken })
    end
end

-- What is built in place gives back each piece its recipe used up, on a roll under BuiltScrap.odds
-- at the builder's level of the recipe's skill, and nothing of its Material's vanilla scrap: a
-- brick dome the bricks of its walls, all of them; a barrel digester the barrel it was built from
-- and its scrubber's materials, but never the glue, tape or garbage bags a build uses up, and its
-- tarp bag, spent sponge and compressor whatever the roll; a wind charger its metal and wiring,
-- or the wood of a wooden frame, and its motor and blades whole whatever the roll, broken blades
-- broken. The counts are the build recipes', so that a piece coming back once for an input of many
-- shows.
dismantleTest("renewable_energy_tiles_built_in_place_scraps_to_recipe", {
    { label = "a dome rolling just under its odds", place = dome, sprite = Sprites.digester.dome, perk = Perks.Masonry,
        level = 5, roll = BuiltScrap.odds(5) - T.UNDER,
        gives = { ["Base.ClayBrick"] = 40, ["Base.RubberHose"] = 2, ["Base.Pipe"] = 1, ["Base.Nails"] = 0, ["Base.Stone2"] = 0 } },
    { label = "a dome rolling its odds", place = dome, sprite = Sprites.digester.dome, perk = Perks.Masonry,
        level = 5, roll = BuiltScrap.odds(5),
        gives = { ["Base.ClayBrick"] = 0, ["Base.RubberHose"] = 0, ["Base.Pipe"] = 0 } },
    { label = "a fitted barrel digester rolling just under its odds", place = fittedBarrel,
        sprite = Sprites.digester.barrel.Mov_OrangeBarrel, perk = Perks.Mechanics, level = 1, roll = BuiltScrap.odds(1) - T.UNDER,
        gives = {
            ["Base.Mov_OrangeBarrel"] = 1, ["Base.MetalDrum"] = 0, ["Base.RubberHose"] = 2, ["Base.Funnel"] = 1,
            ["Base.Bucket"] = 1, ["Base.Pipe"] = 1, ["Base.Glue"] = 0, ["Base.DuctTape"] = 0, ["Base.Garbagebag"] = 0,
            ["RenewableEnergy.TarpGasBag"] = 1, [Digester.SPENT_SPONGE] = 1, [Digester.COMPRESSOR] = 1,
        } },
    { label = "a fitted barrel digester rolling its odds", place = fittedBarrel,
        sprite = Sprites.digester.barrel.Mov_OrangeBarrel, perk = Perks.Mechanics, level = 1, roll = BuiltScrap.odds(1),
        gives = {
            ["Base.Mov_OrangeBarrel"] = 0, ["Base.RubberHose"] = 0, ["Base.Bucket"] = 0,
            ["RenewableEnergy.TarpGasBag"] = 1, [Digester.SPENT_SPONGE] = 1, [Digester.COMPRESSOR] = 1,
        } },
    { label = "a broken wind charger rolling just under its odds", place = charger(true), sprite = CHARGER,
        perk = Perks.MetalWelding, level = 3, roll = BuiltScrap.odds(3) - T.UNDER,
        gives = {
            ["RenewableEnergy.BrokenWoodenBlades"] = 1, ["RenewableEnergy.WoodenBlades"] = 0, ["RenewableEnergy.TreadmillMotor"] = 1,
            ["Base.SheetMetal"] = 1, ["Base.MetalBar"] = 4, ["Base.ElectricWire"] = 3, ["Base.ElectronicsScrap"] = 1,
        } },
    { label = "a wind charger rolling its odds", place = charger(nil), sprite = CHARGER,
        perk = Perks.MetalWelding, level = 3, roll = BuiltScrap.odds(3),
        gives = {
            ["RenewableEnergy.WoodenBlades"] = 1, ["RenewableEnergy.TreadmillMotor"] = 1, ["Base.SheetMetal"] = 0,
            ["Base.MetalBar"] = 0,
        } },
    { label = "a scoop rotor on a wooden frame rolling just under its odds", place = charger(nil, Sprites.windTimberScoop),
        sprite = Sprites.windTimberScoop, perk = Perks.Woodwork, level = 2, roll = BuiltScrap.odds(2) - T.UNDER,
        gives = {
            ["Base.Log"] = 2, ["Base.Plank"] = 4, ["Base.Nails"] = 10, ["Base.Rope"] = 2, ["Base.Screws"] = 4,
            ["Base.MetalDrum"] = 1, ["RenewableEnergy.TreadmillMotor"] = 1, ["Base.MetalBar"] = 0,
        } },
})

-- Dismantling a bank, in any facing, gives back the pieces of the scrap definition the mod registers
-- for its tile's Material (Moveables.lua), every piece of them on the luckiest roll, and nothing
-- else: the definition survives vanilla's reset of them at boot and its tiles name it. What the
-- definition lists is the mod's balance, read rather than restated here.
local function bankCase(field, facing)
    local sprite = Sprites[field][facing]
    return { label = "a " .. field .. " facing " .. facing, sprite = sprite, perk = Perks.Electricity,
        level = 10, roll = 0, vanillaRoll = 0, only = true, gives = function()
            local material = ISMoveableSpriteProps.new(sprite).material
            local def = ISMoveableDefinitions:getInstance().getScrapDefinition(material)
            local gives = {}
            for _, piece in ipairs(def and def.returnItemsStatic or {}) do
                gives[piece.returnItem] = (gives[piece.returnItem] or 0) + piece.maxAmount
            end
            expect(def ~= nil and #def.returnItemsStatic > 0, sprite .. "'s Material " .. tostring(material) .. " has no pieces to give")
            return gives
        end }
end
dismantleTest("renewable_energy_tiles_banks_scrap_to_parts", {
    bankCase("batteryBoxWood", "S"),
    bankCase("batteryBoxMetal", "E"),
    bankCase("batteryRackWood", "N"),
    bankCase("batteryRackMetal", "W"),
    bankCase("batteryBankWood", "S"),
    bankCase("batteryBankMetal", "E"),
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
-- modData (CARRIED); a mount's item on this client shows as many homemade modules as it holds.
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
                local mount = Recipes.MOUNTS[item] ~= nil
                local result = { what = sprite .. " (" .. item .. ")", item = item, expected = carried and describe(carried.value),
                    homemade = mount and Sprites.homemadeCount(carried and carried.value or {}) or nil }
                table.insert(self.results, result)
                local handle = T.placeAsPlayer(self, square, item, sprite, carried and { [carried.key] = carried.value })
                if carried then
                    T.read(self, "PZHarness.objectModData", T.at(square, { sprite = sprite, key = carried.key }), item)
                end
                T.pickUpAsPlayer(self, handle, sprite)
                if mount then
                    T.waitFor(self, function()
                        local copy = T.carried(item)
                        result.modelIndex = copy and copy:getModelIndex()
                        return copy ~= nil
                    end, "this client's picked-up " .. item)
                end
                T.readCarried(self, { item })
                T.step(function()
                    local items = T.carriedItems(self, item)
                    result.removed = PZHarness.Fixtures.objectWithSprite(square, sprite) == nil
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
            if r.homemade then
                expectEqual("this client's picked-up " .. r.what .. "'s model index, its homemade modules", r.modelIndex,
                    r.homemade)
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
                result.removed = PZHarness.Fixtures.objectWithSprite(square, tile) == nil
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
            T.track(self, bank or PZHarness.Fixtures.objectWithSprite(square, box))
            self.height = bank and bank:getRenderYOffset()
        end)
    end,
    validate = function(self)
        expect(self.boxFits, "the cursor refuses a battery box on a table")
        expect(not self.rackFits, "the cursor takes a battery rack on a table")
        expect(self.height ~= nil, "the box placed on the table isn't a working bank")
        -- The table stands on the floor, so its top is its tile's Surface.
        local top = tonumber(properties(PZHarness.Fixtures.WORK_TABLE_SPRITE):get("Surface"))
        expectEqual("the height the bank stands at on the table", self.height, top)
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
-- added under it. A homemade module shows over its own slot only, under its cracks and snow, and
-- factory modules show none; this client matches.
local HEAVY_AT = T.conditionAt(T.FACTORY_MODULE, Specs.crackLooks.heavyBelow) - 1
local LIGHT_AT = T.conditionAt(T.FACTORY_MODULE, Specs.crackLooks.lightBelow) - 1
local WHOLE_AT = LIGHT_AT + 1
local HOMEMADE_HEAVY_AT = T.conditionAt(T.HOMEMADE_MODULE, Specs.crackLooks.heavyBelow) - 1
local HEAVY, LIGHT, SNOW, HOMEMADE = Sprites.cracks.heavy, Sprites.cracks.light, Sprites.snow, Sprites.homemadeModules
local SHOWN = {
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
    { name = "homemadeUpper", sprite = Sprites.rack.wood.S,
        modules = { { type = T.FACTORY_MODULE, condition = 100 }, { type = T.HOMEMADE_MODULE, condition = 100 } },
        shows = HOMEMADE.rack.wood.S[2], what = "a wooden rack facing south with a homemade upper module" },
    { name = "homemadeFlat", sprite = Sprites.flat, modules = { { type = T.HOMEMADE_MODULE, condition = 100 } },
        change = { modules = { { type = T.HOMEMADE_MODULE, condition = HOMEMADE_HEAVY_AT } }, snow = true },
        shows = HOMEMADE.flat[1] .. "," .. HEAVY.flat[1] .. "," .. SNOW.flat,
        what = "a snowed-on flat panel with a homemade module cracked under the snow" },
}

test("renewable_energy_tiles_modules_show", {
    run = function(self)
        -- Every case has a panel of its own, which the other cases' calls leave alone.
        T.batch(function()
            for _, case in ipairs(SHOWN) do
                local panel = T.panel(self, case.sprite, { modules = case.modules })
                if not panel then return end
                T.read(self, "panelCracks", T.at(panel, { sprite = case.sprite, change = case.change }), case.name)
                T.waitFor(self, function()
                    return table.concat(T.overlaysOf(PZHarness.Fixtures.objectWithSprite(panel.square, case.sprite)), ",")
                        == table.concat(self.reads[case.name].overlays, ",")
                end, "this client's overlays of " .. case.what)
            end
        end)
    end,
    validate = function(self)
        for _, case in ipairs(SHOWN) do
            local server = table.concat(self.reads[case.name].overlays, ",")
            expectEqual("what " .. case.what .. " shows", server, case.shows)
        end
    end,
})

-- The item a tile without a CustomItem is picked up as (ISMoveableSpriteProps:instanceItem).
local function moveableType(sprite)
    return instanceItem("Moveables." .. sprite):getFullType()
end

-- Picks up the object drawn as `sprite` on `handle` and puts it down on another free square as a
-- player does, with the moveables action. Returns the new place's handle, of the record kind
-- `kind` if given, or nil without a free square.
local function carryAway(self, handle, sprite, kind)
    T.pickUpAsPlayer(self, handle, sprite)
    local square = T.square(self, {}, "a free square to put the " .. sprite .. " down on")
    if not square then return nil end
    local placed = T.placeAsPlayer(self, square, moveableType(sprite), sprite, nil, true)
    placed.kind = kind
    return placed
end

-- A digester, a gasifier and a wind charger the world leaves out to be found, picked up and put
-- down somewhere else, go down as they were: the digester its gas, sludge, souring, tarp bag and
-- its wear, scrubber and charge and compressor, the gasifier its tar, ash and condensate, the wind
-- charger its broken blades and brake. Catches each starting over as newly built.
test("renewable_energy_tiles_built_in_place_carry_their_state", {
    instant = true,
    run = function(self)
        local digester = T.placeRecord(self, "digester", "barrel.MetalDrum")
        local gasifier = digester and T.placeRecord(self, "gasifier", "primitive")
        local square = gasifier and T.square(self, {}, "a free outdoor square for a wind charger")
        local chargerSprite = Sprites.windCharger.propeller.wood.S
        local charger = square and T.placeTile(self, square, chargerSprite, { [Wind.BROKEN_KEY] = true, [Wind.BRAKED_KEY] = true })
        if not charger then return end
        -- Sour with the acid that keeps it so through the pass its pickup brings it up to now with.
        T.setRecord(self, digester, T.sourDigester("barrel", {
            gas = 0.4, sludge = 30, holder = "tarp", holderCondition = 60,
            scrubber = true, scrubCO2 = 12, scrubWool = 7, compressor = true,
        }))
        T.setRecord(self, gasifier, { tarKg = 1.5, ash = 0.8, condensate = 0.6 })
        T.readRecord(self, digester, "digesterBefore")
        T.readRecord(self, gasifier, "gasifierBefore")
        local digesterSprite = Sprites.digester.barrel.MetalDrum
        local movedDigester = carryAway(self, digester, digesterSprite, "digester")
        local movedGasifier = movedDigester and carryAway(self, gasifier, Sprites.gasifier.primitive, "gasifier")
        local movedCharger = movedGasifier and carryAway(self, charger, chargerSprite)
        if not movedCharger then return end
        T.readRecord(self, movedDigester, "digesterAfter")
        T.readRecord(self, movedGasifier, "gasifierAfter")
        T.step(function()
            local data = movedCharger.object:getModData()
            self.charger = { broken = data[Wind.BROKEN_KEY], braked = data[Wind.BRAKED_KEY] }
        end)
    end,
    validate = function(self)
        local before, after = self.reads.digesterBefore, self.reads.digesterAfter
        for _, field in ipairs({ "holder", "sour", "scrubber", "compressor", "started", "tier" }) do
            expectEqual("the moved digester's " .. field, after[field], before[field])
        end
        for _, field in ipairs({ "gas", "sludge", "holderCondition", "scrubCO2", "scrubWool" }) do
            T.expectNear("the moved digester's " .. field, after[field], before[field], 0.05)
        end
        for _, field in ipairs({ "tarKg", "ash", "condensate" }) do
            T.expectNear("the moved gasifier's " .. field, self.reads.gasifierAfter[field], self.reads.gasifierBefore[field], 0.01)
        end
        expect(self.charger.broken == true, "the moved wind charger's blades aren't broken")
        expect(self.charger.braked == true, "the moved wind charger's brake isn't on")
    end,
})

-- A gasifier still burning can't be picked up, as a running generator can't, and the cursor's
-- panel says to put it out.
test("renewable_energy_tiles_lit_gasifier_not_picked_up", {
    instant = true,
    run = function(self)
        local gasifier = T.placeRecord(self, "gasifier", "primitive")
        if not gasifier then return end
        T.setRecord(self, gasifier, { lit = true, fireKg = 1 })
        T.waitForSummary(self, gasifier, function(summary) return summary.lit end, "this client's summary of the lit gasifier")
        T.step(function()
            local character, object = T.player(), gasifier.object
            local props = ISMoveableSpriteProps.fromObject(object)
            self.pickUp = props:canPickUpMoveable(character, gasifier.square, object)
            local refusal = "- " .. getText("Tooltip_RenewableEnergy_PutOutFirst")
            for _, line in ipairs(props:getInfoPanelDescription(gasifier.square, object, character, "pickup")) do
                self.says = self.says or line[1].txt == refusal
            end
        end)
    end,
    validate = function(self)
        expect(not self.pickUp, "the cursor picks up a lit gasifier")
        expect(self.says, "the cursor's panel doesn't say to put the gasifier out")
    end,
})

-- A gasifier piped to a generator can't be picked up, as a connected source can't, and the
-- cursor's panel says to disconnect it first. Catches the pipe lost to a pickup.
test("renewable_energy_tiles_piped_gasifier_not_picked_up", {
    instant = true,
    run = function(self)
        local generator, gasifier = T.gasifierBeside(self, "primitive")
        if not gasifier then return end
        T.fitAndConnect(self, generator, gasifier)
        T.waitForSummary(self, gasifier, function(summary) return summary.piped end, "this client's summary of the piped gasifier")
        T.step(function()
            local character, object = T.player(), gasifier.object
            local props = ISMoveableSpriteProps.fromObject(object)
            self.pickUp = props:canPickUpMoveable(character, gasifier.square, object)
            local refusal = "- " .. getText("Tooltip_RenewableEnergy_DisconnectFirst")
            for _, line in ipairs(props:getInfoPanelDescription(gasifier.square, object, character, "pickup")) do
                self.says = self.says or line[1].txt == refusal
            end
        end)
    end,
    validate = function(self)
        expect(not self.pickUp, "the cursor picks up a piped gasifier")
        expect(self.says, "the cursor's panel doesn't say to disconnect the gasifier first")
    end,
})
