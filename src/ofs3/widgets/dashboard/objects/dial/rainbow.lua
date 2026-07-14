--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local render = {}

local utils = ofs3.widgets.dashboard.utils
local getParam = utils.getParam
local resolveThresholdColor = utils.resolveThresholdColor
local resolveThemeColor = utils.resolveThemeColor
local resolveThemeColorArray = utils.resolveThemeColorArray

function render.dirty(box)
    return utils.dirtyOnDisplayValueChange(box)
end

local function drawRainbowArc(cx, cy, radius, thickness, startAngle, endAngle, colors)
    local inner = math.max(1, radius - thickness)
    local outer = radius
    local segmentCount = #colors
    if segmentCount == 0 then return end

    startAngle = startAngle % 360
    endAngle = endAngle % 360
    if endAngle <= startAngle then endAngle = endAngle + 360 end

    local angleSweep = endAngle - startAngle
    local anglePerSegment = angleSweep / segmentCount

    for i, color in ipairs(colors) do
        local segStart = startAngle + (i - 1) * anglePerSegment
        local segEnd = startAngle + i * anglePerSegment

        lcd.color(color)
        lcd.drawAnnulusSector(cx, cy, inner, outer, segStart, segEnd)
    end
end

local function calDialAngle(percent, startAngle, sweepAngle) return (startAngle or 135) + (sweepAngle or 270) * (percent or 0) end

local function ensureCfg(box)
    return utils.ensureCfg(box, function(cfg, box)
        cfg.source = getParam(box, "source")
        cfg.manualUnit = getParam(box, "unit")
        cfg.min = getParam(box, "min") or 0
        cfg.max = getParam(box, "max") or 100

        local showvalue = getParam(box, "showvalue")
        if showvalue == nil then showvalue = true end
        cfg.showvalue = showvalue

        cfg.titlepos = "bottom"
        cfg.font = getParam(box, "font") or "FONT_STD"
        cfg.textcolor = resolveThemeColor("textcolor", getParam(box, "textcolor"))
        cfg.fillbgcolor = resolveThemeColor("fillbgcolor", getParam(box, "fillbgcolor"))
        cfg.bgcolor = resolveThemeColor("bgcolor", getParam(box, "bgcolor"))
        cfg.title = getParam(box, "title")
        cfg.titlefont = getParam(box, "titlefont")
        cfg.titlealign = getParam(box, "titlealign")
        cfg.titlespacing = getParam(box, "titlespacing") or 0
        cfg.titlecolor = resolveThemeColor("titlecolor", getParam(box, "titlecolor"))
        cfg.titlepadding = getParam(box, "titlepadding")
        cfg.titlepaddingleft = getParam(box, "titlepaddingleft")
        cfg.titlepaddingright = getParam(box, "titlepaddingright")
        cfg.titlepaddingtop = getParam(box, "titlepaddingtop")
        cfg.titlepaddingbottom = getParam(box, "titlepaddingbottom")
        cfg.valuealign = getParam(box, "valuealign")
        cfg.valuepadding = getParam(box, "valuepadding")
        cfg.valuepaddingleft = getParam(box, "valuepaddingleft")
        cfg.valuepaddingright = getParam(box, "valuepaddingright")
        cfg.valuepaddingtop = getParam(box, "valuepaddingtop")
        cfg.valuepaddingbottom = getParam(box, "valuepaddingbottom")
        cfg.bandlabeloffset = getParam(box, "bandlabeloffset") or 14
        cfg.bandlabeloffsettop = getParam(box, "bandlabeloffsettop") or 8
        cfg.bandlabelfont = getParam(box, "bandlabelfont") or "FONT_XS"
        cfg.bandlabels = getParam(box, "bandlabels") or {"Low", "Med", "High"}
        cfg.bandcolors = resolveThemeColorArray("fillcolor", getParam(box, "bandcolors") or {"red", "orange", "green"})
        cfg.needlethickness = getParam(box, "needlethickness") or 5
        cfg.needlehubsize = getParam(box, "needlehubsize") or 7
        cfg.needlestartangle = getParam(box, "needlestartangle") or 150
        cfg.needlesweepangle = getParam(box, "needlesweepangle") or 240
        cfg.accentcolor = resolveThemeColor("accentcolor", getParam(box, "accentcolor"))
    end)
end

