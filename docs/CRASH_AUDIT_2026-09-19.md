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
