--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html

  Ported from the author's standalone "MWRC" theme (built for the
  rfsuite/Rotorflight dashboard framework) to run natively on ofs3.
  Notes on adaptation:
  - ofs3 has no "altitude" or "smartconsumption" sensors and no
    per-tile bordered/rounded panel backgrounds, so the altitude
    tile/icon was dropped, "smartconsumption" was replaced with the
    real "consumption" sensor, and tile backgrounds are flattened to
    a solid panel color.
  - ofs3's gauge/bar object has no stat (max/min) mode, so all the
    original "gauge/bar, stattype=..." tiles are ported as
    "text/stats" tiles instead (same live max/min tracking, no bar
    fill visual).
]] --

local ofs3 = require("ofs3")
local lcd = lcd

local floor = math.floor
local min = math.min
local max = math.max
local tonumber = tonumber
local ipairs = ipairs

local utils = ofs3.widgets.dashboard.utils

local headeropts = utils.getHeaderOptions()

-- Pre-cached Render Colors for Zero-Lag Performance
local rc = {
    bg = lcd.RGB(5, 8, 14),
    panel = lcd.RGB(12, 18, 28),
    cyan = lcd.RGB(0, 240, 255),
    amber = lcd.RGB(255, 170, 0),
    red = lcd.RGB(255, 0, 60),
    green = lcd.RGB(57, 255, 20),
    orange = lcd.RGB(255, 105, 0),
    magenta = lcd.RGB(190, 30, 255),
    white = lcd.RGB(230, 240, 255),
    dim = lcd.RGB(30, 45, 60)
}

local colorMode = {
    bgcolor = rc.bg,
    tbbgcolor = rc.panel,
    titlecolor = rc.cyan,
    textcolor = rc.white,
    fillcolor = rc.green,
    fillwarncolor = rc.amber,
    fillcritcolor = rc.red,
    accentcolor = rc.cyan,
    fillbgcolor = rc.dim
}

local theme_section = "system/@mwrc"
local tx_section = "system/@default"

local THEME_DEFAULTS = {esctemp_warn = 110, esctemp_max = 150}
local TX_DEFAULTS = {tx_min = 7.2, tx_warn = 7.4, tx_max = 8.4}

local function getThemeValue(key)
    if key == "tx_min" or key == "tx_warn" or key == "tx_max" then
        if ofs3.session and ofs3.session.modelPreferences and ofs3.session.modelPreferences[tx_section] then
            local val = tonumber(ofs3.session.modelPreferences[tx_section][key])
            if val ~= nil then return val end
        end
        return TX_DEFAULTS[key]
    end

    if ofs3.session and ofs3.session.modelPreferences and ofs3.session.modelPreferences[theme_section] then
        local val = tonumber(ofs3.session.modelPreferences[theme_section][key])
        if val ~= nil then return val end
    end
    return THEME_DEFAULTS[key]
end

local function voltsPerCell(v)
    local cfg = ofs3.session.batteryConfig
    local cells = (cfg and cfg.batteryCellCount) or 3
    if cells <= 0 then cells = 3 end
    return v / cells
end

local EMPTY_CACHE = {}
local function wakeStatic()
    return EMPTY_CACHE
end

local ICON_NAMES = {"rpm", "fuel", "current", "watts", "consumed", "link", "voltage", "temperature"}
local ICON_BITMAPS = {}
local iconLoadAttempted = false

local function loadMetricBitmaps()
    if iconLoadAttempted then return end
    iconLoadAttempted = true

    local iconBase = "SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/themes/@mwrc/gfx/icons/"
    for i = 1, #ICON_NAMES do
        local name = ICON_NAMES[i]
        ICON_BITMAPS[name] = ofs3.utils.loadImage(iconBase .. name .. ".bmp") or false
    end
end

loadMetricBitmaps()

local DEFAULT_THEME_OPTION_KEY = "ls_full"
local themeOptionKeysByWidth = {[800] = "ls_full", [784] = "ls_std", [640] = "ss_full", [630] = "ss_std", [480] = "ms_full", [472] = "ms_std"}
local supportedThemeWidths = {800, 784, 640, 630, 480, 472}

local function getThemeOptionKey(W)
    W = tonumber(W)
    if W == nil and system.getVersion then
        local version = system.getVersion() or {}
        W = tonumber(version.lcdWidth)
    end
    W = W or 800

    local closestW, closestDistance
    for _, candidate in ipairs(supportedThemeWidths) do
        local distance = math.abs(W - candidate)
        if closestDistance == nil or distance < closestDistance then
            closestW = candidate
            closestDistance = distance
        end
    end

    return themeOptionKeysByWidth[closestW] or DEFAULT_THEME_OPTION_KEY
