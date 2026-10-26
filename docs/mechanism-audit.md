# Structural mechanism audit

## Purpose and selection rule

This audit supersedes the adjacent-helper-first priority in [the consolidation plan](consolidation-plan.md), not its preservation gates or completed work. The user asked for ambitious structural simplification, landed incrementally, rather than a succession of small optimizations.

Baseline: 17,148 physical lines of shipped RE Lua and 23,344 of RE-specific development Lua, excluding commonlib and the shared harness. These include comments, blanks and definitions; they are not executable-line counts or an estimate of removable code. Start with production mechanisms, not generated data or the harness simply because those files are large.

For each candidate, identify: the complete operation and its entry points; the owner of each state representation; duplicated implementations or compensating machinery; the exact machinery a cutover deletes; differences that must survive; native capability; and the runtime experiment that can reject the design. A file move, shorter helper or new generic framework is not an architectural result. Rank deletion of entire mechanisms above repeated-call savings. Record negative findings so the next session does not rediscover rejected shortcuts.

## Mechanism map

Paths below are relative to `Contents/mods/RenewableEnergy/42/media/lua/`.

| Mechanism | Actual sequence / owners | Consequence for consolidation |
| --- | --- | --- |
| Room discoveries | `server/.../World/WorldSpawns.lua`: OnSeeNewRoom -> chance -> free-square selection -> stock -> existing bank/moveable/entity constructor -> publication. Bank placement precedes crate selection. | Preserve placement and random-draw order. Banks already delegate to PowerBank.place; mounts already use vanilla moveable placement. There is no second constructor to replace merely because several callers spawn things. |
| Building finds | `World/BuildingWatch.lua`: loaded-square discovery -> watcher-specific eligibility/reach -> pending queue -> surroundings ready -> remove ticket -> roll. RuralFinds and GardenLights own saved outcomes. | Scheduling and saved history are different responsibilities. A failed roll, removed find and promised-but-unbuilt house cannot be reconstructed from current world objects. |
| Named installations | `World/SolarSites.lua`: roll stable site name -> save native global-object placement intents and claim neighboring buildings -> chunk/minute readiness -> construct -> remove successful intent. | Refused sites retry on a subsequent chunk load, not continuously. Wind/gas installations need both ends loaded. A transient ticket is not another persistent intent. |
| Device simulation | Native SGlobalObjectSystem -> commonlib ObjectSystem catch-up/update/job lifecycle -> device-specific advance/afterChange/buildSummary. Banks use its derivation with their own cadence and reconstruction. | The generic lifecycle already exists. A universal device framework would mostly add exceptions rather than remove an implementation. |
| Source ownership changes | `server/.../JobSites.lua`: source.open prepares the distinct affected banks -> Jobs revalidates -> source.act mutates attachments -> source.tell publishes each affected bank. World wiring enters the same operation. | M2 removed nested connection/drop orchestration from player jobs. Standalone destruction/unwiring still needs BankSystem.dropSource. |
| Trailer initialization | Native vehicle create/init -> stock panel conditions -> native post-create condition overwrite -> next-tick correction. | The correction is not proven obsolete. OnSpawnVehicleEnd is too early for addVehicleDebug and world-story condition overrides. |

## Re-ranked teardown audit

This pass followed complete operations through RE development code, RE/commonlib jobs and device lifecycles, and equivalent RE/EI/HA mechanisms. It did not establish a large removable production framework. That is a scoped negative result, not a declaration that the repository is clean. The strongest new finding is a development pipeline that maintains an altered loot universe alongside a second implementation of native loot mathematics.

The inventories below count **existing physical lines at audit time**, including comments/blanks, not net savings. Replacement code is still needed. No production or permanent test changes were made in this audit; the native probes were removed.

| Priority | Whole operation | Decision |
| --- | --- | --- |
| T1 | `--loot`: native list measurements → town resource estimates | Next cutover. Retire pre-roll filtering, then make the two reports share measured list yields rather than independently model the picker. Accuracy and full-report resource use are gates, not assumed solved. |
| T2 | HA sandbox-dependent loot installation → native reparse | Real duplicate lifecycle, but bounded and conditional. HA currently has no commonlib dependency; weigh that cost against the complete cutover, not a twelve-line wrapper. |
| T3 | Test expectations and definition-only checks | Batch only proven redundancies. Do not replace the main mission with scattered assertion deletion. |
| M1 / M4 | Initial bank publication / site tickets | M1 remains capability-blocked; M4 remains bounded cleanup. Neither becomes the next project merely because its files are familiar. |

