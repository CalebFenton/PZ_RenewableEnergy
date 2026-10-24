# Renewable Energy: player's guide

The crafting window lists every recipe, and tooltips and **Status** windows give the numbers for whatever you're looking at. This guide covers the rest: what each thing is for, how one setup leads to the next, and the rules that decide whether it pays off. Figures are rounded and assume the default sandbox settings.

- [How power works](#how-power-works)
- [Your first setup](#your-first-setup)
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

## How power works

There are two ways to keep the lights on, and most homesteads end up using both.

**A battery bank.** Panels, wind chargers and treadmills charge the bank's batteries, and its inverter turns that charge into power for the house. Underneath, a bank is a generator that burns no fuel and makes no noise: it powers whatever a generator in its spot would, with the same reach and floors.

**A generator on gas.** A Gas Conversion Kit lets a vanilla generator run on gas from a manure digester or a wood gasifier instead of gasoline. It's still loud, and it still draws the dead, but it keeps going once the gas stations run dry.

They work together: a charger wired into the bank fills it from a running generator, and a **Solar Failsafe** starts the generator when the batteries run low. You get quiet power most days, and the generator's roar only when the weather fails you.

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

The inverter also loses a tenth of what passes through it, and draws a few watts while it's on. Everything in the bank's reach counts, the neighbours' lights and fridges included, so set up away from town or switch off what you don't need.

## Your first setup

You need a **Wooden Battery Box** (Homestead Power #1, or Woodwork), two car batteries, a **Plug-in Inverter** from an auto parts store or a car's glove box, and a solar module or two.

1. Place the box inside a building, in a room. Outdoors, it does nothing.
2. Right-click it and **Wire In** the batteries and the inverter. That takes a screwdriver, some Electric Wire and enough light to see by.
3. **Connect Bank**, as you would connect a generator: Electricity 3, or the generator magazine.
4. Build a **Flat Solar Panel** around a module, place it outdoors within 20 squares of the box, then right-click the box and **Connect Sources in Reach**.
5. **Turn On**, and open **Status** to see what's coming in and going out.

The box holds about 1.2 kWh, and the plug-in inverter carries 300 W: enough for the TV, the radio and the lights through an evening. A fridge fits too, but two car batteries carry one through only about six hours of darkness, and draining them flat every night halves their capacity in about a month. Run the fridge while the sun's up, and save up for bigger batteries and a bigger box.

While the grid is still on, the bank stands by. Nothing drains it, the panels keep filling it, and it takes over within minutes of the shutoff.

## Moving up

Every piece has a better version. Mostly you upgrade by building the next one and moving your parts across: **Unwire** them from the old bank and **Wire In** them on the new one. Batteries keep their charge and condition, and panels keep their modules.

### Storage

| Storage | Batteries (metal) | Inverters | Chargers | Controllers | Inputs at most |
|---|---|---|---|---|---|
| Battery box | 2 (2) | 1 | 1 | 0 | 2 |
| Battery rack | 6 (8) | 1 | 2 | 2 | 16 |
| Battery bank | 12 (16) | 2 | 2 | 4 | 30 |

A metal rack or bank holds more batteries than a wooden one; a metal box holds the same two.

### Inverters

The inverter decides how much you can switch on at once. With two inverters, a bank carries what both add up to.

| Inverter | Carries | Wire it in at | Found |
|---|---|---|---|
| Plug-in Inverter | 300 W | Electricity 0 | Common |
| Power Inverter | 600 W | Electricity 2 | Uncommon |
| Inverter/Charger | 1000 W | Electricity 4 | Rare |

Inverters can't be crafted. The Inverter/Charger also has a 1000 W charger built in (see [Chargers and generators](#chargers-and-generators)). As a guide, 300 W runs a fridge with the TV, the radio and the lights; 600 W adds the washer or the stove; 1000 W runs a fridge-freezer, the stove and the washer at once; a pair of inverter/chargers runs the whole house.

### Sources

A usual climb:

- **Two flat panels**, for summer days.
- **Wall panels and ground racks** for winter, and a **scoop rotor** for a trickle at night.
- A **treadmill wind charger** and a handful of panels, enough for a fridge around the clock.
- A **car alternator wind charger**, then a **homebuilt wind turbine** on high, open ground.
- A generator on biogas or wood gas as the backup, started by a **Solar Failsafe**.

### Batteries

Car batteries come first, then **Deep Cycle Marine Batteries**, which hold twice as much and last far longer, then **L-16s**, found mostly where the phone and power companies kept them. You can make a **Jar Battery** from scratch when you can't find anything better. See [Batteries](#batteries).

### Gas

| Line | Small | Medium | Large |
|---|---|---|---|
| Digesters | Barrel Digester | Insulated Digester: three times the barrel, built new or upgraded from a barrel | Brick Dome Digester: three times again, buried and warm |
| Gasifiers | Primitive Gasifier (trash can) | Gasifier (steel drum) | Advanced Gasifier (welded sheet metal) |

A bigger digester holds more feed and gas and rides out cold snaps. **Upgrade to Insulated Digester** keeps what's inside the barrel. The brick dome sits in a pit you dig, so it goes only where you could dig a grave: earth, grass or sand at ground level, not a floor or pavement. A bigger gasifier carries more fuel and makes less ash.

### Sizing a bank

Size the batteries so that one night uses about half of them or less. Wear grows with how deep you drain them (see [Wear](#wear)), so a bank twice the size lasts four times as long.

For a fridge through a twelve-hour night you need about 2 kWh out of the batteries. That's more than a box of car batteries holds, but less than a third of a rack of six deep cycles, which will last you years.

## Battery banks

### Placing

A box, rack or bank works only inside a building's room. Like furniture, it turns to face any way as you place it: hold the mouse button and move the cursor the way it should face. Its charge meter is on the front. One you find stands with its back to a wall, already connected but switched off.

### Wiring parts in

Parts go in with **Wire In** and come out with **Unwire**; you can't drag them. **Wire In** lists every part you carry by type, each with its condition. **Wire In > All Batteries** fills the bank with your best batteries first, and **Unwire > All Batteries** empties it in one go. What doesn't fit in your inventory lands at your feet.

Every part takes a screwdriver, Electric Wire and light to see by; an L-16's cable lugs bolt on, so it takes a wrench too. Unwiring takes the same tools and gives the wire back. The first time an item is wired in, it gives Electricity XP, and higher Electricity makes the work faster. A charge controller needs Electricity 3 and an Electronics Scrap.

**Turn On** stays greyed out until the bank has a working inverter and a battery.

### What it powers

The bank powers everything a generator in its spot would, including the floors above and below. It takes over within minutes of the grid shutoff, which comes when vanilla's Electricity Shutoff option says. It keeps charging and draining while you're away, and anything left switched on in its reach keeps drawing. Mods that tell it what their machines draw are billed the same way: Enhanced Irrigation's Pump Houses show in the status window while they run.

### Overload

If more is switched on than the inverters can carry, the whole area goes dark. A bank powers everything or nothing; it never drops just the dryer. Switch something off and the power comes back at the next update, or turn the bank off and on to bring it back at once. Every overload costs each inverter a little condition.

At zero charge the power cuts too. It comes back by itself once some charge has built up, so a bank that barely charges doesn't flicker on and off.

### Inputs

A bank has 2 inputs of its own, and each working **Charge Controller** adds 7. Each source takes some:

| Source | Inputs |
|---|---|
| Any solar panel, including a ground rack's two modules | 1 |
| Scoop rotor, treadmill | 1 |
| Treadmill or car alternator wind charger | 2 |
| Homebuilt wind turbine | 3 |

Inputs go in the order you connected the sources. Sources past the last input stay connected but make nothing, and the status window says "no free input". A broken controller loses its inputs, so check them when a source goes quiet.

### Reach

**Connect Sources in Reach** picks up every source within 20 squares and 3 floors of the bank. A bank takes sources only once it's connected itself (**Connect Bank**). Panels and wind chargers must stand outdoors; a treadmill can be under a roof. Move a source and it drops off its bank, so connect it again.

### Chargers and generators

A wired-in vanilla **Car Battery Charger** (100 W), or the charger built into an **Inverter/Charger** (1000 W), fills the batteries from the grid, or from a running generator whose reach covers the bank. That generator burns fuel for the charging as it would for an appliance of those watts. Chargers only top up what your sources leave unfilled. Without one, grid and generator power charge nothing.

A running generator within 3 squares of the bank, on its floor, takes over the load while it runs, and the batteries rest.

### Solar Failsafe

Place it on a generator's square. It starts the generator when the bank drops to the start charge (20% by default) and stops it at the stop charge (80%). It won't start a generator with no fuel, or one worn enough to catch fire. Without a charger in the bank, the generator only carries the load, and the charge climbs only as fast as your sources fill it. Sandbox: **Failsafe Start Charge**, **Failsafe Stop Charge**.

### Upkeep

Inverters lose condition every hour the bank powers its area, about one Electronics Scrap's worth every two and a half weeks. Controllers wear half as fast, so even a full metal bank needs only a scrap every few days. **Repair with Scrap** in the bank's menu (Electricity 2) adds the same amount for each scrap. A part at zero is broken, but you can still repair it. Found inverters and controllers are usually in good shape, but now and then one is a dud.

### The status window

**Status** walks you over to the bank and opens a window that closes once you walk more than 4 squares away. It shows:

- Whether the bank is charging or draining, by how much, and how long until it's full or empty.
- The load against the limit, and the inputs used.
- Each battery's charge, condition and a repair hint.
- Each source's output, and the biggest reason it falls short. Reasons you can fix are in red. Click a source to see where it stands.

While grid power reaches the bank, the window says so, and whether the chargers are filling from it. **Rename** gives a bank a name of your own, which helps once you have several.

## Batteries

| Battery | Holds | Years to half capacity, drained half (a quarter) nightly | Fits a car |
|---|---|---|---|
| Car battery | 600 Wh | 0.4 (1.6) | Yes |
| Deep Cycle Marine Battery | 1260 Wh | 1 (4) | Yes |
| L-16 Battery | 2100 Wh | 2 (8) | No |
| Jar Battery | 400 Wh | 0.2 (0.8) | No |

The tooltip shows each battery's capacity and stored charge. Capacity falls with condition.

### Shared charge

All the batteries in a bank share one charge level. Wire in a full one next to empty ones and the charge evens out; a battery you unwire leaves at the bank's level. Found batteries hold between a third and four fifths of a charge.

### Wear

Once a game day, each battery wears by that day's deepest drop from its peak. Wear grows with the square of the depth, so draining half as deep wears a quarter as much. That's why a bigger bank pays for itself: the same load drains it less deeply. Temperature doesn't matter. Sandbox: **Battery Wear**.

### Keeping batteries going

Batteries never last forever, but you can bring them back a few times before they need rebuilding:

1. **Service Battery**: Electricity 1, water, and a rag or baking soda. A small boost, and it keeps its charge.
2. **Recondition Battery** (learned from Homestead Power #2): water and baking soda bring it straight up to its ceiling, but leave it empty.
3. **The ceiling**: each service or recondition lowers how far the next one can bring it back. After a handful, it needs a rebuild.
4. **Rebuild**: **Strip** the battery (gloves, and containers to catch the acid) for its case, worn plates and acid. Recast the plates at a furnace in a fired clay mold. Some lead burns off, so three worn sets make two, and a lead pipe can stand in for one set. Then rebuild with acid and water. The battery comes back like new, empty, with its repair count cleared.

Acid can't be made. It comes from auto parts stores and garages, or from batteries you strip. A rebuild keeps the battery's kind: a deep cycle or L-16 can only be rebuilt from its own case.

### Found batteries

Batteries in a bank you find have been used, and the riskier the place, the better they are. Sheds and farm storerooms hold well-worn ones that are worth reconditioning. Homesteads, storage units and utility sites hold batteries at around four fifths, a few as good as new, and an electronics store's backroom stock is nearly new. Now and then one is a dud: nearly dead, and repaired too often for reconditioning to help. Strip it for a rebuild instead.

### Jar battery

Six glass jars, one set of plates (three lead pipes cast a set), acid and water. It's small and short-lived, but everything except the acid can be made.

### In a car

A deep cycle fits a car's battery slot. It runs the lights and radio twice as long and takes twice as long to fill from the alternator. L-16s and jar batteries are heavy items, like a generator: you can carry one in a car, but you can't take it into your inventory while you sit in the car. Get out and take it from the seat through the door.

## Solar panels

### Mounts

Each mount holds factory or homemade modules, and each suits a different season:

| Mount | Modules | Best in | A new module banks a day, July / December |
|---|---|---|---|
| Flat Solar Panel | 1 | Summer | 1.7 / 0.5 kWh |
| Wall-Mounted Solar Panel | 1 | Winter | 0.7 / 0.9 kWh |
| Solar Ground Rack | 2 | All year | 1.5 / 0.9 kWh per module |

Those are averages over the weather; a clear day gives half again or more, and a grey week much less. A flat panel lies flat and likes the summer sun high overhead. A wall panel goes on an outside wall facing south or east, and gets extra light off fresh snow; an east wall gets only morning sun. A ground rack tilts its two modules and faces any way you place it, which makes it the most even across the year.

As a rule of thumb, three flat panels run a fridge through a July day and night, and it takes five modules on racks or walls in December. Sandbox: **Sunlight Multiplier**.

### Weather and snow

Overcast skies take most of the light. Fog and rain take some more, and falling snow halves what's left. Wind doesn't matter to a panel.

Snow piles up on flat panels and racks, and output drops by the share covered. A rack sheds its snow within a few hours in sun or mild air. A flat panel loses its snow only as it melts above freezing, unless you **Clear Snow** with a broom or a snow shovel. Wall panels never hold snow.

### Storms

A thunderstorm with strong wind can crack a module; a gale without thunder can't. You hear the glass go, and anyone within about 30 squares sees "A solar module cracked in the storm". Each crack costs the module 20 condition, and output follows condition: a module at half makes half.

| Mount | Storm risk |
|---|---|
| Wall panel | Never cracks |
| Metal ground rack | Least |
| Flat panel | Middling |
| Wooden ground rack | Most |

At the default rate, ten panels lose about one module every four to six months. Even the longest run of thunderstorms cracks a module on a wooden rack only about one time in seven. Every panel standing outdoors is at risk, connected or not. Sandbox: **Storm Damage**, **Storm Damage Rate**.

The glass shows how worn a module is: whole down to 85% of its best condition, a few fine cracks below that, and heavy cracks below half. A new module's first crack always shows.

### Fixing modules

Sealing is the cheap fix, reglazing the good one.

- **Seal Cracked Module** takes a screwdriver and either 1 use of epoxy or 2 of glue. Seal a loose module in the crafting window (with glue, pick **Seal Cracked Module With Glue**), or one still on a placed panel from the panel's menu. It brings back some condition, but only up to a ceiling that drops with every seal, and the glass still looks cracked.
- **Reglaze Module** puts on a new pane of glass. **Unmount** the module first. It looks whole again, and its seal count clears. If its cracks were light, it's as good as new; if they were heavy, or you'd sealed it, the cells underneath cracked too and it comes back to 90% of new.

**Unmount** always gives back the same modules at the same condition, plus some of the frame.

### Homemade modules

A **Homemade Solar Module** is 16 solar cells under glass. Cells come from taking apart calculators, garden lights, solar battery chargers, maintainers, and shattered modules (only at zero condition). A homemade module tops out at 60% of a factory one, so its glass cracks at 51 and 30.

## Wind chargers

Wind blows day and night, and hardest in winter, just when the panels give the least. Wind chargers are built on the **Welding** page of the build menu, and each needs a generator: a treadmill's motor, a car's alternator, or an alternator you make yourself.

### The four kinds

| Charger | Generator | Full output | Inputs | Breaks in storms |
|---|---|---|---|---|
| Scoop Rotor Wind Charger | Treadmill Motor | 480 W at 50 km/h | 1 | Never |
| Treadmill Wind Charger | Treadmill Motor | 1600 W at 40 km/h | 2 | Yes |
| Car Alternator Wind Charger | Car Alternator | 2000 W at 40 km/h | 2 | Yes |
| Homebuilt Wind Turbine | Homemade Alternator | 3200 W at 40 km/h | 3 | Yes, but turns aside in a gale |

- **Scoop rotor**: two half-drum scoops on a short pole. It never needs the brake and never breaks, but it makes little.
- **Treadmill wind charger**: three blades high on a pipe mast. It's the first charger that makes real power.
- **Car alternator wind charger**: the same mast belted to a car's alternator. It makes a quarter more in any wind for the same inputs, a straight upgrade.
- **Homebuilt wind turbine**: speaker magnets on a car's brake hub turning past hand-wound coils. It makes double the treadmill charger's power, and its tail swings it out of a gale.

### How much the wind gives

A charger makes nothing below its starting speed, and output climbs with the cube of the wind until full output. Halfway from its starting speed to full output, it makes only an eighth:

| Wind | Scoop | Treadmill | Car alternator | Turbine |
|---|---|---|---|---|
| 20 km/h | 10 W | 60 W | 75 W | 145 W |
| 25 km/h | 30 W | 200 W | 250 W | 440 W |
| 30 km/h | 70 W | 475 W | 595 W | 995 W |
| 35 km/h | 130 W | 925 W | 1160 W | 1890 W |
| 40 km/h | 210 W | 1600 W | 2000 W | 3200 W |

That's in the open on the ground. The status window shows the wind in km/h next to each charger's output.

### Where to put one

Placement matters as much as the charger: get it high, get it clear, and give it room.

- **Height.** A charger makes 15% more for each floor it stands on above the ground, up to the third floor (45% more). What counts is the floor you place it on, not its own mast, so building up is worth the effort.
- **Shelter.** Trees, buildings and solid walls within 8 squares steal wind, the nearer the more. A hemmed-in charger loses most of its output, and the status window says "sheltered". Only what reaches the blades' height counts: a scoop's blades turn at its own floor, a mast charger's a floor above. So walls count only on the blades' floor, buildings only when their roof reaches the blades, and trees only while the blades are within two floors of the ground. Fences and windows never count.
- **Spacing.** Keep chargers **four squares apart**. Any closer, and each charger whose blades turn at the same height takes a share of the other's wind: a quarter right beside it, a sixth at two squares, a twelfth at three. Every neighbour takes its share, so a cluster adds up, and once a charger loses a sixth the status window says "too close to another charger". Chargers don't count as shelter, and a scoop on the ground never crowds a mast charger, whose blades turn a floor higher.

### Storms and the brake

Blades break in gales. **Set the Brake** before one and **Release the Brake** after it. A braked charger makes nothing, and its blades can't break.

A charger warns you when the wind gets strong enough to break its blades. Wooden blades creak and pipe or steel blades rattle every few seconds, and the status window says "gale, set the brake". The stronger the wind, the likelier they break. When they go, there's a loud crack, and anyone within about 30 squares sees "A wind charger's blades broke in the gale".

| Blades | On the treadmill and car alternator chargers | On the turbine |
|---|---|---|
| Plastic Pipe Blades | At risk above 60 km/h: strong thunderstorms | Above 80 km/h |
| Carved Wooden Blades | Above 70 km/h: the worst thunderstorms | Above 90 km/h: safe in every thunderstorm |
| Forged Steel Blades | Above 90 km/h: only blizzards and tropical storms | Above 110 km/h: all but the worst blizzards |

Once at risk, steel blades break a quarter as often as pipe, and wood half as often. Thunderstorms top out around 84 km/h. Blizzards blow 90 to 120 km/h for a day or two and are the real danger, though even the longest breaks unbraked pipe blades at most about one time in seven at the default Storm Damage Rate. Blades never change the power, only how much wind they stand.

From 55 km/h, the homebuilt turbine's tail swings its head out of the wind ("turned out of the wind"). It keeps 85% of its full output, and its blades take less of the gale, which is why they hold 20 km/h longer.

### Replacing blades

**Replace Blades** fits a spare set onto a charger whose blades broke. It takes any kind the charger can use, its own kind first if you carry them, so a broken pipe-blade charger can come back with steel. You get the broken set back: broken wood burns in a campfire, fireplace or wood stove, broken pipe is junk, and broken steel melts down at a blast furnace. Blades that are still whole can't be swapped, so to change kinds on a working charger, build a new one.

### Making the generators

- **Treadmill Motor**: take a treadmill apart. Every one gives its motor.
- **Car Alternator**: in the vehicle mechanics window, the engine's menu has **Take Out Alternator** (engine off, a wrench, Mechanics 2; it opens the hood if it's shut). Each car has one. The car still runs without it, but it stops charging its battery until you **Put Back Alternator**. Cutting up a smashed wreck gives one as often as it gives engine parts, more with Metalworking and Mechanics; a burnt wreck never does. Mechanics' shelves and auto parts stores have them too.
- **Homemade Alternator**: a car's brake, two speakers (or four portable radios, for their smaller speakers' magnets), four lengths of wire, two Electronics Scrap and a small sheet of metal, with a screwdriver and a wrench, at Electricity 5 and Mechanics 3.

## Treadmills

No sun and no wind? Run for it.

**Wire the Motor** on a treadmill (Electricity 2, a screwdriver, wire and an Electronics Scrap), then connect it to a bank like any source. **Run on Treadmill** lasts half an hour and banks roughly what a fridge-freezer draws in that time. The energy goes in when the run ends and reaches the batteries over the next half hour; stopping early banks your share of the run.

A run costs a good chunk of endurance and some thirst, and trains Fitness and Sprinting. You stop by yourself when you're nearly spent. If the bank has no free input, the run still tires you, but the energy is lost.

**Unwire the Motor** with the screwdriver gives the wire back, and so does picking the treadmill up, which forgets its wiring. Where there's power from the grid, a generator or a bank, an unwired treadmill is plain exercise equipment, and on a bank it draws about what a washer does.

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

A digester turns manure and rotten food into gas, slowly and steadily, for weeks. It's the backup that needs no trip to town, as long as you keep animals and keep it warm.

### How it works

1. **Feed it.** Put feed in the hopper. One item goes into the tank each hour, while there's room; the rest waits in the hopper.
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
| Rotten or compostable food | 0.12 m³ a kg | Sours it |
| Rotten meat and fish | 0.2 m³ a kg | Sours it twice as fast |
| Wood ash, baking soda | None | Settles it |
| Quicklime | None | Settles it twice as much |

Each manure item stands for about a day of what the animal makes. Hens drop nothing inside their hutch, only out in their pen. Fresh food is refused. Sandbox: **Biogas Multiplier**.

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

### Sludge

Each feeding adds sludge. Output halves once the tank is nearly full of it. **Take Sludge** fills sandbags or compost bags with compost, a tenth of the tank per bag.

### Gas holders

The gas waits in a holder until something burns it. Gas made past what the holder can take is wasted, so a small holder needs a generator that runs often.

| Holder | On | Holds | Wear |
|---|---|---|---|
| Garbage bags | Barrel | 0.6 m³ | Tear within a few months |
| Sewn tarp | Barrel | 1 m³ | Lasts about four times as long |
| Floating drum | Insulated digester | 1.5 m³ | Never wears out |
| The dome itself | Brick dome | 4 m³ | Never wears out |

**Replace Gas Bags** or **Sew Tarp Gas Bag** to fix a torn holder; either loses the gas stored in it. **Vent Gas** empties the holder.

### Smell and fumes

A digester smells worst while starting up, when sour, or when full of sludge, and a settled one mellows over its first weeks. The insulated digester smells about half as much as a barrel, and the dome stays faint. Indoors, any digester smells twice as bad.

Players nearby get vanilla's noxious smell moodle and can get sick from it, just as with corpses; gas masks help. The game counts smell in blocks of 8 by 8 squares. An outdoor digester at its worst smells strongest in its own block, one level less a block away, faintly two blocks away, and not at all three blocks off. One indoors smells only inside its building.

A barrel or insulated digester inside a building poisons the whole building while it's sour, and for a while each time its holder overflows or is vented. The dome is sealed and never fumes. Build them outside, away from where you sleep.

### Bottling

Generators burn raw gas, but bottling it needs it cleaned first.

- **Fit Scrubber**, then **Charge Scrubber** with water (cleans about 5 m³), water and wood ash (15 m³) or water and quicklime (30 m³). A new charge replaces the old one. Its steel wool cleans about 10 m³ per use before you **Repack Steel Wool**.
- **Fill Propane Tank (Tire Pump)** fills a tank only a quarter of the way, and it's tiring work.
- **Fill Propane Tank (Compressor)** fills it all the way where there's power, using scrubbed gas past the first quarter. Salvage a **Fridge Compressor** by cutting up a fridge.

A propane tank refills lantern bottles. Where there's power, a carried Fridge Compressor inflates tires too.

Digesters keep digesting, and eating from their hoppers, while you're away.

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

### Upkeep

- **Ash.** The ash pit fills as it burns, fastest in the primitive gasifier. A full pit halves the gas. **Clean Out Ash** with a shovel gives **Wood Ash**, which settles a sour digester or charges a scrubber.
- **Filter.** The filter holds hay, straw, grass or splinters, which turn into **Tarry Packing** as it burns. Change the packing in time: once no clean packing is left, tar reaches the engine, for half the gas and fast wear. Tarry packing wears the generator faster even before then.
- **Condensate.** Burning fills a condensate drain, and while it's full, tar builds up twice as fast. **Drain Condensate** into a metal or glass container while the gasifier is lit. It's wood vinegar: poisonous to drink, but mixed with water it makes mildew spray and aphid spray.

A lit gasifier inside a building poisons the whole building. While nobody is near, it burns only what's already in its firebox, then goes out and cools, and the generator stops.

## Small gadgets and the arrow board

These need no bank.

- **Solar Battery Maintainer**: **Attach Solar Maintainer** to a car and it trickle-charges whatever battery is in it, in daylight, while the car stands in the open; in a garage it does nothing. It keeps a parked car topped up but is too slow to revive a flat battery. It stays with the car when you swap batteries.
- **Solar Battery Charger**: place it outside and load up to four flashlight batteries. They charge in daylight, emptiest first, so a full tray takes a few sunny days.
- **Solar Garden Light**: outside, on the ground floor. It charges by day and lights up after sunset until the charge runs out, which on a short winter day can be early in the evening. Right-click to swap the bulb for a coloured one. Found lights start without charge, and picking one up keeps its charge and bulb.

Gadgets charge only while someone is near enough for the area to be loaded. A car parked across the map isn't charging.

### The arrow board trailer

Road crews left solar arrow board trailers behind at road works, checkpoints and traffic jams, still flashing. Each has two panels on top and a box of worn deep cycles on its tongue, usually with a charge controller. The panels keep the batteries charged and the arrow lit, and after dark the lamps light the ground around it.

- **The box** is usually padlocked: cut the lock or unbolt the lid.
- **The panels** come off in the mechanics window and give their modules, and any module goes back on. **Seal Cracked Panel** fixes a cracked one in place.
- **Crashes** crack the panels. A hard crash while you tow it does; bumps and hard braking don't. **Repair Frame** fixes a dented frame.

Tow it home and it keeps charging its batteries on the way, or strip it for parts.

## Learning and crafting

### Magazines and plans

| Read | It teaches |
|---|---|
| Homestead Power #1: Sun & Batteries | Battery boxes and racks, every panel mount, sealing |
| Homestead Power #2: Inverters & Control | Battery banks, the charge controller, the failsafe, homemade modules, reglazing, reconditioning, the whole battery rebuild |
| Homestead Power #3 | Digesters, the Gas Conversion Kit, the Gas Heater |
| Homestead Power #4 | Every wind charger, their blades, the homemade alternator |
| FEMA Wood Gas Generator Plans | The three gasifiers, the Gas Conversion Kit, the wood vinegar sprays |

### Other ways to learn

- **Skills.** Every recipe is also learned by reaching a skill level, usually above what crafting it needs, so a magazine gets you there sooner. Boxes, racks, banks and panels come from Woodwork, Metalworking or Electricity. Battery work and controllers come from Electricity, digesters from Farming plus a building skill, gasifiers from Mechanics and Metalworking, wind chargers from Metalworking and Electricity, and the car alternator wind charger takes Mechanics too.
- **Research.** Researching a found module teaches the panel mounts and sealing, and a homemade one teaches sealing. A plug-in inverter teaches battery boxes, a power inverter racks, and an inverter/charger banks and the failsafe.

### What a recipe needs around it

Most recipes need a table, and every one needs light to see by, as most of vanilla's do. Recasting plates needs a furnace, the plate mold a hand press and a kiln, and steel blades a forge.

Light is also needed for wiring and fittings: wiring parts in and out, wiring a treadmill, connecting or disconnecting a source or a bank, replacing blades, repairing parts and panels, and fitting or removing a Gas Conversion Kit or its gas line. Switches, valves, brakes, bulbs and chores like clearing snow or ash don't need it.

### Blades

**Carve Wooden Blades** (Carving) and **Cut Pipe Blades** are in the crafting window. **Forge Steel Blades** (Blacksmith 3) is only in a Forge's or an Advanced Forge's own crafting window, not the primitive forge's. Whole steel blades melt down at a smelting or blast furnace; broken ones, like a broken sword blade, only at a blast furnace.

### What you can't craft

Inverters, the maintainer, the solar battery charger, garden lights, factory modules, car alternators, and new deep cycle or L-16 batteries all have to be found. Treadmill motors and fridge compressors come only from taking things apart. Cutting up a fridge (a blowtorch and a welding mask, as in vanilla) gives its compressor 10% of the time at Metalworking 0, 10% more for each level, and every time from Metalworking 9.

## When something isn't working

### A source's reason in the status window

| It says | What's wrong | What to do |
|---|---|---|
| night, cloudy, low sun | The sun | Wait, or add wind or a treadmill |
| snow | Snow on the panel | **Clear Snow**, or use racks and wall panels in winter |
| cracked | A cracked module | Seal or reglaze it |
| no free input | The bank ran out of inputs | Wire in a charge controller, or repair a broken one |
| too little wind | Below its starting speed | Wait for the wind |
| sheltered | Trees, buildings or walls around the blades | Move it into the open or up a floor |
| too close to another charger | Other chargers within three squares, at the same height | Move them four squares apart |
| gale, set the brake | The wind can break its blades | **Set the Brake** |
| braked | You set the brake | **Release the Brake** once the gale has passed |
| blades broken | A gale broke them | **Replace Blades** |
| turned out of the wind | The turbine furled in a gale | Nothing; it keeps most of its power |
| nobody running | A treadmill | **Run on Treadmill** |

### Other troubles

- **Turn On is greyed out**: the bank has no working inverter or no battery.
- **The bank does nothing**: it's outdoors, or not connected (**Connect Bank**).
- **The power keeps cutting out**: more is switched on than the inverters carry, including the neighbours' fridges. Switch something off.
- **A recipe is greyed out with everything in hand**: you need more light, a table, or the station it names.
- **A digester makes no gas**: it's still starting up, too cold, sour, full of sludge, or its holder is torn. Its **Status** says which.
- **A generator on gas keeps stalling**: more than it carries is switched on, or its gasifier needs the ash cleaned or the packing changed.

## Moving things and your save

- **Picking up.** Panels keep their modules, and garden lights keep their charge. A bank must be disconnected and emptied before you can pick it up; a sledgehammer dumps what's in it on the floor. A picked-up treadmill forgets its wiring. A generator with a gas kit fitted can't be picked up.
- **Banks from an older version.** A box, rack, bank or gas heater from before they could turn works as before but won't turn. One standing in your world turns once you pick it up and place it again. One you were carrying places facing south only: place it, pick it up, and from then on it turns.
- **Adding to a save.** Loot and stocked rooms turn up only in containers and rooms nobody has opened or seen yet. Solar sites, rural finds and garden lights appear anywhere, explored or not.
- **Removing from a save.** What the mod built into your world goes with it.

## Where to look

Think about who had this gear in 1993, and how far they'd have hauled it. Rarity is relative to the mod's other items and moves with the Loot Rarity Multiplier options.

### Loot

| What | Where to look | How often |
|---|---|---|
| Cracked solar modules | Crates, shelves and tool cabinets in home garages and sheds, more in farm storerooms and electronics store backrooms; trunks of junkyard cars | Common |
| Solar modules | Camper trailers, camping cars, phone and power company vans, electricians' vans and shelves, survivalists' trucks, generator rooms | Rare |
| Deep cycle batteries | Auto parts battery shelves (far fewer than car batteries), mechanics' shelves, camper trailers, electronics store backstock and warehouses; now and then farms, fishing stores and garages | Uncommon |
| L-16 batteries | Phone and power company vans, generator and control rooms, battery crates | Very rare |
| Battery electrolyte | Auto parts stores, mechanics, garages | Common |
| Car alternators | Mechanics' shelves and crates, auto parts battery shelves, garages; or take one out of a car | Uncommon |
| Plug-in inverter | Auto parts stores, gas stations, electronics and department stores, garages, cars' glove boxes and trunks, truckers | Common |
| Power inverter | Auto parts battery shelves, electricians, campers, survivalists' trucks, generator rooms | Uncommon |
| Inverter/charger | Generator and control rooms, phone, power company and electricians' vans, camper trailers | Rare |
| Charge controller | Electricians, phone, power company and radio vans, generator and control rooms, camper trailers | Uncommon |
| Solar Failsafe | Generator rooms, now and then | Very rare: easier to build |
| Solar battery maintainer | Auto parts stores, mechanics, farm supply and barns, fishing stores, campers, farmers' trucks | Uncommon |
| Solar battery charger | Electronics stores, camping stores, army surplus and survival gear, survivors' hideouts | Uncommon |
| Solar garden lights | Garden centres and hardware stores, garages and barns, and along front walks, more often in the nicer neighbourhoods | Common |
| Homestead Power #1 | Electronics store magazine racks, bookstores, tool, outdoor and auto parts stores, post offices, libraries, living rooms, campers | Common |
| Homestead Power #2 | Where #1 is, less often; electricians, utility and radio vans, generator and control rooms | Uncommon |
| Homestead Power #3 | Hardware stores' farming shelves and book racks, farm supply and farm storerooms, the farming shelf of a bookstore, farmers' trucks, living rooms; in barns, on a table or beside an old digester | Uncommon: about half as often as #2 |
| Homestead Power #4 | Hardware, electronics and farm supply stores, bookstores' farming shelves, electricians, hobby shelves, living rooms; on barn tables | Uncommon: about two thirds as often as #2 |
| FEMA plans | Post offices, army surplus, police and fire stations, libraries, hardware store book racks, now and then a shelf at home; preppers, hunting shacks | Uncommon |
| A bit of everything | Prepper caches, and survivalists dead or alive | |
| Never found | The Gas Conversion Kit, Gas Heater, blades, treadmill motors and fridge compressors: craft or salvage them | |

### Places already set up

The named places are rolled once per world, so not all of them will be there, and batteries found in them hold part of a charge. Sandbox: **Solar Sites**, **Battery Bank Spawn**, **Stash Houses**.

Folks put their panels where the sun is, which is usually up on the roof, and few of those roofs come with stairs. Bring what you need to build your own way up.

| What | Where | What you'll find |
|---|---|---|
| Stocked storerooms | Sheds, garages, storage units, farm storerooms and electronics store backrooms, the first time anyone sees them | A battery box or rack with a few batteries, sometimes an inverter; a box in a shed, garage or storage unit often has a panel or two lying beside it; in garages and storage units, now and then a crate of RV solar gear |
| Stock tank pumps | Pastures across the farm country | A rack of panels by a water tank |
| Off-grid farms | A few farms around Riverside, Rosewood and West Point | Panels on the roof, a battery box inside, garden lights |
| Campers | Trailer parks, a summer camp, a trailer in the woods | A panel or two on the roof and a box with a deep cycle |
| Phone company relay sheds | By the radio masts on the hills around Brandenburg, Irvington and Riverside | Racks of panels, a rack of L-16s and an inverter/charger |
| The power company yard | A substation outside Muldraugh | The best single haul in the county |
| Ranger stations | By the lakes in the parks | Wall panels, racks and a battery box |
| Old wind farms | Farmland near Echo Creek and Ekron | A treadmill wind charger with broken blades, wired to a barn's tired batteries |
| A dairy | Near Ekron | A sour digester piped to a run-down generator with a gas kit |
| A prepper's cabin | In the woods near Echo Creek | A dirty gasifier piped to a generator, and the plans that built it |
| Arrow board trailers | Road works around Muldraugh, Riverside and Rosewood, the checkpoints outside Louisville, and traffic jams and junkyards anywhere | Two panels, often one cracked, a box of worn deep cycles, usually a charge controller |
| Barns | Now and then, by barns and farm storage | An old treadmill wind charger with broken blades |
| Livestock buildings | Now and then, by barns, stables, coops and pigsties | A barrel digester, gone sour, its bags torn, sometimes with Homestead Power #3 left in the building |
| Hunting shacks | Often, by hunting shacks and deer stands | A primitive gasifier full of ash and tar, sometimes with the FEMA plans in the shack |
| Stash houses | Four of them, each marked on an annotated map. Survivalists and preppers carry one map, campers another, and two are on town maps | A crate of solar gear, and more crates and shelves of panels and batteries |
