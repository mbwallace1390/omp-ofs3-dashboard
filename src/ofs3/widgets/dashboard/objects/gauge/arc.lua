--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local render = {}

local utils = ofs3.widgets.dashboard.utils
local getParam = utils.getParam
local resolveThemeColor = utils.resolveThemeColor
local resolveThresholdColor = utils.resolveThresholdColor
local drawArc = utils.drawArc

function render.dirty(box)
    return utils.dirtyOnDisplayValueChange(box)
end

local function ensureCfg(box)
    return utils.ensureCfg(box, function(cfg, box)
        cfg.source = getParam(box, "source")
        cfg.arcmax = getParam(box, "arcmax") == true
        cfg.manualUnit = getParam(box, "unit")
        cfg.rawMin = getParam(box, "min") or 0
        cfg.rawMax = getParam(box, "max") or 100
        cfg.thresholds = getParam(box, "thresholds")

        cfg.fillbgcolor = resolveThemeColor("fillbgcolor", getParam(box, "fillbgcolor"))
        cfg.bgcolor = resolveThemeColor("bgcolor", getParam(box, "bgcolor"))
        cfg.titlecolor = resolveThemeColor("titlecolor", getParam(box, "titlecolor"))

        cfg.title = getParam(box, "title")
        cfg.titlepos = getParam(box, "titlepos") or (cfg.title and "top")
        cfg.titlealign = getParam(box, "titlealign")
        cfg.titlefont = getParam(box, "titlefont")
        cfg.titlespacing = getParam(box, "titlespacing") or 0
        cfg.titlepadding = getParam(box, "titlepadding")
        cfg.titlepaddingleft = getParam(box, "titlepaddingleft")
        cfg.titlepaddingright = getParam(box, "titlepaddingright")
        cfg.titlepaddingtop = getParam(box, "titlepaddingtop")
        cfg.titlepaddingbottom = getParam(box, "titlepaddingbottom")

        cfg.font = getParam(box, "font") or "FONT_STD"
        cfg.maxfont = getParam(box, "maxfont") or "FONT_S"
        cfg.decimals = getParam(box, "decimals")
        cfg.valuealign = getParam(box, "valuealign")
        cfg.valuepadding = getParam(box, "valuepadding")
        cfg.valuepaddingleft = getParam(box, "valuepaddingleft")
        cfg.valuepaddingright = getParam(box, "valuepaddingright")
        cfg.valuepaddingtop = getParam(box, "valuepaddingtop") or 18
        cfg.valuepaddingbottom = getParam(box, "valuepaddingbottom")

        cfg.thickness = getParam(box, "thickness")
        cfg.maxprefix = getParam(box, "maxprefix") or "+"
        cfg.maxpadding = getParam(box, "maxpadding") or 0
        cfg.maxpaddingleft = getParam(box, "maxpaddingleft") or 0
        cfg.maxpaddingtop = getParam(box, "maxpaddingtop") or 0
        cfg.gaugepadding = getParam(box, "gaugepadding") or 0
        cfg.gaugepaddingbottom = getParam(box, "gaugepaddingbottom") or 0
    end)
end

function render.wakeup(box)
    local cfg = ensureCfg(box)
    local telemetry = ofs3.tasks.telemetry

    local source = cfg.source
    local value, _, dynamicUnit
    if telemetry and source then value, _, dynamicUnit = telemetry.getSensor(source) end

    local arcmax = cfg.arcmax
    local maxval = nil
    if arcmax and source then
        local stats = ofs3.tasks.telemetry.getSensorStats(source)
        local currentMax = stats and stats.max or nil
        local prevMax = box._dyn_maxval
        maxval = currentMax or prevMax
    end

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

    local min = cfg.rawMin
    local max = cfg.rawMax

    local isFahrenheit = unit and unit:match("F$") ~= nil
    local isFeet = unit and unit:lower():match("ft$") ~= nil

    if isFahrenheit then
        min = min * 9 / 5 + 32
        max = max * 9 / 5 + 32
        if arcmax and maxval then maxval = maxval * 9 / 5 + 32 end
    elseif isFeet then
        min = min * 3.28084
        max = max * 3.28084
        if arcmax and maxval then maxval = maxval * 3.28084 end
    end

    local thresholds = cfg.thresholds
    local adjustedThresholds = thresholds

    if thresholds and (isFahrenheit or isFeet) then
        adjustedThresholds = {}
        for i, t in ipairs(thresholds) do
            local newT = {}
            for k, v in pairs(t) do newT[k] = v end
            if type(newT.value) == "number" then
                if isFahrenheit then
                    newT.value = newT.value * 9 / 5 + 32
                elseif isFeet then
                    newT.value = newT.value * 3.28084
                end
            end
            table.insert(adjustedThresholds, newT)
        end
    end

    local percent = 0
    if value and max ~= min then
        percent = (value - min) / (max - min)
        percent = math.max(0, math.min(1, percent))
    end
    local maxPercent = 0
    if arcmax and maxval and max ~= min then
        maxPercent = (maxval - min) / (max - min)
        maxPercent = math.max(0, math.min(1, maxPercent))
    end

    local displayValue
    if value ~= nil then displayValue = utils.transformValue(value, box) end

    local displayMaxValue = nil
    if arcmax and maxval ~= nil then displayMaxValue = utils.transformValue(maxval, box) end

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
    box._dyn_maxval = maxval
    box._dyn_displayValue = displayValue
    box._dyn_displayMaxValue = displayMaxValue
    box._dyn_arcmax = arcmax
    box._dyn_min = min
    box._dyn_max = max
    box._dyn_percent = percent
    box._dyn_maxPercent = maxPercent
    box._dyn_unit = unit
    box._dyn_textcolor = resolveThresholdColor(value, box, "textcolor", "textcolor", adjustedThresholds)
    box._dyn_maxtextcolor = resolveThresholdColor(maxval, box, "maxtextcolor", "textcolor", adjustedThresholds)
    box._dyn_fillcolor = resolveThresholdColor(value, box, "fillcolor", "fillcolor", adjustedThresholds)
    box._dyn_maxfillcolor = resolveThresholdColor(maxval, box, "fillcolor", "fillcolor", adjustedThresholds)
