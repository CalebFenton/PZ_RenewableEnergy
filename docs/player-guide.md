# Renewable Energy: player's guide

How the mod's systems work, for players who want more than the Workshop page tells them, and where to start looking for the gear. Figures are rounded and assume the default sandbox settings. The tooltips and status windows in game show the exact ones.

## Mechanics

### Battery banks

| Mechanic | How it works |
|---|---|
| Box, rack and bank | A battery box takes 2 batteries, an inverter and a charger. A rack takes 6 batteries (8 in metal), an inverter, 2 chargers and 2 charge controllers. A bank takes 12 batteries (16 in metal), 2 inverters, 2 chargers and 4 controllers. Metal versions hold more batteries and nothing else. |
| Indoors only | A bank works only inside a building's room. Placed outdoors, it says so and does nothing. |
| Wiring parts | Parts go in with **Wire In** and come out with **Unwire**; you can't drag them. Wire In lists every part you carry by type, each with its condition, as the mechanics window lists car parts. **Wire In > All Batteries** wires in as many of your batteries as the bank has room for, best condition first, and **Unwire > All Batteries** takes every battery out in one go. What doesn't fit in your inventory lands at your feet. Wiring a part in takes a screwdriver, wire and enough light to see; an L-16's cable lugs bolt on, so it takes a wrench as well. Unwiring takes the same tools and gives the wire back. An item gives Electricity XP the first time it is wired, and higher Electricity makes the work faster. |
| Connect and turn on | **Connect Bank** works like connecting a generator: Electricity 3, or the generator magazine. **Turn On** stays greyed out until the bank has a working inverter and battery. A bank you find already standing somewhere is connected but switched off. |
| What it powers | Under the hood a bank is a generator. It powers whatever a generator in its spot would, with the same reach and floors. The neighbours' lights and fridges count, and they add to its load. It burns no fuel and makes no noise or fumes. While the grid is still on, the bank stands by: nothing drains its batteries, panels and chargers keep filling them, and its status still shows the load switched on in its reach. It takes over within minutes of the shutoff, which comes when vanilla's Electricity Shutoff option says. |
| Load limit | A bank can carry as much as its working inverters add up to: about 300 W for the plug-in inverter, 600 W for the power inverter and 1000 W for the inverter/charger. Each appliance draws what vanilla bills a generator for it. Inverters lose some of what passes through them, and they draw a little while on, even with nothing switched on. |
| Overload | If more is switched on than the inverters can carry, the whole area goes dark. A bank powers everything or nothing, so it never drops just the dryer. Switch something off and the power comes back on the next update. Turning the bank off and on brings it back at once. Every overload costs each inverter a little condition. |
| Running empty | At zero charge the power cuts. It comes back by itself once some charge has built up, so a bank that barely charges doesn't flicker. |
| Source slots | A bank takes 2 sources by itself, plus 7 for each working charge controller. Any panel takes 1 slot, so a ground rack's two modules cost a single slot. A scoop rotor and a treadmill take 1, a propeller 2, a homemade alternator 3. Slots go in the order sources were connected. Sources past the last slot stay connected but make nothing ("no controller slot"). A broken controller loses its slots. |
| Reach | **Connect Sources in Reach** picks up sources within 20 squares and 3 floors. Panels and wind chargers must stand outdoors; a treadmill can be under a roof. If you move a source, it drops off its bank and has to be connected again. |
| Part wear | Inverters lose condition every hour their bank powers its area, about one Electronics Scrap's worth a week. Controllers wear half as fast. **Repair** in the bank's menu (Electricity 2) adds the same amount for each scrap. A part at zero is broken, but you can still repair it. |
| Chargers | A wired-in vanilla car battery charger, or the charger built into an inverter/charger, fills the batteries from the grid or from a running generator whose reach covers the bank. That burns the generator's fuel. Chargers fill only what your sources leave unfilled. |
| Backup generator | A running generator within a few squares of the bank, on its floor, takes over the load while it runs, and the batteries rest. |
| Solar Failsafe | Place it on the generator's square. It starts the generator when the bank drops below one charge level and stops it at a higher one. It won't start a generator with no fuel, or one worn enough to catch fire. It stays idle while the bank can't power its area. Without a charger in the bank, the generator only carries the load, and the charge climbs only as fast as your sources fill it. Sandbox: Failsafe Start Charge, Failsafe Stop Charge. |
| While you're away | Banks keep charging and draining when you're far away. Anything left switched on in their area keeps drawing. Sandbox: Charge Frequency (how often banks update). |
| Status window | Shows whether the bank is charging or draining and by how much, time to full or empty, load against the limit and slots used. Each source has its output and the biggest reason it falls short: night, cloud, low sun, snow, cracked, braked, broken blades, sheltered or no controller slot. Reasons you can fix are in red. Each battery has its charge, condition and a repair hint. Click a source to see where it stands. **Status** walks you over to the bank, and the window closes once you walk more than 4 squares away, as a digester's and a gasifier's do. |

