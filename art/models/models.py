"""Bakes and exports the ground model of every item in items.ITEMS and the body of every vehicle in
items.VEHICLES, and writes Models.txt.

    PYTHONHASHSEED=0 blender -b --factory-startup --python-use-system-env -P art/models/models.py

Each model's parts are merged into one mesh, unwrapped, and their materials baked into one texture
(colour, darkened by ambient occlusion so creases read without the renderer's light), because the
game draws a world item or a vehicle body with a single texture. An item's mesh goes to
models_X/WorldItems and its texture to textures/WorldItems, both RenewableEnergy_<Item>, and
Models.txt gets a model <Item>_Ground in module RenewableEnergy for the item's WorldStaticModel. A
vehicle's mesh goes to models_X/vehicles, cut into the body and the part models items.VEHICLES
names, a hinged one skinned to a bone with the clip that swings it, and its texture, with the mask,
lights, rust, damage and blood textures of its shader, to textures/Vehicles;
scripts/RenewableEnergy/Vehicles.txt names them.

An item's exported mesh rests on y = 0 with y up, centred, in metres, transforms baked into the
vertices (like HearingAid's ground model): the game draws a dropped item that way.

The FBX files come out the same, byte for byte, from the same parts (make.sh says why).
"""
import datetime
import functools
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from bpy_extras.io_utils import axis_conversion
from io_scene_fbx import export_fbx_bin
from mathutils import Quaternion, Vector

if sys.flags.hash_randomization:
    sys.exit("models.py: set PYTHONHASHSEED and pass --python-use-system-env, or every FBX object id changes")
# The exporter's own hook for the creation time; it takes the time of writing without one.
export_fbx_bin.fbx_header_elements = functools.partial(export_fbx_bin.fbx_header_elements,
                                                       time=datetime.datetime(2000, 1, 1))

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import items  # noqa: E402
import kit  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
MOD = os.path.join(REPO, "Contents/mods/RenewableEnergy")
MESH_DIR = os.path.join(MOD, "common/media/models_X/WorldItems")
TEXTURE_DIR = os.path.join(MOD, "common/media/textures/WorldItems")
VEHICLE_MESH_DIR = os.path.join(MOD, "common/media/models_X/vehicles")
VEHICLE_TEXTURE_DIR = os.path.join(MOD, "common/media/textures/Vehicles")
MODELS_TXT = os.path.join(MOD, "42/media/scripts/RenewableEnergy/Models.txt")
PREFIX = "RenewableEnergy_"
VEHICLE_TEXTURE_SIZE = 1024

# Big flat things need more texels for their cells than a battery does.
TEXTURE_SIZE = {name: 512 for name in ("SolarModule", "HomemadeSolarModule", "SolarFlat", "SolarWallWood", "SolarWallMetal",
                                       "SolarRackWood", "SolarRackMetal", "BatteryRackWood", "BatteryRackMetal",
                                       "BatteryBankWood", "BatteryBankMetal")}
DEFAULT_TEXTURE_SIZE = 256
# Real size reads well on the ground next to most of the game's own items; an item's
# "ground_scale" in items.ITEMS overrides it where the game draws its kind smaller (batteries).
WORLD_SCALE = 1.0


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 64
    world = bpy.data.worlds.new("Ambient")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
    world.light_settings.distance = 0.05
    scene.world = world
    stage = bpy.data.collections.new("Stage")
    scene.collection.children.link(stage)
    return stage


# Thinner than this, a part is printed on the surface below it rather than modelled: labels,
# lettering, solar cells. Exported as faces of their own they would flicker against that surface,
# so they are baked into its texture instead.
DECAL_THICKNESS = 0.0025


def is_decal(obj):
    return min(obj.dimensions) <= DECAL_THICKNESS


