--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local arg = {...}
local config = arg[1]

local timer = {}
local lastFlightMode = nil

function timer.reset()
    ofs3.utils.log("Resetting flight timers", "info")
    lastFlightMode = nil

    local timerSession = {}
    ofs3.session.timer = timerSession
    ofs3.session.flightCounted = false

    timerSession.baseLifetime = tonumber(ofs3.ini.getvalue(ofs3.session.modelPreferences, "general", "totalflighttime")) or 0

    timerSession.session = 0
    timerSession.lifetime = timerSession.baseLifetime
end

function timer.save()
    local prefs = ofs3.session.modelPreferences
    local prefsFile = ofs3.session.modelPreferencesFile

    if not prefsFile then
        ofs3.utils.log("No model preferences file set, cannot save flight timers", "info")
        return
    end

    ofs3.utils.log("Saving flight timers to INI: " .. prefsFile, "info")

    if prefs then
        ofs3.ini.setvalue(prefs, "general", "totalflighttime", ofs3.session.timer.baseLifetime or 0)
        ofs3.ini.setvalue(prefs, "general", "lastflighttime", ofs3.session.timer.session or 0)
        ofs3.ini.save_ini_file(prefsFile, prefs)
    end
end

local function finalizeFlightSegment(now)
    local timerSession = ofs3.session.timer
    local prefs = ofs3.session.modelPreferences

    local segment = now - timerSession.start
    timerSession.session = (timerSession.session or 0) + segment
    timerSession.start = nil

    if timerSession.baseLifetime == nil then timerSession.baseLifetime = tonumber(ofs3.ini.getvalue(prefs, "general", "totalflighttime")) or 0 end

    timerSession.baseLifetime = timerSession.baseLifetime + segment
    timerSession.lifetime = timerSession.baseLifetime

    timer.save()
end

function timer.wakeup()
    local now = os.time()
    local timerSession = ofs3.session.timer
    local prefs = ofs3.session.modelPreferences
    local flightMode = ofs3.flightmode.current

    lastFlightMode = flightMode

    if flightMode == "inflight" then
        if not timerSession.start then timerSession.start = now end

        local currentSegment = now - timerSession.start
        timerSession.live = (timerSession.session or 0) + currentSegment

        local computedLifetime = (timerSession.baseLifetime or 0) + currentSegment
        timerSession.lifetime = computedLifetime

        if prefs then ofs3.ini.setvalue(prefs, "general", "totalflighttime", computedLifetime) end

        if timerSession.live >= 25 and not ofs3.session.flightCounted then
            ofs3.session.flightCounted = true

            if prefs and ofs3.ini.section_exists(prefs, "general") then
                local count = ofs3.ini.getvalue(prefs, "general", "flightcount") or 0
                ofs3.ini.setvalue(prefs, "general", "flightcount", count + 1)
                ofs3.ini.save_ini_file(ofs3.session.modelPreferencesFile, prefs)
            end
        end

    else
        timerSession.live = timerSession.session or 0
    end

    if flightMode == "postflight" and timerSession.start then finalizeFlightSegment(now) end
end

return timer
