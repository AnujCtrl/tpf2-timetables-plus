--[[
Every game-script and widget callback (handleEvent, save, load, update,
guiUpdate, guiHandleEvent, onClick, ...) crashes the whole game if a Lua
error escapes it; the same error caught by pcall/xpcall is only logged. This
module is the one place that boundary is enforced, so every entry point runs
through it instead of each guarding itself. See docs/CRASH_AUDIT_2026-09-19.md.
--]]

local guard = { }

-- Formatted message -> how many times reportError has been asked to log it.
-- Keyed by the fully formatted line, so the same failure repeating (a
-- callback raising the same way every tick) is throttled instead of
-- flooding stdout.txt, while a genuinely different failure still gets its
-- own line.
local counts = { }

---Log a guarded failure, throttled: the first occurrence of a message prints,
---then only every 100th repeat after that. Must not be able to raise itself -
---a callback that is already failing is the worst place for a second,
---unhandled error, and formatting (tostring on a hostile label or error
---object) is not guaranteed to be safe.
---@param label string
---@param traceback string
local function reportError(label, traceback)
    local ok, message = pcall(function()
        return "timetables_plus: " .. tostring(label) .. ": " .. tostring(traceback)
    end)
    if not ok then
        -- tostring(label) or tostring(traceback) itself raised (a hostile
        -- __tostring). Do not touch either value again.
        message = "timetables_plus: (error while formatting a guard failure)"
    end

    local count = (counts[message] or 0) + 1
    counts[message] = count

    if count == 1 or count % 100 == 0 then
        pcall(print, message)
    end
end

---Run fn(...) under xpcall so a Lua error inside it cannot escape into the
---game. On success, returns whatever fn returned (however many values). On
---failure, logs it (throttled) and returns nil.
---@param label string identifies the callback in the log
---@param fn function
---@return any ... fn's return values, or nil if it raised
---Hands xpcall's results on as varargs: everything after the status on
---success, nil after reporting on failure.
local function finish(label, ok, ...)
    if ok then return ... end
    reportError(label, (...))
    return nil
end

-- NO unpack IN HERE. Transport Fever 2's own res/scripts/init.lua:86 replaces
-- table.unpack with a one-argument version that drops (i, j), so
-- table.unpack(packed, 2, packed.n) returned xpcall's `true` instead of fn's
-- result - in the game only, never on the host. Results travel as varargs.
function guard.call(label, fn, ...)
    return finish(label, xpcall(fn, debug.traceback, ...))
end

---Wrap fn so every call runs under guard.call. For widget callbacks (a
---checkbox's onClick and friends), which the game cannot tolerate raising
---any more than it can a game-script entry point.
---@param label string
---@param fn function
---@return function
function guard.wrap(label, fn)
    return function(...)
        return guard.call(label, fn, ...)
    end
end

return guard
