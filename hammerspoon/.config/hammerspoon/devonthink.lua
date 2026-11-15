-- devonthink.lua: DEVONthink PDF highlight keys.
--
-- Keys on the Caps Lock layer (hold Caps Lock, the F18 layer of
-- aerospace-keys.lua, then press):
--   x                 Tools > Annotate > Highlight Text (persistent highlight mode)
--   c                 next colour (cycling), then highlight again
--   Ctrl+1 ... Ctrl+7 pick colour N (list below), then highlight again
--   Ctrl+Shift+1 ...  set colour N only, no highlight mode (to recolour the
--                     highlights selected in the Annotations inspector; the
--                     result depends on DEVONthink, see the PR)
--
-- Key active only while DEVONthink is in front:
--   Cmd+Z          delete the latest highlight, if it is the next undo step;
--                  otherwise the normal Cmd+Z goes to DEVONthink
--
-- Why:
--   * The layer never reaches Emacs or any other app, and uses no Option,
--     Cmd+Space or Ctrl+Space chord.
--   * The keys do nothing outside DEVONthink.
--   * No automatic highlight on activation: it only runs when you press the key.
--   * Caps+1..9 are AeroSpace workspaces (aerospace-keys.lua), so the colour
--     numbers use Caps+Ctrl+number. Caps+Ctrl+h/j/k/l is join-with, no clash.
--
-- Colours:
--   * The colour menu items are renamed, e.g. "Red - Important point".
--   * So they are found by the start of the name (the patterns below),
--     searched in the Format menu, not by a fixed full title.
--
-- Undo:
--   * The menu item is found by title pattern, because its title changes with
--     the action ("Undo Add Highlight").
--   * Only enabled items count. The Edit menu always shows the next undo step,
--     so a highlight that is gone or older than another action is never touched.
--   * Check titles from the Hammerspoon console: DEVONthink.dumpMenu("Edit").

local M = {}

local APP = "DEVONthink"
-- DEVONthink 3 and DEVONthink 4
local BUNDLE_IDS = {
  ["com.devon-technologies.think3"] = true,
  ["com.devon-technologies.think"] = true,
}

-- Lua patterns for the start of each colour item title. The position is the
-- number key (1 = Red, ...) and the cycling order.
local colors = {
  { name = "Red",    pattern = "^Red" },
  { name = "Green",  pattern = "^Green" },
  { name = "Blue",   pattern = "^Blue" },
  { name = "Yellow", pattern = "^Yellow" },
  { name = "Orange", pattern = "^Orange" },
  { name = "Purple", pattern = "^Purple" },
  { name = "Grey",   pattern = "^Gr[ae]y" },
}
local colorIndex = 0

-- Edit > Undo titles that mean "the last step was a highlight".
local undoHighlightPatterns = {
  "^Undo.*[Hh]ighlight",
  "^Undo.*[Aa]nnotat",
  "^Undo.*[Mm]arkup",
}

local function isDevonthink(app)
  if not app then return false end
  return BUNDLE_IDS[app:bundleID() or ""] or app:name() == APP
end

local function frontIsDevonthink()
  return isDevonthink(hs.application.frontmostApplication())
end

local function selectMenu(path)
  local app = hs.application.frontmostApplication()
  if not app or not app:selectMenuItem(path) then
    hs.alert.show("Menu item not found: " .. table.concat(path, " > "))
    return false
  end
  return true
end

