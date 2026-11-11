require "ISUI/ISContextMenu"
require "ISUI/ISToolTip"
require "ISMeditation/ZenWellnessContextMenu"
local UI = require "AutoMindful/UI"
local Options = require "AutoMindful/Options"
local Controller = require "AutoMindful/Controller"

AutoMindful = AutoMindful or {}
local Context = AutoMindful.ContextMenu or {}
AutoMindful.ContextMenu = Context

local function tooltip(context, option, title, description)
    local tip = ISToolTip:new()
    tip:initialise()
    tip:setName(title)
    tip.description = description
    tip:setContextMenu(context)
    option.toolTip = tip
end

local function manualAction(action)
    return action.callback(action.target, unpack(action.parameters, 1, 10))
end

local function decorate(menu, option, player, mode)
    local original = {callback=option.onSelect, target=option.target, parameters={}}
    for index = 1, 10 do original.parameters[index] = option["param" .. index] end
    local submenu = option.subOption and menu:getSubMenu(option.subOption) or ISContextMenu:getNew(menu)
    local manual = submenu:addOption(tostring(option.name) .. " (once)", original, manualAction)
    for _, field in ipairs({"notAvailable", "iconTexture", "color", "itemForTexture", "toolTip", "checkMark"}) do
        manual[field] = option[field]
    end
    if manual.toolTip then manual.toolTip:setContextMenu(submenu) end
    local check = submenu:addOptionOnTop("Check supplies", player, UI.checkFor)
    tooltip(submenu, check, "Check supplies", "Open the live inventory and nearby supply report. This does not interrupt training or collect items immediately.")
    local train = submenu:addOptionOnTop(mode == "yoga" and "Train yoga" or "Train meditation", player, UI.startTraining, mode)
    local status = Controller.status(player)
    train.notAvailable = status.active
    local level = status[mode] or 0
    local description = string.format("Level %.1f / 10 <LINE> ", level)
        .. (mode == "yoga" and "Practice Lifestyle's poses and rest between sessions. Normal yoga requirements still apply."
            or "Sit, meditate, and take care breaks before resuming. Eligible literature can relieve boredom.")
        .. " <LINE> " .. (status.active and "Stop the current loop before changing modes."
            or "Uses your saved adjacent-supply setting. The window can stay closed.")
    tooltip(submenu, train, "Automatic " .. mode, description)
    local open = submenu:addOptionOnTop("Open AutoMindful", player, UI.open)
    tooltip(submenu, open, "AutoMindful window", "Open training, both-skill mode, live supplies, and collection settings. Closing the window keeps the training loop running.")
    menu:addSubMenu(option, submenu)
    option.onSelect, option.target, option.notAvailable = nil, nil, false
    for index = 1, 10 do option["param" .. index] = nil end
    option.toolTip = nil
end

function Context.attach(menu, player)
    if not player or player:isDead() then return end
    for _, option in ipairs(menu.options) do
        local mode
        for _, entry in ipairs({{"meditation", ZenWellnessContextMenu.Options.Meditation}, {"yoga", ZenWellnessContextMenu.Options.Yoga}}) do
            if option.onSelect and (option.onSelect == entry[2].onAction or option.param1 == entry[2]) then mode = entry[1]; break end
        end
        if mode then decorate(menu, option, player, mode)
        elseif option.subOption then Context.attach(menu:getSubMenu(option.subOption), player) end
    end
end

function Context.install()
    if ZenWellnessContextMenu.doBuildMenu == Context.wrapper then return end
    local original = ZenWellnessContextMenu.doBuildMenu
    Context.wrapper = function(playerIndex, menu, ...)
        local function finish(...)
            Context.attach(menu, getSpecificPlayer(playerIndex))
            return ...
        end
        return finish(original(playerIndex, menu, ...))
    end
    ZenWellnessContextMenu.doBuildMenu = Context.wrapper
end

function Context.generalMenu(playerIndex, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer(playerIndex)
    if not player or player:isDead() then return end
    local status = Controller.status(player)
    if not Options.generalMenu() and not status.active and (status.pendingReturns or 0) == 0 then return end
    local label = status.active and "AutoMindful (running)" or "AutoMindful"
    local option = context:addOption(label, player, UI.open)
    tooltip(context, option, "AutoMindful", "Open the training window and live supplies. Training continues while the window is closed.")
end

Context.install()
return Context
