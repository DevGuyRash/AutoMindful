-- What AutoMindful can do for this survivor right now. The window and the
-- right-click menu both read this list, so a job that makes no sense in the
-- current situation is missing from both, and a blocked one says why in both.
local Controller = require "AutoMindful/Controller"
local Options = require "AutoMindful/Options"
local Preferences = require "AutoMindful/Preferences"
local Progress = require "AutoMindful/Progress"
local Tiers = require "AutoMindful/TierTargets"
local Theme = require "AutoMindful/Theme"
local Log = require "AutoMindful/Log"

local Jobs = {}
local names = {meditation="Meditation", yoga="Yoga", both="Yoga and Meditation", recovery="Autopilot"}
local policyText = {alternate="Switches after each session", lowest="Trains whichever is behind", closest="Finishes whichever is ahead"}
local tierModes = {meditation="meditateTo", yoga="yogaTo"}
local tierFamily = {meditation="Mindfulness", yoga="Zen"}
Jobs.colors = {meditation="meditation", yoga="yoga", both="both", tier="tier", recovery="recovery",
    meditateTo="meditation", yogaTo="yoga"}
Jobs.icons = {meditation="Meditate", yoga="Yoga", both="Mindful", tier="Mindful", recovery="Endurance",
    meditateTo="Meditate", yogaTo="Yoga"}

function Jobs.title(status)
    local goal = status.tierGoal
    if status.mode == "meditateTo" or status.mode == "yogaTo" then
        return "Reach " .. (goal and Tiers.label(goal.kind, goal.target) or "a moodle tier")
    end
    local name = names[status.mode] or "Second Nature"
    return status.backgroundPractice and (name .. " practice") or name
end

local needs = {
    {"water","THIRST"}, {"food","HUNGRY"}, {"fatigue","TIRED"}, {"endurance","ENDURANCE"}, {"boredom","BORED"},
    {"pain","PAIN"}, {"stress","STRESS"}, {"unhappiness","UNHAPPY"}, {"panic","PANIC"},
}