### Batteries

| Mechanic | How it works |
|---|---|
| Capacity | Compared to a car battery, a deep cycle holds about twice as much, an L-16 about three and a half times and a homemade jar battery about two thirds. Capacity goes down with condition. The tooltip shows capacity and stored charge in Wh. |
| Shared charge | All the batteries in a bank share one charge level. Wire a full one in next to empty ones and the charge evens out. A battery you unwire leaves at the bank's level. Found batteries hold somewhere between a third and four fifths of a charge. |
| Found banks | Batteries already in a box, rack or bank you find have been used, and the riskier the place, the better they are. Sheds and farm storerooms hold well-worn ones, never like new, which are worth reconditioning. Homesteads, storage units and utility sites hold batteries at around four fifths, a few as good as new. An electronics store's backroom stock is nearly new. Now and then one is a dud: nearly dead, and repaired too often for reconditioning to help. Strip it for a rebuild instead. |
| Wear | Once a game day, each battery wears by that day's deepest drop from its peak. Wear grows with the square of the depth, so draining half as deep wears a quarter as much. Carrying a load that takes half its new capacity every night, a car battery falls to half its capacity in about five months, a deep cycle in about a year and an L-16 in about two. A bank twice that size lasts four times as long. Temperature doesn't matter. Sandbox: Battery Wear. |
| Service | **Service Battery** needs Electricity 1, water, and a rag or baking soda. It gives a small boost and keeps the charge. |
| Recondition | You have to learn it first. Water and baking soda bring a battery straight up to its ceiling, but leave it empty. |
| Repair ceiling | Each service or recondition lowers how far the next one can bring the battery back. After a handful, it needs a rebuild. |
| Rebuild | **Strip** the battery (gloves, and containers to catch the acid) for its case, worn plates and acid. Recast the plates at a furnace in a fired clay mold. Some lead burns off, so three worn sets make two, and a lead pipe can stand in for one set. Then rebuild with acid and water. The battery comes back like new, empty, with its repair count cleared. Acid can't be made: it comes from loot or from stripped batteries. |
| Jar battery | Six glass jars, one set of plates (three lead pipes cast a set), acid and water. Small and short-lived, but you can make it from scratch. |
| In a car | A deep cycle fits a car's battery slot. It runs the lights and radio twice as long and takes twice as long to fill from the alternator. L-16s and jar batteries don't fit. |

### Solar panels

