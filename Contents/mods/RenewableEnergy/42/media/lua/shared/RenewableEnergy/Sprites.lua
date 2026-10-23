-- The mod's tile sprites by what they show, and back.
--
-- The tiles are rendered from the same models as the item icons and ground models. Lua names tiles
-- only through this file, so a new layout changes nothing else.

require "RenewableEnergy/Specs"

RenewableEnergy = RenewableEnergy or {}
local Specs = RenewableEnergy.Specs

local Sprites = {}
RenewableEnergy.Sprites = Sprites

local TILESET = "renewable_energy_01"
-- The overlays of the banks' E, N and W tiles, which the first tileset can't also hold: a tileset
-- holds 512 tiles (IsoWorld.LoadTileDefinitions).
local TURNED_TILESET = "renewable_energy_02"

local function tile(index, tileset)
    return (tileset or TILESET) .. "_" .. index
end

-- `count` tiles numbered from `first`, in order.
local function tiles(first, count, tileset)
    local list = {}
    for i = 1, count do
        list[i] = tile(first + i - 1, tileset)
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

-- Banks, one tile per tier, material and facing. Specs.banks[itemType].sprite names the field. The
-- placing cursor finds a facing's tile by its number in the same tileset, at most 96 away
-- (ISMoveableSpriteProps.getFaces, IsoWorld.SetCustomPropertyValues), so each bank's four follow
-- one another.
Sprites.batteryBoxWood = { S = tile(340), E = tile(341), N = tile(342), W = tile(343) }
Sprites.batteryBoxMetal = { S = tile(344), E = tile(345), N = tile(346), W = tile(347) }
Sprites.batteryRackWood = { S = tile(348), E = tile(349), N = tile(350), W = tile(351) }
Sprites.batteryRackMetal = { S = tile(352), E = tile(353), N = tile(354), W = tile(355) }
Sprites.batteryBankWood = { S = tile(356), E = tile(357), N = tile(358), W = tile(359) }
Sprites.batteryBankMetal = { S = tile(360), E = tile(361), N = tile(362), W = tile(363) }

-- Biogas digesters, built in place, one facing each. A barrel digester looks like the barrel it was
-- built from, so its tiles are keyed by that item's type (DigesterSystem.OnCreate).
Sprites.digester = {
    barrel = {
        MetalDrum = tile(228),
        Mov_OrangeBarrel = tile(229),
        Mov_DarkGreenBarrel = tile(277),
        Mov_LightGreenBarrel = tile(278),
    },
    insulated = tile(230),
    dome = tile(231),
}
-- Their gas holders, drawn over the digester's own tile: `bags` and `tarp` beside any barrel,
-- from slack to taut, or torn; `drum` the insulated digester's floating drum, from low to risen
-- highest.
Sprites.digesterHolder = {
    bags = tiles(232, 3),
    bagsTorn = tile(235),
    tarp = tiles(236, 3),
    tarpTorn = tile(239),
    drum = tiles(240, 4),
}
-- The scrubber fitted to each digester, drawn over the digester's own tile.
Sprites.digesterScrubber = { barrel = tile(247), insulated = tile(248), dome = tile(249) }
-- The homemade gas heater, off and lit, by facing; every tile gives the heater back.
Sprites.gasHeater = {
    off = { S = tile(364), E = tile(365), N = tile(366), W = tile(367) },
    lit = { S = tile(368), E = tile(369), N = tile(370), W = tile(371) },
}
-- The S tiles a save's banks and heaters may stand on, each to its turnable twin, which looks the
-- same. No numbers within 96 of them are free for other facings, so they don't turn; they work as
-- their twin, and pick up and place as it (Moveables.lua).
Sprites.fixedTiles = {
    [tile(8)] = Sprites.batteryBoxWood.S, [tile(23)] = Sprites.batteryBoxMetal.S,
    [tile(32)] = Sprites.batteryRackWood.S, [tile(33)] = Sprites.batteryRackMetal.S,
    [tile(34)] = Sprites.batteryBankWood.S, [tile(9)] = Sprites.batteryBankMetal.S,
    [tile(244)] = Sprites.gasHeater.off.S, [tile(245)] = Sprites.gasHeater.lit.S,
}

