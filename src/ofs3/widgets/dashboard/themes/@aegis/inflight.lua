--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html

  Ported from the author's standalone "Aegis" theme (built for the
  rfsuite/Rotorflight dashboard framework) to run natively on ofs3.
  Substitutions for telemetry ofs3 doesn't have:
  - bec_voltage -> main pack voltage (cell-scaled thresholds)
  - link/vfr -> rssi
  - throttle_percent (no ofs3 sensor) -> flight profile
  - armflags/governor-driven arm state -> the real "armed" sensor
  See the PR description for the full list.
]] --

local ofs3 = require("ofs3")
local lcd = lcd
local math = math
local floor = math.floor
local min = math.min
local max = math.max
local sin = math.sin
local cos = math.cos
local rad = math.rad
local tonumber = tonumber
local tostring = tostring
local type = type
local format = string.format

local utils = ofs3.widgets.dashboard.utils
local headeropts = utils.getHeaderOptions()
local colorMode = utils.themeColors()
local header_layout = {height = headeropts.height, cols = 7, rows = 1, padding = 0}
local C

local function resolveFont(name)
    return _G[name]
end

local HEADER_TEXT_1 = "ETHOS "
local HEADER_TEXT_2 = "// "
local HEADER_TEXT_3 = "OFS3"
local HEADER_WATERMARK = "MWRC"

local function paintHeaderLogo(x, y, w, h, box)
    x, y = utils.applyOffset(x, y, box)

    local headerBg = colorMode.tbbgcolor or colorMode.bgcolor
    if type(headerBg) == "number" then
        lcd.color(headerBg)
        lcd.drawFilledRectangle(floor(x), floor(y), floor(w), floor(h))
    end

    local font = resolveFont("FONT_L")
    if type(font) ~= "number" then return end
    lcd.font(font)

    local tw1, th = lcd.getTextSize(HEADER_TEXT_1)
    local tw2 = lcd.getTextSize(HEADER_TEXT_2)
    local tw3 = lcd.getTextSize(HEADER_TEXT_3)

    local watermarkFont = resolveFont("FONT_XS")
    local watermarkWidth, watermarkHeight = 0, 0
    if type(watermarkFont) == "number" then
        lcd.font(watermarkFont)
        watermarkWidth, watermarkHeight = lcd.getTextSize(HEADER_WATERMARK)
        lcd.font(font)
    end

    local titleW = tw1 + tw2 + tw3
    local dividerGap = watermarkWidth > 0 and 14 or 0
    local totalW = titleW + dividerGap + watermarkWidth
    local tx = floor(x + (w - totalW) / 2)
    local ty = floor(y + (h - th) / 2)

    lcd.color(C.cyan)
    lcd.drawText(tx, ty, HEADER_TEXT_1)
    lcd.color(C.amber)
    lcd.drawText(tx + tw1, ty, HEADER_TEXT_2)
    lcd.color(C.white)
    lcd.drawText(tx + tw1 + tw2, ty, HEADER_TEXT_3)

    if watermarkWidth > 0 then
        local dividerX = tx + titleW + 6
        lcd.color(C.line2)
        lcd.drawLine(dividerX, y + 7, dividerX, y + h - 7)
        lcd.font(watermarkFont)
        lcd.color(C.cyan)
        lcd.drawText(dividerX + 7, floor(y + (h - watermarkHeight) / 2), HEADER_WATERMARK)
    end
end

local THEME_SECTION = "system/@aegis"
local DEFAULTS = {
    rpm_max = 5800,
    esc_warn = 110,
    esc_max = 150,
    fuel_warn = 25,
    link_warn = 50
}

C = {
    bg = lcd.RGB(7, 11, 16),
    panel = lcd.RGB(14, 21, 29),
    panel2 = lcd.RGB(19, 28, 38),
    line = lcd.RGB(50, 67, 82),
    line2 = lcd.RGB(76, 97, 115),
    white = lcd.RGB(230, 239, 247),
    muted = lcd.RGB(132, 151, 168),
    cyan = lcd.RGB(48, 218, 238),
    cyanDim = lcd.RGB(17, 75, 86),
    green = lcd.RGB(75, 224, 149),
    greenDim = lcd.RGB(18, 79, 54),
    amber = lcd.RGB(255, 183, 72),
    amberDim = lcd.RGB(93, 61, 17),
    red = lcd.RGB(255, 86, 103),
    redDim = lcd.RGB(91, 25, 35),
    violet = lcd.RGB(174, 133, 255),
    violetDim = lcd.RGB(55, 41, 88)
}

