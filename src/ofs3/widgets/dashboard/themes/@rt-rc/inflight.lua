--[[ Aegis OFS3 inflight dashboard - GPLv3 ]] --
local ofs3 = require("ofs3")
local lcd = lcd
local math = math
local floor = math.floor
local min = math.min
local max = math.max

local common = assert(loadfile("SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/themes/@rt-rc/common.lua"))()
local C = common.C

local layout = {cols = 12, rows = 12, padding = 0}
local header_layout = common.headerLayout()
local header_boxes = common.headerBoxes()

local function wakeup(box, telemetry)
    local cache = box._cache or {maxRpm = 0}
    box._cache = cache

    cache.rpm = common.sensor(telemetry, "rpm") or 0
    cache.maxRpm = max(cache.maxRpm or 0, cache.rpm)
    cache.throttle = common.throttlePercent()
    cache.esc = common.sensor(telemetry, "temp_esc")
    cache.fuel = common.sensor(telemetry, "smartfuel")
    cache.current = common.sensor(telemetry, "current")
    cache.voltage = common.sensor(telemetry, "voltage")
    cache.link = common.sensor(telemetry, "rssi")
    cache.consumed = common.sensor(telemetry, "consumption")
    cache.state, cache.stateColor = common.flightState(telemetry)
    cache.timer = common.flightTimeText()
    return cache
end

local function drawRadialGauge(cx, cy, radius, value, maximum, color)
    local startAngle = 140
    local sweep = 260
    local ticks = 32
    local percent = maximum > 0 and common.clamp(value / maximum, 0, 1) or 0
    local active = floor(ticks * percent + 0.5)
    for index = 0, ticks - 1 do
        local angle = math.rad(startAngle + sweep * index / (ticks - 1))
        local inner = radius - 14
        local x1 = cx + math.cos(angle) * inner
        local y1 = cy + math.sin(angle) * inner
        local x2 = cx + math.cos(angle) * radius
        local y2 = cy + math.sin(angle) * radius
        lcd.color(index < active and color or C.line)
        lcd.drawLine(floor(x1), floor(y1), floor(x2), floor(y2))
    end
    lcd.color(C.line2)
    lcd.drawLine(floor(cx - radius * 0.68), floor(cy + radius * 0.72), floor(cx + radius * 0.68), floor(cy + radius * 0.72))
end

local function drawVerticalMeter(x, y, w, h, title, value, maximum, color, unit, compact)
    common.drawPanel(x, y, w, h, color, title)
    local barX = x + 15
    local barY = y + (compact and 30 or 34)
    local barW = 14
    local barH = h - (compact and 44 or 52)
    local percent = value and maximum > 0 and common.clamp(value / maximum, 0, 1) or 0
    lcd.color(C.line)
    lcd.drawRectangle(floor(barX), floor(barY), floor(barW), floor(barH), 1)
    if percent > 0 then
        local fillHeight = floor((barH - 4) * percent)
        lcd.color(color)
        lcd.drawFilledRectangle(floor(barX + 2), floor(barY + barH - 2 - fillHeight), floor(barW - 4), fillHeight)
    end
    common.drawTextAligned(x + 38, y + (compact and 36 or 44), w - 50, common.formatValue(value, 0, unit), compact and "FONT_S" or "FONT_L", C.white, "left")
end

local function drawCompactMetric(x, y, w, h, title, valueText, accent, subtitle)
    common.drawPanel(x, y, w, h, accent, title)
    if h < 70 then
        common.drawTextAligned(x + 12, y + 23, w - 24, valueText, "FONT_S", C.white, "left")
    else
        common.drawTextAligned(x + 12, y + 26, w - 24, valueText, "FONT_L", C.white, "left")
        if subtitle then
            common.drawTextAligned(x + 12, y + h - 22, w - 24, subtitle, "FONT_XXS", C.muted, "left")
        end
    end
end

