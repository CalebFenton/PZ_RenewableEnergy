require "RenewableEnergy/Debug/RenewableEnergyTestLib"
require "RenewableEnergy/Sprites"
require "Moveables/ISMoveableSpriteProps"

-- Tests of the art: the tiles in renewable_energy.tiles and the pack, as Sprites.lua names them,
-- and the items' ground models. See RenewableEnergyTestLib.lua for how the runner works.

local test, expect = RenewableEnergyTest.test, RenewableEnergyTest.expect

local Sprites = RenewableEnergy.Sprites

-- Placed tile -> the item picking it up gives, and the kind and facing Sprites.kindOf reports.
local PLACED = {
    { sprite = Sprites.flat, item = "RenewableEnergy.SolarFlat", kind = "flat" },
    { sprite = Sprites.wall.S, item = "RenewableEnergy.SolarWall", kind = "wall", facing = "S" },
    { sprite = Sprites.wall.E, item = "RenewableEnergy.SolarWall", kind = "wall", facing = "E" },
    { sprite = Sprites.rack.S, item = "RenewableEnergy.SolarRack", kind = "rack", facing = "S" },
    { sprite = Sprites.rack.E, item = "RenewableEnergy.SolarRack", kind = "rack", facing = "E" },
    { sprite = Sprites.rack.N, item = "RenewableEnergy.SolarRack", kind = "rack", facing = "N" },
    { sprite = Sprites.rack.W, item = "RenewableEnergy.SolarRack", kind = "rack", facing = "W" },
    { sprite = Sprites.failsafe, item = "RenewableEnergy.SolarFailsafe", kind = "failsafe" },
    { sprite = Sprites.batteryBox, item = "RenewableEnergy.BatteryBox", kind = "batteryBox", container = true },
    { sprite = Sprites.batteryBank, item = "RenewableEnergy.BatteryBank", kind = "batteryBank", container = true },
    { sprite = Sprites.cellCharger, item = "RenewableEnergy.SolarCellCharger", kind = "cellCharger", container = true },
}

local function overlays()
    local all = { Sprites.crateOverlays.full, Sprites.crateOverlays.closed, Sprites.snow.flat }
    for _, list in ipairs({ Sprites.snow.rack, Sprites.bankBatteries, Sprites.boxBatteries, Sprites.bankMeter }) do
        for _, name in pairs(list) do
            table.insert(all, name)
        end
    end
    return all
end

local function properties(spriteName)
    local sprite = getSprite(spriteName)
    return sprite and sprite:getProperties()
end

test("renewable_energy_art_tiles_have_pictures", {
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

test("renewable_energy_art_placed_tiles_give_their_item", {
    validate = function()
        for _, placed in ipairs(PLACED) do
            local props = properties(placed.sprite)
            if expect(props ~= nil, placed.sprite .. " has no properties") then
                expect(props:has("IsMoveAble"), placed.sprite .. " can't be picked up")
                expect(props:get("CustomItem") == placed.item,
                    placed.sprite .. " gives " .. tostring(props:get("CustomItem")) .. ", expected " .. placed.item)
                expect(not placed.container or props:has("container"), placed.sprite .. " has no container")
            end
            expect(instanceItem(placed.item) ~= nil, placed.item .. " does not exist")
        end
    end,
})

test("renewable_energy_art_moveable_items_place_their_tiles", {
    validate = function()
        for _, placed in ipairs(PLACED) do
            local script = getScriptManager():getItem(placed.item)
            local placedKind = script and Sprites.kindOf(script:getWorldObjectSprite())
            expect(placedKind == placed.kind, placed.item .. " places a " .. tostring(placedKind) .. " tile, expected " .. placed.kind)
        end
    end,
})

test("renewable_energy_art_kind_of_reads_every_placed_tile", {
    validate = function()
        for _, placed in ipairs(PLACED) do
            local kind, facing = Sprites.kindOf(placed.sprite)
            expect(kind == placed.kind and facing == placed.facing, string.format("kindOf(%s) is %s %s, expected %s %s",
                placed.sprite, tostring(kind), tostring(facing), placed.kind, tostring(placed.facing)))
            expect(not Sprites.isOverlay(placed.sprite), placed.sprite .. " counts as an overlay")
        end
        for _, name in ipairs(overlays()) do
            expect(Sprites.isOverlay(name), name .. " does not count as an overlay")
            expect(Sprites.kindOf(name) == nil, name .. " has a kind")
        end
        expect(Sprites.kindOf("carpentry_01_16") == nil, "a vanilla crate has a kind")
    end,
})

-- The placing cursor turns a rack through all four facings and a wall panel between its two.
test("renewable_energy_art_mounts_rotate", {
    validate = function()
        for _, set in ipairs({ Sprites.rack, Sprites.wall }) do
            for facing, name in pairs(set) do
                local faces = ISMoveableSpriteProps.new(name):getFaces()
                for otherFacing, otherName in pairs(set) do
                    expect(faces[otherFacing] == otherName, string.format("%s (%s) turns %s to %s, expected %s",
                        name, facing, otherFacing, tostring(faces[otherFacing]), otherName))
                end
            end
        end
    end,
})

test("renewable_energy_art_bank_overlays", {
    validate = function()
        local full = Sprites.bankOverlays(Sprites.batteryBank, 12, 1)
        expect(#full == 2 and full[1] == Sprites.bankBatteries[12] and full[2] == Sprites.bankMeter[5],
            "a full bank of 12 shows " .. table.concat(full, ", "))
        local low = Sprites.bankOverlays(Sprites.batteryBank, 3, 0.05)
        expect(low[1] == Sprites.bankBatteries[3] and low[2] == Sprites.bankMeter[1],
            "3 batteries at 5% show " .. table.concat(low, ", "))
        local box = Sprites.bankOverlays(Sprites.batteryBox, 5, 0.5)
        expect(#box == 1 and box[1] == Sprites.boxBatteries[2], "a box shows " .. table.concat(box, ", "))
        expect(#Sprites.bankOverlays(Sprites.batteryBank, 0, 1) == 0, "an empty bank shows overlays")
        for fraction, level in pairs({ [0] = 1, [0.2] = 2, [0.5] = 3, [0.8] = 4, [0.96] = 5, [1] = 5 }) do
            expect(Sprites.meterLevel(fraction) == level,
                "charge " .. fraction .. " shows meter level " .. Sprites.meterLevel(fraction) .. ", expected " .. level)
        end
    end,
})

test("renewable_energy_art_items_have_ground_models", {
    validate = function()
        local items = getScriptManager():getAllItems()
        local checked = 0
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item:getModuleName() == "RenewableEnergy" then
                checked = checked + 1
                local model = item:getWorldStaticModel()
                expect(model ~= nil and getScriptManager():getModelScript(model) ~= nil,
                    item:getFullName() .. " has no ground model (" .. tostring(model) .. ")")
            end
        end
        expect(checked > 0, "no RenewableEnergy items")
    end,
})