-- Use the radio's actual header surface for the dashboard and every panel.
C.bg = colorMode.tbbgcolor or colorMode.bgcolor or C.bg
C.panel = C.bg
C.panel2 = C.bg

local TX_SECTION = "system/@default"
local TX_DEFAULTS = {tx_min = 7.2, tx_warn = 7.4, tx_max = 8.4}

local function getThemeValue(key)
    if key == "tx_min" or key == "tx_warn" or key == "tx_max" then
        local prefs = ofs3.session and ofs3.session.modelPreferences and ofs3.session.modelPreferences[TX_SECTION]
        local value = prefs and tonumber(prefs[key])
        return value or TX_DEFAULTS[key]
    end

    local prefs = ofs3.session and ofs3.session.modelPreferences and ofs3.session.modelPreferences[THEME_SECTION]
    local value = prefs and tonumber(prefs[key])
    return value or DEFAULTS[key]
end

local function header_boxes()
    return {
        {col = 1, row = 1, colspan = 2, type = "text", subtype = "craftname", font = headeropts.font, valuealign = "left", valuepaddingleft = 5, bgcolor = "transparent", titlecolor = colorMode.titlecolor, textcolor = colorMode.textcolor},
        {col = 3, row = 1, colspan = 3, type = "func", subtype = "func", paint = paintHeaderLogo, bgcolor = "transparent"}, {
            col = 6,
            row = 1,
            type = "gauge",
            subtype = "bar",
            source = "txbatt",
            font = headeropts.font,
            battery = true,
            batteryframe = true,
            hidevalue = true,
            valuealign = "left",
            batterysegments = 4,
            batteryspacing = 1,
            batteryframethickness = 2,
            batterysegmentpaddingtop = headeropts.batterysegmentpaddingtop,
            batterysegmentpaddingbottom = headeropts.batterysegmentpaddingbottom,
            batterysegmentpaddingleft = headeropts.batterysegmentpaddingleft,
            batterysegmentpaddingright = headeropts.batterysegmentpaddingright,
            gaugepaddingright = headeropts.gaugepaddingright,
            gaugepaddingleft = headeropts.gaugepaddingleft,
            gaugepaddingbottom = headeropts.gaugepaddingbottom,
            gaugepaddingtop = headeropts.gaugepaddingtop,
            fillbgcolor = colorMode.fillbgcolor,
            bgcolor = "transparent",
            accentcolor = colorMode.accentcolor,
            textcolor = colorMode.textcolor,
            min = getThemeValue("tx_min"),
            max = getThemeValue("tx_max"),
            thresholds = {{value = getThemeValue("tx_warn"), fillcolor = C.amber}, {value = getThemeValue("tx_max"), fillcolor = colorMode.accentcolor}}
        }, {
            col = 7,
            row = 1,
            type = "gauge",
            subtype = "step",
            source = "rssi",
            font = "FONT_XS",
            stepgap = 2,
            stepcount = 5,
            decimals = 0,
            valuealign = "left",
            barpaddingleft = headeropts.barpaddingleft,
            barpaddingright = headeropts.barpaddingright,
            barpaddingbottom = headeropts.barpaddingbottom,
            barpaddingtop = headeropts.barpaddingtop,
            valuepaddingleft = headeropts.valuepaddingleft,
            valuepaddingbottom = headeropts.valuepaddingbottom,
            bgcolor = "transparent",
            textcolor = colorMode.textcolor,
            fillcolor = colorMode.accentcolor,
            fillbgcolor = colorMode.fillbgcolor
        }
    }
end

local function packMinV()
    local cfg = ofs3.session.batteryConfig
    local cells = (cfg and cfg.batteryCellCount) or 3
    return cells * ((cfg and cfg.vbatmincellvoltage) or 3.3)
end

local function packWarnV()
    local cfg = ofs3.session.batteryConfig
    local cells = (cfg and cfg.batteryCellCount) or 3
    return cells * ((cfg and cfg.vbatwarningcellvoltage) or 3.5)
end

