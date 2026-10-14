require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Specs"
require "RenewableEnergy/PowerBank/PowerBank"
require "RenewableEnergy/Gadgets/SolarGardenLight"
require "Moveables/ISMoveableSpriteProps"
require "Moveables/ISMoveableDefinitions"

-- Tests of the tiles in renewable_energy.tiles and the pack, as Sprites.lua names them: their
-- pictures, overlays and properties, and placing and picking them up. See
-- RenewableEnergyTestLib.lua for how the runner works.

local T = RenewableEnergyTest
local test, expect = T.test, T.expect

local Sprites, Specs = RenewableEnergy.Sprites, RenewableEnergy.Specs
local PowerBank, SolarGardenLight = RenewableEnergy.PowerBank, RenewableEnergy.SolarGardenLight

local MATERIALS = { "wood", "metal" }

local PLACED = T.PLACED_TILES

-- Every overlay tile Sprites.lua names.
local function overlays()
    local all = { Sprites.crateOverlays.full, Sprites.crateOverlays.closed, Sprites.snow.flat, Sprites.cracks.flat }
    local function add(list)
        for _, name in pairs(list) do
            table.insert(all, name)
        end
    end
    for _, facings in pairs(Sprites.snow.rack) do
        add(facings)
    end
    for _, facings in pairs(Sprites.cracks.wall) do
        add(facings)
    end
    for _, facings in pairs(Sprites.cracks.rack) do
        for _, slots in pairs(facings) do
            add(slots)
        end
    end
    for _, fill in pairs(Sprites.bankFill) do
        for _, slots in pairs(fill.batteries) do
            add(slots)
        end
        add(fill.meter)
    end
    return all
end

local function properties(spriteName)
    local sprite = getSprite(spriteName)
    return sprite and sprite:getProperties()
end

test("renewable_energy_tiles_have_pictures", {
    validate = function()
        local names = { Sprites.crate }
        for _, placed in ipairs(PLACED) do
            table.insert(names, placed.sprite)
        end
        for _, name in ipairs(overlays()) do
            table.insert(names, name)
        end
        for _, name in ipairs(names) do
            expect(getSprite(name) ~= nil, name .. " is not a tile in renewable_energy.tiles")
            expect(getTexture(name) ~= nil, name .. " has no picture in the pack")
        end
    end,
})

test("renewable_energy_tiles_moveable_items_place_their_tiles", {
    validate = function()
        for _, placed in ipairs(PLACED) do
            local script = getScriptManager():getItem(placed.item)
            local kind, _, material = Sprites.kindOf(script and script:getWorldObjectSprite())
            expect(kind == placed.kind and material == placed.material, string.format("%s places a %s %s tile, expected %s %s",
                placed.item, tostring(material), tostring(kind), tostring(placed.material), placed.kind))
        end
    end,
})

test("renewable_energy_tiles_kind_of_reads_every_placed_tile", {
    validate = function()
        for _, placed in ipairs(PLACED) do
            local kind, facing, material = Sprites.kindOf(placed.sprite)
            expect(kind == placed.kind and facing == placed.facing and material == placed.material,
                string.format("kindOf(%s) is %s %s %s, expected %s %s %s", placed.sprite, tostring(kind), tostring(facing),
                    tostring(material), placed.kind, tostring(placed.facing), tostring(placed.material)))
            expect(not Sprites.isOverlay(placed.sprite), placed.sprite .. " counts as an overlay")
        end
        for _, name in ipairs(overlays()) do
            expect(Sprites.isOverlay(name), name .. " does not count as an overlay")
            expect(Sprites.kindOf(name) == nil, name .. " has a kind")
        end
        expect(Sprites.kindOf("carpentry_01_16") == nil, "a vanilla crate has a kind")
    end,
})

-- The placing cursor turns a rack through all four facings and a wall panel between its two,
-- without turning wood into metal.
test("renewable_energy_tiles_mounts_rotate", {
    validate = function()
        for _, mount in ipairs({ "rack", "wall" }) do
            for _, material in ipairs(MATERIALS) do
                local set = Sprites[mount][material]
                for facing, name in pairs(set) do
                    local faces = ISMoveableSpriteProps.new(name):getFaces()
                    for otherFacing, otherName in pairs(set) do
                        expect(faces[otherFacing] == otherName, string.format("%s (%s %s) turns %s to %s, expected %s",
                            name, material, facing, otherFacing, tostring(faces[otherFacing]), otherName))
                    end
                end
            end
        end
    end,
})