local function paint(x, y, w, h, box, cache)
    cache = cache or box._cache or {}
    lcd.color(C.bg)
    lcd.drawFilledRectangle(floor(x), floor(y), floor(w), floor(h))

    local compact = h < 360
    local pad = compact and 10 or 12
    common.drawTextAligned(x + pad, y + (compact and 6 or 8), w * 0.5, "AEGIS // FLIGHT", compact and "FONT_S" or "FONT_STD", C.cyan, "left")
    common.drawTextAligned(x + w * 0.35, y + (compact and 1 or 3), w * 0.30, cache.timer or "00:00", compact and "FONT_L" or "FONT_XL", C.white, "center")

    local bodyY = y + (compact and 38 or 42)
    local bodyH = h - (compact and 48 or 54)
    local leftW = floor(w * 0.18)
    local rightW = floor(w * 0.24)
    local centerX = x + pad + leftW + pad
    local centerW = w - leftW - rightW - pad * 4
    local leftX = x + pad
    local rightX = centerX + centerW + pad

    local escColor = common.escColor(cache.esc)
    local throttleColor = (cache.throttle or 0) >= 90 and C.amber or C.cyan
    local fuelColor = common.fuelColor(cache.fuel)
    local packColor = common.packColor(cache.voltage)
    local linkColor = common.linkColor(cache.link)

    local halfH = floor((bodyH - pad) / 2)
    drawVerticalMeter(leftX, bodyY, leftW, halfH, "ESC TEMP", cache.esc, common.getConfig("esc_max"), escColor, "°", compact)
    drawVerticalMeter(leftX, bodyY + halfH + pad, leftW, halfH, "THROTTLE", cache.throttle, 100, throttleColor, "%", compact)

    common.drawPanel(centerX, bodyY, centerW, bodyH, C.cyan, nil)
    local cx = centerX + centerW / 2
    local cy = bodyY + bodyH * (compact and 0.45 or 0.48)
    local radius = min(centerW * (compact and 0.37 or 0.43), bodyH * (compact and 0.36 or 0.43))
    local rpmMax = common.getConfig("rpm_max")
    local rpmColor = (cache.rpm or 0) > rpmMax and C.red or C.cyan
    drawRadialGauge(cx, cy, radius, cache.rpm or 0, rpmMax, rpmColor)
    common.drawTextAligned(centerX, cy - (compact and 32 or 44), centerW, common.formatValue(cache.rpm, 0, ""), compact and "FONT_XL" or "FONT_XXL", C.white, "center")
    common.drawTextAligned(centerX, cy + (compact and 5 or 10), centerW, "HEADSPEED  RPM", "FONT_XS", C.muted, "center")
    common.drawTextAligned(centerX + 18, bodyY + bodyH - (compact and 27 or 33), centerW - 36, "MAX " .. common.formatValue(cache.maxRpm, 0, " RPM"), "FONT_XXS", C.amber, "left")
    common.drawTextAligned(centerX + 18, bodyY + bodyH - (compact and 27 or 33), centerW - 36, "LIMIT " .. common.formatValue(rpmMax, 0, " RPM"), "FONT_XXS", C.muted, "right")

    local fuelH = floor(bodyH * (compact and 0.32 or 0.34))
    common.drawPanel(rightX, bodyY, rightW, fuelH, fuelColor, "SMART FUEL")
    common.drawTextAligned(rightX + 12, bodyY + (compact and 29 or 34), rightW - 24, common.formatValue(cache.fuel, 0, "%"), compact and "FONT_L" or "FONT_XL", C.white, "right")
    common.drawSegments(rightX + 12, bodyY + fuelH - (compact and 31 or 39), rightW - 32, compact and 13 or 16, cache.fuel or 0, compact and 8 or 10, fuelColor)
    lcd.color(fuelColor)
    lcd.drawFilledRectangle(floor(rightX + rightW - 16), floor(bodyY + fuelH - (compact and 28 or 35)), 4, 8)

    local stateGap = compact and 6 or 8
    local stateH = compact and 25 or 28
    local stateY = bodyY + fuelH + stateGap
    common.drawStateBadge(rightX, stateY, rightW, stateH, cache.state, cache.stateColor)

    local smallY = stateY + stateH + stateGap
    local smallH = floor((bodyY + bodyH - smallY - pad) / 2)
    drawCompactMetric(rightX, smallY, rightW, smallH, "CURRENT LOAD", common.formatValue(cache.current, 1, " A"), C.violet, "instantaneous")
    drawCompactMetric(rightX, smallY + smallH + pad, rightW, smallH, "PACK / LINK", common.formatValue(cache.voltage, 1, " V") .. "   " .. common.formatValue(cache.link, 0, "%"), packColor == C.red and C.red or linkColor, "power and RF health")

    local throttleY = bodyY + halfH + pad
    local consumedX = leftX + 38
    local consumedW = leftW - 50
    local consumedLabelY = throttleY + halfH - (compact and 53 or 64)
    common.drawTextAligned(consumedX, consumedLabelY, consumedW, "CONSUMED", "FONT_XXS", C.muted, "center")
    common.drawTextAligned(consumedX, consumedLabelY + 16, consumedW, common.formatValue(cache.consumed, 0, " mAh"), "FONT_XS", C.white, "center")

    if not compact then
        common.drawTextAligned(x + w * 0.67, y + h - 22, w * 0.31 - pad, "AEGIS MONITORING", "FONT_XXS", C.line2, "right")
    end
end

local boxes = {{
    col = 1, row = 1, colspan = 12, rowspan = 12,
    type = "func", subtype = "func",
    wakeup = wakeup, paint = paint, bgcolor = "transparent"
}}

return {
    layout = layout,
    boxes = boxes,
    header_boxes = header_boxes,
    header_layout = header_layout,
    scheduler = {spread_scheduling = true, spread_scheduling_paint = false, spread_ratio = 0.85}
}
