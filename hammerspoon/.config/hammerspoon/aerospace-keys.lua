-- aerospace-keys.lua: the AeroSpace key bindings, moved out of the Option key.
--
-- Why: Emacs uses Option as Meta (see sp-macos in emacs-modular), so
-- AeroSpace must not grab Option+<key>.
--
-- How:
--   * Caps Lock is remapped to F18 with hidutil (at every Hammerspoon start).
--   * Holding F18 is the "layer" key; keys pressed while it is held run the
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

local layer = hs.hotkey.modal.new()
-- A hotkey only matches the modifiers it is bound with. Bound with none, F18
-- pressed while Shift is already held is not the layer key, so the layer never
-- opens and Shift+letter types a capital. Bind the layer key with and without
-- Shift so that either order of pressing works. Same for Ctrl (join, below).
for _, mods in ipairs({ {}, { "shift" }, { "ctrl" } }) do
  hs.hotkey.bind(mods, layerKey,
    function() layer:enter() end,
    function() layer:exit() end)
end

-- bind(mods, key, ...aerospace arguments)
local function bind(mods, key, ...)
  local fn = run(...)
  layer:bind(mods, key, fn)
end

-- Terminal (was alt-enter)
layer:bind({}, "return", function()
  hs.osascript.applescript('tell application "WezTerm" to activate')
end)

-- Layouts (was alt-slash, alt-comma)
bind({}, "/", "layout", "tiles", "horizontal", "vertical")
bind({}, ",", "layout", "accordion", "horizontal", "vertical")

-- Focus and move (was alt-hjkl, alt-shift-hjkl)
for key, dir in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  bind({}, key, "focus", dir)
  bind({ "shift" }, key, "move", dir)
  -- Stack windows (join-with): the window becomes a container with its
  -- neighbour. Not only in the service mode: while Caps Lock is still held,
  -- Shift+h/j/k/l is "move" here, so the service-mode keys were unreliable.
  bind({ "ctrl" }, key, "join-with", dir)
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
-- It is a toggle: when AeroSpace is already in the service mode, the same keys
-- go back to main. `aerospace list-modes --current` prints the current mode; if
-- that command fails (an old AeroSpace), the key only enters the service mode.
layer:bind({ "shift" }, ";", function()
  hs.task.new(aerospace, function(code, out)
    local current = (code == 0) and out:gsub("%s+", "") or ""
    local target = (current == "service") and "main" or "service"
    hs.task.new(aerospace, nil, { "mode", target }):start()
  end, { "list-modes", "--current" }):start()
end)

-- Always a way out of service mode, even when AeroSpace does not get Esc:
-- Caps Lock + Esc goes back to the main mode.
bind({}, "escape", "mode", "main")

M.layer = layer
return M
