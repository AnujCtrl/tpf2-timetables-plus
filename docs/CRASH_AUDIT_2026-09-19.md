# Crash audit, 2026-09-19 (HEAD b8da25c)

Why: the game crashed on 2026-09-19 with `timetable_gui.lua:315: bad argument #2 to 'tonumber' (base out of
range)` in guiHandleEvent (`tonumber(id:gsub(...))`: gsub's count became the base). Fixed in b8da25c with a
lint test. A Lua error escaping a game-script or widget callback crashes the whole game; inside pcall it is
only logged. This audit looked for more of the same. Nothing is left in "will crash in normal play".

## Can crash under conditions a player will eventually hit (all unguarded callbacks)
- B1 `res/config/game_script/timetable_gui.lua` load(): indexes its argument after only a nil check
  (`loadedState.regulation`). The game has been seen storing and passing a boolean as a script's state.
  Fix: `if reset or type(loadedState) ~= "table" then return end`.
- B2 guiHandleEvent: `api.engine.getComponent(entityID, LINE)` on an id parsed from a window id, outside the
  pcall. getComponent RAISES "Invalid entity" on a dead id (that exact error crashed another mod here).
  Fix: `api.engine.entityExists(entityID)` first, and put the whole handler body under the guard.
- B3 guiHandleEvent: `api.gui.util.downcast(api.gui.util.getById(id))` before the nil check (suspicion).
- B4 the checkbox onClick: getAllStations -> getComponent, statusTextFor -> game.interface.getEntity, all
  unguarded; `configChanged = true` is the last statement, so a raise leaves the box flipped and the engine
  never told.
- Entry points guarded today: only update() (its work runs inside coroutine.resume). handleEvent, save, load,
  guiUpdate, guiHandleEvent (partial) and the checkbox callback are not.

## Wrong behaviour, no crash
- C1 HEADLINE `res/scripts/celmi/timetables/timetable_helper.lua:164`: `departure / 1000`, but
  lineStopDepartures is MICROseconds (gameTime is milliseconds, doorsTime is microseconds). Proven from this
  mod's own probe lines in crash_dump/stdout_old.txt: with /1000000 the previous departures are 313, 304, 348,
  306 s apart (a ~5 min headway); with /1000 they are 5.7 years in the past. Effect: every regulated vehicle is
  held for exactly the stop's max waiting time, or for ever where the stop has none, and that departureTime is
  written into the save. Two tests encode the wrong constant (tests/timetable_helper_tests.lua:23,27,33,37).
- C2 the probe prints a cooked value (getPreviousDepartureTime's output), so it could never show C1.
- C3 regulator.adoptGuiConfig deletes engine entries the GUI blob lacks; a GUI whose first load saw an empty
  state would wipe every other line's config on the first checkbox click.
- C4 nothing prunes deleted lines or sold vehicles any more. C5 regulated lines switch a vehicle the player
  parked on manual departure back to auto. C6 one bad line aborts the rest of that second's pass (pcall each
  line). C8 a NaN frequency would hold a vehicle for ever (suspicion). C9 state.timetable only cleared on
  migration. About two thirds of timetable_helper.lua has no caller in the shipped code.

## Save fallback (2026-09-19)

**Bug.** The game writes whatever save() returns into `<save>.sav.lua`, verbatim, and hands it to load() next
session. save() kept a fallback for a guarded failure, but it was initialised to `{ }` and replaced by anything
that was not nil. So a first save() that failed persisted `{ }`, and a guard that returned a non-table persisted
that: the 15:09 autosave holds `["timetable_gui.lua"] = true` and every regulated line's config in it is gone
(the unpack-based guard returned xpcall's `true`; mechanism fixed in 7c425ea). No log line either way.

**Fix** (`res/config/game_script/timetable_gui.lua`, `guard.report` added to `celmi/timetables/guard.lua`):
- `lastGoodState` starts as nil, is seeded by the first usable load() and refreshed by every successful save().
  Usable = a non-empty table. It is held by reference (in practice the same table as `state`), so it is as
  current as the state itself and never a stale snapshot, in whichever Lua state save() runs.
- save() returns the fresh state only if it is a usable table. Otherwise it returns `lastGoodState`; failing
  that the live `state` that update()/handleEvent have been keeping (new game, player configured lines, every
  save failed); failing that the new-game default `{regulation = { }}`. Never a non-table, never `{ }`. One
  line is logged: `timetables_plus: save: could not build a fresh state; the previous state was re-saved`
  (throttled like every guard line: first occurrence, then every 100th).
- load() already ignored a non-table without touching held state; it now also logs one line for it
  (`timetables_plus: load: was given a boolean (true), not a state; ignored, ...`). nil, `{ }` and `reset` stay
  silent: they are the game's ordinary "nothing to adopt" (guidesystem.lua:1343). `{ }` is no longer adopted as
  the session's state, which used to make the real state arriving next look like a repeat call (only `waiting`
  copied) - one route into C3.
- Tests: `tests/save_fallback_tests.lua` drives the real game_script through data() under fakes, including two
  coexisting copies standing in for the engine and GUI states.

**Still unverified in the game.**
- Which thread the game calls save() on (the wiki says engine; nothing on this machine proves it). The code is
  written to be right in both; the two-state test pins that the GUI copy re-saves the newest engine data it has.
- That load() precedes the first update()/save() on the engine thread. If update() ran first, `state` would be
  non-nil and the sidecar's config would be taken for a repeat call. Unchanged by this fix.
- Whether one Lua state is reused when a second savegame is loaded in the same session; if so the fallback
  (like `state` itself) would belong to the first save. Unchanged by this fix.
- Whether the GUI's load() is handed a non-table at startup in normal play; if it is, expect one benign
  `load: was given ...` line per session.
- The poisoned 15:09 autosave is not repaired by any of this: load it and the mod starts empty (and now says
  so). Load `gtnh kab.sav` instead.
