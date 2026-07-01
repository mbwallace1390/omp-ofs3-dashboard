--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local runtime = {}

local telemetry = ofs3.tasks.telemetry

local trackedStats = {"rssi", "voltage", "rpm", "current", "temp_esc", "consumption", "smartfuel"}
local FLIGHT_COUNT_MIN_SECONDS = 10

-- MWRC switch-safety screen control, telemetry-gated v7.
-- The selected Throttle Cut and Throttle Hold positions are authoritative only
-- while live OFS3 telemetry is connected. RPM remains a configuration fallback.
local FLIGHT_START_RPM = 1000
local FLIGHT_STOP_RPM = 250
local POSTFLIGHT_RPM_DELAY = 8.0
local POSTFLIGHT_DISPLAY_SECONDS = 8.0

local defaultBatteryConfig = {
    batteryCapacity = 750,
    batteryCellCount = 3,
    vbatwarningcellvoltage = 3.5,
    vbatmincellvoltage = 3.3,
    vbatmaxcellvoltage = 4.3,
    vbatfullcellvoltage = 4.1,
    lvcPercentage = 30,
    consumptionWarningPercentage = 30
}

local configurableBatteryFields = {
    batteryCapacity = true,
    batteryCellCount = true
}

local modelPreferenceDefaults = {
    general = {
        flightcount = 0,
        totalflighttime = 0,
        lastflighttime = 0
    },
    battery = {
        batteryCapacity = 750,
        batteryCellCount = 3,
        vbatwarningcellvoltage = 3.5,
        vbatmincellvoltage = 3.3,
        vbatmaxcellvoltage = 4.3,
        vbatfullcellvoltage = 4.1,
        lvcPercentage = 30,
        consumptionWarningPercentage = 30
    },
    ["system/@default"] = {
        tx_min = 7.2,
        tx_warn = 7.4,
        tx_max = 8.4
    }
}

local currentModelKey = nil
local currentFlightMode = "preflight"
local hasBeenInFlight = false
local rpmBelowStopSince = nil
local postflightEnteredAt = nil

-- Radio-side OFS3 safety sequence:
--   1. Cut active + Hold active primes the safe arming sequence.
--   2. Release Cut while Hold remains active latches Armed.
--   3. Release Hold starts Inflight.
--   4. Hold may be re-applied in flight without ending the flight.
--   5. Cut active is the only switch action that ends the flight.
local armSequenceReady = false
local switchArmed = false
local lastCutActive = nil
local lastHoldActive = nil

local lastStatsAt = 0
local currentTelemetryType = nil
local lastTelemetryAvailable = nil
local channelSources = {}
local rxInitializedForProtocol = nil
local telemetryActiveSource = nil
local flightResetEventSrc = nil
local flightResetEventSupported = (CATEGORY_SYSTEM_EVENT ~= nil and SYSTEM_EVENT_FLIGHT_RESET ~= nil)
local flightResetEventPrimed = false
local lastFlightResetEventState = false
local SRC_FLIGHT_RESET = {category = CATEGORY_SYSTEM_EVENT, member = SYSTEM_EVENT_FLIGHT_RESET}
local SRC_TELEMETRY_ACTIVE = {category = CATEGORY_SYSTEM_EVENT, member = TELEMETRY_ACTIVE}

local function copyTable(input)
    local out = {}
    for key, value in pairs(input or {}) do
        if type(value) == "table" then
            out[key] = copyTable(value)
        else
            out[key] = value
        end
    end
    return out
end

local function getModelKey()
    local path = model.path and model.path() or ""
    local name = model.name and model.name() or ""
    local raw = path ~= "" and path or name
    return ofs3.utils.sanitize_filename(raw)
end

local function normalizeSourceState(state)
    if state == true then return true end
    if type(state) == "number" then return state ~= 0 end
    return false
end

