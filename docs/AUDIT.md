# Code audit — upstream @ 70c7d14 (2024-11-15)

Audit of Gregory365/TPF2-Timetables `main` as inherited by this fork.
Performed 2026-09-18 by reading the source. Nothing here was measured in a
running game; see "Not verified" at the end.

Severity: **S1** breaks a headline feature · **S2** causes wrong behaviour or
crashes · **S3** performance · **S4** smell / latent.

---

## S1-1 · `getForceDepartureEnabled` always returns false

`res/scripts/celmi/timetables/timetable.lua:442`

```lua
function timetable.getForceDepartureEnabled(line)
    if timetableObject[line] then
        if timetableObject[line].forceDeparture ~= true then
            return false
        end
    end
    return false          -- every path returns false
end
```

Introduced by `d72fbc5` (2023-11-18, *"Update: Force departure to be disabled by
default"*). The commit flipped both the condition and the return when it should
have flipped only one:

```diff
-        if timetableObject[line].forceDeparture ~= false then
-            return true
+        if timetableObject[line].forceDeparture ~= true then
+            return false
```

Consequences, live for ~2 years:

- `timetable.lua:311` — `departIfReady` can never reach
  `timetableHelper.departVehicle`. It always falls through to
  `restartAutoVehicleDeparture`, handing control back to vanilla. The mod stops
  enforcing its own departure times.
- `timetable_gui.lua:616` — the "Force departure" checkbox reads this getter, so
  it renders unchecked forever. `setForceDepartureEnabled` writes the value; the
  read discards it. The toggle is cosmetic.

Maps to upstream issue #37. The branch `bugs/ForceDepartureEnabledByDefault`
contains the *same broken function* — never fixed anywhere.

Compare the neighbouring `getMinWaitEnabled` (`:450`), which has the correct
shape and returns `true` in the matching branch.

---

## S2-1 · Whole-object state sync races in both directions

The two Lua states (see `docs/CONTEXT.md`) are synchronised by copying the
entire timetable tree across and assigning it wholesale.

**Engine → GUI**, `res/config/game_script/timetable_gui.lua:1201`

```lua
load = function(loadedState)
    state = loadedState or {timetable = {}}
    timetable.setTimetableObject(state.timetable)   -- unconditional
end,
```

Celmi's original guarded this with `if state == nil then ... end`, so it ran
once. Removing the guard is a **regression introduced in this fork's lineage**.
Because the GUI thread's `load()` is called every frame, the engine's snapshot
now overwrites the GUI's copy continuously — including while the user is typing
into an arrival/departure field. Most plausible mechanism for issue #8.

**GUI → engine**, `timetable_gui.lua:1231` → `:1180`

```lua
game.interface.sendScriptEvent("timetableUpdate", "", timetable.getTimetableObject())
...
state.timetable = param
timetable.setTimetableObject(state.timetable)       -- wholesale replace
```

Any `vehiclesWaiting` bookkeeping the engine advanced since the GUI's last
snapshot is silently discarded — a lost update. Fits issues #64 (*vehicle
assigned its previous slot*) and #27 (*vehicle doesn't depart at correct time*).

This architecture is **Celmi's, inherited unchanged** — the `data()` blocks are
the same shape in both. Choosing a different base does not avoid it.

---

## S2-2 · `anotherVehicleArrivedEarlier` inspects one arbitrary vehicle

`timetable.lua:553`

```lua
for _, otherVehicle in pairs(vehiclesAtStop) do
    if otherVehicle ~= vehicle then
        ...
        return otherArrivalTime < arrivalTime    -- returns inside the loop
    end
end
```

The `return` is inside the loop, so with three or more vehicles at a stop only
the first one `pairs()` happens to yield is considered. `pairs()` order is
unspecified, so the unbunching decision is **nondeterministic** for busy stops.

---

## S2-3 · `slots == {}` is always false

`timetable.lua:397`

```lua
if not slots or slots == {} then
```

In Lua, table comparison is by identity, so `{} == {}` is always false. The
empty-slots guard never fires; the `conditions.type = "None"` reset it is
supposed to perform never happens. Downstream code only works because
`getNextSlot` separately returns `nil` for an empty list.

---

## S2-4 · `getNextSlot` reorders persisted user configuration

`timetable.lua:620`

```lua
table.sort(slots, function(slot1, slot2) ... end)
```

`slots` is `timetableObject[line].stations[stop].conditions.ArrDep` — persisted
state. A read path silently reorders the user's saved slot list on every vehicle
arrival.

---

## S2-5 · Unguarded arithmetic on possibly-nil API values

`timetable_helper.lua:159`

```lua
departureTimes[#departureTimes + 1] = lineVehicle.lineStopDepartures[stop]/1000
```

No nil guard. A vehicle that has not yet departed that stop gives
arithmetic-on-nil. There is a stale upstream branch named
`bugs/NoVehicleAutoUnbunchCrash`.

`timetable_helper.lua:476` — `maximumArray` returns `nil` for an empty array and
callers do arithmetic on the result.

---

## S2-6 · Boolean-documented functions return `-1`, which is truthy

`timetable_helper.lua:199` and throughout the helper:

```lua
---@param lineType string
-- returns Bool
function timetableHelper.lineHasType(line, lineType)
    if not(type(line) == "number") then print(...) return -1 end
```

In Lua only `nil` and `false` are falsy, so **every error path reads as "yes"**
at the call site. This pattern is pervasive in `timetable_helper.lua`.

---

