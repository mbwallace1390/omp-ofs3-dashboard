--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local configui = {}

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function addLine(parent, label)
    if parent and parent.addLine then
        return parent:addLine(label)
    end
    return form.addLine(label)
end

local function ensureWidgetDefaults(widget)
    ofs3.runtime.readWidgetSettings(widget)
end

local themesModule

local function ensureThemesModule()
    themesModule = themesModule or assert(loadfile("SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/lib/themes.lua"))()
    return themesModule
end

function configui.read(widget)
    ensureWidgetDefaults(widget)
    return true
end

function configui.write(widget)
    return ofs3.runtime.writeWidgetSettings(widget)
end

function configui.configure(widget)
    ensureWidgetDefaults(widget)

    local themes = ensureThemesModule()
    local themeList = themes.list()
    local themeValues = {}
    for index, entry in ipairs(themeList) do
        themeValues[#themeValues + 1] = {entry.name, index}
    end

    local function themeIndexForId(themeId)
        for index, entry in ipairs(themeList) do
            if entry.id == themeId then
                return index
            end
        end
        return 1
    end

    local themeLine = addLine(nil, "@i18n(widgets.dashboard.configure_theme)@")
    form.addChoiceField(themeLine, nil, themeValues, function()
        return themeIndexForId(widget.dashboardTheme or themes.defaultId())
    end, function(index)
        local entry = themeList[index]
        widget.dashboardTheme = entry and entry.id or themes.defaultId()
    end)

    local cellsLine = addLine(nil, "@i18n(widgets.dashboard.configure_cell_count)@")
    local cellsField = form.addNumberField(cellsLine, nil, 1, 14, function()
        return math.floor(tonumber(widget.batteryCellCount) or 3)
    end, function(value)
        widget.batteryCellCount = clamp(math.floor(tonumber(value) or 3), 1, 14)
    end)
    if cellsField and cellsField.suffix then
        cellsField:suffix("S")
    end

    local capacityLine = addLine(nil, "@i18n(widgets.dashboard.configure_capacity)@")
    local capacityField = form.addNumberField(capacityLine, nil, 100, 20000, function()
        return math.floor(tonumber(widget.batteryCapacity) or 750)
    end, function(value)
        widget.batteryCapacity = clamp(math.floor(tonumber(value) or 750), 100, 20000)
    end)
    if capacityField and capacityField.suffix then
        capacityField:suffix("mAh")
    end
end

return configui
