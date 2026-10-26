# Production mechanism audit

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

## Ranked cutovers

### M1. Complete initial publication instead of publish-then-resync

**Structural target:** delete the bank-added client listener/request in `client/.../PowerBank/ClientBankSystem.lua:26-37` and the server `resync` command branch in `server/.../PowerBank/BankSystem.lua:232-236`. Construction should make the first published bank semantically complete, including restored active records, instead of requiring a second client/server exchange. Gas-site generation has a related publication boundary, but its earlier intermittent client-copy failure is not diagnosed by this finding.

**Evidence:** BankSystem.makeBank stocks the container, publishes the complete object, then sets condition/fuel/connection and triggers record adoption (`BankSystem.lua:74-115`). The native full-object serialization already includes the generator flags, fuel and condition. However, the setters send separate reliable-unordered SyncIsoObject snapshots, while the object itself uses ordered AddItemToMap publication. A state packet can arrive before its object. A reconstructed bank can also reactivate during `Bank:loaded -> refresh -> switchGenerator`, after the initial setters.

**Real MP probe, 2026-10-26:** instrumented the existing `renewable_energy_world_bank_spawns_stocked` scenario without replacing production construction or its repair protocol. All three bank tiers first reached OnObjectAdded as **connected=false, fuel=0, condition=0**. At validation all three were **connected=true, fuel=10, condition=100**; the existing scenario passed. This proves incomplete first publication and eventual repair in that run, not a player-visible freeze or a diagnosed gas-site failure. Temporary instrumentation was removed.

**Native feasibility result:** `IsoGenerator(IsoCell)` is detached; `setInfoFromItem` initializes fuel/condition without sending, but not connection/activation. `setConnected`, `setActivated`, `setFuel` and `setCondition` send state. Calling sync-producing setters without a square/object index logs errors. Public Java fields are not writable Lua instance fields: the installed LuaJavaClassExposer exports public static fields and instance methods; the real MP probe found `object["connected"] == nil` and no `__newindex` writer. No legitimate atomic no-send connection/activation initializer was established.

**Status: blocked for deletion, not approved for a setter-reordering patch.** Moving setters before publication can leave older intermediate snapshots arriving after the final object; suppressing packets globally, debug reflection, or hand-building native serialized/network state would replace a small workaround with more fragile machinery. Keep resync until a supported initialization contract covers final flags AND restored-record reconciliation. The source evidence is in installed `IsoGenerator`, `IsoObject.syncIsoObject`, and `LuaJavaClassExposer`; the first-copy evidence is from the real MP run above.

**Acceptance if unblocked:** observe first client availability, not just eventual convergence, for new stocked banks, player-placed tiles and rebuilt active banks. Verify initial stock/flags, restored charge/wear, power/toxicity, overlays and later normal switching in SP/MP. Remove the whole request/response path and its documentation together. This is the highest-value deletion lead, not a promised line reduction.

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

The world/device audit and M1 feasibility investigation are committed as `6fd2f43`; M2 as `32687fd`. M3 is complete with the evidence above. M1 remains blocked, M4 remains bounded cleanup, and the larger reduction mission remains open: re-rank complete mechanisms before promoting an adjacent helper change. Full process save/restart is not claimed. The earlier intermittent sealing and gas-site-copy failures remain undiagnosed. Native engine timing is not a mod acceptance criterion; completion scenarios should use instant actions and test the mod's duration policy separately.
