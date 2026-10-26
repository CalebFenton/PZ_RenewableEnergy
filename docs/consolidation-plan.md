# Layered mod consolidation

## Mission and resume protocol

User-approved plan: reduce code and cognitive overhead without dropping behavior, by using the game's native APIs and giving each operation one implementation. Scope includes Renewable Energy, Enhanced Irrigation, Hearing Aid, cf_commonlib and the canonical development harness. Start with the electrical vertical slice; proceed incrementally, not as a rewrite.

Read this file before resuming consolidation work, including after context compaction. Read the relevant source and repository guidance before editing. After every verified logical change, update the checkpoint and evidence below and commit that change separately. Do not reinterpret the latest finding as the whole mission. A checkpoint is not completion of the mission.

Reference: `/Users/caleb/repos/delphos-v2/docs/style-guides/engineering-lessons.md`. Central rules: find the existing owner; reconcile differing rules when merging; prefer native operations to approximations; remove production-unreachable scaffolding; verify consumer outcomes rather than wiring; measure frequency multiplied by work; report actual deletions separately from moves and tests.

## Layers and acceptance gates

### 1. Map operations and native capabilities

Trace update/event -> measurement -> discovery -> allocation -> billing -> synchronization. Record callers, repeated calls inside a single operation, allocations, writes, native alternatives and necessary differences (loaded/unloaded, SP/MP, grid/generator, preview/authority). Instrument only unanswered questions; remove temporary probes after recording evidence. Do not count file-family size as duplication.

### 2. Remove unnecessary Lua work

Use `IsoGridSquare.getNextNonItemObjectIndex` for placed-object electrical discovery. Explicitly narrow the custom-consumer contract to placed objects, including floor tiles but excluding dropped inventory objects. Keep classification and billing unchanged. Then examine related hot paths for native filtering/lookup, unnecessary Java calls, temporary collections and homemade validation. Do not blindly change inventory scans or substitute incomplete object lists.

### 3. Reuse results within an operation

Electrical: share an already-measured generator load within billing; build charger ordering/allocation once where state is unchanged. Start with local results, not persistent caches. Preserve scheduling and immediate changes initially.

Irrigation: prepare component tiles/membership once, catch up relevant state before deriving demand, and reuse prepared demand/outlets for delivery. Replace nested link-by-tile searches with membership checks. Preserve ordering, water conservation, pump wear and deferred catch-up.

### 4. Consolidate electrical settlement lifecycle

Target ownership: Loads discovers demand; Payers owns payer selection and settlement; gas lines supply constraints and consume resulting demand; banks supply charging demand and apply allocation; outer operations control settlement timing.

First expose existing settlement boundaries. Distinguish standalone player changes from changes within periodic updates. Consolidate nested global rebilling only after proving intermediate bills are unnecessary. Delete obsolete cross-module calculation paths and circular dependencies. Do not freeze a whole update into one snapshot without accounting for banks filling/switching, supplier changes, backup activation and gas limits.

### 5. Derive preview and execution from the same rules

BankJobs/SourceJobs own bulk requirements derived from single-job rules. Delete Menu.allWiring and independent bulk material/slot policies; menus select and render. Preserve sequential attempts and partial success, not atomic batch transactions.

Investigate Recipes.lua's in-place crafting bridge against native execution APIs. Delete local selection/payment/wear only where native behavior genuinely covers mounted modules. Some native methods are private and mounted modules are not inventory items: prove the adapter first; do not build a second crafting engine.

### 6. Delete obsolete scaffolding and reorganize around real owners

After earlier cutovers, delete redundant wrappers, fields, callbacks and paths; move test execution onto production entry points and craft orchestration onto the existing harness owner. Reorganize files only when ownership is clearer. Existing common JobAction/Jobs/Materials/ObjectSystem infrastructure already centralizes much of this; do not create it again. Harness submodule checkouts are not three authored copies.

## Execution order and evidence

Complete the electrical slice through layers 1-4 first, then irrigation, then job/crafting policy and resulting deletions. Keep commits small and behaviorally complete. After each layer ask what implementation/calculation disappeared, what state no longer needs storing, which adapters became obsolete, and whether the native API offers a simpler solution. Report production line changes separately from development/test additions and file moves. No deletion quota or invented savings estimate.

Run the affected paths in the real game, including dedicated-server/SP/MP checks appropriate to the change. Preserve electrical totals, nearest-payer ties, overlaps, backup loads, full batteries, gas caps, immediate switches, unloaded banks, grid transitions and placed custom consumers. Performance probes measure scans/calls and runtime, not just test pass counts. Save/reload and synchronization contracts must remain intact. Do not change multiple timing/state boundaries before verifying the preceding layer.

## Established evidence

