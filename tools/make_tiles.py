"""Write renewable_energy.tiles, the properties of every tile in renewable_energy_01 and
renewable_energy_02, tileGeometry.txt, and SpriteTiles.lua, every tile by meaning for Lua.

    python3 tools/make_tiles.py

Tile numbers come from art/models/tile_numbers.py, which art/models/tiles.py renders from too.
Overlay tiles (snow, cracked glass, batteries, the charge meter, the crate's contents and lid, the
digesters' gas holders, scrubbers and sour foam, the generator's gas kit, the gasifiers' glow and
gas pipes, and all of renewable_energy_02) are only ever attached to another tile, so they have no
properties. Property names and values follow the vanilla tile definitions
(newtiledefinitions.tiles); ISMoveableSpriteProps reads the moveable ones:

- CustomItem: the item that picking the tile up gives, instead of a generic Moveables item.
- Facing and N/S/E/Woffset: the placing cursor's rotation, the offsets pointing from one facing's
  tile number to the others' in the same tileset (ISMoveableSpriteProps.getFaces).
- MoveType = WallObject with attachedN or attachedW: hung on the wall at the square's north or west
  edge, which ISMoveableSpriteProps.getWallForFacing finds for Facing S and E.
- PickUpTool and PlaceTool name an ISMoveableDefinitions tool (Electrician is a screwdriver and the
  Electricity skill), PickUpLevel the skill needed.
- Container types and scrap materials are global across mods, so they carry the mod's name.

With the harness's lib/art/tilefile.py, it also writes the tileGeometry.txt that makes the game
load the depth maps art/models/render.py renders. Without them every tile would be drawn as if it
filled its square up to the ceiling, and hide a character standing in front of a wall panel.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "dev", "harness", "lib"))
sys.path.insert(0, os.path.join(HERE, "..", "art", "models"))
from art import tilefile  # noqa: E402
from tile_numbers import (BARREL_DIGESTERS, BARREL_HOLDERS, BATTERY_LOOKS, CRACKS, CRATE_CLOSED, CRATE_FULL,  # noqa: E402
                          DIGESTERS, DIRECTIONS, DOME_DIGESTER, DRUM_HOLDER, DRUM_LEVELS, FACINGS, FLAT_SNOW,
                          GARDEN_LIGHT, GARDEN_LIGHT_LIT, GAS_KIT, GASIFIER_PIPE, GASIFIERS, GENERATOR_BODIES,
                          GENERATOR_KIT_FIRST, GENERATOR_PIPE, GENERATOR_PIPE_FIRST, GENERATOR_TILESET, HEATER,
                          HEATER_LIT, HOLDER_FILLS, INSULATED_DIGESTER, METER_LEVELS, MOUNTS, RACK_SLOTS, ROTOR_SPIN,
                          SCOOP_ROTOR, SCOOP_SPIN, SCRUBBERS, SOLAR_CELL_CHARGER, SOLAR_CRATE, SOLAR_FAILSAFE,
                          SOLAR_FLAT, SOUR_FOAM, SPENT_SCRUBBERS, STORAGE_CAPACITY, STORAGE_TILES, TURNED_HEATER_FIRST,
                          TURNED_STORAGE_FIRST, TURNED_STORAGE_OVERLAYS, WIND_TILES)

MEDIA = os.path.join(HERE, "..", "Contents", "mods", "RenewableEnergy", "common", "media")
# Each tileset's name and rows, tilefile.COLUMNS tiles to a row; the file numbers them from 1 in
# this order.
TILESETS = (("renewable_energy_01", 53), ("renewable_energy_02", 56))


def moveable(item, level=None, tool="Electrician", **props):
    base = {"IsMoveAble": "", "CustomItem": "RenewableEnergy." + item}
    if tool:
        base.update(PickUpTool=tool, PlaceTool=tool, PickUpLevel=str(level))
    base.update(props)
    return base


def panel(group, item, level, **props):
    return moveable(item, level, CustomName="Solar Panel", GroupName=group, Material="Electric", **props)


def wall(item, facing):
    if facing == "S":
        return panel("Wall Mounted", item, 3, MoveType="WallObject", Facing="S", attachedN="", IsHigh="", Eoffset="1")
    return panel("Wall Mounted", item, 3, MoveType="WallObject", Facing="E", attachedW="", IsHigh="", Soffset="-1")


def turned(first, make):
    """Four tiles from `first`, one per facing in FACINGS' order, each make(**its rotation)."""
    tiles = {facing: first + f for f, facing in enumerate(FACINGS)}
    for facing, index in tiles.items():
        TILES[index] = make(**tilefile.facings(tiles, facing))