-- Only moodles the game is showing. Labels are the game's own, so they are
-- translated and always agree with the icons on the right of the screen.
function Jobs.needs(player)
    local result, moodles = {}, player.getMoodles and player:getMoodles()
    if not moodles or not MoodleType then return result end
    for _, row in ipairs(needs) do
        local kind = MoodleType[row[2]]
        local level = kind and moodles:getMoodleLevel(kind) or 0
        if level > 0 then
            local label = moodles.getMoodleDisplayString and Theme.plain(moodles:getMoodleDisplayString(kind)) or row[1]
            result[#result + 1] = {id=row[1], level=level, label=label}
        end
    end
    return result
end

-- A tier is offered only when it is unlocked and not already active.
function Jobs.tiers(player, status, kind)
    local result = {}
    if not Tiers.providerCompatible() or not Tiers.wellnessEnabled() then return result end
    local current, skill = Tiers.current(player, kind), tonumber(status[kind])
    if current == nil or skill == nil then return result end
    for _, entry in ipairs(Tiers.choices(kind)) do
        if entry.tier > current and Tiers.clamp(kind, entry.tier, skill) == entry.tier then
            result[#result + 1] = {mode=tierModes[kind], kind=kind, tier=entry.tier, label=entry.label}
        end
    end
    return result
end

local function skillText(status, kind)
    local progress = status.progress and status.progress[kind]
    if not progress then return "Level " .. tostring(status[kind] or 0) end
    if progress.capped then return "Level 10. Practises while you are idle" end
    return string.format("Level %d, %s of %s XP", progress.level, Progress.number(math.floor(progress.current)), Progress.number(progress.required))
end

local function add(list, player, status, job)
    local ok, reason = Controller.check(player, job.mode or job.id, job.tier)
    if not ok and job.id ~= "tier" then job.disabled, job.reason = true, Theme.plain(reason) end
    job.color, job.icon = Jobs.colors[job.id], Jobs.icons[job.id]
    job.running = status.active and status.mode == job.id or nil
    list[#list + 1] = job
end

function Jobs.addRecovery(list, player, status)
    local present, words = Jobs.needs(player), {}
    for index, need in ipairs(present) do if index <= 3 then words[#words + 1] = need.label end end
    add(list, player, status, {id="recovery", mode="recovery", title=names.recovery,
        sub=#words > 0 and ("Looks after: " .. table.concat(words, ", "):lower()) or "Looks after the survivor while you play or are away"})
end

function Jobs.list(player, status)
    local list = {}
    local gates = Controller.gates(player)
    if not gates then
        -- Lifestyle is missing, still loading, or its Wellness is off: say that once.
        local recovery, missing = Controller.check(player, "recovery")
        local _, wellness = Controller.check(player, "both")
        if recovery then Jobs.addRecovery(list, player, status) end
        local notice = wellness and missing and missing ~= wellness and (wellness .. " " .. missing) or wellness or missing
        return list, Theme.plain(notice)
    end
    for _, kind in ipairs({"yoga", "meditation"}) do
        local gate = gates[kind]
        local sub, tone = skillText(status, kind)
        local progress = status.progress and status.progress[kind]
        if not gate.ready then
            sub = sub .. ". " .. (gate.temporary and "Rests first: " or kind == "meditation" and gate.kind == "boredom" and "Reads first: " or "Blocked: ")
                .. (Theme.plain(gate.reason) or "Lifestyle's requirements are not met")
            tone = "warn"
        end
        add(list, player, status, {id=kind, mode=kind, title=names[kind], sub=sub, tone=tone,
            fraction=progress and not progress.capped and progress.fraction or nil})
    end
    local meditation, yoga = status.meditation or 0, status.yoga or 0
    if (meditation >= 10) == (yoga >= 10) then
        add(list, player, status, {id="both", mode="both", title=names.both,
            sub=meditation >= 10 and "Both at level 10. Takes turns while you are idle" or policyText[Options.cyclePolicy()]})
    end
    local tiers, reachable = {}, {}
    for _, kind in ipairs({"meditation", "yoga"}) do
        tiers[kind] = Jobs.tiers(player, status, kind)
        local best = tiers[kind][#tiers[kind]]
        if best then reachable[#reachable + 1] = best.label end
    end
    if #reachable > 0 then
        add(list, player, status, {id="tier", mode="recovery", title="Reach a moodle tier", tiers=tiers, menu=true,
            sub="Practise, then stop. Up to " .. table.concat(reachable, " or ")})
    end
    Jobs.addRecovery(list, player, status)
    return list
end

-- Returns whether it started; the reason is shown where the player clicked.
function Jobs.launch(player, mode, tier)
    local started, message = Controller.launch(player, mode, Preferences.collectNearby(player), tier)
    local window = AutoMindful.UI and AutoMindful.UI.windows[player:getPlayerNum()]
    if not started and AutoMindful.UI then window = AutoMindful.UI.open(player) end
    if window then
        window.startError = not started and message or nil
        window:invalidate()
    end
    return started, message
end

function Jobs.stop(player, source)
    Log.event(player, "ui.stop", "source", source)
    Controller.stop(player, "You stopped Second Nature.")
    local window = AutoMindful.UI and AutoMindful.UI.windows[player:getPlayerNum()]
    if window then window.startError = nil; window:invalidate() end
end

-- Fill a context menu with the tiers that can be reached, grouped by practice.
function Jobs.fillTiers(menu, player, tiers)
    local function leaf(parent, entry)
        local option = parent:addOption(entry.label, player, Jobs.launch, entry.mode, entry.tier)
        if option then
            option.iconTexture, option.color = Tiers.texture(entry.kind, entry.tier)
            if not option.iconTexture then option.color = nil end
        end
    end
    local groups = {}
    for _, kind in ipairs({"meditation", "yoga"}) do if #tiers[kind] > 0 then groups[#groups + 1] = kind end end
    for _, kind in ipairs(groups) do
        local parent = menu
        if #groups > 1 then
            local group = menu:addOption(tierFamily[kind], nil, nil)
            if group then
                group.iconTexture = Theme.icon(Jobs.icons[kind])
                parent = ISContextMenu:getNew(menu)
                menu:addSubMenu(group, parent)
            end
        end
        for _, entry in ipairs(tiers[kind]) do leaf(parent, entry) end
    end
end

return Jobs