local function resetFlightEventMonitor()
    if flightResetEventSupported and system.getSource then
        flightResetEventSrc = system.getSource(SRC_FLIGHT_RESET)
    else
        flightResetEventSrc = nil
    end
    flightResetEventPrimed = false
    lastFlightResetEventState = false
end

local function resolvePreferencePaths(modelKey)
    local prefDir = "SCRIPTS:/" .. ofs3.config.preferences
    local modelsDir = prefDir .. "/models"
    local prefFile = modelsDir .. "/" .. modelKey .. ".ini"

    os.mkdir(prefDir)
    os.mkdir(modelsDir)

    return prefFile
end

local function loadModelPreferencesData(modelKey)
    local prefFile = resolvePreferencePaths(modelKey)

    local existing = ofs3.ini.load_ini_file(prefFile) or {}
    local merged = ofs3.ini.merge_ini_tables(existing, modelPreferenceDefaults)

    if not ofs3.ini.ini_tables_equal(existing, merged) then
        ofs3.ini.save_ini_file(prefFile, merged)
    end

    return merged, prefFile
end

local function buildBatteryConfig(prefs)
    local battery = copyTable(defaultBatteryConfig)
    local stored = prefs and prefs.battery or {}

    for key, defaultValue in pairs(defaultBatteryConfig) do
        if configurableBatteryFields[key] then
            local value = stored[key]
            if type(defaultValue) == "number" then
                value = tonumber(value)
            end
            if value ~= nil then
                battery[key] = value
            end
        end
    end

    return battery
end

local function loadModelPreferences(modelKey)
    local merged, prefFile = loadModelPreferencesData(modelKey)

    ofs3.session.modelPreferences = merged
    ofs3.session.modelPreferencesFile = prefFile
    ofs3.session.batteryConfig = buildBatteryConfig(merged)
end

local function resetTimer()
    local total = 0
    if ofs3.session.modelPreferences then
        total = tonumber(ofs3.ini.getvalue(ofs3.session.modelPreferences, "general", "totalflighttime")) or 0
    end

    ofs3.session.timer = {
        start = nil,
        live = 0,
        session = 0,
        lifetime = total,
        baseLifetime = total
    }
    ofs3.session.flightCounted = false
end

local function saveTimerTotals()
    local prefs = ofs3.session.modelPreferences
    local prefFile = ofs3.session.modelPreferencesFile

    if not prefs or not prefFile then
        return
    end

    ofs3.ini.setvalue(prefs, "general", "totalflighttime", ofs3.session.timer.baseLifetime or 0)
    ofs3.ini.setvalue(prefs, "general", "lastflighttime", ofs3.session.timer.session or 0)
    ofs3.ini.save_ini_file(prefFile, prefs)
end

local function initializeModel(modelKey)
    ofs3.utils.session()

    ofs3.session.mcu_id = modelKey
    ofs3.session.craftName = model.name and model.name() or "Model"

    loadModelPreferences(modelKey)
    resetTimer()

    telemetry.reset()
    if ofs3.logs and ofs3.logs.reset then
        ofs3.logs.reset()
    end
    if ofs3.events and ofs3.events.reset then
        ofs3.events.reset()
    end
    ofs3.flightmode.current = "preflight"
    currentFlightMode = "preflight"
    currentTelemetryType = nil
    lastTelemetryAvailable = nil
    hasBeenInFlight = false
    rpmBelowStopSince = nil
    postflightEnteredAt = nil
    armSequenceReady = false
    switchArmed = false
    lastCutActive = nil
    lastHoldActive = nil
    ofs3.mwrcSafetyUsingSwitches = false
    ofs3.mwrcArmedLatched = nil
    ofs3.mwrcCutActive = nil
    ofs3.mwrcHoldActive = nil
    lastStatsAt = 0
    channelSources = {}
    rxInitializedForProtocol = nil
    telemetryActiveSource = nil
    resetFlightEventMonitor()
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function normalizeBatterySettings(input)
    local output = copyTable(defaultBatteryConfig)

    if type(input) ~= "table" then
        return output
    end

    output.batteryCellCount = clamp(math.floor(tonumber(input.batteryCellCount) or output.batteryCellCount), 1, 14)
    output.batteryCapacity = clamp(math.floor(tonumber(input.batteryCapacity) or output.batteryCapacity), 100, 20000)

    return output
