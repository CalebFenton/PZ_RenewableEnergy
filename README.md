# ![Renewable Energy](art/promo/images/banner.png)

Sooner or later the grid goes down, and sooner or later the gas runs out too. The pumps in Knox County hold what they hold and nobody's coming to refill them. A generator buys you time, but it's loud, it fills the house with fumes if you run it inside, and it eats scrap electronics to keep going.

Renewable Energy is the other option: the solar gear a Kentucky household, farm or RV owner could have owned in 1993. You start with a car battery in a wooden box and an inverter that plugs into a lighter socket, which is enough for the TV, your tapes and a lamp. A few months later there's a room full of L-16s, a yard of panels, and a generator you only start when it's been cloudy all week.

Requires Build 42.20 or newer. I've tested it in single player on 42.21.0. It loads on a dedicated server, and the server owns the banks, but nobody has played it with clients connected yet.

## How it plays

| When | What you're after | What it takes |
|---|---|---|
| Before the grid goes | Stocking up | Charge every battery you own with a car battery charger while the power's still on |
| The first weeks | The TV, a lamp, a mini fridge | A battery box, two car batteries and a Plug-in Inverter, plus a panel or two or a couple of hours of generator a day |
| Weeks 3 to 6 | The kitchen fridge | A battery rack of deep cycle batteries, a Power Inverter and 4 to 6 panels |
| Months 2 and 3 | Fridge and freezer all year, the washer, the microwave | A battery bank, L-16s, an Inverter/Charger, a failsafe on the generator, 10 to 14 panels |
| After that | The electric range and the dryer | A metal bank with two Inverter/Chargers and 20 to 30 panels |

Panels are what you'll spend the game chasing. You find a few, you fix the cracked ones, and eventually you build your own out of whatever has solar cells in it.

## How real is it?

Real where that's fun, gamey where it isn't.

The sun moves the way it does over Knox County. The mod works out its height and direction from the in-game date and time at 38° north, and I checked the output against sunlight measured at Louisville between 1961 and 1990. You start in July, when that's easy. By December a flat panel makes less than a third of what it did in July. Overcast lets through about a quarter of the light, and fog and rain take more. Snow piles up on flat panels until it melts or you go out with a broom.

The hardware is the stuff they really sold then: 50 W modules, marine and L-16 batteries, inverters for RVs and cabins. Batteries wear out faster the harder you drain them, and a car battery hates it most because it was built to start an engine.

Some of it isn't realistic, on purpose:

- Panels make three times what they would have. Set **Sunlight Multiplier** to 1 for true 1993 output, when it took a yard full of panels to run one fridge.
- An inverter is just a number of watts. Put more on it than that and the bank shuts off until you switch something off. Real fridges kick hard when they start, and real systems care about voltage. This one doesn't.
- Cold doesn't hurt batteries. They live indoors anyway.
- The solar charger recharges flashlight batteries. In 1993 most of those were throwaway alkalines, but the game only has one kind.
- Sixteen calculators make a solar panel. A real calculator cell is about a thousandth of what this gives you credit for. It's meant to be a chore, so you'll go looking for garden lights instead.
- You can melt a worn battery's plates down at a furnace and cast new ones. Battery recyclers really do that, just not in somebody's backyard.

One thing fell out of the game by accident. Project Zomboid hangs wall objects on the north and west edges of a square, so a panel on an outside wall can only face south or east. Those are the walls you'd pick anyway.

## Install

It isn't on the Steam Workshop yet. Put this repository in `~/Zomboid/Workshop/RenewableEnergy`, start the game with Steam running, and enable **Renewable Energy** in the mod list.

## Getting started

<p align="center"><img src="art/promo/images/setup.png" alt="A wooden battery box with a car battery indoors, panels on the roof and the lawn, and a battery bank with wall panels and ground racks outside" width="100%"></p>

