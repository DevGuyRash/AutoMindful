-- The right-click menu shows AutoMindful where it applies and nowhere else:
--   idle            under Lifestyle's own Wellness entry, beside its actions
--   on a yoga mat   "practise here", because that is what the mat is for
--   a job running   on your survivor, because Wellness hides itself then
require "ISUI/ISContextMenu"
require "ISUI/ISToolTip"
require "ISMeditation/ZenWellnessContextMenu"
require "TimedActions/WalkToTimedAction"
local Controller = require "AutoMindful/Controller"
local Jobs = require "AutoMindful/Jobs"
local Log = require "AutoMindful/Log"
local Options = require "AutoMindful/Options"
local Theme = require "AutoMindful/Theme"
local Window = require "AutoMindful/Window"

AutoMindful = AutoMindful or {}
local Menu = AutoMindful.WorldMenu or {}
AutoMindful.WorldMenu = Menu

local function tip(menu, option, title, text)
    if not option or not text then return end
    local tooltip = ISToolTip:new()
    tooltip:initialise()
    tooltip:setName(title)
    tooltip.description = text
    tooltip:setContextMenu(menu)
    option.toolTip = tooltip
end

local function choose(player, job)
    Log.event(player, "ui.choose", "job", job.id, "source", "menu")
    Jobs.launch(player, job.mode)
end

local function submenu(parent, option)
    local menu = ISContextMenu:getNew(parent)
    parent:addSubMenu(option, menu)
    return menu
end

