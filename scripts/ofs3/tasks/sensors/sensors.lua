--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local arg = {...}
local config = arg[1]

local sensors = {}
local loadedSensorModule = nil

local delayDuration = 2
local delayStartTime = nil
local delayPending = false

local smart = assert(loadfile("tasks/sensors/smart.lua"))(config)

local log = ofs3.utils.log
local tasks = ofs3.tasks

local function loadSensorModule()
    if not tasks.active() then return nil end
    if not ofs3.session.apiVersion then return nil end

    local protocol = "crsf"

    if system:getVersion().simulation == true then
        if not loadedSensorModule or loadedSensorModule.name ~= "sim" then loadedSensorModule = {name = "sim", module = assert(loadfile("tasks/sensors/sim.lua"))(config)} end
    else
        loadedSensorModule = nil
    end
end

function sensors.wakeup()

    if ofs3.session.resetSensors and not delayPending then
        delayStartTime = os.clock()
        delayPending = true
        ofs3.session.resetSensors = false
        log("Delaying sensor wakeup for " .. delayDuration .. " seconds", "info")
        return
    end

    if delayPending then
        if os.clock() - delayStartTime >= delayDuration then
            log("Delay complete; resuming sensor wakeup", "info")
            delayPending = false
        else
            local module = model.getModule(ofs3.session.telemetrySensor:module())
            if module ~= nil and module.muteSensorLost ~= nil then module:muteSensorLost(5.0) end
            return
        end
    end

    loadSensorModule()
    if loadedSensorModule and loadedSensorModule.module.wakeup then loadedSensorModule.module.wakeup() end

    if smart and smart.wakeup then smart.wakeup() end

end

function sensors.reset()

    if loadedSensorModule and loadedSensorModule.module and loadedSensorModule.module.reset then loadedSensorModule.module.reset() end

    loadedSensorModule = nil

end

return sensors