end

local themeOptions = {
    ls_full = {font = "FONT_XL", titlefont = "FONT_STD", titlepaddingtop = 5, tilefont = "FONT_XXL", tiletitlespacing = 4, tilevaluepaddingtop = 3, tilevaluepaddingbottom = 0, iconsize = 32, iconpadleft = 12},
    ls_std = {font = "FONT_L", titlefont = "FONT_STD", titlepaddingtop = 2, tilefont = "FONT_XL", tiletitlespacing = 4, tilevaluepaddingtop = 3, tilevaluepaddingbottom = 0, iconsize = 26, iconpadleft = 9},
    ms_full = {font = "FONT_L", titlefont = "FONT_STD", titlepaddingtop = 2, tilefont = "FONT_XL", tiletitlespacing = 4, tilevaluepaddingtop = 3, tilevaluepaddingbottom = 0, iconsize = 32, iconpadleft = 12},
    ms_std = {font = "FONT_S", titlefont = "FONT_STD", titlepaddingtop = 0, tilefont = "FONT_L", tiletitlespacing = 3, tilevaluepaddingtop = 2, tilevaluepaddingbottom = 0, iconsize = 26, iconpadleft = 9},
    ss_full = {font = "FONT_L", titlefont = "FONT_STD", titlepaddingtop = 2, tilefont = "FONT_XL", tiletitlespacing = 4, tilevaluepaddingtop = 3, tilevaluepaddingbottom = 0, iconsize = 32, iconpadleft = 12},
    ss_std = {font = "FONT_S", titlefont = "FONT_STD", titlepaddingtop = 0, tilefont = "FONT_L", tiletitlespacing = 3, tilevaluepaddingtop = 2, tilevaluepaddingbottom = 0, iconsize = 26, iconpadleft = 9}
}

local lastScreenW = nil
local boxes_cache = nil
local themeconfig = nil

local layout = {cols = 12, rows = 12, padding = 0}

local topbarShiftY = 4
local header_layout = {height = headeropts.height + topbarShiftY, cols = 7, rows = 1, padding = 0}

local HEADER_TEXT_1 = "ETHOS "
local HEADER_TEXT_2 = "// "
local HEADER_TEXT_3 = "OFS3"
local HEADER_WATERMARK = "MWRC"
local headerTextWidth1 = nil
local headerTextWidth2 = nil
local headerTextWidth3 = nil
local headerWatermarkWidth = nil

local function paintHeaderLogo(x, y)
    lcd.font(FONT_L or 0)

    if headerTextWidth1 == nil then
        headerTextWidth1 = lcd.getTextSize(HEADER_TEXT_1)
        headerTextWidth2 = lcd.getTextSize(HEADER_TEXT_2)
        headerTextWidth3 = lcd.getTextSize(HEADER_TEXT_3)
    end

    lcd.color(colorMode.accentcolor)
    lcd.drawText(x + 5, y + 4, HEADER_TEXT_1)
    lcd.color(rc.amber)
    lcd.drawText(x + 5 + headerTextWidth1, y + 4, HEADER_TEXT_2)
    lcd.color(colorMode.textcolor)
    lcd.drawText(x + 5 + headerTextWidth1 + headerTextWidth2, y + 4, HEADER_TEXT_3)

    local watermarkX = x + 5 + headerTextWidth1 + headerTextWidth2 + headerTextWidth3 + 10
    lcd.color(rc.amber)
    lcd.drawLine(watermarkX - 5, y + 9, watermarkX - 5, y + 25)
    lcd.font(FONT_XS or FONT_XXS or 0)
    if headerWatermarkWidth == nil then headerWatermarkWidth = lcd.getTextSize(HEADER_WATERMARK) end
    lcd.color(colorMode.accentcolor)
    lcd.drawText(watermarkX, y + 8, HEADER_WATERMARK)
end

