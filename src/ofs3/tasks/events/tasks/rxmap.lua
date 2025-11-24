--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local arg = {...}
local config = arg[1]

local rxmap = {}

local channelNames = {"aileron", "elevator", "collective", "rudder", "arm", "throttle", "headspeed", "mode"}

local channelSources = {}
local initialized = false

local function initChannelSources()
    local rxMap = ofs3.session.rx.map
    for _, name in ipairs(channelNames) do
        local member = rxMap[name]
        if member then
            local src = system.getSource({category = CATEGORY_CHANNEL, member = member, options = 0})
            if src then channelSources[name] = src end
        end
    end
    initialized = true
end

function rxmap.wakeup()
    if not ofs3.utils.rxmapReady() then return end

    if not initialized then initChannelSources() end

    for name, src in pairs(channelSources) do
        if src then
            local val = src:value()
            if val ~= nil then ofs3.session.rx.values[name] = val end
        end
    end
end

function rxmap.reset()
    channelSources = {}
    initialized = false
end

return rxmap
