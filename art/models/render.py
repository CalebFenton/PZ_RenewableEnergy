"""Renders the tile sprites, their depth map, the inventory icons and the build-menu icons from the
models in items.py.

    blender -b --factory-startup -P art/models/render.py [-- tiles|icons ...]

Tiles go to tools/tiles as whole 128 x 256 cells, which tools/pack_textures.py trims and packs.
Icons go to tools/textures as Item_RenewableEnergy_<Item>.png, 32 x 32 like the game's own, and
the build-menu icons of tiles.BUILD_ICONS as RenewableEnergy_Build_<Name>.png, 48 x 48 like the
game's Build_ icons in UI2.pack. The depth map goes to common/media/depthmaps.

The projection is the game's (TileDepthTexture, TileGeometryUtils): an orthographic camera 30
degrees above the horizon looking north-west, a tile floor 128 x 64 pixels, so 64 * sqrt(2)
pixels to the metre across the floor, and a storey of 2.44949 metres drawn 192 pixels tall. A
tile's floor centre is at pixel (64, 224) of its cell.
"""
import math
import os
import sys
import tempfile

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import items  # noqa: E402
import kit  # noqa: E402
import tiles  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
MEDIA = os.path.join(REPO, "Contents/mods/RenewableEnergy/common/media")
TILE_DIR = os.path.join(REPO, "tools/tiles")
ICON_DIR = os.path.join(REPO, "tools/textures")
DEPTH_FILE = os.path.join(MEDIA, "depthmaps/DEPTH_renewable_energy_01.png")
TILESET = "renewable_energy_01"
SCRATCH = os.path.join(tempfile.gettempdir(), "renewable-energy-render")

TILE_W, TILE_H = 128, 256
COLUMNS = 8  # the game reads tilesets and their depth maps eight tiles wide
PIXELS_PER_METRE = 64 * math.sqrt(2)
STOREY = 2.44949
ICON_SIZE = 32
BUILD_ICON_SIZE = 48
ICON_OVERSAMPLE = 8  # rendered larger, then averaged down, so edges stay clean


def view_direction(elevation=30.0):
    """From the camera into the scene: from the south-east, `elevation` degrees down."""
    e = math.radians(elevation)
    return Vector((-math.cos(e) / math.sqrt(2), math.cos(e) / math.sqrt(2), -math.sin(e)))


# Scene --------------------------------------------------------------------------------------------


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 96
    scene.cycles.use_denoising = False
    scene.cycles.pixel_filter_type = "BLACKMAN_HARRIS"
    scene.cycles.filter_width = 1.2
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.new("Ambient")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.56, 0.6, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    scene.world = world
    # The game's own tiles are lit from the upper left of the screen: west, a little south. A sun
    # shines down its -Z axis, so that is the axis turned along the light's way.
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(8)
    sun.rotation_euler = Vector((0.85, 0.35, -1.0)).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(sun)
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    camera.data.type = "ORTHO"
    camera.data.sensor_fit = "HORIZONTAL"
    camera.data.clip_start, camera.data.clip_end = 0.1, 60
    scene.collection.objects.link(camera)
    scene.camera = camera
    stage = bpy.data.collections.new("Stage")
    scene.collection.children.link(stage)
    return camera, stage


def build(stage, layers):
    for spec in layers:
        before = set(stage.objects)
        spec["build"](stage, **spec["options"])
        new = [obj for obj in stage.objects if obj not in before]
        placed = kit.group(stage, "Layer", [obj for obj in new if obj.parent is None], at=spec["at"], rotate=(0, 0, spec["turn"]))
        placed.scale = (spec["scale"],) * 3
        if spec["holdout"]:
            for obj in new:
                if obj.type == "MESH":
                    for i in range(len(obj.data.materials)):
                        obj.data.materials[i] = kit.holdout()
    bpy.context.view_layer.update()


