local mockTimetableHelper = {}
package.loaded["celmi/timetables/timetable_helper"] = mockTimetableHelper

local guard = require ".res.scripts.celmi.timetables.guard"
package.loaded["celmi/timetables/guard"] = guard

local timetable = require ".res.scripts.celmi.timetables.timetable"
package.loaded["celmi/timetables/timetable"] = timetable

local ops = require ".res.scripts.celmi.timetables.ops"

local tests = {}

-- An op names a whitelisted timetable mutation and carries its arguments.
tests[#tests + 1] = function()
    timetable.setTimetableObject({})
    mockTimetableHelper.getStationID = function() return 7 end

    local op = ops.make("setHasTimetable", 1, true)
    assert(op.name == "setHasTimetable", "op carries its name")

    assert(ops.apply(op) == true, "a whitelisted op applies")
    assert(timetable.hasTimetable(1) == true, "the mutation actually happened")
end

-- Arguments must survive intact, including falsy ones, which a naive
-- table.unpack over an array with holes would drop.
tests[#tests + 1] = function()
    timetable.setTimetableObject({})
    mockTimetableHelper.getStationID = function() return 7 end
    timetable.setHasTimetable(1, true)
    timetable.setForceDepartureEnabled(1, true)

    assert(ops.apply(ops.make("setForceDepartureEnabled", 1, false)) == true,
        "an op with a false argument applies")
    assert(timetable.getForceDepartureEnabled(1) == false,
        "the false argument reached the mutator")
end

-- Anything not on the whitelist is refused. The op channel crosses a thread
-- boundary, so it must not be a way to call arbitrary module functions.
tests[#tests + 1] = function()
    assert(ops.apply(ops.make("getTimetableObject")) == false,
        "a non-whitelisted timetable function is refused")
    assert(ops.apply(ops.make("nosuchfunction", 1)) == false,
        "an unknown name is refused")
    assert(ops.apply(nil) == false, "a nil op is refused")
    assert(ops.apply({}) == false, "an op with no name is refused")
end

return {
    test = function()
        for k, v in pairs(tests) do
            print("Running ops test: " .. tostring(k))
            v()
        end
    end
}
