-- The mod's tile sprites by what they show, and back.
--
-- art/models renders every tile of renewable_energy_01 from the same Blender models as the
-- item icons and ground models, and tools/make_tiles.py gives each placed tile its properties.
-- Lua names tiles only through this file, so a new layout changes nothing else.

require "RenewableEnergy/Specs"

RenewableEnergy = RenewableEnergy or {}
local Specs = RenewableEnergy.Specs

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

-- Biogas digesters, built in place, one facing each.
Sprites.digester = { barrel = { steel = tile(228), plastic = tile(229) }, insulated = tile(230), dome = tile(231) }
-- Their gas holders, drawn over the digester's own tile: `bags` and `tarp` beside either barrel,
-- from 1 (slack) to 3 (taut), or torn; `drum` the insulated digester's floating drum, from 1 (low)
-- to 4 (risen highest).
Sprites.digesterHolder = {
    bags = tiles(232, 3),
    bagsTorn = tile(235),
    tarp = tiles(236, 3),
    tarpTorn = tile(239),
    drum = tiles(240, 4),
}
-- The scrubber fitted to each digester, drawn over the digester's own tile.
Sprites.digesterScrubber = { barrel = tile(247), insulated = tile(248), dome = tile(249) }
-- The homemade gas heater, one facing; both tiles give the heater back.
Sprites.gasHeater = { off = tile(244), lit = tile(245) }
-- The gas kit fitted to a generator, drawn over the game's own generator tile in any facing.
Sprites.gasKit = tile(246)

-- Snow lying on a panel, drawn over the panel's own tile. Wall panels are upright and hold none.
Sprites.snow = {
    flat = tile(16),
    rack = {
        wood = { S = tile(28), E = tile(29), N = tile(30), W = tile(31) },
        metal = { S = tile(17), E = tile(18), N = tile(19), W = tile(20) },
    },
}

-- A cracked module's glass, drawn over its mount's tile. A rack has one per module slot, slot 1
-- the lower module, so it shows only the modules that are cracked.
Sprites.cracks = {
    flat = tile(115),
    wall = {
        wood = { S = tile(118), E = tile(119) },
        metal = { S = tile(116), E = tile(117) },
    },
    rack = {
        wood = { S = tiles(128, 2), E = tiles(130, 2), N = tiles(132, 2), W = tiles(134, 2) },
        metal = { S = tiles(120, 2), E = tiles(122, 2), N = tiles(124, 2), W = tiles(126, 2) },
    },
}

-- Each bank tile's overlays: `batteries[look][n]` shows a battery of that look in slot n, linked
-- to the one before it, and `meter[level]` its charge meter lit from 1 (empty) to the last level
-- (full). A bank draws one battery overlay per battery it holds, in slot order, then its meter.
Sprites.bankFill = {
    batteryBoxWood = { batteries = { car = tiles(36, 2), deepCycle = tiles(136, 2), l16 = tiles(182, 2) },
        meter = tiles(48, 5) },
    batteryBoxMetal = { batteries = { car = tiles(38, 2), deepCycle = tiles(138, 2), l16 = tiles(184, 2) },
        meter = tiles(53, 5) },
    batteryRackWood = { batteries = { car = tiles(73, 6), deepCycle = tiles(140, 6), l16 = tiles(186, 6) },
        meter = tiles(58, 5) },
    batteryRackMetal = { batteries = { car = tiles(79, 8), deepCycle = tiles(146, 8), l16 = tiles(192, 8) },
        meter = tiles(63, 5) },
    batteryBankWood = { batteries = { car = tiles(87, 12), deepCycle = tiles(154, 12), l16 = tiles(200, 12) },
        meter = tiles(68, 5) },
    batteryBankMetal = { batteries = { car = tiles(99, 16), deepCycle = tiles(166, 16), l16 = tiles(212, 16) },
        meter = tiles(40, 5) },
}
-- The look a battery's overlay draws it with, by item type: any other battery is drawn as a car
-- battery.
local BATTERY_LOOKS = { ["RenewableEnergy.DeepCycleBattery"] = "deepCycle", ["RenewableEnergy.L16Battery"] = "l16" }
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

local function addAll(set, names)
    for _, name in pairs(names) do
        set[name] = true
    end
end

local SNOW, CRACKS, OVERLAYS = {}, {}, {}
SNOW[Sprites.snow.flat] = true
for _, facings in pairs(Sprites.snow.rack) do
    addAll(SNOW, facings)
