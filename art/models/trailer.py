"""The arrow board trailer, the mod's vehicle."""
import math

from kit import beam, box, cylinder, group, text, tube
from palette import M
from parts import arch
from solar import MODULE, solar_module

# Vehicles -----------------------------------------------------------------------------------------
#
# A vehicle body is built in the frame of vanilla's vehicle meshes as the game draws them: +Y
# forward (towards the hitch), Z up, the origin where vanilla's utility trailer has its own, so the
# vehicle script's wheel, hitch and physics offsets, copied from that trailer, fit it the same way.
# The ground is TRAILER_GROUND below the origin.

TRAILER_GROUND = -0.45
TRAILER_DECK = (1.16, 1.67)  # width and length
TRAILER_DECK_Y = -0.575  # the deck's centre
TRAILER_AXLE = (-0.56, -0.18)  # y and z of the wheel centres
TRAILER_HITCH_Y = 1.4


def arrow_board_trailer(col):
    """A solar arrow board trailer of the late 1980s, set for the road: a steel deck on one axle in
    highway orange, the lamp board folded down flat over the back on its mast, two modules on a
    frame over the front, and a padlocked battery box on the tongue. Red and white reflective tape
    runs along its sides and back, reflectors mark its corners, amber at the front and red at the
    back, and it carries the county's name and a Kentucky plate."""
    width, length = TRAILER_DECK
    front, rear = TRAILER_DECK_Y + length / 2, TRAILER_DECK_Y - length / 2
    axle_y, axle_z = TRAILER_AXLE
    paint = M("safety")
    for sign in (-1, 1):
        side = sign * (width / 2 + 0.0008)
        box(col, "Trailer_Rail", paint, (0.05, length, 0.13), at=(sign * (width / 2 - 0.025), TRAILER_DECK_Y, -0.13), bevel=0.005)
        box(col, "Trailer_Spring", M("darkgrey"), (0.05, 0.6, 0.04), at=(sign * (width / 2 - 0.025), axle_y, axle_z - 0.02))
        # A fender over each wheel, outside the rails.
        box(col, "Trailer_Fender", M("black"), (0.24, 0.66, 0.025), at=(sign * 0.69, axle_y, 0.12), bevel=0.008)
        for y in (axle_y - 0.32, axle_y + 0.32):
            box(col, "Trailer_FenderSkirt", M("black"), (0.24, 0.025, 0.17), at=(sign * 0.69, y, -0.05))
        box(col, "Trailer_TailLight", M("red"), (0.1, 0.02, 0.05), at=(sign * (width / 2 - 0.08), rear - 0.01, -0.1), bevel=0.005)
        for y, name, colour in ((front - 0.1, "Trailer_Reflector", "amberlamp"), (rear + 0.1, "Trailer_ReflectorRear", "red")):
            box(col, name, M(colour), (0.004, 0.06, 0.03), at=(side + sign * 0.0012, y, -0.09))
        # The tape in two runs, ahead of and behind the wheel.
        for start, end in ((rear + 0.03, axle_y - 0.37), (axle_y + 0.37, front - 0.03)):
            _tape(col, "Trailer_Tape", start, end, lambda at, w: ((0.0016, w, 0.022), (side, at, -0.122)))
        text(col, "Trailer_Stencil", M("ink"), "KNOX CO", 0.045, at=(side + sign * 0.0006, (rear + axle_y - 0.37) / 2 + 0.05, -0.085),
             rotate=(90, 0, 90 * sign))
    _tape(col, "Trailer_TapeRear", -0.42, 0.42, lambda at, w: ((w, 0.0016, 0.02), (at, rear - 0.0008, -0.045)))
    for y in (rear + 0.025, axle_y, front - 0.025):
        box(col, "Trailer_CrossMember", paint, (width - 0.1, 0.05, 0.1), at=(0, y, -0.12))
    box(col, "Trailer_Deck", M("rawsteel"), (width, length, 0.012), at=(0, TRAILER_DECK_Y, 0))
    tube(col, "Trailer_Axle", M("darkgrey"), [(-0.62, axle_y, axle_z), (0.62, axle_y, axle_z)], 0.035, 8)
    _trailer_plate(col, rear)
    _trailer_tongue(col, front)
    _trailer_battery_box(col)
    _arrow_board(col, rear)
    _trailer_modules(col, front)
    # The lamps' cable from the battery box, along the deck to the mast and up it.
    mast_back = rear + 0.175
    tube(col, "Trailer_Cable", M("black"), [(-0.3, TRAILER_BOX_AT[0] - TRAILER_BOX[1] / 2, TRAILER_BOX_AT[1] + 0.06),
                                            (-0.3, front - 0.02, 0.02), (-0.3, mast_back + 0.1, 0.02), (-0.03, mast_back, 0.02),
                                            (-0.03, mast_back, 0.4)], 0.008)