end

function runtime.readWidgetSettings(widget)
    local modelKey = getModelKey()
    local prefs, prefFile = loadModelPreferencesData(modelKey)
    local battery = normalizeBatterySettings(buildBatteryConfig(prefs))

    if widget then
        for key, value in pairs(battery) do
            widget[key] = value
        end
        widget._modelKey = modelKey
        widget._preferencesFile = prefFile
    end

    if currentModelKey == modelKey then
        ofs3.session.modelPreferences = prefs
        ofs3.session.modelPreferencesFile = prefFile
        ofs3.session.batteryConfig = copyTable(battery)
    end

    return battery, prefs, prefFile, modelKey
end

function runtime.writeWidgetSettings(widget)
    local modelKey = (widget and widget._modelKey) or getModelKey()
    local prefs, prefFile = loadModelPreferencesData(modelKey)
    local battery = normalizeBatterySettings(widget or {})

    prefs.battery = prefs.battery or {}
    for key, value in pairs(battery) do
        prefs.battery[key] = value
        if widget then
            widget[key] = value
        end
    end

    ofs3.ini.save_ini_file(prefFile, prefs)

    if currentModelKey == modelKey then
        ofs3.session.modelPreferences = prefs
        ofs3.session.modelPreferencesFile = prefFile
        ofs3.session.batteryConfig = copyTable(battery)
    end

    return true
end

local function initializeRxMap(protocol)
    ofs3.session.rx = ofs3.session.rx or {map = {}, values = {}}
    ofs3.session.rx.map = ofs3.session.rx.map or {}
    ofs3.session.rx.values = ofs3.session.rx.values or {}

    local map = ofs3.session.rx.map

    if protocol == "sport" then
        map.aileron = 0
        map.elevator = 1
        map.collective = 5
        map.rudder = 3
        map.arm = 7
        map.throttle = 2
        map.mode = 6
        map.headspeed = 6
    else
        map.aileron = 0
        map.elevator = 1
        map.collective = 2
        map.rudder = 3
        map.arm = 4
        map.throttle = 5
        map.mode = 6
        map.headspeed = 7
    end

    channelSources = {}
    rxInitializedForProtocol = protocol
end

local function updateRxValues(protocol)
    if protocol == nil or protocol == "sim" then
        return
    end

    if rxInitializedForProtocol ~= protocol or not ofs3.utils.rxmapReady() then
        initializeRxMap(protocol)
    end

    local rx = ofs3.session.rx
    local map = rx and rx.map or nil
    if not map then
        return
    end

    for name, member in pairs(map) do
        if channelSources[name] == nil and member ~= nil then
            channelSources[name] = system.getSource({category = CATEGORY_CHANNEL, member = member, options = 0})
        end
    end

    for name, src in pairs(channelSources) do
        if src and src.value then
            local value = src:value()
            if value ~= nil then
                rx.values[name] = value
            end
        end
    end
end

local function getTelemetryActiveSource()
    if system.getVersion().simulation then
        return nil
    end

    if CATEGORY_SYSTEM_EVENT == nil or TELEMETRY_ACTIVE == nil then
        return nil
    end

    if telemetryActiveSource == nil and system.getSource then
        telemetryActiveSource = system.getSource(SRC_TELEMETRY_ACTIVE)
    end

    return telemetryActiveSource
end

local function sourceIsActive(source)
    if not source then
        return false
    end

    if type(source.state) ~= "function" then
        return true
    end

    local ok, state = pcall(source.state, source)
    if not ok then
        return true
    end

    return state ~= false
end

