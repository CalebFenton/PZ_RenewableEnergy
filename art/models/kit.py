"""Geometry and material helpers shared by the item builders in items.py, and the stage and pixel
helpers that models.py, render.py and preview.py share.

Units are metres and the scene is Blender's: +Z up. An item is built standing on z = 0, centred on
the origin, with its front facing -Y. In a tile, -Y is south and +X east (Blender's +Y is the
game's north, because the game's y axis points south).
"""
import math
import os
import random

import bmesh
import bpy
import numpy as np
from mathutils import Vector

# Materials ----------------------------------------------------------------------------------------


def hex_rgb(value):
    """'#rrggbb' to linear RGB, so the colours below read like the sRGB values of a paint chip."""
    def channel(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return tuple(channel(int(value[i:i + 2], 16)) for i in (1, 3, 5))


def _principled(material):
    if not material.node_tree:
        material.use_nodes = True
    nodes = material.node_tree.nodes
    return nodes, nodes.get("Principled BSDF") or nodes.new("ShaderNodeBsdfPrincipled")


_MATERIALS = {}

# Wood grain, by kind: the size across the grain of the figure the grain lines follow (metres),
# how many times longer it runs along the grain, and how many lines cross one figure. Boards are
# sawn, so their grain runs in long straight streaks; plywood's face is a veneer peeled off the
# log, its figure broad and wavy.
GRAIN = {"board": (0.08, 12.0, 3.0), "veneer": (0.09, 4.0, 3.0)}
GRAIN_LINE, GRAIN_EARLY = 0.5, 1.1  # a grain line's shade, and the pale wood between lines


def material(name, color, roughness=0.6, metallic=0.0, grime=0.12, scale=40.0, emission=None, speckle=None, grain=None):
    """A painted, plastic or metal surface. `grime` darkens it in blotches, so flat colours don't
    look like a render. `speckle` = (colour, amount) mottles it with a second colour in a web of
    flakes, the base colour left at each flake's centre and less of it the higher `amount`: the way
    multicrystalline cells sparkle, or rust on scrap steel. `emission` makes it glow, for lit LEDs.
    `grain`, a kind in GRAIN, draws dark grain lines along each part's longest side, as `_object`
    laid them out."""
    key = name
    if key in _MATERIALS:
        return _MATERIALS[key]
    mat = bpy.data.materials.new(name)
    nodes, bsdf = _principled(mat)
    links = mat.node_tree.links
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    base = (*hex_rgb(color), 1.0)
    coords = nodes.new("ShaderNodeTexCoord")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale / 8
    noise.inputs["Detail"].default_value = 6.0
    links.new(coords.outputs["Object"], noise.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (1 - grime, 1 - grime, 1 - grime, 1)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    tint = nodes.new("ShaderNodeMix")
    tint.data_type = "RGBA"
    tint.blend_type = "MULTIPLY"
    tint.inputs["Factor"].default_value = 1.0
    tint.inputs[6].default_value = base
    links.new(ramp.outputs["Color"], tint.inputs[7])
    color_out = tint.outputs[2]
    if speckle:
        flakes = nodes.new("ShaderNodeTexVoronoi")
        flakes.inputs["Scale"].default_value = scale * 6
        links.new(coords.outputs["Object"], flakes.inputs["Vector"])
        mix = nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        steps = nodes.new("ShaderNodeMath")
        steps.operation = "MULTIPLY"
        steps.inputs[1].default_value = speckle[1]
        links.new(flakes.outputs["Distance"], steps.inputs[0])
        links.new(steps.outputs[0], mix.inputs["Factor"])
        links.new(color_out, mix.inputs[6])
        mix.inputs[7].default_value = (*hex_rgb(speckle[0]), 1.0)
        color_out = mix.outputs[2]
    if grain:
        across, stretch, lines = GRAIN[grain]
        attribute = nodes.new("ShaderNodeAttribute")
        attribute.attribute_name = "grain"
        along = nodes.new("ShaderNodeVectorMath")
        along.operation = "MULTIPLY"
        along.inputs[1].default_value = (1 / stretch, 1, 1)
        links.new(attribute.outputs["Vector"], along.inputs[0])
        figure = nodes.new("ShaderNodeTexNoise")
        figure.inputs["Scale"].default_value = 1 / across
        figure.inputs["Detail"].default_value = 2.0
        links.new(along.outputs[0], figure.inputs["Vector"])
        # The figure's contour lines: up and down `lines` times over its range, a dark line at each
        # low.
        count = nodes.new("ShaderNodeMath")
        count.operation = "MULTIPLY"
        count.inputs[1].default_value = lines * 2
        links.new(figure.outputs["Fac"], count.inputs[0])
        wave = nodes.new("ShaderNodeMath")
        wave.operation = "PINGPONG"
        wave.inputs[1].default_value = 1.0
        links.new(count.outputs[0], wave.inputs[0])
        shade = nodes.new("ShaderNodeValToRGB")
        shade.color_ramp.elements[0].position = 0.0
        shade.color_ramp.elements[0].color = (GRAIN_LINE, GRAIN_LINE, GRAIN_LINE, 1)
        shade.color_ramp.elements[1].position = 0.3
        shade.color_ramp.elements[1].color = (1, 1, 1, 1)
        early = shade.color_ramp.elements.new(1.0)
        early.color = (GRAIN_EARLY, GRAIN_EARLY, GRAIN_EARLY, 1)
        links.new(wave.outputs[0], shade.inputs["Fac"])
        streaked = nodes.new("ShaderNodeMix")
        streaked.data_type = "RGBA"
        streaked.blend_type = "MULTIPLY"
        streaked.inputs["Factor"].default_value = 1.0
        links.new(color_out, streaked.inputs[6])
        links.new(shade.outputs["Color"], streaked.inputs[7])
        color_out = streaked.outputs[2]
    links.new(color_out, bsdf.inputs["Base Color"])
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*hex_rgb(emission), 1.0)
        bsdf.inputs["Emission Strength"].default_value = 6.0
    _MATERIALS[key] = mat
    return mat


def holdout():
    """Hides what is behind it and leaves its own pixels transparent: an overlay tile renders its
    base object with this, so the overlay keeps only what the base doesn't cover."""
    if "Holdout" in _MATERIALS:
        return _MATERIALS["Holdout"]
    mat = bpy.data.materials.new("Holdout")
    nodes, bsdf = _principled(mat)
    out = nodes.get("Material Output")
    hold = nodes.new("ShaderNodeHoldout")
    mat.node_tree.links.new(hold.outputs[0], out.inputs["Surface"])
    _MATERIALS["Holdout"] = mat
    return mat


# Meshes -------------------------------------------------------------------------------------------


# Each mesh carries its own wood grain coordinates (attribute "grain"): its vertices' positions
# turned so its longest side runs along X, where a grain material stretches its figure, and moved by
# an offset of its own, so boards side by side don't match. They stay in the part's frame through
# models.py's merge, so the grain follows each board however it is placed.
_grain_offsets = random.Random(0)


def _object(name, bm, mat, collection):
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    extent = [max(v.co[i] for v in bm.verts) - min(v.co[i] for v in bm.verts) for i in range(3)]
    axes = sorted(range(3), key=lambda i: -extent[i])
    offset = Vector([_grain_offsets.uniform(-20, 20) for _ in range(3)])
    layer = bm.verts.layers.float_vector.new("grain")
    for v in bm.verts:
        v[layer] = Vector([v.co[i] for i in axes]) + offset
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    return obj


def box(collection, name, mat, size, at=(0, 0, 0), bevel=0.0, rotate=None):
    """A box of `size` whose bottom centre is at `at`, optionally rotated (euler degrees) about that
    point. A small bevel catches light along the edges, which keeps low-poly boxes readable."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector((0, 0, size[2] / 2)), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) / 2.5), segments=1,
                        affect="EDGES", profile=0.5)
    obj = _object(name, bm, mat, collection)
    place(obj, at, rotate)
    return obj


def beam(collection, name, mat, start, end, section, bevel=0.0):
    """A straight post, board or bar from `start` to `end`, `section` = (width, thickness) across
    it: a box turned the shortest way from upright, so a beam in the YZ plane keeps its width on
    X and one along X stands its width up on Z."""
    start, end = Vector(start), Vector(end)
    run = end - start
    obj = box(collection, name, mat, (section[0], section[1], run.length), bevel=bevel)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(run)
    obj.location = start
    return obj


def cylinder(collection, name, mat, radius, height, at=(0, 0, 0), rotate=None, segments=12, radius_top=None):
    """An upright cylinder (or cone, with `radius_top`) whose bottom centre is at `at`."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius,
                          radius2=radius if radius_top is None else radius_top, depth=height)
    bmesh.ops.translate(bm, vec=Vector((0, 0, height / 2)), verts=bm.verts)
    obj = _object(name, bm, mat, collection)
    place(obj, at, rotate)
    return obj