def _tape(col, name, start, end, piece):
    """Reflective tape from `start` to `end` in alternating red and white pieces about 10 cm long;
    `piece(centre, length)` gives each piece's size and where it goes."""
    count = max(1, round((end - start) / 0.1))
    length = (end - start) / count
    for i in range(count):
        size, at = piece(start + (i + 0.5) * length, length)
        box(col, name, M("red" if i % 2 == 0 else "white"), size, at=at)


def _trailer_plate(col, rear):
    """A Kentucky plate of the day, its county along the bottom, on a bracket under the back."""
    width, height, z = 0.3, 0.15, -0.28
    box(col, "Trailer_PlateBracket", M("darkgrey"), (0.05, 0.03, 0.17), at=(0, rear + 0.015, z + 0.02))
    box(col, "Trailer_Plate", M("white"), (width, 0.004, height), at=(0, rear - 0.002, z), bevel=0.004)
    face = rear - 0.0045
    for body, size, dz in (("KENTUCKY", 0.022, 0.118), ("RD 4417", 0.055, 0.045), ("KNOX", 0.02, 0.012)):
        text(col, "Trailer_Stencil", M("navy"), body, size, at=(0, face, z + dz))


def _trailer_tongue(col, front):
    """The A-frame tongue from the deck's front corners to the coupler, its safety chains slung
    from it, and the jack stand."""
    hitch = TRAILER_HITCH_Y
    for sign in (-1, 1):
        beam(col, "Trailer_Tongue", M("safety"), (sign * 0.5, front - 0.05, -0.09), (sign * 0.03, hitch - 0.1, -0.12),
             (0.06, 0.07), bevel=0.005)
        tube(col, "Trailer_Chain", M("galvanised"), [(sign * 0.14, hitch - 0.35, -0.15), (sign * 0.12, hitch - 0.24, -0.28),
                                                     (sign * 0.07, hitch - 0.11, -0.24), (sign * 0.05, hitch - 0.07, -0.18)], 0.007)
    box(col, "Trailer_Coupler", M("darkgrey"), (0.1, 0.22, 0.08), at=(0, hitch - 0.12, -0.16), bevel=0.01)
    cylinder(col, "Trailer_CouplerCap", M("darkgrey"), 0.05, 0.08, at=(0, hitch - 0.02, -0.16), segments=12)
    jack_x, jack_y = 0.33, front + 0.45
    cylinder(col, "Trailer_Jack", M("darkgrey"), 0.03, 0.55, at=(jack_x, jack_y, TRAILER_GROUND), segments=10)
    box(col, "Trailer_JackFoot", M("darkgrey"), (0.12, 0.12, 0.01), at=(jack_x, jack_y, TRAILER_GROUND))
    top = TRAILER_GROUND + 0.55
    tube(col, "Trailer_JackCrank", M("darkgrey"), [(jack_x, jack_y, top), (jack_x + 0.1, jack_y, top), (jack_x + 0.1, jack_y, top + 0.06)],
         0.008)


TRAILER_BOX = (0.72, 0.42, 0.34)  # width, depth and height of the battery box
TRAILER_BOX_AT = (TRAILER_DECK_Y + TRAILER_DECK[1] / 2 + 0.3, -0.05)  # y and z of its bottom centre
# The lid's hinge pins run along X at the back of the box's top, and the lid turns about them.
# Open TRAILER_LID_OPEN degrees, it just clears the panels' undersides; much further and it meets
# them.
TRAILER_LID_HINGE = (0, TRAILER_BOX_AT[0] - TRAILER_BOX[1] / 2 - 0.01, TRAILER_BOX_AT[1] + TRAILER_BOX[2])
TRAILER_LID_OPEN = 70


