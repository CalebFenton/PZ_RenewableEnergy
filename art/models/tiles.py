"""What each tile of renewable_energy_01 and renewable_energy_02 shows, built from the item builders.

The index of each entry is the tile's number, from tile_numbers.py, the one record of them. A tile
is a list of layers. A layer marked `holdout` is drawn invisible: an overlay tile renders the object
it sits on that way, so it keeps only the pixels the object doesn't hide.

Tile coordinates are a square one metre wide centred on the origin: its north edge is y = +0.5 and
its west edge x = -0.5 (see the harness's lib/art/kit.py).
"""
import batteries
import biogas
import electronics
import solar
import wind
import woodgas
from art.kit import FACING_TURN
from art.render import layer
from tile_numbers import (BARREL_DIGESTERS, BARREL_HOLDERS, BATTERY_LOOKS, CRACKS, CRATE_CLOSED, CRATE_FULL, DIGESTERS,
                          DIRECTIONS, DOME_DIGESTER, DRUM_HOLDER, DRUM_LEVELS, FACINGS, FLAT_SNOW, GARDEN_LIGHT,
                          GARDEN_LIGHT_LIT, GAS_KIT, GASIFIER_PIPE, GASIFIERS, GENERATOR_BODIES, GENERATOR_KIT_FIRST,
                          GENERATOR_PIPE, GENERATOR_PIPE_FIRST, HEATER, HEATER_LIT, HOLDER_FILLS, HOMEMADE_MODULES,
                          INSULATED_DIGESTER, METER_LEVELS, MOUNTS, RACK_SLOTS, SCOOP_ROTOR, SCRUBBERS, SOLAR_CELL_CHARGER,
                          SOLAR_CRATE, SOLAR_FAILSAFE, SOLAR_FLAT, SOUR_FOAM, SPENT_SCRUBBERS, STORAGE_CAPACITY,
                          STORAGE_TILES, TIMBER_SCOOP, TURNED_HEATER_FIRST, TURNED_STORAGE_FIRST, TURNED_STORAGE_OVERLAYS,
                          WIND_TILES)


def _turned(at, facing):
    """`at` turned about the square's centre as FACING_TURN turns an object to face `facing`."""
    x, y, z = at
    return {"S": (x, y, z), "E": (-y, x, z), "N": (-x, -y, z), "W": (y, -x, z)}[facing]


# A wall panel's bottom edge, above the floor.
WALL_PANEL_HEIGHT = 1.1


def _wall(material, facing, cracks=False, light_cracks=False, cover=False):
    """On the square's north edge facing south, or on its west edge facing east. `cracks` makes the
    overlay of the cracks in its glass, the light ones with `light_cracks`; `cover` that of a
    homemade module in place of its factory one."""
    at = (0, 0.5, WALL_PANEL_HEIGHT) if facing == "S" else (-0.5, 0, WALL_PANEL_HEIGHT)
    turn = FACING_TURN[facing]
    if cracks or cover:
        shows = {"cover": True} if cover else {"cracks": True, "light_cracks": light_cracks}
        return [layer(solar.solar_wall, holdout=True, material=material, at=at, turn=turn),
                layer(solar.solar_wall, material=material, at=at, turn=turn, **shows)]
    return [layer(solar.solar_wall, material=material, at=at, turn=turn)]


def _rack(material, facing, snow=False, cracks=None, light_cracks=False, cover=None):
    """`snow` makes the overlay of the snow on it, `cracks` (a module slot) that of the cracks in
    one module's glass, the light ones with `light_cracks`, and `cover` (a slot) that of a homemade
    module in place of that slot's factory one."""
    turn = FACING_TURN[facing]
    if snow or cracks or cover:
        shows = {"cover": cover} if cover else {"snow": snow, "cracks": cracks, "light_cracks": light_cracks}
        return [layer(solar.solar_rack, holdout=True, material=material, turn=turn),
                layer(solar.solar_rack, material=material, turn=turn, **shows)]
    return [layer(solar.solar_rack, material=material, turn=turn)]


def _overlay(build, at=(0, 0, 0), turn=0, **options):
    return [layer(build, holdout=True, at=at, turn=turn), layer(build, frame=False, at=at, turn=turn, **options)]


