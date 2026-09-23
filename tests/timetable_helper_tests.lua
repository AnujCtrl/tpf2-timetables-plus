local fakeApi = require "tests.fake_api"
fakeApi.install()

local timetableHelper = require ".res.scripts.celmi.timetables.timetable_helper"
local regulator = require ".res.scripts.celmi.timetables.regulator"

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

-- The probe compares raw magnitudes, so it needs game time unscaled.
-- getTime() divides by 1000, which is the very convention under question.
tests[#tests + 1] = function()
    fakeApi.install()
    fakeApi.setComponent("world", "GAME_TIME", {gameTime = 3600123})

    assert(timetableHelper.getRawGameTime() == 3600123,
        "raw game time must not be scaled")
    assert(timetableHelper.getTime() == 3600,
        "getTime still returns seconds")
end

-- pruneDeletedLines needs the raw line ids. getAllLines() wraps each in a
-- {id, name} table, which is more work than the prune needs.
tests[#tests + 1] = function()
    fakeApi.install()
    fakeApi.setLine(11, {})
    fakeApi.setLine(22, {})

    local ids = timetableHelper.getAllLineIds()

    assert(type(ids) == "table", "returns a table")
    local seen = {}
    for _, id in pairs(ids) do seen[id] = true end
    assert(seen[11] and seen[22], "carries every line id")
end

--[[
getFrequency reaches game.interface.getEntity, which raises a C++ side error
for ids the legacy interface will not accept. TpF2 writes a ~2.4 MB minidump
AT THROW TIME, before Lua unwinds, so catching the error does not help: the
dump is already on disk. Observed 2026-09-21: 129 dumps, 322 MB, one roughly
every 2.7 seconds, which pushed the machine into swap.

So the rule is: never hand the legacy interface an id we have not validated
against the engine's own view first.
--]]

-- An id that is not an entity at all must never reach getEntity.
tests[#tests + 1] = function()
    fakeApi.install()

    assert(timetableHelper.getFrequency(999) == -2,
        "an unknown id reports no frequency")
    assert(fakeApi.legacyEntityCalls == 0,
        "and the legacy interface is never called with it")
end

-- An entity that exists but is not a line must never reach getEntity either.
tests[#tests + 1] = function()
    fakeApi.install()
    fakeApi.setComponent(500, "NAME", {name = "a station, not a line"})

    assert(timetableHelper.getFrequency(500) == -2, "a non-line reports no frequency")
    assert(fakeApi.legacyEntityCalls == 0, "and never reaches the legacy interface")
end

-- A real line still works.
tests[#tests + 1] = function()
    fakeApi.install()
    fakeApi.setComponent(107136, "LINE", {stops = {}})
    fakeApi.setLegacyEntity(107136, {frequency = 1 / 207})

    local frequency = timetableHelper.getFrequency(107136)

    assert(math.abs(frequency - 207) < 0.001,
        "frequency is the reciprocal of what the engine reports, got " .. tostring(frequency))
    assert(fakeApi.legacyEntityCalls == 1, "reached the legacy interface exactly once")
end

-- If it throws anyway, that line is never tried again. One dump, not one per
-- second forever.
tests[#tests + 1] = function()
    fakeApi.install()
    fakeApi.setComponent(4242, "LINE", {stops = {}})
    fakeApi.makeLegacyEntityThrow(4242)

    assert(timetableHelper.getFrequency(4242) == -2, "a throwing line reports no frequency")
    assert(fakeApi.legacyEntityCalls == 1, "it was attempted once")

    assert(timetableHelper.getFrequency(4242) == -2, "still no frequency")
    assert(fakeApi.legacyEntityCalls == 1,
        "and it is NOT attempted again - this is what stops the dump storm")
end


-- Headway is derived by the caller from these two pieces, so the helper stays
-- a thin wrapper and the arithmetic stays testable in regulator.headwayFrom.
tests[#tests + 1] = function()
    fakeApi.install()
    fakeApi.setLine(42, {1, 2})
    fakeApi.setComponent(1, "TRANSPORT_VEHICLE", {sectionTimes = {60, 60, 60}})

    assert(timetableHelper.getLineVehicleCount(42) == 2, "two vehicles on the line")

    local legs = timetableHelper.getLegTimes(42)
    assert(regulator.headwayFrom(legs, timetableHelper.getLineVehicleCount(42)) == 90,
        "180s lap over 2 vehicles is a 90s headway")
end

tests[#tests + 1] = function()
    fakeApi.install()
    fakeApi.setLine(43, {})

    assert(timetableHelper.getLineVehicleCount(43) == 0, "no vehicles")
    assert(timetableHelper.getLineVehicleCount(9999) == 0, "unknown line")
    assert(timetableHelper.getLineVehicleCount(nil) == 0, "nil line")
end

-- getTime indexed .gameTime on getComponent's result before checking it, and
-- getComponent is documented to return nil when the component is absent. So
-- the `else return 0` below it was dead code, and the real failure was a throw
-- on the engine thread.
--
-- It must also never return 0 as a "failed" clock: decide() compares
-- now >= departAt, and 0 is never >= anything, so a 0 clock holds every
-- vehicle forever.
tests[#tests + 1] = function()
    fakeApi.install()   -- deliberately no GAME_TIME component

    local ok, result = pcall(timetableHelper.getTime)

    assert(ok, "must not throw when the clock component is missing: " .. tostring(result))
    assert(result == nil,
        "an unreadable clock is nil, not 0 - 0 would strand every vehicle, got " .. tostring(result))
end

tests[#tests + 1] = function()
    fakeApi.install()
    fakeApi.setComponent("world", "GAME_TIME", {gameTime = 219889600})

    assert(timetableHelper.getTime() == 219889, "milliseconds to whole seconds")
end
return {
    test = function()
        for k, v in pairs(tests) do
            print("Running helper test: " .. tostring(k))
            v()
        end
    end
}