def merge(objects, name, offset):
    """One mesh of `objects` in world space moved by `offset`, with one material slot per distinct
    material. Each face's "part" attribute is the index in `objects` of the part it came from."""
    materials = []
    bm = bmesh.new()
    for index, obj in enumerate(objects):
        mesh = obj.data.copy()
        mesh.attributes.new("part", "INT", "FACE").data.foreach_set("value", [index] * len(mesh.polygons))
        mesh.transform(obj.matrix_world)
        if obj.matrix_world.determinant() < 0:
            mesh.flip_normals()
        remap = []
        for mat in mesh.materials:
            if mat not in materials:
                materials.append(mat)
            remap.append(materials.index(mat))
        for polygon in mesh.polygons:
            polygon.material_index = remap[polygon.material_index]
        bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
    bmesh.ops.translate(bm, vec=offset, verts=bm.verts)
    merged = bpy.data.meshes.new(name)
    bm.to_mesh(merged)
    bm.free()
    for mat in materials:
        merged.materials.append(mat)
    obj = bpy.data.objects.new(name, merged)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def ground_offset(objects):
    """Moves the parts to stand centred on the ground."""
    points = [obj.matrix_world @ v.co for obj in objects for v in obj.data.vertices]
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    return (-(low[0] + high[0]) / 2, -(low[1] + high[1]) / 2, -low[2])


def unwrap(obj):
    for uv in list(obj.data.uv_layers):
        obj.data.uv_layers.remove(uv)
    obj.data.uv_layers.new(name="UVMap")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.006)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake(obj, kind, size, colorspace, source=None):
    """Bakes every material of `obj` into one new image and returns its pixels. With `source`, the
    colour comes from the nearest surface of that more detailed copy, decals included."""
    image = bpy.data.images.new("bake_" + kind, size, size, alpha=False)
    image.colorspace_settings.name = colorspace
    added = []
    for mat in obj.data.materials:
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        mat.node_tree.nodes.active = node
        added.append((mat, node))
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if kind == "AO":
        bpy.ops.object.bake(type="AO", margin=4)
    else:
        source.select_set(True)
        bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=4, use_selected_to_active=True,
                            cage_extrusion=0.004, max_ray_distance=0.01)
    for mat, node in added:
        mat.node_tree.nodes.remove(node)
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(size, size, 4)
    bpy.data.images.remove(image)
    return pixels


def save_texture(path, pixels, alpha=False):
    size = pixels.shape[0]
    image = bpy.data.images.new("texture", size, size, alpha=alpha)
    image.pixels[:] = np.clip(pixels, 0, 1).ravel()
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def export(obj, name, path):
    """Swaps one material in for the parts' and writes the FBX, with the armature `rig` gave it, if
    any, and its clip. The material holds no texture: the game drops a model's materials
    (JAssImpImporter.takeOutTheTrash) and takes its texture from the model script, and the exporter
    would write the texture's absolute path, so each checkout would write different files."""
    obj.data.materials.clear()
    obj.data.materials.append(bpy.data.materials.new(PREFIX + name))
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    options = dict(filepath=path, use_selection=True, apply_scale_options="FBX_SCALE_ALL", add_leaf_bones=False,
                   mesh_smooth_type="FACE")
    if obj.parent is None:
        bpy.ops.export_scene.fbx(object_types={"MESH"}, bake_space_transform=True, **options)
        return
    # Baking the turn into the data breaks armatures; rig turned the data itself instead.
    obj.parent.select_set(True)
    bpy.ops.export_scene.fbx(object_types={"ARMATURE", "MESH"}, bake_space_transform=False, bake_anim=True,
                             bake_anim_use_all_actions=True, bake_anim_use_nla_strips=False,
                             bake_anim_force_startend_keying=True, bake_anim_simplify_factor=0.0, **options)


def build_baked(stage, builder, name, size, to_ground):
    """Builds one model's parts as a single mesh, unwrapped, and bakes its texture: colour
    darkened by ambient occlusion. `to_ground` centres it standing on the ground; otherwise it
    keeps the builder's origin. Returns the mesh object, the texture's pixels and the parts the
    mesh's "part" attribute indexes; the parts stay on `stage` until the next build."""
    kit.clear(stage)
    builder(stage)
    bpy.context.view_layer.update()
    parts = [obj for obj in stage.objects if obj.type == "MESH"]
    offset = ground_offset(parts) if to_ground else (0, 0, 0)
    solid = [obj for obj in parts if not is_decal(obj)]
    low = merge(solid, name, offset)
    high = merge(parts, name + "_Detail", offset)
    stage.hide_render = True
    unwrap(low)
    colour = bake(low, "COLOR", size, "sRGB", source=high)
    high.hide_render = True
    occlusion = bake(low, "AO", size, "Non-Color")[..., :1]
    colour[..., :3] *= 0.55 + 0.45 * occlusion
    bpy.data.objects.remove(high)
    stage.hide_render = False
    return low, colour, solid


