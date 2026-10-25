"""Bakes and exports the ground model of every item in items.ITEMS and items.GROUND_MODELS, the
model of every sprite model in wind.SPRITE_MODELS and the body of every vehicle in
trailer.VEHICLES, and writes Models.txt and SpriteModels.txt.

    PYTHONHASHSEED=0 blender -b --factory-startup --python-use-system-env -P art/models/models.py

Each model's parts are merged into one mesh, unwrapped, and their materials baked into one texture
(colour, darkened by ambient occlusion so creases read without the renderer's light; a world item's
gets the light painted in as well, `paint_light` says why), because the game draws a world item or
a vehicle body with a single texture. An item's mesh goes to
models_X/WorldItems and its texture to textures/WorldItems, both RenewableEnergy_<Item>, and
Models.txt gets a model <Item>_Ground in module RenewableEnergy for the item's WorldStaticModel. A
vehicle's mesh goes to models_X/vehicles, cut into the body and the part models trailer.VEHICLES
names, a hinged one skinned to a bone with the clip that swings it, and its texture, with the mask,
lights, rust, damage and blood textures of its shader, to textures/Vehicles;
scripts/RenewableEnergy/Vehicles.txt names them. A sprite model's meshes, one per rotor spin step,
and textures, one per skin, go where an item's do, Models.txt gets a model per mesh, and
SpriteModels.txt a spriteModel per skin, yaw and step, which the game draws a placed object as in
place of its tile (build_sprite_model).

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
from io_scene_fbx import export_fbx_bin
from mathutils import Matrix, Vector

if sys.flags.hash_randomization:
    sys.exit("models.py: set PYTHONHASHSEED and pass --python-use-system-env, or every FBX object id changes")
# The exporter's own hook for the creation time; it takes the time of writing without one.
export_fbx_bin.fbx_header_elements = functools.partial(export_fbx_bin.fbx_header_elements,
                                                       time=datetime.datetime(2000, 1, 1))

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import items  # noqa: E402
import kit  # noqa: E402
import trailer  # noqa: E402
import vehicles  # noqa: E402
import wind  # noqa: E402

MESH_DIR = os.path.join(kit.MEDIA, "models_X/WorldItems")
TEXTURE_DIR = os.path.join(kit.MEDIA, "textures/WorldItems")
VEHICLE_MESH_DIR = os.path.join(kit.MEDIA, "models_X/vehicles")
VEHICLE_TEXTURE_DIR = os.path.join(kit.MEDIA, "textures/Vehicles")
MODELS_TXT = os.path.join(kit.MOD, "42/media/scripts/RenewableEnergy/Models.txt")
PREFIX = "RenewableEnergy_"
VEHICLE_TEXTURE_SIZE = 1024

# Big flat things need more texels for their cells than a battery does, and a drum's side is as big;
# the jar battery's six jars and their lids share one texture with its tray.
TEXTURE_SIZE = {name: 512 for name in ("SolarModule", "HomemadeSolarModule", "SolarFlat", "SolarWallWood", "SolarWallMetal",
                                       "SolarRackWood", "SolarRackMetal", "BatteryRackWood", "BatteryRackMetal",
                                       "BatteryBankWood", "BatteryBankMetal", "JarBattery", *items.GROUND_MODELS)}
DEFAULT_TEXTURE_SIZE = 256
# The game draws a dropped item through the same camera as a sprite model, which scales everything
# by 1.5 (ItemModelRenderer$WorldModelCamera.Begin, Core.DoPushIsoStuff with vehicle false), so a
# ground model's scale undoes it and a mesh in metres lies at its real size, as big as the tile it
# is installed as. An item's "ground_scale" in items.ITEMS overrides it where the game draws its
# kind at another size (batteries).
GROUND_SCALE = 1 / 1.5
# A sprite model's translate is in squares and its scale undoes the 1.5 the game's model camera
# scales everything by (IsoObjectModelDrawer.renderMain, WorldModelCamera.Begin), as vanilla's
# doors' 0.6667 does, so a mesh in metres stands at its real size. Its meshes' own model scripts
# keep 1, or they would shrink twice.
SPRITE_MODEL_SCALE = 1 / 1.5
SPRITE_MESH_SCALE = 1.0
# A sprite model stands taller than a person, so it needs the texels of the big flat things.
SPRITE_MODEL_TEXTURE_SIZE = 512
SPRITE_MODELS_TXT = os.path.join(kit.MOD, "42/media/scripts/RenewableEnergy/SpriteModels.txt")


def setup():
    stage = kit.new_stage(64, (1, 1, 1, 1))
    bpy.context.scene.world.light_settings.distance = 0.05
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


def _select(obj):
    """Makes `obj` the only selected object and the active one, as the operators below act on."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def unwrap(obj):
    for uv in list(obj.data.uv_layers):
        obj.data.uv_layers.remove(uv)
    obj.data.uv_layers.new(name="UVMap")
    _select(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.006)
    bpy.ops.object.mode_set(mode="OBJECT")


