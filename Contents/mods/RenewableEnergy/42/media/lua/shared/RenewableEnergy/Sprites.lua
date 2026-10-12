-- The mod's tile sprites by what they show, and back.
--
-- art/models renders every tile of renewable_energy_01 from the same Blender models as the
-- item icons and ground models, and tools/tiledefs.py gives each placed tile its properties.
-- Lua names tiles only through this file, so a new layout changes nothing else.

RenewableEnergy = RenewableEnergy or {}

local Sprites = {}
RenewableEnergy.Sprites = Sprites

Sprites.TILESET = "renewable_energy_01"

local function tile(index)
    return Sprites.TILESET .. "_" .. index
end

-- Placed objects. Each tile's CustomItem is the item that picking it up gives back.
Sprites.flat = tile(0)
-- Wall tiles hang on their square's north edge (attachedN, facing south) or its west edge
-- (attachedW, facing east): the only two edges a square's walls are on.
Sprites.wall = { S = tile(1), E = tile(2) }
Sprites.rack = { S = tile(3), E = tile(4), N = tile(5), W = tile(6) }
Sprites.failsafe = tile(7)
Sprites.batteryBox = tile(8)
Sprites.batteryBank = tile(9)
Sprites.cellCharger = tile(10)
-- The cardboard crate of solar modules that world spawns and stashes place, and its overlays.
Sprites.crate = tile(11)
Sprites.crateOverlays = { full = tile(12), closed = tile(13) }

-- Snow lying on a panel, drawn over the panel's own tile.
Sprites.snow = {
    flat = tile(16),
    rack = { S = tile(17), E = tile(18), N = tile(19), W = tile(20) },
}

-- The batteries a bank shows, by how many it holds: index n shows n batteries.
Sprites.bankBatteries = {}
for count = 1, 12 do
    Sprites.bankBatteries[count] = tile(23 + count)
end
Sprites.boxBatteries = { tile(36), tile(37) }

-- The bank's charge meter, from 1 (empty) to 5 (full), and the charge fraction each level
-- starts below.
Sprites.bankMeter = {}
for level = 1, 5 do
    Sprites.bankMeter[level] = tile(39 + level)
end
local METER_LIMITS = { 0.10, 0.35, 0.65, 0.95 }

-- Sprite name to { kind, facing }; facing is nil for objects without one.
local KINDS = {
    [Sprites.flat] = { "flat" },
    [Sprites.failsafe] = { "failsafe" },
    [Sprites.batteryBox] = { "batteryBox" },
    [Sprites.batteryBank] = { "batteryBank" },
    [Sprites.cellCharger] = { "cellCharger" },
    [Sprites.crate] = { "crate" },
}
for facing, name in pairs(Sprites.wall) do
    KINDS[name] = { "wall", facing }
end
for facing, name in pairs(Sprites.rack) do
    KINDS[name] = { "rack", facing }
end

local OVERLAYS = {}
local function addOverlays(list)
    for _, name in pairs(list) do
        OVERLAYS[name] = true
    end
end
addOverlays(Sprites.crateOverlays)
addOverlays({ Sprites.snow.flat })
addOverlays(Sprites.snow.rack)
addOverlays(Sprites.bankBatteries)
addOverlays(Sprites.boxBatteries)
addOverlays(Sprites.bankMeter)

--- What a placed tile is.
---@param spriteName string?
---@return string? kind "flat", "wall", "rack", "failsafe", "batteryBox", "batteryBank", "cellCharger" or "crate"; nil for any other sprite
---@return string? facing "S", "E", "N" or "W" for walls and racks
function Sprites.kindOf(spriteName)
    local entry = spriteName and KINDS[spriteName]
    if not entry then
        return nil
    end
    return entry[1], entry[2]
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
---@param bankSprite string Sprites.batteryBank or Sprites.batteryBox
---@param batteries integer how many batteries it holds
---@param chargeFraction number stored over capacity, 0 to 1
---@return string[]
function Sprites.bankOverlays(bankSprite, batteries, chargeFraction)
    local overlays = {}
    if batteries <= 0 then
        return overlays
    end
    local shown = bankSprite == Sprites.batteryBox and Sprites.boxBatteries or Sprites.bankBatteries
    table.insert(overlays, shown[math.min(batteries, #shown)])
    if bankSprite == Sprites.batteryBank then
        table.insert(overlays, Sprites.bankMeter[Sprites.meterLevel(chargeFraction)])
    end
    return overlays
end

return Sprites
