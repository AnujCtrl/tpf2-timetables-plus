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
return {
    test = function()
        for k, v in pairs(tests) do
            print("Running regulator test: " .. tostring(k))
            v()
        end
    end
}