local function sensor(telemetry, name, alias1, alias2)
    telemetry = telemetry or ofs3.tasks.telemetry
    if not (telemetry and telemetry.getSensor) then return nil end
    local value = telemetry.getSensor(name)
    if value ~= nil then return tonumber(value) end
    if alias1 then
        value = telemetry.getSensor(alias1)
        if value ~= nil then return tonumber(value) end
    end
    if alias2 then
        value = telemetry.getSensor(alias2)
        if value ~= nil then return tonumber(value) end
    end
    return nil
end

local function getFlightState(telemetry)
    telemetry = telemetry or ofs3.tasks.telemetry
    local arm = telemetry and telemetry.getSensor and telemetry.getSensor("armed")
    if arm == nil then return "STATE --", C.muted end
    if arm == 0 then return "ARMED", C.red end
    return "DISARMED", C.green
end

local function fmt(value, decimals, suffix, missing)
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

local function drawTextAligned(x, y, w, text, fontName, color, align)
    local font = resolveFont(fontName)
    if type(font) ~= "number" then return 0, 0 end
    lcd.font(font)
    lcd.color(color)
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

local function drawPanel(x, y, w, h, accent, title)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    lcd.color(C.panel)
    lcd.drawFilledRectangle(x, y, w, h)
    lcd.color(C.line)
    lcd.drawRectangle(x, y, w, h, 1)
    lcd.color(accent or C.cyan)
    lcd.drawFilledRectangle(x, y, 3, h)
    if title then
        drawTextAligned(x + 12, y + 7, w - 22, title, "FONT_XS", C.muted, "left")
    end
end

local function drawStateBadge(x, y, w, h, label, color)
    x, y, w, h = floor(x), floor(y), floor(w), floor(h)
    color = color or C.muted
    lcd.color(C.panel)
    lcd.drawFilledRectangle(x, y, w, h)
    lcd.color(C.line)
    lcd.drawRectangle(x, y, w, h, 1)
    lcd.color(color)
    lcd.drawFilledRectangle(x, y, 4, h)
    drawTextAligned(x + 10, y + 5, w - 18, label or "STATE --", "FONT_XS", color, "center")
end

local function drawMetric(x, y, w, h, title, valueText, accent, subtitle)
    drawPanel(x, y, w, h, accent, title)
    drawTextAligned(x + 12, y + 26, w - 24, valueText, "FONT_XL", C.white, "left")
    if subtitle then
        drawTextAligned(x + 12, y + h - 31, w - 24, subtitle, "FONT_XXS", C.muted, "left")
    end
end

local function drawSegments(x, y, w, h, percent, count, activeColor, emptyColor)
    count = count or 10
    percent = max(0, min(100, percent or 0))
    local gap = 4
    local segW = floor((w - gap * (count - 1)) / count)
    if segW < 2 then return end
    local active = percent > 0 and max(1, min(count, floor(percent * count / 100 + 0.999))) or 0
    for i = 1, count do
        local sx = x + (i - 1) * (segW + gap)
        if i <= active then
            lcd.color(activeColor)
            lcd.drawFilledRectangle(floor(sx), floor(y), segW, floor(h))
        else
            lcd.color(emptyColor or C.line)
            lcd.drawRectangle(floor(sx), floor(y), segW, floor(h), 1)
        end
    end
end

local layout = {cols = 12, rows = 12, padding = 0}

local function flightTimeText()
    local seconds = ofs3.session and ofs3.session.timer and tonumber(ofs3.session.timer.live) or 0
    seconds = max(0, seconds)
    return format("%02d:%02d", floor(seconds / 60), floor(seconds % 60))
end

local function inflightWakeup(box, telemetry)
    local c = box._cache or {maxRpm = 0}
    box._cache = c

    c.rpm = sensor(telemetry, "rpm") or 0
    c.maxRpm = max(c.maxRpm or 0, c.rpm)
    c.profile = sensor(telemetry, "profile")
    c.esc = sensor(telemetry, "temp_esc")
    c.fuel = sensor(telemetry, "smartfuel")
    c.current = sensor(telemetry, "current")
    c.voltage = sensor(telemetry, "voltage")
    c.link = sensor(telemetry, "rssi", "link", "vfr")
    c.consumed = sensor(telemetry, "consumption")
    c.flightState, c.flightStateColor = getFlightState(telemetry)
    c.timer = flightTimeText()

    -- Cache theme thresholds here (wakeup runs at a bounded rate) instead of
    -- calling getThemeValue()/packMinV()/packWarnV() from paint(), which
    -- runs on every invalidate.
    c.escMax = getThemeValue("esc_max")
    c.escWarn = getThemeValue("esc_warn")
    c.fuelWarn = getThemeValue("fuel_warn")
    c.packMin = packMinV()
    c.packWarn = packWarnV()
    c.linkWarn = getThemeValue("link_warn")
    c.rpmMax = getThemeValue("rpm_max")

    return c