def rack(item, **props):
    return panel("Ground Rack", item, 3, BlocksPlacement="", solidtrans="", **props)


def storage(item, group, name, level, capacity, **props):
    """A battery box, rack or bank: a container of its own type, scrapped by its own definition.
    GeneratorSound names the sounds its generator plays when switched (scripts Sounds.txt)."""
    return moveable(item, level, CustomName=name, GroupName=group, container="RenewableEnergy" + item,
                    ContainerCapacity=str(capacity), Material="RenewableEnergy" + item, CanScrap="",
                    BlocksPlacement="", solidtrans="", GeneratorSound="RenewableEnergyBank", **props)


def garden_light():
    # Lit and unlit both give the light back; it needs no tool, like a lamp.
    return moveable("SolarGardenLight", tool=None, CustomName="Solar Garden Light", Material="Electric")


def gas_heater(**props):
    # Off and lit both give the heater back. Its gas line comes off with a wrench, which, like the
    # game's sinks and toilets, asks no skill level.
    return moveable("GasHeater", tool=None, PickUpTool="Wrench", PlaceTool="Wrench", CustomName="Gas Heater",
                    Material="MetalPlates", BlocksPlacement="", solidtrans="", IsLow="", **props)


def built_in_place(name, container, capacity, material, material2, **props):
    """A digester or gasifier. It is built where it stands and scrapped there, never carried, so it
    gives no item and is too heavy to pick up. Scrap materials are the game's own."""
    return {"IsMoveAble": "", "CustomName": name, "container": "RenewableEnergy" + container,
            "ContainerCapacity": str(capacity), "Material": material, "Material2": material2, "CanScrap": "",
            "PickUpWeight": "400", "BlocksPlacement": "", "solidtrans": "", **props}


def wind_charger(name, material, material2):
    """A wind charger: built in place and scrapped there like a digester, but it holds nothing."""
    return {"IsMoveAble": "", "CustomName": name, "Material": material, "Material2": material2, "CanScrap": "",
            "PickUpWeight": "400", "BlocksPlacement": ""}