1. **Build a bank.** Battery boxes, racks and banks are furniture. Craft one, then place it like a chair: item in your main inventory, right-click, **Place Object**. It has to go indoors.
2. **Wire in the parts.** Right-click the bank and use **Wire In** for each battery, inverter, charge controller and car battery charger. Batteries take a wrench and the rest a screwdriver, each one uses up some Electrical Wire, and you need enough light to see what you're doing. **Unwire** gives you the part and the wire back. You can't just drag parts in or out.
3. **Mount the panels.** A Solar Module is a loose panel. Craft it into a flat panel or a wall panel, or put two on a ground rack, and place it outside.
4. **Connect them.** Right-click the bank and pick **Connect Panels in Reach**, or right-click a panel and pick a bank. Panels have to be within 20 tiles and 3 floors of the bank.
5. **Turn it on.** From then on the bank powers everything a generator in its spot would.

Before you've got a bank, a **Solar Battery Maintainer** helps. It clips onto a parked car and keeps the battery topped up, so the car radio and headlights become your first radio and lamp.

## Battery banks

<p align="center"><img src="art/promo/images/status.png" alt="The battery bank status window: whether it's charging or draining, the load against the inverters, panel slots, what's drawing power, each part and battery with its condition, and each panel with its watts and why it isn't at full sun" width="100%"></p>

Every size comes in wood or metal. Wood takes more carpentry than metal takes welding, since planks are easy to come by, so a good carpenter can build any of them. Metal holds a couple more batteries.

| | Wood needs | Metal needs | Batteries | Inverters | Chargers | Charge controllers |
|---|---|---|---|---|---|---|
| Battery Box | Electrical 1, Carpentry 1 | Electrical 1, Welding 1 | 2 | 1 | 1 | none |
| Battery Rack | Electrical 3, Carpentry 4 | Electrical 3, Welding 2 | 6 wood, 8 metal | 1 | 2 | 2 |
| Battery Bank | Electrical 4, Carpentry 7 | Electrical 4, Welding 4 | 12 wood, 16 metal | 2 | 2 | 4 |

Charge controllers decide how many panels a bank takes. Two panels are fine on their own, and each controller makes room for seven more.

The chargers are vanilla's Car Battery Chargers. Wired into a bank, each one puts in 250 W whenever grid power or a running generator reaches it, and the generator burns fuel for that. That's how you get through a grey week: run the generator for a couple of hours, shut it off, live on the batteries.

Right-click the bank and choose **Status** to see whether it's charging or draining and how long until it's full or empty, the load against what the inverters can carry, what's drawing it, how many panel slots are used, and every part and battery with its condition. Each panel gets a row with its watts, how close it is to full sun, and why it isn't: night, cloud, snow, a low winter sun, a crack, or no controller slot for it. Click a row and that panel lights up in the world. If you've got more than one bank, rename them. Right-clicking a panel tells you which bank it's wired to.

### Inverters

| Inverter | Carries | Draws while on |
|---|---|---|
| Plug-in Inverter | 150 W | 4 W |
| Power Inverter | 600 W | 8 W |
| Inverter/Charger | 2,500 W, and charges the bank at 1,500 W from a generator | 15 W |

A bank with two inverters can carry both ratings added together. If everything switched on in its reach adds up to more than that, the power cuts out and the status window shows what's drawing what. It comes back by itself once you've switched enough off. About 10% of what goes through an inverter is lost as heat.

The reach is a generator's: by default 20 tiles around the bank and 3 floors up and down, the neighbours' houses included. In town, most houses still have their lights switched on and a fridge plugged in, so a small bank there overloads before you've plugged anything in. Switch them off or smash them, or set up away from other houses.

### What things draw

| Appliance | Watts while running | Running |
|---|---|---|
| Fridge-freezer | 200 | about 40% of the time |
| Fridge or freezer | 160 | about 40% of the time |
| Mini fridge | 80 | half the time |
| Light | 60 | |
| TV | 65 | |
| Radio | 10 | |
| Microwave | 1,000 | |
| Washer | 500 | |
| Car battery charger | 100 | |
| Electric range | 2,000 | |
| Dryer | 4,000 | |