## S3-1 · Per-tick poll of every line through the legacy API

`timetable_gui.lua:1223`, inside `update()` — i.e. every engine tick:

```lua
local lines = game.interface.getLines()
for _, line in pairs(lines) do
    timetable.addFrequency(line, timetableHelper.getFrequency(line))
end
```

`getFrequency` (`timetable_helper.lua:223`) calls `game.interface.getEntity(line)`
— the **legacy** interface, which materialises a full entity table per call,
rather than `api.engine.getComponent`. So every tick, for every line in the
game, a whole entity table is built and discarded.

This loop is **new in this fork's lineage** (AutoUnbunch needs line frequency);
Celmi's `update()` has no equivalent. Prime suspect for issue #29, *"Large
memory consumption and lag spikes."*

`save()` at `:1188` compounds it: it rebuilds `state = {}` and returns the live
object for serialisation every frame.

---

## S3-2 · `cleanTimetable` is O(n²)

`timetable.lua` — calls `timetableHelper.lineExists(lineID)` per line, and
`lineExists` (`timetable_helper.lua:301`) calls `getLines()` and scans it every
time.

**Correction (2026-09-19).** This audit originally said the call site was
commented out. That was wrong: `timetable_gui.lua:97` called `cleanTimetable`
on every open of the station tab. Only the *second* call site, inside the
coroutine, was commented out. Removing the function on the strength of the
original claim would have produced a nil-call in game that no test could have
caught, because the game_script cannot be loaded from a test.

---

## S4-1 · Coroutine driver

`timetable_gui.lua:1210`

```lua
for _ = 0, 20 do            -- 21 iterations, not 20
```

and it keeps resuming after the coroutine has died, printing an error each
iteration — roughly 20 log lines per tick while broken.

---

## S4-2 · Display function mutates persistent state

`timetable_helper.lua:505` — `conditionToString`, used to render a label, writes
default values back into the condition table.

---

## S4-3 · `pcall` results named `err`

`timetable_helper.lua` (`getLineName`, `getStationName`) and
`timetable_gui.lua` — `local err, msg = pcall(...)` then `if not err`. The first
return of `pcall` is `ok`, not an error. The logic is correct; the naming
inverts its meaning and invites a wrong "fix".

---

## S4-4 · Shadowed locals

`timetable.lua` — `secToMin` declares `local sec` shadowing its own `sec`
parameter.

---

## Not verified

- The threading claims come from the code's own comments and the standard TpF2
  game_script contract, **not from instrumenting a running game**.
- The performance claims (S3-1, S3-2) are reasoning about call shape, **not
  measurement**. Time them in-game before optimising.
- Whether saved script state is keyed by mod id or script path (see
  `docs/CONTEXT.md`).

---

# Resolution status — updated 2026-09-18

Stage 1 (correctness) complete. Every fix had a test watched failing first.

| Finding | Status | Test |
| --- | --- | --- |
| S1-1 force departure dead code | fixed | `timetable_tests` #16 |
| S2-1 whole-object sync race | fixed — per-field ownership | `timetable_tests` #23–25 |
| S2-2 scans one arbitrary vehicle | fixed | `timetable_tests` #17 |
| S2-3 `slots == {}` never fires | fixed | `timetable_tests` #19 |
| S2-4 read path reorders saved slots | fixed | `timetable_tests` #18 |
| S2-5 nil crash paths | fixed (3 sites) | `helper_tests` #1–3, `timetable_tests` #20, #21 |
| S2-6 truthy `-1` / `"ERROR"` returns | fixed (3 fns) | `helper_tests` #5, #6 |
| S3-1 per-tick all-lines poll | fixed | `timetable_tests` #26 |
| S3-2 `cleanTimetable` O(n²) | fixed — replaced by `pruneDeletedLines` | `timetable_tests` #28–30 |
| S4-1 coroutine driver | fixed — extracted to `driver.lua` | `driver_tests` #1–3 |
| S4-2 display fn mutates state | fixed (2 sites) | `helper_tests` #7, `timetable_tests` #22 |
| S4-3 `pcall` result named `err` | fixed | covered by existing |
| S4-4 shadowed `sec` local | fixed | covered by existing |

## S4-1 — deferred, then fixed

It was deferred from stage 1 because it lived inside the closure returned by
`data()` in `res/config/game_script/timetable_gui.lua`, which cannot be
required from a test: that file pulls in the `gui` module and builds live API
widgets at load. Fixing it there would have meant production code with no test
behind it.

**Done 2026-09-19.** The driver moved to
`res/scripts/celmi/timetables/driver.lua` and is tested against real
coroutines — one that yields forever, one that finishes, and one that errors.

## S2-5, on moving a crash rather than removing one

Guarding `getPreviousDepartureTime` made it reliably return `nil` where it
previously crashed — which relocated the crash into its two callers, and a test
caught exactly that. A third nil path surfaced in the same area:
`autoDebounceDepartureTime` returned `nil` for a line with no frequency, which
reached `nil <= number` in `afterDepartureTime`.

All three now release the vehicle. Releasing was chosen over holding: without a
previous departure or a frequency there is no spacing information to act on, and
the failure mode of holding is a vehicle frozen at a platform indefinitely.

## Characterization test

`helper_tests` #4 (`maximumArray` returns `nil` for an empty array) passed on
the first run — it is a characterization test, not a driven one. It exists to
lock the contract the caller guards now depend on, so that "fixing"
`maximumArray` to return `0` cannot silently change unbunching behaviour.