| Mechanic | How it works |
|---|---|
| Mounts and seasons | A flat panel lies flat and makes the most in summer, with the sun high. A wall panel goes on an outside wall facing south or east, does best in winter, and gets extra light off fresh snow. A ground rack holds two modules on a tilt, faces any way, and stays the most even across the year. Output follows the sun through the day and is zero at night. An east wall gets only morning sun. A handful of modules runs a fridge-freezer through a summer day; winter takes more. Sandbox: Sunlight Multiplier. |
| Weather | Overcast takes most of the light. Fog and rain take some more, and falling snow halves what's left. Wind doesn't affect panels. |
| Module condition | A module makes power in proportion to its condition, so one at half condition makes half. Below about 60 it shows cracked glass. A homemade module tops out at 60. |
| Snow | Falling snow piles up on flat panels and racks, and output drops by the share covered. A rack sheds its snow within a few hours in sun or mild air. A flat panel loses snow only as it melts above freezing; **Clear Snow** with a broom or snow shovel clears it at once. Wall panels never hold snow. |
| Storms | A thunderstorm with strong wind can crack a module. A gale without thunder can't. Wall panels are safe. A wooden rack cracks more easily than a flat panel, and a metal one less. At the default rate, ten panels lose about one module every few months. Every panel standing outdoors is at risk, connected to a bank or not. Sandbox: Storm Damage, Storm Damage Rate. |
| Sealing | Take the module off its mount first. **Seal Cracked Module** uses epoxy (glue won't do). It brings back some condition, but only up to a ceiling that drops with every seal, and the glass still looks cracked. |
| Reglazing | **Reglaze Module** puts on a new pane of glass. The module goes up to a fixed level (never back to new, because the cells underneath stay cracked), and its seal count clears. |
| Homemade modules | 16 solar cells under glass. Cells come from taking apart calculators, garden lights, solar battery chargers, maintainers and shattered modules (only at zero condition). |
| Mounting | **Unmount** gives back the same modules, at the same condition, plus some of the frame. |

### Wind chargers

| Mechanic | How it works |
|---|---|
| The three kinds | The scoop rotor starts in the lightest breeze and is weak. The propeller makes real power in a good wind. The homemade alternator makes the most. Wind blows day and night and hardest in winter. |
| Power and wind | Below its starting speed a charger makes nothing. Output climbs steeply with wind speed until full output, which takes a strong breeze, so halfway there it makes only about an eighth. |
| Brake and blades | **Set the Brake** stops a charger. An unbraked propeller in a gale, thunder or not, is likely to break its blades within a few hours; **Replace Blades** takes a spare set. The scoop never breaks. |
| Alternator in a gale | In a gale the alternator's tail turns it out of the wind and its output drops sharply, so it makes less in a gale than in a strong breeze. Only the worst storms can break its blades. |
| Height | A charger gains output for each floor it stands on above the ground, up to the third. What counts is the floor it's placed on, not its own mast. |
| Shelter | Trees, buildings and solid walls within a few squares steal wind, and nearer ones steal more. Trees stop counting once a charger is above the treetops. Windows and low fences don't count. A fully hemmed-in charger loses most of its output, and the status window calls it "sheltered". |
| Slots | Bigger chargers take more of a bank's source slots (see Source slots). |

### Treadmills

| Mechanic | How it works |
|---|---|
| Wiring | **Wire to a Bank** takes Electricity 2, a screwdriver, wire and an Electronics Scrap. Unwiring takes the screwdriver too; it and picking it up give the wire back. A wired treadmill also has to be connected to a bank like any source. |
| Running | **Run on Treadmill** lasts half an hour and banks roughly what a fridge-freezer draws in that time. The energy goes in when the run ends and reaches the batteries over the next half hour. Stopping early banks your share of the run. |
| Cost and gain | A run costs a good chunk of endurance and some thirst, and trains Fitness and Sprinting. You stop yourself when you're nearly spent. If the bank has no free slot, the run still tires you, but the energy is lost. |
| Unwired | Where there's power from the grid, a generator or a bank, an unwired treadmill is exercise equipment. On a bank it draws about what a washer does. |
| Motor | Taking a treadmill apart gives its motor. The scoop rotor and the propeller are built around it. |

### Generators on gas

| Mechanic | How it works |
|---|---|
| Gas Conversion Kit | Crafted, never found. **Install Gas Conversion Kit** takes a wrench and Mechanics 2. **Remove Gas Conversion Kit** needs the generator switched off. You can't pick up a generator with a kit fitted. |
| Gas line | **Connect Gas Line** needs a wrench. A digester must be on the same floor within 20 squares, with one rubber hose for every 5 squares. A gasifier must stand right beside the generator, not diagonally, and takes one metal pipe. **Disconnect Gas Line** gives the hose or pipe back. |
| Gas or gasoline | **Run on Gas** and **Run on Gasoline** turn the valve. On gas, the generator makes the usual noise, wears and fumes as usual, and draws zombies as usual, but its gasoline tank is left alone. The info window shows the real tank level. |
| Load on gas | On gas, a generator carries less than on gasoline: about a house's worth, with the bank charging too. A gasifier with a full ash pit or spent filter halves that, and with both, quarters it. Switch on more than it can carry and it stalls, then starts again by itself once the load comes down. Bank chargers on it are turned down to fit, so chargers alone never stall it. |
| Out of gas | The generator stops. It doesn't switch to gasoline or restart by itself when gas comes back. Start it by hand with gasoline in the tank and it runs on that, and goes back to gas once the source can supply again. |
| With a failsafe | A lit gasifier counts as fuel for the failsafe, even with an empty tank; an unlit one doesn't, and the failsafe never lights it. |

### Biogas

| Mechanic | How it works |
|---|---|
| Three digesters | The barrel digester is small. The insulated digester holds about three times as much and can be built new or upgraded from a barrel, keeping what's inside. The brick dome holds about three times that again, half buried under earth. The bigger the digester, the bigger its gas holder and the slower it follows the air's temperature, so the big ones ride out cold snaps. |
| Feeding | The hopper takes manure, grass and hay, wood ash, baking soda and quicklime, and rotten or compostable food. Fresh food is refused. One item goes in each hour, while there's room. Every animal's dung works, worth about what the animal makes in a day: cow manure the most, then pig. Sheep, deer and poultry are worth much less, grass and hay little. Hens drop nothing inside their hutch, only out in their pen. Kitchen scraps make decent gas but sour the digester if you overdo them. |
| Startup | A new digester takes as long as compost does before it makes gas, and the clock only runs while it's fed and warm enough. Cow and pig manure shorten it a lot. Sandbox: vanilla compost time. |
| Temperature | Below about 10 °C it stops working ("Too cold to work"). It's slow when cool, at its best in the high 30s °C, and stops again when hot. The brick dome never gets very cold, and once started it burns a little of its own gas to stay warm. |
| Gas Heater | Placed next to a digester and lit, it keeps the digester warm, burning a little gas the whole time it's lit, summer included. It warms only the digester, not the room. |
| Souring | Too much food without manure makes a digester sour. Output drops to a trickle and the smell gets much worse. Wood ash, baking soda or quicklime in the hopper settles it, and so does time. Manure helps keep it balanced. |
| Sludge | Each feeding adds sludge. Kept full, a digester needs emptying about weekly, and output halves once it's nearly full of sludge. **Take Sludge** fills sandbags or compost bags with compost. |
| Gas holders | Garbage bags tear within a few months, and a sewn tarp lasts much longer. The insulated digester's floating drum and the dome's own holder never wear out. Replacing bags or tarp loses the gas stored in them. Gas made past what the holder can take is wasted. **Vent Gas** empties the holder. |
| Smell | A digester smells worst while starting up, when sour, or when full of sludge. A settled one mellows over its first weeks. Indoors, it smells twice as bad. The insulated digester smells about half as much as a barrel, and the dome stays faint. Players nearby get vanilla's noxious smell and can get sick from it; gas masks help. |
| Indoor fumes | A barrel or insulated digester inside a building poisons the whole building while it's sour, and for a while each time its holder overflows or is vented. The dome is sealed and never fumes. |
| Scrubber | **Fit Scrubber**, then **Charge Scrubber** with water, water and wood ash, or water and quicklime (each better than the last). A new charge replaces the old one. The steel wool needs repacking now and then. Scrubbed gas matters only for bottling; generators burn raw gas. |
| Bottling | A tire pump fills a propane tank only a quarter of the way, and it's tiring work. A Fridge Compressor (salvaged from a fridge) fills it all the way where there's power, using scrubbed gas past the first quarter. A full digester holder is a fraction of a tank. |
| Bottles and tires | A propane tank refills lantern bottles. Where there's power, a carried Fridge Compressor inflates tires. |
| While you're away | Digesters keep digesting, and eating from their hoppers, while you're elsewhere. |

### Wood gas

| Mechanic | How it works |
|---|---|
| Three gasifiers | A full hopper runs a generator for roughly a third of a gasoline tank in the primitive gasifier (trash can), nearly a tank in the standard one (steel drum), and more than a tank in the advanced one (welded sheet metal). All three are on the Welding page and need the generator right beside them. |
| Fuel | Logs, branches, planks, firewood, twigs, pinecones, charcoal, and anything a charcoal kiln takes. Fuel counts by weight. Charcoal leaves far less tar and ash than wood. Tarry Packing burns too. |
| Lighting | **Light Gasifier** takes matches or a lighter. A new gasifier, or one that has been out for a while, is cold and also needs bellows. |
| Idle burn | A lit gasifier that isn't feeding a running generator slowly burns its fuel, about a kilogram a day. That's the cost of keeping it ready. |
| Ash | The ash pit fills as it burns, fastest in the primitive gasifier. A full pit halves the gas. **Clean Out Ash** with a shovel gives Wood Ash, which works in a digester or a scrubber. |
| Filter and tar | The filter holds hay, straw, grass or splinters, which turn into Tarry Packing as it burns. Tarry packing wears the generator faster. When no clean packing is left, tar reaches the engine: half the gas and fast wear. Change the packing in time. |
| Condensate | Burning fills a condensate drain, and while it's full, tar builds up twice as fast. **Drain Condensate** into a metal or glass container if the gasifier is lit. It's wood vinegar: poisonous to drink, and mixed with water it makes mildew spray and aphid spray. |
| Indoors | A lit gasifier inside a building poisons the whole building. |
| Walking away | Out of range, a lit gasifier burns only what is already in its firebox, then goes out and cools, and the generator stops. |

### Small gadgets

| Mechanic | How it works |
|---|---|
| Solar battery maintainer | **Attach Solar Maintainer** to a car and it trickle-charges whatever battery is in it, in daylight, while the car stands in the open. In a garage it does nothing. It keeps a parked car topped up, and is too slow to revive a flat battery. It stays with the car when you swap batteries. |
| Solar battery charger | Place it outside and load up to four flashlight batteries. They charge in daylight, emptiest first, so a full tray takes a few sunny days. Indoors it charges nothing. |
| Garden lights | They go outside, on the ground floor. They charge by day and light up after sunset until the charge runs out, which on a short winter day can be early in the evening. Right-click to swap the bulb for a coloured one. Found lights start without charge. Picking one up keeps its charge and bulb. |
| Only nearby | Gadgets charge only while someone is near enough for the area to be loaded. A car parked across the map isn't charging. |

### Learning and crafting

| Mechanic | How it works |
|---|---|
| Homestead Power magazines | #1 teaches battery boxes and racks, every panel mount, and sealing. #2 teaches battery banks, the charge controller, the failsafe, homemade modules, reglazing, reconditioning, and the whole battery rebuild. #3 teaches digesters, the Gas Conversion Kit and the Gas Heater. #4 teaches the wind chargers, their blades and the homemade alternator. |
| FEMA plans | The three gasifiers, the Gas Conversion Kit and the wood vinegar sprays. |
| Skills | Every recipe is also learned by reaching a skill level, usually above what crafting it needs, so a magazine gets you there sooner. Boxes, racks, banks and panels come from Woodwork, Metalworking or Electricity. Battery work and controllers come from Electricity, digesters from Farming plus a building skill, gasifiers from Mechanics and Metalworking, wind chargers from Metalworking and Electricity. |
| Research | Researching a found module teaches the panel mounts. A plug-in inverter teaches battery boxes, a power inverter racks, and an inverter/charger banks and the failsafe. |
| Stations and light | Most recipes need a table. Recasting plates needs a furnace, the plate mold a hand press and a kiln, and steel blades a forge. Every recipe in the crafting window needs light to see by, as most of vanilla's do. So does work on wiring and fittings: wiring parts in and out of a bank, wiring a treadmill, connecting or disconnecting a source or a bank, replacing blades, repairing parts and panels, and fitting or removing a Gas Conversion Kit or its gas line. Switches, valves, brakes, bulbs and chores like clearing snow or ash don't. |
| Can't be crafted | Inverters, the maintainer, the solar battery charger, garden lights, factory modules and new deep cycle or L-16 batteries; those batteries can only be rebuilt from their own case. Treadmill motors and fridge compressors come only from taking things apart. |
| Homemade alternator | A car's brake disc, two speakers, wire, scrap and a sheet of metal. |

### Moving things and your save

| Mechanic | How it works |
|---|---|
| Picking up | Panels keep their modules and garden lights keep their charge. A bank must be disconnected and emptied before you can pick it up; a sledgehammer dumps what's in it on the floor. A picked-up treadmill forgets its wiring. A kitted generator can't be picked up. |
| Adding to a save | Loot and stocked rooms turn up only in containers and rooms nobody has opened or seen yet. Solar sites, rural finds and garden lights appear anywhere, explored or not. |
| Removing from a save | What the mod built into your world goes with it. |

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
| Homestead Power #3 | Farms: farm supply, barns, farmers' trucks, the farming shelf of a bookstore | Uncommon |
| Homestead Power #4 | Farm supply, barns, electricians, hobby shelves | Rare |
| FEMA plans | Post offices, army surplus, police and fire stations, libraries, preppers, hunting shacks | Uncommon |
| A bit of everything | Prepper caches, and survivalists dead or alive | |
| Never found | The Gas Conversion Kit, Gas Heater, blades, treadmill motors and fridge compressors: craft or salvage them | |

### Places already set up

The named places are rolled once per world, so not all of them will be there, and batteries found in them hold part of a charge. Sandbox: Solar Sites, Battery Bank Spawn, Stash Houses.

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
| Old wind farms | Farmland near Echo Creek and Ekron | A propeller with broken blades, wired to a barn's tired batteries |
| A dairy | Near Ekron | A sour digester piped to a run-down generator with a gas kit |
| A prepper's cabin | In the woods near Echo Creek | A dirty gasifier piped to a generator, and the plans that built it |
| Arrow board trailers | Road works around Muldraugh, Riverside and Rosewood, the checkpoints outside Louisville, and traffic jams and junkyards anywhere | Two panels, often one cracked, a box of worn deep cycles, usually a charge controller. The box is usually padlocked: cut the lock or unbolt the lid |
| Barns | Now and then, by barns and farm storage | An old propeller wind charger with broken blades |
| Livestock buildings | Now and then, by barns, stables, coops and pigsties | A barrel digester, gone sour, its bags torn |
| Hunting shacks | Often, by hunting shacks and deer stands | A primitive gasifier full of ash and tar, sometimes with the FEMA plans in the shack |
| Stash houses | Four of them, each marked on an annotated map. Survivalists and preppers carry one map, campers another, and two are on town maps | A crate of solar gear, and more crates and shelves of panels and batteries |

None of the rural finds works as found: fix them first.
