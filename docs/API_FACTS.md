# Verified API facts

Established 2026-09-18 against the official wiki, the LDoc API reference, Urban
Games' shipped scripts, the 35924 binary on this machine, and the savegames in
`~/.local/share/Steam/userdata/204184616/1066780/local/save/`.

Nothing here is taken from the inherited mod's comments. Where the official
record is silent, this document says so rather than guessing.

## The target is frozen

The game's **final patch was 35924, 19 December 2024**. Urban Games has moved to
Transport Fever 3. The local install reports build 35924 despite Steam having
refreshed it in September 2026.

Practical consequence: **validate once against 35924 and the answer stays
valid.** There is no moving target. (Caveat: a beta channel exists and was not
audited.)

## Everything this mod calls still exists

Every `transportVehicleSystem` binding the mod uses is present in the 35924
binary — `getLine2VehicleMap`, `getLineVehicles`, `getLineStopVehicles`,
`getVehiclesWithState`. `lineSystem.getLines` is unchanged. All three departure
commands are intact and unchanged since they were introduced.

Between March 2021 and the final patch, **no scripting API was removed or
renamed.** Every change was additive, with one exception irrelevant here
(`EdgeGeometry`'s return shape, May 2022, track geometry only).

The "summer update" a June-2021 upstream commit anticipated is **33718,
8 July 2021**, whose changelog lines map to:

- "commands to control vehicle departure" → `setVehicleManualDeparture`,
  `setVehicleShouldDepart`, `setUserStopped`
- "command to get list of vehicles in a specific state" → `getVehiclesWithState`

## Risk 1 — the game's own max waiting time may override our hold

**This is the most serious open question for the mod.**

The same July 2021 update added *"minimum and maximum waiting time to loading
configuration per station"*. The game manual says:

> A vehicle will wait at least the minimum time and leave at the maximum time
> **regardless of the condition** specified in the dropdown above.

But `api.cmd.make.setVehicleManualDeparture` — the command this mod holds
vehicles with — is documented as:

> it will **not depart from the terminal under any circumstance**

**Those two absolute claims are in tension and no official source resolves
them.** If the game's max-waiting-time timeout wins, every timetable slot longer
than a stop's max waiting time is silently broken, and the mod cannot tell.

Note the default timeout is **3 minutes of real time at default game speed**,
which is well within the range of ordinary timetable slots.

Current behaviour: `timetable.getDepartureTime` clamps by
`stopInfo.minWaitingTime` / `maxWaitingTime`, but `getMinWaitEnabled` defaults
**on** while `getMaxWaitEnabled` defaults **off**. So by default the mod honours
the game's minimum and ignores its maximum — precisely the case that breaks if
the game enforces the maximum anyway.

**Resolve by experiment, not by reading.** Until then, do not assume a hold
holds.

## Risk 2 — a stop is no longer a single terminal

Version 35044 (May 2022) *"added alternative terminals assignment in line
manager"*; `api.type.Line.Stop` now carries `alternativeTerminals`. The
March-2021 model this code was written against had no such concept.

Upstream's history shows scar tissue consistent with this being a root cause
rather than isolated bugs: *"Fix: No unbunch for multiple platforms"*
(Oct 2024), *"Add: guard"*. 35230 (March 2023) then changed pathfinding around
alternative terminals again.

Any logic keyed on a stop having one terminal is suspect for multi-terminal
stations.

## Risk 3 — train departure ordering was re-based

35905 (September 2024): *"Fixed order of train departure when multiple trains
are waiting for the same track section."* Unbunching logic that assumes a
particular release order for trains contending for one section was written
against different behaviour.

## Issue departure commands from the engine, never the GUI

From the API reference:

> **GUI State** — Commands sent from the GUI will take time to take effect, and
> the callback will be called **many frames after** the command has been sent.
>
> **Engine State** — In this state **all commands take effect immediately**.

The mod already gets this right: `departVehicle` is reached from the coroutine
driven by `update()`, which is the engine state. Keep it that way.

## Deprecated and undocumented corners

- `api.type.Line.waitingTime` is **deprecated** — superseded by the per-stop
  min/max pair. This mod does not use it; do not start.
- `getLineStopVehicles` **exists in the binary but is entirely undocumented** —
  not in the API reference, not in any release note. `getVehiclesAtStop` depends
  on it. It works; it has no published contract.
- `game.interface.getEntity(line).frequency`, which `getFrequency` reads, is
  **documented nowhere**. `game.interface` is not formally deprecated, but the
  LDoc reference covers only `api.*`, and no release note has mentioned
  `game.interface` since March 2021.

## Not a risk, contrary to expectation

**The game has no built-in unbunching and never has.** "unbunch" appears zero
times in the entire release-notes history and zero times in the 35924 binary.
This mod is not duplicating or fighting a built-in feature.

The per-stop min/max waiting time is a **dwell-time clamp**, not headway
regulation — it has no notion of the gap to the preceding vehicle.

## `update()` budget

5 Hz, "on average" — official. Do not assume a fixed tick; accumulate elapsed
time where precision matters. This is the budget the S3-1 optimization was
designed against.

---

# Binary-level findings (35924)

From reading the `sol2` registration tables out of the stripped binary —
string/`lea` cross-reference over `.text`, plus `R_X86_64_RELATIVE` relocations
for the enum tables, plus demangled `usertype_metatable` template symbols for
component field types. "Exists" below means the registration code that publishes
the name was located and read, not that a string matched.

## Everything checks out except two things

`TRANSPORT_VEHICLE` has exactly 23 fields; all nine this mod uses are present
and correctly named: `state`, `stopIndex`, `doorsOpen`, `doorsTime`,
`lineStopDepartures`, `timeUntilCloseDoors`, `sectionTimes`, `carrier`, `line`
(plus `autoDeparture`, which the mod also reads).

`LINE` has exactly three fields — `stops`, `waitingTime`, `vehicleInfo`.
`Line::Stop` carries `stationGroup`, `minWaitingTime`, `maxWaitingTime`,
`alternativeTerminals`, `loadMode`, `terminal`, `waypoints`, `stopConfig`.

`api.cmd.make.setVehicleShouldDepart(vehicleEntity)` takes **one** argument.
This mod passes one. Correct.

## RISK 4 — the time-unit contradiction (UNRESOLVED, do not "fix" blind)

`GAME_TIME.gameTime`, `doorsTime`, `lineStopDepartures[]` and
`lastLineStopDeparture` are **all `long long`**, and the binary analysis
concludes they share one time base, with `game.interface.getGameTime().time`
being that base in seconds (so the native unit is **milliseconds**).

But this mod scales them **inconsistently**, and every downstream calculation
needs seconds (`% 3600` slot arithmetic):

| value | mod divides by | implies unit |
| --- | --- | --- |
| `gameTime` (`timetable_helper.lua:460`) | `1000` | milliseconds |
| `lineStopDepartures[stop]` (`timetable_helper.lua:162`) | `1000` | milliseconds |
| `doorsTime` (`timetable.lua:329`, `:590`) | **`1000000`** | **microseconds** |

Both cannot be true if they share a base. Either `doorsTime` really is
microseconds and the binary analysis over-generalised from the shared C++ type,
or **this mod is out by a factor of 1000 on every arrival time** — which would
fit open issue #27, *"Vehicle doesn't depart at correct time"*.

Cross-checking other installed mods was inconclusive: only one other mod reads
`doorsTime` at all, and it does not scale it.

**Deliberately not changed.** Altering a divisor by 1000× on a static inference,
in the value that drives every slot decision, is exactly the kind of change that
needs evidence. **Probe it in-game first** — log `doorsTime`, `gameTime` and
`lineStopDepartures[stop]` side by side for one vehicle at a terminal and
compare the magnitudes. That single log line settles it.

## RISK 5 — `load` has a second parameter this mod ignores

The `GameScriptRep` constructor binds `load` as
`(ctx, lua::Value2 const&, bool)` — i.e. **`load(state, reset)`**. Urban Games'
own code uses the flag (`res/scripts/guidesystem.lua:1343`):

```lua
load = function (state, reset)
    if state == nil or next(state) == nil or reset then return end
```

This mod declares `load = function(loadedState)` and ignores `reset`, so it will
adopt state on a reset/new-game when it should discard it. Fix as part of the
state-sync rework.

## Line frequency: the legacy call has to stay

**There is no `api.engine.*` route to line frequency.** `LINE` has no frequency
field, `LineVehicleInfo` has exactly two members (`transportModes`,
`defaultPrice`), and the string `"frequency"` occurs **once** in the whole
binary, referenced from inside the `game.interface.getEntity` line branch.

So `game.interface.getEntity(line).frequency` is the only published route, and
it is not deprecated (no deprecation notice exists anywhere in the shipped
product; "legacy" is only an internal C++ name).

This closes the stage-2 question: the legacy call **cannot** be dropped. The
S3-1 fix — calling it only for lines that actually use AutoUnbunch — was
therefore the whole available win, not a stepping stone.

The alternative, if the legacy surface ever has to go: compute headway directly
from `TransportVehicle.lineStopDepartures` across
`transportVehicleSystem.getLineVehicles(line)`. That is strictly more
information than the scalar frequency and is entirely `api.engine.*` — but it is
a reimplementation, not a substitution.

## Reading components from the GUI thread is sanctioned

`res/scripts/selectortooltip.lua` calls `api.engine.entityExists` and
`api.engine.getComponent` from inside `guiUpdate`. So the GUI does **not** need
vehicle data ferried through `save`/`load` — only state the mod owns and wants
persisted. This simplifies the state-sync design: `vehiclesWaiting` is the
engine's private bookkeeping, and the GUI can read live vehicle data directly.

`api.engine.getComponent` returns **nil** when the component is absent, which is
what the S2-5 guards assume.
