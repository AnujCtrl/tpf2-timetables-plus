--[[
The game embeds Lua 5.2.2 (confirmed from the TransportFever2 binary's
$LuaVersion banner). The host test runner is whatever lua is installed, which
is typically newer. That gap is dangerous: 5.3+ syntax and library calls parse
and pass on the host, then fail in the game.

This lint pins the shipped code to what 5.2 actually provides. It scans only
the files install.sh ships, not the tests.
--]]

-- Discover the shipped files rather than listing them. A hardcoded list goes
-- stale the moment a module is added, which is exactly how probe.lua slipped
-- past this lint once already.
--
-- This mirrors install.sh's payload: mod.lua, strings.lua and everything
-- under res/.
local function shippedFiles()
    local found = {}
    local pipe = assert(io.popen("find res -name '*.lua' -type f 2>/dev/null"))
    for path in pipe:lines() do
        found[#found + 1] = path
    end
    pipe:close()
    found[#found + 1] = "mod.lua"
    found[#found + 1] = "strings.lua"
    table.sort(found)
    return found
end

local shipped = shippedFiles()

-- pattern, what it is, which Lua version introduced it
local banned = {
    {"//",                "integer division",        "5.3"},
    {"<<",                "bitwise left shift",      "5.3"},
    {">>",                "bitwise right shift",     "5.3"},
    {"math%.type",        "math.type",               "5.3"},
    {"math%.tointeger",   "math.tointeger",          "5.3"},
    {"math%.ult",         "math.ult",                "5.3"},
    {"table%.move",       "table.move",              "5.3"},
    {"string%.pack",      "string.pack",             "5.3"},
    {"string%.unpack",    "string.unpack",           "5.3"},
    {"<const>",           "const attribute",         "5.4"},
    {"<close>",           "to-be-closed attribute",  "5.4"},
}

-- Strip a trailing line comment so that "https://..." in a comment does not
-- read as integer division. Crude but right for this codebase.
local function stripComment(line)
    local commentStart = line:find("%-%-")
    if commentStart then return line:sub(1, commentStart - 1) end
    return line
end

local tests = {}

tests[#tests + 1] = function()
    local violations = {}

    for _, path in ipairs(shipped) do
        local file = io.open(path, "r")
        assert(file, "shipped file missing from the repo: " .. path)

        local lineNumber = 0
        for line in file:lines() do
            lineNumber = lineNumber + 1
            local code = stripComment(line)
            for _, rule in ipairs(banned) do
                local pattern, what, since = rule[1], rule[2], rule[3]
                if code:find(pattern) then
                    violations[#violations + 1] = string.format(
                        "%s:%d uses %s (Lua %s+); the game runs 5.2.2",
                        path, lineNumber, what, since)
                end
            end
        end
        file:close()
    end


    -- Discovery must actually find something, or this lint silently passes.
    -- Guards against discovery silently returning nothing, not against the
    -- file count changing. mod.lua, strings.lua, the game_script and at least
    -- one module always exist.
    assert(#shipped >= 4, "discovery found no shipped lua files (got " .. #shipped .. ")")
    assert(#violations == 0,
        "Lua 5.2 compatibility violations:\n  " .. table.concat(violations, "\n  "))
end

-- string.gsub returns TWO values: the string and the number of replacements. Passed straight to
-- tonumber, the count becomes the `base` argument, and a count of 0 or 1 raises "bad argument #2 to
-- 'tonumber' (base out of range)". In an unguarded GUI callback that takes the game down, which is
-- what timetable_gui.lua's guiHandleEvent did on 2026-09-19 every time an entity window opened.
-- Wrap the call in parentheses to drop the count, or capture the digits with string.match.
tests[#tests + 1] = function()
    local violations = {}
    for _, path in ipairs(shipped) do
        local file = assert(io.open(path, "r"), "shipped file missing from the repo: " .. path)
        local lineNumber = 0
        for line in file:lines() do
            lineNumber = lineNumber + 1
            local code = stripComment(line)
            -- tonumber( immediately followed by an expression ending in :gsub(...) with no
            -- parenthesis of its own around it
            if code:find("tonumber%(%s*[%w_%.%[%]\"']+:gsub%(") then
                violations[#violations + 1] = string.format(
                    "%s:%d passes gsub's two results to tonumber; the count becomes the base", path, lineNumber)
            end
        end
        file:close()
    end
    assert(#violations == 0, "tonumber(x:gsub(...)) found:\n  " .. table.concat(violations, "\n  "))
end

-- A Lua error escaping a game-script entry point (handleEvent, save, load,
-- update, guiUpdate, guiHandleEvent, guiInit) or a widget handler
-- (checkbox:onClick and friends) crashes the whole game; guard.call/
-- guard.wrap are the only thing standing between a raise and that crash. See
-- docs/CRASH_AUDIT_2026-09-19.md and celmi/timetables/guard.lua.
local GUI_FILE = "res/config/game_script/timetable_gui.lua"
local ENTRY_POINTS = {
    "handleEvent", "save", "load", "update", "guiUpdate", "guiHandleEvent", "guiInit",
}

-- Entry points and handler registrations in this codebase wrap their body
-- starting on the very next line or two; this is generous headroom, not a
-- loophole.
local GUARD_LOOKAHEAD = 5

local function isGuardedNear(lines, fromLine)
    for i = fromLine, math.min(fromLine + GUARD_LOOKAHEAD, #lines) do
        local code = stripComment(lines[i] or "")
        if code:find("guard%.call%(") or code:find("guard%.wrap%(") then
            return true
        end
    end
    return false
end

---Scan already-split, 1-indexed lines for entry points and widget handler
---registrations that never reach guard.call/guard.wrap. Returns a list of
---violation strings; empty means everything is covered.
local function findUnguardedCallbacks(lines)
    local violations = {}

    for lineNumber, line in ipairs(lines) do
        local code = stripComment(line)

        for _, name in ipairs(ENTRY_POINTS) do
            if code:find("^%s*" .. name .. "%s*=%s*function") then
                if not isGuardedNear(lines, lineNumber) then
                    violations[#violations + 1] = string.format(
                        "line %d: entry point %s is not wrapped in guard.call", lineNumber, name)
                end
            end
        end

        -- Widget handler registrations, e.g. checkbox:onClick(...).
        if code:find(":on%u%w*%(") then
            if not isGuardedNear(lines, lineNumber) then
                violations[#violations + 1] = string.format(
                    "line %d: widget handler registration is not wrapped in guard.wrap", lineNumber)
            end
        end
    end

    return violations
end

local function readLines(path)
    local file = assert(io.open(path, "r"), "shipped file missing from the repo: " .. path)
    local lines = {}
    for line in file:lines() do lines[#lines + 1] = line end
    file:close()
    return lines
end

tests[#tests + 1] = function()
    local violations = findUnguardedCallbacks(readLines(GUI_FILE))
    assert(#violations == 0,
        "unguarded game-script callback(s):\n  " .. table.concat(violations, "\n  "))
end

-- Prove the scan actually catches something, not just that today's shipped
-- file happens to be clean already: feed it a small sample with one
-- unguarded entry point, one unguarded onClick, and one properly guarded
-- entry point, and check it reports exactly the two bad ones.
tests[#tests + 1] = function()
    -- Deliberately spaced further apart than GUARD_LOOKAHEAD, so the
    -- guarded save() in the middle cannot accidentally cover the unguarded
    -- handleEvent above or the unguarded onClick below.
    local sample = {
        "function data()",
        "    return {",
        "        handleEvent = function(_, id)",
        "            doSomethingUnguarded(id)",
        "        end,",
        "", "", "", "", "", "",
        "        save = function()",
        "            return guard.call(\"save\", function() return state end)",
        "        end,",
        "", "", "", "", "", "",
        "    }",
        "end",
        "",
        "checkbox:onClick(function()",
        "    configChanged = true",
        "end)",
    }

    local violations = findUnguardedCallbacks(sample)
    local foundHandleEvent, foundOnClick = false, false
    for _, v in ipairs(violations) do
        if v:find("handleEvent") then foundHandleEvent = true end
        if v:find("widget handler") then foundOnClick = true end
    end
    assert(foundHandleEvent, "the checker should flag the unguarded handleEvent")
    assert(foundOnClick, "the checker should flag the unguarded onClick")
    assert(#violations == 2, "save is guarded and must not be flagged, got " .. #violations)
end

return {
    test = function()
        for k, v in pairs(tests) do
            print("Running lint test: " .. tostring(k))
            v()
        end
    end
}
