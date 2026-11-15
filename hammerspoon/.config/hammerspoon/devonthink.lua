-- devonthink.lua: DEVONthink PDF highlight keys on the Caps Lock layer.
--
-- Keys (hold Caps Lock, the F18 layer of aerospace-keys.lua, then press):
--   x   Tools > Annotate > Highlight Text (persistent highlight mode)
--   c   next colour (menu order below), then highlight again
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

local function frontIsDevonthink()
  local front = hs.application.frontmostApplication()
  if not front then return false end
  return BUNDLE_IDS[front:bundleID() or ""] or front:name() == APP
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
local function findItem(items, pattern, prefix)
  for _, item in ipairs(items or {}) do
    local title = item.AXTitle
    if title and title ~= "" then
      local path = { table.unpack(prefix) }
      path[#path + 1] = title
      if title:match(pattern) then return path end
      local found = findItem(item.AXChildren and item.AXChildren[1], pattern, path)
      if found then return found end
    end
  end
  return nil
end

-- Menu path of the colour item matching PATTERN in the Format menu.
local function colorPath(app, pattern)
  for _, top in ipairs(app:getMenuItems() or {}) do
    if top.AXTitle == "Format" then
      return findItem(top.AXChildren and top.AXChildren[1], pattern, { "Format" })
    end
  end
  return nil
end

function M.highlight()
  return selectMenu({ "Tools", "Annotate", "Highlight Text" })
end

function M.nextColor()
  local app = hs.application.frontmostApplication()
  if not app then return end
  colorIndex = colorIndex % #colors + 1
  local color = colors[colorIndex]
  local path = colorPath(app, color.pattern)
  if not path then
    hs.alert.show("No colour starting with " .. color.name .. " in the Format menu")
    return
  end
  if selectMenu(path) then
    hs.alert.show(color.name, 0.5)
    M.highlight()
  end
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

return M
