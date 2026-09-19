--[[
Drives the timetable coroutine from the engine's update() callback.

Extracted from the game_script so it can be tested. The version it replaces
looped `for _ = 0, 20` - which is 21 iterations, not 20 - and kept calling
resume after the coroutine had died, printing a complaint each time. A
persistent failure therefore produced roughly twenty log lines per tick, at
5 Hz, for as long as it stayed broken.
--]]

local driver = { }

---Resume a coroutine up to `steps` times, stopping early if it finishes or
---fails. Reports a failure once rather than once per step.
---@param co thread
---@param steps number maximum resumes this call
---@return number resumed how many times it was actually resumed
---@return string|nil err the error message, if it failed
function driver.pump(co, steps)
    local resumed = 0

    for _ = 1, steps do
        if coroutine.status(co) ~= "suspended" then break end

        local ok, msg = coroutine.resume(co)
        resumed = resumed + 1
        if not ok then return resumed, msg end
    end

    return resumed, nil
end

return driver
