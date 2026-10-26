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
| Source ownership changes | `server/.../JobSites.lua`: source.open prepares banks/source -> Jobs revalidates -> source.act enters standalone connection/drop orchestration -> source.tell publishes again. | This has nested owners for one operation. Target a complete prepare/mutate/publish cutover, not another wrapper deletion. |
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

**First implementation candidate after M1's feasibility rejection.** Existing owner: JobSites plus Bank's attachment/removal mutations. This is source-backed duplication of orchestration, not yet a measured performance defect.

`JobSites.source.open` prepares the destination, recounts its controllers and catches up/reconciles the previous bank/source (`JobSites.lua:191-215`). Connect then enters `JobSites.connectSource`, which discovers/prepares the previous and destination banks again and publishes (`:130-138`). Disconnect enters `BankSystem.dropSource`, which updates/removes/publishes; source.tell publishes again. Clock.hoursSince stamps the clock and updateBank rejects nonpositive elapsed time: this is NOT proof of double charging or extra full scans.

**Cutover:** carry the prepared affected banks/source through the existing Jobs open/act/tell boundary. One mutation implementation attaches/removes sources; the enclosing operation owns preparation and final publication. World wiring, destruction and treadmill unwiring must retain valid standalone entry points into those same mutations. Delete the job path's second preparation/discovery and nested final sends, not the independently required authority revalidation or elapsed simulation.

**Preservation gates:** catch up both banks at their old topology; retain destination recount when no time elapsed; publish catch-up removals even if the requested job is refused; same-bank reconnect must not reset snow/state; pending treadmill energy must be credited once and written to loaded batteries; retain bulk partial success and XP. Compare current world-versus-player preparation order before merging them: connection helpers must not change billing/backup results incidentally.

**Proof before/after:** exercise a real two-bank transfer with elapsed production, a target whose controller inventory changed with zero elapsed time, a source invalidated during catch-up, and removal with pending treadmill energy. Check final watcher-visible status in MP. Existing SolarMenu, Solar, BankServer, Treadmill and named wind-site scenarios provide consumers; a two-bank transfer and zero-elapsed controller case need explicit coverage. Temporary preparation/publication counters can answer whether the duplicate operation actually disappeared; no permanent wiring/count-only tests.

### M3. One placed-panel module commit, not several snapshot repair sequences

**Existing owner:** PanelSource. JobSites sealing, loose-panel storms and connected-panel reconciliation separately assemble storage/copy/overlay/transmission steps (`JobSites.lua:155-166`, `PanelStorms.lua:55-63`, `PanelSource.lua:43-64,151-162,203-211`).

**Cutover:** a module mutation commits through PanelSource to the object representation, the connected record when applicable, and crack presentation. Delete the action's manual source.modules copy and the repeated writeModules/showCracks sequences. Keep XP and storm notifications with the initiating operation. Do not introduce a general device-mutation framework or a lookup/transmit on every unchanged update.

**Preservation gates:** independent snapshots must remain independent tables. modulesChanged is a live precedence marker: damage accumulated while unloaded wins on reload; otherwise loaded object records win. Preserve repair counts, first-connect/mount XP flags, snow overlays and crafting/pickup round trips. Test unload -> storm damage -> reload -> immediate seal before another elapsed pass, plus ordinary connected/loose storms in SP/MP. That precedence scenario and a saved pending-damage restart were not established by the source audit.

**Status:** follow M2 only if this yields one complete mutation owner, not a renamed helper. Do not merge the loose and connected storm clocks: their cadences and random draws differ.

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

This checkpoint completed the world/device ownership audit and the M1 feasibility investigation. **No production changes or permanent test additions were made.** The instrumented MP scenario passed; 209/209 Lua files compiled and cross-checks passed before it. The temporary probe was removed. Full save/restart and an M2/M3 implementation remain unexecuted, not silently treated as covered. The earlier sealing and gas-site-copy failures remain unresolved. No large unconditional deletion was established; M2 is the next bounded operation-level cutover, while broader reductions require further evidence rather than a framework invented to satisfy a line target.
