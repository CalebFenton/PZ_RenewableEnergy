"""Geometry and material helpers shared by the item builders (solar.py, batteries.py and the other
families items.py lists), and the paths, stage and pixel helpers that models.py, render.py and
preview.py share.

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

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MOD = os.path.join(REPO, "Contents/mods/RenewableEnergy")
MEDIA = os.path.join(MOD, "common/media")
# render.py's tile sprites and icons, which tools/pack_textures.py packs.
TILE_DIR = os.path.join(REPO, "tools/tiles")
TILE_FILE = os.path.join(TILE_DIR, "%s_%d.png")
ICON_DIR = os.path.join(REPO, "tools/textures")
ICON_PREFIX, BUILD_ICON_PREFIX = "Item_RenewableEnergy_", "RenewableEnergy_Build_"

# Turning an object whose front faces south (-Y) to face each direction.
FACING_TURN = {"S": 0, "E": 90, "N": 180, "W": -90}

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
# how many times longer it runs along the grain, how many lines cross one figure, and how dark a
# line is. Boards are sawn, so their grain runs in long straight streaks; plywood's face is a veneer
# peeled off the log, its figure broad and wavy. Weathered planks, as the game draws its own crates
# and composters, are dark with grain cut deep by the rain. Small wood, a tray's sides or a carved
# blade, takes a finer figure, or a board's would cross it once or not at all and leave it flat.
GRAIN = {"board": (0.08, 12.0, 3.0, 0.5), "veneer": (0.09, 4.0, 3.0, 0.5), "weathered": (0.05, 14.0, 4.0, 0.3),
         "fine": (0.025, 10.0, 3.0, 0.45)}
GRAIN_EARLY = 1.1  # the pale wood between grain lines


def _math(nodes, links, operation, a, b=None, c=None, clamp=False):
    """A math node on sockets or numbers, returning its output socket."""
    node = nodes.new("ShaderNodeMath")
    node.operation = operation
    node.use_clamp = clamp
    for i, value in enumerate((a, b, c)):
        if value is None:
            continue
        if isinstance(value, (int, float)):
            node.inputs[i].default_value = value
        else:
            links.new(value, node.inputs[i])
    return node.outputs[0]


def _noise(nodes, links, vector, scale, detail):
    """A noise texture over `vector`, returning its Fac."""
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = detail
    links.new(vector, noise.inputs["Vector"])
    return noise.outputs["Fac"]


def _mix(nodes, links, factor, a, b, blend="MIX"):
    """A colour mix from `a` to `b` by `factor`, each a socket, a number, an RGBA tuple or a
    '#rrggbb' colour, returning its result."""
    node = nodes.new("ShaderNodeMix")
    node.data_type = "RGBA"
    node.blend_type = blend
    for socket, value in ((node.inputs["Factor"], factor), (node.inputs[6], a), (node.inputs[7], b)):
        if isinstance(value, bpy.types.NodeSocket):
            links.new(value, socket)
        else:
            socket.default_value = (*hex_rgb(value), 1.0) if isinstance(value, str) else value
    return node.outputs[2]


def material(name, colour, roughness=0.6, metallic=0.0, grime=0.12, scale=40.0, emission=None, speckle=None, grain=None,
             streaks=None, scorch=None, turf=None, fade=None, shine=0.5):
    """A painted, plastic or metal surface. `grime` darkens it in blotches, so flat colours don't
    look like a render. `speckle` = (colour, amount) mottles it with a second colour in a web of
    flakes, the base colour left at each flake's centre and less of it the higher `amount`: the way
    multicrystalline cells sparkle, or rust on scrap steel. `streaks` = (colour, amount) runs that
    colour down its sides in thin streaks, as rust and soot run down a drum left out in the rain.
    `scorch` = (soot, heat, height) blackens it from its foot up to a ragged line `height` metres
    up, with a band of heat tint above, as a fire inside leaves a stove. `emission` makes it glow,
    for lit LEDs. `grain`, a kind in GRAIN, draws dark grain lines along each part's longest side,
    as `_object` laid them out. `turf` = (colour, start, end) turns it to that colour from `start`
    to `end` metres out from the part's own centre, and `fade` = (start, end) thins it to nothing
    over those, both along a ragged line: a bank of earth grassed over towards its foot and lost in
    whatever ground the game draws round it. Only a tile sprite keeps a faded part's transparency;
    a baked texture doesn't. `shine` is the strength of its reflection of the sky, as Principled
    BSDF's Specular IOR Level: soil hardly has any, and with it greys like the game's grass never does."""
    if name in _MATERIALS:
        return _MATERIALS[name]
    mat = bpy.data.materials.new(name)
    nodes, bsdf = _principled(mat)
    links = mat.node_tree.links
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Specular IOR Level"].default_value = shine
    paint = (*hex_rgb(colour), 1.0)
    coords = nodes.new("ShaderNodeTexCoord")
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (1 - grime, 1 - grime, 1 - grime, 1)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    links.new(_noise(nodes, links, coords.outputs["Object"], scale / 8, 6.0), ramp.inputs["Fac"])
    reach = None
    if turf or fade:
        # How far out from the part's centre, give or take a ragged few centimetres.
        axes = nodes.new("ShaderNodeSeparateXYZ")
        links.new(coords.outputs["Object"], axes.inputs[0])
        flat = nodes.new("ShaderNodeCombineXYZ")
        links.new(axes.outputs["X"], flat.inputs["X"])
        links.new(axes.outputs["Y"], flat.inputs["Y"])
        length = nodes.new("ShaderNodeVectorMath")
        length.operation = "LENGTH"
        links.new(flat.outputs[0], length.inputs[0])
        ragged = _noise(nodes, links, coords.outputs["Object"], 7.0, 4.0)
        reach = _math(nodes, links, "ADD", length.outputs["Value"], _math(nodes, links, "MULTIPLY_ADD", ragged, 0.1, -0.05))
    if turf:
        grass, start, end = turf
        paint = _mix(nodes, links, _math(nodes, links, "MULTIPLY_ADD", reach, 1 / (end - start), -start / (end - start), clamp=True),
                     paint, grass)
    colour_out = _mix(nodes, links, 1.0, paint, ramp.outputs["Color"], "MULTIPLY")
    if speckle:
        flakes = nodes.new("ShaderNodeTexVoronoi")
        flakes.inputs["Scale"].default_value = scale * 6
        links.new(coords.outputs["Object"], flakes.inputs["Vector"])
        colour_out = _mix(nodes, links, _math(nodes, links, "MULTIPLY", flakes.outputs["Distance"], speckle[1]), colour_out, speckle[0])
    if streaks:
        # Noise squeezed tall: its features run down the part's local Z, and only its peaks show.
        squeeze = nodes.new("ShaderNodeVectorMath")
        squeeze.operation = "MULTIPLY"
        squeeze.inputs[1].default_value = (1.0, 1.0, 0.06)
        links.new(coords.outputs["Object"], squeeze.inputs[0])
        runs = _noise(nodes, links, squeeze.outputs[0], scale * 1.5, 4.0)
        peaks = nodes.new("ShaderNodeValToRGB")
        peaks.color_ramp.elements[0].position = 0.5
        peaks.color_ramp.elements[0].color = (0, 0, 0, 1)
        peaks.color_ramp.elements[1].position = 0.75
        peaks.color_ramp.elements[1].color = (streaks[1], streaks[1], streaks[1], 1)
        links.new(runs, peaks.inputs["Fac"])
        # Only down the sides: rain runs down a wall, not across a lid.
        normal = nodes.new("ShaderNodeNewGeometry")
        axes = nodes.new("ShaderNodeSeparateXYZ")
        links.new(normal.outputs["Normal"], axes.inputs[0])
        flat = _math(nodes, links, "ABSOLUTE", axes.outputs["Z"])
        side = _math(nodes, links, "SUBTRACT", 1.0, flat)
        amount = _math(nodes, links, "MULTIPLY", peaks.outputs["Color"], side)
        colour_out = _mix(nodes, links, amount, colour_out, streaks[0])
    if scorch:
        # Soot up to a ragged line `scorch[2]` above the part's foot, and a band of heat tint above it.
        soot, heat, height = scorch
        axes = nodes.new("ShaderNodeSeparateXYZ")
        links.new(coords.outputs["Object"], axes.inputs[0])
        wobble = _math(nodes, links, "MULTIPLY_ADD", _noise(nodes, links, coords.outputs["Object"], 9.0, 3.0), 0.16, -0.08)
        level = _math(nodes, links, "ADD", axes.outputs["Z"], wobble)
        below = _math(nodes, links, "SUBTRACT", height, level)
        sooted = _math(nodes, links, "MULTIPLY", below, 20.0, clamp=True)
        above = _math(nodes, links, "SUBTRACT", level, height + 0.05)
        band = _math(nodes, links, "ABSOLUTE", above)
        tinted = _math(nodes, links, "MULTIPLY_ADD", band, -12.0, 0.7, clamp=True)
        for factor, over in ((tinted, heat), (sooted, soot)):
            colour_out = _mix(nodes, links, factor, colour_out, over)
    if grain:
        across, stretch, lines, line = GRAIN[grain]
        attribute = nodes.new("ShaderNodeAttribute")
        attribute.attribute_name = "grain"
        along = nodes.new("ShaderNodeVectorMath")
        along.operation = "MULTIPLY"
        along.inputs[1].default_value = (1 / stretch, 1, 1)
        links.new(attribute.outputs["Vector"], along.inputs[0])
        figure = _noise(nodes, links, along.outputs[0], 1 / across, 2.0)
        # The figure's contour lines: up and down `lines` times over its range, a dark line at each
        # low.
        wave = _math(nodes, links, "PINGPONG", _math(nodes, links, "MULTIPLY", figure, lines * 2), 1.0)
        shade = nodes.new("ShaderNodeValToRGB")
        shade.color_ramp.elements[0].position = 0.0
        shade.color_ramp.elements[0].color = (line, line, line, 1)
        shade.color_ramp.elements[1].position = 0.3
        shade.color_ramp.elements[1].color = (1, 1, 1, 1)
        early = shade.color_ramp.elements.new(1.0)
        early.color = (GRAIN_EARLY, GRAIN_EARLY, GRAIN_EARLY, 1)
        links.new(wave, shade.inputs["Fac"])
        colour_out = _mix(nodes, links, 1.0, colour_out, shade.outputs["Color"], "MULTIPLY")
    links.new(colour_out, bsdf.inputs["Base Color"])
    if fade:
        # Thinned to a holdout, not a transparent shader, so the parts it buries stay hidden where it
        # thins: only the game's ground shows through.
        start, end = fade
        thinned = nodes.new("ShaderNodeMixShader")
        links.new(_math(nodes, links, "MULTIPLY_ADD", reach, -1 / (end - start), end / (end - start), clamp=True),
                  thinned.inputs["Fac"])
        links.new(nodes.new("ShaderNodeHoldout").outputs[0], thinned.inputs[1])
        links.new(bsdf.outputs[0], thinned.inputs[2])
        links.new(thinned.outputs[0], nodes.get("Material Output").inputs["Surface"])
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*hex_rgb(emission), 1.0)
        bsdf.inputs["Emission Strength"].default_value = 6.0
    _MATERIALS[name] = mat
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


def _round_sides(bm, ends):
    """Smooth-shades every face but `ends`, and keeps the edges round them sharp: a drum or a pipe
    drawn in flat facets shows vertical bands that the game's own round things don't."""
    for face in bm.faces:
        face.smooth = face not in ends
    for face in ends:
        for edge in face.edges:
            edge.smooth = False


def cylinder(collection, name, mat, radius, height, at=(0, 0, 0), rotate=None, segments=12, radius_top=None):
    """An upright cylinder (or cone, with `radius_top`) whose bottom centre is at `at`."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius,
                          radius2=radius if radius_top is None else radius_top, depth=height)
    bmesh.ops.translate(bm, vec=Vector((0, 0, height / 2)), verts=bm.verts)
    bm.normal_update()
    _round_sides(bm, {face for face in bm.faces if abs(face.normal.z) > 0.999})
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
    ends = {bm.faces.new(list(reversed(rings[0]))), bm.faces.new(rings[-1])}
    _round_sides(bm, ends)
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


