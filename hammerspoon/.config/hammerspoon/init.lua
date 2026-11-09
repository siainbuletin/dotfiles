-- AeroSpace keys first: they must work even when stackline fails to load.
aerospace_keys = require "aerospace-keys"

-- stackline is optional here. Its files in this folder are not in the layout it
-- expects (stackline.lua is empty, lib/ is called stackline-lib/), so a failed
-- load is only logged and never stops the lines above.
local ok, err = pcall(function()
  stackline = require "stackline"
  stackline:init()
end)
if not ok then
  hs.printf("stackline not loaded: %s", tostring(err))
end

-- Send the selected citation to Emacs (sp-cite-match).  Optional, like stackline.
local ok_cite, err_cite = pcall(function()
  cite_match = require "cite-match"
  cite_match.bind()
end)
if not ok_cite then
  hs.printf("cite-match not loaded: %s", tostring(err_cite))
end
