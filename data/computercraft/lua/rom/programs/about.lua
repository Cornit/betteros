-- about

local betteros = require("betteros")
local colors = require("colors")
local textutils = require("textutils")

textutils.coloredPrint(colors.yellow, betteros.version() .. " on " .. _HOST)