### T1. One native loot-measurement pipeline, not a filtered world plus a picker model

**Entry and consumers.** Under `dev/RenewableEnergyDevHarness/42/media/lua/`, `client/RenewableEnergyDevHarness.lua:16-17,28-32` runs `RenewableEnergy.Loot.printReport(10000)` and then `TownReport.print()`. The first reports per-list and selected room-container yields; the second estimates town modules, batteries, repair value and energy using the generated census. Keep both outputs. `shared/RenewableEnergy/Debug/RenewableEnergyLoot.lua` is 297 lines and `client/RenewableEnergyDevTownReport.lua` is 613; their combined 910 lines are NOT a deletion estimate.

**Two competing models.** RenewableEnergyLoot copies lists with vanilla items removed, creates renamed procedural lists and measures that synthetic universe. TownReport separately computes per-entry probabilities and junk weights, then models procedural choice, vehicle distributions and vehicle spawning. The former documents filtering as a memory workaround; the latter calls per-list expectations exact. Neither model accounts for native capacity rejection correctly. Filtering before a roll is not equivalent to filtering the resulting counts.

**Existing replacement owner.** Canonical `PZ_DevHarness` already provides `PZHarness/Loot.lua:196-238`: `fillOnce` invokes native filling, reads the result, recursively removes created items from the cell's process list and empties the container; `sample` aggregates those results. Its `perContainer` is conditional on finding the item: unconditional expected count is `share * perContainer`. RE's existing `countModItems` can filter observations AFTER the complete native roll. Use the existing owner; do not add another loot simulator or memory-management layer.

**Discriminating runtime evidence.** A temporary SP authority probe used the installed native parser and sampler:

- Capacity-one scratch crate; a guaranteed 9-weight `Base.Log` entry before a guaranteed controller: full list produced **0 controllers**, controller-only list produced **1**. This proves a filtering counterexample, not the size of the error in every production list.
- Real full `proc:ElectronicStoreMagazines`: **1,000 fills, 19 observed item types, process-list delta 0, 51 ms**. An earlier run measured 48 ms and the same zero delta. This supports replacing the old workaround; it does not prove bounded memory or acceptable duration for every list or the entire report.
- The first capacity fixture used `Base.Generator` and did not discriminate: harness `QUIET_WORLD` sets `GeneratorSpawning=1` (None), so it never blocked the target. Replacing only that fixture item with Log made the probe pass. No production fix is claimed from the first failure.
- Corrected probe passed 1/1 in 0.48 s; its launch compiled 209/209 Lua files and passed cross-checks. Both temporary registrations were removed. No native-conformance test was retained.

**Native explanation.** Installed `ItemPickerJava.tryAddItemToContainer:696-719` checks weight/capacity; `doRollItemInternal:1017-1043` aborts the remaining entries when insertion fails. `getActualSpawnChance:2091-2110` also applies native loot modifiers and world context. Recreating only the weight formula is not a replacement for rolling the container.

**Concrete deletion inventory and order.**

1. **Retire the filtered universe as one cutover:** RenewableEnergyLoot's `modItemsOnly` (`98-113`, 16 lines), `modOnlyTables` (`129-141`, 13), `roomContainersModOnly` (`143-166`, 24) and `PROBE_LIST` declaration/comment (`20-21`, 2): **55 existing lines**. Replace their callers in `printReport:240-271` with full-list resolution and original procedural choices through the existing parser. Some list-collection code remains necessary. Retain option restoration/reparse in `withLoot`, world-stock measurements, output rows and post-roll counting.
2. **Make those native observations serve town estimates:** remove TownReport's `JUNK_WEIGHT_MULTIPLIER`, `chancePerRoll`, `expectedInItems` and `expectedIn` (`98-133`, **36 existing lines**) after a measured-yield interface covers the lists and item types needed by `roomFinds` and `vehicleExpected`. Include vanilla car batteries and nested loot where needed, not just RE-prefixed items. Reuse each measurement within this report operation, not a persistent cache. Preserve census aggregation, mod repair/stock calculations and all report sections.
3. **Challenge the remaining native selection models separately:** `isForced/pickWeight/expectedInContainers:135-171`, `distributionOf/vehicleExpected:282-320`, and `zoneVehicles` with its constants at `322-364`. No supported drop-in replacement was established for room limits/forced context or whole-map vehicle spawning. These are NOT approved deletions or part of the 91-line inventory above. A roomless scratch roll is not an exact simulated town.

