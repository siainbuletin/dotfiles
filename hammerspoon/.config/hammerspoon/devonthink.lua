-- devonthink.lua: DEVONthink PDF highlight keys.
--
-- Keys on the Caps Lock layer (hold Caps Lock, the F18 layer of
-- aerospace-keys.lua, then press):
--   x   Tools > Annotate > Highlight Text (persistent highlight mode)
--   c   next colour (menu order below), then highlight again
--
-- Keys active only while DEVONthink is in front:
--   Cmd+Z          delete the latest highlight, if it is the next undo step;
--                  otherwise the normal Cmd+Z goes to DEVONthink
--   Cmd+Shift+D    hide the inspector, else the sidebar; if neither is
--                  shown, an alert says so and the normal Cmd+Shift+D goes
--                  to DEVONthink
--
-- Why:
--   * The layer never reaches Emacs or any other app, and uses no Option,
--     Cmd+Space or Ctrl+Space chord.
--   * The keys do nothing outside DEVONthink.
--   * No automatic highlight on activation: it only runs when you press the key.
--
-- Colours:
--   * The colour menu items are renamed, e.g. "Red - Important point".
--   * So they are found by the start of the name (the patterns below),
--     searched in the Format menu, not by a fixed full title.
--
-- Undo, inspector and sidebar:
--   * Menu items are found by title pattern, because the titles change with the
--     action ("Undo Add Highlight") or the state ("Hide Inspector").
--   * Only enabled items count. The Edit menu always shows the next undo step,
--     so a highlight that is gone or older than another action is never touched.
--   * The sidebar has no Hide item: View > Sidebar lists Navigate, Reading List,
--     Extras, ...; the one with a check mark is open, and choosing it again
--     hides the sidebar.
--   * Check titles from the Hammerspoon console: DEVONthink.dumpMenu("View").

local M = {}

local APP = "DEVONthink"
-- DEVONthink 3 and DEVONthink 4
local BUNDLE_IDS = {
  ["com.devon-technologies.think3"] = true,
  ["com.devon-technologies.think"] = true,
}

-- Lua patterns for the start of each colour item title, in cycling order.
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

-- Menus and title patterns of the inspector when it is shown (Tools > Inspectors
-- in DEVONthink 3; View in case DEVONthink 4 moved it).
local hideInspectorMenus = { "Tools", "View" }
local hideInspectorPatterns = {
  "^Hide.*Inspector",
}

-- The sidebar submenu in the View menu, and a fallback title pattern.
local sidebarMenu = { "View", "Sidebar" }
local hideSidebarPatterns = {
  "^Hide.*Sidebar",
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

-- The items (from getMenuItems) of the submenu at PATH, e.g. { "View", "Sidebar" }.
local function submenuItems(app, path)
  local items = app:getMenuItems() or {}
  for _, title in ipairs(path) do
    local found
    for _, item in ipairs(items) do
      if item.AXTitle == title then found = item break end
    end
    if not found then return nil end
    items = found.AXChildren and found.AXChildren[1] or {}
  end
  return items
end

-- Select the checked item of the submenu at PATH (the open sidebar section).
local function selectChecked(app, path)
  for _, item in ipairs(submenuItems(app, path) or {}) do
    local mark = item.AXMenuItemMarkChar
    if mark and mark ~= "" and item.AXEnabled ~= false and item.AXTitle then
      local full = { table.unpack(path) }
      full[#full + 1] = item.AXTitle
      return app:selectMenuItem(full)
    end
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

function M.nextColor()
  local app = hs.application.frontmostApplication()
  if not app then return end
  colorIndex = colorIndex % #colors + 1
  local color = colors[colorIndex]
  local path = findInMenu(app, "Format", color.pattern)
  if not path then
    hs.alert.show("No colour starting with " .. color.name .. " in the Format menu")
    return
  end
  if selectMenu(path) then
    hs.alert.show(color.name, 0.5)
    M.highlight()
  end
end

-- Undo the latest highlight. False when the next undo step is not a highlight.
function M.undoHighlight()
  local app = hs.application.frontmostApplication()
  return app ~= nil and selectFirst(app, "Edit", undoHighlightPatterns)
end

-- Hide the inspector, else the sidebar. False (with an alert) when none is shown.
function M.hidePanel()
  local app = hs.application.frontmostApplication()
  if not app then return false end
  for _, menu in ipairs(hideInspectorMenus) do
    if selectFirst(app, menu, hideInspectorPatterns) then return true end
  end
  if selectChecked(app, sidebarMenu) or selectFirst(app, "View", hideSidebarPatterns) then
    return true
  end
  hs.alert.show("No inspector or sidebar to hide (see DEVONthink.dumpMenu(\"View\"))")
  return false
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

--------------------------------------------------
-- Cmd+Z and Cmd+Shift+D, only while DEVONthink is in front
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
  withPassThrough({ "cmd", "shift" }, "d", M.hidePanel),
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
