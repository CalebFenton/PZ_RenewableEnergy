"""The static check's rules for this mod's stash houses (dev/harness/docs/static-check.md,
"Plugins").

| Check | What it catches |
| --- | --- |
| `stash-building` | A stash's `buildingX`, `buildingY` in no ground-floor room of a building, read from the game's `.lotheader` files. |
| `stash-crate` | A stash crate outside every room of that building: `doBuildingStash` stocks only containers in the house's rooms. |
"""
import os
import struct

from rules import check


class WorldMap:
    """Rooms and buildings of the world map, read from its .lotheader files on demand.

    The layout is IsoMetaGrid's loader: optional "LOTH", int32 version (0 or 1), a tile count and
    that many newline-terminated tile names (version 0 then has one stray byte), width and height
    in chunks, version 0's level count or version 1's min and max level, then the rooms: a name
    line, the level, a rect count and x, y, w, h per rect (in the cell, though a rect can run past
    its edge into the next cell), and a count of three-int objects. Last come the buildings, each
    a count and that many room indexes. Integers are little endian.
    """

    CELL = 256

    def __init__(self, media):
        maps = os.path.join(media, "maps")
        self.folders = [os.path.join(maps, name) for name in sorted(os.listdir(maps))] if os.path.isdir(maps) else []
        self.cells = {}

    def room_at(self, x, y, z):
        """(room name, building) at a square, building being an id unique on the map; None outside
        any room. Raises LookupError when no lotheader covers the square's cell."""
        cx, cy = x // self.CELL, y // self.CELL
        if self._rooms(cx, cy) is None:
            raise LookupError("no lotheader for cell %d,%d" % (cx, cy))
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for name, level, rects, building in self._rooms(cx + dx, cy + dy) or ():
                    if level == z and any(rx <= x < rx + rw and ry <= y < ry + rh for rx, ry, rw, rh in rects):
                        return name, building
        return None

    def _rooms(self, cx, cy):
        if (cx, cy) not in self.cells:
            self.cells[cx, cy] = None
            for folder in self.folders:
                path = os.path.join(folder, "%d_%d.lotheader" % (cx, cy))
                if os.path.exists(path):
                    with open(path, "rb") as f:
                        self.cells[cx, cy] = self._parse(f.read(), cx, cy)
                    break
        return self.cells[cx, cy]

    def _parse(self, data, cx, cy):
        at = 4 if data[:4] == b"LOTH" else 0

        def ints(n):
            nonlocal at
            values = struct.unpack_from("<%di" % n, data, at)
            at += 4 * n
            return values

        def line():
            nonlocal at
            end = data.index(b"\n", at)
            text = data[at:end].decode("latin-1")
            at = end + 1
            return text

        (version,) = ints(1)
        if version not in (0, 1):
            raise ValueError("lotheader %d,%d has version %d" % (cx, cy, version))
        for _ in range(ints(1)[0]):
            line()
        at += 1 if version == 0 else 0
        ints(3 if version == 0 else 4)
        rooms = []
        for _ in range(ints(1)[0]):
            name = line()
            level, count = ints(2)
            rects = [(x + cx * self.CELL, y + cy * self.CELL, w, h) for x, y, w, h in
                     (ints(4) for _ in range(count))]
            # Not `at += 12 * ints(1)[0]`: that reads at before ints moves it past the count.
            (objects,) = ints(1)
            at += 12 * objects
            rooms.append([name, level, rects, None])
        for building in range(ints(1)[0]):
            for room in ints(ints(1)[0]):
                rooms[room][3] = (cx, cy, building)
        return [tuple(room) for room in rooms]


@check
def stash_houses(mod, game, report):
    # A stash is two hand-written map points that fail quietly. StashSystem finds the house as the
    # building of the ground floor room at buildingX, buildingY, and builds the crate at its
    # coordinates with no fallback. doBuildingStash then stocks only containers standing in a room
    # of that building, so a crate anywhere else spawns empty. Rooms and buildings come from the
    # game's .lotheader files, which IsoMetaGrid builds the map from.
    world = None
    for lua in mod.lua:
        for at, fields in lua.tables:
            if not isinstance(fields.get("buildingX"), int) or not isinstance(fields.get("buildingY"), int):
                continue
            world = world or WorldMap(game.media)
            report.saw("stash houses")
            name = fields.get("name", "stash")
            line = lua.line(at)
            try:
                house = world.room_at(fields["buildingX"], fields["buildingY"], 0)
            except LookupError as e:
                report.note("%s: %s, so its coordinates went unchecked" % (name, e))
                continue
            if house is None or house[1] is None:
                report.fail("stash-building", lua.path, line, "%s: buildingX, buildingY %d,%d is in no room of a "
                            "building, so the game finds no house" % (name, fields["buildingX"], fields["buildingY"]))
                continue
            crate = [fields.get(k) or fields.get(k.replace("crate", "cont")) for k in ("crateX", "crateY", "crateZ")]
            if not all(isinstance(v, int) for v in crate[:2]):
                continue
            crate[2] = crate[2] or 0
            report.saw("stash crates")
            room = world.room_at(*crate)
            if room is None or room[1] != house[1]:
                levels = [z for z in range(8) if (world.room_at(crate[0], crate[1], z) or (None, None))[1] == house[1]]
                report.fail("stash-crate", lua.path, line, "%s: the crate at %d,%d,%d is in no room of the house "
                            "(%s), so it is never stocked%s"
                            % (name, crate[0], crate[1], crate[2], house[0],
                               "; the house has rooms there on level %s" % ", ".join(map(str, levels)) if levels else ""))