The inverter has to carry the running watts. The batteries only pay for the time the compressor is actually on. So a Plug-in Inverter runs the TV and a lamp, or a mini fridge, but not the kitchen fridge. Anything else that runs off a generator draws in proportion to the fuel vanilla would burn for it.

### Batteries

| Battery | Capacity | Cycles at 50% a day | Weight |
|---|---|---|---|
| Car battery (vanilla) | 600 Wh | 80 | 5 |
| Deep Cycle Marine Battery | 1,260 Wh | 1,000 | 8 |
| L-16 Battery | 2,100 Wh | 1,200 | 16 |

Every day the bank wears each battery by how deep it drained that day, and depth counts double: a deep cycle battery taken down 80% every day lasts about 400 days, at 50% about 1,000, at 25% about 4,000. Run a car battery down halfway every day and it's done in under three months. A car battery that stays in its car doesn't wear at all. Batteries you find hold 30 to 80% of a charge.

The deep cycle battery also fits a car. Open the mechanics window, pick the empty battery slot and install it. It holds about twice what a car battery does, so the radio and headlights run about twice as long with the engine off, and it takes twice as long to fill back up from the alternator. The L-16 won't go in a car. It's 6 volts and weighs as much as a big dog.

### Keeping batteries alive

| Repair | Needs | Does |
|---|---|---|
| Service Battery | Electrical 1, half a litre of water, a rag or baking soda | +10 condition, up to 60% |
| Recondition Battery | Electrical 3, a litre of water, baking soda | Back to 85%, but it comes out flat |
| Rebuild | Electrical 5, a furnace, a battery plate mold, Blacksmithing 3 for the plates | Back to 100%, also flat |

Rebuilding takes three steps. Strip the battery with a wrench, a screwdriver and a pair of gloves, pouring its acid into empty jars or bottles: a litre for a car battery, two for a deep cycle, three for an L-16. Melt the worn plates down at a furnace with 4 charcoal and cast new ones in a Battery Plate Mold. Then put the plates back in the case, pour the same acid back in and top it up with half a litre of water. Charcoal is the only thing used up, so a battery you look after lasts as long as you play. Spill the acid and you'll need Battery Electrolyte, which auto parts stores sold by the litre.

The mold is made the way vanilla's ingot molds are. Cut a wooden pattern, press clay over it at a hand press and fire it in a kiln.

### Parts wear too

Inverters and charge controllers lose a little condition while they run, and a bit more every time you overload them. Fix them with Electronics Scrap from the bank's menu, the way you'd fix a generator. At 0 they stop working until you do.

### Backup generator and failsafe

A vanilla generator plugged in within 3 tiles of the bank, on the same floor, is its backup. While it runs it carries the load and the batteries rest, and the bank's chargers fill them. Put a **Solar Failsafe** on the generator's square and the bank starts the generator when it drops below 20% and shuts it off at 80%. Both numbers are sandbox options. The generator still needs fuel, and it won't start below 20% condition.

## Panels

What a panel makes depends on the sun's height, the season, clouds, fog, rain and falling snow. The three mounts behave differently over the year:

| Mount | Modules | Year, compared to a rack | Snow | Goes |
|---|---|---|---|---|
| Solar Ground Rack | 2, tilted 38° | 100% | Slides off within a couple of hours of sun, or once it's above −2 °C | On the ground or a flat roof, facing any way. It blocks the square. |
| Flat Solar Panel | 1 | 90% | Stays until it melts. Right-click and **Clear Snow** with a broom or snow shovel. | On a roof or the ground |
| Wall-Mounted Solar Panel | 1, upright | 66% facing south, 57% east | Never | On an outside wall |

Flat panels are great in summer and bad in winter. Wall panels are the opposite: in December a south wall makes about twice what a flat panel does, and more again with snow on the ground bouncing light up at it. On a clear day at the default multiplier, one module makes:

