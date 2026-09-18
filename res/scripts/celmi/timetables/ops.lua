local timetable = require "celmi/timetables/timetable"

--[[
An "op" is a single timetable mutation, named and with its arguments captured,
so it can be sent across the engine/GUI thread boundary instead of shipping the
whole timetable object.

    {name = "updateArrDep", args = {1, 2, 1, 3, 45, n = 5}}

Only the names below may cross that boundary. The channel carries data from
another Lua state, so it must not be able to call arbitrary module functions.
--]]

local ops = { }

local allowed = {
    setHasTimetable = true,
    setForceDepartureEnabled = true,
    setMinWaitEnabled = true,
    setMaxWaitEnabled = true,
    setConditionType = true,
    addCondition = true,
    removeAllConditions = true,
    removeCondition = true,
    updateArrDep = true,
    updateDebounce = true,
    insertArrDepCondition = true,
}

-- table.unpack in 5.2+, plain unpack in 5.1. The game runs Lua 5.2.2 but the
-- host test runner may be a different version, so bind whichever exists.
local unpackArgs = table.unpack or unpack

---Capture a mutation and its arguments as a sendable op.
---select("#", ...) is used rather than # so that trailing nil and false
---arguments survive the round trip.
---@param name string one of the allowed mutation names
---@return table op
function ops.make(name, ...)
    local args = {...}
    args.n = select("#", ...)
    return {name = name, args = args}
end

---Apply an op to the local timetable object.
---@param op table|nil
---@return boolean applied true if the op was recognised and applied
function ops.apply(op)
    if type(op) ~= "table" then return false end
    if type(op.name) ~= "string" then return false end
    if not allowed[op.name] then return false end

    local mutate = timetable[op.name]
    if type(mutate) ~= "function" then return false end

    local args = op.args or {n = 0}
    mutate(unpackArgs(args, 1, args.n or #args))
    return true
end

---Whether a name is allowed to cross the thread boundary. Exposed for tests.
---@param name string
---@return boolean
function ops.isAllowed(name)
    return allowed[name] == true
end

return ops
