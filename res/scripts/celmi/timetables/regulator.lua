--[[
Interval regulation.

One job: keep a line's vehicles evenly spaced. A line has a single regulation
stop; a vehicle arriving there is held until the line's headway has elapsed
since the previous vehicle departed that same stop.

    regulation[line] = {
        enabled = true,   -- GUI-owned
        stop    = 1,      -- GUI-owned, which stop regulates
        headway = 207,    -- engine-owned, cached from the game's frequency
        waiting = { },    -- engine-owned, vehicle -> planned departure time
    }

Replaces the four per-stop condition modes. See
docs/superpowers/specs/2026-09-19-interval-regulator-design.md.
--]]

local regulator = { }


---Which stop index currently regulates this line.
---
---The regulation point is stored as a station group id, not as a position in
---the stop list, because inserting a station before it shifts every later
---index and would silently move regulation to a different station. Falls back
---to the first stop when the station is gone, so a deleted station degrades
---to "regulate somewhere" rather than to "regulate nowhere, quietly".
---@param stations table|nil stop index -> station group id
---@param entry table|nil the line's regulation entry
---@return number stop index
function regulator.resolveStop(stations, entry)
    if type(stations) ~= "table" or type(entry) ~= "table" then return 1 end

    if entry.station then
        for stopNr, stationGroup in pairs(stations) do
            if stationGroup == entry.station then return stopNr end
        end
    end

    -- Older entries, and anything migrated from a save with no station id.
    if entry.stop and stations[entry.stop] then return entry.stop end

    return 1
end
-- The old condition types that were doing interval regulation by another name.
local UNBUNCHING_TYPES = {
    debounce = true,
    auto_debounce = true,
}

---Convert state saved by the Arr/Dep-era mod.
---
---A line that was unbunching becomes a regulated line, regulating at the stop
---that was doing the unbunching. A line using only Arr/Dep has nothing to
---convert, so it is known but not regulated - silently starting to hold its
---vehicles would be a surprise.
---
---Line ids are normalised to numbers: savegames store them as strings.
---@param old table|nil state in the pre-regulator format
---@return table regulation state
function regulator.migrate(old)
    local migrated = { }
    if type(old) ~= "table" then return migrated end

    for rawLineID, oldLine in pairs(old) do
        local lineID = tonumber(rawLineID)
        if lineID and type(oldLine) == "table" then
            local regulationStop = nil

            -- Lowest stop index wins, and pairs() has no order, so scan for
            -- the minimum rather than taking the first one seen.
            for stopNr, stopInfo in pairs(oldLine.stations or {}) do
                local conditions = type(stopInfo) == "table" and stopInfo.conditions
                local conditionType = type(conditions) == "table" and conditions.type
                if UNBUNCHING_TYPES[conditionType] then
                    if regulationStop == nil or stopNr < regulationStop then
                        regulationStop = stopNr
                    end
                end
            end

            local enabled = (oldLine.hasTimetable == true) and (regulationStop ~= nil)

            local regulationStation = nil
            if regulationStop then
                local stopInfo = (oldLine.stations or { })[regulationStop]
                regulationStation = type(stopInfo) == "table" and stopInfo.stationID or nil
            end

            migrated[lineID] = {
                enabled = enabled,
                stop = regulationStop or 1,
                station = regulationStation,
                waiting = { },
            }
        end
    end

    return migrated
end


-- Slack as a fraction of headway, bounded. The floor keeps very frequent
-- lines usable; the ceiling stops very infrequent lines being given minutes
-- of slack, which would stop being regulation.
local MARGIN_FRACTION = 0.1
local MARGIN_MIN = 10
local MARGIN_MAX = 60

---Slack allowed against a headway. Derived, never configured: the user should
---not have to know what a margin is.
---@param headway number seconds
---@return number seconds
function regulator.marginFor(headway)
    local margin = headway * MARGIN_FRACTION
    if margin < MARGIN_MIN then return MARGIN_MIN end
    if margin > MARGIN_MAX then return MARGIN_MAX end
    return margin
end

---When this vehicle should leave, ignoring the stop's own limits.
---
---Every case where regulation is impossible releases the vehicle. Holding a
---vehicle because we do not know something would strand it at a platform.
---@param lastDeparture number|nil when the previous vehicle left this stop
---@param headway number|nil target spacing, seconds
---@param arrivalTime number when this vehicle arrived
---@return number planned departure time
function regulator.plannedDeparture(lastDeparture, headway, arrivalTime)
    if not lastDeparture then return arrivalTime end
    if not headway or headway <= 0 then return arrivalTime end

    local earliest = lastDeparture + headway - regulator.marginFor(headway)
    if earliest < arrivalTime then return arrivalTime end

    return earliest
end

---Apply the stop's own waiting limits to a planned departure.
---
---The game enforces these regardless, so a plan that ignores them is a plan
---the game will cancel. Respecting them here is what stops the mod and the
---game fighting over the same vehicle.
---@param arrivalTime number
---@param plannedDeparture number
---@param minWait number|nil the stop's minWaitingTime
---@param maxWait number|nil the stop's maxWaitingTime
---@return number departure time the game will also agree with
function regulator.clampToStop(arrivalTime, plannedDeparture, minWait, maxWait)
    local wait = plannedDeparture - arrivalTime

    if minWait and wait < minWait then wait = minWait end
    if maxWait and wait > maxWait then wait = maxWait end

    return arrivalTime + wait
end

