# Timetables Plus

Transport Fever 2 mod that keeps a line's vehicles **evenly spaced instead of
bunched up**. Tick "Even out intervals" in any line window. There is no
separate window, and nothing to configure per stop.

A fork of [Gregory365/TPF2-Timetables](https://github.com/Gregory365/TPF2-Timetables),
itself a fork of Celmi's [TPF2-Timetables](https://github.com/IncredibleHannes/TPF2-Timetables).
Created by Celmi, continued by Gregory365 and quittung. GPL-3.0.
Upstream's own README is kept at `docs/UPSTREAM_README.md`.

## How it works

A line with N vehicles and a lap time T has an ideal headway of T/N — which
the game already computes and shows as the line's frequency. Each regulated
line has one **regulation stop**; a vehicle arriving there is held until a
headway has elapsed since the previous vehicle departed that same stop.

Regulating at one stop rather than every stop is deliberate. Holding everywhere
pays the dwell cost once per stop per lap, and real operators use one or two
regulation points rather than all of them. It also means **adding a station
needs no reconfiguration**: the lap time changes, so the frequency changes, so
the headway adapts by itself.

The stop's own minimum and maximum waiting times are respected rather than
shadowed, so the mod never plans a hold the game will cancel. When the stop's
ceiling is too low to regulate properly, it says so in the log.

## Install

    ./install.sh

Copies the mod to the game's local mods folder as `timetables_plus_1`.
**Disable or unsubscribe from the Workshop copy** (`2408373260`): both register
the same module paths, deliberately so — see `docs/CONTEXT.md`.

## Tests

    ./test.sh

Runs the suite on **Lua 5.2** — the version the game embeds — and again on a
newer Lua as a stricter cross-check. Both must pass.

## Read first

- `docs/CONTEXT.md` — lineage, the two-Lua-state threading model, install gotchas.
- `docs/API_FACTS.md` — what was verified against the game itself, with sources.
- `docs/AUDIT.md` — the 13 findings in the inherited code, and their fixes.
- `docs/superpowers/specs/` — the remediation and interval-regulator designs.

## State of this fork

Forked and audited 2026-09-18; rewritten as an interval regulator 2026-09-19.
All 13 audit findings were fixed first, each with a test watched failing.

Arr/Dep clock timetables are **removed**. Existing saves are migrated on load:
a line that was unbunching becomes a regulated line at the stop that was doing
the unbunching; Arr/Dep slots are discarded.

**Not yet run in the game since the rewrite.**

## Known gaps

- The mod name and description are updated for English and German only; the
  other five locales still describe the old Arr/Dep behaviour.
- The regulation stop is always stop 1 unless migrated from an unbunching
  stop. Moving it is not exposed yet — deliberately, until the automatic
  choice has been felt on a real line.
