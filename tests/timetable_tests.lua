local mockTimetableHelper = {} -- Use mock timetable helper
package.loaded["celmi/timetables/timetable_helper"] = mockTimetableHelper

local guard = require ".res.scripts.celmi.timetables.guard" -- Use real guard class
package.loaded["celmi/timetables/guard"] = guard

local timetable = require ".res.scripts.celmi.timetables.timetable"

local timetableTests = {}
local testsHelper = {}

timetableTests[#timetableTests + 1] = function()
    local x = { [1] = 0 }
    timetable.setTimetableObject(x)
    local y = timetable.getTimetableObject()
    assert(x.testfield == y.testfield, "Error while setting and retriving the same object from the timetable")
end

timetableTests[#timetableTests + 1] = function()
    timetable.setTimetableObject({})
    local x = timetable.getTimeDifference(0,0)
    assert(x == 0, "Difference between same time should be 0")
    x = timetable.getTimeDifference(5,5)
    assert(x == 0, "Difference between same time should be 0")
    x = timetable.getTimeDifference(59,60)
    assert(x == 1, "Difference between 2 times should be 1")
    x = timetable.getTimeDifference(60,59)
    assert(x == 1, "Difference between 2 times should be 1")
    x = timetable.getTimeDifference(10,5)
    assert(x == 5, "Difference between 2 times should be 5")
    x = timetable.getTimeDifference(0,5)
    assert(x == 5, "Difference between 2 times should be 5")
    x = timetable.getTimeDifference(3300,300)
    assert(x == 600, "Difference between 2 times should be 600")
    x = timetable.getTimeDifference(600,2400)
    assert(x == 1800, "Difference between 2 times should be 1800")
end

timetableTests[#timetableTests + 1] = function()
    timetable.setTimetableObject({})
    local x = timetable.getNextSlot({{30,0,59,0},{9,0,59,0} },1200, {})
    assert(x[1] == 30 and x[2] == 0 and x[3] == 59 and x[4] == 0, "should choose the closest time constraint")
    x = timetable.getNextSlot({{30,0,59,0},{11,0,59,0} },1200, {})
    assert(x[1] == 11 and x[2] == 0 and x[3] == 59 and x[4] == 0, "should choose the closest time constraint")
    x = timetable.getNextSlot({{51,0,0,0},{50,0,59,0} },1200, {})
    assert(x[1] == 51 and x[2] == 0 and x[3] == 0 and x[4] == 0, "should choose the closest time constraint")
    x = timetable.getNextSlot({{51,0,0,0},{49,1,0,0} },1200, {})
    assert(x[1] == 51 and x[2] == 0 and x[3] == 0 and x[4] == 0, "should choose the closest time constraint")
    x = timetable.getNextSlot({{0,59,1,0},{1,30,1,30} },60, {})
    assert(x[1] == 0 and x[2] == 59 and x[3] == 1 and x[4] == 0, "should choose the closest time constraint")
    x = timetable.getNextSlot({},1200, {})
    assert(x == nil, "should return nil")

    local a = {slot={30,0,59,0}, departureTime=3540}
    x = timetable.getNextSlot({{30,0,59,0},{9,0,59,0} },1200, {a})
    assert(x[1] == 9 and x[2] == 0 and x[3] == 59 and x[4] == 0, "should choose the only available time constraint")
    x = timetable.getNextSlot({{30,0,59,0},{30,0,59,0} },1200, {a})
    assert(x[1] == 30 and x[2] == 0 and x[3] == 59 and x[4] == 0, "should choose the only available time constraint")
    x = timetable.getNextSlot({{30,0,59,0}},1200, {a})
    assert(x[1] == 30 and x[2] == 0 and x[3] == 59 and x[4] == 0, "should still return the constraint")
end

timetableTests[#timetableTests + 1] = function()
    timetable.setTimetableObject({})
    local x = timetable.getWaitTime({29,00,39,00}, 29*60)
    assert(x == 10*60, "wait time should be 10 min instead of ".. x)
    x = timetable.getWaitTime({29,30,30,00}, 29*60 + 30)
    assert(x == 30, "wait time should be 30 sec instead of ".. x)
    x = timetable.getWaitTime({29,30,30,35}, 29*60 + 30)
    assert(x == 65, "wait time should be 65 sec instead of ".. x)
    x = timetable.getWaitTime({30,00,25,00}, 30*60)
    assert(x == 55*60, "wait time should be 55 min instead of ".. x)
    x = timetable.getWaitTime({55,00,01,00}, 55*60)
    assert(x == 6*60, "wait time should be 6 min instead of ".. x)
    x = timetable.getWaitTime({54,00,01,00}, 55*60)
    assert(x == 6*60, "wait time should be 6 min instead of ".. x)
    x = timetable.getWaitTime({01,30,01,00}, 55*60)
    assert(x == 66*60, "wait time should be 66 min instead of ".. x)
    x = timetable.getWaitTime({55,00,54,00}, 01*60)
    assert(x == 53*60, "wait time should be 53 min instead of ".. x)
    x = timetable.getWaitTime({55,00,54,00}, 01*60 + 30)
    assert(x == 52*60 + 30, "wait time should be 52 min instead of ".. x)
end

timetableTests[#timetableTests + 1] = function()
    table.remove(mockTimetableHelper)
    mockTimetableHelper.getLineInfo = function(line)
        assert(line == 1)
        return {stops = {[1] = {
            minWaitingTime = 30,
            maxWaitingTime = 300
        }}}
    end

    timetable.setTimetableObject({[1] = {minWaitEnabled=true, maxWaitEnabled=false}})
    local x = timetable.getDepartureTime(1, 1, 29*60, 10*60)
    assert(x == 39*60, "departure time should be 39:00 instead of ".. x)
    x = timetable.getDepartureTime(1, 1, 29*60 + 30, 15)
    assert(x == 30*60, "departure time should be 30:00 instead of ".. x)
    x = timetable.getDepartureTime(1, 1, 29*60 + 30, 65)
    assert(x == 30*60 + 35, "departure time should be 30:35 instead of ".. x)
    x = timetable.getDepartureTime(1, 1, 30*60, 55*60)
    assert(x == 85*60, "departure time should be 1+ 25:00 instead of ".. x)

    timetable.setTimetableObject({[1] = {minWaitEnabled=false, maxWaitEnabled=true}})
    x = timetable.getDepartureTime(1, 1, 30*60, 55*60)
    assert(x == 35*60, "departure time should be 35:00 instead of ".. x)
    x = timetable.getDepartureTime(1, 1, 55*60, 06*60)
    assert(x == 60*60, "departure time should be 1+ 00:00 instead of ".. x)
    x = timetable.getDepartureTime(1, 1, 29*60 + 45, 15)
    assert(x == 30*60, "departure time should be 30:00 instead of ".. x)
end

testsHelper.setUpMock = function()
    table.remove(mockTimetableHelper)

    mockTimetableHelper.getStationID = function(line, stationNumber)
        assert(line == 1)
        assert(stationNumber == 1)
        return 1
    end
    mockTimetableHelper.getCurrentLine = function(vehicle)
        assert(vehicle == 1 or vehicle == 2)
        return 1
    end
    mockTimetableHelper.getCurrentStation = function(vehicle)
        assert(vehicle == 1 or vehicle == 2)
        return 1
    end
    mockTimetableHelper.getTimeUntilDepartureReady = function(vehicle)
        assert(vehicle == 1 or vehicle == 2)
        return 1
    end
    mockTimetableHelper.getLineInfo = function(line)
        assert(line == 1)
        return {
            stops = {
                {
                    minWaitingTime = 0,
                    maxWaitingTime = -1
                }
            }
        }
    end
end

timetableTests[#timetableTests + 1] = function()
    testsHelper.setUpMock()
    timetable.setTimetableObject({})
    local constraints = {{00,00,40,00}}
    timetable.addCondition(1, 1, {type = "ArrDep", ArrDep = constraints}) 

    local vehicles = {1}
    local vehiclesWaiting = {}

    local time = (20*60) + 0 -- 20:00
    mockTimetableHelper.getTime = function()
        return time
    end
    local arrivalTime = time
    local x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "should be before departure")

    time = (30*60) + 0 -- 30:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "should be before departure")

    time = (40*60) + 0 -- 40:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")

    time = (50*60) + 0 -- 50:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")

    time = 3600 + (00*60) + 0 -- 00:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")

    time = 3600 + (10*60) + 0 -- 10:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")

    time = 3600 + (20*60) + 0 -- 20:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")



    time = 3600 + (50*60) + 0 -- 50:00
    arrivalTime = time
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "should be before departure")

    time = 7200 + (0*60) + 0 -- 00:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "should be before departure")

    time = 7200 + (10*60) + 0 -- 10:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "should be before departure")

    time = 7200 + (20*60) + 0 -- 20:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "should be before departure")

    time = 7200 + (30*60) + 0 -- 30:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "should be before departure")

    time = 7200 + (40*60) + 0 -- 40:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")

    time = 7200 + (50*60) + 0 -- 50:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")
