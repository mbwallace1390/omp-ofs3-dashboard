--[[ Aegis OFS3 preflight dashboard - GPLv3 ]] --
local ofs3 = require("ofs3")
local lcd = lcd
local floor = math.floor
local min = math.min
local max = math.max
local tostring = tostring

local common = assert(loadfile("SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/themes/@rt-rc/common.lua"))()
local C = common.C

local layout = {cols = 12, rows = 12, padding = 0}
local header_layout = common.headerLayout()
local header_boxes = common.headerBoxes()

local function wakeup(box, telemetry)
    local cache = box._cache or {}
    box._cache = cache

    cache.fuel = common.sensor(telemetry, "smartfuel")
    cache.esc = common.sensor(telemetry, "temp_esc")
    cache.link = common.sensor(telemetry, "rssi")
    cache.profile = common.sensor(telemetry, "profile")
    cache.voltage = common.sensor(telemetry, "voltage")
    cache.state, cache.stateColor, cache.isArmed = common.flightState(telemetry)

    local available = 0
    local faults = 0
    local warnings = 0
    local issues = {}
    local criticalPack, warningPack = common.packLimits()

    if not (ofs3.session and ofs3.session.telemetryState) then
        cache.status = "WAITING"
        cache.statusColor = C.muted
        cache.statusSub = "CONNECT TELEMETRY"
        cache.issueText = nil
        return cache
    end

    if cache.isArmed == true then
        faults = faults + 1
        issues[#issues + 1] = "MODEL IS ARMED"
    end

    if cache.fuel ~= nil then
        available = available + 1
        if cache.fuel <= common.getConfig("fuel_warn") then
            warnings = warnings + 1
            issues[#issues + 1] = "SMART FUEL " .. common.formatValue(cache.fuel, 0, "%") .. " AT RESERVE"
        end
    end

    if cache.voltage ~= nil then
        available = available + 1
        if cache.voltage < criticalPack then
            faults = faults + 1
            issues[#issues + 1] = "PACK " .. common.formatValue(cache.voltage, 1, "V") .. " BELOW MINIMUM"
        elseif cache.voltage < warningPack then
            warnings = warnings + 1
            issues[#issues + 1] = "PACK " .. common.formatValue(cache.voltage, 1, "V") .. " LOW"
        end
    end

    if cache.esc ~= nil then
        available = available + 1
        if cache.esc >= common.getConfig("esc_max") then
            faults = faults + 1
            issues[#issues + 1] = "ESC " .. common.formatValue(cache.esc, 0, "°C") .. " AT LIMIT"
        elseif cache.esc >= common.getConfig("esc_warn") then
            warnings = warnings + 1
            issues[#issues + 1] = "ESC " .. common.formatValue(cache.esc, 0, "°C") .. " ABOVE WARNING"
        end
    end

    if cache.link ~= nil then
        available = available + 1
        if cache.link < common.getConfig("link_warn") then
            warnings = warnings + 1
            issues[#issues + 1] = "LINK " .. common.formatValue(cache.link, 0, "%") .. " LOW"
        end
    end

    local issueCount = faults + warnings
    cache.issueText = issues[1]
    if issueCount > 1 and cache.issueText then
        cache.issueText = cache.issueText .. "  +" .. tostring(issueCount - 1) .. " MORE"
    end

    if available == 0 then
        cache.status = "WAITING"
        cache.statusColor = C.muted
        cache.statusSub = "WAITING FOR SENSOR DATA"
        cache.issueText = nil
    elseif faults > 0 then
        cache.status = "CHECK"
        cache.statusColor = C.red
        cache.statusSub = tostring(issueCount) .. " ITEM" .. (issueCount == 1 and "" or "S") .. " FLAGGED"
    elseif warnings > 0 then
        cache.status = "CAUTION"
        cache.statusColor = C.amber
        cache.statusSub = tostring(issueCount) .. " ITEM" .. (issueCount == 1 and "" or "S") .. " TO REVIEW"
    else
        cache.status = "READY"
        cache.statusColor = C.green
        cache.statusSub = "SYSTEMS NOMINAL"
        cache.issueText = nil
    end

    return cache
end

local function drawCheckRow(x, y, w, label, value, stateColor, compact)
    lcd.color(stateColor)
    lcd.drawFilledRectangle(floor(x), floor(y + (compact and 5 or 6)), 7, 7)
    common.drawTextAligned(x + 14, y, w * 0.44, label, compact and "FONT_XXS" or "FONT_XS", C.muted, "left")
    common.drawTextAligned(x + w * 0.46, y - (compact and 1 or 0), w * 0.54, value, compact and "FONT_XS" or "FONT_S", C.white, "right")
end

local function paint(x, y, w, h, box, cache)
    cache = cache or box._cache or {}
    lcd.color(C.bg)
    lcd.drawFilledRectangle(floor(x), floor(y), floor(w), floor(h))

    local compact = h < 360
    local pad = compact and 10 or 12
    local titleY = compact and 6 or 8
    common.drawTextAligned(x + pad, y + titleY, w * 0.55, "AEGIS // PRE-FLIGHT", compact and "FONT_S" or "FONT_STD", C.cyan, "left")
    common.drawTextAligned(x + w - 220, y + titleY, 208, cache.status or "WAITING", compact and "FONT_S" or "FONT_STD", cache.statusColor or C.muted, "right")

    local bodyY = y + (compact and 38 or 42)
    local bodyH = h - (compact and 48 or 54)
    local sideW = floor(w * 0.25)
    local centerW = w - sideW * 2 - pad * 4
    local leftX = x + pad
    local centerX = leftX + sideW + pad
    local rightX = centerX + centerW + pad
    local cardH = floor((bodyH - pad) / 2)

    local fuelColor = common.fuelColor(cache.fuel)
    local packColor = common.packColor(cache.voltage)
    local escColor = common.escColor(cache.esc)
    local linkColor = common.linkColor(cache.link)
    local _, _, packFull = common.packLimits()

    common.drawMetric(leftX, bodyY, sideW, cardH, "PACK VOLTAGE", common.formatValue(cache.voltage, 1, " V"), packColor, "main flight battery")
    common.drawProgress(leftX + 12, bodyY + cardH - 34, sideW - 24, 8, cache.voltage and cache.voltage / packFull or 0, packColor)

    common.drawMetric(leftX, bodyY + cardH + pad, sideW, cardH, "RADIO LINK", common.formatValue(cache.link, 0, "%"), linkColor, "telemetry link quality")
    common.drawProgress(leftX + 12, bodyY + cardH * 2 + pad - 34, sideW - 24, 8, cache.link and cache.link / 100 or 0, linkColor)

    common.drawPanel(centerX, bodyY, centerW, bodyH, cache.statusColor or C.muted, nil)
    local cx = centerX + centerW / 2
    local cy
    local radius
    if compact then
        cy = bodyY + bodyH * 0.29
        radius = min(centerW * 0.25, bodyH * 0.22)
    else
        cy = bodyY + bodyH * 0.42
        radius = min(centerW * 0.33, bodyH * 0.32)
    end

    common.drawHex(cx, cy, radius + (compact and 9 or 12), C.line2)
    common.drawHex(cx, cy, radius, cache.statusColor or C.muted)
    common.drawTextAligned(centerX, cy - (compact and 23 or 34), centerW, cache.status or "WAITING", compact and "FONT_XL" or "FONT_XXL", C.white, "center")
    if cache.issueText then
        common.drawTextAligned(centerX + 12, cy + (compact and 7 or 15), centerW - 24, cache.issueText, compact and "FONT_XXS" or "FONT_XS", C.white, "center")
        common.drawTextAligned(centerX, cy + (compact and 25 or 40), centerW, cache.statusSub or "ITEM TO REVIEW", "FONT_XXS", cache.statusColor or C.muted, "center")
    else
        common.drawTextAligned(centerX, cy + (compact and 17 or 22), centerW, cache.statusSub or "CONNECT TELEMETRY", "FONT_XXS", cache.statusColor or C.muted, "center")
    end

    local segmentsY = compact and (bodyY + bodyH - 74) or (bodyY + bodyH - 86)
    common.drawTextAligned(centerX + 18, segmentsY - (compact and 19 or 22), centerW - 36, "SMART FUEL", "FONT_XS", C.muted, "left")
    common.drawTextAligned(centerX + 18, segmentsY - (compact and 21 or 24), centerW - 36, common.formatValue(cache.fuel, 0, "%"), compact and "FONT_XS" or "FONT_S", C.white, "right")
    common.drawSegments(centerX + 18, segmentsY, centerW - 42, compact and 14 or 18, cache.fuel or 0, compact and 10 or 12, fuelColor)
    lcd.color(fuelColor)
    lcd.drawFilledRectangle(floor(centerX + centerW - 20), floor(segmentsY + (compact and 3 or 5)), 5, 8)
    common.drawStateBadge(centerX + 18, segmentsY + (compact and 25 or 31), centerW - 36, compact and 25 or 27, cache.state, cache.stateColor)

    common.drawMetric(rightX, bodyY, sideW, cardH, "ESC THERMAL", common.formatValue(cache.esc, 0, "°C"), escColor, "controller temperature")
    common.drawProgress(rightX + 12, bodyY + cardH - 34, sideW - 24, 8, cache.esc and cache.esc / common.getConfig("esc_max") or 0, escColor)

    local setupY = bodyY + cardH + pad
    common.drawPanel(rightX, setupY, sideW, cardH, C.violet, "FLIGHT SETUP")
    local rowStart = setupY + (compact and 34 or 42)
    local rowStep = compact and max(20, floor((cardH - 43) / 3)) or 36
    drawCheckRow(rightX + 14, rowStart, sideW - 28, "PROFILE", common.formatValue(cache.profile, 0, ""), C.violet, compact)
    drawCheckRow(rightX + 14, rowStart + rowStep, sideW - 28, "PACK", common.formatValue(cache.voltage, 1, " V"), packColor, compact)
    drawCheckRow(rightX + 14, rowStart + rowStep * 2, sideW - 28, "STATE", cache.state or "--", cache.stateColor or C.muted, compact)
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
