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
local ARM_CHANGE_MINIMUM = 600
local ARM_CANDIDATE_SECONDS = 12
local MAX_CHANNELS = 24
local STATS_INTERVAL = 0.25
local trackedStats = {"rssi", "voltage", "rpm", "current", "temp_esc", "consumption", "smartfuel"}

local state = {
    mode = "preflight",
    hasBeenInFlight = false,
    seenArmedSignal = false,
    timerStart = nil,
    timerBase = 0,
    lastStatsAt = 0,
    diagnostics = {},
    autoArmMember = nil,
    autoArmReversed = false,
    autoArmLocked = false,
    armCandidate = nil,
    lastMotionActive = false
}

local channelSources = {}
local channelValues = {}

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function channelHigh(value)
    value = tonumber(value)
    if value == nil then return nil end
    if abs(value) <= 1.5 then return value > 0.2 end
    if abs(value) <= 100 then return value > 25 end
    return value >= 500
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

local function aegisPreferences()
    local prefs = ofs3.session and ofs3.session.modelPreferences
    local section = prefs and prefs["system/aegis"] or nil
    local armChannel = floor(tonumber(section and section.armChannel) or 0)
    local armReversed = tonumber(section and section.armReversed) == 1
    return clamp(armChannel, 0, MAX_CHANNELS), armReversed
end

local function getChannelSource(member)
    if member == nil or not system.getSource or CATEGORY_CHANNEL == nil then return nil end
    if channelSources[member] == nil then
        channelSources[member] = system.getSource({category = CATEGORY_CHANNEL, member = member, options = 0})
    end
    return channelSources[member]
end

local function readChannelMember(member)
    local source = getChannelSource(member)
    if not (source and type(source.value) == "function") then return nil end
    local ok, value = pcall(source.value, source)
    if not ok then return nil end
    return tonumber(value)
end

local function excludedChannels(rx)
    local excluded = {}
    local map = rx and rx.map or {}
    for name, member in pairs(map) do
        if name ~= "arm" and member ~= nil then
            excluded[tonumber(member)] = true
        end
    end
    return excluded
end

local function scanForArmChannel(rx, motionActive)
    local manualChannel = aegisPreferences()
    if manualChannel > 0 or state.autoArmLocked then return end

    local excluded = excludedChannels(rx)
    local now = os.clock()
    for member = 0, MAX_CHANNELS - 1 do
        if not excluded[member] then
            local value = readChannelMember(member)
            local previous = channelValues[member]
            channelValues[member] = value
            if value ~= nil and previous ~= nil and not motionActive then
                if abs(value - previous) >= ARM_CHANGE_MINIMUM then
                    state.armCandidate = {member = member, value = value, previous = previous, changedAt = now}
                    state.autoArmMember = member
                    state.autoArmReversed = channelHigh(value) == false
                end
            end
        end
    end

    if state.armCandidate and now - state.armCandidate.changedAt > ARM_CANDIDATE_SECONDS then
        state.armCandidate = nil
        if not state.hasBeenInFlight then
            state.autoArmMember = nil
            state.autoArmReversed = false
        end
    end
end

local function readArmSignal(values, rx)
    local armChannel, armReversed = aegisPreferences()
    local raw, displayChannel, sourceName = nil, armChannel, "DEFAULT"

    if armChannel > 0 then
        raw = readChannelMember(armChannel - 1)
        sourceName = "MANUAL"
    elseif state.autoArmMember ~= nil then
        displayChannel = state.autoArmMember + 1
        raw = readChannelMember(state.autoArmMember)
        armReversed = state.autoArmReversed
        sourceName = state.autoArmLocked and "LEARNED" or "LEARNING"
    else
        raw = tonumber(values.arm)
        local mappedMember = rx and rx.map and tonumber(rx.map.arm)
        if mappedMember ~= nil then displayChannel = mappedMember + 1 end
    end

    local armed = channelHigh(raw)
    local known = armed ~= nil
    if sourceName == "DEFAULT" and raw ~= nil and abs(raw) < 10 then
        known, armed = false, nil
    end
    if known and armReversed then armed = not armed end
    return raw, armed, known, displayChannel, armReversed, sourceName
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

    scanForArmChannel(rx, motionActive)

    if motionActive and not state.lastMotionActive and state.autoArmMember ~= nil then
        local current = readChannelMember(state.autoArmMember)
        local currentHigh = channelHigh(current)
        if currentHigh ~= nil then
            state.autoArmReversed = currentHigh == false
            state.autoArmLocked = true
            state.seenArmedSignal = true
        end
    end
    state.lastMotionActive = motionActive

    local armRaw, armActive, armKnown, armChannel, armReversed, armSource = readArmSignal(values, rx)
    local source = rpmActive and "RPM" or (throttleActive and "THR" or (armKnown and (armActive and "ARM" or "SAFE") or "ARM?"))
    return {
        rpm = rpm,
        throttleRaw = throttleRaw,
        throttle = throttle,
        armRaw = armRaw,
        armActive = armActive,
        armKnown = armKnown,
        armChannel = armChannel,
        armReversed = armReversed,
        armSource = armSource,
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
    state.autoArmMember = nil
    state.autoArmReversed = false
    state.autoArmLocked = false
    state.armCandidate = nil
    state.lastMotionActive = false
    channelSources = {}
    channelValues = {}
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
    if result and (result.model_changed or result.flight_reset) then resetState() end
    local signals = readSignals()
    local previous = state.mode
    if signals.armKnown and signals.armActive then state.seenArmedSignal = true end

    if signals.motionActive then
        state.hasBeenInFlight = true
        state.mode = "inflight"
    elseif state.hasBeenInFlight and state.seenArmedSignal and signals.armKnown and not signals.armActive then
        state.mode = "postflight"
    elseif state.hasBeenInFlight then
        state.mode = "inflight"
    else
        state.mode = "preflight"
    end

    signals.mode = state.mode
    signals.seenArmedSignal = state.seenArmedSignal
    signals.autoArmLocked = state.autoArmLocked
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
            if not diagnostics or next(diagnostics) == nil then diagnostics = readSignals() end
            if diagnostics.armKnown then
                if diagnostics.armActive then return "ARMED", common.C.red, true end
                return "DISARMED", common.C.green, false
            end
            if diagnostics.motionActive then return "RUNNING", common.C.amber, nil end
            return "ARM CH --", common.C.muted, nil
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
    if not diagnostics or next(diagnostics) == nil then diagnostics = readSignals() end
    return diagnostics
end

function M.diagnosticText()
    local diagnostics = M.getDiagnostics()
    local channel = diagnostics.armChannel and diagnostics.armChannel > 0 and ("CH" .. tostring(diagnostics.armChannel)) or "AUTO"
    local arm = diagnostics.armRaw == nil and "--" or tostring(floor(diagnostics.armRaw + 0.5))
    local throttle = diagnostics.throttle == nil and "--" or tostring(floor(diagnostics.throttle + 0.5)) .. "%"
    local rpm = tostring(floor((diagnostics.rpm or 0) + 0.5))
    local seen = diagnostics.seenArmedSignal and "Y" or "N"
    local learned = diagnostics.autoArmLocked and "L" or "?"
    return string.format("%s %s%s A:%s T:%s R:%s S:%s", tostring(diagnostics.source or "ARM?"), channel, learned, arm, throttle, rpm, seen)
end

ofs3.aegisStateManager = M
return M
