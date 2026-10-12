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

local Sprites = RenewableEnergy.Sprites
local Specs = RenewableEnergy.Specs

local MATERIALS = { wood = "Wood", metal = "Metal" }

local PLACED = RenewableEnergyTest.PLACED_TILES

local function overlays()
    local all = { Sprites.crateOverlays.full, Sprites.crateOverlays.closed, Sprites.snow.flat }
    local function add(list)
        for _, name in pairs(list) do
            table.insert(all, name)
        end
    end
    for _, facings in pairs(Sprites.snow.rack) do
        add(facings)
    end
    for _, fill in pairs(Sprites.bankFill) do
        add(fill.batteries)
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
            for material in pairs(MATERIALS) do
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

-- Every battery a bank can hold shows, and the meter reads its charge.
test("renewable_energy_tiles_bank_overlays", {
    validate = function()
        for itemType, bank in pairs(Specs.banks) do
            local fill = Sprites.bankFill[bank.sprite]
            if expect(fill ~= nil, itemType .. " has no battery overlays") then
                expect(#fill.batteries == bank.maxBatteries, string.format("%s shows up to %d batteries but holds %d",
                    itemType, #fill.batteries, bank.maxBatteries))
                local full = Sprites.bankOverlays(bank.sprite, bank.maxBatteries, 1)
                expect(full[1] == fill.batteries[bank.maxBatteries] and full[2] == fill.meter[5],
                    "a full " .. itemType .. " shows " .. table.concat(full, ", "))
                local one = Sprites.bankOverlays(bank.sprite, 1, 0.05)
                expect(one[1] == fill.batteries[1] and one[2] == fill.meter[1],
                    "one battery at 5% in " .. itemType .. " shows " .. table.concat(one, ", "))
                expect(#Sprites.bankOverlays(bank.sprite, 0, 1) == 0, "an empty " .. itemType .. " shows overlays")
            end
        end
        for fraction, level in pairs({ [0] = 1, [0.2] = 2, [0.5] = 3, [0.8] = 4, [0.96] = 5, [1] = 5 }) do
            expect(Sprites.meterLevel(fraction) == level,
                "charge " .. fraction .. " shows meter level " .. Sprites.meterLevel(fraction) .. ", expected " .. level)
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

-- Each tile placed from its item is picked up as that item and nothing else, the tile's
-- CustomItem deciding it (without one the game hands back a generic Moveable); containers are
-- only on the tiles that hold items.
test("renewable_energy_tiles_place_and_pick_up", {
    run = function(self)
        local square = T.need(self, (T.squares(self, 1, { bare = true }) or {})[1], "a free outdoor square")
        if not square then return end
        local inventory = T.player():getInventory()
        self.results = {}
        for _, placed in ipairs(PLACED) do
            -- The lit garden light is the unlit one switched on; its item places the unlit one.
            if placed.sprite ~= Sprites.gardenLight.lit then
                inventory:clear()
                local object = T.placeMoveable(self, square, placed.item, placed.sprite)
                ISMoveableSpriteProps.new(placed.sprite):pickUpMoveable(T.player(), square, true, true)
                table.insert(self.results, {
                    placed = placed,
                    container = object and object:getContainer() ~= nil,
                    removed = T.objectWithSprite(square, placed.sprite) == nil,
                    returned = inventory:getCountTypeRecurse(placed.item),
                    items = inventory:getItems():size(),
                })
            end
        end
    end,
    validate = function(self)
        for _, r in ipairs(self.results) do
            local what = r.placed.sprite .. " (" .. r.placed.item .. ")"
            expect(r.container == (r.placed.container == true), what .. (r.placed.container and " has no container" or " has a container"))
            expect(r.removed, what .. " was not picked up")
            expect(r.returned == 1 and r.items == 1,
                what .. " gave back " .. r.items .. " items, " .. r.returned .. " of them " .. r.placed.item)
        end
    end,
})

-- A mount keeps each module's condition, and a garden light its charge, from item to placed
-- object and back.
local MODULES = {
    { type = "RenewableEnergy.HomemadeSolarModule", condition = 41 },
    { type = "RenewableEnergy.SolarModule", condition = 72 },
}
local CARRIED = {
    { Sprites.rack.wood.S, "RenewableEnergy.SolarRackWood", RenewableEnergy.PowerBank.MODULES, MODULES },
    { Sprites.flat, "RenewableEnergy.SolarFlat", RenewableEnergy.PowerBank.MODULES, { MODULES[1] } },
    { Sprites.gardenLight.off, RenewableEnergy.SolarGardenLight.ITEM, RenewableEnergy.SolarGardenLight.CHARGE_KEY, 2.5 },
}

local function describe(value)
    if type(value) ~= "table" then
        return tostring(value)
    end
    local parts = {}
    for _, module in ipairs(value) do
        table.insert(parts, tostring(module.type) .. "@" .. tostring(module.condition))
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

test("renewable_energy_tiles_pick_up_keeps_mod_data", {
    run = function(self)
        local square = T.need(self, (T.squares(self, 1, { bare = true }) or {})[1], "a free outdoor square")
        if not square then return end
        local inventory = T.player():getInventory()
        self.results = {}
        for _, entry in ipairs(CARRIED) do
            local sprite, fullType, key, value = entry[1], entry[2], entry[3], entry[4]
            inventory:clear()
            local object = T.placeMoveable(self, square, fullType, sprite, { [key] = value })
            local placed = describe(object and object:getModData()[key])
            ISMoveableSpriteProps.new(sprite):pickUpMoveable(T.player(), square, true, true)
            local item = inventory:getFirstTypeRecurse(fullType)
            table.insert(self.results, {
                what = fullType,
                expected = describe(value),
                placed = placed,
                pickedUp = describe(item and item:getModData()[key]),
            })
        end
    end,
    validate = function(self)
        for _, r in ipairs(self.results) do
            expect(r.placed == r.expected, "placed " .. r.what .. " holds " .. r.placed .. ", expected " .. r.expected)
            expect(r.pickedUp == r.expected, "picked-up " .. r.what .. " holds " .. r.pickedUp .. ", expected " .. r.expected)
        end
    end,
})
