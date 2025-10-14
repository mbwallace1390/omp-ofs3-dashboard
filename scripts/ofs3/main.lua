
--[[
 * ofs3 - Main (ENV-scoped, no globals), compatibility-focused
]]

-- Local namespace (kept out of _G)
local ofs3 = {}
ofs3.session = {}

package.loaded.ofs3 = ofs3

-- Print warning if accidental globals:
local _ENV = setmetatable({ ofs3 = ofs3 }, {
  __index = _G,
  __newindex = function(_, k) print("attempt to create global '"..tostring(k).."'", 2) end
})

-- ETHOS font compatibility (1.6 vs 1.7)
if not FONT_M then FONT_M = FONT_STD end

-- Config
local config = {
  toolName = "OFS3",
  icon = lcd.loadMask("app/gfx/icon.png"),
  icon_logtool = lcd.loadMask("app/gfx/icon_logtool.png"),
  icon_unsupported = lcd.loadMask("app/gfx/unsupported.png"),
  version = { major = 2, minor = 3, revision = 0, suffix = "DEV" },
  ethosVersion = { 1, 6, 2 },
  supportedMspApiVersion = { "12.07", "12.08", "12.09" },
  baseDir = "ofs3",
  preferences = "ofs3.user",
  defaultRateProfile = 4,
  watchdogParam = 10,
}
ofs3.config = config

-- INI utilities (no need to pass args)
ofs3.ini = assert(loadfile("lib/ini.lua", nil, _ENV))()

-- Defaults
local userpref_defaults = {
  general = { iconsize = 2, syncname = false, gimbalsupression = 0.85 },
  localizations = { temperature_unit = 0, altitude_unit = 0 },
  dashboard = { theme_preflight = "system/default", theme_inflight = "system/default", theme_postflight = "system/default" },
  events = { armed = true, voltage = true, fuel = true, profile = true },
  switches = {},
  developer = {
    compile = true, devtools = false, logtofile = false, loglevel = "off",
    logmsp = false, logmspQueue = false, memstats = false, mspexpbytes = 8, apiversion = 2,
    -- compilerTiming optional; absent by default
  },
  menulastselected = {},
}

-- Preferences path & load
os.mkdir("SCRIPTS:/" .. ofs3.config.preferences)
local userpref_file = "SCRIPTS:/" .. ofs3.config.preferences .. "/preferences.ini"
local master_ini = ofs3.ini.load_ini_file(userpref_file) or {}
local updated_ini = ofs3.ini.merge_ini_tables(master_ini, userpref_defaults)
ofs3.preferences = updated_ini

-- Save only if effective content changed (FIX: compare against updated_ini)
if not ofs3.ini.ini_tables_equal(master_ini, updated_ini) then
  ofs3.ini.save_ini_file(userpref_file, updated_ini)
end

-- Background task names
ofs3.config.bgTaskName = ofs3.config.toolName .. " [Background]"
ofs3.config.bgTaskKey = "ofs3bg"

-- Core libs/apps (pass config as first arg as expected by these modules)
ofs3.utils = assert(loadfile("lib/utils.lua"))(ofs3.config)
ofs3.app   = assert(loadfile("app/app.lua"))(ofs3.config)
ofs3.tasks = assert(loadfile("tasks/tasks.lua"))(ofs3.config)

-- Flight mode & session
ofs3.flightmode = { current = "preflight" }
ofs3.utils.session()

-- Simulator hooks
ofs3.simevent = { telemetry_state = true }

-- API
function ofs3.version()
  local v = ofs3.config.version
  return {
    version = string.format("%d.%d.%d-%s", v.major, v.minor, v.revision, v.suffix),
    major = v.major, minor = v.minor, revision = v.revision, suffix = v.suffix
  }
end

-- Unsupported tool variants
local function unsupported_tool()
  return {
    name = ofs3.config.toolName,
    icon = ofs3.config.icon_unsupported,
    create = function() end,
    wakeup = function() lcd.invalidate() end,
    paint = function()
      local w, h = lcd.getWindowSize()
      lcd.color(lcd.RGB(255, 255, 255, 1))
      lcd.font(FONT_M)
      local msg = string.format("ETHOS < V%d.%d.%d", table.unpack(ofs3.config.ethosVersion))
      local tw, th = lcd.getTextSize(msg)
      lcd.drawText((w - tw) / 2, (h - th) / 2, msg)
    end,
    close = function() end,
  }
end

local function register_main_tool()
  system.registerSystemTool({
    event = ofs3.app.event,
    name = ofs3.config.toolName,
    icon = ofs3.config.icon,
    create = ofs3.app.create,
    wakeup = ofs3.app.wakeup,
    paint = ofs3.app.paint,
    close = ofs3.app.close,
  })
end

local function register_bg_task()
  system.registerTask({
    name = ofs3.config.bgTaskName,
    key = ofs3.config.bgTaskKey,
    wakeup = ofs3.tasks.wakeup,
    event = ofs3.tasks.event,
    init = ofs3.tasks.init,
  })
end

local function load_widget_cache(cachePath)
  local loadf = loadfile(cachePath)
  if not loadf then return nil end
  local ok, cached = pcall(loadf)
  if ok and type(cached) == "table" then
    ofs3.utils.log("[cache] Loaded widget list from cache","info")
    return cached
  end
  return nil
end

local function build_widget_cache(widgetList, cacheFile)
  ofs3.utils.createCacheFile(widgetList, cacheFile, true)
  ofs3.utils.log("[cache] Created new widgets cache file","info")
end

local function register_widgets(widgetList)
  ofs3.widgets = {}
  local dupCount = {}
  for _, v in ipairs(widgetList) do
    if v.script then
      local path = "widgets/" .. v.folder .. "/" .. v.script
      local scriptModule = assert(loadfile(path))(ofs3.config)

      local base = v.varname or v.script:gsub("%.lua$", "")
      if ofs3.widgets[base] then
        dupCount[base] = (dupCount[base] or 0) + 1
        base = string.format("%s_dup%02d", base, dupCount[base])
      end
      ofs3.widgets[base] = scriptModule

      system.registerWidget({
        name = v.name,
        key = v.key,
        event = scriptModule.event,
        create = scriptModule.create,
        paint = scriptModule.paint,
        wakeup = scriptModule.wakeup,
        build = scriptModule.build,
        close = scriptModule.close,
        configure = scriptModule.configure,
        read = scriptModule.read,
        write = scriptModule.write,
        persistent = scriptModule.persistent or false,
        menu = scriptModule.menu,
        title = scriptModule.title
      })
    end
  end
end

local function init()
  if not ofs3.utils.ethosVersionAtLeast() then
    system.registerSystemTool(unsupported_tool())
    return
  end

  register_main_tool()
  register_bg_task()

  local cacheFile = "widgets.lua"
  local cachePath = "cache/" .. cacheFile
  local widgetList = load_widget_cache(cachePath)

  if not widgetList then
    widgetList = ofs3.utils.findWidgets()
    build_widget_cache(widgetList, cacheFile)
  end

  register_widgets(widgetList)
end

return { init = init }
