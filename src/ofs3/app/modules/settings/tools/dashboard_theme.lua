--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")
local settings = {}
local settings_model = {}

local themeList = ofs3.widgets.dashboard.listThemes()
local formattedThemes = {}
local formattedThemesModel = {}

local enableWakeup = false
local prevConnectedState = nil

local function generateThemeList()

    settings = ofs3.preferences.dashboard

    if ofs3.session.modelPreferences then
        settings_model = ofs3.session.modelPreferences.dashboard
    else
        settings_model = {}
    end

    for i, theme in ipairs(themeList) do table.insert(formattedThemes, {theme.name, theme.idx}) end

    table.insert(formattedThemesModel, {"@i18n(app.modules.settings.dashboard_theme_panel_model_disabled)@", 0})
    for i, theme in ipairs(themeList) do table.insert(formattedThemesModel, {theme.name, theme.idx}) end
end

local function openPage(pageIdx, title, script)
    enableWakeup = true
    ofs3.app.triggers.closeProgressLoader = true
    form.clear()

    ofs3.app.lastIdx = pageIdx
    ofs3.app.lastTitle = title
    ofs3.app.lastScript = script

    ofs3.app.ui.fieldHeader("@i18n(app.modules.settings.name)@" .. " / " .. "@i18n(app.modules.settings.dashboard)@" .. " / " .. "@i18n(app.modules.settings.dashboard_theme)@")
    ofs3.session.formLineCnt = 0

    local formFieldCount = 0

    generateThemeList()

    local global_panel = form.addExpansionPanel("@i18n(app.modules.settings.dashboard_theme_panel_global)@")
    global_panel:open(true)

    formFieldCount = formFieldCount + 1
    ofs3.session.formLineCnt = ofs3.session.formLineCnt + 1
    ofs3.app.formLines[ofs3.session.formLineCnt] = global_panel:addLine("@i18n(app.modules.settings.dashboard_theme_preflight)@")

    ofs3.app.formFields[formFieldCount] = form.addChoiceField(ofs3.app.formLines[ofs3.session.formLineCnt], nil, formattedThemes, function()
        if ofs3.preferences and ofs3.preferences.dashboard then
            local folderName = settings.theme_preflight
            for _, theme in ipairs(themeList) do if (theme.source .. "/" .. theme.folder) == folderName then return theme.idx end end
        end
        return nil
    end, function(newValue)
        if ofs3.preferences and ofs3.preferences.dashboard then
            local theme = themeList[newValue]
            if theme then settings.theme_preflight = theme.source .. "/" .. theme.folder end
        end
    end)

    formFieldCount = formFieldCount + 1
    ofs3.session.formLineCnt = ofs3.session.formLineCnt + 1
    ofs3.app.formLines[ofs3.session.formLineCnt] = global_panel:addLine("@i18n(app.modules.settings.dashboard_theme_inflight)@")

    ofs3.app.formFields[formFieldCount] = form.addChoiceField(ofs3.app.formLines[ofs3.session.formLineCnt], nil, formattedThemes, function()
        if ofs3.preferences and ofs3.preferences.dashboard then
            local folderName = settings.theme_inflight
            for _, theme in ipairs(themeList) do if (theme.source .. "/" .. theme.folder) == folderName then return theme.idx end end
        end
        return nil
    end, function(newValue)
        if ofs3.preferences and ofs3.preferences.dashboard then
            local theme = themeList[newValue]
            if theme then settings.theme_inflight = theme.source .. "/" .. theme.folder end
        end
    end)

    formFieldCount = formFieldCount + 1
    ofs3.session.formLineCnt = ofs3.session.formLineCnt + 1
    ofs3.app.formLines[ofs3.session.formLineCnt] = global_panel:addLine("@i18n(app.modules.settings.dashboard_theme_postflight)@")

    ofs3.app.formFields[formFieldCount] = form.addChoiceField(ofs3.app.formLines[ofs3.session.formLineCnt], nil, formattedThemes, function()
        if ofs3.preferences and ofs3.preferences.dashboard then
            local folderName = settings.theme_postflight
            for _, theme in ipairs(themeList) do if (theme.source .. "/" .. theme.folder) == folderName then return theme.idx end end
        end
        return nil
    end, function(newValue)
        if ofs3.preferences and ofs3.preferences.dashboard then
            local theme = themeList[newValue]
            if theme then settings.theme_postflight = theme.source .. "/" .. theme.folder end
        end
    end)

end

local function onNavMenu()
    ofs3.app.ui.progressDisplay()
    ofs3.app.ui.openPage(pageIdx, "@i18n(app.modules.settings.dashboard)@", "settings/tools/dashboard.lua")
    return true
end

local function onSaveMenu()
    local buttons = {
        {
            label = "@i18n(app.btn_ok_long)@",
            action = function()
                local msg = "@i18n(app.modules.profile_select.save_prompt_local)@"
                ofs3.app.ui.progressDisplaySave(msg:gsub("%?$", "."))

                for key, value in pairs(settings) do ofs3.preferences.dashboard[key] = value end
                ofs3.ini.save_ini_file("SCRIPTS:/" .. ofs3.config.preferences .. "/preferences.ini", ofs3.preferences)

                ofs3.widgets.dashboard.reload_themes(true)

                ofs3.app.triggers.closeSave = true
                return true
            end
        }, {label = "@i18n(app.modules.profile_select.cancel)@", action = function() return true end}
    }

    form.openDialog({width = nil, title = "@i18n(app.modules.profile_select.save_settings)@", message = "@i18n(app.modules.profile_select.save_prompt_local)@", buttons = buttons, wakeup = function() end, paint = function() end, options = TEXT_LEFT})
end

local function event(widget, category, value, x, y)

    if category == EVT_CLOSE and value == 0 or value == 35 then
        ofs3.app.ui.openPage(pageIdx, "@i18n(app.modules.settings.dashboard)@", "settings/tools/dashboard.lua")
        return true
    end
end

local function wakeup() if not enableWakeup then return end end

return {event = event, openPage = openPage, wakeup = wakeup, onNavMenu = onNavMenu, onSaveMenu = onSaveMenu, navButtons = {menu = true, save = true, reload = false, tool = false, help = false}, API = {}}
