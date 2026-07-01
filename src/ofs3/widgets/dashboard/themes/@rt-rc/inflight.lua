--[[ Aegis OFS3 inflight dashboard - overlap-safe visual polish v2 - GPLv3 ]] --
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
    cache.timer = common.flightTimeText()

    return cache
end

local function drawRadialGauge(cx, cy, radius, value, maximum, color)
    local startAngle, sweep, ticks = 140, 260, 36
    local percent = maximum > 0 and common.clamp(value / maximum, 0, 1) or 0
    local active = floor(ticks * percent + 0.5)

    for index = 0, ticks - 1 do
        local angle = math.rad(startAngle + sweep * index / (ticks - 1))
        local inner = radius - 15
        local x1 = cx + math.cos(angle) * inner
        local y1 = cy + math.sin(angle) * inner
        local x2 = cx + math.cos(angle) * radius
        local y2 = cy + math.sin(angle) * radius

        lcd.color(index < active and color or C.line)
        lcd.drawLine(floor(x1), floor(y1), floor(x2), floor(y2))
    end

    lcd.color(C.line2)
    lcd.drawLine(
        floor(cx - radius * 0.68), floor(cy + radius * 0.72),
        floor(cx + radius * 0.68), floor(cy + radius * 0.72)
    )
end

local function drawVerticalMeter(x, y, w, h, title, value, maximum, color, unit, compact, footer)
    common.drawPanel(x, y, w, h, color, title)

    local barX = x + 15
    local barY = y + (compact and 31 or 36)
    local barW = 15
    local footerSpace = footer and (compact and 34 or 38) or 0
    local barH = h - (compact and 47 or 56) - footerSpace
    local percent = value and maximum > 0 and common.clamp(value / maximum, 0, 1) or 0

    lcd.color(C.line)
    lcd.drawRectangle(floor(barX), floor(barY), floor(barW), floor(barH), 1)

    if percent > 0 then
        local fillHeight = floor((barH - 4) * percent)
        lcd.color(color)
        lcd.drawFilledRectangle(
            floor(barX + 2), floor(barY + barH - 2 - fillHeight),
            floor(barW - 4), fillHeight
        )
    end

    common.drawTextAligned(
        x + 40, y + (compact and 38 or 46), w - 52,
        common.formatValue(value, 0, unit),
        compact and "FONT_S" or "FONT_L", C.white, "left"
    )

    if footer then
        lcd.color(C.line)
        lcd.drawLine(
            floor(x + 40), floor(y + h - (compact and 35 or 40)),
            floor(x + w - 12), floor(y + h - (compact and 35 or 40))
        )
        common.drawTextAligned(
            x + 40, y + h - (compact and 28 or 32), w - 52,
            footer, "FONT_XXS", C.muted, "left"
        )
    end
end

local function drawCompactMetric(x, y, w, h, title, valueText, accent, subtitle, align)
    common.drawPanel(x, y, w, h, accent, title)
    local valueY = y + (h < 82 and 25 or 30)
    common.drawTextAligned(
        x + 12, valueY, w - 24, valueText,
        h < 82 and "FONT_S" or "FONT_L", C.white, align or "left"
    )
    if subtitle and h >= 108 then
        common.drawTextAligned(
            x + 12, y + h - 22, w - 24,
            subtitle, "FONT_XXS", C.muted, "left"
        )
    end
end

local function drawPackLink(x, y, w, h, voltage, link, packColor, linkColor)
    common.drawPanel(x, y, w, h, packColor == C.red and C.red or linkColor, "PACK / LINK")

    local dividerX = x + w / 2
    lcd.color(C.line)
    lcd.drawLine(
        floor(dividerX), floor(y + 28),
        floor(dividerX), floor(y + h - 10)
    )

    common.drawTextAligned(
        x + 12, y + 28, w / 2 - 20,
        common.formatValue(voltage, 1, " V"),
        h < 100 and "FONT_S" or "FONT_L", C.white, "center"
    )
    common.drawTextAligned(
        x + 12, y + h - 20, w / 2 - 20,
        "PACK", "FONT_XXS", C.muted, "center"
    )

    common.drawTextAligned(
        dividerX + 8, y + 28, w / 2 - 20,
        common.formatValue(link, 0, "%"),
        h < 100 and "FONT_S" or "FONT_L", C.white, "center"
    )
    common.drawTextAligned(
        dividerX + 8, y + h - 20, w / 2 - 20,
        "LINK", "FONT_XXS", C.muted, "center"
    )
end

