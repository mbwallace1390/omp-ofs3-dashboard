--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local smart = {}

local smartfuel = assert(loadfile("tasks/sensors/lib/smartfuel.lua"))()

local log
local tasks

local interval = 1
local lastWake = os.clock()

local firstWakeup = true

local smart_sensors = {
    armed = {
        name = "Armed",
        appId = 0x5FE0,
        unit = UNIT_RAW,
        minimum = -2000,
        maximum = 2000,
        value = function()

            if system:getVersion().simulation then
                local simValue = ofs3.utils.simSensors('armed')
                if simValue == nil then return nil end
                return simValue == 0 and 1 or 0
            end

            local value = ofs3.session.rx.values['arm']
            if value then
                if value >= 500 then
                    return 0
                else
                    return 1
                end
            end
        end
    },
    profile = {
        name = "Profile",
        appId = 0x5FE1,
        unit = UNIT_RAW,
        minimum = -2000,
        maximum = 2000,
        value = function()

            if system:getVersion().simulation then
                local simValue = ofs3.utils.simSensors('profile')
                return simValue or 1
            end

            local value = ofs3.session.rx.values['headspeed']
            if value then
                if value < -500 then
                    return 1
                elseif value > 500 then
                    return 3
                else
                    return 2
                end
            end
        end
    },
    smartfuel = {name = "Smart Fuel", appId = 0x5FDF, unit = UNIT_PERCENT, minimum = 0, maximum = 100, value = smartfuel.calculate}
}

smart.sensors = msp_sensors
local sensorCache = {}

local function createOrUpdateSensor(appId, fieldMeta, value)
    if not sensorCache[appId] then
        local existingSensor = system.getSource({category = CATEGORY_TELEMETRY_SENSOR, appId = appId})

        if existingSensor then
            sensorCache[appId] = existingSensor
        else
            local sensor = model.createSensor({type = SENSOR_TYPE_DIY})
            sensor:name(fieldMeta.name)
            sensor:appId(appId)
            sensor:physId(0)
            sensor:module(ofs3.session.telemetrySensor:module())

            if fieldMeta.unit then
                sensor:unit(fieldMeta.unit)
                sensor:protocolUnit(fieldMeta.unit)
            end
            sensor:minimum(fieldMeta.minimum or -1000000000)
            sensor:maximum(fieldMeta.maximum or 1000000000)

            sensorCache[appId] = sensor
        end
    end

    if value then
        sensorCache[appId]:value(value)
    else
        sensorCache[appId]:reset()
    end
end

local lastWakeupTime = 0
function smart.wakeup()

    if firstWakeup then
        log = ofs3.utils.log
        tasks = ofs3.tasks
        firstWakeup = false
    end

    if (os.clock() - lastWake) < interval then return end
    lastWake = os.clock()

    for name, meta in pairs(smart_sensors) do
        local value
        if type(meta.value) == "function" then
            value = meta.value()
        else
            value = meta.value
        end
        createOrUpdateSensor(meta.appId, meta, value)

    end
end

function smart.reset() sensorCache = {} end

return smart