def _battery_overlay(build, at, turn, slot, look):
    """The battery in `slot` (from 0) as `look`, and its link to the one before. A bank draws its
    batteries' overlays in slot order, so this one keeps out from behind the storage and the
    batteries in the slots before it, and draws over any in front of it. That holds in every
    facing: a battery behind an earlier one is cut where that one hides it."""
    return [layer(build, holdout=True, at=at, turn=turn), layer(build, holdout=True, frame=False, batteries=slot, at=at, turn=turn),
            layer(build, frame=False, slot=slot, look=look, at=at, turn=turn)]


TILES = {
    SOLAR_FLAT: [layer(solar.solar_flat)],
    # The failsafe shares the generator's square, so it sits in the corner nearest the viewer's
    # left, where the generator doesn't cover it.
    SOLAR_FAILSAFE: [layer(electronics.solar_failsafe, at=(-0.28, -0.3, 0), turn=-20)],
    SOLAR_CELL_CHARGER: [layer(electronics.solar_cell_charger, turn=-15)],
    SOLAR_CRATE: [layer(solar.solar_crate)],
    CRATE_FULL: _overlay(solar.solar_crate, contents=True),
    CRATE_CLOSED: _overlay(solar.solar_crate, closed=True),
    GARDEN_LIGHT: [layer(solar.solar_garden_light, stake=False)],
    GARDEN_LIGHT_LIT: [layer(solar.solar_garden_light, stake=False, lit=True)],
    FLAT_SNOW: [layer(solar.solar_flat, holdout=True), layer(solar.solar_flat, snow=True)],
}
for material, first_wall, first_rack, first_snow in MOUNTS:
    for offset, facing in enumerate("SE"):
        TILES[first_wall + offset] = _wall(material, facing)
    for offset, facing in enumerate(FACINGS):
        TILES[first_rack + offset] = _rack(material, facing)
        TILES[first_snow + offset] = _rack(material, facing, snow=True)
# Cracked glass by look: a flat panel's, a wall panel's per facing, and a rack's per facing and
# module slot.
for look, flat, mounts in CRACKS:
    light = look == "light"
    TILES[flat] = [layer(solar.solar_flat, holdout=True), layer(solar.solar_flat, cracks=True, light_cracks=light)]
    for material, (first_wall, first_rack) in mounts.items():
        for offset, facing in enumerate("SE"):
            TILES[first_wall + offset] = _wall(material, facing, cracks=True, light_cracks=light)
        for offset, facing in enumerate(FACINGS):
            for slot in range(1, RACK_SLOTS + 1):
                TILES[first_rack + RACK_SLOTS * offset + slot - 1] = _rack(material, facing, cracks=slot, light_cracks=light)

# A homemade module in place of a mount's factory one, laid out as the cracks are.
flat, mounts = HOMEMADE_MODULES
TILES[flat] = [layer(solar.solar_flat, holdout=True), layer(solar.solar_flat, cover=True)]
for material, (first_wall, first_rack) in mounts.items():
    for offset, facing in enumerate("SE"):
        TILES[first_wall + offset] = _wall(material, facing, cover=True)
    for offset, facing in enumerate(FACINGS):
        for slot in range(1, RACK_SLOTS + 1):
            TILES[first_rack + RACK_SLOTS * offset + slot - 1] = _rack(material, facing, cover=slot)

# Battery storage. Battery overlay n of a look shows a battery of that look in slot n; meter
# overlay n shows n LEDs lit. The car batteries' overlays are the tiles that once showed n batteries
# of any type, which a save may still have on a bank.
# Storage stands at the back of its square, as the game's own shelves and cabinets do, so that
# against a wall on the square's north edge it stands against the wall: this far north of the
# centre, which leaves a box's propped lid and a rack's back brace just short of the edge.
STORAGE_NORTH = {"BatteryBoxWood": 0.18, "BatteryBoxMetal": 0.18, "BatteryRackWood": 0.22, "BatteryRackMetal": 0.22,
                 "BatteryBankWood": 0.22, "BatteryBankMetal": 0.22}


def _storage(item, facing):
    """A storage's tile facing `facing`, its battery overlays by look, each a list by slot, and its
    meter overlays by level."""
    build, at, turn = batteries.STORAGE[item], _turned((0, STORAGE_NORTH[item], 0), facing), FACING_TURN[facing]
    overlays = {look: [_battery_overlay(build, at, turn, slot, look) for slot in range(STORAGE_CAPACITY[item])]
                for look in BATTERY_LOOKS}
    meter = [_overlay(build, at, turn, meter_level=level) for level in range(1, METER_LEVELS + 1)]
    return [layer(build, at=at, turn=turn)], overlays, meter