--- The tile a placed `spriteName` turns as: its turnable twin for one of Sprites.fixedTiles, else
--- itself.
function Sprites.turnable(spriteName)
    return Sprites.fixedTiles[spriteName] or spriteName
end

-- The gas kit fitted to a generator and the generator's half of a gasifier's pipe, drawn over the
-- game's own generator tile. The kit sits on each generator body's air intake, so both are drawn per
-- body and facing; `default` lies on the floor for a generator the game doesn't know (another mod's).
Sprites.gasKit = { default = tile(246), bySprite = {} }
-- The pipe by the gasifier's direction from the generator.
Sprites.gasifierPipeGen = { default = { N = tile(260), E = tile(261), S = tile(262), W = tile(263) }, bySprite = {} }
do
    local KIT_FIRST, PIPE_FIRST = 280, 292
    local SIDES = { "N", "E", "S", "W" }
    -- The game's generator sprites (appliances_misc_01) by body, in the order of their facings.
    local BODIES = {
        { first = { 0, 8 }, facings = { "E", "S", "W", "N" } },
        { first = { 4 }, facings = { "E", "S", "W", "N" } },
        { first = { 12 }, facings = { "S", "E", "N", "W" } },
    }
    for body, spec in ipairs(BODIES) do
        for _, first in ipairs(spec.first) do
            for offset, facing in ipairs(spec.facings) do
                local name = "appliances_misc_01_" .. (first + offset - 1)
                local fitting = (body - 1) * 4 + ({ N = 0, E = 1, S = 2, W = 3 })[facing]
                Sprites.gasKit.bySprite[name] = tile(KIT_FIRST + fitting)
                local pipes = {}
                for side, letter in ipairs(SIDES) do
                    pipes[letter] = tile(PIPE_FIRST + fitting * 4 + side - 1)
                end
                Sprites.gasifierPipeGen.bySprite[name] = pipes
            end
        end
    end
end

--- The gas kit's overlay for a generator whose sprite is `generatorSprite`.
function Sprites.gasKitFor(generatorSprite)
    return Sprites.gasKit.bySprite[generatorSprite] or Sprites.gasKit.default
end

--- The generator's half of the pipe from a gasifier on its `side` ("N", "E", "S" or "W"), for a
--- generator whose sprite is `generatorSprite`.
function Sprites.gasifierPipeGenFor(generatorSprite, side)
    return (Sprites.gasifierPipeGen.bySprite[generatorSprite] or Sprites.gasifierPipeGen.default)[side]
end

-- Wood gas generators, built in place, one facing each, and the glow at each one's door while lit,
-- drawn over its own tile.
Sprites.gasifier = { primitive = tile(250), standard = tile(251), advanced = tile(252) }
Sprites.gasifierLit = { primitive = tile(253), standard = tile(254), advanced = tile(255) }
-- The metal gas pipe from a gasifier to a generator on the next square, in two halves that meet at
-- the squares' shared edge: `gasifierPipe` on the gasifier's tile, by the generator's direction from
-- it, and the generator's half (Sprites.gasifierPipeGenFor) on the generator's tile with the kit.
Sprites.gasifierPipe = { N = tile(256), E = tile(257), S = tile(258), W = tile(259) }
-- Wind charger tiles, per blade material and rotor facing where the kind has them. In play the game
-- draws each as a sprite model instead (Sprites.windModels).
Sprites.windScoop = tile(264)
Sprites.windPropeller = {
    wood = { N = tile(265), E = tile(266), S = tile(267), W = tile(268) },
    pipe = { N = tile(269), E = tile(270), S = tile(271), W = tile(272) },
}
Sprites.windAlternator = { N = tile(273), E = tile(274), S = tile(275), W = tile(276) }
-- Each wind charger kind's sprite models (scripts SpriteModels.txt): the name before the step
-- number, suffixed with blade material and/or facing per the by* flags; `steps` models each turn
-- the rotor one step, and stepsPerTurn is how many steps bring it back round (fewer for rotors that
-- look the same after part of a turn).
Sprites.windModels = {
    scoop = { name = "RenewableEnergy.ScoopRotor", steps = 6, stepsPerTurn = 12 },
    propeller = { name = "RenewableEnergy.Propeller", byMaterial = true, byFacing = true, steps = 6, stepsPerTurn = 18 },
    alternator = { name = "RenewableEnergy.Alternator", byFacing = true, steps = 6, stepsPerTurn = 18 },
}