-- Depth-first search of ITEMS (from getMenuItems) for an item whose title
-- matches PATTERN. Returns the list of titles from the first one in PREFIX.
-- With ONLY_ENABLED, disabled items are skipped.
local function findItem(items, pattern, prefix, onlyEnabled)
  for _, item in ipairs(items or {}) do
    local title = item.AXTitle
    if title and title ~= "" then
      local path = { table.unpack(prefix) }
      path[#path + 1] = title
      if title:match(pattern) and not (onlyEnabled and item.AXEnabled == false) then
        return path
      end
      local found = findItem(item.AXChildren and item.AXChildren[1], pattern, path, onlyEnabled)
      if found then return found end
    end
  end
  return nil
end

-- Menu path of the item matching PATTERN in the top-level menu MENU.
local function findInMenu(app, menu, pattern, onlyEnabled)
  for _, top in ipairs(app:getMenuItems() or {}) do
    if top.AXTitle == menu then
      return findItem(top.AXChildren and top.AXChildren[1], pattern, { menu }, onlyEnabled)
    end
  end
  return nil
end

-- First enabled item in MENU matching one of PATTERNS; selects it.
local function selectFirst(app, menu, patterns)
  for _, pattern in ipairs(patterns) do
    local path = findInMenu(app, menu, pattern, true)
    if path then return app:selectMenuItem(path) end
  end
  return false
end

-- Print the titles of a top-level menu (check mark, enabled) to the Hammerspoon console.
function M.dumpMenu(menu)
  local app = hs.application.get(APP) or hs.application.frontmostApplication()
  local function dump(items, depth)
    for _, item in ipairs(items or {}) do
      if item.AXTitle and item.AXTitle ~= "" then
        local mark = item.AXMenuItemMarkChar
        hs.printf("%s%s%s%s", string.rep("  ", depth), item.AXTitle,
          (mark and mark ~= "") and " (checked)" or "",
          item.AXEnabled == false and " (disabled)" or "")
        dump(item.AXChildren and item.AXChildren[1], depth + 1)
      end
    end
  end
  for _, top in ipairs(app:getMenuItems() or {}) do
    if top.AXTitle == menu then dump(top.AXChildren and top.AXChildren[1], 0) end
  end
end

function M.highlight()
  return selectMenu({ "Tools", "Annotate", "Highlight Text" })
end

-- Set colour number INDEX (see `colors`). With START_HIGHLIGHT, then start
-- highlighting; without it, only the colour changes (for selected highlights).
function M.setColor(index, startHighlight)
  local app = hs.application.frontmostApplication()
  local color = colors[index]
  if not app or not color then return false end
  local path = findInMenu(app, "Format", color.pattern)
  if not path then
    hs.alert.show("No colour starting with " .. color.name .. " in the Format menu")
    return false
  end
  if not selectMenu(path) then return false end
  colorIndex = index
  hs.alert.show(color.name, 0.5)
  if startHighlight then M.highlight() end
  return true
end

function M.nextColor()
  M.setColor(colorIndex % #colors + 1, true)
end

-- Undo the latest highlight. False when the next undo step is not a highlight.
function M.undoHighlight()
  local app = hs.application.frontmostApplication()
  return app ~= nil and selectFirst(app, "Edit", undoHighlightPatterns)
end

-- Run FN only when DEVONthink is in front; elsewhere the key does nothing.
local function inDevonthink(fn)
  return function()
    if frontIsDevonthink() then fn() end
  end
end

local layer = require("aerospace-keys").layer
layer:bind({}, "x", inDevonthink(M.highlight))
layer:bind({}, "c", inDevonthink(M.nextColor))

-- Caps+Ctrl+N picks colour N and highlights; Caps+Ctrl+Shift+N only sets it.
for index = 1, #colors do
  local key = tostring(index)
  layer:bind({ "ctrl" }, key, inDevonthink(function() M.setColor(index, true) end))
  layer:bind({ "ctrl", "shift" }, key, inDevonthink(function() M.setColor(index, false) end))
end

--------------------------------------------------
-- Cmd+Z, only while DEVONthink is in front
--------------------------------------------------

-- Run ACTION; when it returns false, send the same key to DEVONthink as usual.
-- The hotkey is off while the key is sent, so it does not catch its own event.
local function withPassThrough(mods, key, action)
  local hotkey
  hotkey = hs.hotkey.new(mods, key, function()
    if action() then return end
    hotkey:disable()
    hs.eventtap.keyStroke(mods, key, 0)
    hs.timer.doAfter(0.1, function()
      if frontIsDevonthink() then hotkey:enable() end
    end)
  end)
  return hotkey
end

local scoped = {
  withPassThrough({ "cmd" }, "z", M.undoHighlight),
}

local function setScoped(on)
  for _, hotkey in ipairs(scoped) do
    if on then hotkey:enable() else hotkey:disable() end
  end
end

M.watcher = hs.application.watcher.new(function(_, event, app)
  if not isDevonthink(app) then return end
  if event == hs.application.watcher.activated then
    setScoped(true)
  elseif event == hs.application.watcher.deactivated then
    setScoped(false)
  end
end)
M.watcher:start()

-- Hammerspoon may be reloaded while DEVONthink is already in front.
setScoped(frontIsDevonthink())

return M
