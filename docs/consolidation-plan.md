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
- Before layer 3: Bank.measure scans; Payers.bill asks GasLines.chargingW, which can call split -> Payers.loadOf -> Loads.scan, then bill scanned again. The second scan inside that bill is now removed. Bank.chargeFrom still can trigger global billing and separately ask chargerLimitW. Periodic billing also occurs. This does NOT mean each solar panel scans independently.
- Layer 3 billing probe (real game, production scan wrapped only to count calls): one explicit bill of the gas generator in `renewable_energy_gasline_generator_stalls_on_real_load` made 2 scans while chargers shared the cap and 2 after the nearest bank filled. After reusing the allocation's measured load it made 1 in each case. With no running generators it remained 0. Both scenarios' behavioral checks passed before and after. This measures scan counts, not a total-frame speedup. Temporary probe code and calls were removed.

## Electrical operation map

Paths below are under `Contents/mods/RenewableEnergy/42/media/lua/server/RenewableEnergy/`.

| Entry / owner | Reads and work | Mutation boundary that limits reuse |
| --- | --- | --- |
| `PowerBank/BankSystem.updateAll` | Shares sun/weather contexts; updates each bank. Billing is separately registered after the bank pass every ten minutes. | Each bank can change the active payer set and charger demand. |
| `PowerBank/Bank.update` | Recounts parts, updates sources and backup, measures load, calculates charging and discharge, writes batteries, recounts, switches its generator. | Backup activation precedes measurement; empty/full/overload transitions and battery wear happen during the pass. |
| `Bank.measure` | `Loads.scan(..., Payers.running(), true)` when on or holding chargers; remembers load for unloaded operation. | `gridGone=true` intentionally measures demand even on the grid. Do not reuse a generator's off-grid-only scan here. |
| `Bank.chargeFrom` | Selects nearest fueled supplier, records source and wanted watts; changes trigger `Payers.billGenerators`; gas charger limit asks for another allocation. | Demand depends on room after solar input and inverter draw; a full bank releases capacity. |
| `Bank.switchGenerator` | Updates real generator activation and restores toxicity; changed activation immediately calls `Payers.billGenerators`. | Activation changes payer ownership; unchanged active banks still repower newly loaded squares. |
| `PowerBank/Payers.billGenerators` | Builds running-payer list; for each generator checks overlap/backup/chargers/treadmills, measures its load and applies its fuel bill. | Plain unshared generators with no extra demand retain vanilla billing; preserve that no-scan fast path. |
| `GasLine/GasLines.allocate` | One capped allocation for total demand and individual limits. Total queries iterate bank records directly; only individual limits collect/sort charging banks. No per-bank shares table. | No yield or state mutation between measurement and allocation, except discovery tracking inside the scan. Preserve nearest-bank priority only where it affects the answer. |
| `Payers.keepShares` | OnTick corrects native bill rebuilds from stored base/others/extra fuel. | Necessary engine integration, not a redundant periodic scan; preserve it. |
| `GasLines.updateAll/run` | Every ten minutes settles real/phantom fuel, measures gas load, can stall/restart generators. | Running state and gas supply can change; no cross-pass cache without a complete invalidation contract. |

Native source checked: `IsoGridSquare.java:getNextNonItemObjectIndex` excludes only `IsoWorldInventoryObject`; vanilla `ISBBQMenu.lua` and `ISShovelGroundCursor.lua` use it. Repository consumer search found PumpHouse.bankDraw and the test floor-tile consumer; neither requires dropped-item callbacks.

## Live checkpoint

- Durable plan: `9100c54`. Native traversal: `141574f`; Enhanced Irrigation consumer-contract documentation: `b4a4e0d`.
- Native traversal verification: 209/209 Lua files compiled and cross-checks passed; dedicated server started cleanly; bank/gas-line/treadmill scenarios passed 90 SP (1 skip) and 88 MP (3 skips), zero failures. Existing regressions include dropped items before/after an appliance and beside a floor-tile consumer. Enhanced Irrigation's real Pump House callback scenario passed separately (1/1, 148/148 compiled); no combined-mod bank/Pump House scene was exercised.
- Operation-local reuse complete (commit subject: `Reuse the gas allocation load when billing its generator`): GasLines.chargingW returns its measured gas load to Payers.bill, and both use the same running-payer list. Backup watts are reused too; off-gas generators retain the no-scan vanilla fast path. The clean full suites passed 340 SP (2 skips) and 332 MP (10 skips), zero failures; dedicated server startup and all static checks passed (209/209 compiled). Temporary instrumentation is removed.
- Allocation collections removed (commit subject: `Allocate charger totals without sorting or share tables`): one allocation rule serves total demand and individual priority limits. Net 17 production Lua lines removed, no file moves or permanent test additions. Bank/gas-line scenarios passed 78 SP (1 skip) and 76 MP (3 skips), zero failures; 209/209 compiled and cross-checks passed. A temporary wrapper observed one load scan and zero nearest-bank sorts during explicit gas-generator billing with competing charging banks, in both SP and MP. Existing full-nearest-bank/headroom and overload outcomes passed. Probe removed; no timing-speedup claim.
- Next is layer 4: consolidate chargeFrom/switchGenerator nested bills at the outer bank-update boundary. Native `setTotalPowerUsing` only writes the bill; allocation reads live payer/load/demand state, not that bill. Preserve immediate player actions. `GameTime.update` fires EveryHours before EveryTenMinutes; gas settlement reads the bill during its ten-minute handler, so an hourly bank pass must settle before returning, not simply wait for the later billing callback. No timing changes made yet.
- Later layers remain open. No global cache, topology registry, billing cadence change or generic framework is approved merely as an optimization shortcut.
