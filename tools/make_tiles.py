"""Write renewable_energy.tiles, the properties of every tile in renewable_energy_01 and
renewable_energy_02, and tileGeometry.txt.

    python3 tools/make_tiles.py

Tile numbers come from art/models/tile_numbers.py, which art/models/tiles.py renders from and
media/lua/shared/RenewableEnergy/Sprites.lua names for Lua. Overlay tiles (snow, cracked
glass, batteries, the charge meter, the crate's contents and lid, the digesters' gas holders and
scrubbers, the generator's gas kit, the gasifiers' glow and gas pipes, and all of
renewable_energy_02) are only ever attached to another tile, so they have no properties. Property
names and values follow the vanilla tile definitions
(newtiledefinitions.tiles); ISMoveableSpriteProps reads the moveable ones:

- CustomItem: the item that picking the tile up gives, instead of a generic Moveables item.
- Facing and N/S/E/Woffset: the placing cursor's rotation, the offsets pointing from one facing's
  tile number to the others' in the same tileset (ISMoveableSpriteProps.getFaces).
- MoveType = WallObject with attachedN or attachedW: hung on the wall at the square's north or west
  edge, which ISMoveableSpriteProps.getWallForFacing finds for Facing S and E.
- PickUpTool and PlaceTool name an ISMoveableDefinitions tool (Electrician is a screwdriver and the
  Electricity skill), PickUpLevel the skill needed.
- Container types and scrap materials are global across mods, so they carry the mod's name.

The game loads a mod's depth maps (media/depthmaps/DEPTH_<tileset>.png, which art/models/render.py
renders) only when the mod's common/media has a tileGeometry.txt (TileDepthTextureManager.init),
so this writes one without geometry. Without the depth map every tile would be drawn as if it
filled its square up to the ceiling, and hide a character standing in front of a wall panel.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "dev", "harness", "check"))
sys.path.insert(0, os.path.join(HERE, "..", "art", "models"))
import tiledefs  # noqa: E402
from tile_numbers import (BARREL_DIGESTERS, COLUMNS, DOME_DIGESTER, FACINGS, GARDEN_LIGHT, GARDEN_LIGHT_LIT,  # noqa: E402
                          GASIFIERS, HEATER, HEATER_LIT, INSULATED_DIGESTER, MOUNTS, SCOOP_ROTOR, SOLAR_CELL_CHARGER,
                          SOLAR_CRATE, SOLAR_FAILSAFE, SOLAR_FLAT, STORAGE_TILES, TURNED_HEATER_FIRST,
                          TURNED_STORAGE_FIRST, WIND_TILES)

MEDIA = os.path.join(HERE, "..", "Contents", "mods", "RenewableEnergy", "common", "media")
TILES_FILE = os.path.join(MEDIA, "renewable_energy.tiles")
GEOMETRY_FILE = os.path.join(MEDIA, "tileGeometry.txt")
# Each tileset's name and rows, COLUMNS tiles to a row; the file numbers them from 1 in this order.
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


def facings(tiles, facing):
    """The placing cursor's rotation for `facing`'s tile of `tiles`, a tile number by facing."""
    own = tiles[facing]
    return {"Facing": facing, **{other + "offset": str(index - own) for other, index in tiles.items() if other != facing}}


def turned(first, make):
    """Four tiles from `first`, one per facing in FACINGS' order, each make(**its rotation)."""
    tiles = {facing: first + f for f, facing in enumerate(FACINGS)}
    for facing, index in tiles.items():
        TILES[index] = make(**facings(tiles, facing))


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


def main():
    tilesets = []
    for number, (name, rows) in enumerate(TILESETS, 1):
        properties = TILES if number == 1 else {}
        assert max(properties, default=0) < COLUMNS * rows, "%s has more tiles than rows" % name
        tiles = [sorted(properties.get(index, {}).items(), key=lambda prop: prop[0].lower())
                 for index in range(COLUMNS * rows)]
        tilesets.append(tiledefs.Tileset(name, name + ".png", COLUMNS, rows, number, tiles))
    data = tiledefs.dumps(tilesets)
    assert tiledefs.loads(data) == tilesets, "the tiles would not read back as written"
    with open(TILES_FILE, "wb") as f:
        f.write(data)
    print("%s: %d tiles with properties" % (os.path.basename(TILES_FILE), len(TILES)))
    with open(GEOMETRY_FILE, "w") as f:
        f.write("tileGeometry\n{\n    VERSION = 2,\n}\n")


if __name__ == "__main__":
    main()