local function buildHeaderBoxes()
    return {
        {col = 1, row = 1, colspan = 2, type = "text", subtype = "craftname", font = headeropts.font, valuealign = "left", valuepaddingleft = 5, offsety = topbarShiftY, bgcolor = "transparent", titlecolor = colorMode.titlecolor, textcolor = colorMode.textcolor},
        {col = 3, row = 1, colspan = 3, type = "func", subtype = "func", paint = paintHeaderLogo, offsety = topbarShiftY, bgcolor = "transparent"}, {
            col = 6,
            row = 1,
            type = "gauge",
            subtype = "bar",
            source = "txbatt",
            font = headeropts.font,
            battery = true,
            batteryframe = true,
            hidevalue = true,
            valuealign = "left",
            batterysegments = 4,
            batteryspacing = 1,
            batteryframethickness = 2,
            batterysegmentpaddingtop = headeropts.batterysegmentpaddingtop,
            batterysegmentpaddingbottom = headeropts.batterysegmentpaddingbottom,
            batterysegmentpaddingleft = headeropts.batterysegmentpaddingleft,
            batterysegmentpaddingright = headeropts.batterysegmentpaddingright,
            gaugepaddingright = headeropts.gaugepaddingright,
            gaugepaddingleft = headeropts.gaugepaddingleft,
            gaugepaddingbottom = headeropts.gaugepaddingbottom,
            gaugepaddingtop = headeropts.gaugepaddingtop,
            offsety = topbarShiftY,
            fillbgcolor = colorMode.fillbgcolor,
            bgcolor = "transparent",
            accentcolor = colorMode.accentcolor,
            textcolor = colorMode.textcolor,
            min = getThemeValue("tx_min"),
            max = getThemeValue("tx_max"),
            thresholds = {{value = getThemeValue("tx_warn"), fillcolor = rc.amber}, {value = getThemeValue("tx_max"), fillcolor = colorMode.accentcolor}}
        }, {
            col = 7,
            row = 1,
            type = "gauge",
            subtype = "step",
            source = "rssi",
            font = "FONT_XS",
            stepgap = 2,
            stepcount = 5,
            decimals = 0,
            valuealign = "left",
            barpaddingleft = headeropts.barpaddingleft,
            barpaddingright = headeropts.barpaddingright,
            barpaddingbottom = headeropts.barpaddingbottom,
            barpaddingtop = headeropts.barpaddingtop,
            valuepaddingleft = headeropts.valuepaddingleft,
            valuepaddingbottom = headeropts.valuepaddingbottom,
            offsety = topbarShiftY,
            bgcolor = "transparent",
            textcolor = colorMode.textcolor,
            fillcolor = colorMode.accentcolor,
            fillbgcolor = colorMode.fillbgcolor
        }
    }
end

-- =========================================================================
-- NATIVE LUA METRIC ICONS
-- One overlay object, no per-icon wakeups, and no duplicate shadow strokes.
-- =========================================================================
local function drawRotorIcon(x, y, size, color)
    local cx = x + floor(size / 2)
    local cy = y + floor(size / 2)
    local arm = floor(size * 0.40)
    local diagonal = floor(arm * 0.55)
    local hub = max(2, floor(size * 0.09))

    lcd.color(color)
    lcd.drawLine(cx, cy, cx + arm, cy - diagonal)
    lcd.drawLine(cx, cy, cx - arm, cy + diagonal)
    lcd.drawLine(cx, cy, cx + diagonal, cy + arm)
    lcd.drawLine(cx, cy, cx - diagonal, cy - arm)
    lcd.drawFilledRectangle(cx - hub, cy - hub, hub * 2 + 1, hub * 2 + 1)
end

local function drawBatteryIcon(x, y, size, color, withBolt)
    local bx = x + 3
    local by = y + floor(size * 0.24)
    local bw = size - 8
    local bh = floor(size * 0.52)
    local capW = max(2, floor(size * 0.10))
    local capH = max(5, floor(bh * 0.42))

    lcd.color(color)
    lcd.drawRectangle(bx, by, bw, bh, 2)
    lcd.drawFilledRectangle(bx + bw, by + floor((bh - capH) / 2), capW, capH)

    if withBolt then
        local cx = bx + floor(bw / 2)
        local midY = by + floor(bh * 0.53)
        lcd.drawLine(cx + 2, by + 3, cx - 2, midY)
        lcd.drawLine(cx - 2, midY, cx + 2, midY)
        lcd.drawLine(cx + 2, midY, cx - 2, by + bh - 3)
    else
        local gap = max(2, floor(bw * 0.06))
        local segW = floor((bw - 8 - gap * 2) / 3)
        local sx = bx + 4
        local sy = by + 4
        local sh = bh - 8
        lcd.drawFilledRectangle(sx, sy, segW, sh)
        lcd.drawFilledRectangle(sx + segW + gap, sy, segW, sh)
        lcd.drawFilledRectangle(sx + (segW + gap) * 2, sy, segW, sh)
    end