| Module on | Noon, July | Whole day, July | Whole day, December |
|---|---|---|---|
| A ground rack, facing south | 110 W | 0.85 kWh | 0.6 kWh |
| A flat panel | 115 W | 1 kWh | 0.3 kWh |
| A south wall | 50 W | 0.3 kWh | 0.65 kWh |

For scale, a fridge-freezer uses about 1.9 kWh a day.

Wall panels and racks come in wood or metal, and both make the same power. The difference shows up in storms.

### Storms, cracks and repairs

A thunderstorm with a strong wind can crack a module. Wall panels never crack, metal mounts hold up better than flat panels, and wooden mounts crack twice as often. At the default setting, ten flat panels lose about one module every two or three months.

A module makes power in proportion to its condition, so a cracked one at 40% makes 20 W. **Repair Cracked Module** (Electrical 3) takes a glass pane, epoxy or two glue, and a piece of wire, and gives back 30 points, up to 80%. You can make glass panes yourself once you've learned glassmaking.

### Building your own

Anything with solar cells in it can be taken apart for them:

| Take apart | Solar Cells |
|---|---|
| Calculator | 1, plus Electronics Scrap |
| Solar Garden Light | 2 |
| Solar Battery Charger | 4 |
| Solar Battery Maintainer | 6 |
| A shattered module (0%) | 12 |

**Make Homemade Solar Module** (Electrical 4) takes 16 cells, a glass pane, a frame of 4 planks or a small steel sheet, epoxy or two glue, and 2 pieces of wire. It never gets better than 60%, so it makes 30 W, but it mounts and repairs like any other module.

## Garden lights

Solar garden lights charge in the sun and glow at night. Some houses have a row of them along the front walk. They're common in nice neighbourhoods, turn up now and then on ordinary streets and farms, and are rare in poor areas and trailer parks. Which houses have them is different every game. Pick them up and set them out at your own place, or take them apart for cells.

## Items

<p align="center"><img src="art/promo/images/items.png" alt="Inventory icons of every item in the mod and the vanilla car battery, with their names" width="100%"></p>

| Item | What it's for |
|---|---|
| Solar Module | A 50 W panel. Mount it flat or on a wall, or put two on a ground rack. |
| Homemade Solar Module | One you built from cells. Mounts like the real thing, tops out at 30 W. |
| Solar Cells | Taken out of calculators, garden lights and other solar gadgets, for homemade modules |
| Flat Solar Panel, Wall-Mounted Solar Panel, Solar Ground Rack | The mounts; walls and racks come in wood and metal |
| Battery Box, Battery Rack, Battery Bank | Where batteries and their parts go, each in wood and metal |
| Plug-in Inverter, Power Inverter, Inverter/Charger | See the inverter table |
| Charge Controller | Room for seven more panels on a bank |
| Solar Failsafe | Starts and stops the backup generator for you |
| Deep Cycle Marine Battery, L-16 Battery | See the battery table |
| Battery cases, Worn Battery Plates, Battery Plates, Battery Plate Mold, Battery Electrolyte | For rebuilding batteries |
| Solar Battery Maintainer | Clips onto a car and keeps its battery charged in daylight |
| Solar Battery Charger | Set it outdoors with 4 flashlight batteries in it, and they're charged in a sunny day or two |
| Solar Garden Light | A little light that charges by day and glows at night |
| Homestead Power #1: Sun & Batteries | Teaches the boxes, racks, mounts and module repair |
| Homestead Power #2: Inverters & Control | Teaches the banks, the charge controller, the failsafe, homemade modules, reconditioning and rebuilding |

## Crafting

<p align="center"><img src="art/promo/images/recipes.png" alt="Every recipe's inputs and result, with the skills it needs and how it is learned" width="100%"></p>

You need a table or counter nearby and enough light to see. Tools aren't used up.

