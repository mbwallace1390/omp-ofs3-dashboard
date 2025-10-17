--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local arg = {...}
local config = arg[1]

local telemetry = {}
local protocol, telemetrySOURCE, crsfSOURCE

local sensors = setmetatable({}, {__mode = "v"})

local cache_hits, cache_misses = 0, 0

local HOT_SIZE = 25
local hot_list, hot_index = {}, {}

local function mark_hot(key)
    local idx = hot_index[key]
    if idx then
        table.remove(hot_list, idx)
    elseif #hot_list >= HOT_SIZE then
        local old = table.remove(hot_list, 1)
        hot_index[old] = nil

        sensors[old] = nil
    end
    table.insert(hot_list, key)
    hot_index[key] = #hot_list
end

function telemetry._debugStats()
    local hot_count = #hot_list
    return {hits = cache_hits, misses = cache_misses, hot_size = hot_count, hot_list = hot_list}
end

local sensorRateLimit = os.clock()
local ONCHANGE_RATE = 0.5

local lastValidationResult = nil
local lastValidationTime = 0
local VALIDATION_RATE_LIMIT = 2

local lastCacheFlushTime = 0
local CACHE_FLUSH_INTERVAL = 5

local telemetryState = false

local lastSensorValues = {}

telemetry.sensorStats = {}

local filteredOnchangeSensors = nil
local onchangeInitialized = false

local sensorTable = {

    rssi = {
        name = "@i18n(telemetry.sensors.rssi)@",
        mandatory = true,
        stats = true,
        switch_alerts = true,
        unit = UNIT_PERCENT,
        unit_string = "%",
        sensors = {sim = {{appId = 0xF010, subId = 0}}, sport = {{appId = 0xF010, subId = 0}}, crsf = {{crsfId = 0x14, subId = 2}}, crsfLegacy = {{crsfId = 0x14, subIdStart = 0, subIdEnd = 1}}}
    },

    link = {
        name = "@i18n(telemetry.sensors.link)@",
        mandatory = true,
        stats = true,
        switch_alerts = true,
        unit = UNIT_DB,
        unit_string = "dB",
        sensors = {sim = {{appId = 0xF101, subId = 0}}, sport = {{appId = 0xF101, subId = 0}, "RSSI"}, crsf = {{crsfId = 0x14, subIdStart = 0, subIdEnd = 1}, "Rx RSSI1"}, crsfLegacy = {{crsfId = 0x14, subIdStart = 0, subIdEnd = 1}, "RSSI 1", "RSSI 2"}}
    },

    armed = {
        name = "@i18n(telemetry.sensors.arming_flags)@",
        mandatory = true,
        stats = false,
        switch_alerts = false,
        unit = UNIT_RAW,
        unit_string = "",
        sensors = {sim = {{uid = 0x5FE0, unit = UNIT_RAW, dec = 0, value = function() return not ofs3.utils.simSensors('armed') end, min = 0, max = 1}}, crsf = {{appId = 0x5FE0, subId = 0}}}
    },

    profile = {
        name = "@i18n(telemetry.sensors.profile)@",
        mandatory = true,
        stats = false,
        switch_alerts = false,
        unit = UNIT_RAW,
        unit_string = "",
        sensors = {sim = {{uid = 0x5FE1, unit = UNIT_RAW, dec = 0, value = function() return ofs3.utils.simSensors('profile') end, min = 0, max = 3}}, crsf = {{appId = 0x5FE1, subId = 0}}}
    },

    voltage = {
        name = "@i18n(telemetry.sensors.voltage)@",
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 3,
        switch_alerts = true,
        unit = UNIT_VOLT,
        unit_string = "V",
        sensors = {sim = {{uid = 0x5002, unit = UNIT_VOLT, dec = 2, value = function() return ofs3.utils.simSensors('voltage') end, min = 0, max = 3000}}, crsf = {"Rx Batt"}}
    },

    rpm = {
        name = "@i18n(telemetry.sensors.headspeed)@",
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 60,
        switch_alerts = true,
        unit = UNIT_RPM,
        unit_string = "rpm",
        sensors = {sim = {{uid = 0x5003, unit = UNIT_RPM, dec = nil, value = function() return ofs3.utils.simSensors('rpm') end, min = 0, max = 4000}}, crsf = {"GPS alt"}}
    },

    smartfuel = {
        name = "@i18n(telemetry.sensors.smartfuel)@",
        mandatory = false,
        stats = true,
        set_telemetry_sensors = nil,
        switch_alerts = true,
        unit = UNIT_PERCENT,
        unit_string = "%",
        sensors = {sim = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FDF}}, crsf = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FDF}}}
    },

    current = {
        name = "@i18n(telemetry.sensors.current)@",
        mandatory = false,
        stats = true,
        set_telemetry_sensors = 18,
        switch_alerts = true,
        unit = UNIT_AMPERE,
        unit_string = "A",
        sensors = {sim = {{uid = 0x5004, unit = UNIT_AMPERE, dec = 0, value = function() return ofs3.utils.simSensors('current') end, min = 0, max = 300}}, crsf = {"Rx Current"}}
    },

    temp_esc = {
        name = "@i18n(telemetry.sensors.esc_temp)@",
        mandatory = false,
        stats = true,
        set_telemetry_sensors = 23,
        switch_alerts = true,
        unit = UNIT_DEGREE,
        sensors = {sim = {{uid = 0x5005, unit = UNIT_DEGREE, dec = 0, value = function() return ofs3.utils.simSensors('temp_esc') end, min = 0, max = 100}}, crsf = {"GPS speed"}},
        localizations = function(value)
            local major = UNIT_DEGREE
            if value == nil then return nil, major, nil end

            local prefs = ofs3.preferences.localizations
            local isFahrenheit = prefs and prefs.temperature_unit == 1

            if isFahrenheit then return value * 1.8 + 32, major, "°F" end

            return value, major, "°C"
        end
    },

    temp_mcu = {
        name = "@i18n(telemetry.sensors.mcu_temp)@",
        mandatory = false,
        stats = true,
        set_telemetry_sensors = 52,
        switch_alerts = true,
        unit = UNIT_DEGREE,
        sensors = {sim = {{uid = 0x5006, unit = UNIT_DEGREE, dec = 0, value = function() return ofs3.utils.simSensors('temp_mcu') end, min = 0, max = 100}}, crsf = {"GPS Sats"}},
        localizations = function(value)
            local major = UNIT_DEGREE
            if value == nil then return nil, major, nil end

            local prefs = ofs3.preferences.localizations
            local isFahrenheit = prefs and prefs.temperature_unit == 1

            if isFahrenheit then return value * 1.8 + 32, major, "°F" end

            return value, major, "°C"
        end
    },

    fuel = {
        name = "@i18n(telemetry.sensors.fuel)@",
        mandatory = false,
        stats = true,
        set_telemetry_sensors = 6,
        switch_alerts = true,
        unit = UNIT_PERCENT,
        unit_string = "%",
        sensors = {sim = {{uid = 0x5007, unit = UNIT_PERCENT, dec = 0, value = function() return ofs3.utils.simSensors('fuel') end, min = 0, max = 100}}, crsf = {"Rx Batt%"}}
    },

    consumption = {
        name = "@i18n(telemetry.sensors.consumption)@",
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 5,
        switch_alerts = true,
        unit = UNIT_MILLIAMPERE_HOUR,
        unit_string = "mAh",
        sensors = {sim = {{uid = 0x5008, unit = UNIT_MILLIAMPERE_HOUR, dec = 0, value = function() return ofs3.utils.simSensors('consumption') end, min = 0, max = 5000}}, crsf = {"Rx Cons"}}
    }

}