local function telemetryLinkActive(protocol, rootSource)
    if protocol == "sim" then
        return true
    end

    local activeSource = getTelemetryActiveSource()
    if activeSource and type(activeSource.state) == "function" then
        local ok, state = pcall(activeSource.state, activeSource)
        if ok then
            return state ~= false and state ~= nil
        end
    end

    return sourceIsActive(rootSource)
end

local function updateTelemetryState()
    local protocol, rootSource, moduleRef = telemetry.detectProtocol()

    if protocol ~= currentTelemetryType then
        telemetry.setProtocol(protocol)
        currentTelemetryType = protocol
    end

    ofs3.session.telemetryType = protocol
    ofs3.session.telemetrySensor = rootSource
    ofs3.session.telemetryModule = moduleRef

    local available = protocol ~= nil and telemetryLinkActive(protocol, rootSource)
    local recovered = available and lastTelemetryAvailable == false
    lastTelemetryAvailable = available

    ofs3.session.telemetryState = available
    ofs3.session.isConnected = available
    ofs3.session.isConnectedHigh = available
    ofs3.session.isConnectedLow = available

    return protocol, recovered
end

local function normalizeSwitchPosition(value)
    if type(value) == "boolean" then
        return value
    end

    value = tonumber(value)
    if value == nil then
        return nil
    end

    return value ~= 0
end

local function readSwitchPosition(source)
    if not source then
        return nil
    end

    -- Ethos switch-position sources should report whether the selected
    -- position is active through state(). value() is a compatibility fallback.
    if type(source.state) == "function" then
        local ok, value = pcall(source.state, source)
        if ok and value ~= nil then
            return normalizeSwitchPosition(value)
        end
    end

    if type(source.value) == "function" then
        local ok, value = pcall(source.value, source)
        if ok and value ~= nil then
            return normalizeSwitchPosition(value)
        end
    end

    return nil
end

local function readConfiguredSafetySwitches()
    local cutActive = readSwitchPosition(ofs3.mwrcThrottleCutSource)
    local holdActive = readSwitchPosition(ofs3.mwrcThrottleHoldSource)

    if cutActive == nil or holdActive == nil then
        return nil, nil
    end

    return cutActive, holdActive
end

local function publishSafetyState(usingSwitches, cutActive, holdActive)
    ofs3.mwrcSafetyUsingSwitches = usingSwitches
    ofs3.mwrcCutActive = cutActive
    ofs3.mwrcHoldActive = holdActive

    if usingSwitches then
        ofs3.mwrcArmedLatched = switchArmed
    else
        ofs3.mwrcArmedLatched = nil
    end
end

local function determineSwitchFlightMode(cutActive, holdActive)
    lastCutActive = cutActive
    lastHoldActive = holdActive

    -- The true disarm command. Hold can be in any position here.
    if cutActive then
        switchArmed = false

        -- OFS3 requires both safety conditions before the next arm attempt.
        if holdActive then
            armSequenceReady = true
        end

        publishSafetyState(true, cutActive, holdActive)

        if hasBeenInFlight then
            return "postflight", false
        end

        return "preflight", false
    end

    -- Cut is released. Only latch Armed after the safe sequence has first been
    -- observed with both Cut and Hold active, and Hold is still active now.
    if not switchArmed then
        if armSequenceReady and holdActive then
            switchArmed = true
            armSequenceReady = false
            publishSafetyState(true, cutActive, holdActive)

            -- Re-arming after a completed flight begins a clean new session.
            if currentFlightMode == "postflight" or hasBeenInFlight then
                return "preflight", true
            end

            return "preflight", false
        end

        publishSafetyState(true, cutActive, holdActive)

        -- Unsafe or incomplete sequence: never enter Inflight.
        if currentFlightMode == "postflight" then
            return "postflight", false
        end
        return "preflight", false
    end

    publishSafetyState(true, cutActive, holdActive)

    -- Once a flight has begun, temporary Throttle Hold remains Inflight.
    if hasBeenInFlight then
        return "inflight", false
    end

    -- Armed with Hold active is the ready-to-fly Preflight state.
    if holdActive then
        return "preflight", false
    end

    -- Releasing Hold after the valid safety sequence starts the flight.
    hasBeenInFlight = true
    return "inflight", false
