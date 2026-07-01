--[[
  Aegis dashboard support for OMP OFS3 Dashboard
  GPLv3
]] --

local ofs3 = require("ofs3")
local lcd = lcd
local math = math
local floor = math.floor
local min = math.min
local max = math.max
local tonumber = tonumber
local tostring = tostring
local type = type
local format = string.format

local utils = ofs3.widgets.dashboard.utils
local colorMode = utils.themeColors()
local M = {}

M.DEFAULTS = {
    rpm_max = 2500,
    esc_warn = 110,
    esc_max = 150,
    fuel_warn = 25,
    link_warn = 50
}

M.C = {
    bg = colorMode.tbbgcolor or colorMode.bgcolor or lcd.RGB(7, 11, 16),
    panel = colorMode.tbbgcolor or colorMode.bgcolor or lcd.RGB(14, 21, 29),
    panel2 = colorMode.tbbgcolor or colorMode.bgcolor or lcd.RGB(19, 28, 38),
    line = lcd.RGB(50, 67, 82),
    line2 = lcd.RGB(76, 97, 115),
    white = lcd.RGB(230, 239, 247),
    muted = lcd.RGB(132, 151, 168),
    cyan = lcd.RGB(48, 218, 238),
    green = lcd.RGB(75, 224, 149),
    amber = lcd.RGB(255, 183, 72),
    red = lcd.RGB(255, 86, 103),
    violet = lcd.RGB(174, 133, 255)
}

function M.clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

function M.getConfig(key)
    local prefs = ofs3.session and ofs3.session.modelPreferences
    local section = prefs and prefs["system/aegis"]
    local value = section and tonumber(section[key])
    return value or M.DEFAULTS[key]
end

function M.resolveFont(name)
    if type(name) == "number" then return name end
    if type(name) == "string" and type(_G[name]) == "number" then return _G[name] end
    return FONT_STD
end

function M.drawTextAligned(x, y, w, text, fontName, color, align)
    text = tostring(text or "")
    local font = M.resolveFont(fontName)
    lcd.font(font)
    lcd.color(color or M.C.white)
    local tw, th = lcd.getTextSize(text)
    local tx = x
    if align == "center" then
        tx = x + (w - tw) / 2
    elseif align == "right" then
        tx = x + w - tw
    end
    lcd.drawText(floor(tx + 0.5), floor(y + 0.5), text)
    return tw, th
end

function M.drawPanel(x, y, w, h, accent, title)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    lcd.color(M.C.panel)
    lcd.drawFilledRectangle(x, y, w, h)
    lcd.color(M.C.line)
    lcd.drawRectangle(x, y, w, h, 1)
    lcd.color(accent or M.C.cyan)
    lcd.drawFilledRectangle(x, y, 3, h)
    if title then
        M.drawTextAligned(x + 12, y + 7, w - 22, title, "FONT_XS", M.C.muted, "left")
    end
end

function M.drawMetric(x, y, w, h, title, valueText, accent, subtitle)
    M.drawPanel(x, y, w, h, accent, title)
    M.drawTextAligned(x + 12, y + 26, w - 24, valueText, "FONT_XL", M.C.white, "left")
    if subtitle then
        M.drawTextAligned(x + 12, y + h - 25, w - 24, subtitle, "FONT_XXS", M.C.muted, "left")
    end
end

function M.drawStateBadge(x, y, w, h, label, color)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    color = color or M.C.muted
    lcd.color(M.C.panel)
    lcd.drawFilledRectangle(x, y, w, h)
    lcd.color(M.C.line)
    lcd.drawRectangle(x, y, w, h, 1)
    lcd.color(color)
    lcd.drawFilledRectangle(x, y, 4, h)
    M.drawTextAligned(x + 10, y + 5, w - 18, label or "STATE --", "FONT_XS", color, "center")
end

