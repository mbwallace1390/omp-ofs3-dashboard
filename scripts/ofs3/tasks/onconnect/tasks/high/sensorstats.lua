--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local sensorstats = {}

local runOnce = false

function sensorstats.wakeup()
    if ofs3.tasks.telemetry then
        ofs3.tasks.telemetry.sensorStats = {}
        runOnce = true
    end
end

function sensorstats.reset() runOnce = false end

function sensorstats.isComplete() return runOnce end

return sensorstats