def aim(camera, direction, centre, width):
    """Points the camera along `direction` with `centre` in the middle of a picture `width` metres
    across."""
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera.location = centre - direction * 20
    camera.data.ortho_scale = width
    bpy.context.view_layer.update()


def render(path, width, height):
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = width, height
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# Tiles --------------------------------------------------------------------------------------------


def tile_camera(camera):
    direction = view_direction()
    up = direction.to_track_quat("-Z", "Y") @ Vector((0, 1, 0))
    # The picture's centre is 96 pixels above the floor centre.
    aim(camera, direction, up * ((TILE_H / 2 - 32) / PIXELS_PER_METRE), TILE_W / PIXELS_PER_METRE)


def depth_of(point):
    """The game's tile depth at a point of the tile: 1 at the north-west floor corner, falling a
    quarter per metre east or south and a half per storey up (TileGeometryUtils.getNormalizedDepth)."""
    east = point.x + 0.5
    south = 0.5 - point.y
    return 1 - (east + south) / 4 - point.z / STOREY / 2


def depth_map(camera, alpha):
    """Casts a ray through every pixel the sprite covers and returns that pixel's depth. Pixels
    the sprite only partly covers, at its edges, may miss: they take a neighbour's depth, because
    the game discards every sprite pixel whose depth pixel is empty (tileWithDepth.frag)."""
    scene = bpy.context.scene
    depsgraph = bpy.context.evaluated_depsgraph_get()
    direction = view_direction()
    rotation = direction.to_track_quat("-Z", "Y")
    right, up = rotation @ Vector((1, 0, 0)), rotation @ Vector((0, 1, 0))
    depth = np.full(alpha.shape, -1.0, dtype=np.float32)
    for y, x in zip(*np.nonzero(alpha > 0)):
        origin = (camera.location + right * ((x + 0.5 - TILE_W / 2) / PIXELS_PER_METRE)
                  + up * ((TILE_H / 2 - y - 0.5) / PIXELS_PER_METRE))
        hit, location, *_ = scene.ray_cast(depsgraph, origin, direction)
        if hit:
            depth[y, x] = depth_of(location)
    while True:
        missing = (alpha > 0) & (depth < 0)
        if not missing.any():
            break
        padded = np.pad(depth, 1, constant_values=-1)
        neighbours = np.stack([padded[1 + dy:1 + dy + depth.shape[0], 1 + dx:1 + dx + depth.shape[1]]
                               for dy in (-1, 0, 1) for dx in (-1, 0, 1)])
        best = neighbours.max(axis=0)
        fill = missing & (best >= 0)
        if not fill.any():
            break
        depth[fill] = best[fill]
    return depth


def render_tiles(camera, stage):
    os.makedirs(TILE_DIR, exist_ok=True)
    for stale in os.listdir(TILE_DIR):
        if stale.endswith(".png"):
            os.remove(os.path.join(TILE_DIR, stale))
    rows = max(tiles.TILES) // COLUMNS + 1
    atlas = np.zeros((rows * TILE_H, COLUMNS * TILE_W, 4), dtype=np.float32)
    tile_camera(camera)
    for index, layers in sorted(tiles.TILES.items()):
        kit.clear(stage)
        build(stage, layers)
        # Saved from the pixels: the render's own file carries the date and its timings.
        raw = os.path.join(SCRATCH, "tile.png")
        render(raw, TILE_W, TILE_H)
        pixels = kit.load_pixels(raw)
        kit.save_pixels(os.path.join(TILE_DIR, "%s_%d.png" % (TILESET, index)), pixels)
        depth = depth_map(camera, pixels[..., 3])
        cell = atlas[index // COLUMNS * TILE_H:(index // COLUMNS + 1) * TILE_H,
                     index % COLUMNS * TILE_W:(index % COLUMNS + 1) * TILE_W]
        covered = depth >= 0
        cell[covered, :3] = np.maximum(depth[covered], 1 / 255)[:, None]
        cell[covered, 3] = 1
        print("tile %d: %d layers, %d pixels" % (index, len(layers), int(covered.sum())))
    kit.save_pixels(DEPTH_FILE, atlas)


