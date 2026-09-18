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

return {
    test = function()
        for k, v in pairs(tests) do
            print("Running helper test: " .. tostring(k))
            v()
        end
    end
}
