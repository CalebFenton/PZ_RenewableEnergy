# ![Renewable Energy](art/promo/images/banner.png)

Sooner or later the grid goes down. After that you either haul gas for a generator every few days, or you go out and find some solar gear.

Renewable Energy gives you the solar gear a Kentucky household, farm or RV owner could actually have owned in 1993. You start small: a car battery in a wooden box, one salvaged panel and a cheap inverter that plugs into a lighter socket. That's enough for a lamp and the radio. Later you'll have a rack of deep cycle batteries, a yard of tilted panels and a backup generator that starts itself when the batteries run low.

Requires Build 42.20 or newer. I've tested it in single player on 42.21.0. It loads on a dedicated server, and the server owns the banks, but nobody has played it with clients connected yet.

## How real is it?

More than it strictly needs to be. The sun moves the way it does over Knox County: the mod works out its height and direction from the in-game date and time at 38° north, and I checked the output against sunlight measured at Louisville between 1961 and 1990. You start in July, when that's easy. By December a flat panel makes less than a third of what it did in July.

Weather matters too. Overcast lets through about a quarter of the light, and fog and rain take more. Cells lose a little when they're hot, so a cold clear day in January does better per hour of sun than a sticky one in August. Snow piles up on flat panels and stays there until it melts or you go out with a broom.

The hardware is the stuff they really sold then: 50 W modules at about 12% efficiency, marine and L-16 batteries, inverters for RVs and cabins. Batteries wear out faster the harder you drain them, and a car battery hates it most because it was built to start an engine. Cold batteries hold less. Leave a flat one outside in a hard freeze and it can crack.

A fridge draws several times its running power for a second when the compressor kicks on. That spike is what trips a small inverter, even when the fridge's running watts would fit.

One thing fell out of the game by accident. Project Zomboid hangs wall objects on the north and west edges of a square, so a panel on an outside wall can only face south or east. Those are the walls you'd pick anyway.

Some of it isn't realistic, on purpose:

- Panels make three times what they would have by default. Set **Sunlight Multiplier** to 1 if you want true 1993 output, when it took a yard full of panels to run one fridge.
- The solar charger recharges flashlight batteries. In 1993 most of those were throwaway alkalines, but the game only has one kind, and this is more fun.
- A bank's batteries share one charge. You don't wire 6 V batteries in pairs or worry about mixing old ones with new.

## Install

It isn't on the Steam Workshop yet. Put this repository in `~/Zomboid/Workshop/RenewableEnergy`, start the game with Steam running, and enable **Renewable Energy** in the mod list.

## Getting started

<p align="center"><img src="art/promo/images/setup.png" alt="Stage 0: a wooden battery box holding a car battery, a flat solar panel and a solar battery charger on a lawn. Stages 1 and 2: a metal battery bank against a house with wall-mounted panels above it, a backup generator with a failsafe, tilted ground racks and flat panels" width="100%"></p>

There are three stages, and what sets each one is mostly the inverter in the bank.

| Stage | What you build | What it runs |
|---|---|---|
| 0, scavenger | A Battery Box with a car battery and a Plug-in Inverter, plus one or two panels | A couple of lights, or the radio and the TV (140 W). Not a fridge; the start-up surge trips it. |
| 1, RV or cabin | A Battery Bank of deep cycle batteries with a Power Inverter, charge controllers, wall panels and ground racks | A fridge-freezer and the lights (600 W, 1,200 W for a moment while a motor starts) |
| 2, homestead | The same bank with an Inverter/Charger, L-16 batteries, a backup generator and a Solar Failsafe | Most of a house, but not the electric range or the dryer (2,500 W). The generator can charge the batteries at night. |

To set one up:

1. **Mount a panel.** A Solar Module is a loose 50 W panel. Craft it into a flat panel or a wall panel, or put two on a ground rack. Panels and banks are furniture, so you place them like a chair: item in your main inventory, right-click, **Place Object**. You'll need a screwdriver, and Electrical 1 for the box, 2 for a flat panel, 3 for everything else.
2. **Fill the bank.** It's a container. Batteries go in, plus one inverter, plus up to 4 charge controllers if it's a Battery Bank. The box takes 2 batteries and the bank takes 12. Car batteries go straight in.
3. **Wire up the panels.** Right-click the bank and pick **Connect Panels in Reach**, or right-click a panel and pick a bank. Panels have to be outdoors, within 20 tiles and 3 floors of the bank. It takes 10 in-game minutes at Electrical 3, less if you're better.
4. **Turn it on.** No inverter, no power. Once it's on, the bank powers everything a generator in its spot would.