end

local function drawLightningIcon(x, y, size, color)
    local cx = x + floor(size / 2)
    local half = floor(size * 0.18)
    local midY = y + floor(size * 0.54)

    lcd.color(color)
    lcd.drawLine(cx + half, y + 2, cx - half, midY)
    lcd.drawLine(cx - half, midY, cx, midY)
    lcd.drawLine(cx, midY, cx - half, y + size - 2)
    lcd.drawLine(cx + half - 1, y + 2, cx - half - 1, midY)
end

local function drawWaveIcon(x, y, size, color)
    local left = x + 2
    local right = x + size - 2
    local cy = y + floor(size / 2)
    local step = max(3, floor(size / 8))

    lcd.color(color)
    lcd.drawRectangle(x, y, size - 2, size - 2, 1)
    lcd.drawLine(left, cy, left + step, cy)
    lcd.drawLine(left + step, cy, left + step * 2, cy - floor(size * 0.27))
    lcd.drawLine(left + step * 2, cy - floor(size * 0.27), left + step * 3, cy + floor(size * 0.27))
    lcd.drawLine(left + step * 3, cy + floor(size * 0.27), left + step * 4, cy - floor(size * 0.18))
    lcd.drawLine(left + step * 4, cy - floor(size * 0.18), left + step * 5, cy + floor(size * 0.10))
    lcd.drawLine(left + step * 5, cy + floor(size * 0.10), right, cy)
end

local function drawFuelCanIcon(x, y, size, color)
    local bx = x + floor(size * 0.18)
    local by = y + floor(size * 0.22)
    local bw = floor(size * 0.55)
    local bh = floor(size * 0.65)

    lcd.color(color)
    lcd.drawRectangle(bx, by, bw, bh, 2)
    lcd.drawRectangle(bx + floor(bw * 0.25), y + 3, floor(bw * 0.55), floor(size * 0.20), 1)
    lcd.drawLine(bx + bw, by + floor(bh * 0.18), x + size - 3, y + floor(size * 0.28))
    lcd.drawLine(x + size - 3, y + floor(size * 0.28), x + size - 3, y + floor(size * 0.63))
    lcd.drawLine(bx + 4, by + floor(bh * 0.45), bx + bw - 4, by + floor(bh * 0.45))
    lcd.drawLine(bx + 4, by + floor(bh * 0.62), bx + bw - 4, by + floor(bh * 0.62))
end

local function drawSignalIcon(x, y, size, color)
    local barW = max(2, floor(size * 0.10))
    local gap = max(2, floor(size * 0.08))
    local bottom = y + size - 3
    local startX = x + 3

    lcd.color(color)
    for i = 0, 3 do
        local h = floor(size * (0.22 + i * 0.17))
        lcd.drawFilledRectangle(startX + i * (barW + gap), bottom - h, barW, h)
    end

    local ax = x + size - 7
    lcd.drawLine(ax - 5, y + 8, ax, y + 3)
    lcd.drawLine(ax, y + 3, ax + 5, y + 8)
    lcd.drawLine(ax - 3, y + 12, ax, y + 9)
    lcd.drawLine(ax, y + 9, ax + 3, y + 12)
end

local function drawTemperatureIcon(x, y, size, color)
    local cx = x + floor(size * 0.42)
    local top = y + 3
    local bulb = max(4, floor(size * 0.16))
    local bottom = y + size - bulb - 3

    lcd.color(color)
    lcd.drawRectangle(cx - 3, top, 7, bottom - top, 2)
    lcd.drawRectangle(cx - bulb, bottom, bulb * 2, bulb * 2, 2)
    lcd.drawFilledRectangle(cx - 1, top + floor(size * 0.25), 3, bottom - top - floor(size * 0.18))

    local tx = x + floor(size * 0.68)
    lcd.drawLine(tx, y + floor(size * 0.28), x + size - 2, y + floor(size * 0.28))
    lcd.drawLine(tx, y + floor(size * 0.50), x + size - 5, y + floor(size * 0.50))
    lcd.drawLine(tx, y + floor(size * 0.72), x + size - 2, y + floor(size * 0.72))
end

