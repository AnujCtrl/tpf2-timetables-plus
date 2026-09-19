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

    ./test.sh

Runs the suite on **Lua 5.2** — the version the game embeds — and again on a
newer Lua as a stricter cross-check. Both must pass. Verified by injecting a
failing assertion and watching the runner exit non-zero.

## Read first

- `docs/CONTEXT.md` — lineage, the two-Lua-state threading model, install
  gotchas, log paths.
- `docs/AUDIT.md` — audit of the inherited code: what is broken, where, and
  how severe.

## State of this fork

Forked and audited 2026-09-18. **All 13 audit findings are fixed**, each with a
test that was watched failing first. See `docs/AUDIT.md` for the findings and
their resolution, `docs/API_FACTS.md` for what was verified against the game
itself rather than assumed.

Headlines:

- **Force departure was dead code.** Every path of `getForceDepartureEnabled`
  returned false, so the checkbox did nothing and the mod never enforced its
  own departure times. Broken since November 2023.
- **Three engine-thread crash paths** guarded, all reproduced on the host first.
- **The engine and GUI no longer clobber each other.** State now has explicit
  per-field ownership instead of both sides replacing the whole tree.
- **The per-tick poll of every line in the game is gone.**

**Not yet run in the game.** Two questions cannot be answered by reading and
need one session with the probe — see `docs/API_FACTS.md` RISK 4 (a possible
1000x error in every arrival time) and RISK 1 (whether the game's own maximum
waiting time overrides our hold). Do that on a throwaway save.