function telemetry.getSensorProtocol() return protocol end

function telemetry.listSensors()
    local sensorList = {}
    for key, sensor in pairs(sensorTable) do table.insert(sensorList, {key = key, name = sensor.name, mandatory = sensor.mandatory, set_telemetry_sensors = sensor.set_telemetry_sensors}) end
    return sensorList
end

function telemetry.listSensorAudioUnits()
    local sensorMap = {}
    for key, sensor in pairs(sensorTable) do if sensor.unit then sensorMap[key] = sensor.unit end end
    return sensorMap
end

function telemetry.listSwitchSensors()
    local sensorList = {}
    for key, sensor in pairs(sensorTable) do if sensor.switch_alerts then table.insert(sensorList, {key = key, name = sensor.name, mandatory = sensor.mandatory, set_telemetry_sensors = sensor.set_telemetry_sensors}) end end
    return sensorList
end

function telemetry.getSensorSource(name)
    if not sensorTable[name] then return nil end

    if sensors[name] then
        cache_hits = cache_hits + 1
        mark_hot(name)
        return sensors[name]
    end

    local function checkCondition(sensorEntry)
        if not (ofs3.session and ofs3.session.apiVersion) then return true end
        local roundedApiVersion = ofs3.utils.round(ofs3.session.apiVersion, 2)
        if sensorEntry.mspgt then
            return roundedApiVersion >= ofs3.utils.round(sensorEntry.mspgt, 2)
        elseif sensorEntry.msplt then
            return roundedApiVersion <= ofs3.utils.round(sensorEntry.msplt, 2)
        end
        return true
    end

    if system.getVersion().simulation == true then
        protocol = "sport"
        for _, sensor in ipairs(sensorTable[name].sensors.sim or {}) do

            if sensor.uid then
                if sensor and type(sensor) == "table" then
                    local sensorQ = {appId = sensor.uid, category = CATEGORY_TELEMETRY_SENSOR}
                    local source = system.getSource(sensorQ)
                    if source then
                        cache_misses = cache_misses + 1
                        sensors[name] = source
                        mark_hot(name)
                        return source
                    end
                end
            else

                if checkCondition(sensor) and type(sensor) == "table" then
                    sensor.mspgt = nil
                    sensor.msplt = nil
                    local source = system.getSource(sensor)
                    if source then
                        cache_misses = cache_misses + 1
                        sensors[name] = source
                        mark_hot(name)
                        return source
                    end
                end
            end
        end

    elseif ofs3.session.telemetryType == "crsf" then
        protocol = "crsf"
        for _, sensor in ipairs(sensorTable[name].sensors.crsf or {}) do
            local source = system.getSource(sensor)
            if source then
                cache_misses = cache_misses + 1
                sensors[name] = source
                mark_hot(name)
                return source
            end
        end
    else
        protocol = "unknown"
    end

    return nil
