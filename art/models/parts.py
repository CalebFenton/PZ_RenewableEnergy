"""Parts and stock more than one family of builders uses: board and sheet, handles, and the game's
55 gallon drums."""
import math

from art.kit import around, box, cylinder, ring, tube
from palette import M

BOARD = 0.019  # a pine 1 x 6's thickness
SHEET = 0.004


def side_handles(col, name, mat, x, foot, grip, reach, radius, signs=(-1, 1)):
    """A bent bar handle on each side of `signs` (-X, +X) of a case whose sides are `x` from its
    centre, standing `reach` proud: its feet at (y, z) = (-+foot[0], foot[1]), its grip from
    -grip[0] to grip[0] at grip[1]."""
    for sign in signs:
        tube(col, name, mat, [(sign * x, -foot[0], foot[1]), (sign * (x + reach), -grip[0], grip[1]),
                              (sign * (x + reach), grip[0], grip[1]), (sign * x, foot[0], foot[1])], radius)


def arch(col, name, mat, x, y, foot, grip, z0, z1, radius, sides=6):
    """A lid handle, rope or shackle arched along X over (x, y): its feet `foot` either side at `z0`,
    its grip `grip` either side at `z1`."""
    tube(col, name, mat, [(x - foot, y, z0), (x - grip, y, z1), (x + grip, y, z1), (x + foot, y, z0)], radius, sides)


DRUM = (0.29, 0.88)  # a 55 gallon drum's radius and height
# The bungs in its head, from its centre.
FEED_BUNG = (-0.1, -0.06)
GAS_BUNG = (0.1, 0.12)
# The game's four drums, which a barrel digester may be built from, by the item: its paint, and
# whether it is the game's homemade Metal Drum, rolled from sheet with a welded seam up its side and a
# band round its middle, or a bought drum with two rolling hoops.
DRUM_LOOKS = {"MetalDrum": ("drummetal", "seam"), "Mov_OrangeBarrel": ("drumorange", "hoops"),
              "Mov_DarkGreenBarrel": ("drumgreen", "hoops"), "Mov_LightGreenBarrel": ("drumolive", "hoops")}


def drum_patch(col, name, mat, centre, radius, angle, z, size):
    """A patch of `size` (along the curve, up) on a drum's side, in strips narrow enough to follow
    its curve."""
    width, height = size
    strips = max(1, round(width / 0.035))
    step = math.degrees(width / strips / radius)
    for i in range(strips):
        a = angle + (i - (strips - 1) / 2) * step
        x, y = around(centre, a, radius + 0.001)
        box(col, name, mat, (width / strips + 0.004, 0.002, height), at=(x, y, z), rotate=(0, 0, a + 90))


def drum(col, name, at, look="MetalDrum", paint=None):
    """One of the game's 55 gallon drums (DRUM_LOOKS) standing at `at`, its chimes and hoops or band
    standing proud, the top chime dark as the game outlines its own, rust eating at it where the wet
    ground and the rain on its head reach, on the sides the viewer sees. `paint` overrides its
    look's material, for a drum a fire has scorched. Every look has the one outline, so an overlay
    fits over any."""
    radius, height = DRUM
    look_paint, kind = DRUM_LOOKS[look]
    paint = paint or look_paint
    hoop, proud = 0.025, 0.008
    cylinder(col, name, M(paint), radius, height, at=(at[0], at[1], 0), segments=32)
    bands = (height / 2 - hoop / 2,) if kind == "seam" else (height / 3 - hoop / 2, 2 * height / 3 - hoop / 2)
    # Each hoop is its own part, its paint measured from its own foot, so only the drum's foot
    # takes a scorched body's soot.
    for z in (0,) + bands:
        cylinder(col, name + "_Hoop", M(paint if z == 0 else look_paint), radius + proud, hoop, at=(at[0], at[1], z), segments=32)
    ring(col, name + "_Chime", M("weld"), at, radius - 0.002, height + 0.002, 0.011)
    if kind == "seam":
        drum_patch(col, name + "_Seam", M("weld"), at, radius + 0.001, -15, 0.0, (0.012, height))
        for z in (0.06, 0.2, 0.33, 0.55, 0.68, 0.82):
            x, y = around(at, -11, radius + 0.004)
            cylinder(col, name + "_Rivet", M("weld"), 0.006, 0.004, at=(x, y, z), rotate=(90, 0, -11 + 90), segments=6)
    for angle, z, size, on_hoop in ((-112, 0, (0.13, hoop), True), (-98, hoop, (0.05, 0.03), False),
                                    (-30, 0, (0.09, hoop), True), (-62, height - 0.035, (0.08, 0.03), False),
                                    (-48, height - 0.085, (0.02, 0.05), False), (15, bands[0], (0.06, hoop), True)):
        drum_patch(col, name + "_Rust", M("rust"), at, radius + (proud if on_hoop else 0), angle, z, size)


def dropped_drum(col, look):
    """One of the game's drums (DRUM_LOOKS) as its item, its bungs in its head. Its ground model lies
    on its side, so a dropped drum can't pass for one standing installed. A standing drum's foot
    is two caps in one plane, which the occlusion bake turns black, so a lying one shows a bottom
    head of its own just below them, rimmed with a chime like its top."""
    radius, height = DRUM
    drum(col, "Drum", (0, 0), look)
    for (x, y), bung in ((FEED_BUNG, 0.042), (GAS_BUNG, 0.026)):
        cylinder(col, "Drum_Bung", M("darkgrey"), bung, 0.012, at=(x, y, height), segments=14)
    cylinder(col, "Drum_Bottom", M(DRUM_LOOKS[look][0]), radius + 0.008, 0.004, at=(0, 0, -0.004), segments=32)
    ring(col, "Drum_BottomChime", M("weld"), (0, 0), radius - 0.002, -0.006, 0.011)
