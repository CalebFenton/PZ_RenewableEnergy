"""Renders review sheets of everything make.sh produced, read back from the files the game loads:

    blender -b --factory-startup -P art/models/preview.py

- models.png: every exported ground model and vehicle body (FBX plus its baked texture) from two
  sides, and every sprite model from one side at each of its yaw steps.
- tiles.png, tiles_02.png: every tile of renewable_energy_01 and renewable_energy_02 at four times
  its size on a floor diamond, overlays drawn over their base.
- icons.png: every icon at four times its size.
- build_icons.png: every build-menu icon at four times its size.
- index.html: every cell of those sheets on its own, named, the models at twice the sheet's size,
  from the folders models, tiles, icons and build_icons beside it; a page to review the art by.

Writes to PREVIEWS (default $TMPDIR/renewable-energy-previews) and prints the folder.
"""
import math
import os
import shutil
import sys
import tempfile

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.join(os.path.dirname(os.path.dirname(HERE)), "dev", "harness", "lib")]
import items  # noqa: E402
import paths  # noqa: E402
import render  # noqa: E402
import trailer  # noqa: E402
import wind  # noqa: E402
from art import kit  # noqa: E402
from art.preview import Gallery, enlarge, floor_diamond, grid, layer_caption, over  # noqa: E402

OUT = os.environ.get("PREVIEWS", os.path.join(tempfile.gettempdir(), "renewable-energy-previews"))
ART = render.ART
# index.html's sections in order, and the width each image shows at.
GALLERY = Gallery(OUT, {"Models": 256, "Tiles": 128, "Item icons": 128, "Build-menu icons": 96})


def tile_sheet(tileset, out):
    cells = []
    for index, layers in sorted(ART.tilesets[tileset].items()):
        cell = floor_diamond()
        # An overlay is drawn over the tile it belongs to: the one its holdout layers render.
        if layers[0]["holdout"]:
            base = next((name, i) for name, others in ART.tilesets.items() for i, other in others.items()
                        if len(other) == 1 and other[0]["build"] is layers[0]["build"]
                        and other[0]["turn"] == layers[0]["turn"] and other[0]["at"] == layers[0]["at"]
                        and other[0]["options"] == layers[0]["options"])
            over(cell, kit.load_pixels(ART.tile_file(*base)), 0, 0)
        over(cell, kit.load_pixels(ART.tile_file(tileset, index)), 0, 0)
        cells.append(enlarge(cell, 2))
        GALLERY.keep("Tiles", "tiles", "%s_%d" % (tileset, index), cells[-1],
                     "%s_%d: %s" % (tileset, index, ", ".join(layer_caption(layer) for layer in layers)))
    kit.save_pixels(os.path.join(OUT, out), grid(cells, 8, 256, 512))


def icon_sheet():
    cells = []
    for name in ART.items:
        cells.append(enlarge(kit.load_pixels(ART.icon_file(name)), 4))
        GALLERY.keep("Item icons", "icons", name, cells[-1], name)
    kit.save_pixels(os.path.join(OUT, "icons.png"), grid(cells, 8, 136, 136))
    cells = []
    for name in ART.build_icons:
        cells.append(enlarge(kit.load_pixels(ART.build_icon_file(name)), 4))
        GALLERY.keep("Build-menu icons", "build_icons", name, cells[-1], name)
    kit.save_pixels(os.path.join(OUT, "build_icons.png"), grid(cells, 4, 200, 200))


