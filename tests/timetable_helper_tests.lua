local fakeApi = require "tests.fake_api"
fakeApi.install()

local timetableHelper = require ".res.scripts.celmi.timetables.timetable_helper"

local tests = {}

-- S2-5: a vehicle that has not yet departed this stop has no entry in
-- lineStopDepartures. Dividing that nil by 1000 crashed the engine thread.
tests[#tests + 1] = function()
    fakeApi.install()
    fakeApi.setComponent(1, "TRANSPORT_VEHICLE", {lineStopDepartures = {}})

    local previous = timetableHelper.getPreviousDepartureTime(1, {1}, {})

    assert(previous == nil, "an unknown previous departure should be nil, not a crash")
end

-- A vehicle with no recorded departure must be skipped, not poison the result.
tests[#tests + 1] = function()
    fakeApi.install()
    fakeApi.setComponent(1, "TRANSPORT_VEHICLE", {lineStopDepartures = {}})
    fakeApi.setComponent(2, "TRANSPORT_VEHICLE", {lineStopDepartures = {[1] = 60000}})

    local previous = timetableHelper.getPreviousDepartureTime(1, {1, 2}, {})

    assert(previous == 60, "should use the known departure and ignore the unknown one")
end

-- Vehicles already waiting contribute their planned departure time.
tests[#tests + 1] = function()
    fakeApi.install()
    fakeApi.setComponent(1, "TRANSPORT_VEHICLE", {lineStopDepartures = {[1] = 60000}})

    local previous = timetableHelper.getPreviousDepartureTime(1, {1}, {[2] = {departureTime = 90}})

    assert(previous == 90, "a waiting vehicle's departure time should win when it is later")
end

-- maximumArray must survive an empty array rather than returning nil into
-- caller arithmetic.
tests[#tests + 1] = function()
    assert(timetableHelper.maximumArray({}) == nil, "max of nothing is nil")
    assert(timetableHelper.maximumArray({3, 9, 4}) == 9, "max of {3,9,4} is 9")
end


-- S2-6: helpers documented as returning an array must return an array on the
-- error path too. getAllStations returned the string "ERROR", and its caller
-- in timetable_gui.lua does pairs() on the result, which throws on a string.
tests[#tests + 1] = function()
    fakeApi.install()

    local stations = timetableHelper.getAllStations({})
    assert(type(stations) == "table", "getAllStations must return a table on the error path")
    for _ in pairs(stations) do end  -- must not throw

    local legTimes = timetableHelper.getLegTimes({})
    assert(type(legTimes) == "table", "getLegTimes must return a table on the error path")
    for _ in pairs(legTimes) do end  -- must not throw
end

-- S2-6: helpers documented as returning Bool must not return -1, which is
-- truthy in Lua and so reads as "yes" at every call site.
tests[#tests + 1] = function()
    fakeApi.install()

    assert(timetableHelper.lineHasType({}, "RAIL") == false,
        "lineHasType must return false, not a truthy -1, on the error path")
end

-- S4-2: conditionToString renders a label. It must not write default values
-- back into the condition table, which is persisted state.
tests[#tests + 1] = function()
    fakeApi.install()

    local cond = {}
    timetableHelper.conditionToString(cond, 1, "debounce")
    assert(cond[1] == nil and cond[2] == nil,
        "rendering a debounce label must not mutate the condition")

    local autoCond = {}
    timetableHelper.conditionToString(autoCond, 1, "auto_debounce")
    assert(autoCond[1] == nil and autoCond[2] == nil,
        "rendering an auto_debounce label must not mutate the condition")
end
return {
    test = function()
        for k, v in pairs(tests) do
            print("Running helper test: " .. tostring(k))
            v()
        end
    end
}
