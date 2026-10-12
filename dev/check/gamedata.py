"""What the installed game defines, for the checks to compare the mod against.

Two sources. GameProbe's API file holds what only the running JVM can answer: the classes,
methods and globals Lua reaches, and a few string tables (see GameProbe.writeApi). Everything
else is read from the game's own files: the Lua it ships (what it assigns, defines and requires),
its scripts (items, tags, recipes, models), its English translations, its texture packs and its
tile definitions.

Reading the game's files takes a few seconds, so the result is cached as JSON next to the API
file, keyed by the game jar and by this checker's own source, and rebuilt when either changes.
"""
import hashlib
import json
import os
import struct
import sys

import luasource
import scripts

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))
import pack_textures  # noqa: E402
import tiledefs  # noqa: E402

# Tables the engine puts into the Lua environment itself rather than through an exposed class:
# LuaEventManager.register (Events), LuaHookManager.register (Hook), CoopMaster.register
# (CoopServer), VoiceManager.LuaRegister (VoiceManager) and LuaManager.exposeLuaCalendar
# (Calendar).
ENGINE_TABLES = {"Events", "Hook", "CoopServer", "VoiceManager", "Calendar"}

LUA_FOLDERS = ("client", "server", "shared")


class Game:
    def __init__(self, java_dir, api_file, cache_dir):
        self.java_dir = java_dir
        self.media = os.path.join(java_dir, "media")
        self._read_api(api_file)
        self._load_files(cache_dir)

    # -- GameProbe's facts --------------------------------------------------------------------

    def _read_api(self, path):
        self.methods = set()
        self.classes = {}           # simple name -> Java class name
        self.statics = {}           # simple name -> static members
        self.globals = set(ENGINE_TABLES)
        self.std_members = {}       # standard library table -> its keys
        self.events = set()
        self.translation_files = set()
        self.sandbox_names = set()
        self.item_fields = set()
        with open(path, encoding="utf-8") as f:
            for line in f:
                kind, _, rest = line.rstrip("\n").partition(" ")
                if kind == "method":
                    self.methods.add(rest)
                elif kind == "class":
                    simple, java_name = rest.split(" ", 1)
                    self.classes.setdefault(simple, java_name)
                elif kind == "static":
                    simple, member = rest.split(" ", 1)
                    self.statics.setdefault(simple, set()).add(member)
                elif kind == "global":
                    self.globals.add(rest)
                elif kind == "member":
                    table, key = rest.split(" ", 1)
                    self.std_members.setdefault(table, set()).add(key)
                elif kind == "event":
                    self.events.add(rest)
                elif kind == "translation-file":
                    self.translation_files.add(rest)
                elif kind == "sandbox":
                    self.sandbox_names.add(rest)
                    self.sandbox_names.add(rest.split(".")[0])
                elif kind == "item-field":
                    # Lowercased: Item.DoParam compares keys ignoring case.
                    self.item_fields.add(rest.lower())

    # -- The game's own files, cached ---------------------------------------------------------

    def _load_files(self, cache_dir):
        jar = os.path.join(self.java_dir, "projectzomboid.jar")
        key = hashlib.sha1()
        stat = os.stat(jar)
        key.update(("%s %d %d" % (jar, stat.st_size, stat.st_mtime)).encode())
        for module in (__file__, luasource.__file__, scripts.__file__, pack_textures.__file__, tiledefs.__file__):
            with open(module, "rb") as f:
                key.update(f.read())
        cache = os.path.join(cache_dir, "game-files.json")
        data = None
        if os.path.exists(cache):
            with open(cache, encoding="utf-8") as f:
                data = json.load(f)
            if data.get("key") != key.hexdigest():
                data = None
        if data is None:
            data = self._scan()
            data["key"] = key.hexdigest()
            with open(cache + ".tmp", "w", encoding="utf-8") as f:
                json.dump(data, f)
            os.replace(cache + ".tmp", cache)

        self.lua_globals = set(data["lua_globals"])
        self.lua_members = {table: set(keys) for table, keys in data["lua_members"].items()}
        self.lua_functions = set(data["lua_functions"])
        self.lua_events = set(data["lua_events"])
        self.lua_modules = set(data["lua_modules"])
        self.items = set(data["items"])
        self.tags = set(data["tags"])
        self.recipes = set(data["recipes"])
        self.item_types = set(data["item_types"])
        self.models = set(data["models"])
        self.translations = {name: set(keys) for name, keys in data["translations"].items()}
        self.sprites = set(data["sprites"])
        self.tilesets = data["tilesets"]

    def _scan(self):
        data = {}
        lua_globals, lua_functions, lua_events, lua_modules = set(), set(), set(), set()
        lua_members = {}
        for folder in LUA_FOLDERS:
            top = os.path.join(self.media, "lua", folder)
            for path in _files(top, ".lua"):
                lua_modules.add(os.path.relpath(path, top)[:-4].replace(os.sep, "/"))
                lua = luasource.read(path)
                lua_globals |= lua.globals
                lua_functions |= lua.functions
                for table, key in lua.members:
                    lua_members.setdefault(table, set()).add(key)
                for chain in lua.chains:
                    # LuaEventManager.AddEvent("Name") registers an event from Lua.
                    if chain.names == ["LuaEventManager", "AddEvent"] and chain.called:
                        i = lua.index[chain.at] + 4
                        if i < len(lua.tokens) and lua.tokens[i].kind == luasource.STRING:
                            lua_events.add(lua.tokens[i].text)
        data.update(lua_globals=sorted(lua_globals), lua_functions=sorted(lua_functions),
                    lua_events=sorted(lua_events), lua_modules=sorted(lua_modules),
                    lua_members={table: sorted(keys) for table, keys in lua_members.items()})

        items, tags, recipes, item_types, models = set(), set(), set(), set(), set()
        for path in _files(os.path.join(self.media, "scripts"), ".txt"):
            with open(path, encoding="utf-8", errors="replace") as f:
                root = scripts.parse(f.read())
            for module, block in scripts.modules(root):
                for child in block.children:
                    if child.type == "item":
                        items.add("%s.%s" % (module, child.id))
                        for value in child.all("Tags"):
                            tags.update(t.strip().lower() for t in value.value.split(";") if t.strip())
                        for value in child.all("ItemType"):
                            item_types.add(value.value)
                    elif child.type == "craftRecipe":
                        recipes.add(child.id)
                    elif child.type == "model":
                        models.add("%s.%s" % (module, child.id))
        data.update(items=sorted(items), tags=sorted(tags), recipes=sorted(recipes),
                    item_types=sorted(item_types), models=sorted(models))

        translations = {}
        english = os.path.join(self.media, "lua", "shared", "Translate", "EN")
        for name in os.listdir(english):
            if name.endswith(".json"):
                with open(os.path.join(english, name), encoding="utf-8", errors="replace") as f:
                    try:
                        translations[name[:-5]] = sorted(json.load(f))
                    except ValueError:
                        pass
        data["translations"] = translations

        sprites = set()
        for path in _files(os.path.join(self.media, "texturepacks"), ".pack"):
            for page in pack_textures.read_index(path):
                sprites.update(sprite.name for sprite in page.sprites)
        data["sprites"] = sorted(sprites)

        # Tileset name -> tile count, for sprite names such as location_shop_generic_01_12.
        tilesets = {}
        for name in os.listdir(self.media):
            if name.endswith(".tiles"):
                # IsoWorld.init loads newtiledefinitions.tiles as file number 1.
                number = 1 if name == "newtiledefinitions.tiles" else None
                for tileset in tiledefs.load(os.path.join(self.media, name), number):
                    tilesets[tileset.name] = max(len(tileset.tiles), tilesets.get(tileset.name, 0))
        data["tilesets"] = tilesets
        return data

    # -- Lookups ------------------------------------------------------------------------------

    def file(self, relative):
        """The game file at a path relative to its Java folder (media/...), if it exists."""
        path = os.path.join(self.java_dir, *relative.split("/"))
        return path if os.path.exists(path) else None


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


def _files(top, suffix):
    for base, _dirs, names in os.walk(top):
        for name in sorted(names):
            if name.endswith(suffix):
                yield os.path.join(base, name)
