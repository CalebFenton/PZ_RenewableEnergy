"""Bakes and exports the ground model of every item in items.ITEMS and the body of every vehicle in
items.VEHICLES, and writes Models.txt.

    blender -b --factory-startup -P art/models/models.py

Each model's parts are merged into one mesh, unwrapped, and their materials baked into one texture
(colour, darkened by ambient occlusion so creases read without the renderer's light), because the
game draws a world item or a vehicle body with a single texture. An item's mesh goes to
models_X/WorldItems and its texture to textures/WorldItems, both RenewableEnergy_<Item>, and
Models.txt gets a model <Item>_Ground in module RenewableEnergy for the item's WorldStaticModel. A
vehicle's mesh goes to models_X/vehicles and its texture, with a mask texture, to
textures/Vehicles; scripts/RenewableEnergy/Vehicles.txt names them.

An item's exported mesh rests on y = 0 with y up, centred, in metres, transforms baked into the
vertices (like HearingAid's ground model): the game draws a dropped item that way.
"""
import os
import sys

import bmesh
import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import items  # noqa: E402

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
# Real size reads well on the ground next to the game's own items, which are drawn about life size.
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


def clear(stage):
    for obj in list(stage.objects):
        bpy.data.objects.remove(obj)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


# Thinner than this, a part is printed on the surface below it rather than modelled: labels,
# lettering, solar cells. Exported as faces of their own they would flicker against that surface,
# so they are baked into its texture instead.
DECAL_THICKNESS = 0.0025


def is_decal(obj):
    return min(obj.dimensions) <= DECAL_THICKNESS


def merge(objects, name, offset):
    """One mesh of `objects` in world space moved by `offset`, with one material slot per distinct
    material."""
    materials = []
    bm = bmesh.new()
    for obj in objects:
        mesh = obj.data.copy()
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


def save_texture(path, pixels):
    size = pixels.shape[0]
    image = bpy.data.images.new("texture", size, size, alpha=False)
    image.pixels[:] = np.clip(pixels, 0, 1).ravel()
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    return image


def export(obj, name, image, path):
    """Swaps the baked texture in as the only material and writes the FBX."""
    obj.data.materials.clear()
    mat = bpy.data.materials.new(PREFIX + name)
    if not mat.node_tree:
        mat.use_nodes = True
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    mat.node_tree.links.new(node.outputs["Color"], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    obj.data.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"}, bake_space_transform=True,
                             apply_scale_options="FBX_SCALE_ALL", add_leaf_bones=False, path_mode="STRIP",
                             mesh_smooth_type="FACE")


def build_baked(stage, builder, name, size, to_ground):
    """Builds one model's parts as a single mesh, unwrapped, and bakes its texture: colour
    darkened by ambient occlusion. `to_ground` centres it standing on the ground; otherwise it
    keeps the builder's origin. Returns the mesh object and the texture's pixels."""
    clear(stage)
    builder(stage)
    bpy.context.view_layer.update()
    parts = [obj for obj in stage.objects if obj.type == "MESH"]
    offset = ground_offset(parts) if to_ground else (0, 0, 0)
    low = merge([obj for obj in parts if not is_decal(obj)], name, offset)
    high = merge(parts, name + "_Detail", offset)
    stage.hide_render = True
    unwrap(low)
    colour = bake(low, "COLOR", size, "sRGB", source=high)
    high.hide_render = True
    occlusion = bake(low, "AO", size, "Non-Color")[..., :1]
    colour[..., :3] *= 0.55 + 0.45 * occlusion
    bpy.data.objects.remove(high)
    stage.hide_render = False
    return low, colour


def models_txt(names):
    lines = ["module RenewableEnergy", "{",
             "    /* Written by art/models/models.py: the ground models of the items' WorldStaticModel. */"]
    for name in names:
        lines += ["    model %s_Ground" % name, "    {",
                  "        mesh = WorldItems/%s%s," % (PREFIX, name),
                  "        texture = WorldItems/%s%s," % (PREFIX, name),
                  "        scale = %g," % WORLD_SCALE,
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


def main():
    stage = setup()
    clear_stale((MESH_DIR, TEXTURE_DIR, VEHICLE_MESH_DIR, VEHICLE_TEXTURE_DIR))
    for name, spec in items.ITEMS.items():
        size = TEXTURE_SIZE.get(name, DEFAULT_TEXTURE_SIZE)
        low, colour = build_baked(stage, spec["model"], name, size, to_ground=True)
        image = save_texture(os.path.join(TEXTURE_DIR, PREFIX + name + ".png"), colour)
        export(low, name, image, os.path.join(MESH_DIR, PREFIX + name + ".fbx"))
        print("model %s: %d faces, %d px texture" % (name, len(low.data.polygons), size))
        bpy.data.objects.remove(low)
    models_txt(items.ITEMS)
    for name, builder in items.VEHICLES.items():
        low, colour = build_baked(stage, builder, name, VEHICLE_TEXTURE_SIZE, to_ground=False)
        image = save_texture(os.path.join(VEHICLE_TEXTURE_DIR, PREFIX + name + ".png"), colour)
        # White matches none of the vehicle shader's mask colours (vehicle_common.frag.h), so no
        # part of the body is tinted as paint, a light, a window or a missing part.
        save_texture(os.path.join(VEHICLE_TEXTURE_DIR, PREFIX + name + "_Mask.png"), np.ones((8, 8, 4), dtype=np.float32))
        # Exported like the ground models: the game reads a mesh's vertices with Y up and -Z
        # forward (it flips Z, to left-handed coordinates), so the body's +Y, the hitch, leads.
        export(low, name, image, os.path.join(VEHICLE_MESH_DIR, PREFIX + name + ".fbx"))
        print("vehicle %s: %d faces" % (name, len(low.data.polygons)))
        bpy.data.objects.remove(low)


main()