function M.drawProgress(x, y, w, h, percent, color)
    percent = M.clamp(percent or 0, 0, 1)
    lcd.color(M.C.line)
    lcd.drawRectangle(floor(x), floor(y), floor(w), floor(h), 1)
    if percent > 0 then
        lcd.color(color or M.C.cyan)
        lcd.drawFilledRectangle(floor(x + 2), floor(y + 2), max(1, floor((w - 4) * percent)), max(1, floor(h - 4)))
    end
end

function M.drawSegments(x, y, w, h, percent, count, activeColor)
    count = count or 10
    percent = M.clamp(percent or 0, 0, 100)
    local gap = 4
    local segmentWidth = floor((w - gap * (count - 1)) / count)
    if segmentWidth < 2 then return end
    local active = percent > 0 and max(1, min(count, floor(percent * count / 100 + 0.999))) or 0
    for index = 1, count do
        local sx = x + (index - 1) * (segmentWidth + gap)
        if index <= active then
            lcd.color(activeColor or M.C.cyan)
            lcd.drawFilledRectangle(floor(sx), floor(y), segmentWidth, floor(h))
        else
            lcd.color(M.C.line)
            lcd.drawRectangle(floor(sx), floor(y), segmentWidth, floor(h), 1)
        end
    end
end

function M.drawHex(x, y, radius, color)
    local sin = math.sin
    local cos = math.cos
    local rad = math.rad
    local points = {}
    for index = 0, 5 do
        local angle = rad(30 + index * 60)
        points[index + 1] = {x + cos(angle) * radius, y + sin(angle) * radius}
    end
    lcd.color(color or M.C.cyan)
    for index = 1, 6 do
        local a = points[index]
        local b = points[(index % 6) + 1]
        lcd.drawLine(floor(a[1]), floor(a[2]), floor(b[1]), floor(b[2]))
    end
end

function M.formatValue(value, decimals, suffix, missing)
    if value == nil then return missing or "--" end
    local text
    if decimals == 1 then
        text = format("%.1f", value)
    elseif decimals == 2 then
        text = format("%.2f", value)
    else
        text = tostring(floor(value + 0.5))
    end
    return text .. (suffix or "")
end

function M.sensor(telemetry, key)
    if not (telemetry and telemetry.getSensor) then return nil end
    local value = telemetry.getSensor(key)
    return tonumber(value)
end

function M.stat(telemetry, key, kind)
    if telemetry and telemetry.getSensorStats then
        local stats = telemetry.getSensorStats(key)
        return stats and tonumber(stats[kind]) or nil
    end
    local stats = telemetry and telemetry.sensorStats and telemetry.sensorStats[key]
    return stats and tonumber(stats[kind]) or nil
end

function M.flightSeconds()
    local timer = ofs3.session and ofs3.session.timer
    return max(0, tonumber(timer and timer.live) or 0)
end

function M.flightTimeText()
    local seconds = M.flightSeconds()
    return format("%02d:%02d", floor(seconds / 60), floor(seconds % 60))
end

function M.throttlePercent()
    local rx = ofs3.session and ofs3.session.rx
    local value = rx and rx.values and tonumber(rx.values.throttle)
    if value == nil then return nil end

    if value >= 0 and value <= 100 then return value end
    if value >= -1.5 and value <= 1.5 then return M.clamp((value + 1) * 50, 0, 100) end
    return M.clamp((value + 1024) * 100 / 2048, 0, 100)
end

function M.flightState(telemetry)
    local armed = M.sensor(telemetry, "armed")
    if armed == 0 then return "ARMED", M.C.red, true end
    if armed == 1 then return "DISARMED", M.C.green, false end
    return "STATE --", M.C.muted, nil
end

function M.packLimits()
    local battery = ofs3.session and ofs3.session.batteryConfig or {}
    local cells = tonumber(battery.batteryCellCount) or 3
    local criticalCell = tonumber(battery.vbatmincellvoltage) or 3.3
    local warningCell = tonumber(battery.vbatwarningcellvoltage) or 3.5
    local fullCell = tonumber(battery.vbatfullcellvoltage) or 4.1
    return cells * criticalCell, cells * warningCell, cells * fullCell
end

