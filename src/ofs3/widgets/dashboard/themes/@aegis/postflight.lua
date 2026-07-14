--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html

  Ported from the author's standalone "Aegis" theme (built for the
  rfsuite/Rotorflight dashboard framework) to run natively on ofs3.
  Substitutions for telemetry ofs3 doesn't have:
  - bec_voltage -> main pack voltage (cell-scaled thresholds)
  - link/vfr -> rssi
  - smartconsumption -> consumption
  - "watts" stat (ofs3 never tracks it) -> computed from the
    voltage/current sensor stats, same approach as objects/text/watts.lua
  - altitude (no ofs3 sensor) -> the "MIN PACK / ALT" card became a
    "MIN PACK" card, and the freed grid slot now shows total model
    flight time instead
  See the PR description for the full list.
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

local function drawProgress(x, y, w, h, percent, color)
    percent = max(0, min(1, percent or 0))
    lcd.color(C.line)
    lcd.drawRectangle(floor(x), floor(y), floor(w), floor(h), 1)
    if percent > 0 then
        lcd.color(color)
        lcd.drawFilledRectangle(floor(x + 2), floor(y + 2), floor((w - 4) * percent), max(1, floor(h - 4)))
    end
end

local layout = {cols = 12, rows = 12, padding = 0}

local function stat(telemetry, source, statType, alias1, alias2)
    telemetry = telemetry or ofs3.tasks.telemetry
    local stats = telemetry and telemetry.sensorStats
    local data = stats and stats[source]
    local value = data and data[statType]
    if value ~= nil then return tonumber(value) end
    if alias1 then
        data = stats and stats[alias1]
        value = data and data[statType]
        if value ~= nil then return tonumber(value) end
    end
    if alias2 then
        data = stats and stats[alias2]
        value = data and data[statType]
        if value ~= nil then return tonumber(value) end
    end
    return nil
end

-- ofs3 never tracks a "watts" sensor/stat; approximate peak power from the
-- voltage/current stats, the same way objects/text/watts.lua does.
local function maxWatts(telemetry)
    telemetry = telemetry or ofs3.tasks.telemetry
    local stats = telemetry and telemetry.sensorStats
    local v = stats and stats.voltage
    local i = stats and stats.current
    if v and i and v.max and i.max then return v.max * i.max end
    return nil
end

local function postflightWakeup(box, telemetry)
    local c = box._cache or {}
    box._cache = c

    c.rpm = stat(telemetry, "rpm", "max")
    c.esc = stat(telemetry, "temp_esc", "max")
    c.current = stat(telemetry, "current", "max")
    c.watts = maxWatts(telemetry)
    c.voltage = stat(telemetry, "voltage", "min")
    c.link = stat(telemetry, "rssi", "min")
    c.fuel = stat(telemetry, "smartfuel", "min")
    c.consumed = stat(telemetry, "consumption", "max")

    local lifetimeSeconds = ofs3.session and ofs3.session.modelPreferences
        and tonumber(ofs3.ini.getvalue(ofs3.session.modelPreferences, "general", "totalflighttime")) or 0
    c.totalFlightTime = ofs3.logs and ofs3.logs.formatDuration and ofs3.logs.formatDuration(lifetimeSeconds) or "--"

    local seconds = ofs3.session and ofs3.session.timer and tonumber(ofs3.session.timer.live) or 0
    c.time = format("%02d:%02d", floor(seconds / 60), floor(seconds % 60))

    local packMin, packWarn, packMax = packMinV(), packWarnV(), packMaxV()

    local faults = 0
    local cautions = 0
    if c.esc and c.esc >= getThemeValue("esc_max") then faults = faults + 1
    elseif c.esc and c.esc >= getThemeValue("esc_warn") then cautions = cautions + 1 end
    if c.voltage and c.voltage < packMin then faults = faults + 1
    elseif c.voltage and c.voltage < packWarn then cautions = cautions + 1 end
    if c.fuel and c.fuel <= getThemeValue("fuel_warn") then cautions = cautions + 1 end
    if c.link and c.link < getThemeValue("link_warn") then cautions = cautions + 1 end
    if c.rpm and c.rpm > getThemeValue("rpm_max") * 1.05 then cautions = cautions + 1 end

    if faults > 0 then
        c.grade = "INSPECT"
        c.gradeColor = C.red
        c.gradeSub = "CRITICAL LIMIT EXCEEDED"
    elseif cautions > 0 then
        c.grade = "REVIEW"
        c.gradeColor = C.amber
        c.gradeSub = tostring(cautions) .. " ITEM" .. (cautions == 1 and "" or "S") .. " FLAGGED"
    else
        c.grade = "NOMINAL"
        c.gradeColor = C.green
        c.gradeSub = "FLIGHT DATA WITHIN LIMITS"
    end

    -- Cache theme thresholds here (wakeup runs at a bounded rate) instead of
    -- calling getThemeValue()/packMinV()/etc from paint(), which runs on
    -- every invalidate.
    c.rpmMax = getThemeValue("rpm_max")
    c.escMax = getThemeValue("esc_max")
    c.escWarn = getThemeValue("esc_warn")
    c.packMin = packMin
    c.packWarn = packWarn
    c.packMax = packMax
    c.fuelWarn = getThemeValue("fuel_warn")
    c.linkWarn = getThemeValue("link_warn")

    -- The report card grid only depends on values already cached above, so
    -- build it once per wakeup instead of allocating a fresh table on every
    -- paint() invalidate.
    local rpmColor = c.rpm and c.rpm > c.rpmMax * 1.05 and C.amber or C.cyan
    local escColor = c.esc and (c.esc >= c.escMax and C.red or (c.esc >= c.escWarn and C.amber or C.green)) or C.muted
    local packColor = c.voltage and (c.voltage < c.packMin and C.red or (c.voltage < c.packWarn and C.amber or C.cyan)) or C.muted
    local fuelColor = c.fuel and c.fuel <= c.fuelWarn and C.amber or C.green
    local linkColor = c.link and c.link < c.linkWarn and C.amber or C.cyan
    local packSpan = c.packMax - c.packMin
    local packPct = (c.voltage and packSpan > 0) and (c.voltage - c.packMin) / packSpan or 0

    c.cards = {
        {"MAX HEADSPEED", fmt(c.rpm, 0, " RPM"), rpmColor, c.rpm and c.rpm / c.rpmMax or 0},
        {"MAX ESC TEMP", fmt(c.esc, 0, "°C"), escColor, c.esc and c.esc / c.escMax or 0},
        {"PEAK CURRENT", fmt(c.current, 1, " A"), C.violet, c.current and c.current / 150 or 0},
        {"MIN PACK", fmt(c.voltage, 1, " V"), packColor, packPct},
        {"MIN LINK", fmt(c.link, 0, "%"), linkColor, c.link and c.link / 100 or 0},
        {"FUEL REMAINING", fmt(c.fuel, 0, "%"), fuelColor, c.fuel and c.fuel / 100 or 0},
        {"CONSUMED", fmt(c.consumed, 0, " mAh"), C.amber, c.consumed and c.consumed / 5000 or 0},
        {"PEAK POWER", fmt(c.watts, 0, " W"), C.violet, c.watts and c.watts / 5000 or 0},
        {"TOTAL FLIGHT TIME", c.totalFlightTime, C.cyan, 0}
    }

    return c