def models_txt(specs):
    lines = ["module RenewableEnergy", "{",
             "    /* Written by art/models/models.py: the ground models of the items' WorldStaticModel. */"]
    for name, spec in specs.items():
        lines += ["    model %s_Ground" % name, "    {",
                  "        mesh = WorldItems/%s%s," % (PREFIX, name),
                  "        texture = WorldItems/%s%s," % (PREFIX, name),
                  "        scale = %g," % spec.get("ground_scale", WORLD_SCALE),
                  "    }"]
    lines.append("}")
    with open(MODELS_TXT, "w") as f:
        f.write("\n".join(lines) + "\n")


def clear_stale(folders):
    for folder in folders:
        os.makedirs(folder, exist_ok=True)
        for stale in os.listdir(folder):
            if stale.startswith(PREFIX):
                os.remove(os.path.join(folder, stale))


# Vehicle overlays -----------------------------------------------------------------------------------
#
# The vehicle shader vehicle_multiuv_noreflect finds a body's zones from the colour of its
# mask texture (UV1), and draws rust, damage and blood from textures it samples with UV2. The body
# carries UV2 as a copy of UV1, so every overlay is baked here in the skin's own UV space. Zones
# match within 0.01, so the mask holds flat colours. Its texels are filtered linearly, so the
# check in `mask_zones` refuses two neighbouring zones whose blend passes through a third.

# The multi-UV shaders' zone colours (vehicle_common.frag.h); the single-UV shaders swap the
# guards. Head takes Front blood, Tail and Boot Rear blood, the guards Left and Right blood. Head
# shows the EngineDoor part's damage (the frame's front), Tail and the guards TruckBed's (its
# back) and Boot TrunkDoor's (the battery box lid) (BaseVehicle.doDamageOverlay, doBloodOverlay*).
HEAD, TAIL, BOOT = (255, 0, 0), (0, 255, 0), (0, 255, 127)
GUARD_LEFT, GUARD_RIGHT = (0, 0, 191), (191, 191, 0)
STOPLIGHT_LEFT, STOPLIGHT_RIGHT = (127, 191, 0), (127, 64, 0)
# The rear windshield's zone, the lamp board's: lit from the lights texture while the vehicle's
# windowLightsOn is set, dented by the WindshieldRear part, bloodied from the rear.
LAMP_BOARD = (0, 127, 0)
# Matches no zone: no blood or damage, never dark when a part is missing.
CLEAN = (255, 255, 255)
ZONE_COLOURS = [(255, 0, 0), (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 0, 255), (0, 0, 255), (0, 127, 127),
                (127, 127, 0), (127, 0, 127), (0, 0, 127), (127, 0, 0), (0, 127, 0), (0, 191, 191), (191, 191, 0),
                (191, 0, 191), (0, 0, 191), (0, 0, 0), (64, 0, 0), (191, 0, 0), (0, 191, 0), (0, 64, 0), (127, 64, 0),
                (127, 191, 0), (191, 191, 191), (64, 64, 64), (255, 0, 127), (0, 255, 127)]
# Ahead of the hitch is +Y, and +X is the trailer's right in the game.
SIDE = "side"
FACING = "facing"
STOPLIGHT = "stoplight"