def tube(collection, name, mat, points, radius, sides=6):
    """A cable or pipe along `points`, with closed ends."""
    points = [Vector(p) for p in points]
    bm = bmesh.new()
    rings = []
    for i, point in enumerate(points):
        tangent = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
        across = tangent.orthogonal().normalized()
        other = tangent.cross(across)
        rings.append([bm.verts.new(point + (across * math.cos(a) + other * math.sin(a)) * radius)
                      for a in (2 * math.pi * k / sides for k in range(sides))])
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    return _object(name, bm, mat, collection)


def prism(collection, name, mat, outline, depth, at=(0, 0, 0), rotate=None):
    """A flat shape extruded along +Y: `outline` is a list of (x, z) points, counter-clockwise when
    seen from the front. Used for brackets, triangles and cut sheet."""
    bm = bmesh.new()
    front = [bm.verts.new((x, -depth / 2, z)) for x, z in outline]
    back = [bm.verts.new((x, depth / 2, z)) for x, z in outline]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(outline)
    for i in range(n):
        bm.faces.new((front[(i + 1) % n], front[i], back[i], back[(i + 1) % n]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = _object(name, bm, mat, collection)
    place(obj, at, rotate)
    return obj


def text(collection, name, mat, body, size, at=(0, 0, 0), rotate=(90, 0, 0), align="CENTER"):
    """Flat lettering as a mesh, by default standing upright and reading from the front (-Y), its
    baseline centre at `at`. Lift it a millimetre off the surface it is printed on."""
    curve = bpy.data.curves.new(name, "FONT")
    curve.body = body
    curve.size = size
    curve.align_x = align
    curve.align_y = "BOTTOM_BASELINE"
    curve.resolution_u = 3
    temp = bpy.data.objects.new(name + "_curve", curve)
    collection.objects.link(temp)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(temp.evaluated_get(depsgraph))
    bpy.data.objects.remove(temp)
    bpy.data.curves.remove(curve)
    mesh.materials.clear()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    place(obj, at, rotate)
    return obj


def place(obj, at, rotate=None):
    obj.location = Vector(at)
    if rotate:
        obj.rotation_euler = [math.radians(a) for a in rotate]
    return obj


def group(collection, name, objects, at=(0, 0, 0), rotate=None):
    """Moves and turns several parts as one, through a parent empty."""
    empty = bpy.data.objects.new(name, None)
    collection.objects.link(empty)
    for obj in objects:
        obj.parent = empty
    place(empty, at, rotate)
    return empty


# Stage and pixels ---------------------------------------------------------------------------------


def clear(stage):
    """Takes every object off the stage, and the meshes nothing uses any more, and starts the grain
    offsets over, so a build's parts get the same grain whatever was built before it."""
    _grain_offsets.seed(0)
    for obj in list(stage.objects):
        bpy.data.objects.remove(obj)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def load_pixels(path):
    """An image file as a float array of rows from the top, RGBA."""
    image = bpy.data.images.load(path)
    width, height = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(height, width, 4)[::-1]
    bpy.data.images.remove(image)
    return pixels


def save_pixels(path, pixels):
    """Writes a load_pixels array as a PNG, its values as they are, without a colour transform."""
    height, width, _ = pixels.shape
    image = bpy.data.images.new("out", width, height, alpha=True)
    image.colorspace_settings.name = "Non-Color"
    image.pixels[:] = np.clip(pixels[::-1], 0, 1).ravel()
    image.filepath_raw = path
    image.file_format = "PNG"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save()
    bpy.data.images.remove(image)
