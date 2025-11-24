--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local timer = {}

local runOnce = false

function timer.wakeup()
    ofs3.session.timer = {}
    ofs3.session.timer.start = nil
    ofs3.session.timer.live = nil
    ofs3.session.timer.lifetime = nil
    ofs3.session.timer.session = 0
    runOnce = true

end

function timer.reset() runOnce = false end

function timer.isComplete() return runOnce end

return timer