Two things help before you've got a bank going. A **Solar Battery Maintainer** clips onto a car and keeps its battery topped up while it's parked outdoors, so the car radio and headlights become your first radio and lamp. And a running vehicle within 3 tiles can charge a bank: right-click the bank, connect the vehicle, and its alternator puts in 600 W while the engine burns fuel. That takes 4 Electrical Wire, which you get back when you disconnect.

## Panels

What a panel makes depends on the sun's height, the season, clouds, fog, rain, falling snow and how hot the cells are. The three mounts behave differently over the year:

| Mount | Modules | Year, compared to a rack | Snow | Goes |
|---|---|---|---|---|
| Solar Ground Rack | 2, tilted 38° | 100% | Slides off within a couple of hours of sun, or once it's above −2 °C | On the ground or a flat roof, facing any way. It blocks the square. |
| Flat Solar Panel | 1 | 90% | Stays until it melts. Right-click and **Clear Snow** with a broom or snow shovel. | On a roof or the ground |
| Wall-Mounted Solar Panel | 1, upright | 66% facing south, 57% east | Never | On an outside wall |

Flat panels are great in summer and bad in winter. Wall panels are the opposite: in December a south wall makes about twice what a flat panel does, and more again with snow on the ground bouncing light up at it. On a clear day at the default multiplier, one module makes:

| Module on | Noon, July | Whole day, July | Whole day, December |
|---|---|---|---|
| A ground rack, facing south | 100 W | 0.8 kWh | 0.6 kWh |
| A flat panel | 100 W | 0.9 kWh | 0.3 kWh |
| A south wall | 45 W | 0.3 kWh | 0.65 kWh |

For scale, a fridge-freezer running all day uses about 1.9 kWh.

## The bank

<p align="center"><img src="art/promo/images/status.png" alt="The battery bank status window: power in and out, storage, inverter and charge controllers on the left; each battery and each panel with its watts on the right" width="100%"></p>

Right-click the bank and choose **Status** to see what's coming in, what's going out, how full it is, how cold it is, the inverter's state, and every battery and panel.

### Batteries

| Battery | Capacity | Cycles at 50% a day | Weight |
|---|---|---|---|
| Car battery (vanilla) | 600 Wh | 80 | 5 |
| Deep Cycle Marine Battery | 1,260 Wh | 1,000 | 8 |
| L-16 Battery | 2,100 Wh | 1,200 | 16 |

Every day the bank wears each battery by how deep it drained that day, and depth counts double: a deep cycle battery taken down 80% every day lasts about 400 days, at 50% about 1,000, at 25% about 4,000. Run a car battery down halfway every day and it's dead in under three months.

Batteries hold less in the cold: 80% at 0 °C, 60% at −18 °C. The bank uses the air temperature where it sits, so a bank inside the house does better than one in the shed. A battery under 25% charge at −10 °C or colder can freeze and crack. Batteries you find hold 30 to 80% of a charge.

The deep cycle battery also fits a car. Open the mechanics window, pick the empty battery slot and install it. It holds about twice what a car battery does, so the radio and the headlights run about twice as long with the engine off. It takes twice as long to fill back up from the alternator, too. The L-16 won't go in a car: it's 6 volts and weighs as much as a big dog.

### Inverters

| Inverter | Continuous | Surge | Draw while on |
|---|---|---|---|
| Plug-in Inverter | 140 W | 300 W | 4 W |
| Power Inverter | 600 W | 1,200 W | 8 W |
| Inverter/Charger | 2,500 W | 6,000 W | 15 W |

About 10% of what goes through an inverter is lost as heat. It trips if the load goes over its rating, if a motor's start-up surge is bigger than it can give, or if something needs 240 V (the electric range and the dryer, which nothing here runs yet). Switching a bank on is the worst moment, because every fridge and washer in reach starts at once. A tripped inverter stays off until you hit **Reset Inverter** in the bank's menu or the status window. A bank that runs flat cuts out and comes back once the panels have put enough back.

### What things draw

The bank adds up everything switched on in its reach, in 1993 watts:

| Appliance | Watts | Starting |
|---|---|---|
| Fridge-freezer | 80 | 600–900 |
| Fridge or freezer | 50 | 400–500 |
| Light | 60 | |
| TV | 90 | |
| Radio | 10 | |
| Microwave | 1,000 | |
| Washer | 500 | 800–1,000 |
| Car battery charger | 100 | |
| Electric range | 2,000 at 240 V | |
| Dryer | 4,000 at 240 V | |

