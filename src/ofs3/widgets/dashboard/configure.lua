--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local configui = {}
local STORAGE_KEY = "dashthm"
local CUT_STORAGE_KEY = "mwrcCutActiveV1"
local HOLD_STORAGE_KEY = "mwrcHoldActiveV1"

local DEFAULT_THEME_CHOICES = {
    {"Aegis Polished", 1},
    {"OFS3 Classic", 2}
}

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

local function dashboardModule()
    return ofs3.widgets and ofs3.widgets.dashboard or nil
end

local function normalizeTheme(value)
    local dashboard = dashboardModule()
    if dashboard and dashboard.setTheme then
        return dashboard.setTheme(value)
    end
    return clamp(math.floor(tonumber(value) or 1), 1, #DEFAULT_THEME_CHOICES)
end

local function publishTheme(widget)
    if not widget then return end
    widget.dashboardTheme = normalizeTheme(widget.dashboardTheme)
end

local function readTheme(widget)
    if not widget then return end

    if widget.dashboardTheme == nil and storage and storage.read then
        local ok, value = pcall(storage.read, STORAGE_KEY)
        if ok then
            widget.dashboardTheme = value
        end
    end

    widget.dashboardTheme = normalizeTheme(widget.dashboardTheme)
end

local function publishSafetySources(widget)
    ofs3.mwrcThrottleCutSource =
        widget and widget.mwrcThrottleCutSource or nil
    ofs3.mwrcThrottleHoldSource =
        widget and widget.mwrcThrottleHoldSource or nil
end

local function readSafetySources(widget)
    if not widget then return end

    if storage and storage.read then
        if widget.mwrcThrottleCutSource == nil then
            local ok, value = pcall(storage.read, CUT_STORAGE_KEY)
            if ok then widget.mwrcThrottleCutSource = value end
        end

        if widget.mwrcThrottleHoldSource == nil then
            local ok, value = pcall(storage.read, HOLD_STORAGE_KEY)
            if ok then widget.mwrcThrottleHoldSource = value end
        end
    end

    publishSafetySources(widget)
end

local function ensureWidgetDefaults(widget)
    ofs3.runtime.readWidgetSettings(widget)
    readTheme(widget)
    readSafetySources(widget)
end

function configui.read(widget)
    ensureWidgetDefaults(widget)
    return true
end

function configui.write(widget)
    ofs3.runtime.writeWidgetSettings(widget)
    publishTheme(widget)

    if storage and storage.write then
        pcall(storage.write, STORAGE_KEY, widget and widget.dashboardTheme or 1)
        pcall(
            storage.write,
            CUT_STORAGE_KEY,
            widget and widget.mwrcThrottleCutSource or nil
        )
        pcall(
            storage.write,
            HOLD_STORAGE_KEY,
            widget and widget.mwrcThrottleHoldSource or nil
        )
    end

    publishSafetySources(widget)
    return true
end

function configui.configure(widget)
    ensureWidgetDefaults(widget)

    local themeLine = addLine(nil, "Dashboard Theme")
    local dashboard = dashboardModule()
    local choices = dashboard and dashboard.getThemeChoices and
        dashboard.getThemeChoices() or DEFAULT_THEME_CHOICES

    -- Display-only rename. Keep the dashboard loader registry and folder
    -- mapping untouched so theme loading remains identical to working v1.
    local displayChoices = {}
    for index = 1, #choices do
        local label = choices[index][1]
        local value = choices[index][2]
        if value == 1 then label = "MWRC" end
        displayChoices[#displayChoices + 1] = {label, value}
    end
    choices = displayChoices

    if form.addChoiceField then
        form.addChoiceField(
            themeLine,
            nil,
            choices,
            function()
                return normalizeTheme(widget.dashboardTheme)
            end,
            function(value)
                widget.dashboardTheme = normalizeTheme(value)
                if lcd.invalidate then
                    lcd.invalidate()
                end
            end
        )
    elseif form.addNumberField then
        form.addNumberField(
            themeLine, nil, 1, #choices,
            function()
                return normalizeTheme(widget.dashboardTheme)
            end,
            function(value)
                widget.dashboardTheme = normalizeTheme(value)
            end
        )
    end

    local cellsLine = addLine(nil, "Cell Count")
    local cellsField = form.addNumberField(
        cellsLine, nil, 1, 14,
        function()
            return math.floor(tonumber(widget.batteryCellCount) or 3)
        end,
        function(value)
            widget.batteryCellCount =
                clamp(math.floor(tonumber(value) or 3), 1, 14)
        end
    )
    if cellsField and cellsField.suffix then
        cellsField:suffix("S")
    end

    local capacityLine = addLine(nil, "Capacity")
    local capacityField = form.addNumberField(
        capacityLine, nil, 100, 20000,
        function()
            return math.floor(tonumber(widget.batteryCapacity) or 750)
        end,
        function(value)
            widget.batteryCapacity =
                clamp(math.floor(tonumber(value) or 750), 100, 20000)
        end
    )
    if capacityField and capacityField.suffix then
        capacityField:suffix("mAh")
    end

    local cutLine = addLine(nil, "Throttle Cut ACTIVE position")
    if form.addSwitchField then
        form.addSwitchField(
            cutLine,
            nil,
            function()
                return widget.mwrcThrottleCutSource
            end,
            function(value)
                widget.mwrcThrottleCutSource = value
                publishSafetySources(widget)
            end
        )
    elseif form.addStaticText then
        form.addStaticText(cutLine, nil, "Select SG up")
    end

    local holdLine = addLine(nil, "Throttle Hold ACTIVE position")
    if form.addSwitchField then
        form.addSwitchField(
            holdLine,
            nil,
            function()
                return widget.mwrcThrottleHoldSource
            end,
            function(value)
                widget.mwrcThrottleHoldSource = value
                publishSafetySources(widget)
            end
        )
    elseif form.addStaticText then
        form.addStaticText(holdLine, nil, "Select SD down")
    end
end

return configui
