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

function render.dirty(box)
    return utils.dirtyOnDisplayValueChange(box)
end

local function drawFilledRoundedRectangle(x, y, w, h, r)
    x = math.floor(x + 0.5)
    y = math.floor(y + 0.5)
    w = math.floor(w + 0.5)
    h = math.floor(h + 0.5)
    r = r or 0
    if r > 0 then
        lcd.drawFilledRectangle(x + r, y, w - 2 * r, h)
        lcd.drawFilledRectangle(x, y + r, r, h - 2 * r)
        lcd.drawFilledRectangle(x + w - r, y + r, r, h - 2 * r)
        lcd.drawFilledCircle(x + r, y + r, r)
        lcd.drawFilledCircle(x + w - r - 1, y + r, r)
        lcd.drawFilledCircle(x + r, y + h - r - 1, r)
        lcd.drawFilledCircle(x + w - r - 1, y + h - r - 1, r)
    else
        lcd.drawFilledRectangle(x, y, w, h)
    end
end

local function drawBatteryBox(x, y, w, h, percent, gaugeorientation, batterysegments, batteryspacing, fillbgcolor, fillcolor, batteryframe, batteryframethickness, accentcolor, battery, batterysegmentpaddingtop, batterysegmentpaddingbottom, batterysegmentpaddingleft, batterysegmentpaddingright)

    local frameThickness = batteryframethickness or 4
    local segments = batterysegments or 5
    local spacing = batteryspacing or 2

    if gaugeorientation == "vertical" then
        local capH = 0
        if batteryframe then
            local maxCapH = math.floor(h * 0.5)
            capH = math.min(math.max(8, math.floor(h * 0.10)), maxCapH)

        end
        local bodyY = y + capH
        local bodyH = h - capH

        if batteryframe then
            lcd.color(accentcolor)
            local capW = math.min(math.max(4, math.floor(w * 0.40)), w)
            for i = 0, frameThickness - 1 do lcd.drawFilledRectangle(x + (w - capW) / 2 - i, y + i, capW + 2 * i, capH - i) end
        end

        if battery then
            local segCount = math.max(1, segments)
            local fillSegs = math.floor(segCount * percent + 0.5)
            local totalSpacing = (segCount - 1) * spacing
            local segH = (bodyH - totalSpacing) / segCount
            for i = 1, segCount do
                local segY = bodyY + bodyH - (segH + spacing) * i + spacing
                lcd.color(i <= fillSegs and fillcolor or fillbgcolor)
                lcd.drawFilledRectangle(x, segY, w, segH)
            end
        else
            lcd.color(fillbgcolor)
            lcd.drawFilledRectangle(x, bodyY, w, bodyH)
            if percent > 0 then
                lcd.color(fillcolor)
                local fillH = math.floor(bodyH * percent)
                local fillY = bodyY + bodyH - fillH
                lcd.drawFilledRectangle(x, fillY, w, fillH)
            end
        end

        if batteryframe then
            lcd.color(accentcolor)
            lcd.drawRectangle(x, bodyY, w, bodyH, frameThickness)
        end

    else

        local maxCapW = math.floor(w * 0.5)
        local capOffset = math.min(math.max(8, math.floor(w * 0.03)), maxCapW)
        local bodyW = w - capOffset

        if battery then
            local segCount = math.max(1, segments)
            local fillSegs = math.floor(segCount * percent + 0.5)
            local totalSpacing = (segCount - 1) * spacing
            local segW = (bodyW - totalSpacing) / segCount
            local segPadT = batterysegmentpaddingtop or 0
            local segPadB = batterysegmentpaddingbottom or 0
            local segHeight = h - segPadT - segPadB
            local segPadL = batterysegmentpaddingleft or 0
            local segPadR = batterysegmentpaddingright or 0
            local segAvailW = bodyW - segPadL - segPadR
            local segW = (segAvailW - totalSpacing) / segCount

            for i = 1, segCount do
                local segX = x + segPadL + (i - 1) * (segW + spacing)
                lcd.color(i <= fillSegs and fillcolor or fillbgcolor)
                lcd.drawFilledRectangle(segX, y + segPadT, segW, segHeight)
            end
        else
            lcd.color(fillbgcolor)
            lcd.drawFilledRectangle(x, y, bodyW, h)
            if percent > 0 then
                lcd.color(fillcolor)
                local fillW = math.floor(bodyW * percent)
                lcd.drawFilledRectangle(x, y, fillW, h)
            end
        end

        if batteryframe then
            lcd.color(accentcolor)
            lcd.drawRectangle(x, y, bodyW, h, frameThickness)
            local capW = capOffset
            local capH = math.min(math.max(4, math.floor(h * 0.33)), h)
            for i = 0, frameThickness - 1 do lcd.drawFilledRectangle(x + bodyW + i, y + (h - capH) / 2 + i, capW, capH - 2 * i) end
        end
    end
