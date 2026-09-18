--[[
Temporary diagnostic. Answers two questions that no amount of reading the
game's files could settle, and that both need exactly one in-game run:

RISK 4 — gameTime, doorsTime and lineStopDepartures are all `long long` in one
time base, but this mod divides gameTime and lineStopDepartures by 1000 and
doorsTime by 1000000. Printing all three raw, side by side, shows immediately
which scaling is right. If doorsTime is the same order of magnitude as
gameTime, the /1000000 is wrong by a factor of 1000.

RISK 1 — the game's per-stop maxWaitingTime is documented to force departure
"regardless of the condition", while setVehicleManualDeparture is documented to
hold a vehicle "under any circumstance". Printing the stop's configured min/max
alongside the slot we intend to hold for shows whether the two ever conflict.

Remove this module once both are answered. See docs/API_FACTS.md.
--]]

local probe = { }

local loggedStop = { }   -- vehicle -> the stop index last logged for it
local budget = 20

---Arm the probe with a maximum number of lines it may ever print.
---@param lines number
function probe.reset(lines)
    loggedStop = { }
    budget = lines or 20
end

---Whether to log this vehicle now.
---Runs on the engine thread at 5 Hz and a vehicle sits at a terminal for many
---ticks, so this logs once per arrival, not once per tick, and never more than
---the armed budget in total.
---@param vehicle number
---@param stop number
---@return boolean
function probe.shouldLog(vehicle, stop)
    if budget <= 0 then return false end
    if loggedStop[vehicle] == stop then return false end

    loggedStop[vehicle] = stop
    budget = budget - 1
    return true
end

---Render one line. Values are printed RAW and unscaled - comparing their
---magnitudes is the entire point.
---@param fields table
---@return string
function probe.format(fields)
    local function show(value)
        if value == nil then return "nil" end
        if type(value) == "number" then return string.format("%.0f", value) end
        return tostring(value)
    end

    return table.concat({
        "timetables_plus probe:",
        "vehicle=" .. show(fields.vehicle),
        "line=" .. show(fields.line),
        "stop=" .. show(fields.stop),
        "gameTime=" .. show(fields.gameTime),
        "doorsTime=" .. show(fields.doorsTime),
        "lineStopDeparture=" .. show(fields.lineStopDeparture),
        "minWaitingTime=" .. show(fields.minWaitingTime),
        "maxWaitingTime=" .. show(fields.maxWaitingTime),
    }, " ")
end

return probe