def model_sheet():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    # index.html shows each model at twice the sheet's size; the sheet takes it halved.
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.render.film_transparent = True
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    camera.data.type = "ORTHO"
    scene.collection.objects.link(camera)
    scene.camera = camera
    cells = []
    # A vehicle shows as its body with its part models, once whole and once with each look of
    # cracks, heavy then light, in place of the parts it replaces. A sprite model shows from one
    # side: one mesh at each of its yaws, as the game spins it whole, or the first skin's each spin
    # step, then each other skin's first step.
    models = [("WorldItems", name, name, [name], None) for name in {**items.ITEMS, **items.GROUND_MODELS}]
    for name, spec in wind.SPRITE_MODELS.items():
        (texture, meshes), *others = wind.sprite_model_names(name)[0]
        if len(meshes) == 1:
            models.append(("WorldItems", name, texture, meshes, list(spec["yaws"].values())))
            continue
        models += [("WorldItems", mesh, texture, [mesh], [0]) for mesh in meshes]
        models += [("WorldItems", texture, texture, meshes[:1], [0]) for texture, meshes in others]
    for name, spec in trailer.VEHICLES.items():
        whole = [s for s in spec["pieces"] if not s.endswith("Cracked")]
        models.append(("vehicles", name, name, [name + s for s in [""] + whole], None))
        for variant in ("Cracked", "LightCracked"):
            swapped = [s + variant if s + variant in spec["pieces"] else s for s in whole]
            if swapped != whole:
                models.append(("vehicles", name + variant, name, [name + s for s in [""] + swapped], None))
    for folder, name, texture_name, files, steps in models:
        bpy.ops.object.select_all(action="DESELECT")
        imported = []
        for file in files:
            bpy.ops.import_scene.fbx(filepath=os.path.join(paths.MEDIA, "models_X/%s/RenewableEnergy_%s.fbx" % (folder, file)))
            imported += list(bpy.context.selected_objects)
        texture_folder = "Vehicles" if folder == "vehicles" else folder
        texture = bpy.data.images.load(os.path.join(paths.MEDIA, "textures/%s/RenewableEnergy_%s.png" % (texture_folder, texture_name)))
        # A hinged piece comes with its armature, which shows it shut at rest.
        for obj in imported:
            if obj.type == "ARMATURE":
                obj.data.pose_position = "REST"
        meshes = [obj for obj in imported if obj.type == "MESH"]
        for obj in meshes:
            # The files carry no texture (models.py export says why): it goes on here.
            for mat in obj.data.materials:
                node = mat.node_tree.nodes.new("ShaderNodeTexImage")
                node.image = texture
                mat.node_tree.links.new(node.outputs["Color"], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
        points = [obj.matrix_world @ v.co for obj in meshes for v in obj.data.vertices]
        centre = sum(points, Vector()) / len(points)
        size = max((p - centre).length for p in points) * 2.1
        views = [((-1, 1, -0.8), 0), ((1, -1, -0.8), 0)] if steps is None else [((-1, 1, -0.6), yaw) for yaw in steps]
        for view, (direction, yaw) in enumerate(views):
            for obj in meshes:
                obj.rotation_euler.z = math.radians(yaw)
            direction = Vector(direction).normalized()
            camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
            camera.location = centre - direction * 10
            camera.data.ortho_scale = size
            file = "models/%s_%d.png" % (name, view)
            scene.render.filepath = os.path.join(OUT, file)
            bpy.ops.render.render(write_still=True)
            pixels = kit.load_pixels(scene.render.filepath)
            cells.append(pixels.reshape(256, 2, 256, 2, 4).mean(axis=(1, 3)))
            GALLERY.add("Models", file, "%s, %s" % (name, "side %d" % (view + 1) if steps is None else "yaw %s" % yaw))
        for obj in imported:
            bpy.data.objects.remove(obj)
        print("previewed %s" % name)
    kit.save_pixels(os.path.join(OUT, "models.png"), grid(cells, 8, 256, 256))


def main():
    os.makedirs(OUT, exist_ok=True)
    # Last run's named cells go, so a model or tile that's gone doesn't linger on the page.
    for folder in ("models", "tiles", "icons", "build_icons"):
        shutil.rmtree(os.path.join(OUT, folder), ignore_errors=True)
    model_sheet()
    tile_sheet("renewable_energy_01", "tiles.png")
    tile_sheet("renewable_energy_02", "tiles_02.png")
    icon_sheet()
    GALLERY.write("Renewable Energy art")
    print("previews:", OUT)


if __name__ == "__main__":
    main()
