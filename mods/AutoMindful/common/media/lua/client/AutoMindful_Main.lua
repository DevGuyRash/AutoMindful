local UI = require "AutoMindful/UI"
local Options = require "AutoMindful/Options"
local Context = require "AutoMindful/ContextMenu"

local function keyPressed(key)
    if getCore():isDoingTextEntry() or (ISChat and ISChat.focused) then return end
    if key == Keyboard.KEY_ESCAPE then
        for _, window in pairs(UI.windows) do
            if window:getIsVisible() then window:close() end
        end
    elseif key ~= 0 and key == Options.windowKey() then
        local player = getSpecificPlayer(0)
        if player and not player:isDead() then UI.open(player) end
    end
end

local old = AutoMindful.uiEvents
if old then
    Events.OnFillWorldObjectContextMenu.Remove(old.context)
    Events.OnKeyPressed.Remove(old.key)
    Events.OnGameStart.Remove(old.start)
end
AutoMindful.uiEvents = {context=Context.generalMenu, key=keyPressed, start=Context.install}
Events.OnFillWorldObjectContextMenu.Add(Context.generalMenu)
Events.OnKeyPressed.Add(keyPressed)
Events.OnGameStart.Add(Context.install)
