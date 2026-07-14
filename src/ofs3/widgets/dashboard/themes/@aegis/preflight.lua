--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html

  Ported from the author's standalone "Aegis" theme (built for the
  rfsuite/Rotorflight dashboard framework) to run natively on ofs3.
  Substitutions for telemetry/preferences ofs3 doesn't have:
  - bec_voltage -> main pack voltage (cell-scaled min/warn/max via
    ofs3.session.batteryConfig, same convention as the other themes)
  - link/vfr -> rssi
  - rate_profile/pid_profile check rows -> profile/rpm check rows
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
    rpm_max = 2500,
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

-- Pack voltage thresholds, cell-scaled like the other themes' voltage gauges.
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

local function packMaxV()
    local cfg = ofs3.session.batteryConfig
    local cells = (cfg and cfg.batteryCellCount) or 3
    return cells * ((cfg and cfg.vbatfullcellvoltage) or 4.1)
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
        drawTextAligned(x + 12, y + h - 22, w - 24, subtitle, "FONT_XXS", C.muted, "left")
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

local function drawProgress(x, y, w, h, percent, color)
    percent = max(0, min(1, percent or 0))
    lcd.color(C.line)
    lcd.drawRectangle(floor(x), floor(y), floor(w), floor(h), 1)
    if percent > 0 then
        lcd.color(color)
        lcd.drawFilledRectangle(floor(x + 2), floor(y + 2), floor((w - 4) * percent), max(1, floor(h - 4)))
    end
end

local HEX_UNIT = {}
for i = 0, 5 do
    local a = rad(30 + i * 60)
    HEX_UNIT[i + 1] = {cos(a), sin(a)}
end

local function drawHex(x, y, radius, color)
    local points = {}
    for i = 1, 6 do
        local u = HEX_UNIT[i]
        points[i] = {x + u[1] * radius, y + u[2] * radius}
    end
    lcd.color(color)
    for i = 1, 6 do
        local a = points[i]
        local b = points[(i % 6) + 1]
        lcd.drawLine(floor(a[1]), floor(a[2]), floor(b[1]), floor(b[2]))
    end
end

local layout = {cols = 12, rows = 12, padding = 0}

