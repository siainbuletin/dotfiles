-- devonthink.lua: DEVONthink PDF highlight keys on the Caps Lock layer.
--
-- Keys (hold Caps Lock, the F18 layer of aerospace-keys.lua, then press):
--   x   Tools > Annotate > Highlight Text (persistent highlight mode)
--   c   next colour (Yellow, Red, Green, Blue), then highlight again
--
-- Why:
--   * The layer never reaches Emacs or any other app, and uses no Option,
--     Cmd+Space or Ctrl+Space chord.
--   * The keys do nothing outside DEVONthink.
--   * No automatic highlight on activation: it only runs when you press the key.

local M = {}

local APP = "DEVONthink"
-- DEVONthink 3 and DEVONthink 4
local BUNDLE_IDS = {
  ["com.devon-technologies.think3"] = true,
  ["com.devon-technologies.think"] = true,
}

local colors = { "Yellow", "Red", "Green", "Blue" }
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

function M.highlight()
  return selectMenu({ "Tools", "Annotate", "Highlight Text" })
end

function M.nextColor()
  colorIndex = colorIndex % #colors + 1
  local color = colors[colorIndex]
  if selectMenu({ "Format", "Highlight Color", color }) then
    hs.alert.show(color, 0.5)
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