def loft(collection, name, mat, sections):
    """A solid skinned through cross-sections, each (z, [(x, y), ...]): one closed outline,
    counter-clockwise seen from above, the same number of points in every section, capped at both
    ends. One mesh with no faces buried in another, where boxes laid end to end would leave seams
    that bake dark and split the texture into slivers."""
    bm = bmesh.new()
    rings = [[bm.verts.new((x, y, z)) for x, y in outline] for z, outline in sections]
    n = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _object(name, bm, mat, collection)


def lathe(collection, name, mat, profile, at=(0, 0, 0), lumps=0.0, seed=0, segments=32):
    """A surface turned round the Z axis through `profile`, [(radius, z), ...] from its inner edge
    out, open at both edges and facing up: earth banked round something that hides its inner edge.
    `lumps` raises or lowers each vertex by up to that fraction of its height at random (from
    `seed`), so an edge on the ground stays on it. It is smooth shaded."""
    rng = random.Random(seed)
    bm = bmesh.new()
    rings = []
    for radius, z in profile:
        row = []
        for k in range(segments):
            azimuth = 2 * math.pi * k / segments
            row.append(bm.verts.new((radius * math.cos(azimuth), radius * math.sin(azimuth),
                                     z * (1 + lumps * rng.uniform(-1, 1)))))
        rings.append(row)
    # Out along the radius, then on round the axis: counter-clockwise seen from above, facing up.
    for a, b in zip(rings, rings[1:]):
        for k in range(segments):
            face = bm.faces.new((a[k], b[k], b[(k + 1) % segments], a[(k + 1) % segments]))
            face.smooth = True
    obj = _object(name, bm, mat, collection)
    place(obj, at)
    return obj


