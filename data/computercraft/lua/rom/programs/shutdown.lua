local betteros = require("betteros")
local term = require("term")
local colors = require("colors")

term.setTextColor(colors.yellow)
print("Shutting down")

if (...) ~= "now" then betteros.sleep(1) end

betteros.shutdown()
