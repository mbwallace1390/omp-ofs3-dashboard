--[[
  Copyright (C) 2025 Rob Thomson
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ofs3 = require("ofs3")

local arg = {...}
local config = arg[1]

local logger = {}

os.mkdir("LOGS:")
os.mkdir("LOGS:/ofs3")
os.mkdir("LOGS:/ofs3/logs")
logger.queue = assert(loadfile("tasks/logger/lib/log.lua"))(config)
logger.queue.config.log_file = "LOGS:/ofs3/logs/ofs3_" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".log"
logger.queue.config.min_print_level = ofs3.preferences.developer.loglevel
logger.queue.config.log_to_file = tostring(ofs3.preferences.developer.logtofile)

function logger.wakeup() logger.queue.process() end

function logger.reset() end

function logger.add(message, level)
    logger.queue.config.min_print_level = ofs3.preferences.developer.loglevel
    logger.queue.config.log_to_file = tostring(ofs3.preferences.developer.logtofile)
    logger.queue.add(message, level)
end

return logger