- Earlier commits: `739bbef` unified loaded/unloaded digester feeding; `04a597e` fixed protected recipe inputs and propane rounding; `a7a4855` stocks banks through their construction owner before publication. Those removed 42 production Lua lines, with 39 added dev/test lines; not a large architectural reduction.
- Broader audit covered 190 production Lua files (27,956 physical lines). Common actions and persistent-object lifecycles already have shared owners. Remaining candidates are semantic ownership and repeated work, not established large copy-paste blocks.
- User-provided in-game report: unmodified Loads.scan median 8.6 ms without loot, 25.0 ms with 10,000 dropped items, restored to 8.6 ms after removal. Paired traversal comparison: no loot 9.4/9.8 ms; 1,000 items 11.0/9.6; 10,000 items 30.4/11.4; 10,000 on fridge square 28.0/9.6; 10,000 plus custom floor-tile consumer 33.6/10.6 (all-object/non-item). Totals matched. Treat as established avoidable cost, NOT proof of the reported freeze. Probes were removed by the reporter; do not rerun merely to confirm their finding.
- Native traversal: start at 0, advance from previous index + 1, stop at -1. Java still traverses loot internally; the benefit is avoiding per-item Lua processing. `getSpecialObjects()` missed appliances; native generator candidate index is not a simple Lua-exposed replacement. No bridge, registry or lifecycle tracking needed for this change.
- Known production custom consumer: Enhanced Irrigation Pump Houses, placed objects. Audit all repository callers before changing the contract.
- Before layer 3: Bank.measure scanned; Payers.bill asked GasLines.chargingW, which called split -> Payers.loadOf -> Loads.scan, then bill scanned again. Bank.chargeFrom could trigger global billing and separately ask chargerLimitW, followed by periodic billing. This did NOT mean each solar panel scanned independently.
- Layer 3 billing probe (real game, production scan wrapped only to count calls): one explicit bill of the gas generator in `renewable_energy_gasline_generator_stalls_on_real_load` made 2 scans while chargers shared the cap and 2 after the nearest bank filled. After reusing the allocation's measured load it made 1 in each case. With no running generators it remained 0. Both scenarios' behavioral checks passed before and after. This measures scan counts, not a total-frame speedup. Temporary probe code and calls were removed.
- Layer 4 probe: with three banks starting to charge from one gas generator, one explicit `BankSystem.updateAll` made 3 global billing calls and 9 load scans before consolidation; afterward it made 1 billing call and 7 scans in SP and MP. The existing allocation/overload scenario passed before and after. Counts cover that method, not the entire clock tick (the old ten-minute path also billed separately afterward). Native clock charging/full-bank bill outcomes also passed in SP. Probes removed; no timing-speedup claim.
- Hourly verification exposed a fixture mistake: `setTimeOfDay` jumps can trigger EveryTenMinutes, but not EveryHours, whose previousHour is read inside the same `GameTime.update`. Clock regressions now let native time cross an hour rather than treating a jump as an hourly event. Both clock scenarios passed on a real MP server configured with ChargeFreq=2; temporary configuration changes were restored.

## Electrical operation map

Paths below are under `Contents/mods/RenewableEnergy/42/media/lua/server/RenewableEnergy/`.

| Entry / owner | Reads and work | Mutation boundary that limits reuse |
| --- | --- | --- |
| `PowerBank/BankSystem.updateAll` | Shares sun/weather contexts; updates each bank with billing deferred, then bills once. Hourly mode retains separate ten-minute billing after gas settlement. | Each bank still changes live payer state and charger demand; only writing the fuel bill waits. |
| `PowerBank/Bank.update` | Recounts parts, updates sources and backup, measures load, calculates charging/discharge, writes batteries, recounts, switches its generator; settles once unless updateAll owns the pass. | Backup activation precedes measurement; empty/full/overload transitions and battery wear happen during the pass. |
| `Bank.measure` | `Loads.scan(..., Payers.running(), true)` when on or holding chargers; remembers load for unloaded operation. | `gridGone=true` intentionally measures demand even on the grid. Do not reuse a generator's off-grid-only scan here. |
| `Bank.chargeFrom` | Selects nearest fueled supplier, records source and wanted watts; asks for its gas allocation without triggering global billing. | Demand depends on room after solar input and inverter draw; a full bank releases capacity. |
| `Bank.switchGenerator` | Updates real activation and restores toxicity; returns whether activation changed. Bills immediately outside a bank pass; inside it, the outer update settles. | Activation still happens immediately, so subsequent banks see live ownership; unchanged active banks still repower newly loaded squares. |
| `PowerBank/Payers.billGenerators` | Builds running-payer list; for each generator checks overlap/backup/chargers/treadmills, measures its load and applies its fuel bill. | Plain unshared generators with no extra demand retain vanilla billing; preserve that no-scan fast path. |
| `GasLine/GasLines.allocate` | One capped allocation for total demand and individual limits. Total queries iterate bank records directly; only individual limits collect/sort charging banks. No per-bank shares table. | No yield or state mutation between measurement and allocation, except discovery tracking inside the scan. Preserve nearest-bank priority only where it affects the answer. |
| `Payers.keepShares` | OnTick corrects native bill rebuilds from stored base/others/extra fuel. | Necessary engine integration, not a redundant periodic scan; preserve it. |
| `GasLines.updateAll/run` | Every ten minutes settles real/phantom fuel, measures gas load, can stall/restart generators. | Running state and gas supply can change; no cross-pass cache without a complete invalidation contract. |

