#!/usr/bin/env python3
"""Counts what a thorough player could search in the TOWNS of the Build 42 map: every room, every
container tile by the room it stands in, and every vehicle stall by its vehicle zone, and the
whole map's vehicle stalls. Writes them to
dev/RenewableEnergyDevHarness/42/media/lua/client/RenewableEnergyDevTownCensus.lua, which the
--loot report multiplies by each container's, room's and vehicle's expected modules.

    python3 dev/loot/census.py [PZ media folder]

The media folder defaults to the macOS Steam install. Rerun it after a game update changes the
map. It reads the files IsoMetaGrid and IsoLot read:

- <map>/<cx>_<cy>.lotheader: "LOTH", int32 version, the cell's tile names (one per line), its
  size and levels, then its rooms: a name line, level, rects (x, y, w, h in the cell, which can
  run into the next cell), and objects.
- <map>/world_<cx>_<cy>.lotpack: "LOTP", int32 version, int32 chunk count, then an int64 offset
  per 8 x 8 chunk (index x * 32 + y). Each chunk lists its squares level by level, x then y: an
  int32 count; -1 and a count of squares to skip; or an int32 the game skips (-1 in Build 42
  maps) and count - 1 tile indexes into the header's names. Rooms come from the rects.
- <map>/objects.lua: the map zones; a ParkingStall zone's name is its VehicleZoneDistribution.
- *.tiles: each tile's properties; a container tile has a "container" property naming its type.

Vehicle stalls are counted as IsoChunk.AddVehicles_OnZone lays them out: a stall every 3 squares
across and 5 along a zone facing north or south, 5 across and 3 along one facing east or west.
Traffic jam zones (trafficjam<n|s|e|w>, and the rtrafficjam ones each chunk rolls for) are laid
out by IsoChunk.AddVehicles_TrafficJam_*, closer together; their counts are the expected number
of cars' slots, whether or not a car takes each.
"""
import functools
import os
import re
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
import tiledefs  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(REPO, "dev", "RenewableEnergyDevHarness", "42", "media", "lua", "client",
                   "RenewableEnergyDevTownCensus.lua")
DEFAULT_MEDIA = os.path.expanduser("~/Library/Application Support/Steam/steamapps/common/ProjectZomboid/"
                                   "Project Zomboid.app/Contents/Java/media")
MAP = "Muldraugh, KY"
CELL = 256
CHUNK = 8

# Town bounds, x1, y1, x2, y2 inclusive, drawn around each town's built-up area.
TOWNS = [
    ("Muldraugh", 10550, 9250, 11000, 10700),
    ("West Point", 10900, 6550, 12200, 7150),
    ("Riverside", 5650, 5100, 7000, 5600),
    ("Rosewood", 7950, 11380, 8400, 11960),
    ("March Ridge", 9800, 12590, 10510, 13140),
]


def container_types(media):
    """Tile name -> container type, from the game's tile definitions. The game reads its own
    files as file 1, which may hold more tilesets than a mod's."""
    types = {}
    for name in sorted(os.listdir(media)):
        if name.endswith(".tiles"):
            for tileset in tiledefs.load(os.path.join(media, name), 1):
                for index, props in enumerate(tileset.tiles):
                    for key, value in props:
                        if key == "container":
                            types["%s_%d" % (tileset.name, index)] = value
    return types


@functools.lru_cache(maxsize=None)
def read_header(path, cell):
    """The cell's tile names, its lowest and highest level, and its rooms as (name, level, rects),
    with the rects in world squares."""
    with open(path, "rb") as f:
        data = f.read()
    at = 4 if data[:4] == b"LOTH" else 0
    (version,) = struct.unpack_from("<i", data, at)
    at += 4
    (count,) = struct.unpack_from("<i", data, at)
    at += 4
    tiles = []
    for _ in range(count):
        end = data.index(b"\n", at)
        tiles.append(data[at:end].decode("latin-1"))
        at = end + 1
    if version == 0:
        _w, _h, levels = struct.unpack_from("<3i", data, at + 1)
        at += 13
        min_level, max_level = 0, levels - 1
    else:
        _w, _h, min_level, max_level = struct.unpack_from("<4i", data, at)
        at += 16
    (room_count,) = struct.unpack_from("<i", data, at)
    at += 4
    rooms = []
    ox, oy = cell
    for _ in range(room_count):
        end = data.index(b"\n", at)
        name = data[at:end].decode("latin-1")
        at = end + 1
        level, rect_count = struct.unpack_from("<2i", data, at)
        at += 8
        rects = []
        for _ in range(rect_count):
            x, y, w, h = struct.unpack_from("<4i", data, at)
            at += 16
            rects.append((x + ox * CELL, y + oy * CELL, w, h))
        (objects,) = struct.unpack_from("<i", data, at)
        at += 4 + 12 * objects
        rooms.append((name, level, rects))
    return tiles, min_level, max_level, rooms