end

local function drawRadialGauge(cx, cy, radius, value, maximum, color)
    local startA = 140
    local sweep = 260
    local ticks = 32
    local pct = maximum > 0 and max(0, min(1, value / maximum)) or 0
    local active = floor(ticks * pct + 0.5)

    for i = 0, ticks - 1 do
        local a = rad(startA + sweep * i / (ticks - 1))
        local r1 = radius - 14
        local r2 = radius
        local x1 = cx + cos(a) * r1
        local y1 = cy + sin(a) * r1
        local x2 = cx + cos(a) * r2
        local y2 = cy + sin(a) * r2
        lcd.color(i < active and color or C.line)
        lcd.drawLine(floor(x1), floor(y1), floor(x2), floor(y2))
    end

    lcd.color(C.line2)
    lcd.drawLine(floor(cx - radius * 0.68), floor(cy + radius * 0.72), floor(cx + radius * 0.68), floor(cy + radius * 0.72))
end

local function drawVerticalMeter(x, y, w, h, title, value, maximum, color, unit)
    drawPanel(x, y, w, h, color, title)
    local barX = x + 15
    local barY = y + 34
    local barW = 14
    local barH = h - 52
    local pct = maximum > 0 and max(0, min(1, (value or 0) / maximum)) or 0
    lcd.color(C.line)
    lcd.drawRectangle(floor(barX), floor(barY), floor(barW), floor(barH), 1)
    if pct > 0 then
        local fillH = floor((barH - 4) * pct)
        lcd.color(color)
        lcd.drawFilledRectangle(floor(barX + 2), floor(barY + barH - 2 - fillH), floor(barW - 4), fillH)
    end
    drawTextAligned(x + 38, y + 44, w - 50, fmt(value, 0, unit), "FONT_L", C.white, "left")
end

