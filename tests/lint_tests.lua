--[[
The game embeds Lua 5.2.2 (confirmed from the TransportFever2 binary's
$LuaVersion banner). The host test runner is whatever lua is installed, which
is typically newer. That gap is dangerous: 5.3+ syntax and library calls parse
and pass on the host, then fail in the game.

This lint pins the shipped code to what 5.2 actually provides. It scans only
the files install.sh ships, not the tests.
--]]

local shipped = {
    "res/config/game_script/timetable_gui.lua",
    "res/config/style_sheet/timetable_colors.lua",
    "res/config/style_sheet/timetable_stylesheet.lua",
    "res/scripts/celmi/timetables/guard.lua",
    "res/scripts/celmi/timetables/ops.lua",
    "res/scripts/celmi/timetables/timetable.lua",
    "res/scripts/celmi/timetables/timetable_helper.lua",
    "mod.lua",
    "strings.lua",
}

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

    assert(#violations == 0,
        "Lua 5.2 compatibility violations:\n  " .. table.concat(violations, "\n  "))
end

return {
    test = function()
        for k, v in pairs(tests) do
            print("Running lint test: " .. tostring(k))
            v()
        end
    end
}
