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
        cfg.ringbatt = getParam(box, "ringbatt")
        cfg.ringbattsubtext = getParam(box, "ringbattsubtext")
        cfg.manualUnit = getParam(box, "unit")
        cfg.novalue = getParam(box, "novalue") or "-"
        cfg.thresholds = getParam(box, "thresholds")

        cfg.fillbgcolor = resolveThemeColor("fillbgcolor", getParam(box, "fillbgcolor"))
        cfg.bgcolor = resolveThemeColor("bgcolor", getParam(box, "bgcolor"))
        cfg.titlecolor = resolveThemeColor("titlecolor", getParam(box, "titlecolor"))

        cfg.title = getParam(box, "title")
        cfg.titlepos = getParam(box, "titlepos") or (cfg.title and "top")
        cfg.titlealign = getParam(box, "titlealign")
        cfg.titlefont = getParam(box, "titlefont")
        cfg.titlespacing = getParam(box, "titlespacing")
        cfg.titlepadding = getParam(box, "titlepadding")
        cfg.titlepaddingleft = getParam(box, "titlepaddingleft")
        cfg.titlepaddingright = getParam(box, "titlepaddingright")
        cfg.titlepaddingtop = getParam(box, "titlepaddingtop")
        cfg.titlepaddingbottom = getParam(box, "titlepaddingbottom")

        cfg.font = getParam(box, "font") or "FONT_STD"
        cfg.decimals = getParam(box, "decimals")
        cfg.valuealign = getParam(box, "valuealign")
        cfg.valuepadding = getParam(box, "valuepadding")
        cfg.valuepaddingleft = getParam(box, "valuepaddingleft")
        cfg.valuepaddingright = getParam(box, "valuepaddingright")
        cfg.valuepaddingtop = getParam(box, "valuepaddingtop")
        cfg.valuepaddingbottom = getParam(box, "valuepaddingbottom")
        cfg.thickness = getParam(box, "thickness")
        cfg.innerringcolor = resolveThemeColor("innerringcolor", getParam(box, "innerringcolor") or "white")
        cfg.innerringthickness = getParam(box, "innerringthickness") or 8
        cfg.ringbattsubalign = getParam(box, "ringbattsubalign")
        cfg.ringbattsubpadding = getParam(box, "ringbattsubpadding") or 2
        cfg.ringbattsubpaddingleft = getParam(box, "ringbattsubpaddingleft")
        cfg.ringbattsubpaddingright = getParam(box, "ringbattsubpaddingright")
        cfg.ringbattsubpaddingtop = getParam(box, "ringbattsubpaddingtop")
        cfg.ringbattsubpaddingbottom = getParam(box, "ringbattsubpaddingbottom")
        cfg.ringbattsubfont = getParam(box, "ringbattsubfont") or "FONT_XS"
    end)
end

function render.wakeup(box)
    local cfg = ensureCfg(box)
    local telemetry = ofs3.tasks.telemetry

    local source = cfg.source
    local value, _, dynamicUnit
    if telemetry and source then value, _, dynamicUnit = telemetry.getSensor(source) end

    local ringbatt = cfg.ringbatt
    local percent = 0
    local mahUnit = ""

    if ringbatt and telemetry and telemetry.getSensor then
        local fuel = telemetry.getSensor("fuel") or 0
        local consumption = telemetry.getSensor("consumption") or 0
        percent = math.max(0, math.min(1, fuel / 100))
        mahUnit = string.format("%dmah", math.floor(consumption + 0.5))

        local override = cfg.ringbattsubtext
        if override == "" or override == false then
            mahUnit = nil
        elseif override then
            mahUnit = override
        end
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
    box._dyn_unit = unit
    box._dyn_percent = percent
    box._dyn_mahUnit = mahUnit
    box._dyn_fillcolor = resolveThresholdColor(value, box, "fillcolor", "fillcolor", cfg.thresholds)
    box._dyn_textcolor = resolveThresholdColor(value, box, "textcolor", "textcolor", cfg.thresholds)
end

function render.paint(x, y, w, h, box)
    x, y = utils.applyOffset(x, y, box)
    local c = box._cfg or {}
    local percent = box._dyn_percent or 0
    local fillcolor = box._dyn_fillcolor
    local textcolor = box._dyn_textcolor
    local mahUnit = box._dyn_mahUnit
    local displayValue = box._dyn_displayValue
    local unit = box._dyn_unit

    if c.bgcolor then
        lcd.color(c.bgcolor)
        lcd.drawFilledRectangle(x, y, w, h)
    end

    local cx = x + w / 2

    local titleHeight = 0
    if c.title then
        lcd.font(_G[c.titlefont] or FONT_XS)
        local _, th = lcd.getTextSize(c.title)
        titleHeight = (th or 0) + (c.titlespacing or 0) + (c.titlepaddingtop or 0) + (c.titlepaddingbottom or 0)
    end

    local cy
    if c.titlepos == "top" then
        cy = y + titleHeight + (h - titleHeight) * 0.45
    elseif c.titlepos == "bottom" then
        cy = y + (h - titleHeight) * 0.5
    else
        cy = y + h * 0.5
    end

    local ringPadding = 2
    local baseSize = math.min(w, h - (c.title and ringPadding * 2 or 0))
    local ringSize = math.min(0.88 * (c.title and 1 or 1.05), 1.0)
    local radius = baseSize * 0.5 * ringSize
    local thickness = c.thickness or math.max(8, radius * 0.18)

    if c.ringbatt then

        drawArc(cx, cy, radius, thickness, 0, 360, c.fillbgcolor)

        local startAngle = 360 - (percent * 360)
        drawArc(cx, cy, radius, thickness, startAngle, 360, fillcolor)

        drawArc(cx, cy, radius - thickness, c.innerringthickness, 0, 360, c.innerringcolor)
    else

        drawArc(cx, cy, radius, thickness, 0, 360, c.fillbgcolor)
        drawArc(cx, cy, radius, thickness, 0, 360, fillcolor)
    end

    if c.ringbatt and mahUnit then

        lcd.font(_G[c.ringbattsubfont] or FONT_XS)
        local tw, th = lcd.getTextSize(mahUnit)

        local padL = c.ringbattsubpaddingleft or c.ringbattsubpadding or 0
        local padR = c.ringbattsubpaddingright or c.ringbattsubpadding or 0
        local padT = c.ringbattsubpaddingtop or c.ringbattsubpadding or 0
        local padB = c.ringbattsubpaddingbottom or c.ringbattsubpadding or 0

        local textX
        if c.ringbattsubalign == "left" then
            textX = x + padL
        elseif c.ringbattsubalign == "right" then
            textX = x + w - tw - padR
        else
            textX = x + (w - tw) / 2 + (padL - padR)
        end

        lcd.font(_G[c.font] or FONT_STD)
        local _, mainH = lcd.getTextSize("0")
        local centerY = y + h / 2
        local textY = centerY + mainH / 2 + padT - padB

        lcd.font(_G[c.ringbattsubfont] or FONT_XS)
        lcd.color(textcolor)
        lcd.drawText(textX, textY, mahUnit)
    end

    utils.box(x, y, w, h, c.title, c.titlepos, c.titlealign, c.titlefont, c.titlespacing, c.titlecolor, c.titlepadding, c.titlepaddingleft, c.titlepaddingright, c.titlepaddingtop, c.titlepaddingbottom, displayValue, unit, c.font, c.valuealign, textcolor, c.valuepadding, c.valuepaddingleft,
        c.valuepaddingright, c.valuepaddingtop, c.valuepaddingbottom, nil)
end

return render
