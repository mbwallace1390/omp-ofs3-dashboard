--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local apiversion = {}

function apiversion.wakeup() ofs3.session.apiVersion = 12.07 end

function apiversion.reset() ofs3.session.apiVersion = nil end

function apiversion.isComplete() if ofs3.session.apiVersion ~= nil then return true end end

return apiversion