def chunk_squares(pack, index, levels):
    """Yields (lx, ly, z, tile indexes) of one chunk's non-empty squares."""
    (offset,) = struct.unpack_from("<q", pack, 12 + index * 8)
    at = offset
    skip = 0
    for z in range(levels[0], levels[1] + 1):
        for x in range(CHUNK):
            for y in range(CHUNK):
                if skip > 0:
                    skip -= 1
                    continue
                (count,) = struct.unpack_from("<i", pack, at)
                at += 4
                if count == -1:
                    (skip,) = struct.unpack_from("<i", pack, at)
                    at += 4
                    if skip > 0:
                        skip -= 1
                        continue
                if count > 1:
                    tiles = struct.unpack_from("<%di" % (count - 1), pack, at + 4)
                    at += 4 * count
                    yield x, y, z, tiles


def town_cells(folder, town, margin=0):
    """(cx, cy, lotheader path) of each cell of the map under the town's bounds, and `margin`
    cells around them."""
    _name, x1, y1, x2, y2 = town
    for cx in range(x1 // CELL - margin, x2 // CELL + 1 + margin):
        for cy in range(y1 // CELL - margin, y2 // CELL + 1 + margin):
            header = os.path.join(folder, "%d_%d.lotheader" % (cx, cy))
            if os.path.exists(header):
                yield cx, cy, header


def room_names(folder, town):
    """(x, y, z) -> room name for the squares of the town's rooms, from the town's cells and
    their neighbours, whose rects can reach in."""
    _name, x1, y1, x2, y2 = town
    names = {}
    for cx, cy, header in town_cells(folder, town, margin=1):
        for name, level, rects in read_header(header, (cx, cy))[3]:
            for rx, ry, w, h in rects:
                for x in range(max(rx, x1), min(rx + w, x2 + 1)):
                    for y in range(max(ry, y1), min(ry + h, y2 + 1)):
                        names[x, y, level] = name
    return names


def count_containers(folder, types, town):
    _name, x1, y1, x2, y2 = town
    rooms = room_names(folder, town)
    containers = {}
    for cx, cy, header in town_cells(folder, town):
        tiles, min_level, max_level, _rooms = read_header(header, (cx, cy))
        with open(os.path.join(folder, "world_%d_%d.lotpack" % (cx, cy)), "rb") as f:
            pack = f.read()
        for chx in range(CELL // CHUNK):
            for chy in range(CELL // CHUNK):
                ox, oy = cx * CELL + chx * CHUNK, cy * CELL + chy * CHUNK
                if ox + CHUNK <= x1 or ox > x2 or oy + CHUNK <= y1 or oy > y2:
                    continue
                for lx, ly, z, indexes in chunk_squares(pack, chx * 32 + chy, (min_level, max_level)):
                    room_name = rooms.get((ox + lx, oy + ly, z))
                    if room_name is None:
                        continue
                    for index in indexes:
                        kind = types.get(tiles[index])
                        if kind:
                            by_type = containers.setdefault(room_name, {})
                            by_type[kind] = by_type.get(kind, 0) + 1
    return containers


def count_rooms(folder, town):
    """Room name -> how many rooms of that name start inside the town."""
    _name, x1, y1, x2, y2 = town
    counts = {}
    for cx, cy, header in town_cells(folder, town):
        for name, _level, rects in read_header(header, (cx, cy))[3]:
            if rects and x1 <= rects[0][0] <= x2 and y1 <= rects[0][1] <= y2:
                counts[name] = counts.get(name, 0) + 1
    return counts


ZONE = re.compile(r'\{ name = "([^"]*)", type = "ParkingStall", x = (\d+), y = (\d+), z = 0, '
                  r'width = (\d+), height = (\d+)(?:, properties = \{ Direction = "(\w)" \})?')


def stalls_along(start, length, step):
    count, at = 0, start + step / 2.0
    while at < start + length:
        count, at = count + 1, at + step
    return count


JAM = re.compile(r"^r?trafficjam([nsew])$")


def jam_slots_along(start, length, first, step, jitter):
    """Expected slots along one axis of a traffic jam zone, as each chunk lays them: from the
    first slot of the zone's grid (start + first + step * k) inside the chunk, then every `step`
    squares, or one less half the time when `jitter`, while still inside the chunk and the zone."""
    end, count = start + length, 0.0
    for chunk in range(start // CHUNK * CHUNK, end, CHUNK):
        at = start + first
        while at < chunk:
            at += step
        limit = min(chunk + CHUNK, end)
        if at >= limit:
            continue
        count += 1
        for next_at, chance in (((at + step - 1, 0.5), (at + step, 0.5)) if jitter else ((at + step, 1.0),)):
            if next_at < limit:
                count += chance
    return count


def jam_slots(facing, x, y, w, h):
    """IsoChunk.AddVehicles_TrafficJam_*: rows 3 squares apart across the road, cars about 6
    along it."""
    if facing in ("n", "s"):
        return jam_slots_along(x, w, 1, 3, False) * jam_slots_along(y, h, 3, 6, True)
    return jam_slots_along(y, h, 1, 3, False) * jam_slots_along(x, w, 3, 6, False)


def vehicle_stalls(folder, town):
    _name, x1, y1, x2, y2 = town
    stalls = {}
    with open(os.path.join(folder, "objects.lua"), encoding="latin-1") as f:
        text = f.read()
    for m in ZONE.finditer(text):
        name, x, y, w, h, direction = m.group(1), *map(int, m.groups()[1:5]), m.group(6)
        if not (x1 <= x + w / 2 <= x2 and y1 <= y + h / 2 <= y2):
            continue
        key = (name or "parkingstall").lower()
        jam = JAM.match(key)
        if jam:
            count = jam_slots(jam.group(1), x, y, w, h)
        elif "trafficjam" in key:
            continue  # A misspelt jam, which the engine neither jams nor parks.
        else:
            # The engine's guess at the facing of a zone without a Direction (IsoChunk.AddVehicles_OnZone).
            facing = "N"
            if w in (4, 5, 6) and (h <= 3 or h >= 6):
                facing = "W"
            facing = direction or facing
            across, along = (3, 5) if facing in ("N", "S") else (5, 3)
            count = stalls_along(x, w, across) * stalls_along(y, h, along)
        stalls[key] = stalls.get(key, 0) + count
    return stalls


def lua_table(counts, indent):
    pad = " " * indent
    lines = []
    for key in sorted(counts):
        value = counts[key]
        if isinstance(value, dict):
            lines.append('%s["%s"] = { %s },' % (pad, key, ", ".join('["%s"] = %d' % (k, value[k]) for k in sorted(value))))
        else:
            lines.append('%s["%s"] = %g,' % (pad, key, round(value, 1)))
    return "\n".join(lines)


def main():
    media = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MEDIA
    folder = os.path.join(media, "maps", MAP)
    types = container_types(media)
    out = ["-- Written by dev/loot/census.py from the game's map; rerun it rather than edit this file.",
           "-- towns: each town's bounds, its rooms by name, its container tiles by room name and",
           "-- container type, and its vehicle stalls by vehicle zone. mapVehicleStalls: the whole map's.",
           "return {",
           "    towns = {"]
    for town in TOWNS:
        name, x1, y1, x2, y2 = town
        print("counting", name, file=sys.stderr)
        out.append('        { name = "%s", x1 = %d, y1 = %d, x2 = %d, y2 = %d,' % (name, x1, y1, x2, y2))
        for field, counts in (("rooms", count_rooms(folder, town)),
                              ("containers", count_containers(folder, types, town)),
                              ("vehicleStalls", vehicle_stalls(folder, town))):
            out.append("            %s = {" % field)
            out.append(lua_table(counts, 16))
            out.append("            },")
        out.append("        },")
    out.append("    },")
    out.append("    mapVehicleStalls = {")
    out.append(lua_table(vehicle_stalls(folder, ("map", 0, 0, 1 << 20, 1 << 20)), 8))
    out.append("    },")
    out.append("}")
    with open(OUT, "w") as f:
        f.write("\n".join(out) + "\n")
    print("wrote", OUT, file=sys.stderr)


if __name__ == "__main__":
    main()