for item, base, first_batteries, first_meter in STORAGE_TILES:
    TILES[base], overlays, meter = _storage(item, "S")
    for look, first_battery in zip(BATTERY_LOOKS, first_batteries):
        for slot, overlay in enumerate(overlays[look]):
            TILES[first_battery + slot] = overlay
    for level, overlay in enumerate(meter):
        TILES[first_meter + level] = overlay

# The storage in all four facings, which the placing cursor turns it through as it does the game's
# furniture. The cursor finds a facing's tile by its number in the same tileset, at most 96 away
# (ISMoveableSpriteProps.getFaces, IsoWorld.SetCustomPropertyValues), and the tiles above, which a
# save's storage stands on, have no free numbers that near. So each storage has four tiles from
# TURNED_STORAGE_FIRST, its S one drawn as the tile above and taking its overlays; the other
# facings' overlays are renewable_energy_02's.
TILES_02 = {}
for f, facing in enumerate(FACINGS):
    for i, (item, *_) in enumerate(STORAGE_TILES):
        TILES[TURNED_STORAGE_FIRST + len(FACINGS) * i + f], overlays, meter = _storage(item, facing)
        if facing == "S":
            continue
        numbers, meter_numbers = TURNED_STORAGE_OVERLAYS[facing, item]
        for look in BATTERY_LOOKS:
            TILES_02.update(zip(numbers[look], overlays[look]))
        TILES_02.update(zip(meter_numbers, meter))

# Biogas digesters: a base tile each, then their gas holders' overlays. The barrel digester has a tile
# for each of the game's drums it may be built from (Sprites.digester.barrel); its holder overlays fit
# them all, which share one outline, and find the Metal Drum's, the builder's default, as their base.
# Level n of a holder shows it that full, from slack to taut; the insulated digester's shows its
# floating drum risen to n.
for look, index in BARREL_DIGESTERS.items():
    TILES[index] = [layer(biogas.barrel_digester)] if look == "MetalDrum" else [layer(biogas.barrel_digester, look=look)]
TILES[INSULATED_DIGESTER] = [layer(biogas.insulated_digester)]
TILES[DOME_DIGESTER] = [layer(biogas.dome_digester)]
for holder, first in BARREL_HOLDERS.items():
    for fill in range(1, HOLDER_FILLS + 1):
        TILES[first + fill - 1] = _overlay(biogas.barrel_digester, holder=holder, fill=fill)
    TILES[first + HOLDER_FILLS] = _overlay(biogas.barrel_digester, holder=holder, torn=True)
for level in range(1, DRUM_LEVELS + 1):
    TILES[DRUM_HOLDER + level - 1] = _overlay(biogas.insulated_digester, level=level)
# Each digester's scrubber, drawn over its tile, working and then spent; and the foam a sour
# digester heaves out of its funnel.
for offset, digester in enumerate(DIGESTERS):
    build = getattr(biogas, digester + "_digester")
    TILES[SCRUBBERS + offset] = _overlay(build, scrubber=True)
    TILES[SPENT_SCRUBBERS + offset] = _overlay(build, scrubber=True, spent=True)
    TILES[SOUR_FOAM + offset] = _overlay(build, sour=True)

# The gas heater, off and lit, then turned as the storage turns.
TILES[HEATER] = [layer(biogas.gas_heater)]
TILES[HEATER_LIT] = [layer(biogas.gas_heater, lit=True)]
for s, lit in enumerate((False, True)):
    for f, facing in enumerate(FACINGS):
        TILES[TURNED_HEATER_FIRST + len(FACINGS) * s + f] = [layer(biogas.gas_heater, lit=lit, turn=FACING_TURN[facing])]

# The gas kit fitted to a generator: an overlay on the game's own generator tiles, so it has no
# base of the mod's to hold out. The first lies on the floor at the front corner of a generator the
# game doesn't know; from GENERATOR_KIT_FIRST, one sits on the air intake of each of the game's
# generator bodies in each facing.
TILES[GAS_KIT] = [layer(biogas.generator_gas_kit)]
for b, (body, *_) in enumerate(GENERATOR_BODIES):
    for f, facing in enumerate(DIRECTIONS):
        TILES[GENERATOR_KIT_FIRST + len(DIRECTIONS) * b + f] = [layer(biogas.generator_gas_kit, body=body, facing=facing)]