**Preservation and rejection gates.** Run the actual `--loot` surface before/after the integrated cutover, not just a synthetic probability test. Preserve list/room/world-stock rows, town/site/vehicle totals and energy yardsticks; restore sandbox options and native parsed tables on exit. Measure full-report duration and retained process items, including nested containers. Explicitly retain scratch-capacity and room-context assumptions. Replacing deterministic leaf estimates with sampled estimates introduces rare-item uncertainty: a zero observation is not proof of absence, and the current 10,000 samples are not automatically adequate for town totals. Establish useful precision/cost before deleting the formula; if that gate fails, finish the full-list sampling correction but mark the estimator cutover blocked rather than silently degrade or omit rare results. Do not tune gameplay weights to make the reports agree.

This is a genuine ownership/correctness target, but **91 existing lines plus caller changes are the established initial inventory, not hundreds or thousands of proven net deletions**. The unresolved selection layers explain why this is a pipeline investigation rather than another helper extraction.

### T2. HA's independent loot startup/application

**Same operation, existing owner.** HA `server/HearingAid/HearingAidDistributions.lua:50-93` applies sandbox-scaled flat-list entries after saved options load and reparses native loot. RE and EI already use commonlib `server/cf_commonlib/Loot.lua:77-111` (`place`, `register`) for that lifecycle.

**Inventory.** HA's private `onInitGlobalModData`/client guard/Parse/event block at `82-93` is **12 existing lines**; the broader insertion/application region at `50-93` is **44 existing lines**, including substantive setup that must remain. Replace `addItem/addAids/addToLists` and private startup ownership, not the loot weights. The broader count includes the smaller one; do not add them together.

**Gates before selecting it.** HA's manifest has no commonlib dependency. A cutover needs manifest, development library loading and installation documentation together, not a fallback local copy. Preserve broken versus working multipliers, skip base-weight-zero entries (commonlib currently gates only the multiplier), and retain missing `Outfit_Retiree` creation. HA appends; `Loot.place` removes prior same-item entries before insertion. Repeated worlds and third-party same-item additions can therefore behave differently. Resolve that ownership contract before full migration; scheduling alone can preserve append semantics but is too small to justify a new dependency by itself.

**Discriminator, not yet run.** Fresh/continued SP and real MP with late saved options, zero/nonzero multipliers, ordinary/retiree corpses and missing retiree table; then two worlds in one process and a foreign same-item contribution. With all three mods enabled, native parsed lists must contain all intended entries without HA's separate Parse. No runtime equivalence is claimed by this source audit.

### T3. Test-policy audit: remove duplicate reasoning, retain mod outcomes

- `RenewableEnergyTestsGasLineLoad.lua:55-85` contains **31 existing lines** of `shareOrder/expectedShares` that reimplement nearest-bank greedy allocation. Replace that oracle with an explicitly arranged scene and hand-derived allocations while retaining actual load, full-nearest-bank handoff and overload checks at `92-197`. Do not use the production allocator to compute expected answers. Fixture replacement cost is not yet measured; this is bounded suite cleanup.
- `RenewableEnergyTestsTiles.lua` has picture/definition checks (`42-50`), native face expectations (`63-97`) and scrap-definition checks (`187-208`). The shared static checker already covers declared tile images and reciprocal tile/item mappings, but equivalence for every dynamically collected sprite and Lua scrap result is NOT established. Classify and remove definition echoes, rather than migrating them into a new permanent runtime conformance framework. Keep mod classification, fixed-tile migration, battery overlays and actual pickup/placement behavior. Do not delete the entire 498-line file.
- Native calls do not make a test an engine test. Loot marking/refill preservation/player-container exclusion, visible solar-light power/color, actual menu payment and crash-classifier boundaries exercise mod-owned behavior. Retain them. The bank-menu scenario named `wire_in_and_unwire` actually executes Wire In and only checks that Unwire is offered; do not cite it as exercised Unwire coverage.
- The native elapsed-action timing case is already removed. Do not rediscover it as future savings, reintroduce normal-speed waits or count the harness submodule checkouts as authored duplicates.

### Production teardown proposals rejected by this pass

Source traces covered digester vessel filling and bank Wire In from menu → common action → authority revalidation → mutation/payment → inventory, overlay and summary publication; source connection was the topology-changing contrast. The seven initial RE/commonlib files total 1,741 lines, but the trace establishes no second job engine. `Jobs.perform:124-142` already owns catch-up, revalidation, successful-only payment/XP and publication even after refusal. Digester filling reuses `DigesterJobs.fillUses`; putting server handlers into policy rows would move code, not remove another implementation.

