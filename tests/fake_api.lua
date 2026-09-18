-- Minimal stand-in for the Transport Fever 2 scripting API, so the pieces of
-- timetable_helper.lua that talk to the game can be exercised on the host.
--
-- Only the surface timetable_helper actually touches is modelled. Add to it
-- when a test needs more; do not grow it speculatively.

local fakeApi = {}

local components = {}   -- components[entity][componentType] = value
local lines = {}        -- array of line entity ids
local lineVehicles = {} -- lineVehicles[line] = {vehicle, ...}
local stopVehicles = {} -- stopVehicles[line][stop] = {vehicle, ...}

--- Register a component on an entity. Overwrites any previous value.
function fakeApi.setComponent(entity, componentType, value)
    components[entity] = components[entity] or {}
    components[entity][componentType] = value
end

--- Register a line and the vehicles running on it.
function fakeApi.setLine(line, vehicles)
    local known = false
    for _, l in ipairs(lines) do if l == line then known = true end end
    if not known then lines[#lines + 1] = line end
    lineVehicles[line] = vehicles or {}
end

--- Register which vehicles are sitting at a given stop of a line.
function fakeApi.setStopVehicles(line, stop, vehicles)
    stopVehicles[line] = stopVehicles[line] or {}
    stopVehicles[line][stop] = vehicles
end

--- Commands the code under test sent, in order.
fakeApi.commands = {}

--- Install the fakes as globals and reset all registered state.
function fakeApi.install()
    components = {}
    lines = {}
    lineVehicles = {}
    stopVehicles = {}
    fakeApi.commands = {}

    -- The mod's translation function; identity is enough for tests.
    _G._ = function(key) return key end

    -- Component types and enums are opaque keys in the real API. An __index
    -- that returns the key itself gives every name a stable identity.
    local keyedByName = setmetatable({}, {__index = function(_, k) return k end})

    _G.api = {
        type = {
            ComponentType = keyedByName,
            enum = {
                TransportVehicleState = keyedByName,
                Carrier = keyedByName,
            },
        },
        engine = {
            getComponent = function(entity, componentType)
                local onEntity = components[entity]
                return onEntity and onEntity[componentType] or nil
            end,
            util = {
                getWorld = function() return "world" end,
            },
            system = {
                transportVehicleSystem = {
                    getLine2VehicleMap = function() return lineVehicles end,
                    getLineVehicles = function(line) return lineVehicles[line] or {} end,
                    getLineStopVehicles = function(line, stop)
                        return (stopVehicles[line] or {})[stop] or {}
                    end,
                    getVehiclesWithState = function() return {} end,
                },
                lineSystem = {
                    getLines = function() return lines end,
                },
            },
        },
        cmd = {
            sendCommand = function(command)
                fakeApi.commands[#fakeApi.commands + 1] = command
            end,
            make = {
                setVehicleManualDeparture = function(vehicle, manual)
                    return {name = "setVehicleManualDeparture", vehicle = vehicle, manual = manual}
                end,
                setVehicleShouldDepart = function(vehicle)
                    return {name = "setVehicleShouldDepart", vehicle = vehicle}
                end,
                setUserStopped = function(vehicle, stopped)
                    return {name = "setUserStopped", vehicle = vehicle, stopped = stopped}
                end,
            },
        },
    }

    _G.game = {
        interface = {
            getEntity = function(entity)
                local onEntity = components[entity]
                return onEntity and onEntity.ENTITY or nil
            end,
            getLines = function() return lines end,
        },
    }

    return fakeApi
end

return fakeApi