-- Every battery a bank can hold shows in its own slot, as its type, and the meter reads its
-- charge: it climbs with the charge, through every level, from its lowest empty to its highest full.
test("renewable_energy_tiles_bank_overlays", {
    validate = function()
        local levels
        for itemType, bank in pairs(Specs.banks) do
            local fill = Sprites.bankFill[bank.sprite]
            if expect(fill ~= nil, itemType .. " has no battery overlays") then
                levels = #fill.meter
                for look, slots in pairs(fill.batteries) do
                    expect(#slots == bank.maxBatteries, string.format("%s shows up to %d %s batteries but holds %d",
                        itemType, #slots, look, bank.maxBatteries))
                end
                local cars = {}
                for i = 1, bank.maxBatteries + 1 do
                    cars[i] = "Base.CarBattery1"
                end
                local full = Sprites.bankOverlays(bank.sprite, cars, 1)
                expect(#full == bank.maxBatteries + 1 and full[bank.maxBatteries] == fill.batteries.car[bank.maxBatteries]
                    and full[#full] == fill.meter[levels], "an overfull " .. itemType .. " shows " .. table.concat(full, ", "))
                local mixed = Sprites.bankOverlays(bank.sprite, { "RenewableEnergy.L16Battery", "RenewableEnergy.DeepCycleBattery" }, 0)
                expect(#mixed == 3 and mixed[1] == fill.batteries.l16[1] and mixed[2] == fill.batteries.deepCycle[2]
                    and mixed[3] == fill.meter[1], "an empty L-16 and deep-cycle in " .. itemType .. " show " .. table.concat(mixed, ", "))
                expect(#Sprites.bankOverlays(bank.sprite, {}, 1) == 0, "an empty " .. itemType .. " shows overlays")
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

-- Every bank tile switches with a click, not a gas generator's pull-start and shutdown: the
-- generator plays its tile's GeneratorSound prefix + Starting or Stopping.
test("renewable_energy_tiles_bank_switch_sounds", {
    validate = function()
        for field in pairs(Sprites.bankFill) do
            local props = properties(Sprites[field])
            local prefix = props and props:get("GeneratorSound")
            if expect(prefix ~= nil, field .. " has no GeneratorSound and plays the gas generator's") then
                for _, suffix in ipairs({ "Starting", "Stopping" }) do
                    expect(GameSounds.isKnownSound(prefix .. suffix), field .. "'s sound " .. prefix .. suffix .. " is not defined")
                end
            end
        end
    end,
})

-- Scrapping a bank finishes on the server, which only has shared Lua, so the definitions for the
-- banks' tile Materials must come from shared Lua, with an Electricity check and parts back.
test("renewable_energy_tiles_bank_scrap_definitions", {
    validate = function()
        local defs = ISMoveableDefinitions:getInstance()
        for field in pairs(Sprites.bankFill) do
            local material = "RenewableEnergy" .. field:gsub("^%l", string.upper)
            local def = defs.getScrapDefinition(material)
            if expect(def ~= nil and defs.isScrapDefinitionValid(material), material .. " has no valid scrap definition") then
                expect(def.perk == Perks.Electricity, "scrapping " .. material .. " does not use Electricity")
                expect(#def.returnItemsStatic > 0, "scrapping " .. material .. " returns nothing")
            end
        end
    end,
})

-- The tiles' PickUpTool and PlaceTool, Electrician, are a screwdriver and some Electricity.
local function electrician(self)
    T.setPerk(self, Perks.Electricity, 10)
    T.give(self, "screwdriver", { { type = "Base.Screwdriver" } })
end

-- What a kind keeps in its modData from item to placed object and back: a mount each module's
-- condition and whether it was mounted or connected before, and a garden light its charge. The
-- gadget tests follow the light's bulb (renewable_energy_gadgets_garden_light_pick_up_keeps_bulb).
local MODULES = {
    { type = "RenewableEnergy.HomemadeSolarModule", condition = 41 },
    { type = "RenewableEnergy.SolarModule", condition = 72, mounted = true, connected = true },
}
local CARRIED = {
    ["RenewableEnergy.SolarRackWood"] = { key = PowerBank.MODULES, value = MODULES },
    ["RenewableEnergy.SolarFlat"] = { key = PowerBank.MODULES, value = { MODULES[1] } },
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

-- Every placed tile's CustomItem names its item, so picking it up gives that item and nothing
-- else (without one the game hands back a generic Moveable). And each item's own tile, placed and
-- picked up the way a player does, comes back as the item, with a container only on the tiles that
-- hold items, and with what CARRIED says it keeps. Wall panels need a wall to hang on, and the
-- other facings are the same item's (renewable_energy_tiles_mounts_rotate turns them), so only the
-- tile an item places is placed.
test("renewable_energy_tiles_place_and_pick_up", {
    instant = true,
    run = function(self)
        local square = T.need(self, (T.squares(self, 1, { bare = true }) or {})[1], "a free outdoor square")
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
                    T.step(function() result.container = handle.object ~= nil and handle.object:getContainer() ~= nil end)
                    if carried then
                        T.server(self, "objectModData", { x = square:getX(), y = square:getY(), z = square:getZ(),
                            sprite = placed.sprite, key = carried.key })
                        T.step(function() result.placedData = describe(self.server.objectModData.value) end)
                    end
                    T.pickUpAsPlayer(self, handle, placed.sprite)
                    T.server(self, "carried", { types = { placed.item } })
                    T.step(function()
                        local items = self.server.carried.items[placed.item]
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
        for _, placed in ipairs(PLACED) do
            local props = properties(placed.sprite)
            local customItem = props and props:get("CustomItem")
            expect(customItem == placed.item, placed.sprite .. " gives " .. tostring(customItem) .. ", expected " .. placed.item)
        end
        expect(#self.results > 0, "no item places one of the tiles")
        local kept = {}
        for _, r in ipairs(self.results) do
            local what = r.placed.sprite .. " (" .. r.placed.item .. ")"
            expect(r.container == (r.placed.container == true), what .. (r.placed.container and " has no container" or " has a container"))
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

local function modulesAt(...)
    local modules = {}
    for i, condition in ipairs({ ... }) do
        modules[i] = { type = "RenewableEnergy.SolarModule", condition = condition }
    end
    return modules
end

-- A module below Specs.crackedBelow shows cracked glass on the mount placed with it, a rack only
-- over the cracked module's slot; one at it shows whole. Repairing the module takes the cracks
-- off, and snow already lying on a panel stays drawn over cracks added under it. The panels are
-- placed and changed on the authority (panelCracks); what is checked is what this client shows,
-- the same as the authority's.
local CRACKED_AT, WHOLE_AT = Specs.crackedBelow - 1, Specs.crackedBelow
local CRACKED = {
    { name = "flatCracked", sprite = Sprites.flat, modules = modulesAt(CRACKED_AT), shows = "renewable_energy_01_115",
        what = "a flat panel just below the crack" },
    { name = "flatWhole", sprite = Sprites.flat, modules = modulesAt(WHOLE_AT), shows = "", what = "a flat panel at the crack" },
    { name = "rackUpper", sprite = Sprites.rack.metal.W, modules = modulesAt(100, CRACKED_AT), shows = "renewable_energy_01_127",
        what = "a metal rack facing west with its upper module cracked" },
    { name = "rackBoth", sprite = Sprites.rack.wood.E, modules = modulesAt(0, CRACKED_AT),
        shows = "renewable_energy_01_130,renewable_energy_01_131", what = "a wooden rack facing east with both modules cracked" },
    -- A wall panel needs a wall to be placed against, so this one is a bare tile.
    { name = "wall", sprite = Sprites.wall.wood.E, modules = modulesAt(CRACKED_AT), shows = "renewable_energy_01_119",
        what = "a cracked wooden wall panel facing east" },
    { name = "repaired", sprite = Sprites.flat, modules = modulesAt(CRACKED_AT), change = { modules = modulesAt(85) }, shows = "",
        what = "a cracked flat panel repaired to 85" },
    { name = "snowed", sprite = Sprites.flat, modules = modulesAt(100), change = { modules = modulesAt(30), snow = true },
        shows = "renewable_energy_01_115,renewable_energy_01_16", what = "a snowed-on flat panel at 30" },
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
                T.server(self, "panelCracks", { x = at.x, y = at.y, z = at.z, sprite = case.sprite, change = case.change })
                T.waitForCopy(function()
                    return T.overlays(T.objectWithSprite(panel.square, case.sprite)) == table.concat(self.server.panelCracks.overlays, ",")
                end)
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

-- The dev mod's remove hook takes away the tiles T.placeTile places, as it does every other
-- fixture's: the harness reads one registration on both sides. A stand-in hook notes the tile and
-- hands it on to the mod's. The check runs as an undo, since the tile goes only when the test
-- ends; a multiplayer server takes it away in its own Lua, where the stand-in isn't.
test("renewable_energy_tiles_remove_hook_takes_placed_tile", {
    spOnly = "the server removes the tile in its own Lua, out of the stand-in hook's reach",
    run = function(self)
        local sprite = PZHarness.Fixtures.WORK_TABLE_SPRITE
        -- Not next to the character, where it would count as the craft tests' work table.
        local square = T.need(self, (T.squares(self, 1, { bare = true, minDistance = 2 }) or {})[1], "a free outdoor square")
        if not square then return end
        local settings = PZHarness.testSettings
        local hook, taken = settings.remove, false
        -- Undos run newest first: the tile's, then the check, then the hook goes back.
        T.defer(self, function() settings.remove = hook end)
        T.defer(self, function()
            expect(taken, "the tile T.placeTile placed went without the dev mod's remove hook")
        end)
        settings.remove = function(object)
            taken = taken or (object:getSquare() == square and object:getSprite():getName() == sprite)
            return hook(object)
        end
        T.placeTile(self, square, sprite)
    end,
})
