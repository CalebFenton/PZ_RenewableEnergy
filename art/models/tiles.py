"""What each tile of renewable_energy_01 and renewable_energy_02 shows, built from the item builders.

The index of each entry is the tile's number. The numbers tools/make_tiles.py gives properties too
are in tile_numbers.py; the overlays' are here alone. A tile is a list of layers. A layer marked
`holdout` is drawn invisible: an overlay tile renders the object it sits on that way, so it keeps
only the pixels the object doesn't hide.

Tile coordinates are a square one metre wide centred on the origin: its north edge is y = +0.5 and
its west edge x = -0.5 (see kit.py).
"""
import batteries
import biogas
import electronics
import solar
import wind
import woodgas
from kit import FACING_TURN
from tile_numbers import (BARREL_DIGESTERS, DOME_DIGESTER, FACINGS, GARDEN_LIGHT, GARDEN_LIGHT_LIT, GASIFIERS, HEATER,
                          HEATER_LIT, INSULATED_DIGESTER, MOUNTS, SCOOP_ROTOR, SOLAR_CELL_CHARGER, SOLAR_CRATE, SOLAR_FAILSAFE,
                          SOLAR_FLAT, STORAGE_TILES, TURNED_HEATER_FIRST, TURNED_STORAGE_FIRST, WIND_TILES)


def layer(build, holdout=False, at=(0, 0, 0), turn=0, scale=1, **options):
    return {"build": build, "options": options, "at": at, "turn": turn, "scale": scale, "holdout": holdout}


def _turned(at, facing):
    """`at` turned about the square's centre as FACING_TURN turns an object to face `facing`."""
    x, y, z = at
    return {"S": (x, y, z), "E": (-y, x, z), "N": (-x, -y, z), "W": (y, -x, z)}[facing]


# A wall panel's bottom edge, above the floor.
WALL_PANEL_HEIGHT = 1.1


def _wall(material, facing, cracks=False, light_cracks=False):
    """On the square's north edge facing south, or on its west edge facing east. `cracks` makes the
    overlay of the cracks in its glass, the light ones with `light_cracks`."""
    at = (0, 0.5, WALL_PANEL_HEIGHT) if facing == "S" else (-0.5, 0, WALL_PANEL_HEIGHT)
    turn = FACING_TURN[facing]
    if cracks:
        return [layer(solar.solar_wall, holdout=True, material=material, at=at, turn=turn),
                layer(solar.solar_wall, material=material, cracks=True, light_cracks=light_cracks, at=at, turn=turn)]
    return [layer(solar.solar_wall, material=material, at=at, turn=turn)]


def _rack(material, facing, snow=False, cracks=None, light_cracks=False):
    """`snow` makes the overlay of the snow on it, `cracks` (a module slot) that of the cracks in
    one module's glass, the light ones with `light_cracks`."""
    turn = FACING_TURN[facing]
    if snow or cracks:
        return [layer(solar.solar_rack, holdout=True, material=material, turn=turn),
                layer(solar.solar_rack, material=material, snow=snow, cracks=cracks, light_cracks=light_cracks, turn=turn)]
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
    12: _overlay(solar.solar_crate, contents=True),
    13: _overlay(solar.solar_crate, closed=True),
    GARDEN_LIGHT: [layer(solar.solar_garden_light, stake=False)],
    GARDEN_LIGHT_LIT: [layer(solar.solar_garden_light, stake=False, lit=True)],
    16: [layer(solar.solar_flat, holdout=True), layer(solar.solar_flat, snow=True)],
    115: [layer(solar.solar_flat, holdout=True), layer(solar.solar_flat, cracks=True)],
    376: [layer(solar.solar_flat, holdout=True), layer(solar.solar_flat, cracks=True, light_cracks=True)],
}
for material, first_wall, first_rack, first_snow in MOUNTS:
    for offset, facing in enumerate("SE"):
        TILES[first_wall + offset] = _wall(material, facing)
    for offset, facing in enumerate(FACINGS):
        TILES[first_rack + offset] = _rack(material, facing)
        TILES[first_snow + offset] = _rack(material, facing, snow=True)