def _trailer_battery_box(col):
    """The battery box bolted across the tongue: steel with a lid over its rim, a hasp with a
    staple and a padlock, stencilled on the side that faces the towing car. The padlock hangs from
    the staple, which stays on the box with the hasp, so the box looks right with the lock cut."""
    width, depth, height = TRAILER_BOX
    y, z = TRAILER_BOX_AT
    face = y + depth / 2
    box(col, "Trailer_BatteryBox", M("safety"), (width, depth, height), at=(0, y, z), bevel=0.01)
    box(col, "Trailer_BatteryLid", M("safety"), (width + 0.03, depth + 0.03, 0.035), at=(0, y, z + height), bevel=0.008)
    for x in (-0.22, 0.22):
        cylinder(col, "Trailer_BatteryHinge", M("darkgrey"), 0.012, 0.08, at=(x - 0.04, TRAILER_LID_HINGE[1], TRAILER_LID_HINGE[2]),
                 rotate=(0, 90, 0), segments=8)
    box(col, "Trailer_Hasp", M("rawsteel"), (0.04, 0.012, 0.09), at=(0, face + 0.02, z + height - 0.05))
    staple_y = (face + 0.026, face + 0.045)
    tube(col, "Trailer_Staple", M("rawsteel"), [(0, staple_y[0], z + height - 0.032), (0, staple_y[1], z + height - 0.032),
                                                (0, staple_y[1], z + height - 0.048), (0, staple_y[0], z + height - 0.048)], 0.003)
    box(col, "Trailer_Padlock", M("yellow"), (0.05, 0.025, 0.05), at=(0, face + 0.035, z + height - 0.12), bevel=0.006)
    arch(col, "Trailer_PadlockShackle", M("rawsteel"), 0, face + 0.035, 0.015, 0.015, z + height - 0.07, z + height - 0.04, 0.004)
    text(col, "Trailer_Stencil", M("ink"), "BATTERIES", 0.05, at=(0, face + 0.002, z + 0.1), rotate=(90, 0, 180))


ARROW_BOARD = (1.5, 0.85, 0.09)
# The board's lamps on one grid, (across, along) from its centre: a shaft across the board and a
# head each side pointing left, each head lamp in a shaft lamp's column. The outer head lamps
# clear the frame by a couple of centimetres.
LAMP_PITCH = (0.15, 0.105)
ARROW_LAMPS = ([(LAMP_PITCH[0] * (4 - i), 0.0) for i in range(9)]
               + [(LAMP_PITCH[0] * (i - 4), sign * LAMP_PITCH[1] * i) for i in (1, 2, 3) for sign in (-1, 1)])


def _arrow_board(col, rear):
    """The lamp board folded down for the road, lamps up, resting on its mast at the back and a
    cradle post ahead of it."""
    width, depth, thick = ARROW_BOARD
    centre_y = rear + 0.08 + depth / 2
    top = 0.62
    bottom = top - thick
    box(col, "Trailer_Mast", M("safety"), (0.09, 0.09, bottom), at=(0, rear + 0.12, 0.012), bevel=0.006)
    cylinder(col, "Trailer_MastPivot", M("darkgrey"), 0.03, 0.14, at=(-0.07, rear + 0.12, bottom - 0.04), rotate=(0, 90, 0), segments=10)
    box(col, "Trailer_Cradle", M("safety"), (0.3, 0.05, bottom), at=(0, centre_y + depth / 2 - 0.1, 0.012), bevel=0.006)
    box(col, "Board_Back", M("black"), (width - 0.06, depth - 0.06, thick), at=(0, centre_y, bottom))
    for sign in (-1, 1):
        box(col, "Board_FrameLong", M("safety"), (width, 0.04, thick + 0.01), at=(0, centre_y + sign * (depth - 0.04) / 2, bottom),
            bevel=0.005)
        box(col, "Board_FrameShort", M("safety"), (0.04, depth - 0.08, thick + 0.01), at=(sign * (width - 0.04) / 2, centre_y, bottom),
            bevel=0.005)
    # Each lamp a lens in a grey bezel, standing just proud of the frame: a hood standing up beside
    # it would hide the lamp behind it from some sides and not from others.
    for x, y in ARROW_LAMPS:
        cylinder(col, "Board_Bezel", M("darkgrey"), 0.052, 0.012, at=(x, centre_y + y, top), segments=16)
        cylinder(col, "Board_Lamp", M("amberlampdark"), 0.045, 0.006, at=(x, centre_y + y, top + 0.012), segments=16)


