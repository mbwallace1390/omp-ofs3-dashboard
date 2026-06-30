--[[ Aegis OFS3 preflight dashboard - GPLv3 ]] --
local ofs3 = require("ofs3")
local lcd = lcd
local floor = math.floor
local min = math.min
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

local function drawCheckRow(x, y, w, label, value, stateColor)
    lcd.color(stateColor)
    lcd.drawFilledRectangle(floor(x), floor(y + 6), 7, 7)
    common.drawTextAligned(x + 14, y, w * 0.45, label, "FONT_XS", C.muted, "left")
    common.drawTextAligned(x + w * 0.48, y, w * 0.52, value, "FONT_S", C.white, "right")
end

local function paint(x, y, w, h, box, cache)
    cache = cache or box._cache or {}
    lcd.color(C.bg)
    lcd.drawFilledRectangle(floor(x), floor(y), floor(w), floor(h))

    local pad = 12
    common.drawTextAligned(x + pad, y + 8, w * 0.55, "AEGIS // PRE-FLIGHT", "FONT_STD", C.cyan, "left")
    common.drawTextAligned(x + w - 220, y + 8, 208, cache.status or "WAITING", "FONT_STD", cache.statusColor or C.muted, "right")

    local bodyY = y + 42
    local bodyH = h - 54
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
    common.drawProgress(leftX + 12, bodyY + cardH - 36, sideW - 24, 9, cache.voltage and cache.voltage / packFull or 0, packColor)

    common.drawMetric(leftX, bodyY + cardH + pad, sideW, cardH, "RADIO LINK", common.formatValue(cache.link, 0, "%"), linkColor, "telemetry link quality")
    common.drawProgress(leftX + 12, bodyY + cardH * 2 + pad - 36, sideW - 24, 9, cache.link and cache.link / 100 or 0, linkColor)

    common.drawPanel(centerX, bodyY, centerW, bodyH, cache.statusColor or C.muted, nil)
    local cx = centerX + centerW / 2
    local cy = bodyY + bodyH * 0.42
    local radius = min(centerW * 0.33, bodyH * 0.32)
    common.drawHex(cx, cy, radius + 12, C.line2)
    common.drawHex(cx, cy, radius, cache.statusColor or C.muted)
    common.drawTextAligned(centerX, cy - 34, centerW, cache.status or "WAITING", "FONT_XXL", C.white, "center")
    if cache.issueText then
        common.drawTextAligned(centerX + 12, cy + 15, centerW - 24, cache.issueText, "FONT_XS", C.white, "center")
        common.drawTextAligned(centerX, cy + 40, centerW, cache.statusSub or "ITEM TO REVIEW", "FONT_XXS", cache.statusColor or C.muted, "center")
    else
        common.drawTextAligned(centerX, cy + 22, centerW, cache.statusSub or "CONNECT TELEMETRY", "FONT_XXS", cache.statusColor or C.muted, "center")
    end

    local segmentsY = bodyY + bodyH - 86
    common.drawTextAligned(centerX + 18, segmentsY - 22, centerW - 36, "SMART FUEL", "FONT_XS", C.muted, "left")
    common.drawTextAligned(centerX + 18, segmentsY - 24, centerW - 36, common.formatValue(cache.fuel, 0, "%"), "FONT_S", C.white, "right")
    common.drawSegments(centerX + 18, segmentsY, centerW - 42, 18, cache.fuel or 0, 12, fuelColor)
    lcd.color(fuelColor)
    lcd.drawFilledRectangle(floor(centerX + centerW - 20), floor(segmentsY + 5), 5, 8)
    common.drawStateBadge(centerX + 18, segmentsY + 31, centerW - 36, 27, cache.state, cache.stateColor)

    common.drawMetric(rightX, bodyY, sideW, cardH, "ESC THERMAL", common.formatValue(cache.esc, 0, "°C"), escColor, "controller temperature")
    common.drawProgress(rightX + 12, bodyY + cardH - 36, sideW - 24, 9, cache.esc and cache.esc / common.getConfig("esc_max") or 0, escColor)

    common.drawPanel(rightX, bodyY + cardH + pad, sideW, cardH, C.violet, "FLIGHT SETUP")
    drawCheckRow(rightX + 14, bodyY + cardH + pad + 42, sideW - 28, "PROFILE", common.formatValue(cache.profile, 0, ""), C.violet)
    drawCheckRow(rightX + 14, bodyY + cardH + pad + 78, sideW - 28, "PACK", common.formatValue(cache.voltage, 1, " V"), packColor)
    drawCheckRow(rightX + 14, bodyY + cardH + pad + 114, sideW - 28, "STATE", cache.state or "--", cache.stateColor or C.muted)
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