local function fillJobs(menu, player, status)
    local jobs, unavailable = Jobs.list(player, status)
    local offered = {}
    for _, job in ipairs(jobs) do
        if not job.running then
            local option = menu:addOption(job.title, player, choose, job)
            if option then
                option.iconTexture = Theme.icon(job.icon)
                if job.id == "tier" then
                    option.onSelect, option.target, option.param1 = nil, nil, nil
                    Jobs.fillTiers(submenu(menu, option), player, job.tiers)
                else
                    option.notAvailable = job.disabled
                    tip(menu, option, job.title, job.disabled and job.reason or job.sub)
                end
                offered[#offered + 1] = job.id .. (job.disabled and "(blocked: " .. tostring(job.reason) .. ")" or "")
            end
        end
    end
    if unavailable then
        local option = menu:addOption(unavailable, nil, nil)
        if option then option.notAvailable = true end
    end
    return table.concat(offered, ", ")
end

local function stop(player) Jobs.stop(player, "menu") end

local function fillRunning(menu, player, status)
    local option = menu:addOption("Stop", player, stop)
    if option then tip(menu, option, "Stop AutoMindful", "Your own actions and other mods' actions keep going.") end
    if status.mode == "recovery" then
        local away = menu:addOption(status.away and "I am back" or "I am going AFK", player, Controller.setAway, not status.away)
        if away then tip(menu, away, "Recovery", status.away and "Back to small help only." or "Full care from now on, and a warning if something would go wrong.") end
    end
    local switch = menu:addOption("Switch to", nil, nil)
    local offered = switch and fillJobs(submenu(menu, switch), player, status) or ""
    menu:addOption("Show window", player, Window.open)
    return offered
end

local function root(context, player, status)
    for _, option in ipairs(context.options) do if option.autoMindful then return nil end end
    local label = status.active and ("AutoMindful: " .. Jobs.title(status)) or "AutoMindful"
    local option = context:addOption(label, nil, nil)
    if not option then return nil end
    option.autoMindful = true
    option.iconTexture = Theme.icon(status.active and Jobs.icons[status.mode] or "Mindful")
    return submenu(context, option)
end

-- Idle: one entry inside Wellness. Lifestyle's own actions stay one click away.
function Menu.attach(context, player)
    if not player or player:isDead() then return end
    -- Recovery is often idle, and Wellness with it. The running entry has Stop.
    local status = Controller.status(player)
    if status.active or status.switching then return end
    local entries = ZenWellnessContextMenu.Options
    local function find(menu, seen)
        if not menu or seen[menu] then return nil end
        seen[menu] = true
        for _, option in ipairs(menu.options) do
            if option.autoMindful then return nil, true end
            if option.param1 == entries.Yoga or option.param1 == entries.Meditation
                    or option.onSelect ~= nil and (option.onSelect == entries.Yoga.onAction or option.onSelect == entries.Meditation.onAction) then
                return menu
            end
        end
        for _, option in ipairs(menu.options) do
            if option.subOption then
                local found, present = find(menu:getSubMenu(option.subOption), seen)
                if found or present then return found, present end
            end
        end
    end
    local wellness = find(context, {})
    if not wellness then return end
    for _, option in ipairs(wellness.options) do if option.autoMindful then return end end
    local option = wellness:addOption("AutoMindful", nil, nil)
    if not option then return end
    option.autoMindful = true
    option.iconTexture = Theme.icon("Mindful")
    local menu = submenu(wellness, option)
    local offered = fillJobs(menu, player, status)
    menu:addOption("Show window", player, Window.open)
    Log.detail(player, "ui.menu", "place", "wellness", "offered", offered)
end

function Menu.install()
    if ZenWellnessContextMenu.doBuildMenu == Menu.wrapper then return end
    local original = ZenWellnessContextMenu.doBuildMenu
    Menu.wrapper = function(playerIndex, menu, ...)
        local function finish(...)
            Menu.attach(menu, getSpecificPlayer(playerIndex))
            return ...
        end
        return finish(original(playerIndex, menu, ...))
    end
    ZenWellnessContextMenu.doBuildMenu = Menu.wrapper
end

-- Lifestyle accepts a mat only with both halves in place.
local halves = {[48]={49,"getN"}, [49]={48,"getS"}, [50]={51,"getN"}, [51]={50,"getS"}, [52]={53,"getE"}, [53]={52,"getW"},
    [54]={55,"getN"}, [55]={54,"getS"}, [56]={57,"getE"}, [57]={56,"getW"}, [58]={59,"getN"}, [59]={58,"getS"}}

local function tileOf(object)
    local name = object and object.getSpriteName and object:getSpriteName()
    return type(name) == "string" and tonumber(name:match("^floors_rugs_01_(%d+)$")) or nil
end

local function has(square, tile)
    local objects = square and square.getObjects and square:getObjects()
    if not objects then return false end
    for index = 0, objects:size() - 1 do
        local found = tileOf(objects:get(index))
        if found and (found == tile or tile == nil and halves[found]) then return found end
    end
    return false
end

local function completeMat(square)
    local tile = has(square)
    local half = tile and halves[tile]
    return half and square[half[2]] and has(square[half[2]](square), half[1]) and true or false
end

local function matUnder(worldobjects)
    for _, object in ipairs(worldobjects or {}) do
        local square = object.getSquare and object:getSquare()
        if square and completeMat(square) then return square end
    end
end

-- "On your survivor": the clicked square is theirs or touches it.
local function onSurvivor(player, worldobjects)
    local here = player:getSquare()
    if not here then return false end
    for _, object in ipairs(worldobjects or {}) do
        local square = object.getSquare and object:getSquare()
        if square and square:getZ() == here:getZ() and math.abs(square:getX() - here:getX()) <= 1
                and math.abs(square:getY() - here:getY()) <= 1 then return true end
    end
    return false
end

local function practiseHere(player, mode, square)
    Log.event(player, "ui.choose", "job", mode, "source", "mat")
    if player:getSquare() == square then Jobs.launch(player, mode); return end
    local walk = ISWalkToTimedAction:new(player, square)
    walk:setOnComplete(function() Jobs.launch(player, mode) end)
    ISTimedActionQueue.add(walk)
end

function Menu.fill(playerIndex, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer(playerIndex)
    if not player or player:isDead() then return end
    local status = Controller.status(player)
    if status.active then
        if not Options.generalMenu() and not onSurvivor(player, worldobjects) then return end
        local menu = root(context, player, status)
        if menu then Log.detail(player, "ui.menu", "place", "running", "offered", fillRunning(menu, player, status)) end
        return
    end
    local mat = matUnder(worldobjects)
    if mat and Controller.gates(player) and not player:hasTimedActions() then
        local menu = root(context, player, status)
        if menu then
            local ok, reason = Controller.check(player, "yoga")
            local option = menu:addOption("Train Yoga here", player, practiseHere, "yoga", mat)
            if option then
                option.iconTexture = Theme.icon("Yoga")
                option.notAvailable = not ok
                tip(menu, option, "Train Yoga here", not ok and Theme.plain(reason) or "Walk onto this mat and start.")
            end
            menu:addOption("Show window", player, Window.open)
            Log.detail(player, "ui.menu", "place", "mat", "offered", "yoga", "blocked", not ok and reason or nil)
        end
        return
    end
    if not Options.generalMenu() then return end
    local menu = root(context, player, status)
    if menu then
        Log.detail(player, "ui.menu", "place", "general", "offered", fillJobs(menu, player, status))
        menu:addOption("Show window", player, Window.open)
    end
end

Menu.install()
return Menu
