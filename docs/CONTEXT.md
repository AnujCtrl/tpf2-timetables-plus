# Fork context

Working notes for this fork. Written 2026-09-18 so the lineage and the traps
don't have to be re-derived.

## Lineage

| Repo | Tip | Notes |
| --- | --- | --- |
| IncredibleHannes/TPF2-Timetables | `4e1b789`, 2021-03-28 (`master` 2021-03-28) | The **published Workshop mod**, id `2408373260`, v1.2.3. Dead since 2021. |
| IncredibleHannes `develop` | `2196faf`, 2021-07-28 | 15 commits never released: summer-update API changes, CJK fix, saving waiting vehicles. |
| Gregory365/TPF2-Timetables | `70c7d14`, 2024-11-15 | **This fork's upstream.** 157 commits ahead. Never published to the Workshop. |
| AnujCtrl/tpf2-timetables-plus | this repo | branch `plus-rebuild`. |

The Workshop copy installed at
`~/.local/share/Steam/steamapps/workshop/content/1066780/2408373260` ships the
author's own `.git`. Its working tree diffs against its HEAD with equal
insertion/deletion counts on every file — that is CRLF churn, not real changes.
The Workshop release is content-identical to upstream `develop@4e1b789`.

Upstream tip `70c7d14` is a revert of PR #75. That PR was an "Add files via
upload" whole-file replacement (equal +/- on every file = line-ending churn),
so it was unreviewable and got reverted. It also carried a real idea that went
out with it: a separate `timetable_engine.lua` splitting the engine thread from
the GUI thread. Worth revisiting on its own merits, not by un-reverting.

## Licence

GPL-3.0, inherited. Keep `LICENSE` and the existing author credits in `mod.lua`
(Celmi = CREATOR, Gregory365 and quittung = CO_CREATOR).

## Install

    ./install.sh

Copies the mod payload to `$TPF2_LOCAL_MODS/timetables_plus_1`
(default `~/.local/share/Steam/userdata/204184616/1066780/local/mods`).

**The Workshop copy (2408373260) must be disabled.** This fork keeps the
upstream module paths (`res/scripts/celmi/timetables/*`) and the upstream
game_script filename (`timetable_gui.lua`) deliberately — that is what lets an
existing save's timetable data be found. The cost is that the two mods collide
if both are enabled.

Open question, **not yet verified**: whether TpF2 keys a game_script's saved
state by mod id (folder name) or by script path. If it is the mod id, then
renaming the folder to `timetables_plus_1` orphans timetables in an existing
save. Test with a throwaway save before trusting it.

## Tests

    lua5.4 tests/main_tests.lua

Runs from the repo root (the tests `require` via `.res.scripts...` paths).
A failed `assert` exits non-zero — verified by injecting a failure.

Coverage is narrower than the file count suggests:

- `tests/timetable_tests.lua` — 105 assertions, real coverage of the slot
  arithmetic (`getNextSlot`, `getTimeDifference`, slot maths).
- `tests/timetable_helper_tests.lua` — **empty stub**. Its `require` is
  commented out and the tests table has no entries. The file holding all the
  game-API interaction has no coverage.
- `tests/test_nextDeparture.lua`, `tests/test_mock_th.lua`,
  `tests/mock_timetable_helper.lua` — **orphaned**. `main_tests.lua` never
  requires them, they need `luaunit` (not installed, not in upstream CI), and
  they target `timetable.getNextDeparture()`, which exists nowhere in the
  source. Their *cases* are worth porting; the files as-is do not run.
- `tests/timetable_tests.lua` test 1 asserts `x.testfield == y.testfield`
  where neither field exists — `nil == nil`, vacuously true.

## Threading model (the thing to understand first)

A TpF2 `game_script` runs **the same file in two separate Lua states**: the
engine thread and the GUI thread. No shared memory. Two channels only:

    engine  --save() every frame-->  load()  -->  GUI
    GUI     --sendScriptEvent()   -->  handleEvent()  -->  engine

`save()`/`load()` are not only for savegames — the engine's `save()` result is
handed to the GUI's `load()` continuously. The file says so itself: *"load
happens once for engine thread and repeatedly for gui thread."*

This mod syncs the two states by shipping **the entire timetable object** across
in both directions as a wholesale replacement. That single decision is upstream
of most of the open issue list. See `docs/AUDIT.md`.

## Logs

The mod `print()`s to
`~/.local/share/Steam/userdata/204184616/1066780/local/crash_dump/stdout.txt`.
The crash handler prints the offending mod as `mod: "*id"`.

## Upstream issue tracker

Gregory365's repo has 13 open issues. The ones this fork's audit explains:

- #37 Vehicles don't depart when force-departure is disabled
- #8  Value set back to "00" when manually entering arrivals or departures
- #27 Vehicle doesn't depart at correct time
- #29 Large memory consumption and lag spikes
- #11 Waiting vehicles sometimes do not pick up cargo or passengers

Stale branches exist for several (`bugs/ForceDepartureEnabledByDefault`,
`bugs/NoVehicleAutoUnbunchCrash`, `bugs/SlotIsNil`, ...). Checked: the
force-departure branch contains the *same broken function*, so the branches are
not hidden fixes.
