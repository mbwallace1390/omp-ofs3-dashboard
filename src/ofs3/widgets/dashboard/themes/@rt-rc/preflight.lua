--[[ Aegis OFS3 preflight dashboard - center-text fix v3 - GPLv3 ]] --
local ofs3 = require("ofs3")
local lcd = lcd
local floor = math.floor
local min = math.min
local max = math.max
local tostring = tostring
local tonumber = tonumber

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

    local battery = ofs3.session and ofs3.session.batteryConfig or {}
    cache.cells = tonumber(battery.batteryCellCount) or 3
    cache.capacity = tonumber(battery.batteryCapacity) or 750

    local available, faults, warnings = 0, 0, 0
    local issues = {}
    local criticalPack, warningPack = common.packLimits()

    if not (ofs3.session and ofs3.session.telemetryState) then
        cache.status = "WAITING"
        cache.statusColor = C.muted
        cache.statusSub = "CONNECT TELEMETRY"
        cache.issueText = nil
        return cache
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
        cache.status, cache.statusColor, cache.statusSub, cache.issueText =
            "WAITING", C.muted, "WAITING FOR SENSOR DATA", nil
    elseif faults > 0 then
        cache.status, cache.statusColor, cache.statusSub =
            "CHECK", C.red, tostring(issueCount) .. " ITEM" .. (issueCount == 1 and "" or "S") .. " FLAGGED"
    elseif warnings > 0 then
        cache.status, cache.statusColor, cache.statusSub =
            "CAUTION", C.amber, tostring(issueCount) .. " ITEM" .. (issueCount == 1 and "" or "S") .. " TO REVIEW"
    else
        cache.status, cache.statusColor, cache.statusSub, cache.issueText =
            "READY", C.green, "SYSTEMS NOMINAL", nil
    end

    return cache
end

local function drawStatusMetric(x, y, w, h, title, value, accent, subtitle, percent, compact)
    common.drawPanel(x, y, w, h, accent, title)

    -- Reserve independent vertical zones for the large value, the caption,
    -- and the progress bar. This prevents the caption from sitting on the bar.
    common.drawTextAligned(
        x + 12, y + (compact and 31 or 34), w - 24,
        value, compact and "FONT_L" or "FONT_XL", C.white, "left"
    )

    local barH = compact and 7 or 8
    local barY = y + h - (compact and 14 or 16)
    local captionY = barY - (compact and 17 or 19)

    if subtitle then
        common.drawTextAligned(
            x + 12, captionY, w - 24,
            subtitle, "FONT_XXS", C.muted, "left"
        )
    end

    common.drawProgress(
        x + 12, barY, w - 24, barH,
        percent or 0, accent
    )
end

local function drawInfoRow(x, y, w, label, value, accent, compact)
    lcd.color(accent or C.cyan)
    lcd.drawFilledRectangle(floor(x), floor(y + 5), 7, 7)
    common.drawTextAligned(
        x + 14, y, w * 0.45, label,
        compact and "FONT_XXS" or "FONT_XS", C.muted, "left"
    )
    common.drawTextAligned(
        x + w * 0.45, y - (compact and 1 or 0), w * 0.55, value,
        compact and "FONT_XS" or "FONT_S", C.white, "right"
    )
end