# A bake takes each texel's colour from one point at its centre, so a line thinner than a texel,
# like the gap between two solar cells, shows or vanishes by where it happens to fall. The colour
# is baked this many times finer each way and averaged down, so every such line shows alike.
SUPERSAMPLE = 4


def bake(obj, kind, size, colorspace, source=None):
    """Bakes every material of `obj` into one new image and returns its pixels. With `source`, the
    colour comes from the nearest surface of that more detailed copy, decals included, as paint:
    a metal's diffuse colour is its base colour less its metallic share, nearly black for bare
    metal, and the game has no reflections to give the rest back."""
    fine = size * SUPERSAMPLE if source else size
    image = bpy.data.images.new("bake_" + kind, fine, fine, alpha=False)
    image.colorspace_settings.name = colorspace
    added = []
    for mat in obj.data.materials:
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        mat.node_tree.nodes.active = node
        added.append((mat, node))
    _select(obj)
    if kind == "AO":
        bpy.ops.object.bake(type="AO", margin=4)
    else:
        metallic = [mat.node_tree.nodes["Principled BSDF"].inputs["Metallic"] for mat in source.data.materials
                    if "Principled BSDF" in mat.node_tree.nodes]
        kept = [socket.default_value for socket in metallic]
        for socket in metallic:
            socket.default_value = 0.0
        # A colour has no noise to average out: one sample a fine texel is enough.
        samples = bpy.context.scene.cycles.samples
        bpy.context.scene.cycles.samples = 1
        source.select_set(True)
        bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=4 * SUPERSAMPLE, use_selected_to_active=True,
                            cage_extrusion=0.004, max_ray_distance=0.01)
        bpy.context.scene.cycles.samples = samples
        for socket, value in zip(metallic, kept):
            socket.default_value = value
    for mat, node in added:
        mat.node_tree.nodes.remove(node)
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(fine, fine, 4)
    bpy.data.images.remove(image)
    step = fine // size
    return pixels.reshape(size, step, size, step, 4).mean(axis=(1, 3))


