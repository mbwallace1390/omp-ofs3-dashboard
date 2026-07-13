--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local utils = ofs3.widgets.dashboard.utils
local boxes_cache = nil
local themeconfig = nil
local lastScreenW = nil

local colorMode = assert(loadfile("SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/themes/@dial/palette.lua"))()

local theme_section = "system/@default"

local THEME_DEFAULTS = {tx_min = 7.2, tx_warn = 7.4, tx_max = 8.4}
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

    ls_full = {font = "FONT_XXL", valuepaddingtop = 20, gaugepadding = 20},

    ls_std = {font = "FONT_XL", valuepaddingtop = 5, gaugepadding = 10},

    ms_full = {font = "FONT_XXL", valuepaddingtop = 5, gaugepadding = 10},

    ms_std = {font = "FONT_XL", valuepaddingtop = 10, gaugepadding = 5},

    ss_full = {font = "FONT_XL", valuepaddingtop = 5, gaugepadding = 10},

    ss_std = {font = "FONT_XL", valuepaddingtop = 10, gaugepadding = 10}
}

local function getThemeValue(key)
    if ofs3 and ofs3.session and ofs3.session.modelPreferences and ofs3.session.modelPreferences[theme_section] then
        local val = ofs3.session.modelPreferences[theme_section][key]
        val = tonumber(val)
        if val ~= nil then return val end
    end
    return THEME_DEFAULTS[key]
end

local BAND_LABELS = {"Low", "Med", "Full"}

local function bandColors()
    return {colorMode.fillcritcolor, colorMode.fillwarncolor, colorMode.fillcolor}
end

local headeropts = utils.getHeaderOptions()

local layout = {cols = 4, rows = 14, padding = 1}

local header_layout = {height = headeropts.height, cols = 7, rows = 1, padding = 0}

local function buildBoxes(W)

    local opts = themeOptions[getThemeOptionKey(W)] or themeOptions[DEFAULT_THEME_OPTION_KEY]

    return {

        {
            type = "dial",
            subtype = "rainbow",
            col = 1,
            row = 1,
            rowspan = 12,
            colspan = 2,
            source = "voltage",
            font = opts.font,
            title = "@i18n(widgets.dashboard.theme_voltage)@",
            titlepos = "bottom",
            bgcolor = colorMode.bgcolor,
            titlecolor = colorMode.titlecolor,
            textcolor = colorMode.textcolor,
            accentcolor = colorMode.accentcolor,
            bandlabels = BAND_LABELS,
            bandcolors = bandColors(),

            min = function()
                local cfg = ofs3.session.batteryConfig
                local cells = (cfg and cfg.batteryCellCount) or 3
                local minV = (cfg and cfg.vbatmincellvoltage) or 3.0
                return math.max(0, cells * minV)
            end,

            max = function()
                local cfg = ofs3.session.batteryConfig
                local cells = (cfg and cfg.batteryCellCount) or 3
                local maxV = (cfg and cfg.vbatfullcellvoltage) or 4.2
                return math.max(0, cells * maxV)
            end
        }, {
            type = "dial",
            subtype = "rainbow",
            col = 3,
            row = 1,
            rowspan = 12,
            colspan = 2,
            source = "smartfuel",
            transform = "floor",
            min = 0,
            max = 140,
            font = opts.font,
            title = "@i18n(widgets.dashboard.theme_fuel)@",
            titlepos = "bottom",
            bgcolor = colorMode.bgcolor,
            titlecolor = colorMode.titlecolor,
            textcolor = colorMode.textcolor,
            accentcolor = colorMode.accentcolor,
            bandlabels = BAND_LABELS,
            bandcolors = bandColors()
        }, {col = 1, row = 13, rowspan = 2, type = "text", subtype = "telemetry", nosource = "-", source = "profile", transform = "floor", bgcolor = colorMode.bgcolor, titlecolor = colorMode.titlecolor, textcolor = colorMode.textcolor},
        {col = 4, row = 13, rowspan = 2, type = "time", subtype = "flight", bgcolor = colorMode.bgcolor, titlecolor = colorMode.titlecolor, textcolor = colorMode.textcolor},
        {col = 3, row = 13, rowspan = 2, type = "text", subtype = "telemetry", source = "rpm", nosource = "-", unit = "rpm", transform = "floor", bgcolor = colorMode.bgcolor, titlecolor = colorMode.titlecolor, textcolor = colorMode.textcolor},
        {col = 2, row = 13, rowspan = 2, type = "text", subtype = "telemetry", source = "rssi", nosource = "-", unit = "dB", transform = "floor", bgcolor = colorMode.bgcolor, titlecolor = colorMode.titlecolor, textcolor = colorMode.textcolor}

    }
end

local header_boxes = {

    {col = 1, row = 1, colspan = 2, type = "text", subtype = "craftname", font = headeropts.font, valuealign = "left", valuepaddingleft = 5, bgcolor = colorMode.bgcolortop, titlecolor = colorMode.titlecolor, textcolor = colorMode.textcolor},

    {col = 3, row = 1, colspan = 3, type = "image", subtype = "image", bgcolor = colorMode.bgcolortop}, {
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
        fillbgcolor = colorMode.txbgfillcolor,
        bgcolor = colorMode.bgcolortop,
        accentcolor = colorMode.txaccentcolor,
        textcolor = colorMode.textcolor,
        min = getThemeValue("tx_min"),
        max = getThemeValue("tx_max"),
        thresholds = {{value = getThemeValue("tx_warn"), fillcolor = colorMode.fillwarncolor}, {value = getThemeValue("tx_max"), fillcolor = colorMode.txfillcolor}}
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
        bgcolor = colorMode.bgcolortop,
        textcolor = colorMode.textcolor,
        fillcolor = colorMode.rssifillcolor,
        fillbgcolor = colorMode.rssifillbgcolor
    }
}

local function boxes()
    local config = ofs3 and ofs3.session and ofs3.session.modelPreferences and ofs3.session.modelPreferences[theme_section]
    local W = lcd.getWindowSize()
    if boxes_cache == nil or themeconfig ~= config or lastScreenW ~= W then
        boxes_cache = buildBoxes(W)
        themeconfig = config
        lastScreenW = W
    end
    return boxes_cache
end

return {layout = layout, boxes = boxes, header_boxes = header_boxes, header_layout = header_layout, scheduler = {spread_scheduling = true, spread_scheduling_paint = false, spread_ratio = 0.5}}
