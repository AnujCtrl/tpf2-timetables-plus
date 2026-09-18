# Timetables Plus — remediation design

Date: 2026-09-18
Status: approved to implement
Baseline: upstream Gregory365/TPF2-Timetables @ `70c7d14`

## Purpose

Make the inherited codebase correct, cheap to run, and safe to extend, before
any new feature is added. Findings and their severities are in `docs/AUDIT.md`;
this document decides what to do about them and in what order.

## Criteria

Ranked, as given:

1. **Does not crash the game.** A Lua error on the engine thread is not a
   cosmetic failure.
2. **Optimized.** Cost per engine tick must scale with what the player
   configured, not with the size of their network.
3. **Easier to use.** Controls that do what they say; behaviour that does not
   silently revert.

## Non-goals

- New features. Deferred until this work is verified in-game.
- Publishing to the Workshop.
- Changing the shape of the saved state blob. Any change that would force a
  save migration is out of scope — it trades directly against criterion 1.
- Un-reverting upstream PR #75. Its engine/GUI split is worth revisiting on its
  own merits; the PR itself is unreviewable line-ending churn.

## Sequencing

Each stage is verified in-game before the next begins.

    Stage 1  correctness        -> verify in-game
    Stage 2  optimization       -> measure first, then verify
    Stage 3  state-sync (B)     -> verify

Risk is front-loaded away: the safe, mechanical fixes land and are proven
before the one structural change is attempted.

---

## Stage 1 — correctness

### Test harness first

`tests/timetable_helper_tests.lua` is an empty stub, so the entire game-facing
layer is untested and several findings (S2-5, S2-6) are not expressible as
tests. Before any fix:

- Add `tests/fake_api.lua` providing the `api.engine.*`, `api.cmd.*` and
  `api.type.*` surface the helper touches, following the pattern already proven
  in `tpf2-bus-line-tool/test/fake_api.lua`.
- Fill `timetable_helper_tests.lua` against it.
- Port the cases from the orphaned `tests/test_nextDeparture.lua` into the
  existing assert style. They target `timetable.getNextDeparture()`, which does
  not exist; the *cases* still encode real edge expectations, in particular the
  hourly `{55,0,0,0}` slot where arrival is later in the hour than departure.
  Re-express them against `getNextSlot`/`getWaitTime`.
- Delete the luaunit files once their cases are ported. They require a
  dependency that is not installed and is absent from upstream CI.

### Fixes

Each gets a failing test first.

| Finding | Fix |
| --- | --- |
| S1-1 | `getForceDepartureEnabled` returns `true` when `forceDeparture == true`. Preserves `d72fbc5`'s intent: default off, toggle functional. |
| S2-2 | `anotherVehicleArrivedEarlier` scans all vehicles at the stop instead of returning inside the loop. Removes the `pairs()`-order nondeterminism. |
| S2-3 | Replace `slots == {}` with an emptiness check (`next(slots) == nil`). |
| S2-4 | `getNextSlot` sorts a copy; persisted `conditions.ArrDep` is never reordered by a read path. |
| S2-5 | Nil guards on `lineStopDepartures[stop]` and `maximumArray` on an empty array. Crash paths. |
| S2-6 | `-1` returns from boolean-documented helpers become `false` — **one function at a time, reading every call site**, because `-1` is truthy and code may accidentally depend on the error path reading as "yes". |
| S4-1 | Coroutine driver: correct the off-by-one, stop resuming a dead coroutine. |
| S4-2 | `conditionToString` stops writing defaults into persistent state. |
| S4-3 | Rename `pcall`'s first return `ok`. No behaviour change. |
| S4-4 | Remove the shadowed `sec` local in `secToMin`. |

**Behavioural change to expect:** with S1-1 fixed, force departure works and
defaults to off. Existing lines behave as they do today until the box is
ticked — the difference is the box does something.

---

## Stage 2 — optimization

Target is S3-1: `update()` polls every line in the game, every tick, through
legacy `game.interface.getEntity`.

**Measure first.** The audit's performance claims are reasoning about call
shape, not measurement. Instrument with `os.clock()` around the loop and read
`stdout.txt` on a real save before changing anything.

Then, in order of value:

1. **Poll only lines that need it.** Frequency is consumed solely by
   AutoUnbunch (`autoDebounceDepartureTime`). Lines without an `auto_debounce`
   condition never need it. This changes the loop's cost from O(all lines) to
   O(lines the player configured) and is the dominant win.
2. **Throttle.** Fold the poll into the coroutine's existing 1 Hz gate rather
   than running it per tick.
3. **Drop the legacy call** if a non-legacy frequency source exists. Probe
   whether frequency is reachable via `api.engine.getComponent`; if not, keep
   `game.interface.getEntity` behind (1) and (2), where it is called rarely.

Also fold in S3-2 (`cleanTimetable` is O(n²) and its call site is commented
out) — decide whether to fix it or remove it, rather than leaving dead O(n²)
code in the file.

---

## Stage 3 — state sync (approach B)

### Problem

Both Lua states copy the entire timetable tree to each other and assign it
wholesale, so each direction can discard the other's concurrent work (S2-1).

### Design

**The engine thread becomes the single writer of timetable state.**

- **Engine → GUI** stays a whole-object snapshot, but the GUI treats it as
  read-only display data.
- **GUI → engine** stops sending the tree. It sends *edit intents* —
  `{op = "setCondition", line = .., stop = .., payload = ..}` — which the
  engine applies to its own authoritative copy.

The engine's `vehiclesWaiting` bookkeeping is then never clobbered by a stale
GUI snapshot, and a GUI edit is no longer a whole-tree race.

`load()` keeps its current unconditional `setTimetableObject`, which is correct
once the GUI is a pure view. (Celmi's `if state == nil` guard is the wrong fix:
it stops the clobbering by making the GUI never see engine updates at all.)

### Edit latency

An intent takes a frame or two to round-trip, so a naive GUI would show the old
value until it lands. Handle with a **pending-edit overlay**: the GUI keeps
edits it has sent but not yet seen reflected, and renders
`snapshot + pending`. An entry clears when the snapshot agrees with it, or
after a timeout. Optimistically mutating the GUI's copy is rejected — the next
snapshot overwrites it, which is the flicker being designed away.

### Save compatibility

The saved blob is still `state.timetable`, the same tree in the same shape.
Nothing about this stage changes what is written to a savegame.

### Risk

Highest of the three stages, which is why it is last. If in-game verification
finds the intent channel unreliable, the fallback is approach A (restore the
load guard) — a strictly smaller change that can be made at any point.

---

## Verification

Host tests (`lua5.4 tests/main_tests.lua`) cover pure logic only. Every stage
is additionally checked in-game on a **throwaway save**, never the main one:

1. Timetables from the Workshop version load and display.
2. An ArrDep slot holds a vehicle and releases it at the slot time.
3. Force departure ticked: vehicle departs at the slot. Unticked: vanilla.
4. AutoUnbunch spaces vehicles on a line by its frequency.
5. No new `stdout.txt` errors; no stall on save/load.

The mod-id-vs-script-path question from `docs/CONTEXT.md` gets answered by
check 1.
