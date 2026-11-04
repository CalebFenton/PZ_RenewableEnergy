# Renewable Energy: player's guide

- [Quick start](#quick-start)
- [Why this mod](#why-this-mod)
- [How power works](#how-power-works)
- [Moving up](#moving-up)
- [Battery banks](#battery-banks)
- [Batteries](#batteries)
- [Solar panels](#solar-panels)
- [Wind chargers](#wind-chargers)
- [Treadmills](#treadmills)
- [Generators on gas](#generators-on-gas)
- [Biogas](#biogas)
- [Wood gas](#wood-gas)
- [Small gadgets and the arrow board](#small-gadgets-and-the-arrow-board)
- [Learning and crafting](#learning-and-crafting)
- [When something isn't working](#when-something-isnt-working)
- [Moving things and your save](#moving-things-and-your-save)
- [Where to look](#where-to-look)

## Quick start

### What matters most

- **The grid shuts off.** You have weeks before it does. Until then a bank just stands by and fills up, and it takes over within minutes of the shutoff. Use the time to scavenge.
- **A bank needs four things:** a battery box, rack or cabinet, an inverter, batteries, and a source (a solar panel, a wind charger or a treadmill).
- **Put it inside a room**, close to where you live. Outdoors, it does nothing.
- **It powers the neighbours too.** A bank powers everything a generator in its spot would, the lights and fridges next door included. Set up away from town, or switch off what you don't need.

### What to scavenge

- **Homestead Power #1**, the first magazine: electronics stores about every other time, bookstores, libraries, post offices, tool, outdoor and auto parts stores, and about one home in thirty.
- **Car batteries**: every car has one. Take them from cars you won't drive.
- **A Plug-in Inverter**: auto parts stores, gas stations, electronics stores, garages, glove boxes and trunks.
- **Solar modules**: good ones are in electronics store back rooms and camping stores. Cracked ones sit on garage and shed shelves, and they still make power.
- **Electric Wire and a screwdriver**: every part you wire in takes both.

Later you'll want deep cycle batteries, a power inverter and a charge controller. [Where to look](#where-to-look) lists where everything turns up.

### Skills and shortcuts

Read the magazine first. It teaches the box and the panel. Without it, you learn the box at Woodwork, Metalworking or Electricity 5, and the panel at Electricity 4. Either way, making the **Wooden Battery Box** takes Woodwork 3 (the **Metal Battery Box** takes Metalworking 3), and the **Flat Solar Panel** Electricity 2. Connecting the bank takes Electricity 3, or the vanilla generator magazine. No inverter? Build a **Makeshift Plug-in Inverter** at Electricity 2 (see [Inverters](#inverters)).

**No skills yet?** Two shortcuts need no crafting:

- **Found banks.** Farm storerooms, barns and sheds, and now and then garages and storage units, can hold a battery box or rack already in place and connected, the first time anyone sees them. It has a few worn batteries, sometimes an inverter, and now and then a panel beside it (see [Places already set up](#places-already-set-up)).
- **Arrow board trailers.** Road works around Muldraugh, Riverside and Rosewood, the checkpoints outside Louisville, and traffic jams and junkyards have them: two panels and a box of deep cycles on wheels. Tow one home, or strip it (see [The arrow board trailer](#the-arrow-board-trailer)).

### The first evening

1. Place the box in a room of the building you live in.
2. Right-click it and **Wire In** two batteries and the inverter. That takes a screwdriver, some Electric Wire and enough light to see by.
3. **Connect Bank**, as you would connect a generator.
4. Build a **Flat Solar Panel** around a module and place it outdoors within 20 squares of the box, then right-click the box and **Connect Sources in Reach**.
5. **Turn On**, and open **Status** to see what's coming in and going out.

The box holds about 1.2 kWh, and the plug-in inverter carries 400 W: enough for a fridge-freezer, the TV, the radio and the lights. But two car batteries carry a fridge through only about six hours of darkness, and draining them flat every night halves their capacity in about a month. Run the fridge while the sun's up, and save up for bigger batteries and a bigger box.

### How a run usually goes

| When | What you're after | What it takes |
|---|---|---|
| The first weeks | The TV, the lights, cold food by day | A battery box, two car batteries, a plug-in inverter, one or two flat panels, or a treadmill |
| A month or so in | The fridge through the night | A rack of deep cycles, a power inverter, a charge controller, more panels on racks and walls, a scoop rotor |
| Months later | The washer, the stove, and a backup that needs no gasoline | Bigger batteries, an inverter/charger, a wind charger, a generator on biogas or wood gas started by a **Solar Failsafe** |
| The long haul | The whole house, all winter | A metal cabinet, two inverter/chargers, every panel you can find, homemade wind turbines on high ground, a brick dome digester |

Along the way you'll service batteries, seal cracked modules, set wind brakes before storms and clean out a gasifier's ash. Those chores come every few days, not every hour. Skip them and you'll see the cost. Keep at them, and with skill a battery can be rebuilt with new plates and last as long as you play.

## Why this mod

When the grid goes down, your choices are a gasoline generator or the dark. The generator is loud, it draws the dead, and the gasoline runs out.

People had other answers long before 1993, and none of them is high tech. Farms in the 1930s charged radio batteries from small wind chargers. Gasifiers ran cars and trucks on wood in the Second World War. Villages have cooked with gas from manure pits for decades. Cabins and RVs ran lights off a solar panel and a few batteries. It always frustrated me that a survivor who can build a forge couldn't do any of this, so this mod adds it.

- **Vanilla things get more useful.** Car batteries, treadmills, microwaves, radios, trash cans, steel drums and wood ash all find a new use, and scavenging gets more fun when the junk in a garage is a part you need.
- **Depth, without imbalance or confusion.** Panels like some seasons, wind likes height, a digester likes warmth. We simplify for fun and we add realism for fun, and try to find the balance. Vanilla's numbers are the yardstick, and tooltips and **Status** windows tell you what's happening and why.
- **Things can last forever, with effort and skill.** Batteries wear with every deep drain, panels crack in storms, parts wear while they run. Patching brings a thing back a little less far each time; remaking it fresh takes more skill and resets it. Power is a holdout you keep paying for in work, not a restoration.
- **Quiet is the point.** A renewable source never beats a generator on raw power. It buys you silence: a bank draws nothing to your door.
- **It works like the base game.** You connect a bank the way you connect a generator, and appliances draw what vanilla bills a generator for them.

The crafting window lists every recipe, and tooltips and **Status** windows give the numbers for whatever you're looking at. This guide covers the rest: what each thing is for, how one setup leads to the next, and the rules that decide whether it pays off. Figures are rounded and assume the default sandbox settings.

## How power works

There are two ways to keep the lights on, and most homesteads end up using both.

**A battery bank.** Panels, wind chargers and treadmills charge the bank's batteries, and its inverter turns that charge into power for the house. A bank burns no fuel and makes no noise, and it powers whatever a generator in its spot would, with the same reach and floors.

**A generator on gas.** A Gas Conversion Kit lets a vanilla generator run on gas from a manure digester or a wood gasifier instead of gasoline. It's still loud, and it still draws the dead, but it keeps going once the gas stations run dry.

They work together: a vanilla Car Battery Charger wired into the bank fills it from a running generator, and a **Solar Failsafe** starts the generator when the batteries run low. You get quiet power most days, and the generator's roar only when the weather fails you.

### The words used here

- **Bank**: a battery box, rack or cabinet placed in a room, with everything wired into it.
- **Inverter**: the part that turns the batteries' charge into power for the house. It sets how much you can switch on at once, and a bank needs one to turn on.
- **Source**: anything that charges a bank: a solar panel, a wind charger or a treadmill.
- **Input**: a bank's slot for a source. A bank has 2, each **Charge Controller** wired in adds 7, and a bladed wind charger takes 3 (see [Inputs](#inputs)).
- **Charger**: a Car Battery Charger, or the charger built into an Inverter/Charger, wired into a bank. It fills the batteries from the grid or a running generator.
- **Reach**: the area a generator in the bank's spot would power, 20 squares and 3 floors by default. A bank powers everything in it and takes sources from it.

### What things draw

A bank bills each appliance what vanilla bills a generator for it:

| Appliance | Draw while on |
|---|---|
| Light | 4 W |
| Radio | 20 W |
| TV | 60 W |
| Car battery charger | 100 W |
| Fridge | 160 W |
| Fridge-freezer | 260 W |
| Washer, dryer, stove, microwave | 180 W |

A fridge runs day and night, so it's what sizes your bank: 160 W around the clock is about 4 kWh a day, 2 of them overnight. A stove or a washer counts only while it's on.

The inverter also loses a share of what passes through it, a tenth for a found one and more for a makeshift one, and draws a few watts while it's on. Everything in the bank's reach counts, the neighbours' lights and fridges included, so set up away from town or switch off what you don't need. The status window lists what draws in other buildings apart.

## Moving up

Every piece has a better version. Mostly you upgrade by building the next one and moving your parts across: **Unwire** them from the old bank and **Wire In** them on the new one. Batteries keep their charge and condition, and panels keep their modules.

### Storage

| Storage | Batteries (metal) | Inverters | Chargers | Controllers | Inputs at most |
|---|---|---|---|---|---|
| Battery box | 2 (2) | 1 | 1 | 0 | 2 |
| Battery rack | 6 (8) | 1 | 2 | 2 | 16 |
| Battery cabinet | 12 (16) | 2 | 2 | 4 | 30 |

A metal rack or cabinet holds more batteries than a wooden one; a metal box holds the same two.

### Inverters

The inverter decides how much you can switch on at once. With two inverters, a bank carries what both add up to.

| Inverter | Carries | Wastes | Wire it in at | Comes from |
|---|---|---|---|---|
| Makeshift Plug-in Inverter | 400 W | A quarter | Electricity 0 | Crafted (Electricity 2) |
| Plug-in Inverter | 400 W | A tenth | Electricity 0 | Common |
| Makeshift Power Inverter | 600 W | A fifth | Electricity 2 | Crafted (Electricity 4) |
| Power Inverter | 600 W | A tenth | Electricity 2 | Uncommon |
| Inverter/Charger | 1000 W | A tenth | Electricity 4 | Rare |

The Inverter/Charger also has a 1000 W charger built in (see [Chargers and generators](#chargers-and-generators)). As a guide, 400 W runs a fridge-freezer (a mini fridge counts as one) with the TV, the radio and the lights; 600 W adds the washer, the stove or the microwave; 1000 W runs a fridge-freezer, the stove and the washer at once; a pair of inverter/chargers runs the whole house.

**Building one.** A makeshift inverter carries what the found one of its size does, but wastes more of your charge, idles hotter, wears a little faster and never comes up to a found one's condition: a Makeshift Plug-in Inverter tops out at 80, a Makeshift Power Inverter at 90. The better your Electricity when you build it, the closer to that it comes out. A found inverter is always an upgrade.

- **Makeshift Plug-in Inverter**: a Car Battery Charger or a Microwave Transformer, an Amplifier, two Scrap Electronics and two lengths of wire, with a screwdriver, at Electricity 2.
- **Makeshift Power Inverter**: a Microwave Transformer (a battery charger's is too small), two Amplifiers, four Scrap Electronics, four lengths of wire, a small sheet of metal and four screws, with a screwdriver and pliers, at Electricity 4.

Taking apart a radio or a TV often gives an Amplifier, and a Speaker always does. Dismantling a microwave gives its transformer 20% of the time at Electricity 0, 10% more for each level, and every time from Electricity 8.

**Controllers and the failsafe.** Homestead Power #2 teaches both; without it, you learn the controller at Electricity 8 and the failsafe at Electricity 6.

- **Charge Controller**: an Amplifier, six Scrap Electronics, two lengths of wire, a small sheet of metal and four screws, with a screwdriver and pliers, at Electricity 5.
- **Solar Failsafe**: a Remote Controller (Long-Range), two Scrap Electronics and two lengths of wire, with a screwdriver and pliers, at Electricity 3.

### Sources

A usual climb:

- **Two flat panels**, for summer days.
- **Wall panels and solar racks** for winter, and a **scoop rotor** for a trickle at night.
- A **charge controller**, then a **treadmill wind charger** to help the panels through winter nights.
- A **car alternator wind charger**, then a **homemade wind turbine** on high, open ground.
- A generator on biogas or wood gas as the backup, started by a **Solar Failsafe**.

### Better batteries

Car batteries come first, then **Deep Cycle Batteries**, which hold twice as much and last far longer, then **L-16s**, found mostly where the phone and power companies kept them. You can make a **Jar Battery** from scratch when you can't find anything better. See [Batteries](#batteries).

### Gas backups

| Line | Small | Medium | Large |
|---|---|---|---|
| Digesters | Barrel Digester | Insulated Digester: three times the barrel, built new or upgraded from a barrel | Brick Dome Digester: three times again, buried and warm |
| Gasifiers | Primitive Gasifier (trash can) | Gasifier (steel drum) | Advanced Gasifier (welded sheet metal) |

A bigger digester holds more feed and gas, takes feed in faster and rides out cold snaps. **Upgrade to Insulated Digester** keeps what's inside the barrel, which goes in a box of planks and straw under a second drum that floats on top to hold the gas. A tarp gas bag on the barrel comes back to you. The brick dome is laid in clay bricks, stone blocks or any mix of the two, and sits in a pit you dig, so it goes only where you could dig a grave: earth, grass or sand at ground level, not a floor or pavement. A bigger gasifier carries more fuel and makes less ash.

### Sizing a bank

Size the batteries so that one night uses about half of them or less. Wear grows with how deep you drain them (see [Wear](#wear)), so a bank twice the size lasts four times as long.

For a fridge through a twelve-hour night you need about 2 kWh out of the batteries. That's more than a box of car batteries holds, but less than a third of a rack of six deep cycles, which will last you years.

## Battery banks

### Placing

A box, rack or cabinet works only inside a building's room. A box is small enough to go on a table, counter or shelf, as a microwave does; racks and cabinets stand on the floor. Like furniture, it turns to face any way as you place it: hold the mouse button and move the cursor the way it should face. Its charge meter is on the front. One you find stands with its back to a wall, already connected but switched off.

### Wiring parts in

Parts go in with **Wire In** and come out with **Unwire**; you can't drag them. **Wire In** lists every part you carry by type, each with its condition. **Wire In > All Batteries** fills the bank with your best batteries first, and **Unwire > All Batteries** empties it in one go. What doesn't fit in your inventory lands at your feet.

Every part takes a screwdriver, Electric Wire and light to see by; an L-16's cable lugs bolt on, so it takes a wrench too. Unwiring takes the same tools and gives the wire back. The first time an item is wired in, it gives Electricity XP, and higher Electricity makes the work faster. A charge controller needs Electricity 3 and a Scrap Electronics.

**Turn On** stays greyed out until the bank has a working inverter and a battery.

### What it powers

The bank powers everything a generator in its spot would, including the floors above and below. It takes over within minutes of the grid shutoff, which comes when vanilla's Electricity Shutoff option says. It keeps charging and draining while you're away, and anything left switched on in its reach keeps drawing. Mods that tell it what their machines draw are billed the same way: Enhanced Irrigation's Pump Houses show in the status window while they run.

Where two banks, or a bank and a running generator, both reach an appliance, only one pays for it: the nearest one that's working. A bank that's off, empty or missing its inverter leaves its appliances to the next nearest. A bank that would overload hands the appliances farthest from it to the nearest other bank or generator with room for them, so two banks share a load neither could carry alone.

### Overload

If more is switched on than the inverters can carry, and no other bank or generator in reach has room for the extra, the whole area goes dark. A bank powers everything or nothing; it never drops just the dryer. Switch something off and the power comes back at the next update, or turn the bank off and on to bring it back at once. Every overload costs each inverter a little condition.

The status window says how much of an overload is in other buildings. Vanilla gives you no way to switch off a fridge, so for the neighbours' fridges the fix is to pick them up.

At zero charge the power cuts too. It comes back by itself once some charge has built up, so a bank that barely charges doesn't flicker on and off.

### Inputs

A bank has 2 inputs of its own, and each working **Charge Controller** adds 7. Each source takes some:

| Source | Inputs |
|---|---|
| Any solar panel, including a solar rack's two modules | 1 |
| Scoop rotor, treadmill | 1 |
| Treadmill or car alternator wind charger, homemade wind turbine | 3 |

So a bladed wind charger always needs a controller.

Inputs go in the order you connected the sources. Sources past the last input stay connected but make nothing, and the status window says "no free input". A broken controller loses its inputs, so check them when a source goes quiet.

### Reach

**Connect Sources in Reach** picks up every source in the bank's reach that isn't yet connected to a bank: within 20 squares and 3 floors of the bank, or whatever the **Generator Tile Range** and **Generator Vertical Power Range** sandbox options say.

- **The bank must be connected first** (**Connect Bank**).
- **Panels and wind chargers must stand outdoors**, under open sky. A treadmill can be under a roof.
- **Inputs.** Sources too large for the bank's free inputs are skipped, and each queued connection still needs room when its turn arrives.
- **Moving a source to another bank**: right-click the source and pick **Connect to** the other bank.
- **What drops a connection**: moving the source, roofing over a panel or wind charger (at the next bank update), or leaving it out of reach when those sandbox options shrink. Put it right and connect it again.

### Chargers and generators

A wired-in vanilla **Car Battery Charger** (100 W), or the charger built into an **Inverter/Charger** (1000 W), fills the batteries from the grid, or from a running generator whose reach covers the bank. That generator burns fuel for the charging as it would for an appliance of those watts. Chargers only top up what your sources leave unfilled. Without one, grid and generator power charge nothing. Unwiring the last charger removes its demand from the generator's fuel bill immediately.

A running generator within 3 squares of the bank, on its floor, takes over the load while it runs, and the batteries rest.

### Solar Failsafe

Place it on a generator's square. It starts the generator when the bank drops to the start charge (20% by default) and stops it at the stop charge (80%). It won't start a generator with no fuel, or one worn enough to catch fire. Without a charger in the bank, the generator only carries the load, and the charge climbs only as fast as your sources fill it. Sandbox: **Failsafe Start Charge**, **Failsafe Stop Charge**.

### Upkeep

Inverters lose condition every hour the bank powers its area, about one Scrap Electronics' worth every two and a half weeks. Controllers wear half as fast, so even a full metal cabinet needs only a scrap every few days. **Repair with Scrap** in the bank's menu (Electricity 2) adds the same amount for each scrap. A part at zero is broken, but you can still repair it. Found inverters and controllers are usually in good shape, but now and then one is a dud.

### The status window

**Status** walks you over to the bank and opens a window that closes once you walk more than 4 squares away. It shows:

- Whether the bank is charging or draining, by how much, and how long until it's full or empty. Once it's full, it says how much it has to spare: more panels would go to waste.
- The load against the limit, and the inputs used.
- What draws, by kind. Once something in another building draws too, the list splits into this building and other buildings, with how far away the nearest is.
- Batteries by type: how many, their charge together, and the condition of the most worn one.
- Sources by kind: how many, and their output together. For wind chargers it also gives the life left in the most worn blades still turning ("blades 40% left"). A source short for a reason you can fix, such as a cracked module, snow or a braked charger, also gets a red row of its own with where it stands and why. Click a row to see where its sources stand.

While grid power reaches the bank, the window says so, and whether the chargers are filling from it. **Rename** gives a bank a name of your own, which helps once you have several.

## Batteries

| Battery | Holds | Years to half capacity, drained half (a quarter) nightly | Fits a car |
|---|---|---|---|
| Car battery | 600 Wh | 0.4 (1.6) | Yes |
| Deep Cycle Battery | 1260 Wh | 1 (4) | Yes |
| L-16 Battery | 2100 Wh | 2 (8) | No |
| Jar Battery | 400 Wh | 1.2 (4.9) | No |

The tooltip shows each battery's capacity and stored charge. Capacity falls with condition.

### Shared charge

All the batteries in a bank share one charge level. Wire in a full one next to empty ones and the charge evens out; a battery you unwire leaves at the bank's level. Found batteries hold between a third and four fifths of a charge.

### Wear

Once a game day, each battery wears by that day's deepest drop from its peak. Wear grows with the square of the depth, so draining half as deep wears a quarter as much. That's why a bigger bank pays for itself: the same load drains it less deeply. Temperature doesn't matter. Sandbox: **Battery Wear**.

### Keeping batteries going

Batteries last as long as you keep at it. You can bring them back a few times, and after that they need rebuilding:

1. **Service Battery**: Electricity 1, water, and a rag, baking soda or wood ash. It adds 10 condition and keeps the charge, but stops 20 short of the ceiling. It doesn't count as a repair, so service as often as you like.
2. **Recondition Battery** (Homestead Power #2, or learned at Electricity or Mechanics 5): Electricity 3, water and baking soda or wood ash bring it straight up to its ceiling, but leave it empty.
3. **The ceiling**: it starts at 85, and each recondition lowers it by 10. After a handful, the battery needs a rebuild.
4. **Rebuild.** No magazine teaches it; you learn every step at Electricity 6, and the mold and plate casting at Blacksmith 4 too.
   1. **Strip** the battery (Electricity 4, gloves, and containers to catch the acid) for its case, worn plates and acid.
   2. Make the mold once: **Make Wooden Battery Plate Pattern** (Woodwork 2, a hammer, a saw, a plank and nails), **Press Battery Plate Mold** from clay and the pattern at a hand press, then **Fire Battery Plate Mold** in a kiln. The pattern and the mold are kept.
   3. **Recast Battery Plates** (Blacksmith 3) at a furnace with the mold and charcoal. A third of the lead skims off as **Lead Dross**, so three worn sets make two, and a lead pipe can stand in for one set. **Cast Battery Plates from Lead Pipe** makes a set from three lead pipes.
   4. **Rebuild** the battery (Electricity 5, a screwdriver, and a wrench for an L-16) from its case, new plates, acid and water. It comes back like new, empty, with its repair count cleared.
5. **Reduce Lead Dross** (Blacksmith 5) at the furnace with charcoal and the mold: each dross makes one set of plates, so no lead is ever lost, only charcoal.

Acid can't be made, and it needn't be: stripping a battery gives back exactly the acid rebuilding it takes. More comes from auto parts stores and garages, or from batteries you strip. A rebuild keeps the battery's kind: a deep cycle or L-16 can only be rebuilt from its own case.

So the batteries themselves never run short of lead, acid or soda: water, wood ash and charcoal keep them going for as long as you play.

### Found batteries

A bank found in a room comes stocked, connected and switched off. Its batteries have been used, and the riskier the place, the better they are. Sheds and farm storerooms hold well-worn ones that are worth reconditioning. Homesteads, storage units and utility sites hold batteries at around four fifths, a few as good as new. Now and then one is a dud: nearly dead, and repaired too often for reconditioning to help. Strip it for a rebuild instead.

### Jar battery

Six glass jars, one set of plates (three lead pipes cast a set), acid and water, at Electricity 4. It holds two-thirds of a car battery but lasts three times as many charge cycles, and everything except the acid can be made.

### In a car

A deep cycle fits a car's battery slot. It runs the lights and radio twice as long and takes twice as long to fill from the alternator, but still charges all the way to full. L-16s and jar batteries are heavy items, like a generator: you can carry one in a car, but you can't take it into your inventory while you sit in the car. Get out and take it from the seat through the door.

## Solar panels

### Mounts

There are two kinds of module. A factory **Solar Module** is rated 160 W; a **Makeshift Solar Module** you build is rated 96 W. Output follows condition: a module at half condition makes half its rating. Every module's tooltip shows **Output: N of M W**, what it makes at its condition out of its rating.

Each mount holds either kind of module, and each suits a different season:

| Mount | Modules | Best in | A new factory module banks a day, July / December |
|---|---|---|---|
| Flat Solar Panel | 1 | Summer | 1.7 / 0.5 kWh |
| Wooden or Metal Wall Solar Panel | 1 | Winter | 0.7 / 0.9 kWh |
| Wooden or Metal Solar Rack | 2 | All year | 1.5 / 0.9 kWh per module |

A makeshift module banks 60% of those figures. They are averages over the weather; a clear day gives half again or more, and a grey week much less. A flat panel lies flat and likes the summer sun high overhead. A wall panel goes on an outside wall facing south or east, and gets extra light off fresh snow; an east wall gets only morning sun. A solar rack tilts its two modules and faces any way you place it, which makes it the most even across the year. A rack's two modules use 1 bank input between them.

A mount's tooltip lists each module it holds with its output, and the total. Makeshift modules look different from factory ones, on a placed mount and on a mount you carry, so you can tell at a glance which slots hold them.

As a rule of thumb, three flat panels with factory modules run a fridge through a July day and night, and it takes five factory modules on racks or walls in December. Sandbox: **Sunlight Multiplier**.

### Weather and snow

Overcast skies take most of the light. Fog and rain take some more, and falling snow halves what's left. Wind doesn't matter to a panel.

Snow piles up on flat panels and racks, and output drops by the share covered. A rack sheds its snow within a few hours in sun or mild air. A flat panel loses its snow only as it melts above freezing, unless you **Clear Snow** with a broom or a snow shovel. Wall panels never hold snow.

### Storms

A thunderstorm with strong wind can crack a module; a gale without thunder can't. You hear the glass go, and anyone within about 30 squares sees "A solar module cracked in the storm". Each crack costs the module 35 condition, and output follows condition: a module at half makes half.

| Mount | Storm risk |
|---|---|
| Wall panel | Never cracks |
| Metal solar rack | Least |
| Flat panel | Middling |
| Wooden solar rack | Most |

At the default rate, ten panels lose about one module every four to six months. Even the longest run of thunderstorms cracks a module on a wooden rack only about one time in seven. Every panel standing outdoors is at risk, connected or not. Sandbox: **Storm Damage**, **Storm Damage Rate**.

The glass shows how worn a module is: whole down to 85 condition, a few fine cracks below that, and heavy cracks below 50. A new module's first crack always shows.

### Fixing modules

Sealing is the cheap fix, reglazing the good one.

- **Seal Cracked Module** (Electricity 2) takes a screwdriver and 1 use of epoxy, glue or wood glue. Seal a loose module in the crafting window, or one still on a placed panel from the panel's menu. Each seal adds 15 condition, up to 80, less 10 for each earlier seal, for either kind of module; the glass still looks cracked. A module at its ceiling can't be sealed, and the menu greys the seal out: reglaze it instead. A module never sealed at 80 or more is too lightly cracked for a seal to help.
- **Reglaze Module** (Electricity 3) puts on a new pane of glass, with a screwdriver, a glass pane, 1 use of epoxy, and electric wire. Glue won't hold glass. Reglaze a loose module in the crafting window, or one still on a placed panel or on the arrow board trailer from its menu. Any damaged module can be reglazed, cracked or not. It comes back as new, looks whole, and its seal count clears.

**Unmount** always gives back the same modules at the same condition, plus some of the frame.

Sealing and reglazing in place follow the crafting window's item protections: favorite adhesives and items excluded from recipes are not used. A favorite screwdriver is allowed because the job keeps it.

### Makeshift modules

A **Makeshift Solar Module** (Electricity 4) is 16 solar cells under glass, rated 96 W. Cells come from taking apart calculators, garden lights, solar battery chargers, maintainers, and shattered factory modules (only at 0 condition, for 12 cells). It wears, cracks, seals and reglazes like a factory module.

### Glass

Reglazing and makeshift modules each take a flat pane of glass. Car windows are curved and won't do. Panes are hard to make, but houses are full of them: pick up a window with a crowbar (that takes a little carpentry), then **Take Out Window Glass** with a screwdriver or a sharp knife digs out the putty and gives you its two panes. Taking the glass out needs nothing learned, but a window can break as you pick it up, and then there is nothing to take out.

## Wind chargers

Wind blows day and night, and hardest in winter, just when the panels give the least. Wind chargers are built on the **Welding** page of the build menu, and each needs a generator: a treadmill's motor, a car's alternator, or an alternator you make yourself. The treadmill and car alternator chargers can instead stand on a timber mast from the **Carpentry** page, at the same skill levels with Woodwork for Metalworking: 3 logs, 2 rope or sheet rope, planks, nails and a metal pipe, with a hammer, a saw and a hand drill, take the place of the welding and metal. Every charger but the scoop rotor also takes a set of blades, wooden, plastic pipe or steel, and stands with whichever set the build used. Those bladed chargers take 3 inputs, so their bank needs a charge controller.

### The four kinds

The figures here are at the default **Wind Multiplier** of 2, which scales them all; 1 is what such homemade chargers really made.

| Charger | Generator | Full output | Inputs | Breaks in storms |
|---|---|---|---|---|
| Scoop Rotor Wind Charger | Treadmill Motor | 300 W at 45 km/h | 1 | Never |
| Treadmill Wind Charger | Treadmill Motor | 600 W at 40 km/h | 3 | Yes |
| Car Alternator Wind Charger | Car Alternator | 800 W at 40 km/h | 3 | Yes |
| Homemade Wind Turbine | Homemade Alternator | 1600 W at 40 km/h | 3 | Yes, but turns aside in a gale |

- **Scoop rotor**: two half-drum scoops on a short pole. It never needs the brake and never breaks, but it makes little. It's the one charger that needs no controller.
- **Treadmill wind charger**: three blades high on a steel mast. It's the first charger that makes real power.
- **Car alternator wind charger**: the same mast belted to a car's alternator. It makes a third more in any wind for the same inputs, a straight upgrade.
- **On a timber mast**: either of those two on three lashed logs. It makes exactly what the welded one does, at the same height, and its blades break and wear the same; dismantled, it gives back wood rather than metal.
- **Homemade wind turbine**: speaker magnets on a car's brake hub turning past hand-wound coils. It makes well over twice the treadmill charger's power, and its tail swings it out of a gale.

### How much the wind gives

A charger makes nothing below its starting speed, and output climbs with the cube of the wind until full output. Halfway from its starting speed to full output, it makes only an eighth:

| Wind | Scoop | Treadmill | Car alternator | Turbine |
|---|---|---|---|---|
| 20 km/h | 10 W | 22 W | 30 W | 72 W |
| 25 km/h | 29 W | 75 W | 100 W | 220 W |
| 30 km/h | 63 W | 178 W | 237 W | 498 W |
| 35 km/h | 117 W | 347 W | 463 W | 944 W |
| 40 km/h | 194 W | 600 W | 800 W | 1600 W |

That's in the open on the ground. The status window shows the wind in km/h next to each charger's output.

The everyday wind averages about 12 km/h in July and 19 in December, so a charger in the open banks far more in winter. In an average day, before storms:

| | July | December |
|---|---|---|
| Scoop rotor | 0.2 kWh | 1 kWh |
| Treadmill wind charger | 0.5 kWh | 2.6 kWh |
| Car alternator wind charger | 0.7 kWh | 3.5 kWh |
| Homemade wind turbine | 1.5 kWh | 7.1 kWh |

A fridge-freezer uses about 6 kWh a day, and a south rack's module banks about 1.5 kWh in July and 0.9 in December.

### Where to put one

Placement matters as much as the charger: get it high, get it clear, and give it room.

- **Height.** A charger makes 15% more for each floor it stands on above the ground, up to the third floor (45% more). What counts is the floor you place it on, not its own mast, so building up is worth the effort.
- **Shelter.** Trees, buildings and solid walls within 8 squares steal wind, the nearer the more. A hemmed-in charger loses most of its output, and the status window says "sheltered". Only what reaches the blades' height counts: a scoop's blades turn at its own floor, a mast charger's a floor above. So walls count only on the blades' floor, buildings only when their roof reaches the blades, and trees only while the blades are within two floors of the ground. Fences and windows never count.
- **Spacing.** Keep chargers **four squares apart**. Any closer, and each charger whose blades turn at the same height takes a share of the other's wind: a quarter right beside it, a sixth at two squares, a twelfth at three. Every neighbour takes its share, so a cluster adds up, and once a charger loses a sixth the status window says "too close to another charger". Chargers don't count as shelter, and a scoop on the ground never crowds a mast charger, whose blades turn a floor higher.

### Storms and the brake

Blades break in gales. **Set the Brake** before one and **Release the Brake** after it. A braked charger makes nothing, and its blades can't break.

A charger warns you when the wind gets strong enough to break its blades. Wooden blades creak and plastic or steel blades rattle every few seconds, and the status window says "gale, set the brake". The stronger the wind, the likelier they break. When they go, there's a loud crack, and anyone within about 30 squares sees "A wind charger's blades broke in the gale".

| Blade set | On the treadmill and car alternator chargers | On the turbine |
|---|---|---|
| Plastic Pipe Blade Set | At risk above 60 km/h: strong thunderstorms | Above 80 km/h |
| Wooden Blade Set | Above 70 km/h: the worst thunderstorms | Above 90 km/h: safe in every thunderstorm |
| Steel Blade Set | Above 90 km/h: only blizzards and tropical storms | Above 110 km/h: all but the worst blizzards |

Once at risk, steel blades break a quarter as often as plastic pipe, and wood half as often. Thunderstorms top out around 84 km/h. Blizzards blow 90 to 120 km/h for a day or two and are the real danger, though even the longest breaks unbraked plastic pipe blades at most about one time in seven at the default Storm Damage Rate. Blades never change the power, only how much wind they stand.

Blades also wear out with use. Every hour a connected charger turns, unbraked and above its cut-in wind, counts against them: plastic pipe lasts 1500 hours of turning, wood 3000 and steel 8000. That's about two months, four months and eleven months of turning without a break. Braked or calm hours don't count, and the brake still keeps gales off them. Its menu says "Blades: 73% left". When they wear out they break as a gale breaks them, with the same crack and "A wind charger's blades wore out". Worn blades are no likelier to break in a gale.

From 55 km/h, the homemade turbine's tail swings its head out of the wind ("turned out of the wind"). It keeps 85% of its full output, and its blades take less of the gale, which is why they hold 20 km/h longer.

### Replacing blades

**Replace Blades** fits a spare set onto a charger whose blades broke or wore out, and the new set starts with all its hours. A charger with broken blades shows them, hanging still. It takes any kind the charger can use, its own kind first if you carry them, so a broken plastic-blade charger can come back with steel. You get the broken set back: broken wood burns in a campfire, fireplace or wood stove, broken pipe is junk, and broken steel melts down at a blast furnace. Blades that are still whole can't be swapped, so to change kinds on a working charger, build a new one.

### Making the generators

- **Treadmill Motor**: take a treadmill apart. Every one gives its motor.
- **Car Alternator**: in the vehicle mechanics window, the engine's menu has **Take Out Alternator** (engine off, a wrench, Mechanics 2; it opens the hood if it's shut). Each car has one. The car still runs without it, but it stops charging its battery until you **Put Back Alternator**. Cutting up a smashed wreck gives one as often as it gives engine parts, more with Metalworking and Mechanics; a burnt wreck never does. Mechanics' shelves and auto parts stores have them too.
- **Homemade Alternator**: a car's brake, two speakers (or two ham radios, or four portable radios, for their smaller speakers' magnets), four lengths of wire, two Scrap Electronics and a small sheet of metal, with a screwdriver and a wrench, at Electricity 5 and Mechanics 3.

## Treadmills

No sun and no wind? Run for it.

Right-click a treadmill and pick a bank in reach under **Connect to a Battery Bank** (Electricity 2, a screwdriver, wire and a Scrap Electronics): that wires its motor to make power instead of using it. **Run on Treadmill** lasts half an hour and banks roughly what a fridge-freezer draws in that time. The energy goes in when the run ends and reaches the batteries over the next half hour; stopping early banks your share of the run.

A run costs a good chunk of endurance and some thirst, and trains Fitness and Sprinting. You stop by yourself when you're nearly spent. If the bank has no free input, the run still tires you, but the energy is lost.

**Disconnect** with the screwdriver wires the motor back and gives the wire back. A treadmill feeding a bank can't be picked up or turned until you disconnect it. A treadmill whose bank is gone or out of reach stays wired: **Connect to a Battery Bank** again takes no more wire, and **Unwire the Motor** gives the wire back; picking it up gives the wire back too, and it forgets its wiring. Where there's power from the grid, a generator or a bank, an unwired treadmill is plain exercise equipment, and on a bank it draws about what a washer does.

## Generators on gas

### The kit

The **Gas Conversion Kit** is crafted, never found. **Install Gas Conversion Kit** takes a wrench and Mechanics 2; **Remove Gas Conversion Kit** needs the generator switched off. You can't pick up a generator with a kit fitted, so put the generator where it will stay.

### The gas line

**Connect Gas Line** needs a wrench and light to see by.

- **From a digester**: on the same floor, within 20 squares, with one Rubber Hose for every 5 squares.
- **From a gasifier**: right beside the generator, not diagonally, with one Metal Pipe. The gas leaves the gasifier hot.

**Disconnect Gas Line** gives the hose or pipe back.

### Running on gas

**Run on Gas** and **Run on Gasoline** turn the valve. On gas, the generator makes its usual noise, wears and fumes as usual, and draws zombies as usual, but its gasoline tank is left alone.

A generator on gas carries at most 3000 W: a whole house, with a bank charging off it. A gasifier with a full ash pit or spent filter halves that, and with both, quarters it. Switch on more than it can carry and it stalls, then starts again by itself once the load comes down. Bank chargers on it are turned down to fit, so they never stall it on their own.

When the gas runs out, the generator stops. It doesn't switch to gasoline or restart by itself. Start it by hand with gasoline in the tank and it runs on that, then goes back to gas once the source can supply again.

A lit gasifier counts as fuel for a **Solar Failsafe**, even with an empty tank. An unlit one doesn't, and the failsafe never lights it.

## Biogas

A digester turns manure and food scraps into gas, slowly and steadily, for weeks. It's the backup that needs no trip to town, as long as you keep animals and keep it warm.

### How it works

1. **Feed it.** Put feed in the hopper. It goes into the tank by weight, a whole item at a time, while there's room: a barrel takes about 2 kg a day, an insulated digester 4 kg and a dome 6 kg. The rest waits in the hopper. It keeps feeding while you're away, and what went in is gone from the hopper when you return. Feed that leaves the hopper isn't used up: it's stored in the tank and turns to gas over the following weeks. The status window's **Feed in the tank** shows how full the tank is and about how much gas is still to come from it.
2. **Wait for it to start.** A new digester takes as long as vanilla compost (two weeks by default) before it makes any gas. The clock runs only while it's fed and warmer than 10 °C. Cow and pig manure bring their own bacteria: each cow pat takes a day off and each pig dropping half a day, down to at most seven tenths of the wait.
3. **Keep it warm.** It digests what's in the tank a little each day, faster the warmer it is, so gas keeps coming for weeks after a feeding.
4. **Pipe it to a generator**, or bottle it.
5. **Empty the sludge** about once a week while you keep it full.

### What to feed it

| Feed | Gas | Effect on souring |
|---|---|---|
| Cow manure | 1 m³ | Settles it a lot |
| Pig manure | 0.3 m³ | Settles it |
| Sheep or deer manure | 0.1 m³ | Settles it a little |
| Chicken or turkey manure | Very little | Barely |
| Grass, hay | Very little | None |
| Food, fresh, stale or rotten | 0.12 m³ a kg | Sours it |
| Meat and fish | 0.2 m³ a kg | Sours it twice as fast |
| Wood ash, baking soda | None | Settles it |
| Quicklime | None | Settles it twice as much |

Each manure item stands for about a day of what the animal makes. Hens drop nothing inside their hutch, only out in their pen. Any food goes in, fresh or rotten, except worms, as with vanilla's composter. Very light things, like chicken droppings or a use of baking soda, count as a tenth of a kilogram each against the daily intake. Sandbox: **Biogas Multiplier**.

For scale: 1.6 m³ of gas runs a generator as long as a litre of gasoline, and a full propane tank holds 16 m³, a generator's full tank. A cow pat is worth about 0.6 litres of gasoline.

### Temperature

| Digester's temperature | What it does |
|---|---|
| Below 10 °C | Nothing ("Too cold to work") |
| 15 °C | A crawl |
| 25 °C | Half speed |
| 35 to 40 °C | Its best |
| 50 °C and up | Nothing |

At its best it digests about a fifteenth of what's in the tank each day. A digester follows the air's temperature: a barrel within about a day, an insulated digester over three days and a dome over a week, so the big ones ride out cold snaps. A brick dome burns a little of its own gas to stay at 20 °C or more once it's started.

A lit **Gas Heater** placed next to a digester keeps it at 25 °C or warmer, burning a little gas the whole time it's lit, summer included. It warms only the digester, not the room.

### Souring

Too much food without manure sours a digester. Output drops to a trickle and the smell gets much worse. A barrel sours on about 4 kg of scraps fed without manure, an insulated digester on about 12 kg and a dome on about 36. Manure offsets food as it goes in: a cow pat cancels about a kilogram and a half of scraps. Wood ash, baking soda or quicklime in the hopper settles a sour digester, and so does time. It's over once the acid falls to half of what soured it.

Any wood fire leaves wood ash: **Clean Out Ash** with a shovel, trowel or broom at a campfire, fireplace, wood stove or charcoal grill gives one for each hour of fuel it has burned. A gasifier leaves it too.

### Sludge

Each feeding adds sludge. Output halves once the tank is nearly full of it. **Take Sludge** fills empty sacks or compost bags with compost, a tenth of the tank per bag, as vanilla's composter does.

### Gas holders

The gas waits in a holder until something burns it. Gas made past what the holder can take is wasted, so a small holder needs a generator that runs often.

| Holder | On | Holds | Wear |
|---|---|---|---|
| Garbage bags | Barrel | 0.6 m³ | Tear within a few months |
| Tarp Gas Bag | Barrel | 1 m³ | Lasts about four times as long |
| Floating drum | Insulated digester | 1.5 m³ | Never wears out |
| The dome itself | Brick dome | 4 m³ | Never wears out |

A barrel's **Gas Bag** menu fits new garbage bags or a **Tarp Gas Bag**, sewn in the crafting menu (Tailoring 2) from a tarp, thread and duct tape. A bag goes on or comes off only once its gas is out, so **Vent Gas** first. **Take Off Gas Bag** gives a tarp bag back with its wear, to repair with duct tape, glue, wood glue, epoxy or a tarp piece as any vanilla item is repaired; garbage bags are thrown away. With no bag on, a barrel's gas is wasted.

### Smell and fumes

A digester smells worst while starting up, when sour, or when full of sludge, and a settled one mellows over its first weeks. The insulated digester smells about half as much as a barrel, and the dome stays faint. Indoors, any digester smells twice as bad.

Players nearby get vanilla's noxious smell moodle and can get sick from it, just as with corpses; gas masks help. The game counts smell in blocks of 8 by 8 squares. An outdoor digester at its worst smells strongest in its own block, one level less a block away, faintly two blocks away, and not at all three blocks off. One indoors smells only inside its building.

A barrel or insulated digester inside a building poisons the whole building while it's sour, and for a while each time its holder overflows or is vented. The dome is sealed and never fumes. Build them outside, away from where you sleep.

### Bottling

A digester fills propane tanks, welding torches and propane lantern bottles. Generators burn raw gas, but bottling past a quarter needs it cleaned first.

- **Fill With Tire Pump** fills a tank, torch or bottle only a quarter of the way, and it's tiring work. That's enough to keep a torch going: weld, then pump it up again.
- **Fit Compressor** wires a **Fridge Compressor** to the digester (Electricity 1, a screwdriver); salvage one by cutting up a fridge. **Fill With Compressor** then fills a tank, torch or bottle all the way while the digester has power, using scrubbed gas past the first quarter. The digester's **Status** says whether its compressor is fitted and has power. **Remove Compressor** gives it back.
- **Fit Scrubber**, then keep it going from **Refill Scrubber**. Each refill takes 4 L of water, clean or tainted, from any container you carry. Its water cleans about 5 m³, with wood ash 15 m³ and with quicklime 30 m³, and new water replaces the old. Its packing cleans about 10 m³ before it needs more: a use of **Steel Wool**, or an **Iron Sponge**. The water and the packing wear out separately.
- **Make Iron Sponge** (Metalworking 1, with a file) from two pieces of any kind of scrap metal or ten nails, three wood splinters and half a litre of water, clean or tainted. A spent sponge comes back out at the next packing; **Air Out Iron Sponge** with a little water, clean or tainted, revives it, twice before it crumbles.

A full torch takes about 2.2 m³ and a lantern bottle 0.8 m³, what refilling them from a tank would. A propane tank still refills lantern bottles and torches the vanilla way. Bottle refills transfer whole uses of the tank; if the bottle has less room than one tank use, neither store changes. Where there's power, a Fridge Compressor you carry inflates tires too.

## Wood gas

FEMA's plans run an engine on wood: a gasifier smoulders wood without enough air and pipes the gas to a generator right beside it. It's dirtier and needs more tending than a digester, but the cold doesn't stop it, and it runs as long as you feed it.

### The three gasifiers

| Gasifier | Made from | A full hopper runs a generator for |
|---|---|---|
| Primitive Gasifier | A trash can | About a third of a gasoline tank |
| Gasifier | A steel drum | Nearly a tank |
| Advanced Gasifier | Welded sheet metal | More than a tank |

All three are on the **Welding** page and need the generator right beside them, not diagonally.

### Fuel and lighting

Logs, branches, planks, firewood, twigs, pinecones, charcoal, and anything a charcoal kiln takes all burn. Fuel counts by weight. Charcoal leaves far less tar and ash than wood, and Tarry Packing burns too.

**Light Gasifier** takes matches or a lighter. A new gasifier, or one that has been out for a while, is cold and needs bellows as well. A lit gasifier that isn't feeding a running generator still burns about a kilogram of fuel a day; that's the price of keeping it ready.

### Gasifier upkeep

- **Ash.** The ash pit fills as it burns, fastest in the primitive gasifier. A full pit halves the gas. **Clean Out Ash** with a shovel, trowel or broom gives **Wood Ash**, which settles a sour digester, goes in a scrubber's water, or stands in for baking soda when you service a battery.
- **Filter.** The filter holds hay, straw, grass or splinters, which turn into **Tarry Packing** as it burns. Change the packing in time: once no clean packing is left, tar reaches the engine, for half the gas and fast wear. Tarry packing wears the generator faster even before then.
- **Condensate.** Burning fills a condensate drain, and while it's full, tar builds up twice as fast. **Drain Condensate** into a metal or glass container while the gasifier is lit. It's wood vinegar: poisonous to drink, but mixed with water it makes mildew spray and aphid spray.

A lit gasifier inside a building poisons the whole building. While nobody is near, it burns only what's already in its firebox, then goes out and cools, and the generator stops.

## Small gadgets and the arrow board

These need no bank.

- **Solar Battery Maintainer**: **Attach Solar Maintainer** to a car and it trickle-charges whatever battery is in it, in daylight, while the car stands in the open; in a garage it does nothing. It keeps a parked car topped up but is too slow to revive a flat battery. It stays with the car when you swap batteries.
- **Solar Battery Charger**: place it outside and load up to four flashlight batteries. They charge in daylight, emptiest first, so a full tray takes a few sunny days.
- **Solar Garden Light**: outside, on the ground floor. It charges by day and lights up once it gets dark, until the charge runs out, which after a short winter day can be long before dawn. It goes out as the sky gets light. Right-click to swap the bulb for a coloured one. Found lights start without charge, and picking one up keeps its charge and bulb.

Gadgets charge only while someone is near enough for the area to be loaded. A car parked across the map isn't charging.

### The arrow board trailer

Road crews left solar arrow board trailers behind at road works, checkpoints and traffic jams, still flashing. Each has two panels on top and a box of worn deep cycles on its tongue, usually with a charge controller. The panels keep the batteries charged and the arrow lit, and after dark the lamps light the ground around it.

- **The box** is usually padlocked: cut the lock or unbolt the lid.
- **The panels** come off in the mechanics window and give their modules, and any module goes back on. **Seal Cracked Panel** fixes a cracked one in place, and **Reglaze Panel** brings a damaged one back to new.
- **Crashes** crack the panels. A hard crash while you tow it does; bumps and hard braking don't. **Repair Frame** fixes a dented frame.

Tow it home and it keeps charging its batteries on the way, or strip it for parts.

## Learning and crafting

### Magazines and plans

| Read | It teaches |
|---|---|
| Homestead Power #1 - Here Comes the Sun | Battery boxes and racks, every panel mount, sealing, the Makeshift Plug-in Inverter |
| Homestead Power #2 - Power Trip | Battery cabinets, the Makeshift Power Inverter, the charge controller, the failsafe, makeshift modules, reglazing, reconditioning |
| Homestead Power #3 - Number Two Power | Digesters, the Gas Conversion Kit, the Gas Heater, Weld Metal Drum |
| Homestead Power #4 - Breaking Wind | Every wind charger, their blade sets, the homemade alternator, Weld Metal Drum |
| FEMA Wood Gas Generator Plans | The three gasifiers, the Gas Conversion Kit, the wood vinegar sprays, Weld Metal Drum |

### Other ways to learn

- **Skills.** Every recipe is also learned by reaching a skill level, usually above what crafting it needs, so a magazine gets you there sooner. The battery rebuild is learned only this way.
  - Battery boxes, racks and cabinets, wall panels and solar racks come from any one of Woodwork, Metalworking or Electricity; the flat panel from Electricity alone.
  - Battery work, inverters, the controller, the failsafe and makeshift modules come from Electricity; reconditioning from Mechanics too, and making the plate mold, casting plates and reducing dross from Blacksmith too. Reglazing takes Electricity and Glassmaking together.
  - The barrel digester comes from Farming or Mechanics, the insulated digester from Woodwork and Farming together, the dome from Masonry and Farming together. The Gas Conversion Kit comes from Mechanics, the Gas Heater from Metalworking and Mechanics together.
  - The primitive gasifier comes from Mechanics, the bigger two from Metalworking and Mechanics together, and the advanced one takes Blacksmith as well.
  - Wind chargers take Metalworking and Electricity together, or Woodwork and Electricity on a timber mast, and the car alternator wind charger Mechanics too; the homemade alternator takes Electricity and Mechanics. Wooden and plastic pipe blades come from Carving, steel ones from Blacksmith.
- **Research.** Researching a found module teaches the panel mounts and sealing, and a makeshift one teaches sealing. A plug-in inverter teaches battery boxes and the Makeshift Plug-in Inverter, a power inverter racks and the Makeshift Power Inverter, and an inverter/charger cabinets and the failsafe.

### What a recipe needs around it

Most recipes need a table, and every one needs light to see by, as most of vanilla's do. Recasting plates and reducing dross need a furnace, the plate mold a hand press and a kiln, and steel blades a forge.

Light is also needed for wiring and fittings: wiring parts in and out, connecting or disconnecting a source, a treadmill or a bank, replacing blades, repairing parts and panels, and fitting or removing a Gas Conversion Kit or its gas line. Switches, valves, brakes, bulbs and chores like clearing snow or ash don't need it.

### Blades

A blade set is all three blades of a charger, so a charger takes one. **Carve Wooden Blade Set** (Carving) and **Cut Plastic Pipe Blade Set** are in the crafting window. **Forge Steel Blade Set** (Blacksmith 3) is only in a Forge's or an Advanced Forge's own crafting window, not the primitive forge's. Whole steel sets melt down at a smelting or blast furnace; broken ones, like a broken sword blade, only at a blast furnace.

### What you can't craft

Found inverters, the maintainer, the solar battery charger, garden lights, factory modules, car alternators, and new deep cycle or L-16 batteries all have to be found. Treadmill motors, fridge compressors and microwave transformers come only from taking things apart. Cutting up a fridge (a blowtorch and a welding mask, as in vanilla) gives its compressor 10% of the time at Metalworking 0, 10% more for each level, and every time from Metalworking 9.

## When something isn't working

### A source's reason in the status window

| It says | What's wrong | What to do |
|---|---|---|
| night, cloudy, low sun | The sun | Wait, or add wind or a treadmill |
| snow | Snow on the panel | **Clear Snow**, or use racks and wall panels in winter |
| cracked | A cracked module | Seal or reglaze it |
| no free input | The bank ran out of inputs | Wire in a charge controller, repair a broken one, or disconnect a source you need less |
| too little wind | Below its starting speed | Wait for the wind |
| sheltered | Trees, buildings or walls around the blades | Move it into the open or up a floor |
| too close to another charger | Other chargers within three squares, at the same height | Move them four squares apart |
| gale, set the brake | The wind can break its blades | **Set the Brake** |
| braked | You set the brake | **Release the Brake** once the gale has passed |
| blades broken | A gale broke them, or they wore out | **Replace Blades** |
| turned out of the wind | The turbine furled in a gale | Nothing; it keeps most of its power |
| nobody running | A treadmill | **Run on Treadmill** |

### Other troubles

- **Turn On is greyed out**: the bank has no working inverter or no battery.
- **The bank does nothing**: it's outdoors, or not connected (**Connect Bank**).
- **The bank drains with everything off**: the inverter draws a few watts while the bank is on, and everything switched on in its reach counts, the neighbours' lights and fridges included. The status window lists what draws in other buildings.
- **The power keeps cutting out**: more is switched on than the inverters carry, including the neighbours' fridges. The status window says how much is in other buildings. Switch something off, or pick up their fridges.
- **Connect Sources in Reach finds nothing**: the bank isn't connected yet (**Connect Bank**), the source is indoors or under a roof, it's out of reach, or it's already connected to another bank (move it with **Connect to**).
- **A treadmill run banked nothing**: the bank had no free input.
- **A recipe is greyed out with everything in hand**: your skill is too low, or you need more light, a table, or the station it names.
- **A digester makes no gas**: it's still starting up, too cold, sour, full of sludge, or its holder is torn. Its **Status** says which.
- **A generator won't run on gas**: it needs a Gas Conversion Kit, a gas line (from a digester, one Rubber Hose for every 5 squares on the same floor; from a gasifier, right beside it, not diagonally), and its valve on **Run on Gas**. A gasifier must be lit, and a cold one needs bellows to light. When the gas runs out the generator stops and doesn't restart by itself.
- **A generator on gas keeps stalling**: more than it carries is switched on, or its gasifier needs the ash cleaned or the packing changed.
- **The Solar Failsafe doesn't start the generator**: it has no gasoline and no lit gasifier, it's worn enough to catch fire, or the failsafe isn't on the generator's square. The bank must drop to the start charge first (20% by default).

## Moving things and your save

- **Picking up.** Panels keep their modules, and garden lights keep their charge. Anything connected (a bank, a panel, a wind charger or a treadmill) must be disconnected before you can pick it up or turn it, as with a generator, and goes down again unconnected. A bank must also be emptied; a sledgehammer dumps what's in it on the floor. A generator with a gas kit fitted can't be picked up. A digester, gasifier or wind charger goes down again just as it was picked up, gas, feed, fittings, wear and all; nothing changes while you carry it. Its hopper must be empty, and a gasifier must be put out and its gas line disconnected. A gas heater goes out when its digester is picked up.
- **Scrapping.** A digester, gasifier or wind charger taken apart with the Moveables tool's Scrap mode gives back what built it: each piece comes back 70% of the time at level 0 of its recipe's first skill, 2% more for each level. Glue, tape, garbage bags, straw, cement and welding fuel are used up for good. A wind charger's motor or alternator and its blades always come off whole, broken blades broken, and a digester's Tarp Gas Bag, compressor and packed Iron Sponge come back as they were.
- **Adding to a save.** Loot and stocked rooms turn up only in containers and rooms nobody has opened or seen yet. Solar sites, rural finds and garden lights appear anywhere, explored or not.
- **Removing from a save.** What the mod built into your world goes with it.

## Where to look

Think about who had this gear in 1993, and how far they'd have hauled it. Rarity is relative to the mod's other items and moves with the Loot Rarity Multiplier options.

### Loot

Stores are the sure places: most electronics stores have a power aisle of inverters, chargers and the magazines, and every electronics store back room and camping store keeps a shelf of panels and batteries. Homes reward a long search: about one home in thirty has Homestead Power #1.

| What | Where to look | How often |
|---|---|---|
| Cracked solar modules | Crates, shelves and tool cabinets in home garages and sheds, more in farm storerooms and electronics store backrooms; trunks of junkyard cars | Common |
| Solar modules | Electronics store back rooms and camping stores, every one; hardware store back rooms, often; camper trailers, camping cars, phone and power company vans, electricians' vans and shelves, survivalists' trucks, generator rooms | Rare, except where they were sold |
| Deep cycle batteries | Electronics store back rooms and camping stores, auto parts battery shelves (far fewer than car batteries), mechanics' shelves, camper trailers, warehouses; now and then farms, fishing stores and garages | Uncommon |
| L-16 batteries | Phone and power company vans, generator and control rooms, battery crates | Very rare |
| Battery electrolyte | Auto parts stores, mechanics, garages | Common |
| Car alternators | Mechanics' shelves and crates, auto parts battery shelves, garages; or take one out of a car | Uncommon |
| Plug-in inverter | Auto parts stores, gas stations, electronics and department stores, garages, cars' glove boxes and trunks, truckers | Common |
| Power inverter | Electronics stores, auto parts battery shelves, electricians, campers, survivalists' trucks, generator rooms | Uncommon |
| Inverter/charger | Battery racks on off-grid farms and in farm storerooms and barns, generator and control rooms, phone, power company and electricians' vans, camper trailers, electronics store back rooms and camping stores now and then, stash houses | Rare |
| Charge controller | Electronics stores and their back rooms, camping stores, electricians, phone, power company and radio vans, generator and control rooms, camper trailers | Uncommon |
| Solar Failsafe | Generator rooms and stash houses, now and then | Very rare: easier to build |
| Solar battery maintainer | Auto parts stores, electronics stores, mechanics, farm supply and barns, fishing stores, campers, farmers' trucks | Uncommon |
| Solar battery charger | Electronics stores, camping stores, army surplus and survival gear, survivors' hideouts | Uncommon |
| Solar garden lights | Garden centres and hardware stores, garages and barns, and along front walks, more often in the nicer neighbourhoods | Common |
| Homestead Power #1 | Electronics stores, about every other one; bookstores, tool, outdoor and auto parts stores, post offices, libraries, campers, most crates of RV solar gear; about one home in thirty | Common |
| Homestead Power #2 | Where #1 is, half as often; electricians, utility and radio vans, generator and control rooms | Uncommon |
| Homestead Power #3 | Hardware stores' farming shelves and book racks, farm supply and farm storerooms, the farming shelf of a bookstore, farmers' trucks, living rooms; in barns, on a table or beside an old digester | Uncommon: nearly as often as #2 |
| Homestead Power #4 | Hardware, electronics and farm supply stores, bookstores' farming shelves, electricians, hobby shelves, living rooms; on barn tables | Uncommon: about two thirds as often as #2 |
| FEMA plans | Post offices, army surplus, police and fire stations, libraries, hardware store book racks, now and then a shelf at home; preppers, hunting shacks | Uncommon |
| A bit of everything | Prepper caches, and survivalists dead or alive | |
| Never found | The Gas Conversion Kit, Gas Heater, blades, treadmill motors and fridge compressors: craft or salvage them | |

### Places already set up

The named places are rolled once per world, so not all of them will be there, and batteries found in them hold part of a charge. Sandbox: **Solar Sites**, **Battery Bank Spawn**, **Stash Houses**.

Folks put their panels where the sun is, which is usually up on the roof, and few of those roofs come with stairs. Bring what you need to build your own way up.

| What | Where | What you'll find |
|---|---|---|
| Stocked storerooms | Farm storerooms, barns and sheds, and now and then garages and storage units, the first time anyone sees them | A battery box or rack with a few batteries, sometimes an inverter; a rack in a farm storeroom or barn, or a box in a shed, garage or storage unit, often has a panel or two lying beside it; in garages and storage units, now and then a crate of RV solar gear: always panels and batteries, usually Homestead Power #1 |
| Stock tank pumps | Pastures across the farm country | A rack of panels by a water tank |
| Off-grid farms | A few farms around Riverside, Rosewood and West Point | Panels on the roof, a rack of batteries inside, often with an inverter/charger and a charge controller, garden lights |
| Campers | Trailer parks, a summer camp, a trailer in the woods | Two panels on the roof and a box with two deep cycles |
| Phone company relay sheds | By the radio masts on the hills around Brandenburg, Irvington and Riverside | Racks of panels, a few L-16s and a charge controller |
| The power company yard | A substation outside Muldraugh | The station battery: a bank of L-16s and its charger |
| Ranger stations | By the lakes in the parks | Wall panels, racks and a battery box |
| Fire lookout towers | Up in the woods south of Riverside and by Doe Valley | Panels hung on the catwalk railing, and a battery box in the cab, usually with an inverter |
| Old wind farms | Farmland near Echo Creek and Ekron | A treadmill wind charger with broken blades, wired to a barn's tired batteries, usually with a charge controller |
| A dairy | Near Ekron | A sour digester piped to a run-down generator with a gas kit |
| A prepper's cabin | In the woods near Echo Creek | A dirty gasifier piped to a generator, and the plans that built it |
| Arrow board trailers | Road works around Muldraugh, Riverside and Rosewood, the checkpoints outside Louisville, and traffic jams and junkyards anywhere | Two panels, often one cracked, a box of worn deep cycles, usually a charge controller |
| Barns | Now and then, by barns and farm storage | An old treadmill wind charger with broken blades |
| Livestock buildings | Now and then, by barns, stables, coops and pigsties | A barrel digester, gone sour, its bags torn, sometimes with Homestead Power #3 left in the building |
| Hunting shacks | Often, by hunting shacks and deer stands | A primitive gasifier full of ash and tar, sometimes with the FEMA plans in the shack |
| Stash houses | Four of them, each marked on an annotated map. Survivalists and preppers carry one map, campers another, and two are on town maps | A crate of solar gear, and more crates and shelves of panels and batteries |
