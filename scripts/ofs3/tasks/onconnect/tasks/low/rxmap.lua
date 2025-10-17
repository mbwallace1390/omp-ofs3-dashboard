--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local rxmap = {}

function rxmap.wakeup()

    if ofs3.session.apiVersion == nil then return end

    if not ofs3.utils.rxmapReady() then

        ofs3.session.rx.map.aileron = 0
        ofs3.session.rx.map.elevator = 1
        ofs3.session.rx.map.collective = 2
        ofs3.session.rx.map.rudder = 3
        ofs3.session.rx.map.arm = 4
        ofs3.session.rx.map.throttle = 5
        ofs3.session.rx.map.mode = 6
        ofs3.session.rx.map.headspeed = 7

    end

end

function rxmap.reset()
    ofs3.session.rxmap = {}
    ofs3.session.rxvalues = {}
end

function rxmap.isComplete() return ofs3.utils.rxmapReady() end

return rxmap
