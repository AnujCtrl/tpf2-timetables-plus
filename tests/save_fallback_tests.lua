-- The game writes whatever save() returns into <save>.sav.lua on every save
-- and autosave, and hands it back to load() next time. On 2026-09-19 an
-- autosave stored `["timetable_gui.lua"] = true` and the whole regulation
-- config was gone. These tests drive the real game_script through data(), on
-- the host, to pin what save() may return when it cannot build a fresh state.
-- See docs/CRASH_AUDIT_2026-09-19.md, "Save fallback".
local fakeApi = require "tests.fake_api"

local GUI_FILE = "res/config/game_script/timetable_gui.lua"
local MODULE_PREFIX = "celmi/timetables/"
local MODULES = {"regulator", "timetable_helper", "driver", "probe", "guard"}
local EVENT_ID = "__timetables_plus__"

-- The game_script requires its modules by their in-game names
-- ("celmi/timetables/guard"), which resolve against res/scripts in the game.
-- Appended, so nothing the other test files require resolves differently.
if not package.path:find("./res/scripts/?.lua", 1, true) then
    package.path = package.path .. ";./res/scripts/?.lua"
end

---One isolated copy of the game_script, as the game gives each thread: fresh
---file-level locals and fresh modules (the regulator's state and the guard's
---log throttle are both module-level). Two copies can coexist, which is how
---the engine and GUI states are modelled below.
---@return table script what data() returned
---@return table regulator the regulator module this copy is using
---@return table guard the guard module this copy is using
local function freshScript()
    fakeApi.install()
    for _, name in ipairs(MODULES) do
        package.loaded[MODULE_PREFIX .. name] = nil
    end

    dofile(GUI_FILE)
    local script = data()
    _G.data = nil

    return script, require(MODULE_PREFIX .. "regulator"), require(MODULE_PREFIX .. "guard")
end