end

local function ensureCfg(box)
    return utils.ensureCfg(box, function(cfg, box)
        local source = getParam(box, "source")
        cfg.source = source
        cfg.manualUnit = getParam(box, "unit")
        cfg.hidevalue = getParam(box, "hidevalue")

        if source == "txbatt" then
            cfg.min = getParam(box, "min") or 7.2
            cfg.max = getParam(box, "max") or 8.4
        else
            cfg.min = getParam(box, "min") or 0
            cfg.max = getParam(box, "max") or 100
        end

        cfg.title = getParam(box, "title")
        cfg.titlefont = getParam(box, "titlefont")
        cfg.titlespacing = getParam(box, "titlespacing") or 0
        cfg.titlepos = getParam(box, "titlepos") or (cfg.title and "top" or nil)

        local title_area_top, title_area_bottom = 0, 0
        if cfg.title and cfg.title ~= "" then
            lcd.font(_G[cfg.titlefont] or FONT_XS)
            local _, tsizeH = lcd.getTextSize(cfg.title)
            if cfg.titlepos == "bottom" then
                title_area_bottom = (tsizeH or 0) + (getParam(box, "titlepaddingtop") or 0) + (getParam(box, "titlepaddingbottom") or 0) + cfg.titlespacing
            else
                title_area_top = (tsizeH or 0) + (getParam(box, "titlepaddingtop") or 0) + (getParam(box, "titlepaddingbottom") or 0) + cfg.titlespacing
            end
        end
        cfg.title_area_top = title_area_top
        cfg.title_area_bottom = title_area_bottom

        cfg.battadv = getParam(box, "battadv")

        cfg.fillbgcolor = resolveThemeColor("fillbgcolor", getParam(box, "fillbgcolor"))
        cfg.bgcolor = resolveThemeColor("bgcolor", getParam(box, "bgcolor"))
        cfg.titlecolor = resolveThemeColor("titlecolor", getParam(box, "titlecolor"))
        cfg.accentcolor = resolveThemeColor("accentcolor", getParam(box, "accentcolor"))
        cfg.font = getParam(box, "font") or "FONT_XL"
        cfg.titlealign = getParam(box, "titlealign")
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
        cfg.gaugeorientation = getParam(box, "gaugeorientation") or "horizontal"
        cfg.gpad_left = getParam(box, "gaugepaddingleft")
        cfg.gpad_right = getParam(box, "gaugepaddingright")
        cfg.gpad_top = getParam(box, "gaugepaddingtop")
        cfg.gpad_bottom = getParam(box, "gaugepaddingbottom")
        cfg.roundradius = getParam(box, "roundradius")
        cfg.battery = getParam(box, "battery")
        cfg.batteryframe = getParam(box, "batteryframe")
        cfg.batteryframethickness = getParam(box, "batteryframethickness")
        cfg.batterysegments = getParam(box, "batterysegments")
        cfg.batteryspacing = getParam(box, "batteryspacing")
        cfg.batterysegmentpaddingleft = getParam(box, "batterysegmentpaddingleft") or 0
        cfg.batterysegmentpaddingright = getParam(box, "batterysegmentpaddingright") or 0
        cfg.batterysegmentpaddingtop = getParam(box, "batterysegmentpaddingtop") or 0
        cfg.batterysegmentpaddingbottom = getParam(box, "batterysegmentpaddingbottom") or 0
        cfg.battadvfont = getParam(box, "battadvfont") or "FONT_S"
        cfg.battadvblockalign = getParam(box, "battadvblockalign") or "right"
        cfg.battadvvaluealign = getParam(box, "battadvvaluealign") or "left"
        cfg.battadvpadding = getParam(box, "battadvpadding") or 4
        cfg.battadvpaddingleft = getParam(box, "battadvpaddingleft") or 0
        cfg.battadvpaddingright = getParam(box, "battadvpaddingright") or 0
        cfg.battadvpaddingtop = getParam(box, "battadvpaddingtop") or 0
        cfg.battadvpaddingbottom = getParam(box, "battadvpaddingbottom") or 0
        cfg.battadvgap = getParam(box, "battadvgap") or 5
        cfg.battstats = getParam(box, "battstats") or false
        cfg.subtext = getParam(box, "subtext")
        cfg.subtextfont = getParam(box, "subtextfont") or "FONT_XS"
        cfg.subtextalign = getParam(box, "subtextalign") or "left"
        cfg.subtextpaddingleft = getParam(box, "subtextpaddingleft") or 0
        cfg.subtextpaddingright = getParam(box, "subtextpaddingright") or 0
        cfg.subtextpaddingtop = getParam(box, "subtextpaddingtop") or 0
        cfg.subtextpaddingbottom = getParam(box, "subtextpaddingbottom") or 0
    end)
