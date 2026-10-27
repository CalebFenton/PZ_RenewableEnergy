-- The mod's tile sprites by what they show, and back.
--
-- The tiles are rendered from the same models as the item icons and ground models. Lua names tiles
-- only through this file, so a new layout changes nothing else. Their names come from SpriteTiles,
-- which tools/make_tiles.py writes from the art's tile numbers.

local ModuleRepair = require "RenewableEnergy/PowerBank/ModuleRepair"
local Tiles = require "RenewableEnergy/SpriteTiles"

local Sprites = {}

-- Placed objects. Each tile's CustomItem is the item that picking it up gives back.
Sprites.flat = Tiles.flat
-- Wall tiles by material and facing hang on their square's north edge (attachedN, facing south) or
-- its west edge (attachedW, facing east): the only two edges a square's walls are on.
Sprites.wall = Tiles.wall
-- Racks by material and facing.
Sprites.rack = Tiles.rack
Sprites.failsafe = Tiles.failsafe
Sprites.cellCharger = Tiles.cellCharger
-- The cardboard crate of solar modules that world spawns and stashes place, and its overlays.
Sprites.crate = Tiles.crate
Sprites.crateOverlays = Tiles.crateOverlays
Sprites.gardenLight = Tiles.gardenLight

-- Banks, one tile per tier, material and facing. Specs.banks[itemType].sprite names the field. The
-- placing cursor finds a facing's tile by its number in the same tileset, at most 96 away
-- (ISMoveableSpriteProps.getFaces, IsoWorld.SetCustomPropertyValues), so each bank's four follow
-- one another.
Sprites.batteryBoxWood = Tiles.batteryBoxWood
Sprites.batteryBoxMetal = Tiles.batteryBoxMetal
Sprites.batteryRackWood = Tiles.batteryRackWood
Sprites.batteryRackMetal = Tiles.batteryRackMetal
Sprites.batteryBankWood = Tiles.batteryBankWood
Sprites.batteryBankMetal = Tiles.batteryBankMetal

-- Biogas digesters, built in place, one facing each. A barrel digester looks like the barrel it was
-- built from, so its tiles are keyed by that item's type (DigesterSystem.OnCreate).
Sprites.digester = Tiles.digester
-- Their gas holders, drawn over the digester's own tile: `bags` and `tarp` beside any barrel,
-- from slack to taut, or torn; `drum` the insulated digester's floating drum, from low to risen
-- highest.
Sprites.digesterHolder = Tiles.digesterHolder
-- The scrubber fitted to each digester, drawn over the digester's own tile, and the same scrubber
-- spent (Digester.scrubLeft), its lid off and its bucket dry.
Sprites.digesterScrubber = Tiles.digesterScrubber
Sprites.digesterScrubberSpent = Tiles.digesterScrubberSpent
-- The foam a sour digester heaves up out of its feed funnel, drawn over its own tile.
Sprites.digesterSour = Tiles.digesterSour
-- The homemade gas heater, off and lit, by facing; every tile gives the heater back.
Sprites.gasHeater = Tiles.gasHeater
-- Save compatibility: the S tiles banks and heaters stood on before they turned (commit 811e5f6),
-- each to its turnable twin, which looks the same. No numbers within 96 of them are free for other
-- facings, so they don't turn; they work as their twin, pick up as it (Moveables.lua), and an item
-- still carrying one places it facing S. Remove this table, its uses and the old tiles once saves
-- from before then needn't load (DEVELOPMENT.md, Save compatibility).
Sprites.fixedTiles = Tiles.fixedTiles

--- The tile a placed `spriteName` turns as: its turnable twin for one of Sprites.fixedTiles, else
--- itself.
function Sprites.turnable(spriteName)
    return Sprites.fixedTiles[spriteName] or spriteName
end

-- The gas kit fitted to a generator and the generator's half of a gasifier's pipe, drawn over the
-- game's own generator tile. The kit sits on each generator body's air intake, so both are drawn per
-- body and facing, by the generator's sprite; `default` lies on the floor for a generator the game
-- doesn't know (another mod's).
Sprites.gasKit = Tiles.gasKit
-- The pipe by the gasifier's direction from the generator.
Sprites.gasifierPipeGen = Tiles.gasifierPipeGen

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
Sprites.gasifier = Tiles.gasifier
Sprites.gasifierLit = Tiles.gasifierLit
-- The metal gas pipe from a gasifier to a generator on the next square, in two halves that meet at
-- the squares' shared edge: `gasifierPipe` on the gasifier's tile, by the generator's direction from
-- it, and the generator's half (Sprites.gasifierPipeGenFor) on the generator's tile with the kit.
Sprites.gasifierPipe = Tiles.gasifierPipe
-- Wind charger tiles: the scoop rotor's, and each bladed kind's per blade material and rotor
-- facing (propeller the treadmill wind charger, alternator the homebuilt wind turbine, as
-- Wind.SPEC.turbines). In play the game draws each as a sprite model instead (Sprites.windModels).
Sprites.windScoop = Tiles.windScoop
Sprites.windCharger = Tiles.windCharger
-- Each wind charger kind's sprite models (scripts SpriteModels.txt): the name before the step
-- number, suffixed with blade material and/or facing per the by* flags; `steps` models each turn
-- the rotor one step, and stepsPerTurn is how many steps bring it back round (fewer for rotors that
-- look the same after part of a turn).
Sprites.windModels = Tiles.windModels

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
Sprites.snow = Tiles.snow

