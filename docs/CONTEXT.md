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

**Resolved, with primary evidence.** Saved script state is keyed by the **bare
game_script filename**, not by mod id or folder name. Verified three ways:

- The wiki: "the game scripts only receive stored data that was saved from a
  game script file **with the same filename**."
  <https://wiki.transportfever2.com/doku.php?id=modding:gamescripts>
- On this machine, `…/local/save/gtnh kab.sav.lua` is plain readable Lua whose
  top level is keyed by filename — `["timetable_gui.lua"]`, `["autosig2.lua"]`,
  `["move_it_script.lua"]` — with no mod id, folder name or workshop id
  anywhere.
- Those keys map to mods in entirely differently-named folders.

Consequences, **inverted from what was feared**:

- Renaming the mod folder to `timetables_plus_1` is **safe**; state survives.
- Renaming or moving `res/config/game_script/timetable_gui.lua` is the real
  hazard — that orphans every existing save's timetables. Do not rename it.
- The filename is a **global namespace across all installed mods**. Sharing
  `timetable_gui.lua` with the Workshop mod is what makes timetables transfer,
  and is also exactly why both must never be enabled at once.

## Verified threading contract

Replaces the guesswork previously inferred from mod comments. Sources:
<https://wiki.transportfever2.com/api/topics/states.md.html>,
<https://wiki.transportfever2.com/doku.php?id=modding:gamescripts>, and Urban
Games' own shipped `res/scripts/mission/taskutil.lua`.

| Fact | Status |
| --- | --- |
| Same file, two completely isolated Lua states, no shared variables | confirmed |
| Engine thread runs `load`, `save`, `update`, `handleEvent` | confirmed |
| GUI thread runs `load`, `guiInit`, `guiUpdate`, `guiHandleEvent` | confirmed |
| `save()`→`load()` is the engine→GUI channel | confirmed |
| GUI `load()` fires **~5×/second**, engine `load()` **once** at savegame load | confirmed — *not* per frame |
| `update()` runs at **5 Hz "on average"** | confirmed — do not assume a fixed tick |
| `handleEvent` does **not** fire in the GUI state; no echo to the sender | confirmed structurally from `taskutil.lua`, which would infinite-loop otherwise |
| An engine-sent event re-entering the engine's own `handleEvent` | **unverified** — make engine handlers idempotent |

Two corrections to things the inherited code implies:

- The signature is `game.interface.sendScriptEvent(id, name, param)`. Upstream
  passes `("timetableUpdate", "", obj)` and matches on `id`, which is correct —
  but the argument order is worth knowing before touching it.
- Script events are **broadcast to every game script on the machine**. The id
  `timetableUpdate` is unnamespaced and can collide with another mod. Urban
  Games namespaces theirs (`__taskEvent__`); so should we.

**State discriminator:** `game.gui == nil` is true in the engine state and
false in the GUI state. Urban Games `assert`s on it throughout `taskutil.lua`.
Use it to make engine-only mutators fail loudly instead of desyncing silently.

**Known API limitation:** a script event must be fired from inside a script
callback, not from a GUI element's click handler. Upstream's `timetableChanged`
flag drained in `guiUpdate` is the documented workaround, and is correct.

## What the real save says

`gtnh kab.sav.lua` currently holds 7 line entries / 7 stops of timetable state
— about 98 lines of Lua. Notable:

- Line ids are stored as **strings** (`["107136"]`), which is why
  `setTimetableObject` has code to patch them back to numbers.
- Every stop carries `inboundTime`, a **Celmi-era field that this fork does not
  know about** — the save was written by the Workshop version. Harmless (the
  fork never reads it) but it confirms the schema diverged.
- One stop has `type = "ArrDep"` with an **empty `ArrDep = { }`** — the exact
  S2-3 case, live in a real save.
- Two stops have `debounce = { 0, 0 }` — defaults written into the savegame by
  the display function, S4-2 in the wild.

At this size the cost of shipping the whole object 5×/second is small. The
whole-object sync is a **correctness** problem, not a performance one; the
frequency poll (S3-1) was the real performance win.
and needs asking first.
## Lua version — verified, not assumed

The game embeds **Lua 5.2.2**. Confirmed from the shipped binary, not from any
mod's assumption:

    $ strings -a ".../Transport Fever 2/TransportFever2" | grep LuaVersion
    $LuaVersion: Lua 5.2.2  Copyright (C) 1994-2013 Lua.org, PUC-Rio $

This matters because 5.3+ constructs (integer division, bitwise operators,
`math.type`, `table.move`, `string.pack`, `<const>`) parse fine on a newer host
Lua and then fail in the game. Upstream's CI has this blind spot: its workflow
uses `leafo/gh-actions-lua`, which does not pin 5.2.

Mitigations, both verified by injecting a violation and watching them catch it:

- `./test.sh` runs the suite on **Lua 5.2.4 first** — the game's language
  version — and then on a newer Lua as a stricter cross-check. Both must pass.
  The newer run earns its place: 5.3+ errors on `string.format("%d", x)` for a
  non-integer float where 5.2 truncates silently, so a 5.4-only failure on a
  5.2-green suite usually means a real latent bug.
- `tests/lint_tests.lua` scans every shipped file for 5.3+/5.4-only constructs.
  It **discovers** the file list with `find` rather than hardcoding it, because
  a hardcoded list already let one new module slip past.

`res/scripts/celmi/timetables/ops.lua` binds `table.unpack or unpack` rather
than depending on either being present.

## Tests

    ./test.sh

Runs from the repo root (the tests `require` via `.res.scripts...` paths).
The runner exercises Lua 5.2 first, then a newer Lua as a stricter check.
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