function render.wakeup(box)
    local cfg = ensureCfg(box)
    local telemetry = ofs3.tasks.telemetry

    local source = cfg.source
    local value, _, dynamicUnit
    if telemetry and source then value, _, dynamicUnit = telemetry.getSensor(source) end

    local manualUnit = cfg.manualUnit
    local unit

    if manualUnit ~= nil then
        unit = manualUnit
    elseif dynamicUnit ~= nil then
        unit = dynamicUnit
    elseif source and telemetry and telemetry.sensorTable[source] then
        unit = telemetry.sensorTable[source].unit_string or ""
    else
        unit = ""
    end

    local min, max = cfg.min, cfg.max
    local percent = 0
    if value and max ~= min then
        percent = (value - min) / (max - min)
        percent = math.max(0, math.min(1, percent))
    end

    local displayValue
    if value ~= nil then displayValue = utils.transformValue(value, box) end

    if value == nil then
        local maxDots = 3
        if box._dotCount == nil then box._dotCount = 0 end
        box._dotCount = (box._dotCount + 1) % (maxDots + 1)
        displayValue = string.rep(".", box._dotCount)
        if displayValue == "" then displayValue = "." end
        unit = nil
    end

    if type(displayValue) == "string" and displayValue:match("^%.+$") then unit = nil end

    box._currentDisplayValue = value

    box._dyn_value = value
    box._dyn_displayValue = displayValue
    box._dyn_percent = percent
    box._dyn_unit = unit
end

function render.paint(x, y, w, h, box)
    x, y = utils.applyOffset(x, y, box)
    local c = box._cfg or {}
    local percent = box._dyn_percent or 0
    local displayValue = box._dyn_displayValue
    local unit = box._dyn_unit

    lcd.font(_G[c.bandlabelfont] or FONT_XS)
    local subtextHeight = select(2, lcd.getTextSize("Med")) + 2

    local titleHeight = 0
    if c.title then
        lcd.font(_G[c.titlefont] or FONT_XS)
        local _, th = lcd.getTextSize(c.title)
        titleHeight = (th or 0) + (c.titlespacing or 0) + (c.titlepaddingtop or 0) + (c.titlepaddingbottom or 0)
    end

    local arcRegionY = y + subtextHeight
    local arcRegionH = h - subtextHeight - titleHeight
    local arcMargin = 2
    local usableW = w - arcMargin * 2
    local usableH = arcRegionH - arcMargin
    local thickness = c.thickness or math.max(6, math.min(usableW, usableH) * 0.25)
    local radius = math.min(usableW / 2, usableH) - (thickness / 2)
    if radius < 8 then radius = 8 end
    local cx = x + w / 2
    local cy = arcRegionY + arcRegionH / 2 + 15

    if c.bgcolor then
        lcd.color(c.bgcolor)
        lcd.drawFilledRectangle(x, y, w, h)
    end

    local bandCount = #c.bandlabels
    local startAngle = 240
    local endAngle = 120
    if bandCount > 0 and c.bandcolors then drawRainbowArc(cx, cy, radius, thickness, startAngle, endAngle, c.bandcolors) end

    local needleHubYOffset = 6

    if percent then
        local angleDeg = calDialAngle(percent, c.needlestartangle or 150, c.needlesweepangle or 240)
        local needleLen = radius
        local cy_needle = cy
        utils.drawBarNeedle(cx, cy_needle, needleLen, c.needlethickness, angleDeg, c.accentcolor)
        lcd.color(c.accentcolor)
        lcd.drawFilledCircle(cx, cy_needle, c.needlehubsize)
    end

    local sweep = (endAngle - startAngle + 360) % 360
    lcd.font(_G[c.bandlabelfont] or FONT_XS)

    local angleOffset = -30

    for i = 1, bandCount do
        local midAngle = startAngle - (i - 0.5) * (sweep / bandCount) + angleOffset
        local degNorm = (midAngle + 360) % 360

        local labelRadius
        if degNorm > 80 and degNorm < 100 then
            labelRadius = radius + thickness / 2 + c.bandlabeloffsettop
        else
            labelRadius = radius + thickness / 2 + c.bandlabeloffset
        end

        local tx = cx + labelRadius * math.cos(math.rad(midAngle))
        local ty = cy - labelRadius * math.sin(math.rad(midAngle))
        ty = ty + 12

        local label = c.bandlabels[i]
        if label then
            local tw, th = lcd.getTextSize(label)
            lcd.color(c.textcolor)
            lcd.drawText(tx - tw / 2, ty - th / 2, label)
        end
    end

    utils.box(x, y, w, h, c.title, c.titlepos, c.titlealign, c.titlefont, c.titlespacing, c.titlecolor, c.titlepadding, c.titlepaddingleft, c.titlepaddingright, c.titlepaddingtop, c.titlepaddingbottom, c.showvalue ~= false and displayValue or nil, c.showvalue ~= false and unit or nil, c.font,
        c.valuealign, c.textcolor, c.valuepadding, c.valuepaddingleft, c.valuepaddingright, c.valuepaddingtop, c.valuepaddingbottom, nil)
end

return render