end

function telemetry.getSensor(sensorKey)
    local entry = sensorTable[sensorKey]

    if entry and type(entry.source) == "function" then
        local src = entry.source()
        if src and type(src.value) == "function" then
            local value, major, minor = src.value()
            major = major or entry.unit

            if entry.localizations and type(entry.localizations) == "function" then value, major, minor = entry.localizations(value) end
            return value, major, minor
        end
    end

    local source = telemetry.getSensorSource(sensorKey)
    if not source then return nil end

    local value = source:value()
    local major = entry and entry.unit or nil
    local minor = nil

    if entry and entry.localizations and type(entry.localizations) == "function" then value, major, minor = entry.localizations(value) end

    return value, major, minor
end

function telemetry.validateSensors(returnValid)
    local now = os.clock()
    if (now - lastValidationTime) < VALIDATION_RATE_LIMIT then return lastValidationResult end
    lastValidationTime = now

    if not ofs3.session.telemetryState then
        local allSensors = {}
        for key, sensor in pairs(sensorTable) do table.insert(allSensors, {key = key, name = sensor.name}) end
        lastValidationResult = allSensors
        return allSensors
    end

    local resultSensors = {}
    for key, sensor in pairs(sensorTable) do
        local sensorSource = telemetry.getSensorSource(key)
        local isValid = (sensorSource ~= nil and sensorSource:state() ~= false)
        if returnValid then
            if isValid then table.insert(resultSensors, {key = key, name = sensor.name}) end
        else
            if not isValid and sensor.mandatory ~= false then table.insert(resultSensors, {key = key, name = sensor.name}) end
        end
    end

    lastValidationResult = resultSensors
    return resultSensors
end

function telemetry.simSensors(returnValid)
    local result = {}
    for key, sensor in pairs(sensorTable) do
        local name = sensor.name
        local firstSportSensor = sensor.sensors.sim and sensor.sensors.sim[1]
        if firstSportSensor then table.insert(result, {name = name, sensor = firstSportSensor}) end
    end
    return result
end

function telemetry.active() return ofs3.session.telemetryState or false end

function telemetry.reset()
    telemetrySOURCE, crsfSOURCE, protocol = nil, nil, nil
    sensors = {}
    hot_list, hot_index = {}, {}

    filteredOnchangeSensors = nil
    lastSensorValues = {}
    onchangeInitialized = false
end

function telemetry.wakeup()
    local now = os.clock()

    if (now - sensorRateLimit) >= ONCHANGE_RATE then
        sensorRateLimit = now

        if not filteredOnchangeSensors then
            filteredOnchangeSensors = {}
            for sensorKey, sensorDef in pairs(sensorTable) do if type(sensorDef.onchange) == "function" then filteredOnchangeSensors[sensorKey] = sensorDef end end

            onchangeInitialized = true
        end

        if onchangeInitialized then
            onchangeInitialized = false
        else

            for sensorKey, sensorDef in pairs(filteredOnchangeSensors) do
                local source = telemetry.getSensorSource(sensorKey)
                if source and source:state() then
                    local val = source:value()
                    if lastSensorValues[sensorKey] ~= val then

                        sensorDef.onchange(val)
                        lastSensorValues[sensorKey] = val
                    end
                end
            end
        end
    end

    if not ofs3.session.telemetryState or ofs3.session.telemetryTypeChanged then telemetry.reset() end
end

function telemetry.getSensorStats(sensorKey) return telemetry.sensorStats[sensorKey] or {min = nil, max = nil} end

telemetry.sensorTable = sensorTable

return telemetry
