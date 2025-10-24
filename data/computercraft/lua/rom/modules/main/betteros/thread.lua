-- New scheduler.
-- Tabs are integral to the design of this scheduler;  Multishell cannot
-- be disabled.

local betteros = require("betteros")
local fs = require("fs")
local keys = require("keys")
local term = require("term")
local colors = require("colors")
local window = require("window")
local expect = require("cc.expect")
local copy = require("betteros.copy").copy

local getfenv
if betteros.lua51 then
  getfenv = betteros.lua51.getfenv
else
  getfenv = function() return _ENV or _G end
end

local tabs = { {} }
local visibleTabs = {}
local threads = {}
local current, wrappedNative

local focused = 1

local function calculateVisibleTabs()
  visibleTabs = {}
  for i = 1, #tabs, 1 do
    local tab = tabs[i]
    if tab.visible then
      table.insert(visibleTabs, tab)
    else
      if tab and tab.term then
        tab.term.setVisible(false)
      end
    end
  end
end

local api = {}

function api.launchTab(x, name)
  expect(1, x, "string", "function")
  name = expect(2, name, "string", "nil") or tostring(x)

  local newTab = {
    term = window.create(wrappedNative, 1, 1, wrappedNative.getSize()),
    id = #tabs + 1,
    visible = true
  }

  tabs[newTab.id] = newTab
  calculateVisibleTabs()

  local id = (type(x) == "string" and api.load or api.spawn)(x, name, newTab)

  return newTab.id, id
end

function api.setFocusedTab(f)
  expect(1, f, "number")
  calculateVisibleTabs()
  if visibleTabs[focused] then focused = f end
  return not not tabs[f]
end

function api.getFocusedTab()
  return focused
end

function api.setTabVisible(id, visible)
  expect(1, id, "number")
  expect(2, visible, "boolean")
  if tabs[id] then
    tabs[id].visible = visible
  end
end

function api.getCurrentTab()
  return current.tab.id
end

function api.load(file, name, _)
  expect(1, file, "string")
  name = expect(2, name, "string", "nil") or file

  local env = copy(current and current.env or _ENV or _G, package.loaded)

  local func, err = loadfile(file, "t", env)
  if not func then
    return nil, err
  end

  return api.spawn(func, name, _ or (current and current.tab or nil))
end

function api.spawn(func, name, _)
  expect(1, func, "function")
  expect(2, name, "string")

  local new = {
    name = name,
    coro = coroutine.create(function()
      assert(xpcall(func, debug.traceback))
    end),
    vars = setmetatable({}, { __index = current and current.vars }),
    env = getfenv(func) or _ENV or _G,
    tab = _ or current and current.tab or nil,
    id = #threads + 1,
    dir = current and current.dir or "/",
    terminating = false
  }

  new.tab[new.id] = true
  threads[new.id] = new

  new.tab.name = name

  return new.id
end

function api.exists(id)
  expect(1, id, "number")
  return not not threads[id]
end

function api.id()
  return current.id
end

function api.dir()
  return current.dir or "/"
end

function api.setDir(dir)
  expect(1, dir, "string")

  if not fs.exists(dir) then
    return nil, "that directory does not exist"
  elseif not fs.isDir(dir) then
    return nil, "not a directory"
  end

  current.dir = dir

  return true
end

function api.vars()
  return current.vars
end

function api.getTerm()
  return current and current.tab and current.tab.term or term.native()
end

function api.setTerm(new)
  calculateVisibleTabs()
  if visibleTabs[focused] then
    local old = visibleTabs[focused].term
    visibleTabs[focused].term = new
    return old
  end
end

local w, h
local function getName(tab)
  local highest = 0

  for k in pairs(tab) do
    if type(k) == "number" then highest = math.max(highest, k) end
  end

  return threads[highest] and threads[highest].name or "???"
end