local function paintAllMetricIcons(x, y, w, h, box, cache)
    local size = box.iconsize or 30
    local pad = box.iconpadleft or 10
    local cellW = w / 12
    local cellH = h / 12
    local tileH = cellH * 3
    local offsetY = -7
    local iconOffsetY = 2

    local function iconPosition(col, row)
        local ix = x + (col - 1) * cellW + pad
        local iy = y + (row - 1) * cellH + offsetY + floor((tileH - size) / 2) + iconOffsetY
        return floor(ix), floor(iy)
    end

    local function paintIcon(name, col, row, fallback, color, extra)
        local ix, iy = iconPosition(col, row)
        local bitmap = ICON_BITMAPS[name]
        if bitmap then
            lcd.drawBitmap(ix, iy, bitmap, size, size)
        else
            fallback(ix, iy, size, color, extra)
        end
    end

    paintIcon("rpm", 1, 4, drawRotorIcon, rc.magenta)
    paintIcon("fuel", 5, 4, drawBatteryIcon, rc.green, false)
    paintIcon("current", 5, 7, drawLightningIcon, rc.cyan)
    paintIcon("watts", 5, 10, drawWaveIcon, rc.green)
    paintIcon("consumed", 9, 4, drawFuelCanIcon, rc.amber)
    paintIcon("link", 1, 7, drawSignalIcon, rc.cyan)
    paintIcon("voltage", 9, 10, drawBatteryIcon, rc.cyan, true)
    paintIcon("temperature", 9, 7, drawTemperatureIcon, rc.orange)
end

