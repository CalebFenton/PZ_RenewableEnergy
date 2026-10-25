"""The printed matter: the Homestead Power magazines and the FEMA wood gas pamphlet."""
from art.kit import around, box, cylinder, prism, ring, text
from palette import M

MAGAZINE = (0.21, 0.275, 0.004)


# Each issue's cover colour, whether its title is printed dark, and the line under its picture.
MAGAZINE_ISSUES = {1: ("magazine1", True, "SUN & BATTERIES"), 2: ("magazine2", False, "INVERTERS & CONTROL"),
                   3: ("magazine3", False, "BIOGAS FROM MANURE"), 4: ("magazine4", False, "WIND & TREADMILL POWER")}


def magazine(col, issue):
    """Homestead Power, a fictional 1990s homesteading magazine: issue 1 on sun and batteries,
    issue 2 on inverters and control, issue 3 on biogas from the farm's manure, issue 4 on wind
    chargers and the treadmill."""
    width, depth, height = MAGAZINE
    cover, dark_title, line = MAGAZINE_ISSUES[issue]
    title = M("ink" if dark_title else "white")
    box(col, "Mag%d_Pages" % issue, M("white"), (width - 0.004, depth - 0.004, height - 0.001))
    box(col, "Mag%d_Cover" % issue, M(cover), (width, depth, 0.001), at=(0, 0, height - 0.001))
    top = height + 0.0003
    flat = (0, 0, 0)
    text(col, "Mag%d_Title" % issue, title, "HOMESTEAD", 0.03, at=(0, 0.09, top), rotate=flat)
    text(col, "Mag%d_Title2" % issue, title, "POWER", 0.036, at=(0, 0.052, top), rotate=flat)
    text(col, "Mag%d_Issue" % issue, M("red"), "#%d" % issue, 0.03, at=(0.075, 0.105, top), rotate=flat)
    box(col, "Mag%d_Picture" % issue, M("sky"), (0.17, 0.13, 0.0004), at=(0, -0.04, height))
    if issue == 1:
        cylinder(col, "Mag1_Sun", M("sun"), 0.025, 0.0006, at=(-0.045, -0.0, height + 0.0002), segments=16)
        box(col, "Mag1_Panel", M("cells"), (0.09, 0.05, 0.0008), at=(0.025, -0.065, height + 0.0002), rotate=(0, 0, -8))
        box(col, "Mag1_Battery", M("marine"), (0.04, 0.025, 0.0009), at=(-0.05, -0.085, height + 0.0002))
    elif issue == 2:
        box(col, "Mag2_Inverter", M("bluegrey"), (0.08, 0.05, 0.0008), at=(-0.02, -0.05, height + 0.0002))
        box(col, "Mag2_Panel", M("black"), (0.04, 0.03, 0.0009), at=(-0.03, -0.05, height + 0.0003))
        prism(col, "Mag2_Bolt", M("sun"), [(0, 0.05), (0.02, 0.0), (0.008, 0.0), (0.016, -0.04), (-0.006, 0.01), (0.006, 0.01)],
              0.0008, at=(0.055, -0.04, height + 0.0002), rotate=(90, 0, 0))
    elif issue == 3:
        # A brick dome in the farmyard's mud, a cow beside it, and the blue flame its gas burns with.
        box(col, "Mag3_Ground", M("earth"), (0.17, 0.045, 0.0008), at=(0, -0.0825, height + 0.0002))
        prism(col, "Mag3_Dome", M("brick"), [(-0.04, 0), (0.04, 0), (0.03, 0.025), (0.0, 0.035), (-0.03, 0.025)], 0.0008,
              at=(-0.03, -0.06, height + 0.0003), rotate=(-90, 0, 0))
        box(col, "Mag3_Cow", M("white"), (0.04, 0.022, 0.0009), at=(0.045, -0.05, height + 0.0003))
        for x in (0.03, 0.06):
            box(col, "Mag3_CowSpot", M("ink"), (0.01, 0.008, 0.001), at=(x, -0.045, height + 0.0003))
        prism(col, "Mag3_Flame", M("flameblue"), [(-0.01, 0), (0.01, 0), (0.0, 0.03)], 0.0008, at=(0.05, -0.005, height + 0.0003),
              rotate=(-90, 0, 0))
    else:
        # A treadmill wind charger on its mast over a red barn, and a treadmill in the yard.
        box(col, "Mag4_Ground", M("earth"), (0.17, 0.035, 0.0008), at=(0, -0.0875, height + 0.0002))
        prism(col, "Mag4_Barn", M("red"), [(-0.03, 0), (0.03, 0), (0.03, 0.03), (0.0, 0.048), (-0.03, 0.03)], 0.0008,
              at=(-0.045, -0.07, height + 0.0003), rotate=(-90, 0, 0))
        hub = (0.035, -0.005)
        box(col, "Mag4_Mast", M("ink"), (0.003, 0.065, 0.0009), at=(hub[0], hub[1] - 0.0325, height + 0.0003))
        for k in range(3):
            angle = 120 * k + 15
            x, y = around(hub, angle + 90, 0.0125)
            box(col, "Mag4_Blade", M("white"), (0.004, 0.025, 0.001), at=(x, y, height + 0.0003), rotate=(0, 0, angle))
        box(col, "Mag4_Treadmill", M("black"), (0.035, 0.012, 0.001), at=(0.06, -0.08, height + 0.0003))
        box(col, "Mag4_TreadmillRail", M("black"), (0.003, 0.018, 0.001), at=(0.077, -0.07, height + 0.0003))
    text(col, "Mag%d_Line" % issue, M("white"), line, 0.015, at=(0, -0.122, top), rotate=flat)


# A government digest-size pamphlet. Its pages are thick enough to be modelled (models.py
# DECAL_THICKNESS) for what is printed on its cover to be baked onto.
PAMPHLET = (0.14, 0.215, 0.004)


def fema_pamphlet(col):
    """The 1989 FEMA plans for a wood gas generator as a government office printed them: a thin
    pamphlet, two staples in its spine, a plain white cover with a blue band and the agency's seal."""
    width, depth, height = PAMPHLET
    box(col, "Pamphlet_Pages", M("white"), (width - 0.003, depth - 0.003, height - 0.0008))
    box(col, "Pamphlet_Cover", M("white"), (width, depth, 0.0008), at=(0, 0, height - 0.0008))
    top = height + 0.0003
    flat = (0, 0, 0)
    box(col, "Pamphlet_Band", M("marine"), (width, 0.05, 0.0004), at=(0, depth / 2 - 0.035, height))
    text(col, "Pamphlet_Agency", M("white"), "FEMA", 0.022, at=(0, depth / 2 - 0.045, top + 0.0002), rotate=flat)
    for i, (line, size) in enumerate((("CONSTRUCTION OF A", 0.0085), ("SIMPLIFIED WOOD GAS", 0.0105),
                                      ("GENERATOR", 0.0105))):
        text(col, "Pamphlet_Title", M("ink"), line, size, at=(0, 0.025 - i * 0.016, top), rotate=flat)
    ring(col, "Pamphlet_Seal", M("marine"), (0, -0.05), 0.02, top, 0.001)
    ring(col, "Pamphlet_SealInner", M("marine"), (0, -0.05), 0.012, top, 0.0008)
    text(col, "Pamphlet_Date", M("ink"), "MARCH 1989", 0.0065, at=(0, -0.095, top), rotate=flat)
    for y in (-0.055, 0.055):
        box(col, "Pamphlet_Staple", M("galvanised"), (0.002, 0.018, 0.0006), at=(-width / 2 + 0.006, y, height))
