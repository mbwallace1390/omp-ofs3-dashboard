--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local arg = {...}
local config = arg[1]

local flightmode = {}
local lastFlightMode = nil
local hasBeenInFlight = false

function flightmode.inFlight()
    local telemetry = ofs3.tasks.telemetry

    if not telemetry.active() then return false end

    local rpm = telemetry.getSensor("rpm")
    local armed = telemetry.getSensor("armed")
    if armed == 0 then if rpm and rpm > 1000 then return true end end
    return false
end

function flightmode.reset()
    lastFlightMode = nil
    hasBeenInFlight = false
end

local function determineMode()
    if ofs3.flightmode.current == "inflight" and not ofs3.session.isConnected then
        hasBeenInFlight = false
        return "postflight"
    end
    if flightmode.inFlight() then
        hasBeenInFlight = true
        return "inflight"
    end

    return hasBeenInFlight and "postflight" or "preflight"
end

function flightmode.wakeup()
    local mode = determineMode()

    if lastFlightMode ~= mode then
        ofs3.utils.log("Flight mode: " .. mode, "info")
        ofs3.flightmode.current = mode
        lastFlightMode = mode
    end
end

return flightmode