# Gasifiers: each tier's tile, then its lit overlay. The pipe overlays on its square, one by the
# direction of the generator they run to, rise off the filter's outlet, which is in one place in
# every tier; the preview draws them over the drum's. The pipe's other half lies on the generator's
# square with the kit, one by the direction of the gasifier it comes from: four for a generator the
# game doesn't know, then from GENERATOR_PIPE_FIRST four for each body and facing.
for tier, index in GASIFIERS.items():
    TILES[index] = [layer(woodgas.gasifier, tier=tier)]
    TILES[index + len(GASIFIERS)] = [layer(woodgas.gasifier, holdout=True, tier=tier), layer(woodgas.gasifier, frame=False, tier=tier, lit=True)]
for offset, side in enumerate(DIRECTIONS):
    TILES[GASIFIER_PIPE + offset] = [layer(woodgas.gasifier, holdout=True, tier="standard"),
                                     layer(woodgas.gasifier, frame=False, tier="standard", pipe=side)]
    TILES[GENERATOR_PIPE + offset] = [layer(woodgas.generator_gas_pipe, side=side)]
    for b, (body, *_) in enumerate(GENERATOR_BODIES):
        for f, facing in enumerate(DIRECTIONS):
            TILES[GENERATOR_PIPE_FIRST + len(DIRECTIONS) * (len(DIRECTIONS) * b + f) + offset] = [
                layer(woodgas.generator_gas_pipe, side=side, body=body, facing=facing)]

# The scoop rotor wind charger as a tile: what the object is and how the build menu shows it. In
# play the game draws its sprite model (wind.SPRITE_MODELS) instead, and spins that. The one on a
# wooden frame, guyed out past its square, shrunk to fit as the blade machines are.
TILES[SCOOP_ROTOR] = [layer(wind.scoop_rotor)]
TILES[TIMBER_SCOOP] = [layer(wind.timber_scoop_rotor, scale=0.65)]

# The blade machines, each facing's tile its sprite model's first spin step. They stand taller than
# a tile's sprite can draw, so the tiles show them shrunk to fit, whole; in play the game draws
# their sprite models at full size.
WIND_TILE_SCALE = {"Propeller": 0.55, "CarAlternator": 0.55, "TimberPropeller": 0.55, "TimberCarAlternator": 0.55, "Alternator": 0.48}
for first, model, blades in WIND_TILES:
    for offset, facing in enumerate(DIRECTIONS):
        TILES[first + offset] = [layer(wind.SPRITE_MODELS[model]["model"], turn=FACING_TURN[facing], scale=WIND_TILE_SCALE[model],
                                       blades=blades)]

# Each tileset's tiles by number.
TILESETS = {"renewable_energy_01": TILES, "renewable_energy_02": TILES_02}

# Build-menu icons by the name after RenewableEnergy_Build_: each digester as it stands built and
# working, its holder full, each gasifier and each wind charger; a bladed charger's head on the top
# of its mast (BUILD_ICON_MAST metres of it), since its whole mast leaves the head a smudge on 48 px,
# turned BUILD_ICON_TURN degrees for its rotor to open out towards the camera.
BUILD_ICON_MAST = 0.6
BUILD_ICON_TURN = 30
BUILD_ICONS = {
    "BarrelDigester": [layer(biogas.barrel_digester, holder="bags")],
    "InsulatedDigester": [layer(biogas.insulated_digester, level=3)],
    "BrickDome": [layer(biogas.dome_digester)],
    "PrimitiveGasifier": [layer(woodgas.gasifier, tier="primitive")],
    "Gasifier": [layer(woodgas.gasifier, tier="standard")],
    "AdvancedGasifier": [layer(woodgas.gasifier, tier="advanced")],
    "ScoopRotor": [layer(wind.scoop_rotor)],
    "TimberScoop": [layer(wind.timber_scoop_rotor, guys=False)],
    "Propeller": [layer(wind.propeller_charger, turn=BUILD_ICON_TURN, stub=BUILD_ICON_MAST)],
    "CarAlternator": [layer(wind.car_alternator_charger, turn=BUILD_ICON_TURN, stub=BUILD_ICON_MAST)],
    "TimberPropeller": [layer(wind.timber_propeller_charger, turn=BUILD_ICON_TURN, stub=BUILD_ICON_MAST)],
    "TimberCarAlternator": [layer(wind.timber_car_alternator_charger, turn=BUILD_ICON_TURN, stub=BUILD_ICON_MAST)],
    "Alternator": [layer(wind.alternator_charger, turn=BUILD_ICON_TURN, stub=BUILD_ICON_MAST)],
}