# Cracked glass, heavy then light (RenewableEnergy.crackLookOf): a wall panel's per facing, and a
# rack's per facing and module slot, slot 1 first.
for light, metal_wall, metal_rack, wood_wall, wood_rack in ((False, 116, 120, 118, 128), (True, 377, 381, 379, 389)):
    for material, first_wall, first_rack in (("metal", metal_wall, metal_rack), ("wood", wood_wall, wood_rack)):
        for offset, facing in enumerate("SE"):
            TILES[first_wall + offset] = _wall(material, facing, cracks=True, light_cracks=light)
        for offset, facing in enumerate(FACINGS):
            for slot in (1, 2):
                TILES[first_rack + 2 * offset + slot - 1] = _rack(material, facing, cracks=slot, light_cracks=light)

# Battery storage. Battery overlay n of a look shows a battery of that look in slot n; meter
# overlay n shows n LEDs lit. The car batteries' overlays are the tiles that once showed n batteries
# of any type, which a save may still have on a bank.
STORAGE_CAPACITY = {"BatteryBoxWood": 2, "BatteryBoxMetal": 2, "BatteryRackWood": 6, "BatteryRackMetal": 8,
                    "BatteryBankWood": 12, "BatteryBankMetal": 16}
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
                for look in batteries.BANK_BATTERY_LOOKS}
    return [layer(build, at=at, turn=turn)], overlays, [_overlay(build, at, turn, meter_level=level) for level in range(1, 6)]


for item, base, first_batteries, first_meter in STORAGE_TILES:
    TILES[base], overlays, meter = _storage(item, "S")
    for look, first_battery in zip(batteries.BANK_BATTERY_LOOKS, first_batteries):
        for slot, overlay in enumerate(overlays[look]):
            TILES[first_battery + slot] = overlay
    for level, overlay in enumerate(meter):
        TILES[first_meter + level] = overlay

# The storage in all four facings, which the placing cursor turns it through as it does the game's
# furniture. The cursor finds a facing's tile by its number in the same tileset, at most 96 away
# (ISMoveableSpriteProps.getFaces, IsoWorld.SetCustomPropertyValues), and the tiles above, which a
# save's storage stands on, have no free numbers that near. So each storage has four tiles from
# TURNED_STORAGE_FIRST, its S one drawn as the tile above and taking its overlays. The other
# facings' overlays fill renewable_energy_02 facing by facing, storage by storage: each look's
# batteries by slot, then the meter where it shows. The meter is on the storage's front, which the
# camera, from the south-east, sees only facing S or E; facing N or W the storage hides every LED.
METER_FACINGS = "SE"
TILES_02 = {}
for f, facing in enumerate(FACINGS):
    for i, (item, *_) in enumerate(STORAGE_TILES):
        TILES[TURNED_STORAGE_FIRST + len(FACINGS) * i + f], overlays, meter = _storage(item, facing)
        if facing == "S":
            continue
        for look in batteries.BANK_BATTERY_LOOKS:
            for overlay in overlays[look]:
                TILES_02[len(TILES_02)] = overlay
        for overlay in meter if facing in METER_FACINGS else ():
            TILES_02[len(TILES_02)] = overlay

# Biogas digesters: a base tile each, then their gas holders' overlays. The barrel digester has a tile
# for each of the game's drums it may be built from (Sprites.digester.barrel); its holder overlays fit
# them all, which share one outline, and find the Metal Drum's, the builder's default, as their base.
# Level n of a holder shows it that full, from slack to taut; the insulated digester's shows its
# floating drum risen to n.
for look, index in BARREL_DIGESTERS.items():
    TILES[index] = [layer(biogas.barrel_digester)] if look == "MetalDrum" else [layer(biogas.barrel_digester, look=look)]
TILES[INSULATED_DIGESTER] = [layer(biogas.insulated_digester)]
TILES[DOME_DIGESTER] = [layer(biogas.dome_digester)]
for holder, first in (("bags", 232), ("tarp", 236)):
    for fill in (1, 2, 3):
        TILES[first + fill - 1] = _overlay(biogas.barrel_digester, holder=holder, fill=fill)
    TILES[first + 3] = _overlay(biogas.barrel_digester, holder=holder, torn=True)
for level in range(1, 5):
    TILES[239 + level] = _overlay(biogas.insulated_digester, level=level)
# The scrubber fitted to each digester, drawn over its tile.
TILES[247] = _overlay(biogas.barrel_digester, scrubber=True)
TILES[248] = _overlay(biogas.insulated_digester, scrubber=True)
TILES[249] = _overlay(biogas.dome_digester, scrubber=True)