Native source checked: `IsoGridSquare.java:getNextNonItemObjectIndex` excludes only `IsoWorldInventoryObject`; vanilla `ISBBQMenu.lua` and `ISShovelGroundCursor.lua` use it. Repository consumer search found PumpHouse.bankDraw and the test floor-tile consumer; neither requires dropped-item callbacks.

## Irrigation operation map

Scoped source paths are under EnhancedIrrigation's `42/media/lua/`:

- `shared/EnhancedIrrigation/Pumps/PumpWater.lua:deliveryOf` builds the component once, asks `Lines.tapIn` directly (not the ignored pump-link search), and returns the component with the destination and source.
- `server/EnhancedIrrigation/Lines/Flow.lua:prepare` catches tiles up before measuring demand. Its operation-local component, outlets and capped rate serve pump water/wear budgeting and `Flow.run` delivery. Hand pumps and gravity taps use the same preparation/delivery path. `takesPerHour`, duplicate outlet construction and the house's second source closure are removed.
- Confirmed catch-up bug: a full sealed tile cracked during the pump's pass beside a drilled tile. With 3 L available, the old path drew 1.5 L instead of 3, gave the crop 18.75 points instead of 37.5, and wore 0.25 condition instead of 1.375 for the wet/dry split. `irrigation_pump_house_budgets_after_line_freeze` failed before and passes after through the real pump update.
- Temporary real-game probe around `PumpObject:update`: the normal pumped-line scenario made 4 component walks before and 2 afterward. Delivery's three walks became one; the separate running-state propagation walk remains. No timing-speedup claim; probe removed.
- `shared/EnhancedIrrigation/Lines/Lines.lua:pumpFeeding` now scans links once against the membership returned by the component BFS. The existing visited map distinguishes reached line tiles (true) from examined empty neighbors (false); no second index or persistent cache. Fit Tap, Plumb Outlet and Lay Line use it. The buried-outlet regression now actually fits a tap beside the empty outlet before proving that relaying the missing tile is refused, rather than installing a tap through fixture fields.
- Preserve finite-source conservation, dry running/burnout, sprinklers, sealed-line filling, loaded/unloaded behavior, hand pumps and tap callers. No persistent topology cache.

## Bulk-job policy and crafting boundary

Paths below are under Renewable Energy's `42/media/lua/`:

- Bulk policy implemented: `BankJobs.batteryBatch` selects batteries and combines the single jobs' needs (consumed wiring items sum; reusable tools/skills take the maximum). `SourceJobs.connectBatch` offers the sequence when any single Connect job can proceed. `Menu.lua` renders/queues; `allWiring`, independent slot checks and grouped-inventory staging tables are removed. Individual authority checks and partial success remain in place.
- Bulk policy commit: `6eba9e4`; queue fix: `81f7c0a`. The All Batteries regression covers mixed car/L-16 batteries, a missing wrench, best-condition selection, tool retention and exact wire payment. The new actual-menu source scenario reproduced an oversized source aborting the sequence before a fitting panel; filtering already-ineligible jobs fixes it. SP: initial batch 17/19, then both failing cases passed together and the sealing case passed with its three preceding garden-light scenarios. MP: all 19 affected scenarios passed across two runs (four invalid selectors in the first command were corrected). Compilation/cross-checks and dedicated-server startup passed. The first multi-module sealing refusal remains unexplained, not claimed fixed; temporary diagnostics were removed.
- Native crafting source audit found no public partial-recipe payment endpoint: `CraftRecipeData` selects every required input, including the inventory module; `processDestroyAndUsedItems` relies on that selection's internal caches. Placed modules are records. Do not introduce phantom modules, mutate registered recipes, or silently change input order/XP to force a full native craft.
- Native input identity commit: `174f85a`. The manual input-list comparator is replaced with `InputScript:getOriginalLine()`; these recipe twins guarantee identical non-adhesive definitions. Real-game probe: native `canConsumeInputs=false`, screwdriver satisfied, epoxy satisfied, inventory module unsatisfied; the actual mounted repair still succeeded. Retain the live selection/payment adapter; no preservation-safe native replacement was established. Probe removed; native constraints are recorded in DEVELOPMENT.md.
- The accounting follow-up is not finished: source tracing found unverified immediate-settlement gaps after gas disconnect/remove-kit jobs, charger removal (saved demand can remain), and standalone failsafe activation (not included in the current settlement predicate). Reproduce through real player operations without explicitly billing in fixtures. Prior periodic scan reductions do not prove these boundaries correct.