function M.packColor(value)
    if value == nil then return M.C.muted end
    local critical, warning = M.packLimits()
    if value < critical then return M.C.red end
    if value < warning then return M.C.amber end
    return M.C.cyan
end

function M.escColor(value)
    if value == nil then return M.C.muted end
    if value >= M.getConfig("esc_max") then return M.C.red end
    if value >= M.getConfig("esc_warn") then return M.C.amber end
    return M.C.green
end

function M.fuelColor(value)
    if value == nil then return M.C.muted end
    if value <= M.getConfig("fuel_warn") then return M.C.red end
    if value <= 50 then return M.C.amber end
    return M.C.green
end

function M.linkColor(value)
    if value == nil then return M.C.muted end
    if value < M.getConfig("link_warn") then return M.C.amber end
    return M.C.cyan
end

function M.headerLayout()
    local options = utils.getHeaderOptions()
    return {height = options.height, cols = 7, rows = 1, padding = 0}
end

function M.headerBoxes()
    local options = utils.getHeaderOptions()
    local C = M.C
    return {
        {
            col = 1, row = 1, colspan = 2,
            type = "text", subtype = "craftname",
            font = options.font, valuealign = "left", valuepaddingleft = 5,
            bgcolor = colorMode.bgcolortop, textcolor = colorMode.textcolor
        },
        {
            col = 3, row = 1, colspan = 3,
            type = "func", subtype = "func", bgcolor = "transparent",
            paint = function(x, y, w, h)
                lcd.color(colorMode.bgcolortop or C.bg)
                lcd.drawFilledRectangle(floor(x), floor(y), floor(w), floor(h))
                local font = M.resolveFont("FONT_L")
                lcd.font(font)
                local first, divider, last = "ETHOS ", "// ", "OFS3"
                local w1, textHeight = lcd.getTextSize(first)
                local w2 = lcd.getTextSize(divider)
                local w3 = lcd.getTextSize(last)
                local tx = floor(x + (w - w1 - w2 - w3) / 2)
                local ty = floor(y + (h - textHeight) / 2)
                lcd.color(C.cyan)
                lcd.drawText(tx, ty, first)
                lcd.color(C.amber)
                lcd.drawText(tx + w1, ty, divider)
                lcd.color(C.white)
                lcd.drawText(tx + w1 + w2, ty, last)
            end
        },
        {
            col = 6, row = 1,
            type = "gauge", subtype = "bar", source = "txbatt",
            battery = true, batteryframe = true, hidevalue = true,
            batterysegments = 4, batteryspacing = 1, batteryframethickness = 2,
            gaugepaddingright = options.gaugepaddingright,
            gaugepaddingleft = options.gaugepaddingleft,
            gaugepaddingbottom = options.gaugepaddingbottom,
            gaugepaddingtop = options.gaugepaddingtop,
            batterysegmentpaddingtop = options.batterysegmentpaddingtop,
            batterysegmentpaddingbottom = options.batterysegmentpaddingbottom,
            batterysegmentpaddingleft = options.batterysegmentpaddingleft,
            batterysegmentpaddingright = options.batterysegmentpaddingright,
            fillbgcolor = colorMode.txbgfillcolor,
            fillcolor = colorMode.txfillcolor,
            accentcolor = colorMode.txaccentcolor,
            bgcolor = colorMode.bgcolortop,
            min = 7.2, max = 8.4
        },
        {
            col = 7, row = 1,
            type = "gauge", subtype = "step", source = "rssi",
            font = "FONT_XS", stepgap = 2, stepcount = 5, decimals = 0,
            hidevalue = true,
            barpaddingleft = options.barpaddingleft,
            barpaddingright = options.barpaddingright,
            barpaddingbottom = options.barpaddingbottom,
            barpaddingtop = options.barpaddingtop,
            valuepaddingleft = options.valuepaddingleft,
            valuepaddingbottom = options.valuepaddingbottom,
            bgcolor = colorMode.bgcolortop,
            textcolor = colorMode.textcolor,
            fillcolor = colorMode.rssifillcolor,
            fillbgcolor = colorMode.rssifillbgcolor
        }
    }
end

return M
