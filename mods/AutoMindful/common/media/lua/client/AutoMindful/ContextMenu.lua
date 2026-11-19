require "ISUI/ISContextMenu"
require "ISUI/ISToolTip"
require "ISMeditation/ZenWellnessContextMenu"
local UI = require "AutoMindful/UI"
local Options = require "AutoMindful/Options"
local Controller = require "AutoMindful/Controller"
local Progress = require "AutoMindful/Progress"

AutoMindful = AutoMindful or {}
local Context = AutoMindful.ContextMenu or {}
AutoMindful.ContextMenu = Context

local textures = {}
local function fillIcon(option, name)
    -- A texture would mask an upstream inventory-item icon in B42's renderer.
    if not option or option.iconTexture or option.itemForTexture or option.color or not getTexture then return end
    textures[name] = textures[name] or getTexture("media/ui/AutoMindful/" .. name .. ".png")
    option.iconTexture = textures[name]
end

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
    local original = {name=option.name, mode=mode, player=player, callback=option.onSelect, target=option.target, parameters={}}
    for index = 1, 10 do original.parameters[index] = option["param" .. index] end
    local submenu = option.subOption and menu:getSubMenu(option.subOption) or ISContextMenu:getNew(menu)
    local manual = submenu:addOption(tostring(option.name) .. " (once)", original, manualAction)
    if not manual then return end -- The native tutorial can suppress an existing label.
    for _, field in ipairs({"notAvailable", "iconTexture", "color", "itemForTexture", "toolTip", "checkMark"}) do
        manual[field] = option[field]
    end
    if manual.toolTip then manual.toolTip:setContextMenu(submenu) end
    fillIcon(manual, "Once")
    fillIcon(option, mode == "yoga" and "Mat" or "Bowl")
    local check = submenu:addOptionOnTop("Check supplies", player, UI.checkFor)
    fillIcon(check, "Supplies")
    tooltip(submenu, check, "Check supplies", "Open the live inventory and nearby supply report. This does not interrupt training or collect items immediately.")
    local train = submenu:addOptionOnTop(mode == "yoga" and "Train yoga" or "Train meditation", player, UI.startTraining, mode)
    fillIcon(train, mode == "yoga" and "Yoga" or "Meditate")
    local status = Controller.status(player)
    train.notAvailable = status.active
    local level = status[mode] or 0
    local description = (status.progress and status.progress[mode] and Progress.text(status.progress[mode])
        or string.format("Level %.1f / 10", level)) .. " <LINE> "
        .. (mode == "yoga" and "Practice Lifestyle's poses and rest between sessions. Normal yoga requirements still apply."
            or "Sit, meditate, and take care breaks before resuming. Eligible literature can relieve boredom.")
        .. " <LINE> " .. (status.active and "Stop the current loop before changing modes."
            or "Uses your saved adjacent-supply setting. The window can stay closed.")
    tooltip(submenu, train, "Automatic " .. mode, description)
    if mode == "meditation" then
        local endurance = submenu:addOptionOnTop("Meditate to Full Endurance", player, UI.startTraining, "endurance")
        fillIcon(endurance, "Endurance")
        endurance.notAvailable = status.active
        tooltip(submenu, endurance, "Meditate to Full Endurance", status.active
            and "Stop the current loop before starting another."
            or "Meditate until endurance is full, then stop. No yoga, supply use or scouting.")
    end
    local open = submenu:addOptionOnTop("Open AutoMindful", player, UI.open)
    fillIcon(open, "Open")
    tooltip(submenu, open, "AutoMindful window", "Open training, both-skill mode, live supplies, and collection settings. Closing the window keeps the training loop running.")
    menu:addSubMenu(option, submenu)
    option.onSelect, option.target, option.notAvailable = nil, nil, false
    for index = 1, 10 do option["param" .. index] = nil end
    option.toolTip = nil
    option.autoMindfulOriginal = original
    return original
end

local function walk(menu, visited, visit)
    if not menu or visited[menu] then return end
    visited[menu] = true
    for _, option in ipairs(menu.options) do
        visit(menu, option)
        if option.subOption then walk(menu:getSubMenu(option.subOption), visited, visit) end
    end
end

local function sameAction(a, option, mode, player)
    if a.mode ~= mode or a.player ~= player or a.name ~= option.name or a.callback ~= option.onSelect or a.target ~= option.target then return false end
    for i = 1, 10 do if a.parameters[i] ~= option["param" .. i] then return false end end
    return true
end

function Context.attach(menu, player)
    if not player or player:isDead() then return end
    local originals, pending = {}, {}
    local entries = ZenWellnessContextMenu.Options
    walk(menu, {}, function(parent, option)
        if option.autoMindfulOriginal then
            originals[#originals+1] = option.autoMindfulOriginal
        elseif option.onSelect and option.onSelect ~= manualAction then
            local mode
            if option.onSelect == entries.Meditation.onAction or option.param1 == entries.Meditation then mode = "meditation"
            elseif option.onSelect == entries.Yoga.onAction or option.param1 == entries.Yoga then mode = "yoga" end
            if mode then pending[#pending+1] = {parent, option, mode} end
        end
    end)
    -- A builder may append the same native leaf twice on the same live menu.
    -- Decorate it once, without removing a foreign row or merging different targets.
    for _, row in ipairs(pending) do
        local seen = false
        for _, original in ipairs(originals) do
            if sameAction(original, row[2], row[3], player) then seen = true; break end
        end
        if not seen then originals[#originals+1] = decorate(row[1], row[2], player, row[3]) end
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
    for _, existing in ipairs(context.options) do
        if existing.autoMindfulGeneral and existing.target == player then
            if existing.name ~= label then
                existing.name = label
                context:setWidth(context:calcWidth())
            end
            return
        end
    end
    local option = context:addOption(label, player, UI.open)
    if not option then return end
    option.autoMindfulGeneral = true
    fillIcon(option, "Mindful")
    tooltip(context, option, "AutoMindful", "Open the training window and live supplies. Training continues while the window is closed.")
end

Context.install()
return Context