# The gas heater, off and lit, then turned as the storage turns.
TILES[HEATER] = [layer(biogas.gas_heater)]
TILES[HEATER_LIT] = [layer(biogas.gas_heater, lit=True)]
for s, lit in enumerate((False, True)):
    for f, facing in enumerate(FACINGS):
        TILES[TURNED_HEATER_FIRST + len(FACINGS) * s + f] = [layer(biogas.gas_heater, lit=lit, turn=FACING_TURN[facing])]

# The gas kit fitted to a generator: an overlay on the game's own generator tiles, so it has no
# base of the mod's to hold out. The first lies on the floor at the front corner of a generator the
# game doesn't know; from GENERATOR_KIT_FIRST, one sits on the air intake of each of the game's
# generator bodies in each facing (Sprites.generatorFittings).
GENERATOR_KIT_FIRST = 280
GENERATOR_PIPE_FIRST = GENERATOR_KIT_FIRST + 4 * len(biogas.GENERATOR_BODIES)
TILES[246] = [layer(biogas.generator_gas_kit)]
for b, body in enumerate(biogas.GENERATOR_BODIES):
    for f, facing in enumerate("NESW"):
        TILES[GENERATOR_KIT_FIRST + 4 * b + f] = [layer(biogas.generator_gas_kit, body=body, facing=facing)]

# Gasifiers: each tier's tile, then its lit overlay. The pipe overlays on its square, one by the
# direction of the generator they run to, rise off the filter's outlet, which is in one place in
# every tier; the preview draws them over the drum's. The pipe's other half lies on the generator's
# square with the kit, one by the direction of the gasifier it comes from: four for a generator the
# game doesn't know, then from GENERATOR_PIPE_FIRST four for each body and facing.
for tier, index in GASIFIERS.items():
    TILES[index] = [layer(woodgas.gasifier, tier=tier)]
    TILES[index + len(GASIFIERS)] = [layer(woodgas.gasifier, holdout=True, tier=tier), layer(woodgas.gasifier, frame=False, tier=tier, lit=True)]
for offset, side in enumerate("NESW"):
    TILES[256 + offset] = [layer(woodgas.gasifier, holdout=True, tier="standard"),
                           layer(woodgas.gasifier, frame=False, tier="standard", pipe=side)]
    TILES[260 + offset] = [layer(woodgas.generator_gas_pipe, side=side)]
    for b, body in enumerate(biogas.GENERATOR_BODIES):
        for f, facing in enumerate("NESW"):
            TILES[GENERATOR_PIPE_FIRST + 16 * b + 4 * f + offset] = [layer(woodgas.generator_gas_pipe, side=side, body=body, facing=facing)]

# The scoop rotor wind charger as a tile: what the object is and how the build menu shows it. In
# play the game draws its sprite model (wind.SPRITE_MODELS) instead, and spins that.
TILES[SCOOP_ROTOR] = [layer(wind.scoop_rotor)]

# The blade machines, each facing's tile its sprite model's first spin step. They stand taller than
# a tile's sprite can draw, so the tiles show them shrunk to fit, whole; in play the game draws
# their sprite models at full size.
WIND_TILE_SCALE = {"Propeller": 0.55, "CarAlternator": 0.55, "Alternator": 0.48}
for first, model, blades in WIND_TILES:
    for offset, facing in enumerate("NESW"):
        TILES[first + offset] = [layer(wind.SPRITE_MODELS[model]["model"], turn=FACING_TURN[facing], scale=WIND_TILE_SCALE[model],
                                       blades=blades)]

# Each tileset's tiles by number.
TILESETS = {"renewable_energy_01": TILES, "renewable_energy_02": TILES_02}

# Build-menu icons by the name after RenewableEnergy_Build_: each digester as it stands built and
# working, its holder full, each gasifier and each wind charger.
BUILD_ICONS = {
    "BarrelDigester": [layer(biogas.barrel_digester, holder="bags")],
    "InsulatedDigester": [layer(biogas.insulated_digester, level=3)],
    "BrickDome": [layer(biogas.dome_digester)],
    "PrimitiveGasifier": [layer(woodgas.gasifier, tier="primitive")],
    "Gasifier": [layer(woodgas.gasifier, tier="standard")],
    "AdvancedGasifier": [layer(woodgas.gasifier, tier="advanced")],
    "ScoopRotor": [layer(wind.scoop_rotor)],
    "Propeller": [layer(wind.propeller_charger)],
    "CarAlternator": [layer(wind.car_alternator_charger)],
    "Alternator": [layer(wind.alternator_charger)],
}
