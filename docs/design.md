# Renewable Energy: design

Why the mod is shaped the way it is. The numbers live in the code; tune them against the questions at the end, and don't copy them in here.

## The kernel

The game opens with "This is how you died." You are alone, fighting back against entropy, and against hordes of monsters that used to be people. You fight depression, the elements, sickness, starvation and zombification. It's bleak, but if you're strong enough you can run into the woods and hold out: if you're committed, determined, resourceful and resilient.

Renewable Energy pushes slightly against that opening. It gives the player a way forward, never a way out. Power is a holdout, not a restoration. The lights stay on because you keep paying for them, and doom still hangs over your head.

## What follows from it

**Entropy is the opponent.** Everything wears: batteries with each deep drain, modules in storms, parts while they run, digesters and gasifiers with use. A repair slows that down; it never stops it.
- **Patching lowers a ceiling.** Each patch-up brings a thing back less far than the last, the way vanilla's `FixingManager` restores less and fails more often with every repair an item has had. Patching forever is not a strategy.
- **Remaking resets, and costs more.** Remaking a thing with fresh parts brings it back and clears its patches: new plates in a battery, new glass on a module. Remaking takes more skill, tools and stations than patching.
- **Something runs out.** Battery acid is found, never made. The sun and the wind are free. The bank is the clock, and how long it runs is the player's to stretch.

**Risk buys reward.** The best gear sits where the danger is: town stores, the power yard, relay sheds on the hills, trailers in traffic jams. What lies about in the quiet countryside (barns, hunting shacks, farm buildings) is worn and needs work. The generator, the strongest source, is loud and draws the dead. Renewables are quiet, and quiet is safety. That, not free watts, is the reason to bother.

**Every step pays off, and the player feels it the day they get it.** Each tier unlocks something a survivor wants: the TV and the lights, cold food, the freezer and a hot stove, then the whole house. A first setup must do its first job well. Don't forbid the obvious use to make room for the next tier: a fridge is the obvious first use of the plug-in inverter, so it fits. Gate the next tier with scarcity, skill and effort, never with rules the player can't see a reason for.

**Commitment is the price of the big payoffs.** A dome digester, a two-storey mast and a metal bank of L-16s tie you to one place, in a game where running away is how you survive. Small setups (a box, flat panels, the arrow board trailer, a treadmill) move with you and do less. Players choose between staying put and staying mobile.

**Balance against vanilla, not against realism.** Vanilla's numbers are the yardstick: its appliance draw, generator fuel, charge rates and repair formulas. Read them from the game rather than keeping a copy, so a vanilla rebalance or a new appliance reaches the mod by itself; the mod's own figures (sources, batteries, inverters) are set to play well against them. A renewable source never beats a generator on raw output, and never makes more than it costs over the game. When realism and play pull apart, play wins, and the code comment says what was bent.

**Feel like the base game.** Reuse vanilla verbs, items, tools, moodles and mechanics: connect a bank the way you connect a generator, count repairs the way vanilla counts them, build in the build menu. No system more complex than its closest vanilla cousin. A new item needs a clear use, ideally more than one.

**Resourcefulness opens doors.** There is more than one way in: lead from pipes or worn plates, glass jars or glazed crocks, Woodwork or Welding or Electricity for storage. A carpenter, a welder and an electrician each find their own route, and a skilled player can make everything except what's deliberately finite.

**Upkeep is a decision, not a chore.** Chores come every few days, not every hour, and are done in batches. Neglect costs something you can see. Cheap repairs fix less and dear ones fix more: the choice is when to spend.

**Grounded in 1993 Kentucky.** Every piece is something a farm, cabin, RV owner, utility or FEMA pamphlet had then. Nothing anachronistic.

## Questions for any new feature

1. **Cost:** what does it take, and what does the player give up for it?
2. **Risk:** where must they go, and what noise do they make, to get it or run it?
3. **Payoff:** what do they get the day it works, and does it beat their alternatives without making them pointless?
4. **Decay:** how does it wear, what patches it, how does each patch fall short, what remakes it, and what finally ends it?
5. **Vanilla:** which vanilla mechanic, number or verb does it mirror? If none, why is it needed?
6. **Doom:** does it make the game less bleak than it should be? If it removes a threat for good, cut it or make it cost more.

## Where the mod falls short of this today

- **Inverter and charge controller repairs don't lower a ceiling.** Each Electronics Scrap adds the same condition, as vanilla's generator repair does, however often the part was repaired.