end

function render.wakeup(box)
    local cfg = ensureCfg(box)
    local telemetry = ofs3.tasks.telemetry

    local source = cfg.source
    local value, _, dynamicUnit

    if source == "txbatt" then
        local src = system.getSource({category = CATEGORY_SYSTEM, member = MAIN_VOLTAGE})
        value = src and src.value and src:value() or nil
        dynamicUnit = "V"
    elseif telemetry and source then
        value, _, dynamicUnit = telemetry.getSensor(source)
    else
        value = getParam(box, "value")
    end

    local getSensor = telemetry and telemetry.getSensor
    local voltage = getSensor and getSensor("voltage") or 0
    local cellCount = getSensor and getSensor("cell_count") or 0
    local consumed = getSensor and getSensor("consumption") or 0
    local perCellVoltage = (cellCount > 0) and (voltage / cellCount) or 0

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

    local displayValue
    if value ~= nil then displayValue = utils.transformValue(value, box) end

    if cfg.hidevalue == true then displayValue = nil end

    local min, max = cfg.min, cfg.max

    local percent = 0
    if value and max ~= min then
        percent = (value - min) / (max - min)
        percent = math.max(0, math.min(1, percent))
    end

    if value == nil then
        local maxDots = 3
        if box._dotCount == nil then box._dotCount = 0 end
        box._dotCount = (box._dotCount + 1) % (maxDots + 1)
        displayValue = string.rep(".", box._dotCount)
        if displayValue == "" then displayValue = "." end
        unit = nil
    end

    if cfg.battadv then
        box._batteryLines = {line1 = string.format("%.1fv / %.2fv (%dS)", voltage, perCellVoltage, cellCount), line2 = string.format("%d mah", consumed)}
    else
        box._batteryLines = nil
    end

    if type(displayValue) == "string" and displayValue:match("^%.+$") then unit = nil end

    box._currentDisplayValue = value

    box._dyn_value = value
    box._dyn_displayValue = displayValue
    box._dyn_unit = unit
    box._dyn_percent = percent
    box._dyn_textcolor = resolveThresholdColor(value, box, "textcolor", "textcolor")
    box._dyn_fillcolor = resolveThresholdColor(value, box, "fillcolor", "fillcolor")
end