# Part name -> zone, or how to pick one per face; parts not listed stay CLEAN.
TRAILER_ZONES = {
    "Trailer_BatteryLid": BOOT, "Trailer_TailLight": STOPLIGHT,
    "Trailer_Tongue": HEAD, "Trailer_Coupler": HEAD, "Trailer_CouplerCap": HEAD, "Trailer_Jack": HEAD,
    "Trailer_JackFoot": HEAD, "Trailer_JackCrank": HEAD, "Trailer_BatteryBox": HEAD, "Trailer_BatteryHinge": HEAD,
    "Trailer_Hasp": HEAD, "Trailer_Staple": HEAD, "Trailer_Padlock": HEAD, "Trailer_PadlockShackle": HEAD,
    "Trailer_Rail": SIDE, "Trailer_Spring": SIDE, "Trailer_Fender": SIDE, "Trailer_FenderSkirt": SIDE,
    "Trailer_Reflector": SIDE,
    "Trailer_Mast": TAIL, "Trailer_MastPivot": TAIL, "Trailer_Cradle": TAIL,
    "Board_Back": LAMP_BOARD, "Board_FrameLong": LAMP_BOARD, "Board_FrameShort": LAMP_BOARD,
    "Board_Lamp": LAMP_BOARD, "Board_Visor": LAMP_BOARD,
    "Trailer_Deck": FACING, "Trailer_CrossMember": FACING,
}
# Parts drawn lit from the lights texture when their zone is lit, in that colour: the arrow's
# lamps, a bright amber against their dark lenses. The tail lights glow by their zone (STOPLIGHT).
GLOWING = {"Board_Lamp": (1.0, 0.86, 0.38)}
# Rust stays off glass, lamps and the board's face. Module parts are named after their module.
RUST_FREE = ("Board_Back", "Board_Lamp", "Board_Visor", "Trailer_TailLight", "Trailer_Reflector", "Trailer_Panel",
             "Trailer0_", "Trailer1_", "TrailerCracked")
# Printed on the battery box: kept clean of blood and rust so it stays legible.
TRAILER_STENCIL = "Trailer_Stencil"
MASK_SIZE = 1024
OVERLAY_SIZE = 512


def part_name(obj):
    return obj.name.split(".")[0]


def face_zone(part, centre, normal):
    zone = TRAILER_ZONES.get(part, CLEAN)
    side = (GUARD_RIGHT, STOPLIGHT_RIGHT) if centre[0] > 0 else (GUARD_LEFT, STOPLIGHT_LEFT)
    if zone == SIDE:
        return side[0]
    if zone == STOPLIGHT:
        return side[1]
    if zone == FACING:
        if abs(normal[0]) > 0.7:
            return side[0]
        if abs(normal[1]) > 0.7:
            return HEAD if normal[1] > 0 else TAIL
        return CLEAN
    return zone


def rasterize(obj, size):
    """For each texel of a `size` texture in UV1, the polygon drawn there (-1 where none is) and
    the surface point, from the triangles whose UV covers the texel's centre."""
    mesh = obj.data
    mesh.calc_loop_triangles()
    count = len(mesh.loop_triangles)
    loops = np.zeros(count * 3, dtype=np.int64)
    verts = np.zeros(count * 3, dtype=np.int64)
    polygons = np.zeros(count, dtype=np.int64)
    mesh.loop_triangles.foreach_get("loops", loops)
    mesh.loop_triangles.foreach_get("vertices", verts)
    mesh.loop_triangles.foreach_get("polygon_index", polygons)
    uv = np.zeros(len(mesh.loops) * 2)
    mesh.uv_layers[0].data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)[loops].reshape(count, 3, 2) * size
    co = np.zeros(len(mesh.vertices) * 3)
    mesh.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)[verts].reshape(count, 3, 3)
    face = np.full((size, size), -1, dtype=np.int64)
    point = np.zeros((size, size, 3))
    for t in range(count):
        (ax, ay), (bx, by), (cx, cy) = uv[t]
        area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
        if abs(area) < 1e-12:
            continue
        x0, x1 = max(int(min(ax, bx, cx)), 0), min(int(max(ax, bx, cx)) + 1, size)
        y0, y1 = max(int(min(ay, by, cy)), 0), min(int(max(ay, by, cy)) + 1, size)
        px, py = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        wb = ((px - ax) * (cy - ay) - (cx - ax) * (py - ay)) / area
        wc = ((bx - ax) * (py - ay) - (px - ax) * (by - ay)) / area
        wa = 1 - wb - wc
        inside = (wa >= -1e-6) & (wb >= -1e-6) & (wc >= -1e-6)
        if not inside.any():
            continue
        rows, cols = py[inside].astype(int), px[inside].astype(int)
        face[rows, cols] = polygons[t]
        weights = np.stack((wa[inside], wb[inside], wc[inside]), axis=1)
        point[rows, cols] = weights @ co[t]
    return face, point


