require "ISUI/ISContextMenu"
require "ISUI/ISToolTip"
require "ISMeditation/ZenWellnessContextMenu"
local UI = require "AutoMindful/UI"
local Options = require "AutoMindful/Options"
local Controller = require "AutoMindful/Controller"
local Progress = require "AutoMindful/Progress"
local TierMenu = require "AutoMindful/TierMenu"

AutoMindful = AutoMindful or {}
local Context = AutoMindful.ContextMenu or {}
AutoMindful.ContextMenu = Context

-- These symbols are in B42's ordinary UI texture packs, not other mods or a local profile.
local stockIcons = {
    Open="Item_Clipboard", Supplies="Item_Backpack", Yoga="Item_Dumbbell", Meditate="Item_Candle",
    Endurance="Moodle_Icon_Endurance", Mat="Item_Bathtowel", Bowl="Item_Bowl",
    Once="ArrowRight", Mindful="FavoriteStar",
}
local packaged = {}
local function usable(t)
    if not t then return false end
    local ok, yes = pcall(function()
        local name = t.getName and t:getName()
        return name ~= "EngineErrorTexture" and name ~= "EngineErrorTexture.png"
            and not (t.isFailure and t:isFailure()) and not (t.isDestroyed and t:isDestroyed())
            and (not t.isReady or t:isReady())
    end)
    return ok and yes
end
local function lookup(key)
    if not getTexture then return end
    local ok, t = pcall(getTexture, key)
    if ok and usable(t) then return t end
end
local function icon(name)
    if usable(packaged[name]) then return packaged[name] end
    packaged[name] = nil
    local path = "media/ui/AutoMindful/" .. name .. ".png"
    -- fileExists checks the game's VFS. Don't feed unmounted paths to the Java
    -- texture miss cache. Never cache a fallback as the real branded texture.
    if fileExists then
        local ok, exists = pcall(fileExists, path)
        if ok and exists then packaged[name] = lookup(path) end
    end
    return packaged[name] or lookup(stockIcons[name])
end
local function fillIcon(option, name)
    if not option then return end
    local ours = option.autoMindfulAssignedIcon
    if option.itemForTexture or option.color or (option.iconTexture and option.iconTexture ~= ours) then
        -- A later upstream item/tint/texture still owns the presentation.
        if ours and option.iconTexture == ours then option.iconTexture = nil end
        option.autoMindfulIconKey, option.autoMindfulAssignedIcon = nil, nil
        return
    end
    local t = icon(name)
    option.iconTexture, option.autoMindfulAssignedIcon, option.autoMindfulIconKey = t, t, name
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
    local status = Controller.status(player)
    local target = submenu:addOptionOnTop(TierMenu.title(mode), nil, nil)
    if target then
        fillIcon(target, "Mindful")
        local tiers = ISContextMenu:getNew(submenu)
        TierMenu.fill(tiers, player, mode, status, UI.startTraining)
        submenu:addSubMenu(target, tiers)
    end
    local check = submenu:addOptionOnTop("Check supplies", player, UI.checkFor)
    fillIcon(check, "Supplies")
    tooltip(submenu, check, "Check supplies", "Open the live inventory and nearby supply report. This does not interrupt your current mode or collect items immediately.")
    local train = submenu:addOptionOnTop(mode == "yoga" and "Train yoga" or "Train meditation", player, UI.startTraining, mode)
    fillIcon(train, mode == "yoga" and "Yoga" or "Meditate")
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
        local endurance = submenu:addOptionOnTop("Recover to Full Endurance", player, UI.startTraining, "recoverEndurance")
        if endurance then
            fillIcon(endurance, "Endurance")
            endurance.notAvailable = status.active
            tooltip(submenu, endurance, "Recover to Full Endurance", status.active
                and "Use Stop All before changing AutoMindful modes."
                or "Run Recovery until your endurance is full, then stop. Useful care and your supply settings still apply.")
        end
    end
    local open = submenu:addOptionOnTop("Open AutoMindful", player, UI.open)
    fillIcon(open, "Open")
    tooltip(submenu, open, "AutoMindful window", "Open Recovery, training, supplies and collection settings. Closing the window keeps the current mode running.")
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
        if option.autoMindfulIconKey then fillIcon(option, option.autoMindfulIconKey) end
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
    local recovering = status.mode == "recovery" or status.mode == "recoverEndurance"
    local label = status.active and (recovering and "AutoMindful (recovery)" or "AutoMindful (running)") or "AutoMindful"
    for _, existing in ipairs(context.options) do
        if existing.autoMindfulGeneral and existing.target == player then
            if existing.autoMindfulIconKey then fillIcon(existing, existing.autoMindfulIconKey) end
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
    tooltip(context, option, "AutoMindful", "Open Recovery, training and live supplies. The current mode continues while the window is closed.")
end

Context.install()
return Context