Anything else that runs off a generator draws in proportion to the fuel vanilla would burn for it.

### Charge controllers

A full bank keeps taking whatever its panels make and slowly cooks its batteries, which lose half a point of condition a day. Two modules (100 W) are small enough to look after themselves, so the battery box doesn't need a controller. Past that, each Charge Controller handles another 360 W of panels, up to 4 per bank. The status window tells you how much room is left and warns you when the bank is overcharging.

### Backup generator and failsafe

A vanilla generator plugged in within 3 tiles of the bank, on the same floor, is its backup. While it runs it carries the load and the batteries rest. With an Inverter/Charger in the bank, it also charges the batteries at 1,500 W and burns more fuel doing it. Put a **Solar Failsafe** on the generator's square and the bank starts the generator when it drops below 20% and shuts it off at 80%. Both numbers are sandbox options. The generator still needs fuel, and it won't start below 20% condition.

## Items

<p align="center"><img src="art/promo/images/items.png" alt="Inventory icons of every item in the mod and the vanilla car battery, with their names" width="100%"></p>

| Item | What it's for |
|---|---|
| Solar Module | A 50 W panel. Mount it flat or on a wall, or put two on a ground rack. |
| Battery Box | The stage 0 bank: a wooden box for 2 batteries and an inverter |
| Battery Bank | A rack for 12 batteries, an inverter and 4 charge controllers |
| Plug-in Inverter, Power Inverter, Inverter/Charger | See the inverter table |
| Charge Controller | Lets a bank take more panels without cooking its batteries |
| Solar Failsafe | Starts and stops the backup generator for you |
| Deep Cycle Marine Battery, L-16 Battery | See the battery table |
| Solar Battery Maintainer | Clips onto a car and keeps its battery charged in daylight |
| Solar Battery Charger | Set it outdoors with 4 flashlight batteries in it, and they're charged in a sunny day or two |
| Homestead Power #1: Sun & Batteries | Teaches the battery box, both battery banks and the three mounts |
| Homestead Power #2: Inverters & Control | Teaches the charge controller and the failsafe |

## Crafting

<p align="center"><img src="art/promo/images/recipes.png" alt="Every recipe's inputs and result, with the skills it needs and how it is learned" width="100%"></p>

You need a table or counter nearby and enough light to see. Tools aren't used up.

| Recipe | Skills | Makes | Uses up | Tools |
|---|---|---|---|---|
| Make Battery Box | Electrical 1, Carpentry 1 | Battery Box | 4 Planks, 8 Nails, 2 Electrical Wire | hammer, screwdriver |
| Build Wooden Battery Bank | Electrical 3, Carpentry 2 | Battery Bank | 6 Planks, 12 Nails, 4 Electrical Wire, 4 Screws | hammer, screwdriver |
| Build Metal Battery Bank | Electrical 3, Welding 1 | Battery Bank | 4 Steel Sheet - Small, 2 Steel Rods, 4 Electrical Wire, 4 Screws, 2 uses of a Welding Torch | welder mask, screwdriver |
| Make Flat Solar Panel | Electrical 2 | Flat Solar Panel | Solar Module, 3 Electrical Wire, 4 Screws | screwdriver |
| Make Wall-Mounted Solar Panel | Electrical 3, Welding 1 | Wall-Mounted Solar Panel | Solar Module, 2 Steel Rods, 3 Electrical Wire, 4 Screws | screwdriver, hand drill |
| Make Solar Ground Rack | Electrical 3, Welding 2 | Solar Ground Rack | 2 Solar Modules, 4 Iron Pipes, Steel Sheet - Small, 6 Screws, 4 Electrical Wire | screwdriver, wrench |
| Make Charge Controller | Electrical 5 | Charge Controller | 6 Scrap Electronics, 2 Electrical Wire, Steel Sheet - Small, Amplifier, 4 Screws | screwdriver, pliers |
| Make Solar Failsafe | Electrical 3 | Solar Failsafe | Remote Controller (Long-Range), 2 Scrap Electronics, 2 Electrical Wire | screwdriver |
| Unmount Flat Solar Panel | Electrical 1 | Solar Module, 2 Electrical Wire, 2 Screws | Flat Solar Panel | screwdriver |
| Unmount Wall-Mounted Solar Panel | Electrical 1 | Solar Module, 2 Steel Rods, 2 Electrical Wire | Wall-Mounted Solar Panel | screwdriver |
| Unmount Solar Ground Rack | Electrical 1 | 2 Solar Modules, 4 Iron Pipes, 2 Electrical Wire | Solar Ground Rack | wrench |
| Make Solar Module | Electrical 7 | Solar Module, 60% condition | Glass Pane, 10 Scrap Electronics, 2 Electrical Wire, Steel Sheet - Small, 2 uses of a Welding Torch | screwdriver |