def bake_emit(obj, size, shader):
    """Bakes what `shader(nodes, links)` returns, a vector socket, into a float image over every face
    of `obj`, and returns its pixels: supersampled like the colour, so thin parts such as fins catch
    the light alike, the scene's samples shared among the fine texels."""
    fine = size * SUPERSAMPLE
    image = bpy.data.images.new("bake_emit", fine, fine, alpha=False, float_buffer=True)
    image.colorspace_settings.name = "Non-Color"
    mat = bpy.data.materials.new("BakeEmit")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    emission = nodes.new("ShaderNodeEmission")
    links.new(shader(nodes, links), emission.inputs["Color"])
    links.new(emission.outputs[0], nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
    target = nodes.new("ShaderNodeTexImage")
    target.image = image
    nodes.active = target
    kept = list(obj.data.materials)
    for i in range(len(kept)):
        obj.data.materials[i] = mat
    _select(obj)
    samples = bpy.context.scene.cycles.samples
    bpy.context.scene.cycles.samples = max(1, samples // SUPERSAMPLE ** 2)
    bpy.ops.object.bake(type="EMIT", margin=4 * SUPERSAMPLE)
    bpy.context.scene.cycles.samples = samples
    for i, original in enumerate(kept):
        obj.data.materials[i] = original
    bpy.data.materials.remove(mat)
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(fine, fine, 4)[..., :3]
    bpy.data.images.remove(image)
    return pixels.reshape(size, SUPERSAMPLE, size, SUPERSAMPLE, 3).mean(axis=(1, 3))


def baked_normal(obj, size, bevel=None):
    """Each texel's normal, rounded over `bevel` metres at the edges if given."""
    def shader(nodes, links):
        if bevel:
            source = nodes.new("ShaderNodeBevel")
            source.inputs["Radius"].default_value = bevel
            source.samples = 16
            normal = source.outputs["Normal"]
        else:
            normal = nodes.new("ShaderNodeNewGeometry").outputs["Normal"]
        encode = nodes.new("ShaderNodeVectorMath")
        encode.operation = "MULTIPLY_ADD"
        encode.inputs[1].default_value = (0.5, 0.5, 0.5)
        encode.inputs[2].default_value = (0.5, 0.5, 0.5)
        links.new(normal, encode.inputs[0])
        return encode.outputs[0]
    normal = bake_emit(obj, size, shader) * 2 - 1
    return normal / np.maximum(np.linalg.norm(normal, axis=-1, keepdims=True), 1e-6)


# The game lights a world item evenly, so faces of one colour draw as one flat patch and the
# item's shape is lost. Like a hand-painted game texture, the bake paints the light in, as the
# tiles are lit (render.py: from the west, a little south): tops lightest, the south side a shade
# darker, the east side darker again, every edge rounded off so it catches a highlight, and each
# side darkening towards the ground. Faces seen head-on keep about their own colour, since the game
# crushes dark ones towards black.
SKY, SKY_TILT = 0.85, 0.15  # sky light on a side face, and how much more (less) facing up (down)
SUN, SUN_TOWARD = 0.45, Vector((-0.85, -0.35, 1.0)).normalized()
EDGE_RADIUS, EDGE_GLINT = 0.008, 0.6
GROUND_SHADE = 0.2  # how much darker the foot of the item than its top


def paint_light(obj, size, occlusion):
    """The light painted onto each texel of the world item `obj`, given its ambient occlusion."""
    flat = baked_normal(obj, size)
    rounded = baked_normal(obj, size, EDGE_RADIUS)
    height = bake_emit(obj, size, lambda nodes, links: nodes.new("ShaderNodeNewGeometry").outputs["Position"])[..., 2:3]
    up = rounded[..., 2:3]
    sun = np.maximum(rounded @ np.array(SUN_TOWARD, dtype=np.float32), 0)[..., None]
    # How far the rounding turns the normal, 1 on the edge itself; only where the edge stands out
    # into the open, not in the crease of an inside corner.
    edge = np.clip((1 - np.sum(flat * rounded, axis=-1, keepdims=True)) / (1 - math.cos(math.pi / 4)), 0, 1)
    glint = EDGE_GLINT * edge * occlusion ** 2
    ground = 1 - GROUND_SHADE * (1 - np.clip(height / max(float(height.max()), 0.01), 0, 1))
    return (SKY + SKY_TILT * up + SUN * sun + glint) * ground


def export(obj, name, path):
    """Swaps one material in for the parts' and writes the FBX, with the armature `rig` gave it, if
    any, and its clip. The material holds no texture: the game drops a model's materials
    (JAssImpImporter.takeOutTheTrash) and takes its texture from the model script, and the exporter
    would write the texture's absolute path, so each checkout would write different files."""
    obj.data.materials.clear()
    obj.data.materials.append(bpy.data.materials.new(PREFIX + name))
    _select(obj)
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
    darkened by ambient occlusion. `to_ground` centres it standing on the ground and paints the
    light in, as for a world item; otherwise it keeps the builder's origin and the light is the
    game's, as for a vehicle or a sprite model. Returns the mesh object, the texture's pixels and the
    parts the mesh's "part" attribute indexes; the parts stay on `stage` until the next build."""
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
    if to_ground:
        colour[..., :3] *= paint_light(low, size, occlusion)
    bpy.data.objects.remove(high)
    stage.hide_render = False
    return low, colour, solid


def models_txt(specs, sprite_models):
    lines = ["module RenewableEnergy", "{",
             "    /* Written by art/models/models.py: the ground models of the items' WorldStaticModel, then the"
             " sprite models' models. */"]
    models = [(name + "_Ground", name, name, spec.get("ground_scale", GROUND_SCALE)) for name, spec in specs.items()]
    for name in sprite_models:
        for texture, meshes in wind.sprite_model_names(name)[0]:
            models += [(mesh, mesh, texture, SPRITE_MESH_SCALE) for mesh in meshes]
    for model, mesh, texture, scale in models:
        lines += ["    model %s" % model, "    {",
                  "        mesh = WorldItems/%s%s," % (PREFIX, mesh),
                  "        texture = WorldItems/%s%s," % (PREFIX, texture),
                  "        scale = %g," % scale,
                  "    }"]
    lines.append("}")
    with open(MODELS_TXT, "w") as f:
        f.write("\n".join(lines) + "\n")


def sprite_models_txt(sprite_models):
    """A spriteModel per skin, yaw and spin step, centred on its square. It names its texture:
    without one the game draws the model white."""
    lines = ["module RenewableEnergy", "{",
             "    /* Written by art/models/models.py: the sprite models placed objects are drawn as. */"]
    for name in sprite_models:
        for sprite, mesh, texture, yaw in wind.sprite_model_names(name)[1]:
            lines += ["    spriteModel %s" % sprite, "    {",
                      "        modelScript = RenewableEnergy.%s," % mesh,
                      "        texture = WorldItems/%s%s," % (PREFIX, texture),
                      "        translate = 0.0 0.0 0.0,",
                      "        rotate = 0.0 %g 0.0," % yaw,
                      "        scale = %.4f," % SPRITE_MODEL_SCALE,
                      "    }"]
    lines.append("}")
    with open(SPRITE_MODELS_TXT, "w") as f:
        f.write("\n".join(lines) + "\n")


def build_sprite_model(stage, name, spec):
    """Bakes and exports a sprite model about its builder's own origin, the square's centre, which
    the game turns it about. Each skin builds its own parts, a mesh and texture of its own: skins
    differ in shape as well as colour, as the blade sets do. No light is painted in, or a model the
    game turns would turn its lit side with it. Each spin step's mesh is the skin's mesh with the
    rotor's parts (named with wind.ROTOR) turned about the hub's axis, along Y at the spec's "hub"
    height."""
    size = SPRITE_MODEL_TEXTURE_SIZE
    for (texture, meshes), options in zip(wind.sprite_model_names(name)[0], (spec.get("skins") or {"": {}}).values()):
        low, colour, solid = build_baked(stage, lambda col: spec["model"](col, **options), texture, size, to_ground=False)
        rotor = [kit.part_name(obj).startswith(wind.ROTOR) for obj in solid]
        kit.save_pixels(os.path.join(TEXTURE_DIR, PREFIX + texture + ".png"), colour[::-1], alpha=False)
        for mesh, spin in zip(meshes, spec.get("spins", (0,))):
            def turn(bm):
                layer = bm.faces.layers.int["part"]
                turning = {v for face in bm.faces if rotor[face[layer]] for v in face.verts}
                bmesh.ops.rotate(bm, verts=list(turning), cent=(0, 0, spec["hub"]), matrix=Matrix.Rotation(math.radians(spin), 3, "Y"))
            piece = kit.edited_copy(low, turn if spin else None)
            export(piece, mesh, os.path.join(MESH_DIR, PREFIX + mesh + ".fbx"))
            print("sprite model %s: %d faces" % (mesh, len(piece.data.polygons)))
            bpy.data.objects.remove(piece)
        bpy.data.objects.remove(low)


def clear_stale(folders):
    for folder in folders:
        os.makedirs(folder, exist_ok=True)
        for stale in os.listdir(folder):
            if stale.startswith(PREFIX):
                os.remove(os.path.join(folder, stale))


def build_vehicles(stage):
    for name, spec in trailer.VEHICLES.items():
        low, colour, solid = build_baked(stage, spec["build"], name, VEHICLE_TEXTURE_SIZE, to_ground=False)
        kit.save_pixels(os.path.join(VEHICLE_TEXTURE_DIR, PREFIX + name + ".png"), colour[::-1], alpha=False)
        for suffix, (pixels, alpha) in vehicles.vehicle_overlays(low, solid).items():
            kit.save_pixels(os.path.join(VEHICLE_TEXTURE_DIR, PREFIX + name + suffix + ".png"), pixels[::-1], alpha)
        # The multi-UV shader reads rust, damage and blood through UV2; new() copies the active UV1.
        low.data.uv_layers.new(name="UVMap2")
        taken = tuple(prefix for prefixes, _ in spec["pieces"].values() for prefix in prefixes)
        pieces = {"": vehicles.cut_piece(low, solid, taken, (0, 0, 0), keep=False)}
        for suffix, (prefixes, offset) in spec["pieces"].items():
            pieces[suffix] = vehicles.cut_piece(low, solid, prefixes, offset, keep=True)
        bpy.data.objects.remove(low)
        for suffix, hinge in spec.get("hinged", {}).items():
            vehicles.rig(pieces[suffix], hinge, suffix.strip("_") + "_bone")
        for suffix, piece in pieces.items():
            # Exported like the ground models: the game reads a mesh's vertices with Y up and -Z
            # forward (it flips Z, to left-handed coordinates), so the body's +Y, the hitch, leads.
            export(piece, name + suffix, os.path.join(VEHICLE_MESH_DIR, PREFIX + name + suffix + ".fbx"))
            print("vehicle %s%s: %d faces" % (name, suffix, len(piece.data.polygons)))
            armature = piece.parent
            bpy.data.objects.remove(piece)
            if armature:
                bpy.data.objects.remove(armature)


def main():
    stage = setup()
    clear_stale((MESH_DIR, TEXTURE_DIR, VEHICLE_MESH_DIR, VEHICLE_TEXTURE_DIR))
    ground = {**items.ITEMS, **items.GROUND_MODELS}
    for name, spec in ground.items():
        size = TEXTURE_SIZE.get(name, DEFAULT_TEXTURE_SIZE)
        low, colour, _ = build_baked(stage, spec["model"], name, size, to_ground=True)
        kit.save_pixels(os.path.join(TEXTURE_DIR, PREFIX + name + ".png"), colour[::-1], alpha=False)
        export(low, name, os.path.join(MESH_DIR, PREFIX + name + ".fbx"))
        print("model %s: %d faces, %d px texture" % (name, len(low.data.polygons), size))
        bpy.data.objects.remove(low)
    for name, spec in wind.SPRITE_MODELS.items():
        build_sprite_model(stage, name, spec)
    models_txt(ground, wind.SPRITE_MODELS)
    sprite_models_txt(wind.SPRITE_MODELS)
    build_vehicles(stage)


main()