def pad(face, steps):
    """Indexes, per texel, the covered texel whose values it takes: itself, or for `steps` texels
    around each island the nearest covered one, so filtering at island edges reads the island."""
    size = face.shape[0]
    source = np.where(face >= 0, np.arange(size * size).reshape(size, size), -1)
    for _ in range(steps):
        grown = source.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            near = np.roll(source, (dy, dx), (0, 1))
            take = (grown < 0) & (near >= 0)
            grown[take] = near[take]
        source = grown
    return source


def depth_in_island(face, steps):
    """0 on an island's edge texels, rising to 1 `steps` texels in."""
    inside = face >= 0
    depth = np.zeros(face.shape)
    for _ in range(steps):
        inside = inside & np.roll(inside, 1, 0) & np.roll(inside, -1, 0) & np.roll(inside, 1, 1) & np.roll(inside, -1, 1)
        depth += inside
    return depth / steps


def noise(point, scale, seed):
    """Smooth value noise in 0..1 at `point` (metres), `scale` cells per metre on each axis."""
    p = point * np.asarray(scale, dtype=float)
    cell = np.floor(p).astype(np.int64)
    f = p - cell
    f = f * f * (3 - 2 * f)
    total = 0.0
    for corner in np.ndindex(2, 2, 2):
        c = cell + corner
        h = (c[..., 0] * 73856093) ^ (c[..., 1] * 19349663) ^ (c[..., 2] * 83492791) ^ (seed * 2654435761)
        h = (h ^ (h >> 13)) * 1274126177
        value = ((h ^ (h >> 16)) & 0xFFFF) / 65535.0
        weight = np.prod(np.where(corner, f, 1 - f), axis=-1)
        total = total + weight * value
    return total


def fractal(point, scale, seed, octaves=4):
    total, amplitude, norm = 0.0, 1.0, 0.0
    for octave in range(octaves):
        total = total + amplitude * noise(point, np.asarray(scale) * 2 ** octave, seed + octave)
        norm += amplitude
        amplitude *= 0.5
    return total / norm


def smoothstep(low, high, x):
    t = np.clip((x - low) / (high - low), 0, 1)
    return t * t * (3 - 2 * t)


