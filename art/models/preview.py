"""Renders review sheets of everything make.sh produced, read back from the files the game loads:

    blender -b --factory-startup -P art/models/preview.py

- models.png: every exported ground model and vehicle body (FBX plus its baked texture) from two
  sides.
- tiles.png: every tile at four times its size on a floor diamond, overlays drawn over their base.
- icons.png: every icon at four times its size.

Writes to PREVIEWS (default $TMPDIR/renewable-energy-previews) and prints the folder.
"""
import os
import sys
import tempfile

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import items  # noqa: E402
import tiles  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
MEDIA = os.path.join(REPO, "Contents/mods/RenewableEnergy/common/media")
OUT = os.environ.get("PREVIEWS", os.path.join(tempfile.gettempdir(), "renewable-energy-previews"))
BACKGROUND = np.array([0.3, 0.3, 0.3, 1.0], dtype=np.float32)


def load(path):
    image = bpy.data.images.load(path)
    width, height = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(height, width, 4)[::-1].copy()
    bpy.data.images.remove(image)
    return pixels


def save(path, pixels):
    height, width, _ = pixels.shape
    image = bpy.data.images.new("sheet", width, height, alpha=True)
    image.pixels[:] = np.clip(pixels[::-1], 0, 1).ravel()
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def over(sheet, pixels, x, y):
    """Alpha-composites `pixels` onto `sheet` with its top left at (x, y)."""
    height, width, _ = pixels.shape
    region = sheet[y:y + height, x:x + width]
    alpha = pixels[..., 3:4]
    region[..., :3] = pixels[..., :3] * alpha + region[..., :3] * (1 - alpha)
    region[..., 3:] = alpha + region[..., 3:] * (1 - alpha)


def grid(cells, columns, cell_w, cell_h):
    rows = (len(cells) + columns - 1) // columns
    sheet = np.tile(BACKGROUND, (rows * cell_h, columns * cell_w, 1))
    for i, pixels in enumerate(cells):
        over(sheet, pixels, (i % columns) * cell_w, (i // columns) * cell_h)
    return sheet


def enlarge(pixels, factor):
    return pixels.repeat(factor, axis=0).repeat(factor, axis=1)


def floor_diamond(width, height):
    """A tile's floor outline, so a sprite's placement on its square shows."""
    cell = np.zeros((height, width, 4), dtype=np.float32)
    for x in range(width):
        dy = round(abs(x - width / 2 + 0.5) / 2)
        for y in (height - 64 + dy, height - 1 - dy):
            cell[min(y, height - 1), x] = (0.5, 0.5, 0.5, 1)
    return cell


def tile_sheet():
    path = os.path.join(REPO, "tools/tiles/renewable_energy_01_%d.png")
    cells = []
    for index, layers in sorted(tiles.TILES.items()):
        cell = floor_diamond(128, 256)
        # An overlay is drawn over the tile it belongs to: the one its holdout layers render.
        if layers[0]["holdout"]:
            base = next(i for i, other in tiles.TILES.items()
                        if len(other) == 1 and other[0]["build"] is layers[0]["build"]
                        and other[0]["turn"] == layers[0]["turn"] and other[0]["at"] == layers[0]["at"])
            over(cell, load(path % base), 0, 0)
        over(cell, load(path % index), 0, 0)
        cells.append(enlarge(cell, 2))
    save(os.path.join(OUT, "tiles.png"), grid(cells, 8, 256, 512))


def icon_sheet():
    cells = [enlarge(load(os.path.join(REPO, "tools/textures/Item_RenewableEnergy_%s.png" % name)), 4)
             for name in items.ITEMS]
    save(os.path.join(OUT, "icons.png"), grid(cells, 8, 136, 136))


def model_sheet():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = scene.render.resolution_y = 256
    scene.render.film_transparent = True
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    camera.data.type = "ORTHO"
    scene.collection.objects.link(camera)
    scene.camera = camera
    cells = []
    models = [("WorldItems", name) for name in items.ITEMS] + [("vehicles", name) for name in items.VEHICLES]
    for folder, name in models:
        bpy.ops.import_scene.fbx(filepath=os.path.join(MEDIA, "models_X/%s/RenewableEnergy_%s.fbx" % (folder, name)))
        imported = list(bpy.context.selected_objects)
        texture_folder = "Vehicles" if folder == "vehicles" else folder
        texture = bpy.data.images.load(os.path.join(MEDIA, "textures/%s/RenewableEnergy_%s.png" % (texture_folder, name)))
        for obj in imported:
            for mat in obj.data.materials:
                nodes = [n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE"]
                if not nodes:
                    nodes = [mat.node_tree.nodes.new("ShaderNodeTexImage")]
                    mat.node_tree.links.new(nodes[0].outputs["Color"],
                                            mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
                for node in nodes:
                    node.image = texture
        points = [obj.matrix_world @ v.co for obj in imported for v in obj.data.vertices]
        centre = sum(points, Vector()) / len(points)
        size = max((p - centre).length for p in points) * 2.1
        for direction in ((-1, 1, -0.8), (1, -1, -0.8)):
            direction = Vector(direction).normalized()
            camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
            camera.location = centre - direction * 10
            camera.data.ortho_scale = size
            path = os.path.join(OUT, "model_%s_%d.png" % (name, direction.x > 0))
            scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            cells.append(load(path))
            os.remove(path)
        for obj in imported:
            bpy.data.objects.remove(obj)
        print("previewed %s" % name)
    save(os.path.join(OUT, "models.png"), grid(cells, 8, 256, 256))


def main():
    os.makedirs(OUT, exist_ok=True)
    model_sheet()
    tile_sheet()
    icon_sheet()
    print("previews:", OUT)


main()
