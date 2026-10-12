"""Renders the mod list icon, 42/icon.png: a solar rack and a deep-cycle battery in afternoon sun,
on a sky tile with the sun in its corner.

    blender -b --factory-startup -P art/models/mod_icon.py

The mod list draws the icon about 28 to 40 pixels square (ModListBox, ModOrderListBox), so it is
shipped at 64 pixels, the size the game scales down cleanly at every font size, and drawn bold:
two objects, big, with a dark outline, nothing thinner than a couple of pixels at that size.
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

REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(REPO, "Contents/mods/RenewableEnergy/42/icon.png")
SCRATCH = os.path.join(tempfile.gettempdir(), "renewable-energy-render")
SIZE = 64
RENDER = 512  # rendered larger, then averaged down

SKY_TOP, SKY_BOTTOM = (0.20, 0.48, 0.82), (0.62, 0.82, 0.96)
SUN = (1.0, 0.84, 0.25)
BORDER = (0.10, 0.16, 0.26)


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 128
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.resolution_x = scene.render.resolution_y = RENDER
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.6, 0.7, 0.85, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world
    # Low sun from behind the camera's left shoulder, so the glass of the modules catches it.
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.5
    sun.data.angle = math.radians(6)
    sun.rotation_euler = Vector((0.4, -0.9, 0.75)).to_track_quat("Z", "Y").to_euler()
    scene.collection.objects.link(sun)
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    camera.data.type = "ORTHO"
    scene.collection.objects.link(camera)
    scene.camera = camera
    stage = bpy.data.collections.new("Stage")
    scene.collection.children.link(stage)
    return camera, stage


def build(stage):
    """The rack faces the camera; the battery stands in front of its right leg."""
    items.solar_rack(stage)
    before = set(stage.objects)
    items.deep_cycle_battery(stage)
    battery = [obj for obj in stage.objects if obj not in before and obj.parent is None]
    # Half again its real size: at the true scale it is a few pixels next to the rack.
    kit.group(stage, "Battery", battery, at=(0.42, -0.66, 0), rotate=(0, 0, 18)).scale = (1.5, 1.5, 1.5)
    bpy.context.view_layer.update()


def aim(camera, stage):
    """From the south-east, a little above, framing everything with a margin."""
    direction = Vector((-0.45, 0.85, -0.38)).normalized()
    rotation = direction.to_track_quat("-Z", "Y")
    right, up = rotation @ Vector((1, 0, 0)), rotation @ Vector((0, 1, 0))
    points = [obj.matrix_world @ v.co for obj in stage.objects if obj.type == "MESH" for v in obj.data.vertices]
    across = [p.dot(right) for p in points]
    along = [p.dot(up) for p in points]
    size = max(max(across) - min(across), max(along) - min(along))
    centre = right * (max(across) + min(across)) / 2 + up * (max(along) + min(along)) / 2
    camera.rotation_euler = rotation.to_euler()
    camera.location = centre - direction * 20
    # The objects fill the lower right of the tile, leaving the top left to the sun.
    camera.data.ortho_scale = size * 1.3
    camera.location += -right * size * 0.1 + up * size * 0.04
    bpy.context.view_layer.update()


def load_pixels(path):
    image = bpy.data.images.load(path)
    width, height = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(height, width, 4)[::-1]
    bpy.data.images.remove(image)
    return pixels


def save_pixels(path, pixels):
    height, width, _ = pixels.shape
    image = bpy.data.images.new("out", width, height, alpha=True)
    image.colorspace_settings.name = "Non-Color"
    image.pixels[:] = np.clip(pixels[::-1], 0, 1).ravel()
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def rounded_square(n, radius):
    """Coverage of a square tile with rounded corners, sampled at pixel centres."""
    c = (np.arange(n) + 0.5) / n
    x, y = np.meshgrid(c, c)
    dx = np.maximum(np.abs(x - 0.5) - (0.5 - radius), 0)
    dy = np.maximum(np.abs(y - 0.5) - (0.5 - radius), 0)
    return (np.hypot(dx, dy) <= radius).astype(np.float32)


def background(n):
    """The sky tile: a gradient, a sun disc with a soft glow in the top left, a dark rim."""
    rows = np.linspace(0, 1, n)[:, None, None]
    sky = np.array(SKY_TOP) * (1 - rows) + np.array(SKY_BOTTOM) * rows
    sky = np.broadcast_to(sky, (n, n, 3)).copy()
    c = (np.arange(n) + 0.5) / n
    x, y = np.meshgrid(c, c)
    distance = np.hypot(x - 0.24, y - 0.22)
    glow = np.clip(1 - distance / 0.32, 0, 1) ** 2 * 0.55
    sky = sky * (1 - glow[..., None]) + np.array(SUN) * glow[..., None]
    disc = distance < 0.11
    sky[disc] = SUN
    tile = rounded_square(n, 0.14)
    inner = rounded_square(n, 0.14)
    shrink = int(n * 0.035)
    inner[:] = 0
    inner[shrink:n - shrink, shrink:n - shrink] = rounded_square(n - 2 * shrink, 0.13)
    out = np.zeros((n, n, 4), dtype=np.float32)
    out[..., :3] = np.where(inner[..., None] > 0, sky, np.array(BORDER))
    out[..., 3] = tile
    return out


def outline(fg, width):
    """A dark rim around the objects, so they stand off the sky at small sizes."""
    alpha = fg[..., 3]
    grown = alpha.copy()
    for dy in range(-width, width + 1):
        for dx in range(-width, width + 1):
            if dx * dx + dy * dy <= width * width:
                grown = np.maximum(grown, np.roll(np.roll(alpha, dy, 0), dx, 1))
    return grown


def compose(fg):
    n = fg.shape[0]
    out = background(n)
    rim = outline(fg, max(2, n // 90))
    out[..., :3] = out[..., :3] * (1 - rim[..., None]) + np.array(BORDER) * rim[..., None]
    a = fg[..., 3:4]
    out[..., :3] = out[..., :3] * (1 - a) + fg[..., :3] * a
    # Clip the objects to the tile, so nothing pokes past the rounded rim.
    out[..., 3] = background(n)[..., 3]
    return out


def downsample(pixels, size):
    factor = pixels.shape[0] // size
    alpha = pixels[..., 3:4]
    colour = (pixels[..., :3] * alpha).reshape(size, factor, size, factor, 3).mean(axis=(1, 3))
    coverage = alpha.reshape(size, factor, size, factor).mean(axis=(1, 3))
    out = np.zeros((size, size, 4), dtype=np.float32)
    out[..., :3] = colour / np.maximum(coverage, 1e-4)[..., None]
    out[..., 3] = coverage
    return out


def main():
    camera, stage = setup()
    build(stage)
    aim(camera, stage)
    os.makedirs(SCRATCH, exist_ok=True)
    raw = os.path.join(SCRATCH, "mod_icon.png")
    bpy.context.scene.render.filepath = raw
    bpy.ops.render.render(write_still=True)
    full = compose(load_pixels(raw))
    save_pixels(os.path.join(SCRATCH, "mod_icon_full.png"), full)
    save_pixels(OUT, downsample(full, SIZE))
    print("mod icon written to %s" % OUT)


main()
