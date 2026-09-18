local probe = require ".res.scripts.celmi.timetables.probe"

local tests = {}

-- The probe runs on the engine thread at 5 Hz. It must log a bounded number
-- of lines or it will flood stdout.txt.
tests[#tests + 1] = function()
    probe.reset(3)
    assert(probe.shouldLog(1, 1) == true,  "first sighting logs")
    assert(probe.shouldLog(2, 1) == true,  "a different vehicle logs")
    assert(probe.shouldLog(3, 1) == true,  "third logs, budget now spent")
    assert(probe.shouldLog(4, 1) == false, "budget exhausted, stop logging")
end

-- A vehicle sits at a terminal for many ticks. One line per arrival, not per
-- tick, or the budget is gone in under a second.
tests[#tests + 1] = function()
    probe.reset(10)
    assert(probe.shouldLog(1, 2) == true,  "arrival at stop 2 logs")
    assert(probe.shouldLog(1, 2) == false, "same vehicle still at stop 2 stays quiet")
    assert(probe.shouldLog(1, 2) == false, "and keeps staying quiet")
    assert(probe.shouldLog(1, 3) == true,  "moving on to stop 3 logs again")
    assert(probe.shouldLog(1, 2) == true,  "returning to stop 2 next lap logs again")
end

-- The whole point is comparing magnitudes, so raw values must survive
-- unscaled and nil-safe.
tests[#tests + 1] = function()
    local line = probe.format({
        vehicle = 42, line = 107136, stop = 2,
        gameTime = 3600000, doorsTime = 3599000000, lineStopDeparture = nil,
        minWaitingTime = 0, maxWaitingTime = 180,
    })
    assert(line:find("vehicle=42", 1, true), "names the vehicle")
    assert(line:find("gameTime=3600000", 1, true), "raw gameTime, unscaled")
    assert(line:find("doorsTime=3599000000", 1, true), "raw doorsTime, unscaled")
    assert(line:find("lineStopDeparture=nil", 1, true), "missing values say nil, not crash")
    assert(line:find("maxWaitingTime=180", 1, true), "carries the game's own max wait")
end

return {
    test = function()
        for k, v in pairs(tests) do
            print("Running probe test: " .. tostring(k))
            v()
        end
    end
}
