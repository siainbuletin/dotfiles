
-- devonthink.lua
-- DEVONthink 4.4.2 PDF annotation shortcuts
--
-- Leader: Cmd + Option + Space
--
-- H       Activate persistent Highlight mode
-- 1       Yellow
-- 2       Red
-- 3       Green
-- 4       Blue
-- Esc     Exit leader mode

local M = {}

local APP = "DEVONthink"

--------------------------------------------------
-- Menu helpers
--------------------------------------------------

local function getApp()
    return hs.application.get(APP)
end

local function selectMenu(path)
    local app = getApp()

    if not app then
        hs.alert.show("DEVONthink is not running")
        return false
    end

    local success = app:selectMenuItem(path)

    if not success then
        hs.alert.show(
            "Menu item not found: " ..
            table.concat(path, " > ")
        )
        return false
    end

    return true
end

--------------------------------------------------
-- Annotation commands
--------------------------------------------------

function M.highlight()
    return selectMenu({
        "Tools",
        "Annotate",
        "Highlight Text"
    })
end

function M.setColor(color)
    if selectMenu({
        "Format",
        "Highlight Color",
        color
    }) then
        M.highlight()
    end
end

--------------------------------------------------
-- Keyboard shortcuts
--------------------------------------------------

local leader = hs.hotkey.modal.new(
    {"cmd", "ctrl", "alt"},
    "h"
)

leader:bind({}, "h", function()
    M.highlight()
    leader:exit()
end)

local colors = {
    ["1"] = "Yellow",
    ["2"] = "Red",
    ["3"] = "Green",
    ["4"] = "Blue",
}

for key, color in pairs(colors) do
    leader:bind({}, key, function()
        M.setColor(color)
        leader:exit()
    end)
end

leader:bind({}, "escape", function()
    leader:exit()
end)

--------------------------------------------------
-- Automatically activate Highlight mode
-- when DEVONthink becomes the foreground app.
--------------------------------------------------

local watcher = hs.application.watcher.new(
    function(appName, event, app)
        if event == hs.application.watcher.activated
            and appName == APP then

            hs.timer.doAfter(0.4, function()
                if hs.application.frontmostApplication() == app then
                    M.highlight()
                end
            end)
        end
    end
)

watcher:start()

--------------------------------------------------
-- Public interface
--------------------------------------------------

M.leader = leader
M.watcher = watcher

return M
