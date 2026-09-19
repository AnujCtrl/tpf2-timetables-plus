local driver = require ".res.scripts.celmi.timetables.driver"

local tests = {}

-- The engine calls update() at 5 Hz and the work is a coroutine that yields
-- between lines. Pump it a bounded number of steps per call.
tests[#tests + 1] = function()
    local resumes = 0
    local co = coroutine.create(function()
        while true do
            resumes = resumes + 1
            coroutine.yield()
        end
    end)

    local steps, err = driver.pump(co, 20)

    assert(steps == 20, "should resume exactly 20 times, got " .. tostring(steps))
    assert(resumes == 20, "the coroutine should have run 20 times, ran " .. tostring(resumes))
    assert(err == nil, "no error expected")
end

-- A coroutine that finishes must not be resumed again. The old loop kept
-- resuming a dead coroutine and printed a complaint every iteration, roughly
-- 20 log lines per tick for as long as it stayed broken.
tests[#tests + 1] = function()
    local co = coroutine.create(function()
        coroutine.yield()
    end)

    local steps, err = driver.pump(co, 20)

    assert(steps == 2, "one yield then completion is two resumes, got " .. tostring(steps))
    assert(coroutine.status(co) == "dead", "the coroutine finished")
    assert(err == nil, "finishing normally is not an error")

    -- Pumping a dead coroutine is a no-op, not 20 failed resumes.
    local again = driver.pump(co, 20)
    assert(again == 0, "a dead coroutine is not resumed, got " .. tostring(again))
end

-- An error must be reported once and stop the pump, not repeat per step.
tests[#tests + 1] = function()
    local co = coroutine.create(function()
        error("boom")
    end)

    local steps, err = driver.pump(co, 20)

    assert(steps == 1, "stop at the first failure, got " .. tostring(steps))
    assert(err ~= nil, "the error is returned")
    assert(tostring(err):find("boom", 1, true), "and carries the message")
end

return {
    test = function()
        for k, v in pairs(tests) do
            print("Running driver test: " .. tostring(k))
            v()
        end
    end
}
