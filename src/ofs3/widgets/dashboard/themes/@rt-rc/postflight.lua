--[[ Aegis OFS3 postflight dashboard - GPLv3 ]] --
local ofs3 = require("ofs3")
local lcd = lcd
local floor = math.floor
local tostring = tostring

local common = assert(loadfile("SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/themes/@rt-rc/common.lua"))()
local C = common.C

local layout = {cols = 12, rows = 12, padding = 0}
local header_layout = common.headerLayout()
local header_boxes = common.headerBoxes()

local function wakeup(box, telemetry)
    local cache = box._cache or {}
    box._cache = cache

    cache.rpm = common.stat(telemetry, "rpm", "max")
    cache.esc = common.stat(telemetry, "temp_esc", "max")
    cache.current = common.stat(telemetry, "current", "max")
    cache.avgCurrent = common.stat(telemetry, "current", "avg")
    cache.voltage = common.stat(telemetry, "voltage", "min")
    cache.maxVoltage = common.stat(telemetry, "voltage", "max")
    cache.link = common.stat(telemetry, "rssi", "min")
    cache.fuel = common.stat(telemetry, "smartfuel", "min")
    cache.consumed = common.stat(telemetry, "consumption", "max")
    cache.packSag = cache.maxVoltage and cache.voltage and math.max(0, cache.maxVoltage - cache.voltage) or nil
    cache.time = common.flightTimeText()

    local faults = 0
    local cautions = 0
    local criticalPack, warningPack = common.packLimits()
    if cache.esc and cache.esc >= common.getConfig("esc_max") then faults = faults + 1
    elseif cache.esc and cache.esc >= common.getConfig("esc_warn") then cautions = cautions + 1 end
    if cache.voltage and cache.voltage < criticalPack then faults = faults + 1
    elseif cache.voltage and cache.voltage < warningPack then cautions = cautions + 1 end
    if cache.fuel and cache.fuel <= common.getConfig("fuel_warn") then cautions = cautions + 1 end
    if cache.link and cache.link < common.getConfig("link_warn") then cautions = cautions + 1 end
    if cache.rpm and cache.rpm > common.getConfig("rpm_max") * 1.05 then cautions = cautions + 1 end

    if faults > 0 then
        cache.grade = "INSPECT"
        cache.gradeColor = C.red
        cache.gradeSub = "CRITICAL LIMIT EXCEEDED"
    elseif cautions > 0 then
        cache.grade = "REVIEW"
        cache.gradeColor = C.amber
        cache.gradeSub = tostring(cautions) .. " ITEM" .. (cautions == 1 and "" or "S") .. " FLAGGED"
    else
        cache.grade = "NOMINAL"
        cache.gradeColor = C.green
        cache.gradeSub = "FLIGHT DATA WITHIN LIMITS"
    end
    return cache
end

local function drawReportCard(x, y, w, h, title, value, accent, percent, compact)
    common.drawPanel(x, y, w, h, accent, nil)
    common.drawTextAligned(x + 10, y + (compact and 4 or 7), w - 20, title, compact and "FONT_XXS" or "FONT_XS", C.muted, "left")
    common.drawTextAligned(x + 10, y + (compact and 19 or 28), w - 20, value, compact and "FONT_S" or "FONT_L", C.white, "left")
    common.drawProgress(x + 10, y + h - (compact and 10 or 19), w - 20, compact and 5 or 7, percent or 0, accent)
end

local function paint(x, y, w, h, box, cache)
    cache = cache or box._cache or {}
    lcd.color(C.bg)
    lcd.drawFilledRectangle(floor(x), floor(y), floor(w), floor(h))

    local compact = h < 360
    local pad = compact and 10 or 12
    common.drawTextAligned(x + pad, y + (compact and 6 or 8), w * 0.5, "AEGIS // DEBRIEF", compact and "FONT_S" or "FONT_STD", C.cyan, "left")
    common.drawTextAligned(x + w - 240, y + (compact and 4 or 6), 228, cache.grade or "NOMINAL", compact and "FONT_S" or "FONT_L", cache.gradeColor or C.green, "right")

    local summaryY = y + (compact and 36 or 42)
    local summaryH = compact and 52 or 62
    common.drawPanel(x + pad, summaryY, w - pad * 2, summaryH, cache.gradeColor or C.green, nil)
    common.drawTextAligned(x + pad + 16, summaryY + (compact and 8 or 10), w * 0.58, cache.gradeSub or "FLIGHT DATA WITHIN LIMITS", compact and "FONT_XS" or "FONT_S", C.white, "left")
    common.drawTextAligned(x + w - 220, summaryY + (compact and 4 or 8), 190, cache.time or "00:00", compact and "FONT_L" or "FONT_XL", C.white, "right")
    common.drawTextAligned(x + w - 220, summaryY + (compact and 31 or 39), 190, "FLIGHT TIME", "FONT_XXS", C.muted, "right")

    local gap = compact and 6 or 10
    local gridY = summaryY + summaryH + gap
    local gridH = h - (gridY - y) - pad
    local cols = 3
    local rows = 3
    local cardW = floor((w - pad * 2 - gap * (cols - 1)) / cols)
    local cardH = floor((gridH - gap * (rows - 1)) / rows)

    local rpmColor = cache.rpm and cache.rpm > common.getConfig("rpm_max") * 1.05 and C.amber or C.cyan
    local escColor = common.escColor(cache.esc)
    local packColor = common.packColor(cache.voltage)
    local fuelColor = common.fuelColor(cache.fuel)
    local linkColor = common.linkColor(cache.link)
    local _, _, fullPack = common.packLimits()

    local cards = {
        {"MAX HEADSPEED", common.formatValue(cache.rpm, 0, " RPM"), rpmColor, cache.rpm and cache.rpm / common.getConfig("rpm_max") or 0},
        {"MAX ESC TEMP", common.formatValue(cache.esc, 0, "°C"), escColor, cache.esc and cache.esc / common.getConfig("esc_max") or 0},
        {"PEAK CURRENT", common.formatValue(cache.current, 1, " A"), C.violet, cache.current and cache.current / 150 or 0},
        {"MIN PACK", common.formatValue(cache.voltage, 2, " V"), packColor, cache.voltage and cache.voltage / fullPack or 0},
        {"MIN LINK", common.formatValue(cache.link, 0, "%"), linkColor, cache.link and cache.link / 100 or 0},
        {"LOWEST FUEL", common.formatValue(cache.fuel, 0, "%"), fuelColor, cache.fuel and cache.fuel / 100 or 0},
        {"CONSUMED", common.formatValue(cache.consumed, 0, " mAh"), C.amber, cache.consumed and cache.consumed / 5000 or 0},
        {"AVG CURRENT", common.formatValue(cache.avgCurrent, 1, " A"), C.violet, cache.avgCurrent and cache.avgCurrent / 100 or 0},
        {"PACK SAG", common.formatValue(cache.packSag, 2, " V"), C.cyan, cache.packSag and cache.packSag / 5 or 0}
    }

    for index = 1, #cards do
        local row = floor((index - 1) / cols)
        local col = (index - 1) % cols
        local card = cards[index]
        local cardX = x + pad + col * (cardW + gap)
        local cardY = gridY + row * (cardH + gap)
        drawReportCard(cardX, cardY, cardW, cardH, card[1], card[2], card[3], card[4], compact)
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
