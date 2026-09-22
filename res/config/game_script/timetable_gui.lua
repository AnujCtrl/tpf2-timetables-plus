--[[
Timetables Plus — interval regulation.

One job: keep a line's vehicles evenly spaced. A regulated line has a single
regulation stop; a vehicle arriving there is held until the line's headway has
elapsed since the previous vehicle departed that same stop.

FILENAME: this file must keep the name timetable_gui.lua. TpF2 keys a
game_script's saved state by its bare filename, so renaming it orphans every
existing save. The name no longer describes the contents; that is the lesser
evil. See docs/CONTEXT.md.

THREADS: the same file runs in two isolated Lua states. update/save/load/
handleEvent run on the engine; guiUpdate/guiHandleEvent on the GUI. They share
no memory. State crosses via save()->load() (engine to GUI, ~5x/second) and
sendScriptEvent->handleEvent (GUI to engine), with per-field ownership so
neither can discard the other's work. See docs/API_FACTS.md.
--]]

local regulator = require "celmi/timetables/regulator"
local timetableHelper = require "celmi/timetables/timetable_helper"
local driver = require "celmi/timetables/driver"
local probe = require "celmi/timetables/probe"
local guard = require "celmi/timetables/guard"

-- Script events are broadcast to every game script on the machine, so the id
-- must be namespaced. Urban Games namespaces theirs (__taskEvent__).
local EVENT_ID = "__timetables_plus__"

local state = nil
local co = nil
local configChanged = false
-- The last known good state: what load() delivered, then whatever save() last
-- built successfully. The game persists whatever save() returns, verbatim, so
-- a save() that cannot build a fresh state hands back this instead. It starts
-- as nil and never as `{ }`: an empty table is a state too, and persisting it
-- silently replaced the player's whole configuration with nothing.
--
-- Held by reference, and in practice the same table as `state`. That is
-- deliberate. It stays as current as the state itself, in whichever of the two
-- Lua states save() turns out to run in; a snapshot taken at load() would be
-- re-saved over everything done since.
local lastGoodState = nil

