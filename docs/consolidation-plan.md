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
- Existing electrical amplification: Bank.measure scans; Payers.bill asks GasLines.chargingW, which can call split -> Payers.loadOf -> Loads.scan, then bill scans again. Bank.chargeFrom can trigger global billing and separately ask chargerLimitW. Periodic billing also occurs. This does NOT mean each solar panel scans independently.

## Live checkpoint

- Plan persisted; implementation not yet started.
- Immediate step: inspect native traversal source/vanilla usage, all Loads.addConsumer references and existing electrical regression fixtures. Implement placed-object traversal and verify real-game accounting before committing.
- Following step: remove the second load measurement within one generator bill without changing settlement timing. Verify gas allocation and generator/bank accounting; update this checkpoint with exact commits and exercised results.
- Later layers remain open. No global cache, topology registry, billing cadence change or generic framework is approved merely as an optimization shortcut.
