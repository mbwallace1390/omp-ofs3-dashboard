--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local battery = {}

function battery.wakeup()

    if ofs3.session.apiVersion == nil then return end

    if (ofs3.session.batteryConfig == nil) then

        ofs3.session.batteryConfig = {}
        ofs3.session.batteryConfig.batteryCapacity = 750
        ofs3.session.batteryConfig.batteryCellCount = 3
        ofs3.session.batteryConfig.vbatwarningcellvoltage = 3.5
        ofs3.session.batteryConfig.vbatmincellvoltage = 3.3
        ofs3.session.batteryConfig.vbatmaxcellvoltage = 4.3
        ofs3.session.batteryConfig.vbatfullcellvoltage = 4.1
        ofs3.session.batteryConfig.lvcPercentage = 30
        ofs3.session.batteryConfig.consumptionWarningPercentage = 30

    end

end

function battery.reset() ofs3.session.batteryConfig = nil end

function battery.isComplete() if ofs3.session.batteryConfig ~= nil then return true end end

return battery