end

function render.paint(x, y, w, h, box)
    x, y = utils.applyOffset(x, y, box)
    local c = box._cfg or {}

    local percent = box._dyn_percent or 0
    local arcmax = box._dyn_arcmax
    local maxval = box._dyn_maxval
    local max = box._dyn_max
    local min = box._dyn_min
    local maxPercent = box._dyn_maxPercent or 0
    local fillcolor = box._dyn_fillcolor
    local maxfillcolor = box._dyn_maxfillcolor

    local titleHeight = 0
    if c.title then
        lcd.font(_G[c.titlefont] or FONT_XS)
        local _, th = lcd.getTextSize(c.title)
        titleHeight = (th or 0) + (c.titlespacing or 0) + (c.titlepaddingtop or 0) + (c.titlepaddingbottom or 0)
    end

    local arcRegionY, arcRegionH, cy, radius
    local thickness, maxRadius

    if c.titlepos == "top" then
        arcRegionY = y + titleHeight
        arcRegionH = h - titleHeight - (c.gaugepaddingbottom or 0)
        cy = arcRegionY + arcRegionH * 0.5
    elseif c.titlepos == "bottom" then
        arcRegionY = y
        arcRegionH = h - titleHeight - (c.gaugepaddingbottom or 0)
        cy = arcRegionY + arcRegionH * 0.6
    else
        arcRegionY = y
        arcRegionH = h - (c.gaugepaddingbottom or 0)
        cy = arcRegionY + arcRegionH * 0.55
    end

    thickness = c.thickness or math.max(6, math.min(w, arcRegionH) * 0.07)
    local gaugepadding = c.gaugepadding or 0
    maxRadius = (arcRegionH / 2) - (thickness / 2)
    radius = math.min((w / 2) - gaugepadding, maxRadius + 8)

    if c.bgcolor then
        lcd.color(c.bgcolor)
        lcd.drawFilledRectangle(x, y, w, h)
    end

    local cx = x + w / 2
    local startAngle = 225
    local endAngle = (startAngle + 270) % 360

    drawArc(cx, cy, radius, thickness, startAngle, endAngle, c.fillbgcolor)

    if percent and percent > 0 then
        local valueEndAngle = (startAngle + 270 * percent) % 360
        drawArc(cx, cy, radius, thickness, startAngle, valueEndAngle, fillcolor)
    end

    if arcmax and maxval and max ~= min and maxPercent > 0 then
        local innerRadius = radius * 0.74
        local innerThickness = thickness * 0.8
        local maxEndAngle = (startAngle + 270 * maxPercent) % 360
        drawArc(cx, cy, innerRadius, innerThickness, startAngle, maxEndAngle, maxfillcolor)
    end

    utils.box(x, y, w, h, c.title, c.titlepos, c.titlealign, c.titlefont, c.titlespacing, c.titlecolor, c.titlepadding, c.titlepaddingleft, c.titlepaddingright, c.titlepaddingtop, c.titlepaddingbottom, box._dyn_displayValue, box._dyn_unit, c.font, c.valuealign, box._dyn_textcolor, c.valuepadding,
        c.valuepaddingleft, c.valuepaddingright, c.valuepaddingtop, c.valuepaddingbottom, nil)

    if arcmax and maxval then
        local maxStr = tostring(c.maxprefix or "") .. (box._dyn_displayMaxValue or maxval) .. (box._dyn_unit or "")
        local maxTextColor = box._dyn_maxtextcolor or box._dyn_textcolor
        lcd.color(maxTextColor)
        lcd.font(_G[c.maxfont] or FONT_S)
        local tw2, th2 = lcd.getTextSize(maxStr)
        lcd.drawText(cx - tw2 / 2 + (c.maxpaddingleft or 0), cy + radius * 0.25 + (c.maxpadding or 0) + (c.maxpaddingtop or 0), maxStr)
    end
end

return render
