# Timetables Plus

Transport Fever 2 timetable mod — a fork of
[Gregory365/TPF2-Timetables](https://github.com/Gregory365/TPF2-Timetables),
itself a fork of Celmi's
[TPF2-Timetables](https://github.com/IncredibleHannes/TPF2-Timetables).

Created by Celmi. Continued by Gregory365 and quittung. GPL-3.0.
Upstream's own README is kept at `docs/UPSTREAM_README.md`.

## Install

    ./install.sh

Copies the mod to the game's local mods folder as `timetables_plus_1`.
**Disable or unsubscribe from the Workshop copy** (`2408373260`): both register
the same module paths, deliberately so — see `docs/CONTEXT.md`.

## Tests

    lua5.4 tests/main_tests.lua

Run from the repo root. A failed `assert` exits non-zero.

## Read first

- `docs/CONTEXT.md` — lineage, the two-Lua-state threading model, install
  gotchas, log paths.
- `docs/AUDIT.md` — audit of the inherited code: what is broken, where, and
  how severe.

## State of this fork

Set up 2026-09-18. Baseline tests pass. No mod code changed yet — the audit
came first, and remediation is sequenced ahead of new features.
