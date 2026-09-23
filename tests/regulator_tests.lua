local regulator = require ".res.scripts.celmi.timetables.regulator"

local tests = {}

-- Old state shaped exactly like the real gtnh kab save: string line ids, an
-- inboundTime field this fork never modelled, and a stop marked ArrDep whose
-- slot list is empty.
local function realWorldOldState()
    return {
        ["107136"] = {
            hasTimetable = true,
            stations = {
                [1] = {
                    stationID = 276967,
                    inboundTime = 0,
                    conditions = {ArrDep = {}, None = {}, debounce = {0, 0}, type = "ArrDep"},
                },
                [2] = {
                    stationID = 244946,
                    inboundTime = 0,
                    conditions = {auto_debounce = {1, 0}, type = "auto_debounce"},
                },
            },
        },
    }
end

-- A line that was being unbunched should come out regulated, at the stop that
-- was doing the unbunching.
tests[#tests + 1] = function()
    local migrated = regulator.migrate(realWorldOldState())

    local line = migrated[107136]
    assert(line ~= nil, "string line id must be migrated to a number key")
    assert(line.enabled == true, "a line that was unbunching becomes regulated")
    assert(line.stop == 2, "regulates at the stop that was unbunching, got " .. tostring(line.stop))
end

-- Arr/Dep is gone. A line using only Arr/Dep has nothing to regulate against,
-- so it must not silently start holding vehicles.
tests[#tests + 1] = function()
    local migrated = regulator.migrate({
        [5] = {hasTimetable = true, stations = {
            [1] = {conditions = {type = "ArrDep", ArrDep = {{1,0,2,0}}}},
            [2] = {conditions = {type = "None"}},
        }},
    })

    assert(migrated[5] ~= nil, "the line is still known")
    assert(migrated[5].enabled == false, "but regulation is off - there was nothing to convert")
end

-- The first unbunching stop wins when several are configured.
tests[#tests + 1] = function()
    local migrated = regulator.migrate({
        [9] = {hasTimetable = true, stations = {
            [1] = {conditions = {type = "None"}},
            [2] = {conditions = {type = "debounce", debounce = {2, 0}}},
            [3] = {conditions = {type = "auto_debounce", auto_debounce = {1, 0}}},
        }},
    })

    assert(migrated[9].enabled == true, "regulated")
    assert(migrated[9].stop == 2, "the first unbunching stop becomes the regulation point")
end

-- Nothing to migrate must not throw.
tests[#tests + 1] = function()
    assert(type(regulator.migrate(nil)) == "table", "nil migrates to an empty table")
    assert(next(regulator.migrate({})) == nil, "empty migrates to empty")
end

-- A line that is disabled overall should not come back regulated.
tests[#tests + 1] = function()
    local migrated = regulator.migrate({
        [3] = {hasTimetable = false, stations = {
            [1] = {conditions = {type = "auto_debounce", auto_debounce = {1, 0}}},
        }},
    })

    assert(migrated[3].enabled == false,
        "a line with its timetable switched off stays switched off")
end


-- Margin is derived, never configured. It exists so a line that is already
-- running slightly late is not delayed further by being held to a full
-- headway every lap.
tests[#tests + 1] = function()
    local margin = regulator.marginFor(600)
    assert(margin > 0 and margin < 600, "a margin is some slack, not the whole headway")

    -- Proportional in the normal range...
    assert(regulator.marginFor(600) > regulator.marginFor(120),
        "a longer headway gets a longer margin")

    -- ...but bounded at both ends, so a very frequent line still gets usable
    -- slack and a very infrequent one is not given minutes of it.
    assert(regulator.marginFor(20) >= 10, "short headways still get a floor of slack")
    assert(regulator.marginFor(36000) <= 60, "long headways do not get absurd slack")
end

-- The core decision: hold until a headway (less margin) has passed since the
-- previous vehicle left this stop.
tests[#tests + 1] = function()
    local headway = 600
    local margin = regulator.marginFor(headway)

    -- Previous vehicle left at 1000, we arrived at 1100: hold.
    local planned = regulator.plannedDeparture(1000, headway, 1100)
    assert(planned == 1000 + headway - margin,
        "held until a headway less margin after the previous departure")

    -- Previous vehicle left ages ago: nothing to wait for.
    assert(regulator.plannedDeparture(0, headway, 5000) == 5000,
        "an old previous departure does not hold us")
end

-- Cases where regulation is impossible must release, never hold forever.
tests[#tests + 1] = function()
    assert(regulator.plannedDeparture(nil, 600, 1100) == 1100,
        "no previous departure known: depart now")
    assert(regulator.plannedDeparture(1000, nil, 1100) == 1100,
        "no headway known: depart now")
    assert(regulator.plannedDeparture(1000, 0, 1100) == 1100,
        "a zero headway is not a reason to hold")
    assert(regulator.plannedDeparture(1000, -5, 1100) == 1100,
        "nor is a nonsense one")
end

-- The game's own per-stop limits win. Planning a hold the game will cancel at
-- maxWaitingTime is how the old mod and the game ended up fighting.
tests[#tests + 1] = function()
    -- Wants to wait 300s, stop allows 180s.
    assert(regulator.clampToStop(1000, 1300, 0, 180) == 1180,
        "a hold longer than the stop's maximum is cut to the maximum")

    -- Wants to leave immediately, stop demands 30s.
    assert(regulator.clampToStop(1000, 1000, 30, 180) == 1030,
        "the stop's minimum is honoured")

    -- No limits configured: plan stands.
    assert(regulator.clampToStop(1000, 1300, nil, nil) == 1300,
        "with no limits the plan is unchanged")
end

-- To regulate properly the stop's ceiling may need raising. Report how high,
-- so the caller can decide whether to write it back to the line.
tests[#tests + 1] = function()
    assert(regulator.requiredMaxWait(1000, 1300, 180) == 300,
        "needs a 300s ceiling to hold for 300s")
    assert(regulator.requiredMaxWait(1000, 1100, 180) == nil,
        "a hold inside the existing ceiling needs no change")
end

-- The whole engine-side decision in one pure function, so the glue in the
-- game_script stays thin enough not to need a test it cannot have.
tests[#tests + 1] = function()
    local headway = 600
    local margin = regulator.marginFor(headway)
    local plannedGap = headway - margin   -- 540

    -- Arrived at 1100, previous vehicle left at 1000, now is 1100.
    -- Planned departure is 1540, so hold.
    local action, departAt = regulator.decide(1100, 1100, 1000, headway, nil, nil)
    assert(action == "hold", "too soon after the previous vehicle: hold")
    assert(departAt == 1000 + plannedGap, "and this is when it may leave")

    -- Same vehicle, later: now past the planned time.
    action = regulator.decide(1600, 1100, 1000, headway, nil, nil)
    assert(action == "depart", "past the planned departure: go")
end

-- The stop's ceiling wins, and the decision reflects that rather than
-- planning a hold the game will cancel.
tests[#tests + 1] = function()
    -- Wants to hold 540s; the stop allows 180s.
    local action, departAt = regulator.decide(1290, 1100, 1000, 600, 0, 180)
    assert(action == "depart", "the stop's ceiling releases the vehicle")
    assert(departAt == 1100 + 180, "cut to the stop's maximum wait")
end

-- Releasing is right in all of these, but the REASON differs and the mod must
-- be able to tell them apart. Conflating them is what made the bunching bug
-- invisible: a line whose headway could not be read looked exactly like a line
-- with nothing to wait for.
tests[#tests + 1] = function()
    assert(regulator.decide(1100, 1100, nil, 600, nil, nil) == "depart",
        "no previous departure is nothing to wait for - a normal release")

    assert(regulator.decide(1100, 1100, 1000, nil, nil, nil) == "unregulated",
        "no headway is an inability, and must be reported as one")
    assert(regulator.decide(1100, 1100, 1000, 0, nil, nil) == "unregulated",
        "zero headway likewise")
end

-- The stop's minimum is honoured even when regulation wants an early release.
tests[#tests + 1] = function()
    local action, departAt = regulator.decide(1105, 1100, nil, 600, 30, 180)
    assert(action == "hold", "the stop's own minimum still holds the vehicle")
    assert(departAt == 1130, "until the minimum has elapsed")
end

-- Config accessors. Defaults must be safe for a line nobody has configured:
-- not regulated, and regulating at stop 1 if it ever is.
tests[#tests + 1] = function()
    regulator.setState({})

    assert(regulator.isEnabled(42) == false, "an unknown line is not regulated")
    assert(regulator.getStop(42) == 1, "and would regulate at stop 1")

    regulator.setEnabled(42, true)
    assert(regulator.isEnabled(42) == true, "enabling sticks")
    assert(regulator.getStop(42) == 1, "still stop 1 by default")

    regulator.setStop(42, 3)
    assert(regulator.getStop(42) == 3, "the regulation stop can be moved")

    regulator.setEnabled(42, false)
    assert(regulator.isEnabled(42) == false, "disabling sticks")
    assert(regulator.getStop(42) == 3, "and does not forget which stop")

    regulator.setStation(42, 9876)
    assert(regulator.getState()[42].station == 9876,
        "the regulating station is remembered by id, not by position")
end

-- Per-field ownership, carried over from the state-sync rework. The field
-- lists are smaller now: the GUI owns enabled and stop, the engine owns the
-- planned departures of vehicles it is currently holding.
tests[#tests + 1] = function()
    local guiCopy = {
        [1] = {enabled = true, stop = 2, waiting = {["9"] = 100}},
    }
    local engineSnapshot = {
        [1] = {enabled = false, stop = 99, waiting = {["7"] = 500}},
    }

    regulator.adoptEngineState(guiCopy, engineSnapshot)

    assert(guiCopy[1].enabled == true, "GUI keeps its own enabled")
    assert(guiCopy[1].stop == 2, "GUI keeps its own regulation stop")
    assert(guiCopy[1].waiting["7"] == 500, "GUI takes the engine's held vehicles")
    assert(guiCopy[1].waiting["9"] == nil, "and drops its stale copy")
end

tests[#tests + 1] = function()
    local engineCopy = {
        [1] = {enabled = false, stop = 99, waiting = {["7"] = 500}},
    }
    local guiBlob = {
        [1] = {enabled = true, stop = 2, station = 4242, waiting = {}},
    }

    regulator.adoptGuiConfig(engineCopy, guiBlob)

    assert(engineCopy[1].enabled == true, "engine takes the GUI's enabled")
    assert(engineCopy[1].stop == 2, "engine takes the GUI's regulation stop")
    assert(engineCopy[1].station == 4242,
        "engine takes the GUI's regulating station - without this the engine\n         never learns where to regulate")
    assert(engineCopy[1].waiting["7"] == 500,
        "engine keeps the vehicles it is holding - this is the lost update")
end

-- A line the player deleted must not linger.
tests[#tests + 1] = function()
    local engineCopy = {[1] = {enabled = true, stop = 1}, [2] = {enabled = true, stop = 1}}

    regulator.adoptGuiConfig(engineCopy, {[1] = {enabled = true, stop = 1}})

    assert(engineCopy[2] == nil, "a line removed in the GUI is removed on the engine")
end

-- A held vehicle must not space itself against its own planned departure.
-- If it did, every tick would push its own deadline further out by a headway
-- and it would never leave the platform.
tests[#tests + 1] = function()
    local waiting = {
        [11] = {departureTime = 500},
        [22] = {departureTime = 700},
    }

    local others = regulator.otherWaiting(waiting, 11)

    assert(others[11] == nil, "the vehicle being decided is excluded")
    assert(others[22] ~= nil, "other held vehicles still count")
    assert(others[22].departureTime == 700, "with their planned times intact")

    -- The original is untouched; this is a read path.
    assert(waiting[11] ~= nil, "the caller's table is not mutated")
end

tests[#tests + 1] = function()
    assert(next(regulator.otherWaiting({}, 1)) == nil, "nothing waiting is nothing")
    assert(next(regulator.otherWaiting(nil, 1)) == nil, "nil is nothing")
end

-- The regulation point is stored as a station, not a position in the list.
-- Inserting a station before it shifts every later index, which would move
-- regulation to a different station without anyone touching it.
tests[#tests + 1] = function()
    local stations = {[1] = 500, [2] = 600, [3] = 700}

    assert(regulator.resolveStop(stations, {station = 600}) == 2,
        "the station is found at its current position")

    -- A station is inserted at the front; our station is now third.
    local afterInsert = {[1] = 400, [2] = 500, [3] = 600, [4] = 700}
    assert(regulator.resolveStop(afterInsert, {station = 600}) == 3,
        "regulation follows the station, not the index")
end

-- If the regulating station is removed from the line, fall back to the first
-- stop rather than pointing at nothing and silently not regulating.
tests[#tests + 1] = function()
    local stations = {[1] = 500, [2] = 700}

    assert(regulator.resolveStop(stations, {station = 600}) == 1,
        "a deleted regulation station falls back to stop 1")
end

-- Older entries may carry only an index. Use it when it still points at a
-- stop, and fall back when it does not.
tests[#tests + 1] = function()
    local stations = {[1] = 500, [2] = 600}

    assert(regulator.resolveStop(stations, {stop = 2}) == 2,
        "an index-only entry still works")
    assert(regulator.resolveStop(stations, {stop = 9}) == 1,
        "an index past the end falls back to stop 1")
    assert(regulator.resolveStop(stations, {}) == 1, "nothing configured is stop 1")
    assert(regulator.resolveStop({}, {station = 600}) == 1, "no stations at all is stop 1")
end

-- Migration must carry the station across, not just its position.
tests[#tests + 1] = function()
    local migrated = regulator.migrate({
        [77] = {hasTimetable = true, stations = {
            [1] = {stationID = 111, conditions = {type = "None"}},
            [2] = {stationID = 222, conditions = {type = "auto_debounce", auto_debounce = {1, 0}}},
        }},
    })

    assert(migrated[77].station == 222,
        "the station that was unbunching is remembered by id, got " .. tostring(migrated[77].station))
end

--[[
The legacy game.interface.getEntity is the only published route to a line's
frequency, and it rejects some perfectly valid line ids - 264322 in the real
game, while 107136 works. A rejected line got no headway, so the regulator
released every vehicle and the trains bunched, which is the bug this fixes.

Headway is computable from api.engine alone: lap time over vehicle count.
--]]
tests[#tests + 1] = function()
    -- Three legs of 60s, two vehicles: one passes any point every 90s.
    assert(regulator.headwayFrom({60, 60, 60}, 2) == 90,
        "lap time over vehicle count")

    assert(regulator.headwayFrom({60, 60, 60}, 1) == 180,
        "a single vehicle's headway is the whole lap")
end

-- Every unusable input must yield nil, so the caller releases the vehicle
-- rather than holding it against a nonsense target.
tests[#tests + 1] = function()
    assert(regulator.headwayFrom(nil, 2) == nil, "no section times")
    assert(regulator.headwayFrom({}, 2) == nil, "empty section times")
    assert(regulator.headwayFrom({60, 60}, 0) == nil, "no vehicles on the line")
    assert(regulator.headwayFrom({60, 60}, nil) == nil, "unknown vehicle count")
    assert(regulator.headwayFrom({0, 0}, 2) == nil, "a zero lap time is not a headway")
end

-- Section times arrive as floats from the game and may carry junk entries.
tests[#tests + 1] = function()
    assert(regulator.headwayFrom({30.5, 29.5}, 1) == 60, "floats sum correctly")
    assert(regulator.headwayFrom({60, "x", 60}, 1) == 120,
        "a non-numeric entry is skipped rather than throwing")
end

--[[
Regression evals built from real values observed in game on 2026-09-23,
line 264322, the line that bunched:

  probe: vehicle=174827 line=264322 stop=1 gameTime=219889600
         doorsTime=219888800000 lineStopDeparture=219753
         minWaitingTime=0 maxWaitingTime=180

  now          = floor(219889600 / 1000)      = 219889   (ms)
  arrivalTime  = floor(219888800000 / 1000000)= 219888   (us)
  lastDeparture                                = 219753
--]]
local REAL = {
    now = 219889,
    arrivalTime = 219888,
    lastDeparture = 219753,
    minWait = 0,
    maxWait = 180,
}

-- With a headway, this vehicle must be held: only 135s had passed since the
-- previous departure from that stop.
tests[#tests + 1] = function()
    local action, departAt = regulator.decide(
        REAL.now, REAL.arrivalTime, REAL.lastDeparture, 207, REAL.minWait, REAL.maxWait)

    assert(action == "hold",
        "135s after the last departure with a 207s headway must hold, got " .. tostring(action))
    assert(departAt > REAL.now, "and the departure must be in the future")
end

-- The bug as it actually happened: no headway, so it departed immediately and
-- the line bunched. Releasing is right - holding against an unknown target
-- would strand the vehicle - but it must be DISTINGUISHABLE from a normal
-- release, or the failure is invisible. It was invisible for a whole session.
tests[#tests + 1] = function()
    local action = regulator.decide(
        REAL.now, REAL.arrivalTime, REAL.lastDeparture, nil, REAL.minWait, REAL.maxWait)

    assert(action == "unregulated",
        "no headway is an inability to regulate, not a decision to depart; got "
        .. tostring(action))
end

-- Same for a nonsense headway.
tests[#tests + 1] = function()
    assert(regulator.decide(REAL.now, REAL.arrivalTime, REAL.lastDeparture, 0,
        REAL.minWait, REAL.maxWait) == "unregulated", "a zero headway cannot regulate")
    assert(regulator.decide(REAL.now, REAL.arrivalTime, REAL.lastDeparture, -5,
        REAL.minWait, REAL.maxWait) == "unregulated", "nor can a negative one")
end

-- Nothing has departed this stop yet. That is a legitimate "nothing to wait
-- for", NOT an inability - so it is a normal depart, not unregulated.
tests[#tests + 1] = function()
    local action = regulator.decide(REAL.now, REAL.arrivalTime, nil, 207,
        REAL.minWait, REAL.maxWait)

    assert(action == "depart",
        "no previous departure is nothing to wait for, not a failure; got " .. tostring(action))
end

-- A vehicle must never be held because the clock is unreadable. getTime
-- returns 0 in that case, and 0 >= departAt is false, so the old decide held
-- the vehicle forever - stranded at the platform.
tests[#tests + 1] = function()
    local action = regulator.decide(0, REAL.arrivalTime, REAL.lastDeparture, 207,
        REAL.minWait, REAL.maxWait)

    assert(action ~= "hold",
        "an unreadable clock must never strand a vehicle, got " .. tostring(action))
end
return {
    test = function()
        for k, v in pairs(tests) do
            print("Running regulator test: " .. tostring(k))
            v()
        end
    end
}
