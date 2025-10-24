-- fg

local args = {...}

if #args == 0 then
  error("command not provided", 0)
end

local shell = require("shell")
local thread = require("betteros.thread")

local path, err = shell.resolveProgram(args[1])
if not path then
  error(err, 0)
end

thread.launchTab(function()
  shell.exec(path, table.unpack(args, 2))
end, args[1])
