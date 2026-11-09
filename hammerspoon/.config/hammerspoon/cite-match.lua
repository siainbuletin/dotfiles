-- cite-match.lua: send the selected citation to Emacs (sp-cite-match).
--
-- The hotkey copies the selection, saves it in a file in the inbox directory
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

-- Send TEXT to Emacs.  Returns true if emacsclient was started.
function M.send(text)
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
  hs.task.new(client, nil, { "-n", "org-protocol://sp-cite-match?file=" .. name }):start()
  return true
end

-- Copy the selection of the front app and send it.
function M.run()
  local old = hs.pasteboard.getContents()
  local marker = "sp-cite-match-" .. tostring(os.time())
  hs.pasteboard.setContents(marker)
  hs.eventtap.keyStroke({ "cmd" }, "c", 0)
  hs.timer.doAfter(0.2, function()
    local text = hs.pasteboard.getContents()
    if old then hs.pasteboard.setContents(old) else hs.pasteboard.clearContents() end
    if not text or text == marker or text:match("^%s*$") then
      hs.alert.show("cite-match: nothing selected")
      return
    end
    M.send(text)
  end)
end

function M.bind()
  M.hotkey = hs.hotkey.bind(M.mods, M.key, M.run)
  return M
end

return M
