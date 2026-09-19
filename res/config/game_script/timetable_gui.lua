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

-- Script events are broadcast to every game script on the machine, so the id
-- must be namespaced. Urban Games namespaces theirs (__taskEvent__).
local EVENT_ID = "__timetables_plus__"

local state = nil
local co = nil
local configChanged = false

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

    if not (entry and entry.enabled) then
        -- Not regulated. Release anything a previous setting left held,
        -- otherwise turning the checkbox off would strand a vehicle.
        for _, vehicle in pairs(vehicles) do
            local vehicleInfo = timetableHelper.getVehicleInfo(vehicle)
            if vehicleInfo then releaseVehicle(vehicle, vehicleInfo) end
        end
        return
    end

    entry.waiting = entry.waiting or { }

    local stop = entry.stop or 1
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
            regulateLine(line, vehicles)
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
        stopNameFor(line, regulator.getStop(line)), headwayText(line))
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

    checkbox:onClick(function()
        local nowEnabled = not regulator.isEnabled(line)
        regulator.setEnabled(line, nowEnabled)
        checkboxImage:setImage(nowEnabled and "ui/checkbox1.tga" or "ui/checkbox0.tga", false)
        status:setText(statusTextFor(line))
        -- Drained in guiUpdate: a script event cannot be fired from inside a
        -- GUI element callback (docs/API_FACTS.md).
        configChanged = true
    end)

    row:addRow({checkbox, label, status})
    return row
end

-------------------------------------------------------------
----------------------- Callbacks ---------------------------
-------------------------------------------------------------

function data()
    return {
        handleEvent = function (_, id, _, param)
            if id == EVENT_ID then
                if state == nil then state = {regulation = { }} end
                -- Take the player's configuration, keep our own record of
                -- which vehicles we are holding. Idempotent: an engine-side
                -- echo back into this handler is not ruled out.
                regulator.adoptGuiConfig(regulator.getState(), param)
                state.regulation = regulator.getState()
            end
        end,

        save = function()
            state = state or { }
            state.regulation = regulator.getState()

            return state
        end,

        load = function(loadedState, reset)
            -- `reset` means discard, not adopt.
            if reset then return end
            if loadedState == nil then return end

            if state == nil then
                state = loadedState

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
                -- Repeated call on the GUI thread. Take only what the engine
                -- owns, or this erases what the player is changing.
                regulator.adoptEngineState(
                    regulator.getState(), loadedState.regulation or { })
            end
        end,

        update = function()
            if state == nil then state = {regulation = { }} end

            if co == nil or coroutine.status(co) == "dead" then
                co = coroutine.create(regulationCoroutine)
            end

            local _, coroutineError = driver.pump(co, 20)
            if coroutineError then
                print("timetables_plus: coroutine error: " .. tostring(coroutineError))
            end

            state.regulation = regulator.getState()
        end,

        guiUpdate = function()
            if configChanged then
                game.interface.sendScriptEvent(EVENT_ID, "", regulator.getState())
                configChanged = false
            end
        end,

        guiHandleEvent = function(id, name, _)
            -- The game raises idAdded for temp.view.entity_<N> whenever an
            -- entity window opens. If that entity is a line, it is the line
            -- window and we can append our control to it.
            if name ~= "idAdded" then return end
            if not id:match("^temp%.view%.entity_%d+$") then return end

            local entityID = tonumber(id:gsub("temp%.view%.entity_", ""))
            if not entityID then return end
            if not api.engine.getComponent(entityID, api.type.ComponentType.LINE) then return end

            local window = api.gui.util.downcast(api.gui.util.getById(id))
            if not window then return end

            local ok, err = pcall(function()
                window:getContent():addItem(buildRegulatorRow(entityID), 0, 0)
            end)
            if not ok then
                print("timetables_plus: could not add line window control: " .. tostring(err))
            end
        end,
    }
end