-- A cracked module's glass, drawn over its mount's tile, by the look ModuleRepair.crackLookOf
-- gives it. A rack has one per module slot, slot 1 the lower module, so it shows only the modules
-- that are cracked, each as it is cracked.
Sprites.cracks = Tiles.cracks

-- Each bank tile's overlays, by the bank's Sprites field and facing: `batteries[look][n]` shows a
-- battery of that look in slot n, linked to the one before it, and `meter[level]` its charge meter
-- lit from 1 (empty) to the last level (full). A bank draws one battery overlay per battery it
-- holds, in slot order, then its meter. The meter is on the bank's front, so facing N or W, away
-- from the camera, a bank shows none and has no `meter`. The E, N and W overlays are in a second
-- tileset: a tileset holds 512 tiles (IsoWorld.LoadTileDefinitions).
Sprites.bankFill = Tiles.bankFill

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
for kind, materials in pairs(Sprites.windCharger) do
    for material, facings in pairs(materials) do
        for facing, name in pairs(facings) do
            KINDS[name] = { kind, facing, material }
        end
    end
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
---@return string? kind "flat", "wall", "rack", "failsafe", "cellCharger", "crate", "gardenLight", "scoop", "propeller", "carAlternator", "alternator", "treadmill", "digester", "gasifier", "gasHeater", or a bank's Sprites field such as "batteryRackWood"; nil for any other sprite
---@return string? facing "S", "E", "N" or "W" for walls, racks, banks, gas heaters, bladed wind chargers and treadmills; a digester's or gasifier's tier
---@return string? variant the material: "wood" or "metal" for walls, racks and banks, the blades' "wood", "pipe" or "steel" for bladed wind chargers, the item type of a barrel digester's barrel, such as "MetalDrum"; a treadmill tile's end, "console" or "rear"; a gas heater's "off" or "lit"
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
    Sprites.digesterHolder, Sprites.digesterScrubber, Sprites.digesterScrubberSpent, Sprites.digesterSour, Sprites.gasKit,
    Sprites.gasifierLit, Sprites.gasifierPipe, Sprites.gasifierPipeGen)

--- The tile of a bladed wind charger of `kind` facing `facing` (Sprites.kindOf) with blades of
--- `material` (Wind.SPEC.blades), or nil for blades it has no tile for.
function Sprites.windTileOf(kind, facing, material)
    local facings = Sprites.windCharger[kind] and Sprites.windCharger[kind][material]
    return facings and facings[facing]
end

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

-- What a mount's tile shows of `byKind` (Sprites.snow or a look of Sprites.cracks): the kind's own
-- entry, or for a kind that has one per material and facing, that one; nil for none.
local function ofMount(byKind, kind, facing, material)
    local entry = byKind[kind]
    if type(entry) == "table" then
        entry = entry[material]
        return entry and entry[facing]
    end
    return entry
end

local NO_SLOTS = {}

-- A mount's crack overlays of `look` by module slot. May be Sprites.cracks' own list: don't change it.
local function crackSlots(look, kind, facing, material)
    local slots = ofMount(Sprites.cracks[look], kind, facing, material)
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

--- The crack overlays a mount's tile shows: one for each cracked module, by slot, of the look
--- ModuleRepair.crackLookOf gives it.
---@param kind string "flat", "wall" or "rack" (see kindOf)
---@param facing string? the mount's facing, for walls and racks
---@param material string? "wood" or "metal", for walls and racks
---@param modules table[] the mount's { type, condition } modules in slot order
---@return string[]
function Sprites.crackOverlays(kind, facing, material, modules)
    local shown = {}
    -- Both looks have an overlay for every slot.
    for slot in ipairs(crackSlots("heavy", kind, facing, material)) do
        local module = modules[slot]
        local look = module and ModuleRepair.crackLookOf(module.type, module.condition)
        if look then
            table.insert(shown, crackSlots(look, kind, facing, material)[slot])
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