def surface(low, solid, size):
    """Per texel of a `size` texture: zone colour (0..1), surface point, normal, whether rust may
    show, how deep into its island it lies, whether it is covered and the colour it glows (GLOWING,
    alpha 0 where it doesn't). Covers the islands padded a few texels."""
    face, point = rasterize(low, size)
    depth = depth_in_island(face, 4)
    source = pad(face, max(2, size // 256)).ravel()
    covered = source >= 0
    polygons = low.data.polygons
    parts = np.zeros(len(polygons), dtype=np.int64)
    low.data.attributes["part"].data.foreach_get("value", parts)
    normals = np.zeros(len(polygons) * 3)
    polygons.foreach_get("normal", normals)
    normals = normals.reshape(-1, 3)
    centres = np.zeros(len(polygons) * 3)
    polygons.foreach_get("center", centres)
    centres = centres.reshape(-1, 3)
    names = [part_name(obj) for obj in solid]
    zones = np.array([face_zone(names[parts[i]], centres[i], normals[i]) for i in range(len(polygons))]) / 255.0
    rusts = np.array([not names[parts[i]].startswith(RUST_FREE) for i in range(len(polygons))])
    glows = np.array([GLOWING[names[parts[i]]] + (1.0,) if names[parts[i]] in GLOWING else (0.0, 0.0, 0.0, 0.0)
                      for i in range(len(polygons))])
    flat_face = face.ravel()[np.where(covered, source, 0)]
    zone = np.where(covered[:, None], zones[flat_face], 1.0)
    rust = covered & rusts[flat_face]
    normal = np.where(covered[:, None], normals[flat_face], 0.0)
    glow = np.where(covered[:, None], glows[flat_face], 0.0)
    point = np.where(covered[:, None], point.reshape(-1, 3)[np.where(covered, source, 0)], 0.0)
    depth = depth.ravel()[np.where(covered, source, 0)]
    stencil = [obj for obj in bpy.data.objects if part_name(obj) == TRAILER_STENCIL]
    for obj in stencil:
        corners = np.array([obj.matrix_world @ Vector(c) for c in obj.bound_box])
        margin = 0.015
        inside = np.all((point >= corners.min(0) - margin) & (point <= corners.max(0) + margin), axis=1)
        zone[inside] = np.array(CLEAN) / 255.0
        rust &= ~inside
    shape = (size, size)
    return (zone.reshape(*shape, 3), point.reshape(*shape, 3), normal.reshape(*shape, 3), rust.reshape(shape),
            depth.reshape(shape), covered.reshape(shape), glow.reshape(*shape, 4))


def check_mask(mask):
    """Fails if linear filtering between two neighbouring texels would pass through a third zone."""
    colours = np.round(mask.reshape(-1, mask.shape[-1])[:, :3] * 255).astype(int)
    grid = colours.reshape(mask.shape[0], mask.shape[1], 3)
    pairs = set()
    for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
        other = np.roll(grid, (dy, dx), (0, 1))
        differ = np.any(grid != other, axis=-1)
        for a, b in zip(grid[differ], other[differ]):
            pairs.add((tuple(a), tuple(b)))
    zones = np.array(ZONE_COLOURS) / 255.0
    for a, b in pairs:
        a, b = np.array(a) / 255.0, np.array(b) / 255.0
        for t in np.linspace(0.02, 0.98, 49):
            blend = a + (b - a) * t
            near = np.linalg.norm(zones - blend, axis=1) < 0.012
            far = (np.linalg.norm(zones - a, axis=1) > 0.012) & (np.linalg.norm(zones - b, axis=1) > 0.012)
            if np.any(near & far):
                raise RuntimeError("mask colours %s and %s blend into another zone" % (a * 255, b * 255))


def vehicle_overlays(low, solid):
    """The mask, lights, rust, damage shells and blood textures of a vehicle body, by file suffix."""
    zone, point, normal, rust_ok, depth, covered, glow = surface(low, solid, MASK_SIZE)
    mask = np.concatenate((zone, np.ones(zone.shape[:2] + (1,))), axis=-1)
    check_mask(mask)
    stop = np.isin(np.round(zone * 255).astype(int) @ np.array([65536, 256, 1]),
                   [(r << 16) | (g << 8) | b for r, g, b in (STOPLIGHT_LEFT, STOPLIGHT_RIGHT)])
    # Drawn over the lit lamps after the scene's lighting, so they glow at night too: the tail
    # lights by their zone, the arrow's lamps by their part.
    lights = glow.copy()
    lights[stop] = (1.0, 0.08, 0.03, 1.0)

    zone, point, normal, rust_ok, depth, covered, _ = surface(low, solid, OVERLAY_SIZE)
    shape = zone.shape[:2]
    z = point[..., 2]
    low_down = 1 - smoothstep(-0.35, 0.55, z)
    # Bevels and island borders are the edges where paint chips first.
    edge = np.maximum(1 - np.max(np.abs(normal), axis=-1) ** 4, 1 - depth)

    patches = fractal(point, (9, 9, 9), 11)
    grain = noise(point, (90, 90, 90), 12)
    # Water runs off and dirt builds up below, so tops rust least.
    amount = patches + 0.3 * low_down + 0.3 * edge - 0.7 - 0.15 * smoothstep(0.7, 0.95, normal[..., 2])
    rust = np.zeros(shape + (4,))
    rust[..., 0] = 0.36 + 0.16 * grain
    rust[..., 1] = 0.17 + 0.07 * grain
    rust[..., 2] = 0.07 + 0.03 * grain
    rust[..., 3] = smoothstep(0.0, 0.18, amount + 0.15 * (grain - 0.5)) * rust_ok

    # Damage shells in grey: the vehicle's forced colour (Vehicles.txt) has the shader draw a shell's
    # own saturation and value, under the paint's hue, outside Head, Tail and the lamps, which draw
    # its colour as is (vehicle_common.frag addDamage), so grey stays grey on every zone. Scratches
    # and dents scrape the paint to bare steel, and a dark crease rings each dent.
    lines = np.maximum(1 - np.abs(2 * noise(point, (5, 5, 60), 21) - 1),
                       1 - np.abs(2 * noise(point, (60, 6, 6), 22) - 1))
    scratches = smoothstep(0.9, 0.97, lines) * smoothstep(0.35, 0.6, fractal(point, (6, 6, 6), 23, 3))
    damage1 = np.zeros(shape + (4,))
    damage1[..., :3] = 0.7
    damage1[..., 3] = scratches
    dents = fractal(point, (8, 8, 8), 31)
    bare = smoothstep(0.6, 0.66, dents)
    crease = smoothstep(0.56, 0.59, dents) * (1 - smoothstep(0.6, 0.63, dents))
    steel = (0.5 + 0.15 * grain)[..., None]
    damage2 = np.zeros(shape + (4,))
    damage2[..., :3] = np.where(crease[..., None] > bare[..., None], 0.08, steel)
    damage2[..., :3] = np.where(scratches[..., None] > np.maximum(bare, crease)[..., None], 0.85, damage2[..., :3])
    damage2[..., 3] = np.clip(np.maximum.reduce((bare * 0.9, crease, scratches)), 0, 1)

    # Blood: the shader shows a texel once growth × splatter, each alpha cubed first, passes 1 minus
    # the side's intensity (vehicle_common.frag addBlood). Smears are stretched upright into runs.
    smears = smoothstep(0.58, 0.68, fractal(point, (10, 10, 3), 41) + 0.2 * low_down)
    drops = smoothstep(0.8, 0.88, noise(point, (70, 70, 40), 44)) * smoothstep(0.4, 0.6, fractal(point, (5, 5, 5), 45, 2))
    shade = noise(point, (40, 40, 40), 42)
    blood = np.zeros(shape + (4,))
    blood[..., 0] = 0.30 + 0.12 * shade
    blood[..., 1] = 0.015
    blood[..., 2] = 0.02
    blood[..., 3] = np.maximum(smears, drops)
    growth = np.zeros(shape + (4,))
    growth[..., :3] = 1.0
    growth[..., 3] = np.clip(0.25 + 0.6 * low_down + 0.5 * (fractal(point, (4, 4, 4), 43, 3) - 0.5), 0, 1)

    covered = covered[..., None]
    return {"_Mask": (mask, False), "_Lights": (lights, True), "_Rust": (rust * covered, True),
            "_Damage1": (damage1 * covered, True), "_Damage2": (damage2 * covered, True),
            "_Blood": (blood * covered, True), "_BloodMask": (growth * covered, True)}


def main():
    stage = setup()
    clear_stale((MESH_DIR, TEXTURE_DIR, VEHICLE_MESH_DIR, VEHICLE_TEXTURE_DIR))
    for name, spec in items.ITEMS.items():
        size = TEXTURE_SIZE.get(name, DEFAULT_TEXTURE_SIZE)
        low, colour, _ = build_baked(stage, spec["model"], name, size, to_ground=True)
        save_texture(os.path.join(TEXTURE_DIR, PREFIX + name + ".png"), colour)
        export(low, name, os.path.join(MESH_DIR, PREFIX + name + ".fbx"))
        print("model %s: %d faces, %d px texture" % (name, len(low.data.polygons), size))
        bpy.data.objects.remove(low)
    models_txt(items.ITEMS)
    build_vehicles(stage)


def cut_piece(low, solid, prefixes, offset, keep):
    """A copy of the baked mesh `low` holding only the faces of parts named with one of
    `prefixes` (`keep`), or only the others, moved back by `offset`. It keeps the shared UVs."""
    names = [part_name(obj) for obj in solid]
    parts = np.zeros(len(low.data.polygons), dtype=np.int64)
    low.data.attributes["part"].data.foreach_get("value", parts)
    piece = low.copy()
    piece.data = low.data.copy()
    bpy.context.scene.collection.objects.link(piece)
    bm = bmesh.new()
    bm.from_mesh(piece.data)
    bm.faces.ensure_lookup_table()
    drop = [face for face in bm.faces if names[parts[face.index]].startswith(prefixes) != keep]
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    bmesh.ops.translate(bm, vec=-Vector(offset), verts=bm.verts)
    bm.to_mesh(piece.data)
    bm.free()
    return piece


# A hinged piece is skinned whole to one bone on its hinge. A part model that isn't static gets an
# animation player of its own (BaseVehicle.ModelInfo), and playPartAnim plays the clip its part's
# anim block names. The armature takes the name of vanilla's vehicle skeletons, VehicleSkeleton,
# where the game looks for the bones (ImportedSkeleton). The game moves the bones by the clip, the
# armature's own key included, and then draws the mesh through the mesh's own transform as well,
# so in the file the armature and the mesh must stand without a transform, or the game turns the
# mesh twice. The export turns the armature into the game's axes, so the armature starts turned
# back by as much, and the piece's data is turned instead, as the static pieces' export turns
# theirs; shut, it draws where a static one would. Vanilla's door and trunk clips run half a
# second at 30 frames a second, which the anim block's rate scales.
HINGE_FPS = 30
HINGE_FRAMES = 15
# From Blender's axes to the game's: what the FBX export's default axes do.
GAME_AXES = axis_conversion(to_forward="-Z", to_up="Y").to_4x4()


def rig(piece, hinge, bone_name):
    """Gives `piece` an armature with one bone on `hinge` (an items.VEHICLES "hinged" entry) and the
    clip that swings it from open to shut, both turned for the game's axes."""
    scene = bpy.context.scene
    scene.render.fps = HINGE_FPS
    scene.frame_start, scene.frame_end = 1, 1 + HINGE_FRAMES
    piece.data.transform(GAME_AXES)
    armature = bpy.data.objects.new("VehicleSkeleton", bpy.data.armatures.new("VehicleSkeleton"))
    armature.matrix_world = GAME_AXES.inverted()
    scene.collection.objects.link(armature)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")
    bone = armature.data.edit_bones.new(bone_name)
    pivot = GAME_AXES @ Vector(hinge["pivot"])
    axis = (GAME_AXES.to_3x3() @ Vector(hinge["axis"])).normalized()
    # A bone's own Y runs from its head to its tail, so along the hinge.
    bone.head, bone.tail = pivot, pivot + axis * 0.1
    bpy.ops.object.mode_set(mode="OBJECT")
    piece.parent = armature
    piece.vertex_groups.new(name=bone_name).add(range(len(piece.data.vertices)), 1.0, "REPLACE")
    piece.modifiers.new("Armature", "ARMATURE").object = armature
    pose = armature.pose.bones[bone_name]
    pose.rotation_mode = "QUATERNION"
    armature.animation_data_create().action = bpy.data.actions.new(hinge["clip"])
    for frame, degrees in ((1, hinge["open"]), (1 + HINGE_FRAMES, 0)):
        pose.rotation_quaternion = Quaternion((0, 1, 0), math.radians(degrees))
        pose.keyframe_insert("rotation_quaternion", frame=frame)
    # The FBX writes each bone as it stands on the current frame; shut, it matches the bind.
    scene.frame_set(1 + HINGE_FRAMES)
    return armature


def build_vehicles(stage):
    for name, spec in items.VEHICLES.items():
        low, colour, solid = build_baked(stage, spec["build"], name, VEHICLE_TEXTURE_SIZE, to_ground=False)
        save_texture(os.path.join(VEHICLE_TEXTURE_DIR, PREFIX + name + ".png"), colour)
        for suffix, (pixels, alpha) in vehicle_overlays(low, solid).items():
            save_texture(os.path.join(VEHICLE_TEXTURE_DIR, PREFIX + name + suffix + ".png"), pixels, alpha)
        # The multi-UV shader reads rust, damage and blood through UV2; new() copies the active UV1.
        low.data.uv_layers.new(name="UVMap2")
        taken = tuple(prefix for prefixes, _ in spec["pieces"].values() for prefix in prefixes)
        pieces = {"": cut_piece(low, solid, taken, (0, 0, 0), keep=False)}
        for suffix, (prefixes, offset) in spec["pieces"].items():
            pieces[suffix] = cut_piece(low, solid, prefixes, offset, keep=True)
        bpy.data.objects.remove(low)
        for suffix, hinge in spec.get("hinged", {}).items():
            rig(pieces[suffix], hinge, suffix.strip("_") + "_bone")
        for suffix, piece in pieces.items():
            # Exported like the ground models: the game reads a mesh's vertices with Y up and -Z
            # forward (it flips Z, to left-handed coordinates), so the body's +Y, the hitch, leads.
            export(piece, name + suffix, os.path.join(VEHICLE_MESH_DIR, PREFIX + name + suffix + ".fbx"))
            print("vehicle %s%s: %d faces" % (name, suffix, len(piece.data.polygons)))
            armature = piece.parent
            bpy.data.objects.remove(piece)
            if armature:
                bpy.data.objects.remove(armature)


main()
