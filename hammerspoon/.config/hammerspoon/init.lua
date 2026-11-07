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