end

timetableTests[#timetableTests + 1] = function()
    testsHelper.setUpMock()
    timetable.setTimetableObject({})
    local constraints = {{00,00,20,00}}
    timetable.addCondition(1, 1, {type = "ArrDep", ArrDep = constraints})

    local vehicles = {1}
    local vehiclesWaiting = {}

    local time = (40*60) + 0 -- 40:00
    mockTimetableHelper.getTime = function()
        return time
    end
    local arrivalTime = time
    local x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "should be before departure")

    time = (50*60) -- 50:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "should be before departure")

    time = 3600 + (00*60) -- 00:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "should be before departure")

    time = 3600 + (10*60) -- 10:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "should be before departure")

    time = 3600 + (20*60) -- 20:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")

    time = 3600 + (30*60) -- 30:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")

    time = 3600 + (40*60) -- 40:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")

    time = 3600 + (50*60) -- 50:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")
end

timetableTests[#timetableTests + 1] = function()
    testsHelper.setUpMock()
    timetable.setTimetableObject({})
    local constraints = {{27,00,28,00}}
    timetable.addCondition(1, 1, {type = "ArrDep", ArrDep = constraints})

    local vehicles = {1}
    local vehiclesWaiting = {}

    local time = (26*60) + 0 -- 26:00
    mockTimetableHelper.getTime = function()
        return time
    end
    local arrivalTime = time
    local x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "should be before departure")

    time = (27*60) -- 27:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "should be before departure")

    time = (28*60) -- 28:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")

    time = (29*60) -- 29:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")


    
    time = 3600 + (27*60) -- 27:00
    arrivalTime = time
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "should be before departure")

    time = 3600 + (28*60) -- 28:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")

    time = 3600 + (29*60) -- 29:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")



    time = 7200 + (28*60) -- 28:00
    arrivalTime = time
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")

    time = 7200 + (29*60) -- 29:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")



    time = 10800 + (29*60) -- 29:00
    arrivalTime = time
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")

    time = 10800 + (30*60) -- 30:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "should be after departure")
