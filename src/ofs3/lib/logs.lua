--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local logs = {}

local ROOT_DIR = "LOGS:"
local BASE_DIR = "LOGS:/ofs3"
local TELEMETRY_DIR = "LOGS:/ofs3/telemetry"
local SAMPLE_INTERVAL_SECONDS = 1

local LOG_COLUMNS = {
    "time",
    "voltage",
    "current",
    "rpm",
    "temp_esc",
    "consumption",
    "smartfuel",
    "profile",
    "throttle_percent"
}

local activeLog = nil

local function ensureDirectories()
    os.mkdir(ROOT_DIR)
    os.mkdir(BASE_DIR)
    os.mkdir(TELEMETRY_DIR)
end

local function extractSortKey(name)
    if type(name) ~= "string" then
        return ""
    end

    local date, time, unique = name:match("^(%d%d%d%d%-%d%d%-%d%d)_(%d%d%-%d%d%-%d%d)_?(%d*)%.csv$")
    if date and time then
        return string.format("%sT%s_%s", date, time, unique or "")
    end

    return name
end

local function fileExists(path)
    local file = io.open(path, "r")
    if not file then
        return false
    end

    file:close()
    return true
end

local function dateFileStem(now)
    local ok, value = pcall(os.date, "%Y-%m-%d_%H-%M-%S", now)
    if ok and type(value) == "string" and value ~= "" then
        return value
    end

    return "flight_" .. tostring(now or os.time())
end

local function createLogPath()
    ensureDirectories()

    local stem = dateFileStem(os.time())
    local filename = stem .. ".csv"
    local path = TELEMETRY_DIR .. "/" .. filename
    local suffix = 1

    while fileExists(path) do
        filename = stem .. "_" .. tostring(suffix) .. ".csv"
        path = TELEMETRY_DIR .. "/" .. filename
        suffix = suffix + 1
    end

    return filename, path
end

local function writeLine(path, line, mode)
    local file = io.open(path, mode or "a")
    if not file then
        return false
    end

    file:write(line)
    file:write("\n")
    file:close()
    return true
end

local function formatValue(value)
    if type(value) ~= "number" then
        return ""
    end

    if math.floor(value) == value then
        return tostring(value)
    end

    return string.format("%.2f", value)
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function getThrottlePercent()
    local rx = ofs3.session and ofs3.session.rx
    local values = rx and rx.values
    local throttle = values and tonumber(values.throttle)

    if throttle == nil then
        return nil
    end

    return clamp(((throttle + 1024) / 2048) * 100, 0, 100)
end

local function getTelemetryValue(sensorKey)
    local telemetry = ofs3.tasks and ofs3.tasks.telemetry
    if not telemetry or not telemetry.getSensor then
        return nil
    end

    local value = telemetry.getSensor(sensorKey)
    if type(value) == "number" then
        return value
    end

    return nil
end

local function buildSampleLine(now)
    local startedAt = activeLog and activeLog.startedAt or now
    local elapsed = math.max(0, now - startedAt)

    local values = {
        elapsed,
        getTelemetryValue("voltage"),
        getTelemetryValue("current"),
        getTelemetryValue("rpm"),
        getTelemetryValue("temp_esc"),
        getTelemetryValue("consumption"),
        getTelemetryValue("smartfuel"),
        getTelemetryValue("profile"),
        getThrottlePercent()
    }

    local out = {}
    for index = 1, #LOG_COLUMNS do
        out[index] = formatValue(values[index])
    end

    return table.concat(out, ",")
end

local function startLog(now)
    if activeLog then
        return true
    end

    local filename, path = createLogPath()
    if not writeLine(path, table.concat(LOG_COLUMNS, ","), "w") then
        ofs3.utils.log("[logs] failed to create telemetry log: " .. tostring(path))
        return false
    end

    activeLog = {
        filename = filename,
        path = path,
        startedAt = now,
        lastSampleAt = nil,
        samples = 0
    }

    ofs3.utils.log("[logs] started telemetry log: " .. tostring(filename))
    return true
end

local function appendSample(now)
    if not activeLog then
        return false
    end

    if activeLog.lastSampleAt and (now - activeLog.lastSampleAt) < SAMPLE_INTERVAL_SECONDS then
        return true
    end

    if writeLine(activeLog.path, buildSampleLine(now), "a") then
        activeLog.lastSampleAt = now
        activeLog.samples = (activeLog.samples or 0) + 1
        return true
    end

    ofs3.utils.log("[logs] failed to append telemetry log: " .. tostring(activeLog.path))
    activeLog = nil
    return false
end

function logs.getDirectory()
    ensureDirectories()
    return TELEMETRY_DIR
end

function logs.getRecentEntries(limit)
    ensureDirectories()

    local files = system.listFiles(TELEMETRY_DIR) or {}
    local entries = {}

    for _, name in ipairs(files) do
        if type(name) == "string" and name:match("%.csv$") then
            entries[#entries + 1] = {
                name = name,
                sortKey = extractSortKey(name)
            }
        end
    end

    table.sort(entries, function(a, b)
        return (a.sortKey or "") > (b.sortKey or "")
    end)

    if limit and #entries > limit then
        for index = #entries, limit + 1, -1 do
            entries[index] = nil
        end
    end

    return entries
end

function logs.wakeup(flightMode)
    local now = os.time()

    if flightMode == "inflight" then
        if startLog(now) then
            appendSample(now)
        end
        return
    end

    if activeLog then
        ofs3.utils.log(string.format("[logs] finished telemetry log: %s (%d samples)", tostring(activeLog.filename), tonumber(activeLog.samples) or 0))
        activeLog = nil
    end
end

function logs.reset()
    activeLog = nil
end

function logs.formatDuration(seconds)
    local total = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    local secs = total % 60

    if hours > 0 then
        return string.format("%dh %02dm %02ds", hours, minutes, secs)
    end

    return string.format("%dm %02ds", minutes, secs)
end

function logs.getSummary()
    local prefs = ofs3.session and ofs3.session.modelPreferences or nil

    return {
        craftName = (ofs3.session and ofs3.session.craftName) or (model.name and model.name()) or "Model",
        flightCount = tonumber(ofs3.ini.getvalue(prefs, "general", "flightcount")) or 0,
        lastFlightTime = tonumber(ofs3.ini.getvalue(prefs, "general", "lastflighttime")) or 0,
        totalFlightTime = tonumber(ofs3.ini.getvalue(prefs, "general", "totalflighttime")) or 0
    }
end

return logs