# The trailer's panels are vehicle parts the player can take off, each shown whole, lightly cracked
# or cracked by its module's condition, so each is a model of its own: TrailerN_ the whole module N
# (0 on the left, at -X), TrailerLightCrackedN_ the lightly cracked one, TrailerCrackedN_ the
# cracked one. The cracked pairs are built this far off, each its own distance, and moved back
# after baking, because the bake takes each surface's colour from the nearest detail and the pairs
# would otherwise lie in one place.
TRAILER_CRACKED_OFFSET = (0.0, 0.0, 4.0)
TRAILER_LIGHT_CRACKED_OFFSET = (0.0, 0.0, 8.0)


def _trailer_modules(col, front):
    """Two modules side by side, long sides front to back, on rails over the front of the deck and
    the battery box, raised a little at the front, on posts from the deck."""
    tilt, centre_y, height = 10, 0.2, 0.72
    for prefix, cracked, light, offset in (("Trailer", False, False, (0, 0, 0)),
                                           ("TrailerLightCracked", True, True, TRAILER_LIGHT_CRACKED_OFFSET),
                                           ("TrailerCracked", True, False, TRAILER_CRACKED_OFFSET)):
        modules = [group(col, "Trailer_Module", solar_module(col, "%s%d" % (prefix, i), cracked=cracked, light_cracks=light),
                         at=(x, 0, 0),
                         rotate=(0, 0, 90))
                   for i, x in enumerate((-0.235, 0.235))]
        group(col, "Trailer_Panels", modules, at=(offset[0], centre_y + offset[1], height + offset[2]), rotate=(tilt, 0, 0))
    rails = [box(col, "Trailer_PanelRail", M("galvanised"), (0.04, MODULE[0] + 0.04, 0.04), at=(x, 0, -0.04)) for x in (-0.4, 0.4)]
    group(col, "Trailer_Rails", rails, at=(0, centre_y, height), rotate=(tilt, 0, 0))
    rise = math.sin(math.radians(tilt))
    for x in (-0.4, 0.4):
        for y in (-0.25, front - 0.04):
            beam(col, "Trailer_PanelPost", M("galvanised"), (x, y, 0.012), (x, y, height - 0.04 + (y - centre_y) * rise), (0.04, 0.04))


# Vehicle -> builder of its body, and the part models cut out of it: model suffix -> (the prefixes
# of the parts it takes, and how far they were built from where they belong). Every piece shares
# the body's texture and mask, and the body keeps whatever no piece takes. A piece in "hinged" turns
# about a hinge in the game: it gets a bone there and one clip, named for the vehicle script's anim
# blocks, that swings it from open, `open` degrees about `axis` by the right-hand rule, to shut.
VEHICLES = {
    "ArrowBoardTrailer": {
        "build": arrow_board_trailer,
        "pieces": {
            "_Lid": (("Trailer_BatteryLid",), (0, 0, 0)),
            "_Padlock": (("Trailer_Padlock",), (0, 0, 0)),
            "_PanelLeft": (("Trailer0_",), (0, 0, 0)),
            "_PanelRight": (("Trailer1_",), (0, 0, 0)),
            "_PanelLeftCracked": (("TrailerCracked0_",), TRAILER_CRACKED_OFFSET),
            "_PanelRightCracked": (("TrailerCracked1_",), TRAILER_CRACKED_OFFSET),
            "_PanelLeftLightCracked": (("TrailerLightCracked0_",), TRAILER_LIGHT_CRACKED_OFFSET),
            "_PanelRightLightCracked": (("TrailerLightCracked1_",), TRAILER_LIGHT_CRACKED_OFFSET),
        },
        "hinged": {
            "_Lid": {"pivot": TRAILER_LID_HINGE, "axis": (1, 0, 0), "open": TRAILER_LID_OPEN, "clip": "Lid_closing"},
        },
    },
}