TILES = {
    SOLAR_FLAT: panel("Flat", "SolarFlat", 2, RenderLayer="Floor", IsLow=""),
    # Sits on the generator's square, which a floor rug's move type allows.
    SOLAR_FAILSAFE: moveable("SolarFailsafe", 3, CustomName="Solar Failsafe", MoveType="FloorRug", Material="Electric"),
    # Small enough for a table or counter, like the vanilla radios.
    SOLAR_CELL_CHARGER: moveable("SolarCellCharger", tool=None, CustomName="Solar Battery Charger",
                                 container="RenewableEnergyCellCharger", ContainerCapacity="1", IsTableTop="",
                                 IsSurfaceOffset="", BlocksPlacement="", Material="Electric"),
    SOLAR_CRATE: {"IsMoveAble": "", "CustomName": "Solar Box", "container": "RenewableEnergySolarBox", "ContainerCapacity": "50",
                  "ContainerPosition": "Low", "Material": "Paper", "CanScrap": "", "PickUpWeight": "10", "BlocksPlacement": "",
                  "solidtrans": "", "IsLow": "", "Surface": "14"},
    GARDEN_LIGHT: garden_light(),
    GARDEN_LIGHT_LIT: garden_light(),
    INSULATED_DIGESTER: built_in_place("Insulated Digester", "Digester", 50, "Wood", "Nails"),
    DOME_DIGESTER: built_in_place("Brick Dome Digester", "Digester", 100, "Brick", "Stone", IsLow=""),
    GASIFIERS["primitive"]: built_in_place("Primitive Gasifier", "Gasifier", 8, "SmallMetalPlates", "MetalPipe"),
    GASIFIERS["standard"]: built_in_place("Gasifier", "Gasifier", 20, "MetalPlates", "MetalPipe"),
    GASIFIERS["advanced"]: built_in_place("Advanced Gasifier", "Gasifier", 30, "MetalPlates", "MetalBars"),
    SCOOP_ROTOR: wind_charger("Scoop Rotor Wind Charger", "MetalPlates", "MetalPipe"),
}
for material, first_wall, first_rack, _ in MOUNTS:
    for offset, facing in enumerate("SE"):
        TILES[first_wall + offset] = wall("SolarWall" + material.title(), facing)
    turned(first_rack, lambda **turn: rack("SolarRack" + material.title(), **turn))

# Battery storage by item: its GroupName and CustomName, pick-up level, container capacity, and its
# other properties. The cursor turns a tile only to numbers at most 96 away (offsets outside -96 to
# 96 read as -96: IsoWorld.SetCustomPropertyValues), and none near the tiles a save's storage
# stands on is free, so they don't turn; the turned tiles do.
STORAGE = {
    "BatteryBoxWood": ("Wooden", "Battery Box", 1, 40, {"ContainerPosition": "Low", "IsLow": ""}),
    "BatteryBoxMetal": ("Metal", "Battery Box", 1, 40, {"ContainerPosition": "Low", "IsLow": ""}),
    "BatteryRackWood": ("Wooden", "Battery Rack", 3, 100, {}),
    "BatteryRackMetal": ("Metal", "Battery Rack", 3, 100, {}),
    "BatteryBankWood": ("Wooden", "Battery Bank", 4, 100, {}),
    "BatteryBankMetal": ("Metal", "Battery Bank", 4, 100, {}),
}
for i, (item, fixed, *_) in enumerate(STORAGE_TILES):
    group, name, level, capacity, props = STORAGE[item]
    TILES[fixed] = storage(item, group, name, level, capacity, **props)
    turned(TURNED_STORAGE_FIRST + len(FACINGS) * i, lambda **turn: storage(item, group, name, level, capacity, **props, **turn))

for fixed, first in ((HEATER, TURNED_HEATER_FIRST), (HEATER_LIT, TURNED_HEATER_FIRST + len(FACINGS))):
    TILES[fixed] = gas_heater()
    turned(first, gas_heater)

WIND_NAMES = {"Propeller": "Treadmill Wind Charger", "Alternator": "Homebuilt Wind Turbine",
              "CarAlternator": "Car Alternator Wind Charger"}
BLADE_MATERIAL = {"wood": "Wood", "pipe": "Plastic", "steel": "MetalScrap"}
for first, model, blades in WIND_TILES:
    for offset in range(4):
        TILES[first + offset] = wind_charger(WIND_NAMES[model], "MetalPipe", BLADE_MATERIAL[blades])

# The barrel digester's tiles, one per barrel it can be built from, all steel like the game's own.
for index in BARREL_DIGESTERS.values():
    TILES[index] = built_in_place("Barrel Digester", "Digester", 30, "MetalPlates", "MetalScrap")


# The tiles by meaning for Lua: the fields of Sprites.lua, which says what each shows.
LUA = os.path.join(HERE, "..", "Contents", "mods", "RenewableEnergy", "42", "media", "lua", "shared", "RenewableEnergy",
                   "SpriteTiles.lua")


