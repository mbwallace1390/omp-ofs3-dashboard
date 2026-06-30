--[[ Aegis OFS3 live state manager - GPLv3 ]] --
local ofs3 = require("ofs3")

if ofs3.aegisStateManager then
    return ofs3.aegisStateManager
end

local M = {}
local telemetry = ofs3.tasks.telemetry
local abs, floor, max, min = math.abs, math.floor, math.max, math.min
local tonumber, tostring, type = tonumber, tostring, type

local ACTIVE_RPM = 250
local THROTTLE_ACTIVE_PERCENT = 5
local STATS_INTERVAL = 0.25
local trackedStats = {"rssi", "voltage", "rpm", "current", "temp_esc", "consumption", "smartfuel"}

local state = {
    mode = "preflight",
    hasBeenInFlight = false,
    seenArmedSignal = false,
    timerStart = nil,
    timerBase = 0,
    lastStatsAt = 0,
    diagnostics = {}
}

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function throttlePercent(value)
    value = tonumber(value)
    if value == nil then return nil end

    if value >= -1024 and value <= 1024 then
        return clamp((value + 1024) * 100 / 2048, 0, 100)
    end
    if value >= 0 and value <= 100 then return value end
    if value >= -1.5 and value <= 1.5 then
        return clamp((value + 1) * 50, 0, 100)
    end
    return clamp(value, 0, 100)
end

local function normalizeSourceState(value)
    if type(value) == "boolean" then
        return value
    end

    value = tonumber(value)
    if value == nil then return nil end

    -- Physical switches, logical switches and channels can use different
    -- numeric ranges. In every case the positive state is treated as active;
    -- the configuration provides a Reverse option for negative-active setups.
    if abs(value) <= 1.5 then return value > 0.2 end
    if abs(value) <= 100 then return value > 1 end
    return value > 0
end

local function selectedArmConfig()
    local config = ofs3.aegisArmConfig or {}
    return config.source, config.reversed == true
end

local function selectedSourceName(source)
    if not source then return "NO SOURCE" end
    if type(source.name) == "function" then
        local ok, name = pcall(source.name, source)
        if ok and name and name ~= "" then
            return tostring(name)
        end
    end
    return "ARM SOURCE"
end

local function readSelectedArmSource()
    local source, reversed = selectedArmConfig()
    local name = selectedSourceName(source)

    if not source or type(source.value) ~= "function" then
        return nil, nil, false, name, reversed
    end

    local ok, raw = pcall(source.value, source)
    if not ok then
        return nil, nil, false, name, reversed
    end

    local armed = normalizeSourceState(raw)
    if armed == nil then
        return raw, nil, false, name, reversed
    end

    if reversed then armed = not armed end
    return raw, armed, true, name, reversed
end

local function readSignals()
    local rx = ofs3.session and ofs3.session.rx
    local values = rx and rx.values or {}
    local rpm = tonumber(telemetry.getSensor("rpm")) or 0
    local throttleRaw = tonumber(values.throttle)
    local throttle = throttlePercent(throttleRaw)
    local rpmActive = rpm > ACTIVE_RPM
    local throttleActive = throttle ~= nil and throttle > THROTTLE_ACTIVE_PERCENT
    local motionActive = rpmActive or throttleActive
    local armRaw, armActive, armKnown, armName, armReversed = readSelectedArmSource()

    local source
    if armKnown then
        source = armActive and "ARM" or "SAFE"
    elseif rpmActive then
        source = "RPM"
    elseif throttleActive then
        source = "THR"
    else
        source = "SELECT"
    end

    return {
        rpm = rpm,
        throttleRaw = throttleRaw,
        throttle = throttle,
        armRaw = armRaw,
        armActive = armActive,
        armKnown = armKnown,
        armName = armName,
        armReversed = armReversed,
        rpmActive = rpmActive,
        throttleActive = throttleActive,
        motionActive = motionActive,
        source = source,
        protocol = ofs3.session and ofs3.session.telemetryType or "--"
    }
end

local function resetState()
    state.mode = "preflight"
    state.hasBeenInFlight = false
    state.seenArmedSignal = false
    state.timerStart = nil
    state.timerBase = 0
    state.lastStatsAt = 0
    state.diagnostics = {}
end