| Apparent duplicate | Necessary difference / actual existing owner | Decision |
| --- | --- | --- |
| RE treadmill (209 lines) versus EI HeldAction (202) | Treadmill settles proportional energy/stats at completion/cancellation and handles belt positioning. EI transfers water incrementally under an exclusive expiring record hold, then delivers the last interval. EI Pump/Water already share HeldAction. | No universal action base. Callback-name similarity is not an operation match. |
| EI Link/Line/Pump/Treatment Jobs (1,018 lines) | Six EI feature registrations and ten RE registrations already use common JobAction/Jobs. Geometry, topology, materials and device rules are the remaining content. PUMP/WATER rows are live refusal policy used by held actions. | No removable second framework; do not delete rows lacking fixed-action handlers. |
| RE/EI device lifecycles | commonlib ObjectSystem already owns native registration/catch-up/publication. Digester inventory debt, bank nonlinear wear, loaded-only gasifier stoking, deferred EI pump/treatment dependencies and buried links without world records have different contracts. | Preserve these state owners; no universal simulator or debt deletion. |
| EI HousePower versus RE Payers | Native reach geometry is already shared. EI keeps a qualifying vanilla payer and unloaded fuel debt; RE has different eligibility/ties and native bill correction. EI must work without RE. | No drop-in payer merger; combined-mod fuel/water/charge behavior would need its own discriminator. |
| HA action and hearing lifecycle versus RE/EI jobs | Inventory/worn-item operations, original/applied trait ledger, battery absence versus zero, clothing replacement and active-only drain are not spatial device jobs or persistent unloaded simulation. | Keep native completion hooks and trait bookkeeping. |
| Rounded global summaries versus detailed watched status | Different recipients, freshness, payload and cost; authority rebuilds summaries after catch-up. | Repeated reads are not two independently maintained implementations. |

Small reachability findings are not a new project: commonlib `Materials.unmetKind:167-171` has no workspace caller (fix its stale Jobs comment if removed); HA `setBaseLevel:269-274` is dev-only but touches private authority bookkeeping; RE `Stink.counted:212-221` is a dev observation seam into private ghost accounting. Do not relocate either private-state adapter by replacing it with an incomplete direct field write.

Unverified lifecycle leads, not diagnosed bugs: **[INFERENCE]** an unwired treadmill disconnect may leave a drawing marker unless native stop callbacks clear it; a real MP disconnect is the discriminator. EI HeldAction's final `letGo` runs the last interval without `runHeld`'s reach check; changing that to treadmill's final-position contract is not behavior-preserving consolidation. Neither lead justifies a new generic lease framework.

## Earlier cutovers and capability gates

### M1. Complete initial publication instead of publish-then-resync

**Structural target:** delete the bank-added client listener/request in `client/.../PowerBank/ClientBankSystem.lua:26-37` and the server `resync` command branch in `server/.../PowerBank/BankSystem.lua:232-236`. Construction should make the first published bank semantically complete, including restored active records, instead of requiring a second client/server exchange. Gas-site generation has a related publication boundary, but its earlier intermittent client-copy failure is not diagnosed by this finding.

**Evidence:** BankSystem.makeBank stocks the container, publishes the complete object, then sets condition/fuel/connection and triggers record adoption (`BankSystem.lua:74-115`). The native full-object serialization already includes the generator flags, fuel and condition. However, the setters send separate reliable-unordered SyncIsoObject snapshots, while the object itself uses ordered AddItemToMap publication. A state packet can arrive before its object. A reconstructed bank can also reactivate during `Bank:loaded -> refresh -> switchGenerator`, after the initial setters.

**Real MP probe, 2026-10-26:** instrumented the existing `renewable_energy_world_bank_spawns_stocked` scenario without replacing production construction or its repair protocol. All three bank tiers first reached OnObjectAdded as **connected=false, fuel=0, condition=0**. At validation all three were **connected=true, fuel=10, condition=100**; the existing scenario passed. This proves incomplete first publication and eventual repair in that run, not a player-visible freeze or a diagnosed gas-site failure. Temporary instrumentation was removed.

**Native feasibility result:** `IsoGenerator(IsoCell)` is detached; `setInfoFromItem` initializes fuel/condition without sending, but not connection/activation. `setConnected`, `setActivated`, `setFuel` and `setCondition` send state. Calling sync-producing setters without a square/object index logs errors. Public Java fields are not writable Lua instance fields: the installed LuaJavaClassExposer exports public static fields and instance methods; the real MP probe found `object["connected"] == nil` and no `__newindex` writer. No legitimate atomic no-send connection/activation initializer was established.

