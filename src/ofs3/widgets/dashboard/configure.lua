--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local configui = {}

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function addLine(parent, label)
    if parent and parent.addLine then
        return parent:addLine(label)
    end
    return form.addLine(label)
end

local function loadAegisSettings(widget, prefs)
    local section = prefs and prefs["system/aegis"] or {}
    widget.aegisArmChannel = clamp(math.floor(tonumber(section.armChannel) or 0), 0, 24)
    widget.aegisArmReversed = clamp(math.floor(tonumber(section.armReversed) or 0), 0, 1)
end

local function ensureWidgetDefaults(widget)
    local _, prefs = ofs3.runtime.readWidgetSettings(widget)
    loadAegisSettings(widget, prefs)
end

function configui.read(widget)
    ensureWidgetDefaults(widget)
    return true
end

function configui.write(widget)
    ofs3.runtime.writeWidgetSettings(widget)

    local _, prefs, prefFile = ofs3.runtime.readWidgetSettings(widget)
    prefs = prefs or {}
    prefs["system/aegis"] = prefs["system/aegis"] or {}
    prefs["system/aegis"].armChannel = clamp(math.floor(tonumber(widget.aegisArmChannel) or 0), 0, 24)
    prefs["system/aegis"].armReversed = clamp(math.floor(tonumber(widget.aegisArmReversed) or 0), 0, 1)

    ofs3.ini.save_ini_file(prefFile, prefs)
    ofs3.session.modelPreferences = prefs
    return true
end

function configui.configure(widget)
    ensureWidgetDefaults(widget)

    local cellsLine = addLine(nil, "@i18n(widgets.dashboard.configure_cell_count)@")
    local cellsField = form.addNumberField(cellsLine, nil, 1, 14, function()
        return math.floor(tonumber(widget.batteryCellCount) or 3)
    end, function(value)
        widget.batteryCellCount = clamp(math.floor(tonumber(value) or 3), 1, 14)
    end)
    if cellsField and cellsField.suffix then cellsField:suffix("S") end

    local capacityLine = addLine(nil, "@i18n(widgets.dashboard.configure_capacity)@")
    local capacityField = form.addNumberField(capacityLine, nil, 100, 20000, function()
        return math.floor(tonumber(widget.batteryCapacity) or 750)
    end, function(value)
        widget.batteryCapacity = clamp(math.floor(tonumber(value) or 750), 100, 20000)
    end)
    if capacityField and capacityField.suffix then capacityField:suffix("mAh") end

    local armChannelLine = addLine(nil, "Aegis arm output channel (0 = protocol default)")
    local armChannelField = form.addNumberField(armChannelLine, nil, 0, 24, function()
        return math.floor(tonumber(widget.aegisArmChannel) or 0)
    end, function(value)
        widget.aegisArmChannel = clamp(math.floor(tonumber(value) or 0), 0, 24)
    end)
    if armChannelField and armChannelField.suffix then armChannelField:suffix("CH") end

    local armReversedLine = addLine(nil, "Aegis arm reversed (0 = no, 1 = yes)")
    form.addNumberField(armReversedLine, nil, 0, 1, function()
        return math.floor(tonumber(widget.aegisArmReversed) or 0)
    end, function(value)
        widget.aegisArmReversed = clamp(math.floor(tonumber(value) or 0), 0, 1)
    end)
end

return configui
