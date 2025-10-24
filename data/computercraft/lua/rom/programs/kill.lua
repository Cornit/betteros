local colors = require("colors")
local thread = require("betteros.thread")
local strings = require("cc.strings")
local textutils = require("textutils")

local args = {...}

if #args == 0 then
  error("thread id not provided", 0)
end

if #args > 1 then
  error("too many arguments", 0)
end

thread.kill(tonumber(args[1]))
textutils.coloredPrint(colors.green, "Thread " .. tostring(tonumber(args[1])) .. " killed", colors.white)