end

local function determineRpmFallbackMode()
    local rpm = tonumber(telemetry.getSensor("rpm")) or 0
    local now = os.clock()

    if currentFlightMode == "postflight" and hasBeenInFlight then
        postflightEnteredAt = postflightEnteredAt or now

        if rpm > FLIGHT_STOP_RPM then
            return "preflight", true
        end

        if now - postflightEnteredAt >= POSTFLIGHT_DISPLAY_SECONDS then
            return "preflight", true
        end

        return "postflight", false
    end

    if rpm > FLIGHT_START_RPM then
        hasBeenInFlight = true
        rpmBelowStopSince = nil
        postflightEnteredAt = nil
        return "inflight", false
    end

    if hasBeenInFlight then
        if rpm <= FLIGHT_STOP_RPM then
            if rpmBelowStopSince == nil then
                rpmBelowStopSince = now
            end

            if now - rpmBelowStopSince >= POSTFLIGHT_RPM_DELAY then
                postflightEnteredAt = postflightEnteredAt or now
                return "postflight", false
            end
        else
            rpmBelowStopSince = nil
        end

        return "inflight", false
    end

    rpmBelowStopSince = nil
    postflightEnteredAt = nil
    return "preflight", false
end

local function determineFlightMode()
    -- Radio switch movement by itself must never create a flight-state change.
    -- Without live OFS3 telemetry, keep the current screen frozen. On startup
    -- currentFlightMode is Preflight, so an unpowered helicopter remains there.
    if not (ofs3.session and ofs3.session.isConnected) then
        publishSafetyState(false, nil, nil)
        return currentFlightMode, false
    end

    local cutActive, holdActive = readConfiguredSafetySwitches()

    if cutActive ~= nil and holdActive ~= nil then
        return determineSwitchFlightMode(cutActive, holdActive)
    end

    publishSafetyState(false, nil, nil)
    return determineRpmFallbackMode()
end

local function updateTimer()
    local timer = ofs3.session.timer
    if not timer then
        resetTimer()
        timer = ofs3.session.timer
    end

    local now = os.time()
    local mode = currentFlightMode

    if mode == "inflight" then
        if not timer.start then
            timer.start = now
        end

        local currentSegment = now - timer.start
        timer.live = (timer.session or 0) + currentSegment
        timer.lifetime = (timer.baseLifetime or 0) + currentSegment

        if ofs3.session.modelPreferences then
            ofs3.ini.setvalue(ofs3.session.modelPreferences, "general", "totalflighttime", timer.lifetime)
        end

        if timer.live >= FLIGHT_COUNT_MIN_SECONDS and not ofs3.session.flightCounted and ofs3.session.modelPreferences then
            ofs3.session.flightCounted = true
            local count = tonumber(ofs3.ini.getvalue(ofs3.session.modelPreferences, "general", "flightcount")) or 0
            ofs3.ini.setvalue(ofs3.session.modelPreferences, "general", "flightcount", count + 1)
            ofs3.ini.save_ini_file(ofs3.session.modelPreferencesFile, ofs3.session.modelPreferences)
        end
    else
        timer.live = timer.session or 0
    end

    if mode == "postflight" and timer.start then
        local segment = now - timer.start
        timer.session = (timer.session or 0) + segment
        timer.start = nil
        timer.baseLifetime = (timer.baseLifetime or 0) + segment
        timer.lifetime = timer.baseLifetime
        saveTimerTotals()
    end
end