def mound(collection, name, mat, radii, at=(0, 0, 0), rotate=None, squareness=1.0, lumps=0.0, seed=0, segments=16,
          rings=6):
    """A heap, a filled sack or a dome: the top half of an ellipsoid with semi-axes `radii`, its flat
    base on z = 0, so nothing of it shows below the floor of a tile. `squareness` above 1 squares
    its outline and shoulders, as a stuffed pillow's; `lumps` pushes each vertex out or in by up to
    that fraction at random (from `seed`), so a heap or a slack bag isn't turned as on a lathe. It
    is smooth shaded, having no edges to catch the light."""
    rng = random.Random(seed)

    def shaped(c):
        return math.copysign(abs(c) ** (1 / squareness), c)

    bm = bmesh.new()
    rows = []
    for i in range(rings):
        polar = math.pi / 2 * i / rings
        row = []
        for k in range(segments):
            azimuth = 2 * math.pi * k / segments
            bump = 1 + lumps * rng.uniform(-1, 1)
            out = shaped(math.cos(polar)) * bump
            up = radii[2] * shaped(math.sin(polar)) * bump
            row.append(bm.verts.new((radii[0] * out * shaped(math.cos(azimuth)), radii[1] * out * shaped(math.sin(azimuth)), up)))
        rows.append(row)
    top = bm.verts.new((0, 0, radii[2] * (1 + lumps * rng.uniform(-1, 1))))
    for a, b in zip(rows, rows[1:]):
        for k in range(segments):
            bm.faces.new((a[k], a[(k + 1) % segments], b[(k + 1) % segments], b[k]))
    for k in range(segments):
        bm.faces.new((rows[-1][k], rows[-1][(k + 1) % segments], top))
    for face in bm.faces:
        face.smooth = True
    bm.faces.new(list(reversed(rows[0])))
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