**Status: blocked for deletion, not approved for a setter-reordering patch.** Moving setters before publication can leave older intermediate snapshots arriving after the final object; suppressing packets globally, debug reflection, or hand-building native serialized/network state would replace a small workaround with more fragile machinery. Keep resync until a supported initialization contract covers final flags AND restored-record reconciliation. The source evidence is in installed `IsoGenerator`, `IsoObject.syncIsoObject`, and `LuaJavaClassExposer`; the first-copy evidence is from the real MP run above.

**Acceptance if unblocked:** observe first client availability, not just eventual convergence, for new stocked banks, player-placed tiles and rebuilt active banks. Verify initial stock/flags, restored charge/wear, power/toxicity, overlays and later normal switching in SP/MP. Remove the whole request/response path and its documentation together. This remains a blocked lifecycle-deletion lead, not a promised line reduction or the current next cutover.

### M2. One source-change operation across player jobs and world wiring

**Completed.** Existing owner: JobSites plus Bank's attachment/removal mutations. This removes duplicated orchestration; it is not a measured performance improvement or a large code reduction.

Before the cutover, `JobSites.source.open` prepared the destination, recounted its controllers and caught up/reconciled the previous bank/source. Connect then entered `JobSites.connectSource`, which discovered/prepared those banks again and published. Disconnect entered `BankSystem.dropSource`, which updated/removed/published; source.tell published again. Clock.hoursSince stamps the clock and updateBank rejects nonpositive elapsed time: this was NOT proof of double charging or extra full scans.

**Cutover:** source.open carries the prepared previous/destination banks through the existing Jobs boundary. Connect/disconnect perform only Bank's attachment/removal mutations; source.tell owns final publication of each distinct affected bank. World wiring calls that same operation. Standalone BankSystem.dropSource remains for destruction and treadmill unwiring. The job path's second discovery/preparation and nested final sends are gone; authority revalidation and elapsed simulation remain.

**Preservation gates:** catch up both banks at their old topology; retain destination recount when no time elapsed; publish catch-up removals even if the requested job is refused; same-bank reconnect must not reset snow/state; pending treadmill energy must be credited once and written to loaded batteries; retain bulk partial success and XP. Compare current world-versus-player preparation order before merging them: connection helpers must not change billing/backup results incidentally.

**Ordering decision:** player jobs retain destination-then-previous preparation. The only production caller of the standalone connect entry point is SolarSites wiring a newly placed wind charger, with no previous bank; it has no two-bank preparation order to reverse. Same-bank preparation/publication is deduplicated. Catch-up can still send its own elapsed-state updates; the cutover does not suppress simulation notifications.

**Exercised evidence:** the source-family batch passed **97/97 SP** and **98/98 MP**, with leak checking enabled. The new permanent `renewable_energy_bank_source_transfer_settles_both_ends` regression verifies old-topology production credit, both watched banks' final state, and production credited to the destination only after transfer. Existing cases exercised same-bank reconnect, catch-up-invalidated source refusal, pending treadmill energy on unwire/pickup, connection XP, partial bulk success, sealing/brakes/blades and named-site world wiring. The extra MP case removed a real destination controller and set its record clock to now immediately before authority job completion, in the same Lua call: the connection was refused for lack of slots and the client received the recounted destination summary. That temporary probe and its server branch were removed. No benchmark or duplicate-scan reduction is claimed.

**Code accounting:** JobSites.lua is 304 lines versus 298 before this cutover (**+6 production Lua**); the retained two-bank regression adds **39 development Lua lines**. No files were moved. The gain is deletion of nested preparation/publication ownership, not net line deletion. Do not present it as meeting the larger reduction mission.

### M3. One placed-panel module commit, not several snapshot repair sequences

**Owner:** PanelSource.writeModules now commits storage, the connected bank snapshot when supplied, and crack presentation. JobSites sealing and loose-panel storms no longer assemble those steps themselves; pending connected damage uses the same commit.

**Cutover:** removed the action's manual source.modules copy and repeated writeModules/showCracks sequences. The writer adopts the detached module records into the bank while storing an independent object copy, clearing pending damage only on commit. Crack presentation accepts the records already in hand instead of copying them back out of modData. XP and storm notifications remain with the initiating operation. Unchanged simulation passes retain their read/reconcile path without new publication or object-kind lookup.