function api.info()
  local running = {}
  for i, thread in pairs(threads) do
    running[#running + 1] = { id = i, name = thread.name, tab = thread.tab.id }
  end

  table.sort(running, function(a, b) return a.id < b.id end)

  return running
end

function api.kill(id)
  expect(1, id, "number", "nil")
  threads[id or current.id] = nil
end

function api.terminate(id)
  expect(1, id, "number", "nil")
  threads[id or current.id].terminating = true
end

local scroll = 0
local totalNameLength = 0
local function redraw()
  calculateVisibleTabs()
  w, h = wrappedNative.getSize()

  wrappedNative.setVisible(false)

  local names = {}
  totalNameLength = 0
  for i = 1, #visibleTabs, 1 do
    names[i] = " " .. getName(visibleTabs[i]) .. " "
    totalNameLength = totalNameLength + #names[i]
  end

  if #visibleTabs > 1 then
    local len = -scroll + 1
    wrappedNative.setCursorPos(1, 1)
    wrappedNative.setTextColor(colors.black)
    wrappedNative.setBackgroundColor(colors.gray)
    wrappedNative.clearLine()

    for i = 1, #visibleTabs, 1 do
      local tab = visibleTabs[i]
      local name = names[i]

      wrappedNative.setCursorPos(len, 1)
      len = len + #name

      if i == focused then
        wrappedNative.setTextColor(colors.yellow)
        wrappedNative.setBackgroundColor(colors.black)
        wrappedNative.write(name)
      else
        wrappedNative.setTextColor(colors.black)
        wrappedNative.setBackgroundColor(colors.gray)
        wrappedNative.write(name)
      end
      tab.term.setVisible(false)
      tab.term.reposition(1, 2, w, h - 1)
    end

    if totalNameLength > w - 2 then
      wrappedNative.setTextColor(colors.black)
      wrappedNative.setBackgroundColor(colors.gray)
      if scroll > 0 then
        wrappedNative.setCursorPos(1, 1)
        wrappedNative.write("<")
      end
      if totalNameLength - scroll > w - 1 then
        wrappedNative.setCursorPos(w, 1)
        wrappedNative.write(">")
      end
    end

    visibleTabs[focused].term.setVisible(true)
  elseif #visibleTabs > 0 then
    local tab = visibleTabs[1]
    tab.term.reposition(1, 1, w, h)
    tab.term.setVisible(true)
  end

  wrappedNative.setVisible(true)
end

local inputEvents = {
  key = true,
  char = true,
  key_up = true,
  mouse_up = true,
  mouse_drag = true,
  mouse_click = true,
  mouse_scroll = true,
  terminate = true,
}

local altIsDown

local function processEvent(event)
  calculateVisibleTabs()
  if inputEvents[event[1]] then
    if #event > 3 then -- mouse event
      if #visibleTabs > 1 then
        if event[4] == 1 then
          local curX = -scroll

          if event[1] == "mouse_scroll" then
            scroll = math.max(0, math.min(totalNameLength - w + 1,
              scroll - event[2]))
            return false
          end

          for i = 1, #visibleTabs, 1 do
            local tab = visibleTabs[i]
            curX = curX + #getName(tab) + 2

            if event[3] <= curX then
              focused = i
              redraw()
              break
            end
          end

          return false
        else
          event[4] = event[4] - 1
        end
      end
    elseif event[1] == "key" then
      if event[2] == keys.rightAlt then
        altIsDown = event[2]
        return false
      elseif altIsDown then
        local num = tonumber(keys.getName(event[2]))
        if num then
          if visibleTabs[num] then
            focused = num
            redraw()
            return false
          end
        elseif event[2] == keys.left then
          focused = math.max(1, focused - 1)
          redraw()
          return false
        elseif event[2] == keys.right then
          focused = math.min(#visibleTabs, focused + 1)
          redraw()
          return false
        elseif event[2] == keys.up then
          scroll = math.max(0, math.min(totalNameLength - w + 1,
            scroll + 1))
          return false
        elseif event[2] == keys.down then
          scroll = math.max(0, math.min(totalNameLength - w + 1,
            scroll - 1))
          return false
        end
      end
    elseif event[1] == "key_up" then
      if event[2] == keys.rightAlt then
        altIsDown = false
        return false
      end
    end
  end

  return true
end

local function cleanTabs()
  for t = #tabs, 1, -1 do
    local tab = tabs[t]

    local count, removed = 0, 0
    for i in pairs(tab) do
      if type(i) == "number" then
        count = count + 1
        if not threads[i] then
          removed = removed + 1
          tab[i] = nil
        end
      end
    end

    if count == removed then
      table.remove(tabs, t)
    end
  end

  for i = 1, #tabs, 1 do
    tabs[i].id = i
  end

  calculateVisibleTabs()
  focused = math.max(1, math.min(#visibleTabs, focused))
end

function api.start()
  api.start = nil

  local _native = term.native()
  wrappedNative = window.create(_native, 1, 1, _native.getSize())
  api.launchTab("/betteros/programs/shell.lua", "shell")

  betteros.pushEvent("init")

  while #tabs > 0 and next(threads) do
    cleanTabs()
    redraw()
    local event = table.pack(coroutine.yield())

    if event[1] == "term_resize" then
      wrappedNative.reposition(1, 1, _native.getSize())
    end

    if processEvent(event) then
      for tid, thread in pairs(threads) do
        if thread.tab == tabs[focused] or not inputEvents[event[1]] then
          current = thread
          local result
          if thread.terminating then
            thread.terminating = false
            result = table.pack(coroutine.resume(thread.coro, "terminate"))
          else
            result = table.pack(coroutine.resume(thread.coro,
              table.unpack(event, 1, event.n)))
          end

          if not result[1] then
            io.stderr:write(result[2] .. "\n")
            threads[tid] = nil
          elseif coroutine.status(thread.coro) == "dead" then
            threads[tid] = nil
          end
        end
      end
    end
  end

  betteros.shutdown()
end

return api