end
CRACKS[Sprites.cracks.flat] = true
for _, facings in pairs(Sprites.cracks.wall) do
    addAll(CRACKS, facings)
end
for _, facings in pairs(Sprites.cracks.rack) do
    for _, slots in pairs(facings) do
        addAll(CRACKS, slots)
    end
end
for _, set in ipairs({ SNOW, CRACKS }) do
    for name in pairs(set) do
        OVERLAYS[name] = true
    end
end
addAll(OVERLAYS, Sprites.crateOverlays)
for _, fill in pairs(Sprites.bankFill) do
    for _, slots in pairs(fill.batteries) do
        addAll(OVERLAYS, slots)
    end
    addAll(OVERLAYS, fill.meter)
end
for _, holder in pairs(Sprites.digesterHolder) do
    if type(holder) == "table" then
        addAll(OVERLAYS, holder)
    else
        OVERLAYS[holder] = true
    end
end
addAll(OVERLAYS, Sprites.digesterScrubber)
OVERLAYS[Sprites.gasKit] = true

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

--- The sprite name of a placed object, or nil for anything else or an object without a sprite.
function Sprites.nameOf(isoObject)
    if not instanceof(isoObject, "IsoObject") then
        return nil
    end
    local sprite = isoObject:getSprite()
    return sprite and sprite:getName()
end

--- Whether a sprite is one of the overlays above, which are never placed on their own.
function Sprites.isOverlay(spriteName)
    return spriteName ~= nil and OVERLAYS[spriteName] == true
end

--- Whether a sprite is a crack overlay of Sprites.cracks.
function Sprites.isCrack(spriteName)
    return spriteName ~= nil and CRACKS[spriteName] == true
end

--- Whether a sprite is a snow overlay of Sprites.snow.
function Sprites.isSnow(spriteName)
    return spriteName ~= nil and SNOW[spriteName] == true
end

-- A mount's crack overlays by module slot.
local function crackSlots(kind, facing, material)
    if kind == "flat" then
        return { Sprites.cracks.flat }
    end
    local mount = Sprites.cracks[kind] and Sprites.cracks[kind][material]
    local slots = mount and mount[facing]
    if type(slots) == "string" then
        return { slots }
    end
    return slots or {}
end

--- The crack overlays a mount's tile shows: one for each module below Specs.crackedBelow, by slot.
---@param kind string "flat", "wall" or "rack" (see kindOf)
---@param facing string? the mount's facing, for walls and racks
---@param material string? "wood" or "metal", for walls and racks
---@param modules table[] the mount's { type, condition } modules in slot order
---@return string[]
function Sprites.crackOverlays(kind, facing, material, modules)
    local shown = {}
    for slot, name in ipairs(crackSlots(kind, facing, material)) do
        local module = modules[slot]
        if module and module.condition < Specs.crackedBelow then
            table.insert(shown, name)
        end
    end
    return shown
end

--- The meter level, from 1 (empty), that shows a charge fraction.
function Sprites.meterLevel(chargeFraction)
    for level, limit in ipairs(METER_LIMITS) do
        if chargeFraction < limit then
            return level
        end
    end
    return #METER_LIMITS + 1
end

--- The look a battery's overlay draws it with: "car", "deepCycle" or "l16" (Sprites.bankFill).
---@param fullType string the battery's item type
---@return string
function Sprites.batteryLook(fullType)
    return BATTERY_LOOKS[fullType] or "car"
end

--- The overlays a bank's tile shows for its batteries and charge, in drawing order: each battery
--- in its slot, as many as the tile has slots, then the meter. A bank without batteries shows
--- none: its meter has nothing to read.
---@param bankSpriteField string the bank's Sprites field, such as "batteryRackWood"
---@param batteryTypes string[] the item types of the batteries it holds, in slot order
---@param chargeFraction number stored over capacity, 0 to 1
---@return string[]
function Sprites.bankOverlays(bankSpriteField, batteryTypes, chargeFraction)
    local fill = Sprites.bankFill[bankSpriteField]
    if not fill or #batteryTypes == 0 then
        return {}
    end
    local shown = {}
    for slot = 1, math.min(#batteryTypes, #fill.batteries.car) do
        shown[slot] = fill.batteries[Sprites.batteryLook(batteryTypes[slot])][slot]
    end
    table.insert(shown, fill.meter[Sprites.meterLevel(chargeFraction)])
    return shown
end

return Sprites
