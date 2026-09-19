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

return {
    test = function()
        for k, v in pairs(tests) do
            print("Running lint test: " .. tostring(k))
            v()
        end
    end
}
