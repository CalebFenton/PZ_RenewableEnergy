"""Write renewable_energy.tiles, the properties of every tile in renewable_energy_01 and
renewable_energy_02, and tileGeometry.txt.

    python3 tools/make_tiles.py

Tile numbers match art/models/tiles.py, which renders them, and
media/lua/shared/RenewableEnergy/Sprites.lua, which names them for Lua. Overlay tiles (snow, cracked
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
import tiledefs  # noqa: E402

MEDIA = os.path.join(HERE, "..", "Contents", "mods", "RenewableEnergy", "common", "media")
TILES_FILE = os.path.join(MEDIA, "renewable_energy.tiles")
GEOMETRY_FILE = os.path.join(MEDIA, "tileGeometry.txt")
# Each tileset's name and rows, eight tiles to a row; the file numbers them from 1 in this order.
TILESETS = (("renewable_energy_01", 47), ("renewable_energy_02", 56))
COLUMNS = 8


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


def rack(item, tiles, facing):
    return panel("Ground Rack", item, 3, BlocksPlacement="", solidtrans="", **facings(tiles, facing))


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
    0: panel("Flat", "SolarFlat", 2, RenderLayer="Floor", IsLow=""),
    # Sits on the generator's square, which a floor rug's move type allows.
    7: moveable("SolarFailsafe", 3, CustomName="Solar Failsafe", MoveType="FloorRug", Material="Electric"),
    # Small enough for a table or counter, like the vanilla radios.
    10: moveable("SolarCellCharger", tool=None, CustomName="Solar Battery Charger",
                 container="RenewableEnergyCellCharger", ContainerCapacity="1", IsTableTop="", IsSurfaceOffset="",
                 BlocksPlacement="", Material="Electric"),
    11: {"IsMoveAble": "", "CustomName": "Solar Box", "container": "RenewableEnergySolarBox", "ContainerCapacity": "50",
         "ContainerPosition": "Low", "Material": "Paper", "CanScrap": "", "PickUpWeight": "10", "BlocksPlacement": "",
         "solidtrans": "", "IsLow": "", "Surface": "14"},
    14: garden_light(),
    15: garden_light(),
    230: built_in_place("Insulated Digester", "Digester", 50, "Wood", "Nails"),
    231: built_in_place("Brick Dome Digester", "Digester", 100, "Brick", "Stone", IsLow=""),
    250: built_in_place("Primitive Gasifier", "Gasifier", 8, "SmallMetalPlates", "MetalPipe"),
    251: built_in_place("Gasifier", "Gasifier", 20, "MetalPlates", "MetalPipe"),
    252: built_in_place("Advanced Gasifier", "Gasifier", 30, "MetalPlates", "MetalBars"),
    264: wind_charger("Scoop Rotor Wind Charger", "MetalPlates", "MetalPipe"),
}
for material, first_wall, first_rack in (("Metal", 1, 3), ("Wood", 21, 24)):
    for offset, facing in enumerate("SE"):
        TILES[first_wall + offset] = wall("SolarWall" + material, facing)
    tiles = {facing: first_rack + offset for offset, facing in enumerate("SENW")}
    for facing, index in tiles.items():
        TILES[index] = rack("SolarRack" + material, tiles, facing)

# Battery storage, in art/models/tiles.py's STORAGE_TILES order: the item, its GroupName and
# CustomName, pick-up level, container capacity, the S tile a save's storage stands on, and its
# other properties. The cursor turns a tile only to numbers at most 96 away (offsets outside -96 to
# 96 read as -96: IsoWorld.SetCustomPropertyValues), and none near those tiles is free, so they
# don't turn. Each storage turns through four tiles in FACINGS' order from TURNED_STORAGE_FIRST.
STORAGE = (
    ("BatteryBoxWood", "Wooden", "Battery Box", 1, 40, 8, {"ContainerPosition": "Low", "IsLow": ""}),
    ("BatteryBoxMetal", "Metal", "Battery Box", 1, 40, 23, {"ContainerPosition": "Low", "IsLow": ""}),
    ("BatteryRackWood", "Wooden", "Battery Rack", 3, 100, 32, {}),
    ("BatteryRackMetal", "Metal", "Battery Rack", 3, 100, 33, {}),
    ("BatteryBankWood", "Wooden", "Battery Bank", 4, 100, 34, {}),
    ("BatteryBankMetal", "Metal", "Battery Bank", 4, 100, 9, {}),
)
FACINGS = "SENW"
TURNED_STORAGE_FIRST = 340
for i, (item, group, name, level, capacity, fixed, props) in enumerate(STORAGE):
    TILES[fixed] = storage(item, group, name, level, capacity, **props)
    tiles = {facing: TURNED_STORAGE_FIRST + len(FACINGS) * i + f for f, facing in enumerate(FACINGS)}
    for facing, index in tiles.items():
        TILES[index] = storage(item, group, name, level, capacity, **props, **facings(tiles, facing))

# The gas heater, off and lit, as a save's heaters stand; then off in each of FACINGS from
# TURNED_HEATER_FIRST, then lit in each, as the storage turns.
TURNED_HEATER_FIRST = TURNED_STORAGE_FIRST + len(FACINGS) * len(STORAGE)
for fixed, first in ((244, TURNED_HEATER_FIRST), (245, TURNED_HEATER_FIRST + len(FACINGS))):
    TILES[fixed] = gas_heater()
    tiles = {facing: first + f for f, facing in enumerate(FACINGS)}
    for facing, index in tiles.items():
        TILES[index] = gas_heater(**facings(tiles, facing))

# The propeller and alternator chargers, a tile per facing (N, E, S, W): the wooden propeller's,
# the pipe propeller's, then the alternator's.
for first, name, material2 in ((265, "Propeller Wind Charger", "Wood"), (269, "Propeller Wind Charger", "Plastic"),
                               (273, "Homemade Alternator Wind Charger", "MetalScrap")):
    for offset in range(4):
        TILES[first + offset] = wind_charger(name, "MetalPipe", material2)

# The barrel digester, a tile per barrel it can be built from: the Metal Drum, then the orange, dark
# green and light green barrels, all steel like the game's own.
for index in (228, 229, 277, 278):
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
