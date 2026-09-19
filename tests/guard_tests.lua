-- Every game-script and widget callback that raises uncaught crashes the
-- whole game (see docs/CRASH_AUDIT_2026-09-19.md). guard.call/guard.wrap are
-- the one place that boundary is enforced; this exercises the boundary
-- itself, not any particular caller of it.
local guard = require ".res.scripts.celmi.timetables.guard"

local tests = {}

---Run fn, capturing every print() call made during it as a line of text.
---Restores the real print no matter how fn ends.
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

-- A callback that succeeds runs normally, and its return values pass
-- straight through, however many there are.
tests[#tests + 1] = function()
    local a, b = guard.call("test", function(x) return x, x * 2 end, 5)
    assert(a == 5, "first return value should pass through")
    assert(b == 10, "second return value should pass through")
end

-- A callback that raises must not crash the caller: this is the whole point.
-- guard.call catches it and returns nil instead of letting the error escape.
tests[#tests + 1] = function()
    local lines = captureLines(function()
        local result = guard.call("myLabel", function() error("boom") end)
        assert(result == nil, "a failed call returns nil")
    end)
    assert(#lines == 1, "one line logged, got " .. tostring(#lines))
    assert(lines[1]:find("timetables_plus: myLabel:", 1, true), "labels the failure: " .. lines[1])
    assert(lines[1]:find("boom", 1, true), "carries the original message: " .. lines[1])
end

-- Extra arguments after fn are forwarded to it.
tests[#tests + 1] = function()
    local seen
    guard.call("test", function(a, b) seen = {a, b} end, "x", "y")
    assert(seen[1] == "x" and seen[2] == "y", "arguments forwarded to fn")
end

-- guard.wrap is the widget-callback form: a plain function that runs its
-- body under guard.call, for onClick and friends.
tests[#tests + 1] = function()
    local wrapped = guard.wrap("onClick", function() error("click boom") end)
    local lines = captureLines(function()
        local ok = pcall(wrapped)
        assert(ok, "the wrapped function itself must never raise")
    end)
    assert(#lines == 1, "the wrapped failure is logged")
    assert(lines[1]:find("onClick", 1, true), lines[1])
end

-- A callback failing repeatedly (e.g. once per engine tick) must not flood
-- stdout.txt: the identical message logs on the first occurrence and then
-- at most once every 100 repeats.
tests[#tests + 1] = function()
    local lines = captureLines(function()
        for _ = 1, 250 do
            guard.call("flood", function() error("same failure every time") end)
        end
    end)
    assert(#lines == 3, "expected 3 lines (repeat 1, 100, 200), got " .. tostring(#lines))
end

-- The error-reporting path itself must never be able to raise, even if
-- formatting the message would (tostring on the label blowing up here).
tests[#tests + 1] = function()
    local badLabel = setmetatable({}, {__tostring = function() error("label tostring exploded") end})
    local lines = captureLines(function()
        local ok, result = pcall(guard.call, badLabel, function() error("boom") end)
        assert(ok, "guard.call must not raise even when formatting fails")
        assert(result == nil, "still returns nil on failure")
    end)
    assert(#lines == 1, "still logs something, got " .. tostring(#lines))
end

-- THE GAME REPLACES table.unpack. Transport Fever 2's own res/scripts/init.lua:86 does
--     local oldunpack = table.unpack
--     table.unpack = function(t) if type(t) == "userdata" then ... else return oldunpack(t) end end
-- which silently DROPS the (i, j) arguments. guard.call used to return
-- table.unpack(packed, 2, packed.n), so IN THE GAME it returned xpcall's `true`
-- instead of fn's result: save() would have handed the game `true` and every
-- line's regulation config would have been lost on the next load. Results must
-- travel as varargs, never through unpack.
tests[#tests + 1] = function()
    local realUnpack = table.unpack
    table.unpack = function(t) return realUnpack(t) end -- exactly what the game installs
    local state = { regulation = { [107136] = { enabled = true } } }
    local ok, err = pcall(function()
        local saved = guard.call("save", function() return state end)
        assert(saved == state, "guard.call must return fn's value under the game's table.unpack, got "
            .. tostring(saved))
        local a, b, c = guard.call("multi", function() return 1, nil, 3 end)
        assert(a == 1 and b == nil and c == 3, "multiple results with a nil in the middle")
        local wrapped = guard.wrap("click", function(x) return x * 2 end)
        assert(wrapped(21) == 42, "guard.wrap must pass the result through too")
    end)
    table.unpack = realUnpack
    assert(ok, err)
end

return {
    test = function()
        for k, v in pairs(tests) do
            print("Running guard test: " .. tostring(k))
            v()
        end
    end
}