---How high this stop's maxWaitingTime would have to be for the plan to hold,
---or nil if the current ceiling already allows it.
---@param arrivalTime number
---@param plannedDeparture number
---@param maxWait number|nil current ceiling
---@return number|nil required ceiling in seconds
function regulator.requiredMaxWait(arrivalTime, plannedDeparture, maxWait)
    local wait = plannedDeparture - arrivalTime
    if maxWait and wait > maxWait then return wait end
    return nil
end

---Decide what to do with a vehicle sitting at the regulation stop.
---
---The whole engine-side decision, kept pure so that the glue inside the
---game_script stays thin enough not to need a test it cannot have.
---@param now number current game time, seconds
---@param arrivalTime number when this vehicle's doors opened, seconds
---@param lastDeparture number|nil when the previous vehicle left this stop
---@param headway number|nil target spacing, seconds
---@param minWait number|nil the stop's own minimum waiting time
---@param maxWait number|nil the stop's own maximum waiting time
---@return string action "hold" or "depart"
---@return number departAt the time it should leave
function regulator.decide(now, arrivalTime, lastDeparture, headway, minWait, maxWait)
    local planned = regulator.plannedDeparture(lastDeparture, headway, arrivalTime)
    local departAt = regulator.clampToStop(arrivalTime, planned, minWait, maxWait)

    if now >= departAt then return "depart", departAt end
    return "hold", departAt
end


---The vehicles currently being held, excluding one.
---
---A vehicle must never space itself against its own planned departure: doing
---so pushes its own deadline out by a headway on every tick, and it never
---leaves the platform.
---@param waiting table|nil vehicle -> {departureTime = number}
---@param vehicle number the one to leave out
---@return table
function regulator.otherWaiting(waiting, vehicle)
    local others = { }
    if type(waiting) ~= "table" then return others end

    for heldVehicle, entry in pairs(waiting) do
        if heldVehicle ~= vehicle then others[heldVehicle] = entry end
    end

    return others
end
-------------------------------------------------------------
---------------------- State --------------------------------
-------------------------------------------------------------

local regulationState = { }

function regulator.getState()
    return regulationState
end

function regulator.setState(newState)
    if type(newState) == "table" then regulationState = newState end
end

local function lineEntry(line)
    if not regulationState[line] then
        regulationState[line] = {enabled = false, stop = 1, waiting = { }}
    end
    return regulationState[line]
end

---@param line number
---@return boolean
function regulator.isEnabled(line)
    local entry = regulationState[line]
    return (entry ~= nil) and (entry.enabled == true)
end

---@param line number
---@param enabled boolean
function regulator.setEnabled(line, enabled)
    lineEntry(line).enabled = (enabled == true)
end

---Which stop regulates this line. Stop 1 unless moved.
---@param line number
---@return number
function regulator.getStop(line)
    local entry = regulationState[line]
    if entry and entry.stop then return entry.stop end
    return 1
end

---@param line number
---@param stop number
function regulator.setStop(line, stop)
    lineEntry(line).stop = stop
end

---Remember which station regulates this line, by id rather than position.
---@param line number
---@param stationGroup number|nil
function regulator.setStation(line, stationGroup)
    lineEntry(line).station = stationGroup
end

-------------------------------------------------------------
------------------- Per-field ownership ----------------------
-------------------------------------------------------------
-- GUI owns    enabled, stop, station
-- engine owns waiting (planned departures of vehicles it is holding)
--
-- Carried over from the state-sync rework; see docs/AUDIT.md S2-1. Each
-- direction copies only what the caller owns, so neither can discard the
-- other's concurrent work.

---@param into table the GUI's copy
---@param from table the engine's snapshot
function regulator.adoptEngineState(into, from)
    if type(into) ~= "table" or type(from) ~= "table" then return end

    for line, fromLine in pairs(from) do
        local intoLine = into[line]
        if type(intoLine) == "table" and type(fromLine) == "table" then
            intoLine.waiting = fromLine.waiting
        end
    end
end

---@param into table the engine's copy
---@param from table the GUI's blob
function regulator.adoptGuiConfig(into, from)
    if type(into) ~= "table" or type(from) ~= "table" then return end

    for line, fromLine in pairs(from) do
        local intoLine = into[line]
        if type(intoLine) ~= "table" or type(fromLine) ~= "table" then
            into[line] = fromLine
        else
            intoLine.enabled = fromLine.enabled
            intoLine.stop = fromLine.stop
            intoLine.station = fromLine.station
            -- waiting is the engine's: deliberately not copied.
        end
    end

    for line in pairs(into) do
        if from[line] == nil then into[line] = nil end
    end
end

---Headway computed from the line itself, without the legacy interface.
---
---game.interface.getEntity is the only *published* route to a line's frequency,
---but it rejects some valid line ids - and a rejected line got no headway, so
---the regulator released every vehicle and they bunched. This is the same
---quantity derived from api.engine data, which cannot throw.
---
---@param sectionTimes table|nil per-leg travel times, TransportVehicle.sectionTimes
---@param vehicleCount number|nil vehicles running the line
---@return number|nil headway in seconds, nil when it cannot be computed
function regulator.headwayFrom(sectionTimes, vehicleCount)
    if type(sectionTimes) ~= "table" then return nil end
    if type(vehicleCount) ~= "number" or vehicleCount <= 0 then return nil end

    local lapTime = 0
    for _, sectionTime in pairs(sectionTimes) do
        -- The game hands these over as floats; skip anything that is not one
        -- rather than letting it throw on the engine thread.
        if type(sectionTime) == "number" then lapTime = lapTime + sectionTime end
    end

    if lapTime <= 0 then return nil end

    return lapTime / vehicleCount
end
return regulator
