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

            migrated[lineID] = {
                enabled = enabled,
                stop = regulationStop or 1,
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
return regulator
