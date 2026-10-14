"""Write renewable_energy.tiles, the properties of every tile in renewable_energy_01, and
tileGeometry.txt.

    python3 tools/make_tiles.py

Tile numbers match art/models/tiles.py, which renders them, and
media/lua/shared/RenewableEnergy/Sprites.lua, which names them for Lua. Overlay tiles (snow, cracked
glass, batteries, the charge meter, the crate's contents and lid) are only ever attached to another tile,
so they have no properties. Property names and values follow the vanilla tile definitions
(newtiledefinitions.tiles); ISMoveableSpriteProps reads the moveable ones:

- CustomItem: the item that picking the tile up gives, instead of a generic Moveables item.
- Facing and N/S/E/Woffset: the placing cursor's rotation, the offsets pointing from one facing's
  tile number to the others'.
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
TILESET = "renewable_energy_01"
COLUMNS, ROWS = 8, 29


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


RACK_OFFSETS = {"S": {"E": 1, "N": 2, "W": 3}, "E": {"S": -1, "N": 1, "W": 2},
                "N": {"S": -2, "E": -1, "W": 1}, "W": {"S": -3, "E": -2, "N": -1}}


def rack(item, facing):
    return panel("Ground Rack", item, 3, Facing=facing, BlocksPlacement="", solidtrans="",
                 **{side + "offset": str(offset) for side, offset in RACK_OFFSETS[facing].items()})


def storage(item, group, name, level, capacity, **props):
    """A battery box, rack or bank: a container of its own type, scrapped by its own definition.
    GeneratorSound names the sounds its generator plays when switched (scripts Sounds.txt)."""
    return moveable(item, level, CustomName=name, GroupName=group, container="RenewableEnergy" + item,
                    ContainerCapacity=str(capacity), Material="RenewableEnergy" + item, CanScrap="",
                    BlocksPlacement="", solidtrans="", GeneratorSound="RenewableEnergyBank", **props)


def garden_light():
    # Lit and unlit both give the light back; it needs no tool, like a lamp.
    return moveable("SolarGardenLight", tool=None, CustomName="Solar Garden Light", Material="Electric")


TILES = {
    0: panel("Flat", "SolarFlat", 2, RenderLayer="Floor", IsLow=""),
    # Sits on the generator's square, which a floor rug's move type allows.
    7: moveable("SolarFailsafe", 3, CustomName="Solar Failsafe", MoveType="FloorRug", Material="Electric"),
    8: storage("BatteryBoxWood", "Wooden", "Battery Box", 1, 40, ContainerPosition="Low", IsLow=""),
    9: storage("BatteryBankMetal", "Metal", "Battery Bank", 4, 100),
    # Small enough for a table or counter, like the vanilla radios.
    10: moveable("SolarCellCharger", tool=None, CustomName="Solar Battery Charger",
                 container="RenewableEnergyCellCharger", ContainerCapacity="1", IsTableTop="", IsSurfaceOffset="",
                 BlocksPlacement="", Material="Electric"),
    11: {"IsMoveAble": "", "CustomName": "Solar Box", "container": "RenewableEnergySolarBox", "ContainerCapacity": "50",
         "ContainerPosition": "Low", "Material": "Paper", "CanScrap": "", "PickUpWeight": "10", "BlocksPlacement": "",
         "solidtrans": "", "IsLow": "", "Surface": "14"},
    14: garden_light(),
    15: garden_light(),
    23: storage("BatteryBoxMetal", "Metal", "Battery Box", 1, 40, ContainerPosition="Low", IsLow=""),
    32: storage("BatteryRackWood", "Wooden", "Battery Rack", 3, 100),
    33: storage("BatteryRackMetal", "Metal", "Battery Rack", 3, 100),
    34: storage("BatteryBankWood", "Wooden", "Battery Bank", 4, 100),
}
for material, first_wall, first_rack in (("Metal", 1, 3), ("Wood", 21, 24)):
    for offset, facing in enumerate("SE"):
        TILES[first_wall + offset] = wall("SolarWall" + material, facing)
    for offset, facing in enumerate("SENW"):
        TILES[first_rack + offset] = rack("SolarRack" + material, facing)


def main():
    tiles = [sorted(TILES.get(index, {}).items(), key=lambda prop: prop[0].lower())
             for index in range(COLUMNS * ROWS)]
    # The only tileset in the file, so number 1.
    tileset = tiledefs.Tileset(TILESET, TILESET + ".png", COLUMNS, ROWS, 1, tiles)
    data = tiledefs.dumps([tileset])
    assert tiledefs.loads(data) == [tileset], "the tiles would not read back as written"
    with open(TILES_FILE, "wb") as f:
        f.write(data)
    print("%s: %d tiles with properties" % (os.path.basename(TILES_FILE), len(TILES)))
    with open(GEOMETRY_FILE, "w") as f:
        f.write("tileGeometry\n{\n    VERSION = 2,\n}\n")


if __name__ == "__main__":
    main()