-- Vanilla's treadmill (the "Hamster Wheel" moveable), two tiles per facing, keyed by the way a runner
-- faces: away from the tiles' Facing. The console tile is the one its depth geometry
-- (tileGeometry.txt) puts the console's box on; the runner stands on the rear.
Sprites.treadmill = {
    W = { console = "recreational_sports_01_36", rear = "recreational_sports_01_37" },
    N = { console = "recreational_sports_01_39", rear = "recreational_sports_01_38" },
    E = { console = "recreational_sports_01_29", rear = "recreational_sports_01_28" },
    S = { console = "recreational_sports_01_30", rear = "recreational_sports_01_31" },
}

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

-- Each bank tile's overlays, by the bank's Sprites field and facing: `batteries[look][n]` shows a
-- battery of that look in slot n, linked to the one before it, and `meter[level]` its charge meter
-- lit from 1 (empty) to the last level (full). A bank draws one battery overlay per battery it
-- holds, in slot order, then its meter. The meter is on the bank's front, so facing N or W, away
-- from the camera, a bank shows none and has no `meter`.
Sprites.bankFill = {
    batteryBoxWood = { S = { batteries = { car = tiles(36, 2), deepCycle = tiles(136, 2), l16 = tiles(182, 2) },
        meter = tiles(48, 5) } },
    batteryBoxMetal = { S = { batteries = { car = tiles(38, 2), deepCycle = tiles(138, 2), l16 = tiles(184, 2) },
        meter = tiles(53, 5) } },
    batteryRackWood = { S = { batteries = { car = tiles(73, 6), deepCycle = tiles(140, 6), l16 = tiles(186, 6) },
        meter = tiles(58, 5) } },
    batteryRackMetal = { S = { batteries = { car = tiles(79, 8), deepCycle = tiles(146, 8), l16 = tiles(192, 8) },
        meter = tiles(63, 5) } },
    batteryBankWood = { S = { batteries = { car = tiles(87, 12), deepCycle = tiles(154, 12), l16 = tiles(200, 12) },
        meter = tiles(68, 5) } },
    batteryBankMetal = { S = { batteries = { car = tiles(99, 16), deepCycle = tiles(166, 16), l16 = tiles(212, 16) },
        meter = tiles(40, 5) } },
}
-- The other facings' overlays fill TURNED_TILESET from 0, facing by facing, bank by bank in this
-- order (art/models/tiles.py's STORAGE_TILES): each look's batteries by slot, then the meter if any.
do
    local BANK_ORDER = { "batteryBoxWood", "batteryBoxMetal", "batteryRackWood", "batteryRackMetal", "batteryBankWood",
        "batteryBankMetal" }
    local nextTile = 0
    local function take(count)
        local list = tiles(nextTile, count, TURNED_TILESET)
        nextTile = nextTile + count
        return list
    end
    for _, facing in ipairs({ "E", "N", "W" }) do
        for _, field in ipairs(BANK_ORDER) do
            local south = Sprites.bankFill[field].S
            local slots = #south.batteries.car
            local fill = { batteries = { car = take(slots), deepCycle = take(slots), l16 = take(slots) } }
            fill.meter = facing == "E" and take(#south.meter) or nil
            Sprites.bankFill[field][facing] = fill
        end
    end
end
-- The look a battery's overlay draws it with, by item type: any other battery is drawn as a car
-- battery.
local BATTERY_LOOKS = { ["RenewableEnergy.DeepCycleBattery"] = "deepCycle", ["RenewableEnergy.L16Battery"] = "l16" }
-- The charge fraction each meter level starts below.
local METER_LIMITS = { 0.10, 0.35, 0.65, 0.95 }

-- Sprite name to { kind, facing, variant } (Sprites.kindOf); facing and variant are nil where
-- there's none.
local KINDS = {
    [Sprites.flat] = { "flat" },
    [Sprites.failsafe] = { "failsafe" },
    [Sprites.cellCharger] = { "cellCharger" },
    [Sprites.crate] = { "crate" },
    [Sprites.gardenLight.off] = { "gardenLight" },
    [Sprites.gardenLight.lit] = { "gardenLight" },
    [Sprites.windScoop] = { "scoop" },
    [Sprites.digester.insulated] = { "digester", "insulated" },
    [Sprites.digester.dome] = { "digester", "dome" },
}
for barrel, name in pairs(Sprites.digester.barrel) do
    KINDS[name] = { "digester", "barrel", barrel }
end
for _, mount in ipairs({ "wall", "rack" }) do
    for material, facings in pairs(Sprites[mount]) do
        for facing, name in pairs(facings) do
            KINDS[name] = { mount, facing, material }
        end
    end
end
for field, facings in pairs(Sprites.bankFill) do
    for facing in pairs(facings) do
        KINDS[Sprites[field][facing]] = { field, facing, field:find("Wood$") and "wood" or "metal" }
    end
end
for state, facings in pairs(Sprites.gasHeater) do
    for facing, name in pairs(facings) do
        KINDS[name] = { "gasHeater", facing, state }
    end
end
for fixed, twin in pairs(Sprites.fixedTiles) do
    KINDS[fixed] = KINDS[twin]
end
for facing, ends in pairs(Sprites.treadmill) do
    for part, name in pairs(ends) do
        KINDS[name] = { "treadmill", facing, part }
    end
end
for material, facings in pairs(Sprites.windPropeller) do
    for facing, name in pairs(facings) do
        KINDS[name] = { "propeller", facing, material }
    end
end
for facing, name in pairs(Sprites.windAlternator) do
    KINDS[name] = { "alternator", facing }
end
for tier, name in pairs(Sprites.gasifier) do
    KINDS[name] = { "gasifier", tier }
end

-- Adds every sprite name in `value`, a name or a table of them nested to any depth, to `set`.
local function addNames(set, value)
    if type(value) == "table" then
        for _, inner in pairs(value) do
            addNames(set, inner)
        end
    elseif value then
        set[value] = true
    end
end

--- A function telling whether a sprite name is one of the names in the arguments, each a sprite
--- name or a table of them nested to any depth, such as Sprites.digesterHolder.
---@return fun(spriteName: string?): boolean
function Sprites.matcher(...)
    local set = {}
    for i = 1, select("#", ...) do
        addNames(set, select(i, ...))
    end
    return function(spriteName)
        return spriteName ~= nil and set[spriteName] == true
    end
end

--- What a placed tile is.
---@param spriteName string?
---@return string? kind "flat", "wall", "rack", "failsafe", "cellCharger", "crate", "gardenLight", "scoop", "propeller", "alternator", "treadmill", "digester", "gasifier", "gasHeater", or a bank's Sprites field such as "batteryRackWood"; nil for any other sprite
---@return string? facing "S", "E", "N" or "W" for walls, racks, banks, gas heaters, propellers, alternators and treadmills; a digester's or gasifier's tier
---@return string? variant the material: "wood" or "metal" for walls, racks and banks, the blades' "wood" or "pipe" for propellers, the item type of a barrel digester's barrel, such as "MetalDrum"; a treadmill tile's end, "console" or "rear"; a gas heater's "off" or "lit"
function Sprites.kindOf(spriteName)
    local entry = spriteName and KINDS[spriteName]
    if not entry then
        return nil
    end
    return entry[1], entry[2], entry[3]
end

--- The sprite names of `kind` (Sprites.kindOf), in no order.
function Sprites.namesOf(kind)
    local names = {}
    for name, entry in pairs(KINDS) do
        if entry[1] == kind then
            table.insert(names, name)
        end
    end
    return names
end

--- The sprite name of a placed object, or nil for anything else or an object without a sprite.
function Sprites.nameOf(isoObject)
    if not instanceof(isoObject, "IsoObject") then
        return nil
    end
    local sprite = isoObject:getSprite()
    return sprite and sprite:getName()
end

--- What a placed object is, by its tile (Sprites.kindOf); nil for anything else.
function Sprites.kindOfObject(isoObject)
    return Sprites.kindOf(Sprites.nameOf(isoObject))
end

--- Whether a sprite is a snow overlay.
Sprites.isSnow = Sprites.matcher(Sprites.snow)
--- Whether a sprite is one of the overlays drawn over a tile, which are never placed on their own.
Sprites.isOverlay = Sprites.matcher(Sprites.snow, Sprites.cracks, Sprites.crateOverlays, Sprites.bankFill,
    Sprites.digesterHolder, Sprites.digesterScrubber, Sprites.gasKit, Sprites.gasifierLit, Sprites.gasifierPipe,
    Sprites.gasifierPipeGen)

--- The name of the sprite model a wind charger tile is drawn as, but for the step number, and its
--- kind's row of Sprites.windModels; nil for any other sprite.
---@param spriteName string?
---@return string? prefix
---@return table? model
function Sprites.windModelOf(spriteName)
    local kind, facing, material = Sprites.kindOf(spriteName)
    local model = kind and Sprites.windModels[kind]
    if not model then
        return nil
    end
    local prefix = model.name
    if model.byMaterial then
        prefix = prefix .. material:sub(1, 1):upper() .. material:sub(2)
    end
    if model.byFacing then
        prefix = prefix .. facing
    end
    return prefix, model
end

-- The priority every loader of the mod's sprites passes to MapObjects.OnLoadWithSprite. MapObjects
-- keeps one function per sprite and priority, a later one silently replacing an earlier
-- (MapObjects.java), and single player loads the client and the server folders both; so a second
-- loader of the same sprites needs a priority of its own, as RenewableEnergy.PlaceTracker's has.
Sprites.LOAD_PRIORITY = 6

-- What a mount's tile shows of `byKind` (Sprites.snow or Sprites.cracks): the kind's own entry, or
-- for a kind that has one per material and facing, that one; nil for none.
local function ofMount(byKind, kind, facing, material)
    local entry = byKind[kind]
    if type(entry) == "table" then
        entry = entry[material]
        return entry and entry[facing]
    end
    return entry
end

local NO_SLOTS = {}

-- A mount's crack overlays by module slot. May be Sprites.cracks' own list: don't change it.
local function crackSlots(kind, facing, material)
    local slots = ofMount(Sprites.cracks, kind, facing, material)
    if type(slots) == "string" then
        return { slots }
    end
    return slots or NO_SLOTS
end

--- The snow overlay a mount's tile shows under snow (Sprites.snow), or nil for a mount that holds
--- none.
---@param kind string "flat", "wall" or "rack" (see kindOf)
---@param facing string? the mount's facing, for walls and racks
---@param material string? "wood" or "metal", for walls and racks
---@return string?
function Sprites.snowOverlay(kind, facing, material)
    return ofMount(Sprites.snow, kind, facing, material)
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

-- The look a battery's overlay draws it with: "car", "deepCycle" or "l16" (Sprites.bankFill).
local function batteryLook(fullType)
    return BATTERY_LOOKS[fullType] or "car"
end

--- The overlays a bank's tile shows for its batteries and charge, in drawing order: each battery
--- in its slot, as many as the tile has slots, then the meter where the tile shows it. A bank
--- without batteries shows none: its meter has nothing to read.
---@param bankSprite string? the bank's placed tile, such as Sprites.batteryRackWood.E
---@param batteryTypes string[] the item types of the batteries it holds, in slot order
---@param chargeFraction number stored over capacity, 0 to 1
---@return string[]
function Sprites.bankOverlays(bankSprite, batteryTypes, chargeFraction)
    local field, facing = Sprites.kindOf(bankSprite)
    local fill = field and Sprites.bankFill[field] and Sprites.bankFill[field][facing]
    if not fill or #batteryTypes == 0 then
        return {}
    end
    local shown = {}
    for slot = 1, math.min(#batteryTypes, #fill.batteries.car) do
        shown[slot] = fill.batteries[batteryLook(batteryTypes[slot])][slot]
    end
    if fill.meter then
        table.insert(shown, fill.meter[Sprites.meterLevel(chargeFraction)])
    end
    return shown
end

return Sprites