local function updateStats()
    if currentFlightMode ~= "inflight" or not ofs3.session.isConnected then
        return
    end

    local now = os.clock()
    if now - lastStatsAt < 0.25 then
        return
    end
    lastStatsAt = now

    telemetry.sensorStats = telemetry.sensorStats or {}

    for _, sensorKey in ipairs(trackedStats) do
        local value = telemetry.getSensor(sensorKey)
        if type(value) == "number" then
            local stats = telemetry.sensorStats[sensorKey]
            if not stats then
                stats = {min = math.huge, max = -math.huge, sum = 0, count = 0, avg = 0}
                telemetry.sensorStats[sensorKey] = stats
            end

            stats.min = math.min(stats.min, value)
            stats.max = math.max(stats.max, value)
            stats.sum = stats.sum + value
            stats.count = stats.count + 1
            stats.avg = stats.sum / stats.count
        end
    end
end

local function handleSystemFlightReset()
    if not flightResetEventSupported or not system.getSource then
        return false
    end

    if not flightResetEventSrc then
        flightResetEventSrc = system.getSource(SRC_FLIGHT_RESET)
        if not flightResetEventSrc then
            return false
        end
    end

    if type(flightResetEventSrc.state) ~= "function" then
        return false
    end

    local stateNow = normalizeSourceState(flightResetEventSrc:state())

    if not flightResetEventPrimed then
        lastFlightResetEventState = stateNow
        flightResetEventPrimed = true
        return false
    end

    if stateNow and not lastFlightResetEventState then
        ofs3.utils.log("[event] system flight reset")
        runtime.resetFlight()
        lastFlightResetEventState = stateNow
        return true
    end

    lastFlightResetEventState = stateNow
    return false
end

function runtime.resetFlight()
    hasBeenInFlight = false
    rpmBelowStopSince = nil
    postflightEnteredAt = nil
    currentFlightMode = "preflight"
    ofs3.flightmode.current = "preflight"
    lastStatsAt = 0

    telemetry.sensorStats = {}
    if ofs3.logs and ofs3.logs.reset then
        ofs3.logs.reset()
    end
    resetTimer()

    if ofs3.events and ofs3.events.reset then
        ofs3.events.reset()
    end

    return true
end

function runtime.wakeup()
    local modelKey = getModelKey()
    local modelChanged = modelKey ~= currentModelKey

    if modelChanged then
        currentModelKey = modelKey
        initializeModel(modelKey)
    end

    ofs3.session.craftName = model.name and model.name() or ofs3.session.craftName
    local systemFlightReset = handleSystemFlightReset()

    local _, telemetryRecovered = updateTelemetryState()
    local resetOnTelemetryRecovered = telemetryRecovered and currentFlightMode == "postflight"
    if resetOnTelemetryRecovered then
        runtime.resetFlight()
    end
    updateRxValues(ofs3.session.telemetryType)
    ofs3.sensors.wakeup(ofs3.session.telemetryType, ofs3.session.telemetrySensor)
    if ofs3.session.telemetryType == "sim" and not ofs3.session.telemetrySensor then
        ofs3.session.telemetrySensor = telemetry.getSensorSource("rssi") or telemetry.getSensorSource("voltage")
    end
    telemetry.wakeup()
    if ofs3.events and ofs3.events.wakeup then
        ofs3.events.wakeup()
    end

    local nextFlightMode, automaticFlightReset = determineFlightMode()

    if automaticFlightReset then
        runtime.resetFlight()
        nextFlightMode = "preflight"
    end

    local flightModeChanged =
        resetOnTelemetryRecovered or automaticFlightReset or
        nextFlightMode ~= currentFlightMode

    currentFlightMode = nextFlightMode
    ofs3.flightmode.current = nextFlightMode

    updateTimer()
    updateStats()
    if ofs3.logs and ofs3.logs.wakeup then
        ofs3.logs.wakeup(currentFlightMode)
    end

    return {
        model_changed = modelChanged,
        telemetry_recovered = telemetryRecovered,
        flightmode_changed = flightModeChanged or systemFlightReset,
        flight_reset = systemFlightReset or automaticFlightReset
    }
end

return runtime