---Run fn, capturing every print() made during it. Restores print however fn
---ends.
local function captureLines(fn)
    local lines = {}
    local realPrint = print
    _G.print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do
            parts[#parts + 1] = tostring((select(i, ...)))
        end
        lines[#lines + 1] = table.concat(parts, "\t")
    end

    local ok, err = pcall(fn)
    _G.print = realPrint
    if not ok then error(err, 0) end
    return lines
end

local function countMatching(lines, needle)
    local count = 0
    for _, line in ipairs(lines) do
        if line:find(needle, 1, true) then count = count + 1 end
    end
    return count
end

---What crossing a save file or a thread boundary does to a state: the
---receiver gets a copy, never the sender's own tables.
local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = deepCopy(v) end
    return copy
end

local tests = {}

-- Shaped like the regulation table in the real gtnh kab sidecar.
local function savedState()
    return {
        regulation = {
            [107136] = {enabled = true, stop = 2, station = 244946, waiting = {}},
        },
    }
end

local function isRegulated(saved, line)
    return type(saved) == "table" and type(saved.regulation) == "table"
        and type(saved.regulation[line]) == "table" and saved.regulation[line].enabled == true
end

---Make building a fresh state raise, the way any bug inside save() would.
local function breakStateBuilding(regulator)
    regulator.getState = function() error("state building exploded") end
end

---Make the guard hand back xpcall's `true` instead of fn's result: exactly
---what the game's one-argument table.unpack did to the unpack-based guard
---that was running when the 15:09 autosave was written.
local function makeGuardReturnTrue(guard)
    local realCall = guard.call
    guard.call = function(label, fn, ...)
        if label ~= "save" then return realCall(label, fn, ...) end
        realCall(label, fn, ...)
        return true
    end
end

-- THE BUG. The first save() of a session fails after a good load(): the game
-- must get the loaded state back, not the `{ }` the fallback started life as.
tests[#tests + 1] = function()
    local script, regulator = freshScript()
    script.load(savedState(), false)
    breakStateBuilding(regulator)

    local saved
    local lines = captureLines(function() saved = script.save() end)

    assert(type(saved) == "table", "save() must return a table, got " .. type(saved))
    assert(next(saved) ~= nil, "save() returned an empty table: the player's config is gone")
    assert(isRegulated(saved, 107136), "the loaded line's config must be what is re-saved")
    assert(countMatching(lines, "previous state was re-saved") == 1,
        "exactly one line must say the previous state was re-saved, got "
        .. table.concat(lines, " | "))
    assert(countMatching(lines, "timetables_plus: save:") == #lines,
        "every line carries the mod's prefix: " .. table.concat(lines, " | "))
end

-- The 15:09 incident exactly: nothing raised, the guard just handed back
-- `true`. save() must never pass a non-table on to the game.
tests[#tests + 1] = function()
    local script, _, guard = freshScript()
    script.load(savedState(), false)
    makeGuardReturnTrue(guard)

    local saved
    local lines = captureLines(function() saved = script.save() end)

    assert(type(saved) == "table", "save() returned a " .. type(saved) .. " to the game")
    assert(isRegulated(saved, 107136), "the loaded line's config must be what is re-saved")
    assert(countMatching(lines, "previous state was re-saved") == 1, table.concat(lines, " | "))
end

-- A save() that keeps failing (it runs several times a second) must not
-- flood stdout.txt, and must keep returning the good state every time.
tests[#tests + 1] = function()
    local script, regulator = freshScript()
    script.load(savedState(), false)
    breakStateBuilding(regulator)

    local lines = captureLines(function()
        for _ = 1, 50 do
            assert(isRegulated(script.save(), 107136), "every failed save re-saves the good state")
        end
    end)
    assert(countMatching(lines, "previous state was re-saved") == 1,
        "one line for 50 identical failures, got " .. tostring(#lines))
end

-- load(true): what the poisoned 15:09 autosave hands back. It must not wipe
-- state this session already holds, and it must say so once.
tests[#tests + 1] = function()
    local script, regulator = freshScript()
    script.load(savedState(), false)

    local lines = captureLines(function()
        script.load(true, false)
        script.load(true, false)
    end)

    assert(regulator.isEnabled(107136), "load(true) wiped the regulation config")
    assert(isRegulated(script.save(), 107136), "load(true) wiped what save() returns")
    assert(#lines == 1, "one line for a repeated bad load, got " .. tostring(#lines))
    assert(lines[1]:find("timetables_plus: load:", 1, true), lines[1])
    assert(lines[1]:find("boolean", 1, true), "the line names what was passed: " .. lines[1])
end

-- load(true) as the very first load (the poisoned autosave being loaded) must
-- leave the script able to adopt a real state afterwards, and must not seed
-- the save fallback with anything.
tests[#tests + 1] = function()
    local script, regulator = freshScript()
    captureLines(function() script.load(true, false) end)

    script.load(savedState(), false)
    assert(regulator.isEnabled(107136), "a real state after load(true) must still be adopted")

    breakStateBuilding(regulator)
    local saved
    captureLines(function() saved = script.save() end)
    assert(isRegulated(saved, 107136), "the fallback must be the real state, not `true`")
end

-- nil, an empty table and reset are the game's ordinary ways of saying
-- "nothing to adopt" (Urban Games' guidesystem.lua treats them so): ignored
-- quietly, no wipe. An empty table in particular must not be adopted as the
-- session's state, or the real state arriving next would be taken for a
-- repeat call and only its `waiting` fields copied.
tests[#tests + 1] = function()
    local script, regulator = freshScript()

    local lines = captureLines(function()
        script.load(nil, false)
        script.load({}, false)
        script.load(savedState(), true)
    end)
    assert(#lines == 0, "nothing-to-adopt is not an error: " .. table.concat(lines, " | "))
    assert(not regulator.isEnabled(107136), "a reset load must not be adopted")

    script.load(savedState(), false)
    assert(regulator.isEnabled(107136), "the first real state must be adopted in full")

    script.load(nil, false)
    script.load({}, false)
    assert(regulator.isEnabled(107136), "nil or {} must not wipe the state already held")
end

-- A successful save() refreshes the fallback: a config change made after the
-- load, and saved once, is what a later failed save() re-saves.
tests[#tests + 1] = function()
    local script, regulator = freshScript()
    script.load(savedState(), false)

    script.handleEvent(nil, EVENT_ID, "", {
        [107136] = {enabled = true, stop = 2, station = 244946},
        [555] = {enabled = true, stop = 1, station = 9001},
    })
    assert(isRegulated(script.save(), 555), "sanity: the successful save carries the new line")

    breakStateBuilding(regulator)
    local saved
    local lines = captureLines(function() saved = script.save() end)

    assert(isRegulated(saved, 555), "the fallback is older than the last successful save")
    assert(isRegulated(saved, 107136), "the fallback lost the line that was loaded")
    assert(countMatching(lines, "previous state was re-saved") == 1, table.concat(lines, " | "))
end

-- Brand-new game: nothing loaded, nothing built, and the first save() fails.
-- There is no good state to fall back on, so the game gets the same default
-- state update() starts every new game with - a table load() accepts.
tests[#tests + 1] = function()
    local script, regulator = freshScript()
    breakStateBuilding(regulator)

    local saved
    local lines = captureLines(function() saved = script.save() end)

    assert(type(saved) == "table", "save() must return a table, got " .. type(saved))
    assert(type(saved.regulation) == "table" and next(saved.regulation) == nil,
        "the default state is {regulation = { }}")
    assert(countMatching(lines, "previous state was re-saved") == 0,
        "nothing was re-saved, so the log must not claim it")
    assert(countMatching(lines, "no earlier state") == 1, table.concat(lines, " | "))

    -- ...and that default is safe to hand to load(), in a fresh state or in
    -- one that already holds a config.
    local nextSession, nextRegulator = freshScript()
    local loadLines = captureLines(function() nextSession.load(deepCopy(saved), false) end)
    assert(#loadLines == 0, "load() must accept the default: " .. table.concat(loadLines, " | "))
    assert(next(nextRegulator.getState()) == nil, "the default regulates nothing")

    local holder, holderRegulator = freshScript()
    holder.load(savedState(), false)
    holder.load(deepCopy(saved), false)
    assert(holderRegulator.isEnabled(107136), "the default must not wipe a held config")
end

-- New game, nothing loaded, and EVERY save() of the session fails (what the
-- unpack bug did). The player still configures lines; that live state is a
-- real state, and it is what must be saved - not the empty default.
tests[#tests + 1] = function()
    local script, _, guard = freshScript()
    makeGuardReturnTrue(guard)
    captureLines(function() script.save() end)

    script.handleEvent(nil, EVENT_ID, "", {[555] = {enabled = true, stop = 1, station = 9001}})

    local saved
    captureLines(function() saved = script.save() end)
    assert(type(saved) == "table", "save() returned a " .. type(saved) .. " to the game")
    assert(isRegulated(saved, 555), "a config made this session was dropped for the default")
end

-- TWO LUA STATES. The engine and the GUI each run their own copy; state
-- crosses only as a copy, engine save() -> GUI load(). Which thread the game
-- calls save() on is not proven, so the GUI copy's fallback has to be right
-- too: it must carry the newest engine-owned data the GUI has been given,
-- never the snapshot from its first load().
tests[#tests + 1] = function()
    local engine = freshScript()
    local gui, guiRegulator = freshScript()

    engine.load(savedState(), false)
    gui.load(deepCopy(engine.save()), false)

    -- The engine moves on: it is now holding vehicle 77 on that line.
    local newer = deepCopy(engine.save())
    newer.regulation[107136].waiting = {[77] = {departureTime = 500}}
    gui.load(deepCopy(newer), false)

    -- A junk value in between must not cost the GUI what it holds.
    captureLines(function() gui.load(true, false) end)
    assert(guiRegulator.isEnabled(107136), "load(true) wiped the GUI's copy")

    breakStateBuilding(guiRegulator)
    local saved
    captureLines(function() saved = gui.save() end)

    assert(isRegulated(saved, 107136), "the GUI copy's fallback lost the config")
    local waiting = saved.regulation[107136].waiting
    assert(type(waiting) == "table" and waiting[77] and waiting[77].departureTime == 500,
        "the GUI copy re-saved a stale snapshot over newer engine state")
end

-- TESTS GO ABOVE THIS LINE

return {
    test = function()
        for k, v in pairs(tests) do
            print("Running save fallback test: " .. tostring(k))
            v()
        end
    end
}