end

-- All tests here done with line and station IDs of 1 for simplicity
-- Tests that nearest timetable slot is given, unless already taken.
-- In which case, the next consecutive timetable slot available is given.
timetableTests[#timetableTests + 1] = function()
    testsHelper.setUpMock()
    timetable.setTimetableObject({})
    local constraints = {{55, 0, 58, 0}, {57, 0, 0, 0}, {59, 0, 2, 0}}
    timetable.addCondition(1, 1, {type = "ArrDep", ArrDep = constraints})

    local vehicles = {1, 2}
    local vehiclesWaiting = {}

    local time = (57*60) + 1 -- 57:01
    mockTimetableHelper.getTime = function()
        return time
    end
    local arrivalTime1 = time
    local x = timetable.readyToDepartArrDep(1, arrivalTime1, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    time = (59*60) + 11 -- 59:11
    local arrivalTime2 = time
    x = timetable.readyToDepartArrDep(2, arrivalTime2, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    time = (60*60) + 0 -- 00:00
    x = timetable.readyToDepartArrDep(1, arrivalTime1, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "Shouldn't wait for train")

    time = (60*60) + 1 -- 00:01
    x = timetable.readyToDepartArrDep(1, arrivalTime1, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "Shouldn't wait for train")

    time = (60*60) + 0 -- 00:00
    x = timetable.readyToDepartArrDep(2, arrivalTime2, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    time = (62*60) + 0 -- 02:00
    x = timetable.readyToDepartArrDep(2, arrivalTime2, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "Shouldn't wait for train")

    time = (62*60) + 1 -- 02:01
    x = timetable.readyToDepartArrDep(2, arrivalTime2, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "Shouldn't wait for train")
end

-- Tests for issue #26: Vehicle takes departed vehicles timetable slot
timetableTests[#timetableTests + 1] = function()
    testsHelper.setUpMock()
    timetable.setTimetableObject({})
    local constraints = {{5, 0, 7, 0}, {15, 0, 17, 0}, {25, 0, 27, 0}, {35, 0, 37, 0}, {45, 0, 47, 0}, {55, 0, 57, 0}}
    timetable.addCondition(1, 1, {type = "ArrDep", ArrDep = constraints})

    local vehicles = {1, 2}
    local vehiclesWaiting = {}

    local time = (5*60) + 1 -- 05:01
    mockTimetableHelper.getTime = function()
        return time
    end
    local arrivalTime1 = time
    local x = timetable.readyToDepartArrDep(1, arrivalTime1, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    time = (7*60) + 0 -- 07:00
    x = timetable.readyToDepartArrDep(1, arrivalTime1, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "Shouldn't wait for train")

    time = (8*60) + 11 -- 08:11
    local arrivalTime2 = time
    x = timetable.readyToDepartArrDep(2, arrivalTime2, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    time = (15*60) + 11 -- 15:11
    local arrivalTime2 = time
    x = timetable.readyToDepartArrDep(2, arrivalTime2, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    time = (17*60) -- 17:00
    local arrivalTime2 = time
    x = timetable.readyToDepartArrDep(2, arrivalTime2, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "Shouldn't wait for train")
end

-- Tests for issue #38: Vehicle departs too soon
timetableTests[#timetableTests + 1] = function()
    testsHelper.setUpMock()
    timetable.setTimetableObject({})
    local constraints = {{5, 0, 30, 0}, {35, 0, 0, 0}}
    timetable.addCondition(1, 1, {type = "ArrDep", ArrDep = constraints})

    local vehicles = {1, 2}
    local vehiclesWaiting = {}

    local time = (05*60) -- 05:00
    mockTimetableHelper.getTime = function()
        return time
    end
    local arrivalTime1 = time
    local x = timetable.readyToDepartArrDep(1, arrivalTime1, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    time = (29*60) + 59 -- 29:59
    x = timetable.readyToDepartArrDep(1, arrivalTime1, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    time = (30*60) -- 30:00
    x = timetable.readyToDepartArrDep(1, arrivalTime1, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "Shouldn't wait for train")

    local time = (35*60) + 1 -- 35:01
    local arrivalTime2 = time
    x = timetable.readyToDepartArrDep(2, arrivalTime2, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    time = (59*60) -- 59:00
    x = timetable.readyToDepartArrDep(2, arrivalTime2, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    time = (60*60) + 0 -- 00:00
    x = timetable.readyToDepartArrDep(2, arrivalTime2, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "Shouldn't wait for train")
end

-- Test for issue 55, checking getNextSot with old vehiclesWaiting
timetableTests[#timetableTests + 1] = function()
    local slots = {{30,0,59,0},{9,0,59,0}}
    local arrivalTime = 0
    local vehiclesWaiting = {{30,0,59,0}, {9,0,59,0}}
    
    timetable.getNextSlot(slots, arrivalTime, vehiclesWaiting)
end

-- Tests for issue #58: VehiclesWaiting is nil
timetableTests[#timetableTests + 1] = function()
    timetable.setTimetableObject({})
    local vehiclesWaiting = {
        [1] = {
            departureTime = 3540,
            slot = { 30, 0, 59, 0 },
        },
        [2] = {
            departureTime = 7140,
            slot = { 9, 0, 59, 0 },
        },
    }
    local x = timetable.getNextSlot({{30,0,59,0},{9,0,59,0}}, (9*60 + 60*60), vehiclesWaiting)
    assert(x[1] == 30, "Slot with 30 minute arrival should be chosen")
    -- Reasoning: vehicleWaiting 1 (30:00 arrival) has departed, vehicleWaiting 2 (09:00 arrival) is waiting. 
    -- Vehicle 2 arrives before vehicle 1 departs, so vehicle 1 doesn't get removed from vehiclesWaiting on 2s arrival.
    -- Vehicle 3 arrives at 09:00, but shouldn't take this slot as vehicle 2 is still waiting with it allocated.
    -- Instead vehicle 1 should get removed from vehiclesWaiting, and vehicle 3 can pick this timetable slot up.
end

-- Tests for issue #62 with one vehicle
timetableTests[#timetableTests + 1] = function()
    testsHelper.setUpMock()
    timetable.setTimetableObject({})
    local constraints = {{0, 0, 2, 0}, {4, 0, 6, 0}, {8, 0, 10, 0}}
    timetable.addCondition(1, 1, {type = "ArrDep", ArrDep = constraints})

    local vehicles = {1}
    local vehiclesWaiting = {}

    local time = (00*60) -- 00:00
    mockTimetableHelper.getTime = function()
        return time
    end
    local arrivalTime = time
    local x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    time = (02*60) -- 02:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "Shouldn't wait for train")

    time = (04*60) -- 04:00
    arrivalTime = time
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    time = (06*60) -- 06:00
    x = timetable.readyToDepartArrDep(1, arrivalTime, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "Shouldn't wait for train")
end

-- Tests for issue #62 with two vehicles
timetableTests[#timetableTests+1] = function ()
    testsHelper.setUpMock()
    timetable.setTimetableObject({})
    local constraints = {{ 24, 0, 25, 0, }, { 26, 0, 27, 0, }, { 28, 0, 29, 0, }, { 30, 0, 31, 0, }}
    timetable.addCondition(1, 1, {type = "ArrDep", ArrDep = constraints})

    local arrivalTime1 = (23*60) + 30 -- 23:30
    local arrivalTime2 = (24*60) -- 24:00

    local vehicles = {1, 2}
    local vehiclesWaiting = {
        [1] = {
            arrivalTime = arrivalTime1,
            departureTime = 1500,
            slot = { 24, 0, 25, 0, },
        },
        [2] = {
            arrivalTime = arrivalTime2,
            departureTime = 1620,
            slot = { 26, 0, 27, 0, },
        },
    }

    local time = (24*60) -- 24:00
    local x = timetable.readyToDepartArrDep(1, arrivalTime1, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    x = timetable.readyToDepartArrDep(2, arrivalTime2, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    time = (25*60) -- 25:00
    x = timetable.readyToDepartArrDep(1, arrivalTime1, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "Shouldn't wait for train")

    x = timetable.readyToDepartArrDep(2, arrivalTime2, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    time = (26*60) -- 26:00
    arrivalTime1 = time
    x = timetable.readyToDepartArrDep(1, arrivalTime1, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    x = timetable.readyToDepartArrDep(2, arrivalTime2, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    time = (27*60) -- 27:00
    x = timetable.readyToDepartArrDep(1, arrivalTime1, vehicles, time, 1, 1, vehiclesWaiting)
    assert(not x, "Should wait for train")

    x = timetable.readyToDepartArrDep(2, arrivalTime2, vehicles, time, 1, 1, vehiclesWaiting)
    assert(x, "Shouldn't wait for train")
end

-- S1-1: the force departure toggle must be readable, not permanently false.
-- Regression guard for d72fbc5, which flipped both the condition and the
-- return so every path yielded false.
timetableTests[#timetableTests + 1] = function()
    timetable.setTimetableObject({})
    timetable.setHasTimetable(1, true)

    -- default: off, as d72fbc5 intended
    assert(timetable.getForceDepartureEnabled(1) == false,
        "force departure should default to false")

    timetable.setForceDepartureEnabled(1, true)
    assert(timetable.getForceDepartureEnabled(1) == true,
        "force departure should read back true once enabled")

    timetable.setForceDepartureEnabled(1, false)
    assert(timetable.getForceDepartureEnabled(1) == false,
        "force departure should read back false once disabled")

    -- an unknown line must not report enabled
    assert(timetable.getForceDepartureEnabled(999) == false,
        "force departure should be false for a line with no timetable")
end


-- S2-2: must consider every vehicle at the stop, not just the first one
-- pairs() happens to yield. Vehicle 3 arrived earliest but is listed last.
timetableTests[#timetableTests + 1] = function()
    timetable.setTimetableObject({})
    local info = {
        [1] = {doorsOpen = true, doorsTime = 100 * 1000000},
        [2] = {doorsOpen = true, doorsTime = 200 * 1000000},
        [3] = {doorsOpen = true, doorsTime =  50 * 1000000},
    }
    mockTimetableHelper.getVehiclesAtStop = function(line, stop) return {1, 2, 3} end
    mockTimetableHelper.getVehicleInfo = function(v) return info[v] end

    -- vehicle 1 arrived at 100; vehicle 3 arrived at 50, so someone was earlier
    assert(timetable.anotherVehicleArrivedEarlier(1, 100, 1, 1) == true,
        "should detect an earlier vehicle listed after a later one")

    -- vehicle 3 arrived first, so nobody was earlier than it
    assert(timetable.anotherVehicleArrivedEarlier(3, 50, 1, 1) == false,
        "the earliest vehicle should see nobody ahead of it")
end

-- S2-4: getNextSlot must not reorder the caller's slot list. That list is
-- persisted user configuration; a read path must not rewrite it.
timetableTests[#timetableTests + 1] = function()
    timetable.setTimetableObject({})
    local slots = {{30,0,59,0},{9,0,59,0}}

    timetable.getNextSlot(slots, 1200, {})

    assert(slots[1][1] == 30 and slots[2][1] == 9,
        "getNextSlot must leave the caller's slot order untouched")
end

-- S2-3: a stop configured as ArrDep but holding no slots must fall back to
-- "None". The old guard compared `slots == {}`, which in Lua is always false
-- because tables compare by identity, so the reset never happened.
timetableTests[#timetableTests + 1] = function()
    timetable.setTimetableObject({
        [1] = {
            hasTimetable = true,
            stations = {
                [1] = {stationID = 1, conditions = {type = "ArrDep", ArrDep = {}}}
            }
        }
    })

    local departed = timetable.readyToDepartArrDep(1, 100, {1}, 100, 1, 1, {})

    assert(departed == true, "a stop with no slots should release the vehicle")
    assert(timetable.getConditionType(1, 1) == "None",
        "a stop with no slots should reset its condition type to None")
end

-- S2-5: with no previous departure known, unbunching has no constraint to work
-- from. It must release the vehicle, not do arithmetic on nil.
timetableTests[#timetableTests + 1] = function()
    timetable.setTimetableObject({[1] = {hasTimetable = true, frequency = 600, stations = {}}})
    mockTimetableHelper.getPreviousDepartureTime = function() return nil end
    mockTimetableHelper.getLineInfo = function(line)
        return {stops = {[1] = {minWaitingTime = 0, maxWaitingTime = 0}}}
    end

    local manual = timetable.manualDebounceDepartureTime(100, {1}, 100, 1, 1, {})
    assert(manual == 100, "manual unbunch with no previous departure should depart at arrival")

    local auto = timetable.autoDebounceDepartureTime(100, {1}, 100, 1, 1, {})
    assert(auto == 100, "auto unbunch with no previous departure should depart at arrival")
end

-- S2-5: a line with no known frequency cannot be auto-unbunched. That must
-- release the vehicle, not compare nil with a number.
timetableTests[#timetableTests + 1] = function()
    timetable.setTimetableObject({[1] = {hasTimetable = true, stations = {}}}) -- no frequency
    mockTimetableHelper.getPreviousDepartureTime = function() return 50 end
    mockTimetableHelper.getVehiclesAtStop = function() return {} end
    mockTimetableHelper.getLineInfo = function(line)
        return {stops = {[1] = {minWaitingTime = 0, maxWaitingTime = 0}}}
    end

    local ready = timetable.readyToDepartDebounce(1, 100, {1, 2}, 100, 1, 1, {}, false)

    assert(ready == true, "auto unbunch on a line with no frequency should release the vehicle")
end
return {
    test = function()
        for k,v in pairs(timetableTests) do
            print("Running test: " .. tostring(k))
            v()
        end
    end
}