| Recipes | Skills | Uses up |
|---|---|---|
| Wooden Battery Box, Rack, Bank | Electrical 1, 3, 4 and Carpentry 1, 4, 7 | 4, 6 or 10 Planks, Nails, Electrical Wire, Screws for the rack and bank |
| Metal Battery Box, Rack, Bank | Electrical 1, 3, 4 and Welding 1, 2, 4 | Steel sheets, Steel Rods for the rack and bank, Welding Torch uses, Electrical Wire, Screws |
| Flat Solar Panel | Electrical 2 | A module, 3 Electrical Wire, 4 Screws |
| Wooden and Metal Wall-Mounted Solar Panel | Electrical 3, Carpentry 3 or Welding 1 | A module, 2 Planks or 2 Steel Rods, Nails or Screws, 3 Electrical Wire |
| Wooden and Metal Solar Ground Rack | Electrical 3, Carpentry 4 or Welding 2 | 2 modules, 6 Planks or 4 Iron Pipes and a small steel sheet, Nails or Screws, 4 Electrical Wire |
| Unmount any mount | Electrical 1 | The mount. You get the modules back as they were, plus most of the materials. |
| Repair Cracked Module | Electrical 3 | A glass pane, epoxy or 2 glue, 1 Electrical Wire |
| Take apart a calculator, garden light, battery charger, maintainer or shattered module | Electrical 1 | The thing you take apart |
| Make Homemade Solar Module | Electrical 4 | 16 Solar Cells, a glass pane, a frame, epoxy or 2 glue, 2 Electrical Wire |
| Service and Recondition Battery | Electrical 1 and 3 | Water, a rag or baking soda |
| Strip, Recast Plates, Rebuild | Electrical 4, Blacksmithing 3, Electrical 5 | 4 charcoal per set of plates, and half a litre of water |
| Wooden Battery Plate Pattern, Battery Plate Mold | Carpentry 2, then a hand press and a kiln | A plank, nails, clay, fuel |
| Make Charge Controller | Electrical 5 | 6 Scrap Electronics, 2 Electrical Wire, a small steel sheet, an Amplifier, 4 Screws |
| Make Solar Failsafe | Electrical 3 | A long-range remote controller, 2 Scrap Electronics, 2 Electrical Wire |

Unmounting, taking things apart and servicing a battery don't need learning. Everything else you learn one of three ways:

- Read a Homestead Power magazine.
- Level up. Electrical 2 teaches the battery boxes, 3 the flat panel, 4 the battery racks and wall panels, 6 the whole battery rebuild.
- Research something you found. A Solar Module teaches the mounts, a Plug-in Inverter the battery boxes, a Power Inverter the racks, and an Inverter/Charger the banks and the failsafe.

The Solar Battery Maintainer, the Solar Battery Charger and the inverters can't be crafted. You have to find them.

## Where to look

Think about who had this stuff in 1993: people with campers and boats, farmers, electricians, the phone and power companies, road crews, and preppers.

| Item | Best places |
|---|---|
| Homestead Power #1 | Electronics store magazine racks (1 in 8), survivor caches and safehouse bookshelves, bookstores, hardware and camping stores. Ordinary homes too, about 1 living room shelf in 60. |
| Homestead Power #2 | Electrician vans (1 in 14), electronics store racks, radio, phone company and power company vans, survivor caches and safehouses. Also in homes, about half as often as #1. |
| Plug-in Inverter | Gas station emergency shelves, auto parts stores, campers, electronics stores (about 1 in 15 each), garages, and now and then a glove box |
| Solar Battery Maintainer | Auto parts store battery shelves (1 in 17), campers, farm tool cabinets, mechanics |
| Solar Battery Charger | Camping store and survivor safehouse lighting, electronics stores (about 1 in 16) |
| Solar Module | Survivor caches, camper trailers, campers, phone company, electrician and power company vans. Cracked ones are much more common: garages, sheds, junkyards, farm storage and electronics store back rooms. |
| Power Inverter | Camper trailers, auto parts stores, electrician vans, campers |
| Charge Controller | Power company and phone company vans, electrician vans, camper trailers, survivor caches |
| Deep Cycle Marine Battery | Auto parts store battery shelves, camper trailers, mechanics, battery plants |
| Inverter/Charger | Rare: phone company vans, survivor caches, control rooms, generator rooms |
| L-16 Battery | Rare: phone company vans, battery plants, power company vans, generator rooms |
| Battery Electrolyte | Auto parts stores, mechanics, battery plants |
| Solar Garden Light | Garden centers, hardware stores, sheds, garages, and the front walks of some houses |
| Solar Failsafe | Hardly ever found. Craft it. |