## Live checkpoint

- Durable plan: `9100c54`. Native traversal: `141574f`; Enhanced Irrigation consumer-contract documentation: `b4a4e0d`.
- Native traversal verification: 209/209 Lua files compiled and cross-checks passed; dedicated server started cleanly; bank/gas-line/treadmill scenarios passed 90 SP (1 skip) and 88 MP (3 skips), zero failures. Existing regressions include dropped items before/after an appliance and beside a floor-tile consumer. Enhanced Irrigation's real Pump House callback scenario passed separately (1/1, 148/148 compiled); no combined-mod bank/Pump House scene was exercised.
- Operation-local reuse complete (commit subject: `Reuse the gas allocation load when billing its generator`): GasLines.chargingW returns its measured gas load to Payers.bill, and both use the same running-payer list. Backup watts are reused too; off-gas generators retain the no-scan vanilla fast path. The clean full suites passed 340 SP (2 skips) and 332 MP (10 skips), zero failures; dedicated server startup and all static checks passed (209/209 compiled). Temporary instrumentation is removed.
- Allocation collections removed: `6127836` (`Allocate charger totals without sorting or share tables`). One allocation rule serves total demand and individual priority limits. Net 17 production Lua lines removed, no file moves or permanent test additions. Bank/gas-line scenarios passed 78 SP (1 skip) and 76 MP (3 skips), zero failures; 209/209 compiled and cross-checks passed. A temporary wrapper observed one load scan and zero nearest-bank sorts during explicit gas-generator billing with competing charging banks, in both SP and MP. Existing full-nearest-bank/headroom and overload outcomes passed. Probe removed; no timing-speedup claim.
- Settlement boundary consolidated (commit subject: `Settle generator bills once per bank-update operation`). chargeFrom no longer rebills; activation still changes immediately, but a bank pass settles once at its end, or updateAll settles once for the whole pass. Player changes remain immediate. Hourly mode retains ten-minute billing after gas settlement. Deferral is an explicit call argument, not mutable global state or a cache. This adds 4 production Lua lines; together with allocation, this batch removes a net 13 production lines. Clock regressions add a net 40 test lines; no file moves.
- Verification: full SP passed 341 tests (2 skips); after the final clock-fixture correction both clock scenarios passed again in SP. Final clean full MP passed 333 tests (10 skips). Both final clock scenarios also passed on an MP server configured for hourly bank updates. Dedicated-server startup passed; 209/209 Lua files compiled and all cross-checks passed. All temporary probes and configuration overrides are removed.
- One earlier full MP run failed `renewable_energy_world_sites_placed_on_visit`, waiting for Dairy farm south of Ekron's client copies. An isolated diagnostic run and subsequent full runs passed that scenario without a production site change. Cause unproven, not fixed. If it recurs, inspect gas-site publication: SolarSites.placeGenerator's native constructor transmits before GasLines.fit adds the kit; this is a lead, not an established cause.
- Irrigation preparation/delivery consolidated: Enhanced Irrigation `b275fe3`. Net 22 production Lua lines removed; 40 dev/test lines added, no file moves. Clean affected-path runs passed 72 SP (3 MP-only skips) and 73 MP (2 unloaded-chunk SP-only skips), zero failures; 148/148 Lua files compiled, cross-checks and dedicated-server startup passed. Includes real frozen-line regression, finite sources, dry wear, burnout, sprinklers, taps, hand pumps, timers and SP unloaded catch-up.
- Feed membership consolidated: Enhanced Irrigation `cf281d4`. Net 2 further production Lua lines removed and 3 test lines added; this irrigation batch totals 24 production lines removed and 43 dev/test lines added, with no moves. Final membership runs passed 28 SP (1 MP-only skip) and 29 MP, zero failures; 148/148 compiled, cross-checks and dedicated-server startup passed. Includes actual tap fitting beside a buried empty outlet, rejected reconnection, wall separation, line edits and hand-pump delivery. The improvement is elimination of a links × tiles loop, not a measured frame-time claim.
- Next batch: reproduce all three post-operation settlement gaps above together, then fix their owning boundaries and batch SP/MP verification. Bulk-menu policy and the bounded native-crafting reduction are committed and exercised. Persistent accounting fields are not proven dead; do not remove saved demand, retained unloaded load or native-bill repair state merely because the periodic pass now has one settlement owner.
- Later layers remain open. No global cache, topology registry, billing cadence change or generic framework is approved merely as an optimization shortcut.
