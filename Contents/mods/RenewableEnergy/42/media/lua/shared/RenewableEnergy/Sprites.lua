-- The mod's tile sprites by what they show, and back.
--
-- art/models renders every tile of renewable_energy_01 from the same Blender models as the
-- item icons and ground models, and tools/make_tiles.py gives each placed tile its properties.
-- Lua names tiles only through this file, so a new layout changes nothing else.

RenewableEnergy = RenewableEnergy or {}

local Sprites = {}
RenewableEnergy.Sprites = Sprites

Sprites.TILESET = "renewable_energy_01"

local function tile(index)
    return Sprites.TILESET .. "_" .. index
end

-- `count` tiles numbered from `first`, in order.
local function tiles(first, count)
    local list = {}
    for i = 1, count do
        list[i] = tile(first + i - 1)
    end
    return list
end

-- Placed objects. Each tile's CustomItem is the item that picking it up gives back.
Sprites.flat = tile(0)
-- Wall tiles hang on their square's north edge (attachedN, facing south) or its west edge
-- (attachedW, facing east): the only two edges a square's walls are on.
Sprites.wall = {
    wood = { S = tile(21), E = tile(22) },
    metal = { S = tile(1), E = tile(2) },
}
Sprites.rack = {
    wood = { S = tile(24), E = tile(25), N = tile(26), W = tile(27) },
    metal = { S = tile(3), E = tile(4), N = tile(5), W = tile(6) },
}
Sprites.failsafe = tile(7)
Sprites.cellCharger = tile(10)
-- The cardboard crate of solar modules that world spawns and stashes place, and its overlays.
Sprites.crate = tile(11)
Sprites.crateOverlays = { full = tile(12), closed = tile(13) }
Sprites.gardenLight = { off = tile(14), lit = tile(15) }

-- Banks, one tile per tier and material. Specs.banks[itemType].sprite names the field.
Sprites.batteryBoxWood = tile(8)
Sprites.batteryBoxMetal = tile(23)
Sprites.batteryRackWood = tile(32)
Sprites.batteryRackMetal = tile(33)
Sprites.batteryBankWood = tile(34)
Sprites.batteryBankMetal = tile(9)

-- Snow lying on a panel, drawn over the panel's own tile. Wall panels are upright and hold none.
Sprites.snow = {
    flat = tile(16),
    rack = {
        wood = { S = tile(28), E = tile(29), N = tile(30), W = tile(31) },
        metal = { S = tile(17), E = tile(18), N = tile(19), W = tile(20) },
    },
}

-- Each bank tile's overlays: `batteries[n]` shows n batteries in it, `meter[level]` its charge
-- meter lit from 1 (empty) to 5 (full).
Sprites.bankFill = {
    batteryBoxWood = { batteries = tiles(36, 2), meter = tiles(48, 5) },
    batteryBoxMetal = { batteries = tiles(38, 2), meter = tiles(53, 5) },
    batteryRackWood = { batteries = tiles(73, 6), meter = tiles(58, 5) },
    batteryRackMetal = { batteries = tiles(79, 8), meter = tiles(63, 5) },
    batteryBankWood = { batteries = tiles(87, 12), meter = tiles(68, 5) },
    batteryBankMetal = { batteries = tiles(99, 16), meter = tiles(40, 5) },
}
-- The charge fraction each meter level starts below.
local METER_LIMITS = { 0.10, 0.35, 0.65, 0.95 }

-- Sprite name to { kind, facing, material }; facing and material are nil where there's none.
local KINDS = {
    [Sprites.flat] = { "flat" },
    [Sprites.failsafe] = { "failsafe" },
    [Sprites.cellCharger] = { "cellCharger" },
    [Sprites.crate] = { "crate" },
    [Sprites.gardenLight.off] = { "gardenLight" },
    [Sprites.gardenLight.lit] = { "gardenLight" },
}
for _, mount in ipairs({ "wall", "rack" }) do
    for material, facings in pairs(Sprites[mount]) do
        for facing, name in pairs(facings) do
            KINDS[name] = { mount, facing, material }
        end
    end
end
for field in pairs(Sprites.bankFill) do
    KINDS[Sprites[field]] = { field, nil, field:find("Wood$") and "wood" or "metal" }
end

local OVERLAYS = {}
local function addOverlays(list)
    for _, name in pairs(list) do
        OVERLAYS[name] = true
    end
end
addOverlays(Sprites.crateOverlays)
addOverlays({ Sprites.snow.flat })
for _, facings in pairs(Sprites.snow.rack) do
    addOverlays(facings)
end
for _, fill in pairs(Sprites.bankFill) do
    addOverlays(fill.batteries)
    addOverlays(fill.meter)
end

--- What a placed tile is.
---@param spriteName string?
---@return string? kind "flat", "wall", "rack", "failsafe", "cellCharger", "crate", "gardenLight", or a bank's Sprites field such as "batteryRackWood"; nil for any other sprite
---@return string? facing "S", "E", "N" or "W" for walls and racks
---@return string? material "wood" or "metal" for walls, racks and banks
function Sprites.kindOf(spriteName)
    local entry = spriteName and KINDS[spriteName]
    if not entry then
        return nil
    end
    return entry[1], entry[2], entry[3]
end

--- Whether a sprite is one of the overlays above, which are never placed on their own.
function Sprites.isOverlay(spriteName)
    return spriteName ~= nil and OVERLAYS[spriteName] == true
end

--- The meter level, 1 to 5, that shows a charge fraction.
function Sprites.meterLevel(chargeFraction)
    for level, limit in ipairs(METER_LIMITS) do
        if chargeFraction < limit then
            return level
        end
    end
    return #METER_LIMITS + 1
end

--- The overlays a bank's tile shows for its batteries and charge, in drawing order. A bank
--- without batteries shows none: its meter has nothing to read.
---@param bankSpriteField string the bank's Sprites field, such as "batteryRackWood"
---@param batteries integer how many batteries it holds
---@param chargeFraction number stored over capacity, 0 to 1
---@return string[]
function Sprites.bankOverlays(bankSpriteField, batteries, chargeFraction)
    local fill = Sprites.bankFill[bankSpriteField]
    if not fill or batteries <= 0 then
        return {}
    end
    return {
        fill.batteries[math.min(batteries, #fill.batteries)],
        fill.meter[Sprites.meterLevel(chargeFraction)],
    }
end

return Sprites