# Icons --------------------------------------------------------------------------------------------


def icon_camera(camera, stage, elevation, icon_size):
    direction = view_direction(elevation)
    rotation = direction.to_track_quat("-Z", "Y")
    right, up = rotation @ Vector((1, 0, 0)), rotation @ Vector((0, 1, 0))
    points = [obj.matrix_world @ v.co for obj in stage.objects if obj.type == "MESH" for v in obj.data.vertices]
    across = [p.dot(right) for p in points]
    along = [p.dot(up) for p in points]
    size = max(max(across) - min(across), max(along) - min(along))
    centre = right * (max(across) + min(across)) / 2 + up * (max(along) + min(along)) / 2
    aim(camera, direction, centre, size * icon_size / (icon_size - 3))


def pixel_icon(pixels, size):
    """Averages a large render down to `size` and draws the game's dark outline: vanilla icons
    are pixel art with a solid silhouette whose edge pixels are a dark shade of the object."""
    factor = pixels.shape[0] // size
    alpha = pixels[..., 3:4]
    blocks = (pixels[..., :3] * alpha).reshape(size, factor, size, factor, 3).mean(axis=(1, 3))
    coverage = alpha.reshape(size, factor, size, factor).mean(axis=(1, 3))
    colour = blocks / np.maximum(coverage, 1e-4)[..., None]
    # A little more contrast and saturation, as the hand-drawn icons have.
    grey = colour.mean(axis=2, keepdims=True)
    colour = np.clip(grey + (colour - grey) * 1.4, 0, 1)
    colour = np.clip((colour - 0.5) * 1.15 + 0.56, 0, 1)
    solid = coverage > 0.35
    padded = np.pad(solid, 1, constant_values=False)
    edge = solid & ~(padded[:-2, 1:-1] & padded[2:, 1:-1] & padded[1:-1, :-2] & padded[1:-1, 2:])
    colour[edge] = colour[edge] * 0.28
    out = np.zeros((size, size, 4), dtype=np.float32)
    out[..., :3] = colour
    out[..., 3] = solid
    return out


def render_icon(camera, stage, layers, elevation, size, path):
    kit.clear(stage)
    build(stage, layers)
    icon_camera(camera, stage, elevation, size)
    raw = os.path.join(SCRATCH, "icon.png")
    render(raw, size * ICON_OVERSAMPLE, size * ICON_OVERSAMPLE)
    kit.save_pixels(path, pixel_icon(kit.load_pixels(raw), size))


def render_icons(camera, stage):
    # Only this script's icons: an item or build icon that's gone leaves none behind.
    for stale in os.listdir(ICON_DIR):
        if stale.startswith(("Item_RenewableEnergy_", "RenewableEnergy_Build_")):
            os.remove(os.path.join(ICON_DIR, stale))
    for name, spec in items.ITEMS.items():
        render_icon(camera, stage, [tiles.layer(spec.get("icon", spec["model"]))], spec.get("icon_elevation", 30), ICON_SIZE,
                    os.path.join(ICON_DIR, "Item_RenewableEnergy_%s.png" % name))
        print("icon %s" % name)
    for name, layers in tiles.BUILD_ICONS.items():
        render_icon(camera, stage, layers, 30, BUILD_ICON_SIZE, os.path.join(ICON_DIR, "RenewableEnergy_Build_%s.png" % name))
        print("build icon %s" % name)


def main():
    jobs = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["tiles", "icons"]
    camera, stage = setup()
    os.makedirs(SCRATCH, exist_ok=True)
    if "tiles" in jobs:
        render_tiles(camera, stage)
    if "icons" in jobs:
        render_icons(camera, stage)


main()