function render.paint(x, y, w, h, box)
    x, y = utils.applyOffset(x, y, box)
    local c = box._cfg or {}
    local percent = box._dyn_percent or 0
    local textcolor = box._dyn_textcolor
    local fillcolor = box._dyn_fillcolor
    local displayValue = box._dyn_displayValue
    local unit = box._dyn_unit

    if c.bgcolor then
        lcd.color(c.bgcolor)
        lcd.drawFilledRectangle(x, y, w, h)
    end

    local gauge_x = x + (c.gpad_left or 0)
    local gauge_y = y + (c.gpad_top or 0) + (c.title_area_top or 0)
    local gauge_w = w - (c.gpad_left or 0) - (c.gpad_right or 0)
    local gauge_h = h - (c.gpad_top or 0) - (c.gpad_bottom or 0) - (c.title_area_top or 0) - (c.title_area_bottom or 0)

    if c.batteryframe or c.battery then
        drawBatteryBox(gauge_x, gauge_y, gauge_w, gauge_h, percent, c.gaugeorientation, c.batterysegments, c.batteryspacing, c.fillbgcolor, fillcolor, c.batteryframe, c.batteryframethickness, c.accentcolor, c.battery, c.batterysegmentpaddingtop, c.batterysegmentpaddingbottom,
            c.batterysegmentpaddingleft, c.batterysegmentpaddingright)
    else

        lcd.color(c.fillbgcolor)
        drawFilledRoundedRectangle(gauge_x, gauge_y, gauge_w, gauge_h, c.roundradius)

        if not c.battstats and (tonumber(percent) or 0) > 0 then
            lcd.color(fillcolor)
            if c.gaugeorientation == "vertical" then
                local fillH = math.floor(gauge_h * percent)
                local fillY = gauge_y + gauge_h - fillH
                lcd.setClipping(gauge_x, fillY, gauge_w, fillH)
                drawFilledRoundedRectangle(gauge_x, gauge_y, gauge_w, gauge_h, c.roundradius)
                lcd.setClipping()
            else
                local fillW = math.floor(gauge_w * percent)
                if fillW > 0 then
                    lcd.setClipping(gauge_x, gauge_y, fillW, gauge_h)
                    drawFilledRoundedRectangle(gauge_x, gauge_y, gauge_w, gauge_h, c.roundradius)
                    lcd.setClipping()
                end
            end
        end
    end

    if c.subtext and c.subtext ~= "" then
        lcd.font(_G[c.subtextfont] or FONT_XS)
        lcd.color(textcolor)
        local textW, textH = lcd.getTextSize(c.subtext)
        local sy = gauge_y + gauge_h - textH - c.subtextpaddingbottom
        local sx
        if c.subtextalign == "right" then
            sx = gauge_x + gauge_w - textW - c.subtextpaddingright
        elseif c.subtextalign == "center" then
            sx = gauge_x + math.floor((gauge_w - textW) / 2 + 0.5)
        else
            sx = gauge_x + c.subtextpaddingleft
        end
        sy = sy + c.subtextpaddingtop
        lcd.drawText(sx, sy, c.subtext)
    end

    local boxValue = displayValue
    local boxUnit = unit
    if c.hidevalue then
        boxValue = nil
        boxUnit = nil
    end
    utils.box(x, y, w, h, c.title, c.titlepos, c.titlealign, c.titlefont, c.titlespacing, c.titlecolor, c.titlepadding, c.titlepaddingleft, c.titlepaddingright, c.titlepaddingtop, c.titlepaddingbottom, boxValue, boxUnit, c.font, c.valuealign, textcolor, c.valuepadding, c.valuepaddingleft,
        c.valuepaddingright, c.valuepaddingtop, c.valuepaddingbottom, nil)

    if c.battadv and box._batteryLines then
        local line1 = box._batteryLines.line1 or ""
        local line2 = box._batteryLines.line2 or ""

        lcd.font(_G[c.battadvfont] or FONT_S)
        local w1, h1 = lcd.getTextSize(line1)
        local w2, h2 = lcd.getTextSize(line2)
        local blockW = math.max(w1, w2) + c.battadvpaddingleft + c.battadvpaddingright
        local blockH = h1 + h2 + c.battadvpaddingtop + c.battadvpaddingbottom + c.battadvgap

        local startY = y + math.max(0, math.floor((h - blockH) / 2 + 0.5))
        local startX
        if c.battadvblockalign == "left" then
            startX = x
        elseif c.battadvblockalign == "center" then
            startX = x + math.floor((w - blockW) / 2 + 0.5)
        else
            startX = x + w - blockW
        end

        utils.box(startX + c.battadvpaddingleft, startY + c.battadvpaddingtop, blockW - c.battadvpaddingleft - c.battadvpaddingright, h1, nil, nil, c.battadvvaluealign, c.battadvfont, 0, textcolor, 0, 0, 0, 0, 0, line1, nil, c.battadvfont, c.battadvvaluealign, textcolor, 0, 0, 0, 0, 0, nil)

        utils.box(startX + c.battadvpaddingleft, startY + c.battadvpaddingtop + h1 + c.battadvgap, blockW - c.battadvpaddingleft - c.battadvpaddingright, h2, nil, nil, c.battadvvaluealign, c.battadvfont, 0, textcolor, 0, 0, 0, 0, 0, line2, nil, c.battadvfont, c.battadvvaluealign, textcolor, 0, 0, 0,
            0, 0, nil)
    end
end

return render