local function inflightPaint(x, y, w, h, box, c)
    x, y = utils.applyOffset(x, y, box)
    c = c or box._cache or {}

    -- Safety net: if paint() runs before the first wakeup() cycle has
    -- populated the cache (e.g. very first frame), fall back to a live
    -- lookup so we never compare a number against a nil threshold.
    c.escMax = c.escMax or getThemeValue("esc_max")
    c.escWarn = c.escWarn or getThemeValue("esc_warn")
    c.fuelWarn = c.fuelWarn or getThemeValue("fuel_warn")
    c.packMin = c.packMin or packMinV()
    c.packWarn = c.packWarn or packWarnV()
    c.linkWarn = c.linkWarn or getThemeValue("link_warn")
    c.rpmMax = c.rpmMax or getThemeValue("rpm_max")

    lcd.color(C.bg)
    lcd.drawFilledRectangle(floor(x), floor(y), floor(w), floor(h))

    local pad = 12
    drawTextAligned(x + pad, y + 8, w * 0.5, "AEGIS // FLIGHT", "FONT_STD", C.cyan, "left")
    drawTextAligned(x + w * 0.35, y + 3, w * 0.30, c.timer or "00:00", "FONT_XL", C.white, "center")

    local bodyY = y + 42
    local bodyH = h - 54
    local leftW = floor(w * 0.18)
    local rightW = floor(w * 0.24)
    local centerX = x + pad + leftW + pad
    local centerW = w - leftW - rightW - pad * 4
    local leftX = x + pad
    local rightX = centerX + centerW + pad

    local escColor = c.esc and (c.esc >= c.escMax and C.red or (c.esc >= c.escWarn and C.amber or C.green)) or C.muted
    local fuel = c.fuel or 0
    local fuelColor = fuel <= c.fuelWarn and C.red or (fuel <= 50 and C.amber or C.green)
    local packColor = c.voltage and (c.voltage < c.packMin and C.red or (c.voltage < c.packWarn and C.amber or C.cyan)) or C.muted
    local linkColor = c.link and (c.link < c.linkWarn and C.amber or C.cyan) or C.muted

    local halfH = floor((bodyH - pad) / 2)
    drawVerticalMeter(leftX, bodyY, leftW, halfH, "ESC TEMP", c.esc, c.escMax, escColor, "°")
    drawVerticalMeter(leftX, bodyY + halfH + pad, leftW, halfH, "PID PROFILE", c.profile, 3, C.violet, "")

    drawPanel(centerX, bodyY, centerW, bodyH, C.cyan, nil)
    local cx = centerX + centerW / 2
    local cy = bodyY + bodyH * 0.48
    local radius = min(centerW * 0.43, bodyH * 0.43)
    local rpmMax = c.rpmMax
    local rpmColor = (c.rpm or 0) > rpmMax and C.red or C.cyan
    drawRadialGauge(cx, cy, radius, c.rpm or 0, rpmMax, rpmColor)
    drawTextAligned(centerX, cy - 44, centerW, fmt(c.rpm, 0, ""), "FONT_XXL", C.white, "center")
    drawTextAligned(centerX, cy + 10, centerW, "HEADSPEED  RPM", "FONT_XS", C.muted, "center")
    drawTextAligned(centerX + 22, bodyY + bodyH - 33, centerW - 44, "MAX " .. fmt(c.maxRpm, 0, " RPM"), "FONT_XS", C.amber, "left")
    drawTextAligned(centerX + 22, bodyY + bodyH - 33, centerW - 44, "LIMIT " .. fmt(rpmMax, 0, " RPM"), "FONT_XS", C.muted, "right")

    local fuelH = floor(bodyH * 0.34)
    drawPanel(rightX, bodyY, rightW, fuelH, fuelColor, "SMART FUEL")
    drawTextAligned(rightX + 12, bodyY + 34, rightW - 24, fmt(c.fuel, 0, "%"), "FONT_XL", C.white, "right")
    drawSegments(rightX + 12, bodyY + fuelH - 39, rightW - 32, 16, fuel, 10, fuelColor, C.line)
    lcd.color(fuelColor)
    lcd.drawFilledRectangle(floor(rightX + rightW - 16), floor(bodyY + fuelH - 35), 4, 8)

    -- Arm state sits immediately below the Smart Fuel battery.
    local stateGap = 8
    local stateH = 28
    local stateY = bodyY + fuelH + stateGap
    drawStateBadge(rightX, stateY, rightW, stateH, c.flightState, c.flightStateColor)

    local smallY = stateY + stateH + stateGap
    local smallH = floor((bodyY + bodyH - smallY - pad) / 2)
    drawMetric(rightX, smallY, rightW, smallH, "CURRENT LOAD", fmt(c.current, 1, " A"), C.violet, "instantaneous")
    drawMetric(rightX, smallY + smallH + pad, rightW, smallH, "PACK / LINK", fmt(c.voltage, 1, " V") .. "   " .. fmt(c.link, 0, "%"), packColor == C.red and C.red or linkColor, "pack voltage and RF health")

    -- Keep consumed capacity inside the second vertical meter as two centered rows.
    local secondMeterY = bodyY + halfH + pad
    local consumedX = leftX + 38
    local consumedW = leftW - 50
    local consumedLabelY = secondMeterY + halfH - 64
    local consumedValueY = consumedLabelY + 18
    drawTextAligned(consumedX, consumedLabelY, consumedW, "CONSUMED", "FONT_XXS", C.muted, "center")
    drawTextAligned(consumedX, consumedValueY, consumedW, fmt(c.consumed, 0, " mAh"), "FONT_XS", C.white, "center")

    local monitorY = y + h - 22
    drawTextAligned(x + w * 0.67, monitorY, w * 0.31 - pad, "AEGIS MONITORING", "FONT_XXS", C.line2, "right")
end

local boxes_cache = nil

local function boxes()
    if boxes_cache == nil then
        boxes_cache = {{
            col = 1, row = 1, colspan = 12, rowspan = 12,
            type = "func", subtype = "func",
            wakeup = inflightWakeup,
            paint = inflightPaint,
            bgcolor = "transparent"
        }}
    end
    return boxes_cache
end

return {
    layout = layout,
    boxes = boxes,
    header_boxes = header_boxes(),
    header_layout = header_layout,
    scheduler = {spread_scheduling = true, spread_scheduling_paint = false, spread_ratio = 0.85}
}
