"""Geometry and material helpers shared by the item builders in items.py.

Units are metres and the scene is Blender's: +Z up. An item is built standing on z = 0, centred on
the origin, with its front facing -Y. In a tile, -Y is south and +X east (Blender's +Y is the
game's north, because the game's y axis points south).
"""
import math

import bmesh
import bpy
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


def material(name, color, roughness=0.6, metallic=0.0, grime=0.12, scale=40.0, emission=None, speckle=None):
    """A painted, plastic or metal surface. `grime` darkens it in blotches, so flat colours don't
    look like a render. `speckle` = (colour, amount) scatters fine flakes of a second colour, the
    way multicrystalline cells sparkle. `emission` makes it glow, for lit LEDs."""
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


def _object(name, bm, mat, collection):
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
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


def torus(collection, name, mat, major, minor, at=(0, 0, 0), rotate=None, segments=16, sides=6):
    """A ring lying in the XY plane, such as a coil of cable."""
    bm = bmesh.new()
    rings = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        centre = Vector((math.cos(a) * major, math.sin(a) * major, 0))
        out = Vector((math.cos(a), math.sin(a), 0))
        rings.append([bm.verts.new(centre + (out * math.cos(b) + Vector((0, 0, 1)) * math.sin(b)) * minor)
                      for b in (2 * math.pi * k / sides for k in range(sides))])
    for i in range(segments):
        a, b = rings[i], rings[(i + 1) % segments]
        for k in range(sides):
            bm.faces.new((a[k], b[k], b[(k + 1) % sides], a[(k + 1) % sides]))
    obj = _object(name, bm, mat, collection)
    place(obj, at, rotate)
    return obj


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