---A state worth adopting or re-saving. nil and `{ }` are how the game says
---"nothing was saved" (Urban Games' own guidesystem.lua treats them so); the
---game has also been seen handing load() the boolean true.
local function isUsableState(candidate)
    return type(candidate) == "table" and next(candidate) ~= nil
end

-------------------------------------------------------------
---------------------- Engine -------------------------------
-------------------------------------------------------------

local function stopConfigFor(line, stop)
    local lineInfo = timetableHelper.getLineInfo(line)
    local stops = lineInfo and lineInfo.stops
    return stops and stops[stop] or nil
end

---getFrequency returns -1 and -2 as error codes, which are perfectly good
---numbers and would otherwise be treated as a headway.
local function headwayFor(line)
    local frequency = timetableHelper.getFrequency(line)
    if type(frequency) ~= "number" or frequency <= 0 then return nil end
    return frequency
end

local function releaseVehicle(vehicle, vehicleInfo)
    if not vehicleInfo.autoDeparture then
        timetableHelper.restartAutoVehicleDeparture(vehicle)
    end
end

local function regulateLine(line, vehicles)
    local entry = regulator.getState()[line]

    -- Never configured. Do not touch this line's vehicles at all: walking
    -- every vehicle in the game once a second is the cost that S3-1 was about.
    if entry == nil then return end

    if not entry.enabled then
        -- Regulation was switched off. Release only what we were actually
        -- holding, or unchecking the box would strand a vehicle - then stop
        -- paying anything for this line.
        if entry.waiting and next(entry.waiting) then
            for vehicle in pairs(entry.waiting) do
                local vehicleInfo = timetableHelper.getVehicleInfo(vehicle)
                if vehicleInfo then releaseVehicle(vehicle, vehicleInfo) end
            end
            entry.waiting = { }
        end
        return
    end

    entry.waiting = entry.waiting or { }

    local stations = timetableHelper.getAllStations(line)
    local stop = regulator.resolveStop(stations, entry)
    local headway = headwayFor(line)
    local now = timetableHelper.getTime()
    local stopInfo = stopConfigFor(line, stop)
    local minWait = stopInfo and stopInfo.minWaitingTime
    local maxWait = stopInfo and stopInfo.maxWaitingTime

    for _, vehicle in pairs(vehicles) do
        local vehicleInfo = timetableHelper.getVehicleInfo(vehicle)
        if vehicleInfo then
            local atRegulationStop = timetableHelper.isVehicleAtTerminal(vehicleInfo)
                and (vehicleInfo.stopIndex + 1) == stop

            if atRegulationStop and vehicleInfo.doorsOpen then
                -- doorsTime is microseconds; gameTime and lineStopDepartures
                -- are milliseconds. Verified in game, see docs/API_FACTS.md.
                local arrivalTime = math.floor(vehicleInfo.doorsTime / 1000000)

                -- Exclude this vehicle's own planned departure, or it spaces
                -- against itself and never leaves.
                local others = regulator.otherWaiting(entry.waiting, vehicle)
                local lastDeparture =
                    timetableHelper.getPreviousDepartureTime(stop, vehicles, others)

                local action, departAt = regulator.decide(
                    now, arrivalTime, lastDeparture, headway, minWait, maxWait)

                if probe.shouldLog(vehicle, stop) then
                    print(probe.format({
                        vehicle = vehicle, line = line, stop = stop,
                        gameTime = timetableHelper.getRawGameTime(),
                        doorsTime = vehicleInfo.doorsTime,
                        lineStopDeparture = lastDeparture,
                        minWaitingTime = minWait,
                        maxWaitingTime = maxWait,
                    }))

                    -- If the stop's ceiling is cutting regulation short, say
                    -- so: the hold the line needs is longer than the game will
                    -- allow, and silently under-regulating is how the old mod
                    -- and the game ended up fighting.
                    local planned = regulator.plannedDeparture(lastDeparture, headway, arrivalTime)
                    local needed = regulator.requiredMaxWait(arrivalTime, planned, maxWait)
                    if needed then
                        print(string.format(
                            "timetables_plus: line %s stop %s needs a %ds max wait but has %ds",
                            tostring(line), tostring(stop), needed, maxWait))
                    end
                end

                if action == "hold" then
                    entry.waiting[vehicle] = {departureTime = departAt}
                    if vehicleInfo.autoDeparture then
                        timetableHelper.stopAutoVehicleDeparture(vehicle)
                    end
                else
                    entry.waiting[vehicle] = nil
                    if not vehicleInfo.autoDeparture then
                        timetableHelper.departVehicle(vehicle)
                    end
                end
            else
                entry.waiting[vehicle] = nil
                releaseVehicle(vehicle, vehicleInfo)
            end
        end
    end
end

local function regulationCoroutine()
    local lastRun = -1

    while true do
        -- Once a second is plenty; update() runs at 5 Hz.
        while timetableHelper.getTime() - lastRun < 1 do
            coroutine.yield()
        end
        lastRun = timetableHelper.getTime()

        local lineVehicles = api.engine.system.transportVehicleSystem.getLine2VehicleMap()
        for line, vehicles in pairs(lineVehicles) do
            -- One bad line must not cost every other line its pass.
            guard.call("regulateLine", regulateLine, line, vehicles)
            coroutine.yield()
        end

        coroutine.yield()
    end
end

-------------------------------------------------------------
------------------------- GUI -------------------------------
-------------------------------------------------------------

local function headwayText(line)
    local headway = headwayFor(line)
    if not headway then return "--:--" end
    return string.format("%d:%02d", math.floor(headway / 60), math.floor(headway % 60))
end

local function stopNameFor(line, stop)
    local stations = timetableHelper.getAllStations(line)
    local stationID = stations and stations[stop]
    if not stationID then return "stop " .. tostring(stop) end
    return timetableHelper.getStationName(stationID)
end

local function statusTextFor(line)
    if not regulator.isEnabled(line) then
        return "Vehicles run without interval regulation."
    end
    return string.format("Evening out at %s, every %s.",
        stopNameFor(line, regulator.resolveStop(
            timetableHelper.getAllStations(line), regulator.getState()[line])),
        headwayText(line))
end

---The control appended to the game's own line window.
local function buildRegulatorRow(line)
    local row = api.gui.comp.Table.new(3, 'NONE')

    local checkboxImage = api.gui.comp.ImageView.new("ui/checkbox0.tga")
    if regulator.isEnabled(line) then
        checkboxImage:setImage("ui/checkbox1.tga", false)
    end

    local checkbox = api.gui.comp.Button.new(checkboxImage, true)
    checkbox:setGravity(0, 0.5)

    local label = api.gui.comp.TextView.new("Even out intervals")
    label:setGravity(-1, 0.5)

    local status = api.gui.comp.TextView.new(statusTextFor(line))
    status:setGravity(-1, 0.5)

    checkbox:onClick(guard.wrap("checkbox.onClick", function()
        local nowEnabled = not regulator.isEnabled(line)
        regulator.setEnabled(line, nowEnabled)
        if nowEnabled then
            -- Pin the regulation point to a station id so that inserting a
            -- station before it does not silently move regulation elsewhere.
            local stations = timetableHelper.getAllStations(line)
            local resolved = regulator.resolveStop(stations, regulator.getState()[line])
            regulator.setStation(line, stations and stations[resolved])
        end
        checkboxImage:setImage(nowEnabled and "ui/checkbox1.tga" or "ui/checkbox0.tga", false)
        status:setText(statusTextFor(line))
        -- Drained in guiUpdate: a script event cannot be fired from inside a
        -- GUI element callback (docs/API_FACTS.md). Only set once everything
        -- above has succeeded, or a raise would leave the box flipped with
        -- the engine never told.
        configChanged = true
    end))

    row:addRow({checkbox, label, status})
    return row
end

-------------------------------------------------------------
----------------------- Callbacks ---------------------------
-------------------------------------------------------------

---What save() hands the game when it could not build a fresh state. Runs
---outside the guard, so it must not be able to raise: type checks, a
---throttled log line that cannot raise, and a table constructor.
local function stateToResave()
    local known = lastGoodState
    -- Nothing loaded and no save has succeeded yet, but update()/handleEvent
    -- may already be keeping a live state (a new game the player configured
    -- while every save() failed). That is a real state; do not drop it for
    -- the default.
    if known == nil and isUsableState(state) then known = state end

    if known ~= nil then
        guard.report("save", "could not build a fresh state; the previous state was re-saved")
        return known
    end

    -- Genuinely nothing: a new game whose first save() failed. The default
    -- every new game starts with; load() adopts it as "regulates nothing".
    guard.report("save", "could not build a fresh state and no earlier state is known; "
        .. "an empty state was saved")
    return {regulation = { }}
end

function data()
    return {
        handleEvent = function (_, id, _, param)
            guard.call("handleEvent", function()
                if id == EVENT_ID then
                    if state == nil then state = {regulation = { }} end
                    -- Take the player's configuration, keep our own record of
                    -- which vehicles we are holding. Idempotent: an
                    -- engine-side echo back into this handler is not ruled
                    -- out.
                    regulator.adoptGuiConfig(regulator.getState(), param)
                    state.regulation = regulator.getState()
                end
            end)
        end,

        save = function()
            local fresh = guard.call("save", function()
                state = state or { }
                state.regulation = regulator.getState()
                return state
            end)

            -- The game persists whatever comes back, verbatim, and hands it
            -- to load() next session: nil stores nothing, `true` stored
            -- `true`. So a table, always, and never an emptier one than the
            -- best we know of.
            if isUsableState(fresh) then
                lastGoodState = fresh
                return fresh
            end

            return stateToResave()
        end,

        load = function(loadedState, reset)
            guard.call("load", function()
                -- `reset` means discard, not adopt.
                if reset then return end

                -- Nothing below may run for a value that is not a state:
                -- whatever this session already holds stays exactly as it
                -- is. nil and `{ }` are the ordinary "nothing was saved" and
                -- pass quietly. Anything else is a save that lost its state
                -- (the game stored `true` on 2026-09-19 and handed it back
                -- here), and indexing it below would crash the game.
                if not isUsableState(loadedState) then
                    if loadedState ~= nil and type(loadedState) ~= "table" then
                        guard.report("load", "was given a " .. type(loadedState) .. " ("
                            .. tostring(loadedState) .. "), not a state; ignored, and the "
                            .. "state already held is kept")
                    end
                    return
                end

                if state == nil then
                    state = loadedState
                    -- Seed the save fallback: from here on a failing save()
                    -- re-saves this, never an empty table.
                    lastGoodState = loadedState

                    if loadedState.regulation then
                        regulator.setState(loadedState.regulation)
                    elseif loadedState.timetable then
                        -- Saved by the Arr/Dep-era mod. Convert once.
                        local migrated = regulator.migrate(loadedState.timetable)
                        regulator.setState(migrated)
                        state.regulation = migrated
                        state.timetable = nil
                        print("timetables_plus: migrated timetable state to interval regulation")
                    end
                else
                    -- Repeated call on the GUI thread. Take only what the
                    -- engine owns, or this erases what the player is
                    -- changing.
                    regulator.adoptEngineState(
                        regulator.getState(), loadedState.regulation or { })
                end
            end)
        end,

        update = function()
            guard.call("update", function()
                if state == nil then state = {regulation = { }} end

                if co == nil or coroutine.status(co) == "dead" then
                    co = coroutine.create(regulationCoroutine)
                end

                -- The coroutine's own errors are already caught by
                -- coroutine.resume (driver.pump reports them without
                -- raising); this guard covers everything else in here.
                local _, coroutineError = driver.pump(co, 20)
                if coroutineError then
                    print("timetables_plus: coroutine error: " .. tostring(coroutineError))
                end

                state.regulation = regulator.getState()
            end)
        end,

        guiUpdate = function()
            guard.call("guiUpdate", function()
                if configChanged then
                    game.interface.sendScriptEvent(EVENT_ID, "", regulator.getState())
                    configChanged = false
                end
            end)
        end,

        guiHandleEvent = function(id, name, _)
            guard.call("guiHandleEvent", function()
                -- The game raises idAdded for temp.view.entity_<N> whenever
                -- an entity window opens. If that entity is a line, it is
                -- the line window and we can append our control to it.
                if name ~= "idAdded" then return end
                if not id:match("^temp%.view%.entity_%d+$") then return end

                -- Capture the digits with match: gsub returns (string, count) and the count would
                -- become tonumber's base, which raises "base out of range" and crashes the game.
                local entityID = tonumber(id:match("^temp%.view%.entity_(%d+)$"))
                if not entityID then return end

                -- getComponent RAISES "Invalid entity" on an id that no
                -- longer exists; entityExists is the safe check.
                if not api.engine.entityExists(entityID) then return end
                if not api.engine.getComponent(entityID, api.type.ComponentType.LINE) then
                    return
                end

                -- The same window id comes back when a line window is
                -- reopened, and idAdded is not guaranteed to fire only once
                -- per window. Give the row an id and skip if it is already
                -- there, or the control stacks up.
                local rowId = "timetables_plus.line." .. tostring(entityID)
                if api.gui.util.getById(rowId) then return end

                local widget = api.gui.util.getById(id)
                if not widget then return end
                local window = api.gui.util.downcast(widget)
                if not window then return end

                local ok, err = pcall(function()
                    local row = buildRegulatorRow(entityID)
                    row:setId(rowId)
                    window:getContent():addItem(row, 0, 0)
                end)
                if not ok then
                    print("timetables_plus: could not add line window control: " .. tostring(err))
                end
            end)
        end,
    }
end