local function buildBoxes(W)
    local opts = themeOptions[getThemeOptionKey(W)] or themeOptions.ls_full

    return {
        -- Flight Timers
        {
            col = 5, row = 1, colspan = 4, rowspan = 3,
            type = "time", subtype = "flight", title = "Flight Time", titlepos = "top",
            titlealign = "center", valuealign = "center", font = opts.tilefont, titlefont = opts.titlefont,
            titlespacing = opts.tiletitlespacing, titlepaddingtop = opts.titlepaddingtop + 11,
            valuepaddingtop = opts.tilevaluepaddingtop, valuepaddingbottom = opts.tilevaluepaddingbottom,
            bgcolor = "transparent", titlecolor = rc.cyan, textcolor = rc.white
        },
        {
            col = 9, row = 1, colspan = 4, rowspan = 3,
            type = "time", subtype = "total", title = "Total Flight Time", titlepos = "top",
            titlealign = "center", valuealign = "center", font = opts.tilefont, titlefont = opts.titlefont,
            titlespacing = opts.tiletitlespacing, titlepaddingtop = opts.titlepaddingtop + 11,
            valuepaddingtop = opts.tilevaluepaddingtop, valuepaddingbottom = opts.tilevaluepaddingbottom,
            bgcolor = "transparent", titlecolor = rc.cyan, textcolor = rc.white
        },
        {
            col = 1, row = 1, colspan = 4, rowspan = 3,
            type = "time", subtype = "count", title = "Flights", titlepos = "top",
            titlealign = "center", valuealign = "center", font = opts.tilefont, titlefont = opts.titlefont,
            titlespacing = opts.tiletitlespacing, titlepaddingtop = opts.titlepaddingtop + 11,
            valuepaddingtop = opts.tilevaluepaddingtop, valuepaddingbottom = opts.tilevaluepaddingbottom,
            bgcolor = "transparent", titlecolor = rc.cyan, textcolor = rc.white, transform = "floor"
        },

        -- Stat tiles (icon overlay is painted separately, on top of these)
        {
            col = 1, row = 4, colspan = 4, rowspan = 3, offsety = -7,
            type = "text", subtype = "stats", source = "rpm", stattype = "max", title = "Max Rpm", unit = "rpm",
            titlepos = "top", titlealign = "center", valuealign = "center",
            font = opts.font, titlefont = opts.titlefont, titlespacing = opts.tiletitlespacing, titlepaddingtop = opts.titlepaddingtop + 11,
            bgcolor = rc.panel, textcolor = rc.white, titlecolor = rc.magenta, transform = "floor"
        },
        {
            col = 5, row = 4, colspan = 4, rowspan = 3, offsety = -7,
            type = "text", subtype = "stats", source = "smartfuel", stattype = "min", title = "Battery Remaining", unit = "%",
            titlepos = "top", titlealign = "center", valuealign = "center",
            font = opts.font, titlefont = opts.titlefont, titlespacing = opts.tiletitlespacing, titlepaddingtop = opts.titlepaddingtop + 11,
            bgcolor = rc.panel, textcolor = rc.white, titlecolor = rc.green, transform = "floor",
            thresholds = {{value = 25, textcolor = rc.red}, {value = 50, textcolor = rc.amber}, {value = 100, textcolor = rc.green}}
        },
        {
            col = 9, row = 4, colspan = 4, rowspan = 3, offsety = -7,
            type = "text", subtype = "stats", source = "consumption", stattype = "max", title = "Consumed mAh", unit = "mAh",
            titlepos = "top", titlealign = "center", valuealign = "center",
            font = opts.font, titlefont = opts.titlefont, titlespacing = opts.tiletitlespacing, titlepaddingtop = opts.titlepaddingtop + 11,
            bgcolor = rc.panel, textcolor = rc.white, titlecolor = rc.amber, transform = "floor"
        },
        {
            col = 1, row = 7, colspan = 4, rowspan = 3, offsety = -7,
            type = "text", subtype = "stats", source = "rssi", stattype = "min", title = "Link Min",
            titlepos = "top", titlealign = "center", valuealign = "center",
            font = opts.font, titlefont = opts.titlefont, titlespacing = opts.tiletitlespacing, titlepaddingtop = opts.titlepaddingtop + 11,
            bgcolor = rc.panel, textcolor = rc.white, titlecolor = rc.cyan, transform = "floor"
        },
        {
            col = 5, row = 7, colspan = 4, rowspan = 3, offsety = -7,
            type = "text", subtype = "stats", source = "current", stattype = "max", title = "Max Amps", unit = "A",
            titlepos = "top", titlealign = "center", valuealign = "center",
            font = opts.font, titlefont = opts.titlefont, titlespacing = opts.tiletitlespacing, titlepaddingtop = opts.titlepaddingtop + 11,
            bgcolor = rc.panel, textcolor = rc.white, titlecolor = rc.cyan, transform = "floor"
        },
        {
            col = 9, row = 7, colspan = 4, rowspan = 3, offsety = -7,
            type = "text", subtype = "stats", source = "temp_esc", stattype = "max", title = "ESC Max Temp", unit = "°C",
            titlepos = "top", titlealign = "center", valuealign = "center",
            font = opts.font, titlefont = opts.titlefont, titlespacing = opts.tiletitlespacing, titlepaddingtop = opts.titlepaddingtop + 11,
            bgcolor = rc.panel, textcolor = rc.white, titlecolor = rc.orange, transform = "floor",
            thresholds = {{value = getThemeValue("esctemp_warn"), textcolor = rc.white}, {value = getThemeValue("esctemp_max"), textcolor = rc.amber}, {value = 10000, textcolor = rc.red}}
        },
        {
            col = 5, row = 10, colspan = 4, rowspan = 3, offsety = -7,
            type = "text", subtype = "watts", source = "max", title = "Max Watts", unit = "W",
            titlepos = "top", titlealign = "center", valuealign = "center",
            font = opts.font, titlefont = opts.titlefont, titlespacing = opts.tiletitlespacing, titlepaddingtop = opts.titlepaddingtop + 11,
            bgcolor = rc.panel, textcolor = rc.white, titlecolor = rc.green
        },
        {
            col = 9, row = 10, colspan = 4, rowspan = 3, offsety = -7,
            type = "text", subtype = "stats", source = "voltage", stattype = "min", title = "Volts per cell", unit = "V",
            titlepos = "top", titlealign = "center", valuealign = "center",
            font = opts.font, titlefont = opts.titlefont, titlespacing = opts.tiletitlespacing, titlepaddingtop = opts.titlepaddingtop + 11,
            bgcolor = rc.panel, textcolor = rc.white, titlecolor = rc.cyan,
            transform = voltsPerCell, decimals = 2
        },

        -- One static overlay replaces the per-icon widgets.
        {
            col = 1, row = 1, colspan = 12, rowspan = 12,
            type = "func", subtype = "func",
            wakeup = wakeStatic,
            paint = paintAllMetricIcons,
            iconsize = opts.iconsize,
            iconpadleft = opts.iconpadleft,
            bgcolor = "transparent"
        }
    }
end

local function boxes()
    local config = ofs3.session and ofs3.session.modelPreferences and ofs3.session.modelPreferences[theme_section]
    local W = lcd.getWindowSize()
    if boxes_cache == nil or themeconfig ~= config or lastScreenW ~= W then
        boxes_cache = buildBoxes(W)
        themeconfig = config
        lastScreenW = W
    end
    return boxes_cache
end

local header_boxes = buildHeaderBoxes()

return {layout = layout, boxes = boxes, header_boxes = header_boxes, header_layout = header_layout, scheduler = {spread_scheduling = true, spread_scheduling_paint = false, spread_ratio = 0.5}}
