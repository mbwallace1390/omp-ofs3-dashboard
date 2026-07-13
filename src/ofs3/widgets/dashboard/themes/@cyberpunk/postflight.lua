--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local utils = ofs3.widgets.dashboard.utils
local boxes_cache = nil
local themeconfig = nil
local lastScreenW = nil

local colorMode = assert(loadfile("SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/themes/@cyberpunk/palette.lua"))()

local theme_section = "system/@default"

local THEME_DEFAULTS = {tx_min = 7.2, tx_warn = 7.4, tx_max = 8.4}

local function getThemeValue(key)
    if ofs3 and ofs3.session and ofs3.session.modelPreferences and ofs3.session.modelPreferences[theme_section] then
        local val = ofs3.session.modelPreferences[theme_section][key]
        val = tonumber(val)
        if val ~= nil then return val end
    end
    return THEME_DEFAULTS[key]
end

local headeropts = utils.getHeaderOptions()

local layout = {cols = 3, rows = 3, padding = 1}

local header_layout = {height = headeropts.height, cols = 7, rows = 1, padding = 0}

local function buildBoxes(W)

    return {

        {col = 1, row = 1, type = "time", subtype = "flight", title = "@i18n(widgets.dashboard.theme_flight_duration)@", titlepos = "bottom", bgcolor = colorMode.bgcolor, textcolor = colorMode.textcolor, titlecolor = colorMode.titlecolor},
        {col = 1, row = 2, type = "time", subtype = "total", title = "@i18n(widgets.dashboard.theme_total_model_flight_duration)@", titlepos = "bottom", bgcolor = colorMode.bgcolor, textcolor = colorMode.textcolor, titlecolor = colorMode.titlecolor},
        {col = 1, row = 3, type = "text", subtype = "stats", source = "rpm", title = "@i18n(widgets.dashboard.theme_rpm_max)@", unit = " rpm", titlepos = "bottom", bgcolor = colorMode.bgcolor, transform = "floor", textcolor = colorMode.textcolor, titlecolor = colorMode.titlecolor},

        {col = 2, row = 1, type = "text", subtype = "stats", source = "current", title = "@i18n(widgets.dashboard.theme_current_max)@", titlepos = "bottom", bgcolor = colorMode.bgcolor, transform = "floor", textcolor = colorMode.textcolor, titlecolor = colorMode.titlecolor},
        {col = 2, row = 2, type = "text", subtype = "stats", source = "temp_esc", title = "@i18n(widgets.dashboard.theme_esc_temp_max)@", titlepos = "bottom", bgcolor = colorMode.bgcolor, transform = "floor", textcolor = colorMode.textcolor, titlecolor = colorMode.titlecolor},
        {col = 2, row = 3, type = "text", subtype = "watts", source = "max", title = "@i18n(widgets.dashboard.theme_max_watts)@", unit = "W", titlepos = "bottom", bgcolor = colorMode.bgcolor, transform = "floor", textcolor = colorMode.textcolor, titlecolor = colorMode.titlecolor},

        {col = 3, row = 1, type = "text", subtype = "stats", stattype = "max", source = "consumption", title = "@i18n(widgets.dashboard.theme_consumed_mah)@", titlepos = "bottom", bgcolor = colorMode.bgcolor, transform = "floor", textcolor = colorMode.textcolor, titlecolor = colorMode.titlecolor},
        {col = 3, row = 2, type = "text", subtype = "telemetry", source = "smartfuel", title = "@i18n(widgets.dashboard.theme_fuel_remaining)@", titlepos = "bottom", bgcolor = colorMode.bgcolor, transform = "floor", textcolor = colorMode.textcolor, titlecolor = colorMode.titlecolor},
        {col = 3, row = 3, type = "text", subtype = "stats", stattype = "min", source = "rssi", title = "@i18n(widgets.dashboard.theme_link_min)@", titlepos = "bottom", bgcolor = colorMode.bgcolor, transform = "floor", textcolor = colorMode.textcolor, titlecolor = colorMode.titlecolor}

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
        batteryframethickness = 1,
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