local function paint(x, y, w, h, box, cache)
    cache = cache or box._cache or {}
    lcd.color(C.bg)
    lcd.drawFilledRectangle(floor(x), floor(y), floor(w), floor(h))

    local compact = h < 400
    local pad = compact and 10 or 12
    local topY = compact and 6 or 8

    common.drawTextAligned(
        x + pad, y + topY, w * 0.58,
        "AEGIS // PRE-FLIGHT",
        compact and "FONT_S" or "FONT_STD", C.cyan, "left"
    )
    common.drawTextAligned(
        x + w - 220, y + topY, 208,
        cache.status or "WAITING",
        compact and "FONT_S" or "FONT_STD",
        cache.statusColor or C.muted, "right"
    )

    local bodyY = y + (compact and 38 or 42)
    local bodyH = h - (compact and 48 or 54)
    local sideW = floor(w * 0.245)
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

    -- Left status cards
    drawStatusMetric(
        leftX, bodyY, sideW, cardH,
        "PACK VOLTAGE", common.formatValue(cache.voltage, 1, " V"),
        packColor, "main flight battery",
        cache.voltage and cache.voltage / packFull or 0, compact
    )

    drawStatusMetric(
        leftX, bodyY + cardH + pad, sideW, cardH,
        "RADIO LINK", common.formatValue(cache.link, 0, "%"),
        linkColor, "telemetry link quality",
        cache.link and cache.link / 100 or 0, compact
    )

    -- Center readiness panel
    common.drawPanel(centerX, bodyY, centerW, bodyH, cache.statusColor or C.muted, nil)
    local cx = centerX + centerW / 2
    local cy = bodyY + bodyH * (compact and 0.255 or 0.275)
    local radius = min(centerW * 0.24, bodyH * 0.19)

    common.drawHex(cx, cy, radius + (compact and 9 or 12), C.line2)
    common.drawHex(cx, cy, radius, cache.statusColor or C.muted)
    common.drawTextAligned(
        centerX, cy - (compact and 19 or 28), centerW,
        cache.status or "WAITING",
        compact and "FONT_L" or "FONT_XL", C.white, "center"
    )

    local messageY = bodyY + bodyH * (compact and 0.455 or 0.47)
    if cache.issueText then
        common.drawTextAligned(
            centerX + 14, messageY, centerW - 28,
            cache.issueText,
            compact and "FONT_XXS" or "FONT_XS", C.white, "center"
        )
        common.drawTextAligned(
            centerX + 14, messageY + (compact and 22 or 26), centerW - 28,
            cache.statusSub or "ITEM TO REVIEW",
            "FONT_XXS", cache.statusColor or C.muted, "center"
        )
    else
        common.drawTextAligned(
            centerX + 14, messageY + (compact and 16 or 18), centerW - 28,
            cache.statusSub or "CONNECT TELEMETRY",
            compact and "FONT_XS" or "FONT_S",
            cache.statusColor or C.muted, "center"
        )
    end

    local dividerY = bodyY + bodyH * (compact and 0.625 or 0.62)
    lcd.color(C.line)
    lcd.drawLine(
        floor(centerX + 18), floor(dividerY),
        floor(centerX + centerW - 18), floor(dividerY)
    )

    local fuelTitleY = dividerY + (compact and 10 or 13)
    common.drawTextAligned(
        centerX + 18, fuelTitleY, centerW * 0.56,
        "SMART FUEL", compact and "FONT_XS" or "FONT_S", C.muted, "left"
    )
    common.drawTextAligned(
        centerX + centerW * 0.56, fuelTitleY - (compact and 2 or 4),
        centerW * 0.36 - 18,
        common.formatValue(cache.fuel, 0, "%"),
        compact and "FONT_S" or "FONT_L", C.white, "right"
    )

    local segmentsY = fuelTitleY + (compact and 27 or 34)
    common.drawSegments(
        centerX + 18, segmentsY, centerW - 36,
        compact and 16 or 20, cache.fuel or 0,
        compact and 10 or 12, fuelColor
    )
    common.drawTextAligned(
        centerX + 18, segmentsY + (compact and 22 or 28), centerW - 36,
        "ESTIMATED ENERGY REMAINING",
        "FONT_XXS", C.muted, "center"
    )

    -- Right-side health and setup
    drawStatusMetric(
        rightX, bodyY, sideW, cardH,
        "ESC TEMPERATURE", common.formatValue(cache.esc, 0, "°C"),
        escColor, "controller thermal health",
        cache.esc and cache.esc / common.getConfig("esc_max") or 0, compact
    )

    local setupY = bodyY + cardH + pad
    common.drawPanel(rightX, setupY, sideW, cardH, C.violet, "FLIGHT SETUP")
    local rowStart = setupY + (compact and 34 or 42)
    local rowStep = floor((cardH - (compact and 48 or 57)) / 3)

    drawInfoRow(
        rightX + 14, rowStart, sideW - 28,
        "PROFILE", common.formatValue(cache.profile, 0, ""),
        C.violet, compact
    )
    drawInfoRow(
        rightX + 14, rowStart + rowStep, sideW - 28,
        "CELL COUNT", tostring(cache.cells or 3) .. "S",
        packColor, compact
    )
    drawInfoRow(
        rightX + 14, rowStart + rowStep * 2, sideW - 28,
        "CAPACITY", common.formatValue(cache.capacity, 0, " mAh"),
        C.cyan, compact
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