end

local function drawReportCard(x, y, w, h, title, value, accent, percent)
    drawPanel(x, y, w, h, accent, title)
    drawTextAligned(x + 12, y + 28, w - 24, value, "FONT_L", C.white, "left")
    drawProgress(x + 12, y + h - 19, w - 24, 7, percent or 0, accent)
end

local function postflightPaint(x, y, w, h, box, c)
    x, y = utils.applyOffset(x, y, box)
    c = c or box._cache or {}

    -- Safety net: if paint() runs before the first wakeup() cycle has
    -- populated the cache (e.g. very first frame), fall back to a live
    -- lookup so we never compare a number against a nil threshold.
    c.rpmMax = c.rpmMax or getThemeValue("rpm_max")
    c.escMax = c.escMax or getThemeValue("esc_max")
    c.escWarn = c.escWarn or getThemeValue("esc_warn")
    c.packMin = c.packMin or packMinV()
    c.packWarn = c.packWarn or packWarnV()
    c.fuelWarn = c.fuelWarn or getThemeValue("fuel_warn")
    c.linkWarn = c.linkWarn or getThemeValue("link_warn")

    lcd.color(C.bg)
    lcd.drawFilledRectangle(floor(x), floor(y), floor(w), floor(h))

    local pad = 12
    drawTextAligned(x + pad, y + 8, w * 0.5, "AEGIS // DEBRIEF", "FONT_STD", C.cyan, "left")
    drawTextAligned(x + w - 240, y + 6, 228, c.grade or "NOMINAL", "FONT_L", c.gradeColor or C.green, "right")

    local summaryY = y + 42
    local summaryH = 62
    drawPanel(x + pad, summaryY, w - pad * 2, summaryH, c.gradeColor or C.green, nil)
    drawTextAligned(x + pad + 16, summaryY + 10, w * 0.5, c.gradeSub or "FLIGHT DATA WITHIN LIMITS", "FONT_S", C.white, "left")
    drawTextAligned(x + w - 220, summaryY + 8, 190, c.time or "00:00", "FONT_XL", C.white, "right")
    drawTextAligned(x + w - 220, summaryY + 39, 190, "FLIGHT TIME", "FONT_XXS", C.muted, "right")

    local gridY = summaryY + summaryH + pad
    local gridH = h - (gridY - y) - pad
    local cols = 3
    local rows = 3
    local gap = 10
    local cardW = floor((w - pad * 2 - gap * (cols - 1)) / cols)
    local cardH = floor((gridH - gap * (rows - 1)) / rows)

    local cards = c.cards or {}

    for i = 1, #cards do
        local row = floor((i - 1) / cols)
        local col = (i - 1) % cols
        local card = cards[i]
        local cx = x + pad + col * (cardW + gap)
        local cy = gridY + row * (cardH + gap)
        drawReportCard(cx, cy, cardW, cardH, card[1], card[2], card[3], card[4])
    end
end

local boxes_cache = nil

local function boxes()
    if boxes_cache == nil then
        boxes_cache = {{
            col = 1, row = 1, colspan = 12, rowspan = 12,
            type = "func", subtype = "func",
            wakeup = postflightWakeup,
            paint = postflightPaint,
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