Some places come already set up, each with a chance of being there in a new world:

- Stock tank pumps out in the pastures, with a panel rack beside the trough.
- A few farmhouses with panels on the roof, a battery box inside and garden lights out front.
- Campers in the trailer parks and campgrounds, with panels on the roof and a deep cycle battery.
- The phone company's relay sheds at the radio masts, with racks of panels and L-16s.
- The Deer Valley Power yard west of Muldraugh, the best haul on the map.
- Ranger stations at Deerhead Lake and Doe Valley.
- Solar arrow boards: the orange trailers road crews park at work zones, with a flashing arrow and panels on top. They turn up at road works, in junkyards and in highway pileups, and their battery box holds a couple of modules, a row of deep cycle batteries and a charge controller. Strip it where it stands or hitch it to a car and tow it home.

Sheds, garages and storage units sometimes hold someone's homemade battery box, farm and electronics storage rooms a full rack, and garages and storage units a crate of modules.

If you turn on **Stash Houses** before starting a game, four places get stocked:

- A prepper's farmhouse on Crowcall Road, south of Rosewood, with a bunker under the shed. The doors are trapped. Its map only drops from survivalists and bandits.
- A mobile home in the Dixie trailer park that ran on solar. Its map can turn up on any body.
- A barn on Soretoe Road in Rosewood, marked on the town map.
- Dale's Electric on Oak Street in West Point, also on the town map.

Loot respawn never refills a battery bank, a battery charger or a solar crate.

## Sandbox options

All on the **Renewable Energy** page:

- **Sunlight Multiplier**, 1 to 5, default 3. At 1 you get what panels really made.
- **Charge Frequency**: banks update every ten minutes or every hour. They end up with the same charge either way.
- **Battery Wear**: how much wear batteries take, in percent. 0 turns it off.
- **Failsafe Start Charge** and **Failsafe Stop Charge**, 20% and 80%.
- **Solar Sites**: the chance each of the map's solar sites is there, 75%.
- **Garden Lights**: how often houses have them, in percent of the usual. 0 turns them off.
- **Battery Bank Spawn**: how often rooms come with a stocked bank or crate. None, Very Rare, Rare (default) or Uncommon.
- **Stash Houses**: off, maps only, or maps plus houses stocked from the start.
- **Loot Rarity Multiplier** for modules, for batteries, and for everything else. 0 takes them out of the loot.
- **Connect Panel Time**: minutes to connect a panel at Electrical 3.
- **Storm Damage** and **Storm Damage Rate**: whether storms crack modules, and how often.

The game's own loot sliders still apply on top (Other for the hardware, Recipe Resources for the magazines).

## What's next

Biogas. A drum of kitchen scraps and manure ferments into methane, an air mattress holds the gas, and you cook and light with it. Later a gas generator charges the bank at night through the Inverter/Charger.

## Development

[DEVELOPMENT.md](DEVELOPMENT.md) has the commands for testing the mod and rebuilding the art, plus notes on the Build 42 behavior it relies on. [AGENTS.md](AGENTS.md) has the rules. Rebuilding the art needs [Blender](https://www.blender.org/) and [uv](https://docs.astral.sh/uv/).

## Credits

By Caleb Fenton. Inspired by [Immersive Solar Arrays](https://github.com/radx5Blue/ImmersiveSolarArrays) by RadX5 and Poltergeist. Licensed under the Apache License 2.0, see [LICENSE](LICENSE).