local function updateTimer(mode)
    local timer = ofs3.session and ofs3.session.timer
    if not timer then return end

    local now = os.time()
    if mode == "inflight" then
        if not state.timerStart then
            state.timerStart = now
            state.timerBase = tonumber(timer.session) or tonumber(timer.live) or 0
        end
        timer.live = state.timerBase + max(0, now - state.timerStart)
    elseif mode == "postflight" then
        if state.timerStart then
            timer.session = state.timerBase + max(0, now - state.timerStart)
            timer.live = timer.session
            state.timerStart = nil
        else
            timer.live = tonumber(timer.session) or tonumber(timer.live) or 0
        end
    else
        timer.live = tonumber(timer.session) or 0
    end
end

local function updateStats(mode)
    if mode ~= "inflight" or not (ofs3.session and ofs3.session.isConnected) then return end

    local now = os.clock()
    if now - state.lastStatsAt < STATS_INTERVAL then return end
    state.lastStatsAt = now

    telemetry.sensorStats = telemetry.sensorStats or {}
    for _, key in ipairs(trackedStats) do
        local value = tonumber(telemetry.getSensor(key))
        if value ~= nil then
            local stats = telemetry.sensorStats[key]
            if not stats then
                stats = {min = math.huge, max = -math.huge, sum = 0, count = 0, avg = 0}
                telemetry.sensorStats[key] = stats
            end
            stats.min = min(stats.min, value)
            stats.max = max(stats.max, value)
            stats.sum = stats.sum + value
            stats.count = stats.count + 1
            stats.avg = stats.sum / stats.count
        end
    end
end

local function updateMode(result)
    if result and (result.model_changed or result.flight_reset) then
        resetState()
    end

    local signals = readSignals()
    local previous = state.mode

    if signals.armKnown and signals.armActive then
        state.seenArmedSignal = true
    end

    -- Once a flight has started, an explicit selected-source DISARM has
    -- priority over RPM. This changes to postflight immediately on disarm,
    -- while throttle hold stays inflight because the arm source remains active.
    if state.hasBeenInFlight and state.seenArmedSignal and signals.armKnown and not signals.armActive then
        state.mode = "postflight"
    elseif signals.motionActive then
        state.hasBeenInFlight = true
        state.mode = "inflight"
    elseif state.hasBeenInFlight then
        state.mode = "inflight"
    else
        state.mode = "preflight"
    end

    signals.mode = state.mode
    signals.seenArmedSignal = state.seenArmedSignal
    state.diagnostics = signals
    ofs3.session.aegisState = signals
    ofs3.flightmode.current = state.mode

    updateTimer(state.mode)
    updateStats(state.mode)

    if result then
        result.flightmode_changed = result.flightmode_changed or previous ~= state.mode
        result.aegis_mode = state.mode
    end
end

function M.install(common)
    if common then
        common.flightState = function()
            local diagnostics = state.diagnostics
            if not diagnostics or next(diagnostics) == nil then
                diagnostics = readSignals()
            end

            if diagnostics.armKnown then
                if diagnostics.armActive then
                    return "ARMED", common.C.red, true
                end
                return "DISARMED", common.C.green, false
            end

            if diagnostics.motionActive then
                return "RUNNING", common.C.amber, nil
            end
            return "SELECT ARM", common.C.muted, nil
        end
    end

    if not ofs3.runtime._aegisOriginalWakeup then
        ofs3.runtime._aegisOriginalWakeup = ofs3.runtime.wakeup
        ofs3.runtime.wakeup = function(...)
            local result = ofs3.runtime._aegisOriginalWakeup(...) or {}
            updateMode(result)
            return result
        end
    end

    return M
end

function M.getDiagnostics()
    local diagnostics = state.diagnostics
    if not diagnostics or next(diagnostics) == nil then
        diagnostics = readSignals()
    end
    return diagnostics
end

local function rawText(value)
    if type(value) == "boolean" then return value and "1" or "0" end
    value = tonumber(value)
    if value == nil then return "--" end
    return tostring(floor(value + (value >= 0 and 0.5 or -0.5)))
end

function M.diagnosticText()
    local diagnostics = M.getDiagnostics()
    local name = tostring(diagnostics.armName or "NO SOURCE")
    if #name > 8 then name = name:sub(1, 8) end
    local throttle = diagnostics.throttle == nil and "--" or tostring(floor(diagnostics.throttle + 0.5)) .. "%"
    local rpm = tostring(floor((diagnostics.rpm or 0) + 0.5))
    local seen = diagnostics.seenArmedSignal and "Y" or "N"
    return string.format("%s %s A:%s T:%s R:%s S:%s", tostring(diagnostics.source or "SELECT"), name, rawText(diagnostics.armRaw), throttle, rpm, seen)
end

ofs3.aegisStateManager = M
return M
