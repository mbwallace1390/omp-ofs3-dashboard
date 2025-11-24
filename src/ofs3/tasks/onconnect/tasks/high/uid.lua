--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local uid = {}

function uid.wakeup() if ofs3.session.mcu_id == nil then ofs3.session.mcu_id = "a3e5f2d7-9c4b-4e6a-b8f1-3d7e2c9a1f45" end end

function uid.reset() ofs3.session.mcu_id = nil end

function uid.isComplete() if ofs3.session.mcu_id ~= nil then return true end end

return uid
