-- aerospace-keys.lua: the AeroSpace key bindings, moved out of the Option key.
--
-- Why: Emacs uses Option as Meta (see sp-macos in emacs-modular), so
-- AeroSpace must not grab Option+<key>.
--
-- How:
--   * Caps Lock is remapped to F18 with hidutil (at every Hammerspoon start).
--   * Holding F18 is the "layer" key (an event tap, so Shift may be pressed
--     before or after it); keys pressed while it is held run the
--     `aerospace` command that the old `alt-<key>` binding ran.
--   * F18 plus a key never reaches Emacs or any other app.
--
-- Set `capsLockAsLayer` to false to use another key: then bind `layerKey`
-- yourself (for example with Karabiner) and Caps Lock keeps working.

local M = {}

local capsLockAsLayer = true
local layerKey = "f18"
local aerospace = "/opt/homebrew/bin/aerospace" -- `which aerospace`; /usr/local/bin on Intel

if capsLockAsLayer then
  -- Caps Lock (0x700000039) -> F18 (0x70000006D). Lost at reboot, so run it here.
  hs.execute([[hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}']])
end

local function run(...)
  local args = { ... }
  return function()
    hs.task.new(aerospace, nil, args):start()
  end
end

-- The layer is an event tap, not `hs.hotkey` + `hs.hotkey.modal`: a hotkey bound
-- with no modifiers does not match when Shift is already down, so Shift then
-- Caps Lock (F18) fell through to the focused app and typed capital letters.
-- The tap tracks F18 whatever modifiers are down, and looks the key up with
-- or without Shift.
local bindings = {}   -- ["h"] or ["shift+h"] -> function
local layerDown = false
local keyDown, keyUp = hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp
local layerCode = hs.keycodes.map[layerKey]

-- bind(mods, key, fn): mods is {} or { "shift" }
local function layerBind(mods, key, fn)
  bindings[(#mods > 0 and "shift+" or "") .. key] = fn
end

-- bind(mods, key, ...aerospace arguments)
local function bind(mods, key, ...)
  layerBind(mods, key, run(...))
end

M.tap = hs.eventtap.new({ keyDown, keyUp }, function(e)
  local code = e:getKeyCode()
  if code == layerCode then
    layerDown = (e:getType() == keyDown)
    return true                       -- never reaches the app, even with Shift
  end
  if not layerDown then return false end
  if e:getType() ~= keyDown then return false end
  local flags = e:getFlags()
  if flags.cmd or flags.alt or flags.ctrl then return false end
  local fn = bindings[(flags.shift and "shift+" or "") .. (hs.keycodes.map[code] or "")]
  if fn then fn(); return true end
  return false
end)
M.tap:start()

-- Terminal (was alt-enter)
layerBind({}, "return", function()
  hs.osascript.applescript('tell application "WezTerm" to activate')
end)

-- Layouts (was alt-slash, alt-comma)
bind({}, "/", "layout", "tiles", "horizontal", "vertical")
bind({}, ",", "layout", "accordion", "horizontal", "vertical")

-- Focus and move (was alt-hjkl, alt-shift-hjkl)
for key, dir in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  bind({}, key, "focus", dir)
  bind({ "shift" }, key, "move", dir)
end

-- Resize (was alt-shift-minus, alt-shift-equal)
bind({ "shift" }, "-", "resize", "smart", "-50")
bind({ "shift" }, "=", "resize", "smart", "+50")

-- Workspaces (was alt-<key> and alt-shift-<key>)
local workspaces = { "1", "2", "3", "4", "5", "6", "7", "8", "9",
                     "a", "b", "d", "e", "m", "t", "w" }
for _, key in ipairs(workspaces) do
  local ws = key:upper()
  bind({}, key, "workspace", ws)
  bind({ "shift" }, key, "move-node-to-workspace", ws)
end
bind({ "shift" }, "o", "move-node-to-workspace", "O")

-- Back and forth, move workspace to the next monitor (was alt-tab, alt-shift-tab)
bind({}, "tab", "workspace-back-and-forth")
bind({ "shift" }, "tab", "move-workspace-to-monitor", "--wrap-around", "next")

-- Service mode (was alt-shift-semicolon); its keys are in aerospace.toml
bind({ "shift" }, ";", "mode", "service")

return M
