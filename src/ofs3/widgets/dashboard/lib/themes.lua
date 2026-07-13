--[[
  Copyright (C) 2026 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local themes = {}

local THEMES_DIR = "SCRIPTS:/" .. ofs3.config.baseDir .. "/widgets/dashboard/themes/"
local DEFAULT_THEME_ID = "@rt-rc"

local cachedList

local function loadThemeMeta(themeId)
    local loader = loadfile(THEMES_DIR .. themeId .. "/init.lua")
    if not loader then
        return nil
    end

    local ok, meta = pcall(loader)
    if not ok or type(meta) ~= "table" then
        return nil
    end

    return meta
end

function themes.basePath(themeId)
    return THEMES_DIR .. themeId .. "/"
end

function themes.list()
    if cachedList then
        return cachedList
    end

    local list = {}
    local names = system.listFiles(THEMES_DIR) or {}

    for _, name in ipairs(names) do
        local themeId = name:gsub("/$", "")
        local meta = loadThemeMeta(themeId)
        if meta then
            list[#list + 1] = {id = themeId, name = meta.name or themeId, standalone = meta.standalone == true, meta = meta}
        end
    end

    table.sort(list, function(a, b)
        return a.name < b.name
    end)

    if #list == 0 then
        list[1] = {
            id = DEFAULT_THEME_ID,
            name = DEFAULT_THEME_ID,
            standalone = false,
            meta = {name = DEFAULT_THEME_ID, preflight = "preflight.lua", inflight = "inflight.lua", postflight = "postflight.lua"}
        }
    end

    cachedList = list
    return list
end

function themes.defaultId()
    return themes.list()[1].id
end

function themes.resolve(themeId)
    local list = themes.list()

    for _, entry in ipairs(list) do
        if entry.id == themeId then
            return entry
        end
    end

    return list[1]
end

return themes