**Preserved:** modulesChanged retains unloaded-damage precedence; otherwise loaded object records win. The new real SP chunk-unload regression storms the absent panel, reloads it, resets elapsed time to zero, seals immediately, then runs another pass. It checks condition, repair count, earned-XP markers, the bank's immediate/later snapshot, and cracks below retained snow. The initial fixture incorrectly expected light cracks at condition 40 and put snow exactly on its display threshold; it was corrected to the documented heavy-crack rule and snow safely above the threshold, not treated as a production bug. Full process save/restart with pending damage remains unverified.

**Completed:** 72/72 SP and 70 MP passed (2 SP-only skips), including connected/loose storms, in-place sealing, crafting and pickup round trips, and client overlays. The new authority-unload case is SP-only because the MP server retains those chunks. Final 209/209 compilation, cross-checks and dedicated-server startup passed. Net **1 production Lua line removed**, **50 development lines added**; no file moves. Loose and connected storm clocks remain separate. This establishes one commit owner, not a large reduction or a measured speedup.

### M4. Site payload and native discovery cleanup — deliberately not the main project

SolarSites copies native placement-intent modData into minute tickets, then looks up the native object again while still using the copied payload (`SolarSites.lua:348-383`). Coordinates plus the current native object's payload can have one authority; keep scheduling/order and consume the payload before removeObject resets it. No production stale-ticket bug was reproduced. Test replacement/unload/reload and blocked-site retry before cutover. This is bounded state cleanup, not a substantial architectural reduction.

Native IsoMetaChunk exposes building/room intersection queries, but metadata rooms are not proven equivalent to BuildingWatch's actually loaded z=0..1 discovery and representative-square unload check. Do not substitute the query based on its name or make it the next optimization by default.

## Mechanisms retained on purpose

- **Digester hopper and eaten:** one describes simulated remaining feed, the other unapplied deductions against real inventory IDs/uses. The loaded/unloaded feed algorithm was already unified. Removing either requires a different resource contract, not a table cleanup.
- **Bank battery and part wear debt:** cycle wear is nonlinear and ordered; part wear has different rules. Saved load and charger demand have live unloaded/allocation consumers. Summing/deleting these changes behavior.
- **Gasifier loaded-only inventory access:** unloaded gasifiers burn their existing fire but do not stoke or consume filter inventory. A digester-style generic snapshot system would add behavior.
- **Global summary versus watcher status:** globally synchronized rounded device summaries and detailed bank-window state serve different consumers and costs. Do not replace both with an always-broadcast universal payload.
- **Saved world ledgers:** site-name rolls, rural claims, empty failed outcomes, garden true-versus-number promises, and trailer stock markers preserve save compatibility and prevent respawn after player removal. Native object scans cannot replace that history.
- **Separate readiness contracts:** room loot, surrounding-ground building rolls and durable named-site placement have different triggers and retry rules. A shared scheduler is not justified just because all three place objects.
- **ArrowBoard correction:** native addVehicleDebug and world-story constructors overwrite part conditions after addToWorld/OnSpawnVehicleEnd. The installed item is overwritten too. Keep the saved original condition and next-tick correction until a genuinely later native hook is established.

## Execution protocol and checkpoint

1. Select an operation from this audit, not whichever neighboring function was last opened. State its deletion inventory and current preservation gates before editing.
2. Resolve native/lifecycle assumptions with one discriminating probe before designing around them. A failed feasibility gate rejects that design; it is not permission to invent a bridge or substitute an easy micro-cleanup.
3. Land complete behavior-preserving cutovers with all callers migrated. Batch related real-game checks after integration; do not run full suites after individual edits.
4. Update this audit's status and the consolidation checkpoint with actual deleted mechanisms, production/development line changes and exercised evidence. No estimated savings presented as results.

The world/device audit and M1 feasibility investigation are committed as `6fd2f43`; M2 as `32687fd`; M3 as `a0a942e`. The expanded teardown audit above selects T1's complete loot-analysis pipeline next, with full-report resource use and sampled-estimate accuracy still to establish. T2 is conditional, T3/M4 are bounded cleanup, and M1 remains blocked. No large new production teardown was proved by these traces; the larger reduction mission remains open. Full process save/restart is not claimed. The earlier intermittent sealing and gas-site-copy failures remain undiagnosed. Native engine timing is not a mod acceptance criterion; completion scenarios should use instant actions and test the mod's duration policy separately.