def around(centre, angle, distance):
    """The point `distance` from `centre`, (x, y), `angle` degrees round from +X."""
    a = math.radians(angle)
    return centre[0] + math.cos(a) * distance, centre[1] + math.sin(a) * distance


def ring(collection, name, mat, centre, radius, z, thickness):
    """A ring of tube lying flat round `centre` at height `z`, as a drum's rolled rim, a seam or a
    coil: a solid cap there would lie in the plane of what it rings and shade it black."""
    tube(collection, name, mat, [(*around(centre, 360 * k / 28, radius), z) for k in range(29)], thickness, 6)


# Stage and pixels ---------------------------------------------------------------------------------


def new_stage(samples, background):
    """A factory-fresh Cycles scene on the CPU, `samples` a pixel, lit by a world of `background`
    colour, and its collection the builds go in."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    world = bpy.data.worlds.new("Ambient")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = background
    scene.world = world
    stage = bpy.data.collections.new("Stage")
    scene.collection.children.link(stage)
    return stage


def clear(stage):
    """Takes every object off the stage, and the meshes nothing uses any more, and starts the grain
    offsets over, so a build's parts get the same grain whatever was built before it."""
    _grain_offsets.seed(0)
    for obj in list(stage.objects):
        bpy.data.objects.remove(obj)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def added(collection, build, *args, **options):
    """Runs `build(collection, *args, **options)` and returns the objects it added, in the
    collection's order."""
    before = set(collection.objects)
    build(collection, *args, **options)
    return [obj for obj in collection.objects if obj not in before]


def part_name(obj):
    """An object's name as its builder gave it, without the number Blender adds to a repeat."""
    return obj.name.split(".")[0]


def edited_copy(obj, edit=None):
    """A copy of `obj` with a mesh of its own, in the scene, `edit(bm)` applied to that mesh."""
    piece = obj.copy()
    piece.data = obj.data.copy()
    bpy.context.scene.collection.objects.link(piece)
    if edit:
        bm = bmesh.new()
        bm.from_mesh(piece.data)
        edit(bm)
        bm.to_mesh(piece.data)
        bm.free()
    return piece


def load_pixels(path):
    """An image file as a float array of rows from the top, RGBA."""
    image = bpy.data.images.load(path)
    width, height = image.size
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(height, width, 4)[::-1]
    bpy.data.images.remove(image)
    return pixels


def save_pixels(path, pixels, alpha=True):
    """Writes a load_pixels array as a PNG, its values as they are, without a colour transform;
    without `alpha`, opaque."""
    height, width, _ = pixels.shape
    image = bpy.data.images.new("out", width, height, alpha=alpha)
    image.colorspace_settings.name = "Non-Color"
    image.pixels[:] = np.clip(pixels[::-1], 0, 1).ravel()
    image.filepath_raw = path
    image.file_format = "PNG"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save()
    bpy.data.images.remove(image)