Making your own modules is off by default, because finding them is half the game. Turn on **Expanded Recipes** in the sandbox options if you want it.

Unmounting doesn't need learning. Everything else you learn one of three ways:

- Read a Homestead Power magazine.
- Level up. Electrical 2 teaches the battery box, 3 the flat panel, 4 the wall panel and both banks, 7 the solar module.
- Research something you found. A Solar Module teaches the three mounts, a Plug-in Inverter the battery box, a Power Inverter both banks, and an Inverter/Charger both banks and the failsafe.

The Solar Battery Maintainer and the Solar Battery Charger can't be crafted. You have to find them.

## Where to look

Think about who had this stuff in 1993: people with campers and boats, farmers, electricians, the phone and power companies, and preppers. Modules are the hard part. The odds below are per container, at default loot settings.

| Item | Best places |
|---|---|
| Homestead Power #1 | Electronics store magazine racks (1 in 7), survivor caches and safehouse bookshelves, bookstores, hardware and camping stores. Ordinary homes too, about 1 living room shelf in 60. |
| Homestead Power #2 | Electrician vans (1 in 14), electronics store racks, radio, phone company and power company vans, survivor caches and safehouses. Also in homes, about half as often as #1. |
| Plug-in Inverter | Gas station emergency shelves, auto parts stores, campers, electronics stores (about 1 in 15 each), garages, and now and then a glove box |
| Solar Battery Maintainer | Auto parts store battery shelves (1 in 17), campers, farm tool cabinets, mechanics |
| Solar Battery Charger | Camping store and survivor safehouse lighting, electronics stores (about 1 in 16) |
| Solar Module | Survivor caches (1 in 9 to 16), camper trailers (1 in 17), campers, phone company, electrician and power company vans |
| Power Inverter | Camper trailers (1 in 21), auto parts stores, electrician vans, campers |
| Charge Controller | Power company and phone company vans (about 1 in 20), electrician vans, camper trailers, survivor caches |
| Deep Cycle Marine Battery | Auto parts store battery shelves (1 in 15), camper trailers, mechanics, battery plants |
| Inverter/Charger | Rare: phone company vans, survivor caches, control rooms, generator rooms |
| L-16 Battery | Rare: phone company vans, battery plants, power company vans, generator rooms |
| Solar Failsafe | Hardly ever found. Craft it. |

Some places come already set up. A shed or a garage might have someone's homemade battery box with a car battery or two in it. Farm and electronics storage rooms sometimes hold a full battery bank, often with an inverter. Garages and storage units sometimes have a cardboard crate of modules and a deep cycle battery. On the Muldraugh map there are also 33 fixed spots, panels on farm buildings and a ranger station and crates in hardware and camping stores, and each one has a 1 in 4 chance of being there in a new world.

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
- **Solar Panel / Crate World Spawns**: the chance for each fixed spot, 25%.
- **Battery Bank Spawn**: how often rooms come with a stocked bank or crate. None, Very Rare, Rare (default) or Uncommon.
- **Stash Houses**: off, maps only, or maps plus houses stocked from the start.
- **Loot Rarity Multiplier** for modules, for batteries, and for everything else. 0 takes them out of the loot.
- **Connect Panel Time**: minutes to connect a panel at Electrical 3.
- **Expanded Recipes**: lets you make solar modules.

The game's own loot sliders still apply on top (Other for the hardware, Recipe Resources for the magazines).

## What's next

Biogas. A drum of kitchen scraps and manure ferments into methane, an air mattress holds the gas, and you cook and light with it. Later a gas generator charges the bank at night through the Inverter/Charger.

## Development

[DEVELOPMENT.md](DEVELOPMENT.md) has the commands for testing the mod and rebuilding the art, plus notes on the Build 42 behavior it relies on. [AGENTS.md](AGENTS.md) has the rules. Rebuilding the art needs [Blender](https://www.blender.org/) and [uv](https://docs.astral.sh/uv/).

## Credits

By Caleb Fenton. Inspired by [Immersive Solar Arrays](https://github.com/radx5Blue/ImmersiveSolarArrays) by RadX5 and Poltergeist. Licensed under the Apache License 2.0, see [LICENSE](LICENSE).