local function preflightWakeup(box, telemetry)
    local c = box._cache or {}
    box._cache = c

    c.fuel = sensor(telemetry, "smartfuel")
    c.voltage = sensor(telemetry, "voltage")
    c.esc = sensor(telemetry, "temp_esc")
    c.link = sensor(telemetry, "rssi", "link", "vfr")
    c.profile = sensor(telemetry, "profile")
    c.rpm = sensor(telemetry, "rpm")
    c.flightState, c.flightStateColor = getFlightState(telemetry)

    local packMin, packWarn = packMinV(), packWarnV()

    local available = 0
    local faults = 0
    local warnings = 0
    local issues = {}

    if c.fuel ~= nil then
        available = available + 1
        if c.fuel <= getThemeValue("fuel_warn") then
            faults = faults + 1
            issues[#issues + 1] = "SMART FUEL " .. fmt(c.fuel, 0, "%") .. " AT RESERVE"
        end
    end
    if c.voltage ~= nil then
        available = available + 1
        if c.voltage < packMin then
            faults = faults + 1
            issues[#issues + 1] = "PACK " .. fmt(c.voltage, 1, "V") .. " BELOW " .. fmt(packMin, 1, "V")
        elseif c.voltage < packWarn then
            warnings = warnings + 1
            issues[#issues + 1] = "PACK " .. fmt(c.voltage, 1, "V") .. " BELOW " .. fmt(packWarn, 1, "V")
        end
    end
    if c.esc ~= nil then
        available = available + 1
        if c.esc >= getThemeValue("esc_max") then
            faults = faults + 1
            issues[#issues + 1] = "ESC " .. fmt(c.esc, 0, "°C") .. " AT LIMIT"
        elseif c.esc >= getThemeValue("esc_warn") then
            warnings = warnings + 1
            issues[#issues + 1] = "ESC " .. fmt(c.esc, 0, "°C") .. " ABOVE WARNING"
        end
    end
    if c.link ~= nil then
        available = available + 1
        if c.link < getThemeValue("link_warn") then
            warnings = warnings + 1
            issues[#issues + 1] = "LINK " .. fmt(c.link, 0, "%") .. " BELOW " .. fmt(getThemeValue("link_warn"), 0, "%")
        end
    end

    local issueCount = faults + warnings
    c.issueText = issues[1]
    if issueCount > 1 and c.issueText then
        c.issueText = c.issueText .. "  +" .. tostring(issueCount - 1) .. " MORE"
    end

    if available == 0 then
        c.status = "WAITING"
        c.statusColor = C.muted
        c.statusSub = "CONNECT TELEMETRY"
        c.issueText = nil
    elseif faults > 0 then
        c.status = "CHECK"
        c.statusColor = C.red
        c.statusSub = tostring(issueCount) .. " ITEM" .. (issueCount == 1 and "" or "S") .. " FLAGGED"
    elseif warnings > 0 then
        c.status = "CAUTION"
        c.statusColor = C.amber
        c.statusSub = tostring(issueCount) .. " ITEM" .. (issueCount == 1 and "" or "S") .. " TO REVIEW"
    else
        c.status = "READY"
        c.statusColor = C.green
        c.statusSub = "SYSTEMS NOMINAL"
        c.issueText = nil
    end

    -- Cache theme thresholds here (wakeup runs at a bounded rate) instead of
    -- calling getThemeValue()/packMinV()/packWarnV() from paint(), which runs
    -- on every invalidate.
    c.fuelWarn = getThemeValue("fuel_warn")
    c.packMin = packMin
    c.packWarn = packWarn
    c.packMax = packMaxV()
    c.escMax = getThemeValue("esc_max")
    c.escWarn = getThemeValue("esc_warn")
    c.linkWarn = getThemeValue("link_warn")

    return c
end

local function drawCheckRow(x, y, w, label, value, stateColor)
    lcd.color(stateColor)
    lcd.drawFilledRectangle(floor(x), floor(y + 6), 7, 7)
    drawTextAligned(x + 14, y, w * 0.45, label, "FONT_XS", C.muted, "left")
    drawTextAligned(x + w * 0.48, y, w * 0.52, value, "FONT_S", C.white, "right")
end

local function preflightPaint(x, y, w, h, box, c)
    x, y = utils.applyOffset(x, y, box)
    c = c or box._cache or {}

    -- Safety net: if paint() runs before the first wakeup() cycle has
    -- populated the cache (e.g. very first frame), fall back to a live
    -- lookup so we never compare a number against a nil threshold.
    c.fuelWarn = c.fuelWarn or getThemeValue("fuel_warn")
    c.packMin = c.packMin or packMinV()
    c.packWarn = c.packWarn or packWarnV()
    c.packMax = c.packMax or packMaxV()
    c.escMax = c.escMax or getThemeValue("esc_max")
    c.escWarn = c.escWarn or getThemeValue("esc_warn")
    c.linkWarn = c.linkWarn or getThemeValue("link_warn")

    lcd.color(C.bg)
    lcd.drawFilledRectangle(floor(x), floor(y), floor(w), floor(h))

    local pad = 12
    local topY = y + 8
    drawTextAligned(x + pad, topY, w * 0.55, "AEGIS // PRE-FLIGHT", "FONT_STD", C.cyan, "left")
    drawTextAligned(x + w - 220, topY, 208, c.status or "WAITING", "FONT_STD", c.statusColor or C.muted, "right")

    local bodyY = y + 42
    local bodyH = h - 54
    local sideW = floor(w * 0.25)
    local centerW = w - sideW * 2 - pad * 4
    local leftX = x + pad
    local centerX = leftX + sideW + pad
    local rightX = centerX + centerW + pad

    local cardH = floor((bodyH - pad) / 2)
    local fuel = c.fuel or 0
    local fuelColor = fuel <= c.fuelWarn and C.red or (fuel <= 50 and C.amber or C.green)
    local packColor = c.voltage and (c.voltage < c.packMin and C.red or (c.voltage < c.packWarn and C.amber or C.cyan)) or C.muted
    local escColor = c.esc and (c.esc >= c.escMax and C.red or (c.esc >= c.escWarn and C.amber or C.green)) or C.muted
    local linkColor = c.link and (c.link < c.linkWarn and C.amber or C.cyan) or C.muted
    local packSpan = c.packMax - c.packMin
    local packPct = (c.voltage and packSpan > 0) and (c.voltage - c.packMin) / packSpan or 0

    drawMetric(leftX, bodyY, sideW, cardH, "PACK VOLTAGE", fmt(c.voltage, 1, " V"), packColor, "main battery")
    drawProgress(leftX + 12, bodyY + cardH - 36, sideW - 24, 9, packPct, packColor)

    drawMetric(leftX, bodyY + cardH + pad, sideW, cardH, "RADIO LINK", fmt(c.link, 0, "%"), linkColor, "frame quality")
    drawProgress(leftX + 12, bodyY + cardH * 2 + pad - 36, sideW - 24, 9, c.link and c.link / 100 or 0, linkColor)

    drawPanel(centerX, bodyY, centerW, bodyH, c.statusColor or C.muted, nil)
    local cx = centerX + centerW / 2
    local cy = bodyY + bodyH * 0.42
    local radius = min(centerW * 0.33, bodyH * 0.32)
    drawHex(cx, cy, radius + 12, C.line2)
    drawHex(cx, cy, radius, c.statusColor or C.muted)
    drawTextAligned(centerX, cy - 34, centerW, c.status or "WAITING", "FONT_XXL", C.white, "center")
    if c.issueText then
        drawTextAligned(centerX + 12, cy + 15, centerW - 24, c.issueText, "FONT_XS", C.white, "center")
        drawTextAligned(centerX, cy + 40, centerW, c.statusSub or "ITEM TO REVIEW", "FONT_XXS", c.statusColor or C.muted, "center")
    else
        drawTextAligned(centerX, cy + 22, centerW, c.statusSub or "CONNECT TELEMETRY", "FONT_XXS", c.statusColor or C.muted, "center")
    end

    local segY = bodyY + bodyH - 86
    drawTextAligned(centerX + 18, segY - 22, centerW - 36, "SMART FUEL", "FONT_XS", C.muted, "left")
    drawTextAligned(centerX + 18, segY - 24, centerW - 36, fmt(c.fuel, 0, "%"), "FONT_S", C.white, "right")
    drawSegments(centerX + 18, segY, centerW - 42, 18, fuel, 12, fuelColor, C.line)
    lcd.color(fuelColor)
    lcd.drawFilledRectangle(floor(centerX + centerW - 20), floor(segY + 5), 5, 8)

    -- Put the arm state directly below the Smart Fuel battery.
    drawStateBadge(centerX + 18, segY + 31, centerW - 36, 27, c.flightState, c.flightStateColor)

    drawMetric(rightX, bodyY, sideW, cardH, "ESC THERMAL", fmt(c.esc, 0, "°C"), escColor, "controller temperature")
    drawProgress(rightX + 12, bodyY + cardH - 36, sideW - 24, 9, c.esc and c.esc / c.escMax or 0, escColor)

    drawPanel(rightX, bodyY + cardH + pad, sideW, cardH, C.violet, "FLIGHT PROFILE")
    drawCheckRow(rightX + 14, bodyY + cardH + pad + 38, sideW - 28, "PID BANK", fmt(c.profile, 0, ""), C.violet)
    drawCheckRow(rightX + 14, bodyY + cardH + pad + 70, sideW - 28, "HEADSPEED", fmt(c.rpm, 0, " rpm"), C.violet)
    drawCheckRow(rightX + 14, bodyY + cardH + pad + 102, sideW - 28, "PACK", fmt(c.voltage, 1, " V"), C.cyan)
end

local boxes_cache = nil

local function boxes()
    if boxes_cache == nil then
        boxes_cache = {{
            col = 1, row = 1, colspan = 12, rowspan = 12,
            type = "func", subtype = "func",
            wakeup = preflightWakeup,
            paint = preflightPaint,
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
