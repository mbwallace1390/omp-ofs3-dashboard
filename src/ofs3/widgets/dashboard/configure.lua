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

local function publishArmSettings(widget)
    ofs3.session = ofs3.session or {}
    ofs3.session.aegisArmSource = widget.aegisArmSource
    ofs3.session.aegisArmReversed = widget.aegisArmReversed == true or tonumber(widget.aegisArmReversed) == 1
end

local function loadAegisSettings(widget, prefs)
    local section = prefs and prefs["system/aegis"] or {}

    widget.aegisArmReversed = tonumber(section.armReversed) == 1

    -- Ethos can persist Source objects directly through widget storage. This
    -- lets Aegis follow a physical switch, logical switch, function source, or
    -- channel selected by the user instead of guessing an output channel.
    if storage and storage.read then
        widget.aegisArmSource = storage.read("aegisArmSource")
    end

    publishArmSettings(widget)
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
    prefs["system/aegis"].armReversed = widget.aegisArmReversed and 1 or 0

    ofs3.ini.save_ini_file(prefFile, prefs)
    ofs3.session.modelPreferences = prefs

    if storage and storage.write then
        storage.write("aegisArmSource", widget.aegisArmSource)
    end

    publishArmSettings(widget)
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

    local armSourceLine = addLine(nil, "Aegis arm switch / source")
    form.addSourceField(armSourceLine, nil, function()
        return widget.aegisArmSource
    end, function(value)
        widget.aegisArmSource = value
        publishArmSettings(widget)
    end)

    local armReversedLine = addLine(nil, "Reverse selected arm source")
    form.addBooleanField(armReversedLine, nil, function()
        return widget.aegisArmReversed == true
    end, function(value)
        widget.aegisArmReversed = value == true
        publishArmSettings(widget)
    end)
end

return configui
