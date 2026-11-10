local UI = require "AutoMindful/UI"

local function contextMenu(playerIndex, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer(playerIndex)
    if not player or player:isDead() then return end
    context:addOption("AutoMindful", player, UI.open)
end

local function escape(key)
    if key ~= Keyboard.KEY_ESCAPE then return end
    for _, window in pairs(UI.windows) do
        if window:isVisible() then window:close() end
    end
end

Events.OnFillWorldObjectContextMenu.Add(contextMenu)
Events.OnKeyPressed.Add(escape)