def _name(number, tileset=0):
    return "%s_%d" % (TILESETS[tileset][0], number)


def _names(numbers, tileset=0):
    return [_name(number, tileset) for number in numbers]


def _run(first, count):
    return _names(range(first, first + count))


def _by(first, keys):
    """The tiles from `first`, one per key in order, by key."""
    return {key: _name(first + offset) for offset, key in enumerate(keys)}


def _field(name):
    """An item's or sprite model's name as Lua's field for it: BatteryBoxWood is batteryBoxWood."""
    return name[0].lower() + name[1:]


def _wind_model(model, spin, bladed):
    """A sprite model's name before the step, whether a skin per blade material and a yaw per facing
    suffix it, its steps, and the steps that bring it round a whole turn."""
    flags = {"byMaterial": True, "byFacing": True} if bladed else {}
    return {"name": "RenewableEnergy." + model, **flags, "steps": spin[1], "stepsPerTurn": 360 // spin[0]}


def sprite_tiles():
    """Every tile Lua names, by meaning."""
    storage = {_field(item): _by(TURNED_STORAGE_FIRST + len(FACINGS) * i, FACINGS) for i, (item, *_) in enumerate(STORAGE_TILES)}
    heater = {"off": _by(TURNED_HEATER_FIRST, FACINGS), "lit": _by(TURNED_HEATER_FIRST + len(FACINGS), FACINGS)}
    fixed = {_name(base): storage[_field(item)]["S"] for item, base, *_ in STORAGE_TILES}
    fixed.update({_name(HEATER): heater["off"]["S"], _name(HEATER_LIT): heater["lit"]["S"]})

    holders = {}
    for holder, first in BARREL_HOLDERS.items():
        holders[holder] = _run(first, HOLDER_FILLS)
        holders[holder + "Torn"] = _name(first + HOLDER_FILLS)
    holders["drum"] = _run(DRUM_HOLDER, DRUM_LEVELS)

    kits, pipes = {}, {}
    for b, (_, firsts, facings) in enumerate(GENERATOR_BODIES):
        for first in firsts:
            for offset, facing in enumerate(facings):
                generator = "%s_%d" % (GENERATOR_TILESET, first + offset)
                fitting = len(DIRECTIONS) * b + DIRECTIONS.index(facing)
                kits[generator] = _name(GENERATOR_KIT_FIRST + fitting)
                pipes[generator] = _by(GENERATOR_PIPE_FIRST + len(DIRECTIONS) * fitting, DIRECTIONS)

    chargers, models = {}, {"scoop": _wind_model("ScoopRotor", SCOOP_SPIN, False)}
    for first, model, blades in WIND_TILES:
        chargers.setdefault(_field(model), {})[blades] = _by(first, DIRECTIONS)
        models.setdefault(_field(model), _wind_model(model, ROTOR_SPIN, True))

    cracks = {}
    for look, flat, mounts in CRACKS:
        cracks[look] = {
            "flat": _name(flat),
            "wall": {material: _by(wall, "SE") for material, (wall, _) in mounts.items()},
            "rack": {material: {facing: _run(rack + RACK_SLOTS * f, RACK_SLOTS) for f, facing in enumerate(FACINGS)}
                     for material, (_, rack) in mounts.items()},
        }

    fills = {}
    for item, _, first_batteries, first_meter in STORAGE_TILES:
        slots = STORAGE_CAPACITY[item]
        fill = {"S": {"batteries": {look: _run(first, slots) for look, first in zip(BATTERY_LOOKS, first_batteries)},
                      "meter": _run(first_meter, METER_LEVELS)}}
        for facing in FACINGS[1:]:
            batteries, meter = TURNED_STORAGE_OVERLAYS[facing, item]
            fill[facing] = {"batteries": {look: _names(batteries[look], 1) for look in BATTERY_LOOKS}}
            if meter:
                fill[facing]["meter"] = _names(meter, 1)
        fills[_field(item)] = fill

    return {
        "flat": _name(SOLAR_FLAT),
        "wall": {material: _by(wall, "SE") for material, wall, _, _ in MOUNTS},
        "rack": {material: _by(rack, FACINGS) for material, _, rack, _ in MOUNTS},
        "failsafe": _name(SOLAR_FAILSAFE),
        "cellCharger": _name(SOLAR_CELL_CHARGER),
        "crate": _name(SOLAR_CRATE),
        "crateOverlays": {"full": _name(CRATE_FULL), "closed": _name(CRATE_CLOSED)},
        "gardenLight": {"off": _name(GARDEN_LIGHT), "lit": _name(GARDEN_LIGHT_LIT)},
        **storage,
        "digester": {"barrel": {drum: _name(number) for drum, number in BARREL_DIGESTERS.items()},
                     "insulated": _name(INSULATED_DIGESTER), "dome": _name(DOME_DIGESTER)},
        "digesterHolder": holders,
        "digesterScrubber": _by(SCRUBBERS, DIGESTERS),
        "digesterScrubberSpent": _by(SPENT_SCRUBBERS, DIGESTERS),
        "digesterSour": _by(SOUR_FOAM, DIGESTERS),
        "gasHeater": heater,
        "fixedTiles": fixed,
        "gasKit": {"default": _name(GAS_KIT), "bySprite": kits},
        "gasifierPipeGen": {"default": _by(GENERATOR_PIPE, DIRECTIONS), "bySprite": pipes},
        "gasifier": {tier: _name(number) for tier, number in GASIFIERS.items()},
        "gasifierLit": {tier: _name(number + len(GASIFIERS)) for tier, number in GASIFIERS.items()},
        "gasifierPipe": _by(GASIFIER_PIPE, DIRECTIONS),
        "windScoop": _name(SCOOP_ROTOR),
        "windCharger": chargers,
        "windModels": models,
        "snow": {"flat": _name(FLAT_SNOW), "rack": {material: _by(snow, FACINGS) for material, _, _, snow in MOUNTS}},
        "cracks": cracks,
        "bankFill": fills,
    }


LUA_WIDTH = 120


def _lua_key(key):
    # A sprite name reads as one when bracketed, though it is also a Lua name.
    return key if key.isidentifier() and not re.search(r"_\d+$", key) else '["%s"]' % key


def _lua_value(value, indent, lead=""):
    """`value` as Lua, at `indent` levels after `lead`: a table on one line if it holds no table and
    fits, else one entry a line."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return '"%s"' % value
    pairs = [("", v) for v in value] if isinstance(value, list) else [(_lua_key(k) + " = ", v) for k, v in value.items()]
    entries = [key + _lua_value(v, indent + 1, key) for key, v in pairs]
    inline = "{ %s }" % ", ".join(entries)
    if not any(isinstance(v, (dict, list)) for _, v in pairs) and len("    " * indent + lead + inline + ",") <= LUA_WIDTH:
        return inline
    inner = "    " * (indent + 1)
    return "{\n%s\n%s}" % ("\n".join(inner + entry + "," for entry in entries), "    " * indent)


def sprite_tiles_lua():
    return ("-- Written by tools/make_tiles.py from art/models/tile_numbers.py: edit those, not this. Every tile Lua\n"
            "-- names, by meaning; RenewableEnergy/Sprites.lua says what each shows.\n"
            "return %s\n" % _lua_value(sprite_tiles(), 0))


def main():
    # Only renewable_energy_01's tiles have properties: renewable_energy_02 is all overlays.
    tilefile.write(MEDIA, "renewable_energy.tiles",
                   [(name, rows, TILES if number == 1 else {}) for number, (name, rows) in enumerate(TILESETS, 1)])
    with open(LUA, "w", newline="\n") as f:
        f.write(sprite_tiles_lua())


if __name__ == "__main__":
    main()
