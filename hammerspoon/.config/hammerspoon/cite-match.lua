-- cite-match.lua: send the selected citation to Emacs (sp-cite-match).
--
-- Two hotkeys use it: Ctrl+Shift+K (match, write Cited works) and, in DEVONthink,
-- Caps+r (devonthink.lua, M.open: open the cited record).
--
-- A hotkey copies the selection, saves it in a file in the inbox directory
-- and calls emacsclient with org-protocol://sp-cite-match?file=NAME.  All the
-- matching is done in Emacs Lisp (libraries/modules/academic/sp-cite-match.el).
-- The text goes through a file, not the URL, so there is no quoting problem and
-- no length limit.  The clipboard is put back afterwards.

local M = {}

-- Change these here, not in init.lua.
M.mods = { "ctrl", "shift" }
M.key = "k"
M.inbox = os.getenv("HOME") .. "/.cache/sp-cite-match"
M.emacsclients = {
  "/opt/homebrew/bin/emacsclient",
  "/usr/local/bin/emacsclient",
  "/Applications/Emacs.app/Contents/MacOS/bin/emacsclient",
}

local function find_emacsclient()
  for _, path in ipairs(M.emacsclients) do
    if hs.fs.attributes(path) then return path end
  end
  return nil
end

local function write_file(path, text)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(text)
  f:close()
  return true
end

-- Send TEXT to Emacs through org-protocol://PROTOCOL (default sp-cite-match).
-- Returns true if emacsclient was started.
function M.send(text, protocol)
  local client = find_emacsclient()
  if not client then
    hs.alert.show("cite-match: emacsclient not found")
    return false
  end
  hs.execute("/bin/mkdir -p '" .. M.inbox .. "'")
  local name = string.format("cite-%d-%d.txt", os.time(), math.random(100000, 999999))
  if not write_file(M.inbox .. "/" .. name, text) then
    hs.alert.show("cite-match: cannot write " .. M.inbox)
    return false
  end
  hs.task.new(client, nil, { "-n", "org-protocol://" .. (protocol or "sp-cite-match") .. "?file=" .. name }):start()
  return true
end

-- Copy the selection of the front app and call ACTION with its text (nil when
-- nothing was selected).  The clipboard is put back first.
local function withSelection(action)
  local old = hs.pasteboard.getContents()
  local marker = "sp-cite-match-" .. tostring(os.time())
  hs.pasteboard.setContents(marker)
  hs.eventtap.keyStroke({ "cmd" }, "c", 0)
  hs.timer.doAfter(0.2, function()
    local text = hs.pasteboard.getContents()
    if old then hs.pasteboard.setContents(old) else hs.pasteboard.clearContents() end
    if not text or text == marker or text:match("^%s*$") then text = nil end
    action(text)
  end)
end

-- Send the selection to sp-cite-match (match, write the Cited works section).
function M.run()
  withSelection(function(text)
    if text then M.send(text) else hs.alert.show("cite-match: nothing selected") end
  end)
end

-- Open the DEVONthink record of the selected citation (sp-cite-open).
-- With no copied text, Emacs reads the selection from DEVONthink itself.
function M.open()
  withSelection(function(text)
    if text then
      M.send(text, "sp-cite-open")
    else
      local client = find_emacsclient()
      if not client then
        hs.alert.show("cite-open: emacsclient not found")
        return
      end
      hs.task.new(client, nil, { "-n", "org-protocol://sp-cite-open?file=none" }):start()
    end
  end)
end

function M.bind()
  M.hotkey = hs.hotkey.bind(M.mods, M.key, M.run)
  return M
end

return M
