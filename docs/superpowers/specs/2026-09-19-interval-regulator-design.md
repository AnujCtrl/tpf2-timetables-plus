# Interval regulator — design

Date: 2026-09-19
Status: approved in outline, implementation staged below
Supersedes the remediation spec's "new features" placeholder.

## What changes

The mod stops being a timetable mod. Arr/Dep clock schedules are **removed**.
What remains is one job: keep a line's vehicles evenly spaced.

Driving requirements, from the user:

1. No separate window. The control lives in the game's own line window.
2. Waiting times sync with the game's own per-stop settings rather than
   shadowing them.
3. Adding a station to a line must not require reconfiguration.
4. One simple concept: regulate intervals. Not modes, margins and slots.

## Why the existing feature set goes

`Auto Unbunch` already computes the right thing — target headway is lap time
divided by vehicle count, which the game exposes as a line's frequency. The
problem was never the algorithm. It was that expressing one intention required
understanding three concepts (mode, margin time, unbunch time) and repeating
the configuration per stop, where none of the stored data was actually
per-stop.

Arr/Dep is the only feature that genuinely needs per-stop configuration, and
it is being dropped, so the per-stop data model goes with it.

## Behaviour

**One checkbox per line: "Even out intervals".** Nothing else is required.

When enabled, the line has a single **regulation stop**. A vehicle arriving
there is held until the line's headway has elapsed since the previous vehicle
departed that same stop, then released.

    headway  = the line's frequency, from the game
    earliest = lastDepartureFromThisStop + headway - margin
    hold the vehicle until now >= earliest

### Regulate at one stop, not all

Holding at every stop pays the dwell cost once per stop per lap. On a ten-stop
line that is ten holds per circuit to buy evenness that one hold largely
achieves. Real operators use one or two regulation points, typically a
terminus.

It also satisfies requirement 3 for free: adding a station changes the lap
time, so the frequency the game reports changes, so the headway adapts by
itself. Nothing to reconfigure, because the regulator is not at the new stop.

Default regulation stop is stop 1. If the regulating stop is removed from the
line, fall back to stop 1.

### Margin is derived, not configured

The user should not have to know what a margin is. Derived from headway, with
a floor so that very frequent lines still get usable slack.

### Waiting times come from the game

The mod's own `minWaitEnabled` / `maxWaitEnabled` toggles are **removed**. They
shadowed `Line.Stop.minWaitingTime` / `maxWaitingTime`, and defaulted min on
and max off, which is why a hold could be planned that the game would override
at its 3-minute default.

Instead: always respect the stop's configured min and max. If regulating the
line requires a hold longer than the regulation stop's `maxWaitingTime`, raise
that stop's ceiling through `api.cmd.make.updateLine` rather than planning a
hold the game will cancel. The mod configures the game instead of fighting it.

This closes RISK 1 in `docs/API_FACTS.md` by construction.

### Force departure is implicit

Regulation requires controlling departure, so the hold uses
`setVehicleManualDeparture` and the release uses `setVehicleShouldDepart`.
There is no toggle: it is what the feature does.

## Data model

Before, per line: `hasTimetable`, `forceDeparture`, `minWaitEnabled`,
`maxWaitEnabled`, `frequency`, and a `stations` map each holding `conditions`
(four modes) and `vehiclesWaiting`.

After, per line:

    regulation[line] = {
        enabled  = true,      -- GUI-owned
        stop     = 1,         -- GUI-owned, which stop regulates
        headway  = 207,       -- engine-owned, cached from frequency
        waiting  = { },       -- engine-owned, vehicle -> planned departure
    }

Per-field ownership from the state-sync rework carries over unchanged; the
field lists shrink.

## Migration

Saved state is keyed by game_script **filename**, so `timetable_gui.lua` is
kept as the filename permanently despite no longer describing what the file
does. Renaming it orphans every existing save. The cost is a misleading name;
the alternative is silent data loss.

On load, old-format state is converted:

- a line with any stop set to `debounce` or `auto_debounce` becomes
  `enabled = true`, with `stop` set to the first such stop
- a line whose stops are all `None` or `ArrDep` becomes `enabled = false`
- Arr/Dep slots are discarded, and their loss is logged once per line

Migration is pure logic over the loaded table and is tested as such.

## UI

Injected into the game's line window via the hook More Line Statistics uses:

    guiHandleEvent(id, name, param)
      name == "idAdded" and id:match("temp.view.entity_%d")
      -> entity has a LINE component -> getById(id):getContent():addItem(...)

Content: one checkbox, plus a status line naming the regulation stop and the
current headway. The standalone window, its tabs, the constraint editor and
the station tab are all deleted.

## What this deletes from the recent remediation

Honest accounting. Of the 13 findings fixed:

- **S2-3** (`slots == {}`) and **S2-4** (`getNextSlot` sorting persisted
  slots) are Arr/Dep-specific and die with the feature, along with their
  tests and the slot arithmetic they guard.
- Everything else survives: the crash guards, the error-path return types,
  the display-mutation fixes, the coroutine driver, the prune, the per-field
  state ownership, and the whole verified-API foundation.
- **S1-1** (force departure) survives as behaviour but loses its toggle — the
  hold is now unconditional, which is what the fix made possible.

The ArrDep slot-arithmetic tests were also the bulk of upstream's only real
test coverage. Removing the feature removes them; the regulator needs its own.

## Staging

1. Regulator core as pure logic, with migration. Tested on the host.
2. Line-window UI, standalone window deleted.
3. Waiting-time sync via `updateLine`.
4. Remove the probe once RISK 1 is observed under the new behaviour.

## Open, deliberately not decided yet

- Whether to let the user move the regulation stop, or keep it automatic.
  Defer until the automatic choice has been felt on a real line.
- Whether the mod should be renamed. Its identity has changed, but the
  game_script filename cannot move, so a rename is cosmetic only.
