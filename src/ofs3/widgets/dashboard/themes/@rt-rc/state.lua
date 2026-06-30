--[[ Aegis OFS3 live state manager - GPLv3 ]] --
local ofs3 = require("ofs3")

if ofs3.aegisStateManager then return ofs3.aegisStateManager end

local M = {}
local telemetry = ofs3.tasks.telemetry
local abs, floor, max, min = math.abs, math.floor, math.max, math.min
local tonumber, tostring = tonumber, tostring
local ACTIVE_RPM = 250
local THROTTLE_ACTIVE_PERCENT = 5
local POSTFLIGHT_DELAY = 2.0
local STATS_INTERVAL = 0.25
local trackedStats = {"rssi", "voltage", "rpm", "current", "temp_esc", "consumption", "smartfuel"}
local state = {mode="preflight",hasBeenInFlight=false,lastActiveAt=0,timerStart=nil,timerBase=0,lastStatsAt=0,diagnostics={}}

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
local function channelHigh(v)
    v = tonumber(v); if v == nil then return false end
    if abs(v) <= 1.5 then return v > 0.2 end
    if abs(v) <= 100 then return v > 25 end
    return v >= 500
end
local function throttlePercent(v)
    v = tonumber(v); if v == nil then return nil end
    if v >= -1024 and v <= 1024 then return clamp((v + 1024) * 100 / 2048, 0, 100) end
    if v >= 0 and v <= 100 then return v end
    if v >= -1.5 and v <= 1.5 then return clamp((v + 1) * 50, 0, 100) end
    return clamp(v, 0, 100)
end
local function readSignals()
    local rx = ofs3.session and ofs3.session.rx
    local values = rx and rx.values or {}
    local rpm = tonumber(telemetry.getSensor("rpm")) or 0
    local armRaw = tonumber(values.arm)
    local throttleRaw = tonumber(values.throttle)
    local throttle = throttlePercent(throttleRaw)
    local rpmActive = rpm > ACTIVE_RPM
    local armActive = channelHigh(armRaw)
    local throttleActive = throttle ~= nil and throttle > THROTTLE_ACTIVE_PERCENT
    local active = rpmActive or armActive or throttleActive
    local source = rpmActive and "RPM" or (armActive and "ARM" or (throttleActive and "THR" or "IDLE"))
    return {rpm=rpm,armRaw=armRaw,throttleRaw=throttleRaw,throttle=throttle,rpmActive=rpmActive,armActive=armActive,throttleActive=throttleActive,active=active,source=source,protocol=ofs3.session and ofs3.session.telemetryType or "--"}
end
local function resetState()
    state.mode="preflight"; state.hasBeenInFlight=false; state.lastActiveAt=0; state.timerStart=nil; state.timerBase=0; state.lastStatsAt=0; state.diagnostics={}
end
local function updateTimer(mode)
    local timer = ofs3.session and ofs3.session.timer
    if not timer then return end
    local now = os.time()
    if mode == "inflight" then
        if not state.timerStart then state.timerStart=now; state.timerBase=tonumber(timer.session) or tonumber(timer.live) or 0 end
        timer.live = state.timerBase + max(0, now - state.timerStart)
    elseif mode == "postflight" then
        if state.timerStart then timer.session=state.timerBase+max(0,now-state.timerStart); timer.live=timer.session; state.timerStart=nil
        else timer.live=tonumber(timer.session) or tonumber(timer.live) or 0 end
    else timer.live=tonumber(timer.session) or 0 end
end
local function updateStats(mode)
    if mode ~= "inflight" or not (ofs3.session and ofs3.session.isConnected) then return end
    local now=os.clock(); if now-state.lastStatsAt < STATS_INTERVAL then return end; state.lastStatsAt=now
    telemetry.sensorStats=telemetry.sensorStats or {}
    for _,key in ipairs(trackedStats) do
        local value=tonumber(telemetry.getSensor(key))
        if value ~= nil then
            local s=telemetry.sensorStats[key]
            if not s then s={min=math.huge,max=-math.huge,sum=0,count=0,avg=0}; telemetry.sensorStats[key]=s end
            s.min=min(s.min,value); s.max=max(s.max,value); s.sum=s.sum+value; s.count=s.count+1; s.avg=s.sum/s.count
        end
    end
end
local function updateMode(result)
    if result and (result.model_changed or result.flight_reset) then resetState() end
    local signals=readSignals(); local now=os.clock(); local previous=state.mode
    if signals.active then state.lastActiveAt=now; state.hasBeenInFlight=true; state.mode="inflight"
    elseif state.hasBeenInFlight then state.mode=(now-state.lastActiveAt >= POSTFLIGHT_DELAY) and "postflight" or "inflight"
    else state.mode="preflight" end
    signals.mode=state.mode; state.diagnostics=signals; ofs3.session.aegisState=signals; ofs3.flightmode.current=state.mode
    updateTimer(state.mode); updateStats(state.mode)
    if result then result.flightmode_changed=result.flightmode_changed or previous~=state.mode; result.aegis_mode=state.mode end
end
function M.install(common)
    if common then
        common.flightState=function()
            local d=state.diagnostics or readSignals()
            if d.active then return "ARMED", common.C.red, true end
            return "DISARMED", common.C.green, false
        end
    end
    if not ofs3.runtime._aegisOriginalWakeup then
        ofs3.runtime._aegisOriginalWakeup=ofs3.runtime.wakeup
        ofs3.runtime.wakeup=function(...)
            local result=ofs3.runtime._aegisOriginalWakeup(...) or {}
            updateMode(result)
            return result
        end
    end
    return M
end
function M.getDiagnostics()
    local d=state.diagnostics
    if not d or next(d)==nil then d=readSignals() end
    return d
end
function M.diagnosticText()
    local d=M.getDiagnostics()
    local arm=d.armRaw==nil and "--" or tostring(floor(d.armRaw+0.5))
    local throttle=d.throttle==nil and "--" or tostring(floor(d.throttle+0.5)).."%"
    local rpm=tostring(floor((d.rpm or 0)+0.5))
    return string.format("%s A:%s T:%s R:%s", tostring(d.source or "IDLE"), arm, throttle, rpm)
end
ofs3.aegisStateManager=M
return M