local function paint(x, y, w, h, box, cache)
    cache = cache or box._cache or {}
    lcd.color(C.bg)
    lcd.drawFilledRectangle(floor(x), floor(y), floor(w), floor(h))

    local compact = h < 400
    local pad = compact and 10 or 12

    common.drawTextAligned(
        x + pad, y + (compact and 6 or 8), w * 0.42,
        "AEGIS // FLIGHT",
        compact and "FONT_S" or "FONT_STD", C.cyan, "left"
    )
    common.drawTextAligned(
        x + w * 0.36, y + (compact and 0 or 2), w * 0.28,
        cache.timer or "00:00",
        compact and "FONT_L" or "FONT_XL", C.white, "center"
    )
    common.drawTextAligned(
        x + w - 170, y + (compact and 10 or 12), 158,
        "LIVE DATA", "FONT_XXS", C.muted, "right"
    )

    local bodyY = y + (compact and 38 or 42)
    local bodyH = h - (compact and 48 or 54)

    local leftW = floor(w * 0.18)
    local rightW = floor(w * 0.25)
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

    drawVerticalMeter(
        leftX, bodyY, leftW, halfH,
        "ESC TEMP", cache.esc, common.getConfig("esc_max"),
        escColor, "°", compact, nil
    )

    drawVerticalMeter(
        leftX, bodyY + halfH + pad, leftW, halfH,
        "THROTTLE", cache.throttle, 100,
        throttleColor, "%", compact,
        "USED " .. common.formatValue(cache.consumed, 0, " mAh")
    )

    -- Center headspeed instrument
    common.drawPanel(centerX, bodyY, centerW, bodyH, C.cyan, nil)
    local cx = centerX + centerW / 2
    local cy = bodyY + bodyH * (compact and 0.47 or 0.49)
    local radius = min(centerW * 0.40, bodyH * 0.39)
    local rpmMax = common.getConfig("rpm_max")
    local rpmColor = (cache.rpm or 0) > rpmMax and C.red or C.cyan

    drawRadialGauge(cx, cy, radius, cache.rpm or 0, rpmMax, rpmColor)
    common.drawTextAligned(
        centerX, cy - (compact and 34 or 45), centerW,
        common.formatValue(cache.rpm, 0, ""),
        compact and "FONT_XL" or "FONT_XXL", C.white, "center"
    )
    common.drawTextAligned(
        centerX, cy + (compact and 4 or 10), centerW,
        "HEADSPEED  RPM", "FONT_XS", C.muted, "center"
    )

    lcd.color(C.line)
    lcd.drawLine(
        floor(centerX + 18), floor(bodyY + bodyH - (compact and 39 or 46)),
        floor(centerX + centerW - 18), floor(bodyY + bodyH - (compact and 39 or 46))
    )
    common.drawTextAligned(
        centerX + 18, bodyY + bodyH - (compact and 30 or 36),
        centerW * 0.52,
        "MAX " .. common.formatValue(cache.maxRpm, 0, " RPM"),
        "FONT_XXS", C.amber, "left"
    )
    common.drawTextAligned(
        centerX + centerW * 0.52, bodyY + bodyH - (compact and 30 or 36),
        centerW * 0.48 - 18,
        "LIMIT " .. common.formatValue(rpmMax, 0, " RPM"),
        "FONT_XXS", C.muted, "right"
    )

    -- Right telemetry stack, expanded after removing arm-state badge
    local gap = compact and 7 or 9
    local fuelH = floor(bodyH * 0.39)
    local remainingH = bodyH - fuelH - gap * 2
    local currentH = floor(remainingH * 0.48)
    local packLinkH = remainingH - currentH

    common.drawPanel(rightX, bodyY, rightW, fuelH, fuelColor, "SMART FUEL")
    common.drawTextAligned(
        rightX + 12, bodyY + (compact and 31 or 37), rightW - 24,
        common.formatValue(cache.fuel, 0, "%"),
        compact and "FONT_L" or "FONT_XL", C.white, "right"
    )
    common.drawSegments(
        rightX + 12, bodyY + fuelH - (compact and 35 or 43),
        rightW - 28, compact and 13 or 16,
        cache.fuel or 0, compact and 8 or 10, fuelColor
    )
    common.drawTextAligned(
        rightX + 12, bodyY + fuelH - (compact and 16 or 20),
        rightW - 24, "REMAINING",
        "FONT_XXS", C.muted, "left"
    )

    local currentY = bodyY + fuelH + gap
    drawCompactMetric(
        rightX, currentY, rightW, currentH,
        "CURRENT LOAD", common.formatValue(cache.current, 1, " A"),
        C.violet, "instantaneous", "left"
    )

    local packLinkY = currentY + currentH + gap
    drawPackLink(
        rightX, packLinkY, rightW, packLinkH,
        cache.voltage, cache.link, packColor, linkColor
    )
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
