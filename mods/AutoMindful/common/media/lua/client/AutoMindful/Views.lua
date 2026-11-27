-- Turns live state into rows. Nothing here draws or stores anything: a section
-- appears only while it has something to say.
local Controller = require "AutoMindful/Controller"
local Decisions = require "AutoMindful/DecisionHistory"
local Jobs = require "AutoMindful/Jobs"
local Log = require "AutoMindful/Log"
local Options = require "AutoMindful/Options"
local Preferences = require "AutoMindful/Preferences"
local Progress = require "AutoMindful/Progress"
local Theme = require "AutoMindful/Theme"
local Tiers = require "AutoMindful/TierTargets"
local Wellness = require "AutoMindful/WellnessInfo"
local Clock = require "AutoMindful/Clock"
local Dashboard = require "AutoMindful/Dashboard"
Dashboard.register(require "AutoMindful/Cards/Wounds")
Dashboard.register(require "AutoMindful/Cards/Nutrition")
Dashboard.register(require "AutoMindful/Cards/Lifestyle")

local Views = {}
local colors = Theme.colors

local function head(rows, text, right) rows[#rows + 1] = {kind="head", text=text, right=right} end
local function gap(rows, height) rows[#rows + 1] = {kind="gap", height=height} end

local function elapsed(ms)
    local s = math.floor((ms or 0) / 1000)
    if s >= 3600 then return string.format("%dh %02dm", math.floor(s / 3600), math.floor(s / 60) % 60) end
    return string.format("%dm %02ds", math.floor(s / 60), s % 60)
end

local waiting = {manual=true, between=true, resuming=true, recovering=true, ["recovery-paused"]=true, seated=true}

-- What it is doing, then why, without repeating itself.
local function activity(status)
    local label = status.decisionLabel or status.message or "Working"
    local detail
    if status.guard then
        -- What is wrong, in one line, instead of a general word about safety.
        return Theme.plain(status.message) or label, nil, colors.warn
    end
    for _, text in ipairs({status.careWaiting and status.message or status.decisionDetail or "", status.message or ""}) do
        local plain = Theme.plain(text)
        if plain and plain ~= label and not detail then detail = plain end
    end
    local tone = (status.careWaiting or waiting[status.phase]) and colors.warn or colors.good
    return label, detail, tone
end

local function chips(rows, player)
    local list = {}
    for _, need in ipairs(Jobs.needs(player)) do
        list[#list + 1] = {text=need.label, icon=Theme.moodle(need.id),
            color=need.level >= 3 and colors.bad or need.level == 2 and colors.warn or colors.muted}
    end
    if #list > 0 then rows[#rows + 1] = {kind="chips", chips=list} end
end

local skillNames = {yoga="Yoga ", meditation="Meditation ", cooking="Cooking "}

local function skillBars(rows, status)
    for _, kind in ipairs({"yoga", "meditation", "cooking"}) do
        local trained
        if kind == "cooking" then trained = status.mode == "recovery" and Options.cookMeals() and Options.cookTraining() ~= "off"
        else
            trained = status.mode == kind or status.mode == "both"
                or kind == "yoga" and status.mode == "yogaTo" or kind == "meditation" and status.mode == "meditateTo"
        end
        local progress = status.progress and status.progress[kind]
        if trained and progress then
            local change = Progress.change(status.startProgress and status.startProgress[kind], progress)
            local gain = change and (change.amount and (Progress.number(change.amount) .. " XP") or (change.levels .. " level")) or nil
            rows[#rows + 1] = {kind="bar", label=skillNames[kind] .. progress.level,
                right=progress.capped and "Max" or string.format("%s / %s XP", Progress.number(progress.current), Progress.number(progress.required)),
                fraction=progress.capped and 1 or progress.fraction, color=colors[kind] or colors.warn,
                gain=gain and ((change.positive and "+" or "") .. gain), loss=change and not change.positive}
            -- At this session's pace, how long to the next level (real time).
            local elapsed = status.elapsed
            if change and change.amount and change.amount > 0 and elapsed and elapsed >= 120000 and not progress.capped then
                local minutes = math.ceil((progress.required - progress.current) / (change.amount / elapsed) / 60000)
                local text = minutes > 7 * 1440 and "over a week" or minutes < 60 and (minutes .. " min")
                    or minutes < 1440 and (math.floor(minutes / 60) .. " h " .. (minutes % 60) .. " min")
                    or (math.floor(minutes / 1440) .. " d " .. math.floor(minutes % 1440 / 60) .. " h")
                rows[#rows + 1] = {kind="text", text="About " .. text .. " to level " .. (progress.level + 1) .. " at this pace.", color=colors.muted}
            end
        end
    end
end

-- Things the player may want to act on. Empty most of the time.
local function notices(player, status, report, startError, said)
    local list = {}
    local function add(text, color)
        text = Theme.plain(text)
        if not text or said and said[text] then return end
        for _, row in ipairs(list) do if row.text == text then return end end
        list[#list + 1] = {kind="text", bullet=true, text=text, color=color or colors.warn}
    end
    add(startError, colors.bad)
    if status.active then
        for _, alert in ipairs(status.alerts or {}) do if not (said and said[alert.id]) then add(alert.text, colors.bad) end end
        add(status.aidNotice, colors.bad)
        add(status.kitchen and status.kitchen.notice, colors.warn)
        if not (said and (said.food or said.water)) then add(status.careNotice) end
        add(status.painNotice)
    end
    add(status.returnNotice)
    -- Borrowing is routine while a job runs; it matters when it is left over.
    if not status.active then
        for _, loan in ipairs(Controller.loans(player)) do add("Still borrowed: " .. loan.name .. ", from " .. loan.from .. ".", colors.muted) end
    end
    if Tiers.providerMismatch and Tiers.providerMismatch() then
        add("This Lifestyle version has not been checked. Tier goals and Mindfulness relief are off until it is.")
    end
    if not status.active and report then
        if (report.food or 0) + (report.nearbyFood or 0) == 0 then add("No food known nearby.", colors.muted) end
        if (report.water or 0) + (report.nearbyWater or 0) == 0 then add("No safe drink known nearby.", colors.muted) end
    end
    return list
end

local function appendNotices(rows, list)
    if #list == 0 then return end
    gap(rows, 4)
    head(rows, "Worth knowing")
    for _, row in ipairs(list) do rows[#rows + 1] = row end
end

-- Recovery's own part: who it thinks is at the controls, how long the known
-- supplies last, and what would go wrong first.
local function outlookRows(rows, player, status)
    local outlook = Controller.outlook(player)
    if not outlook then return nil end
    local function tone(hours) return hours < 12 and colors.bad or hours < 24 and colors.warn or colors.text end
    rows[#rows + 1] = {kind="columns", label="Lasts up to", color=colors.muted, cells={{text="Carried"}, {text="Known"}}}
    rows[#rows + 1] = {kind="columns", label="Food", cells={{text=outlook.carriedFood, color=tone(outlook.carriedFoodHours)},
        {text=outlook.food, color=tone(outlook.foodHours)}}}
    if outlook.cook then
        rows[#rows + 1] = {kind="text", text="Known food includes about " .. outlook.cook .. " that needs cooking.", color=colors.muted}
    end
    rows[#rows + 1] = {kind="columns", label="Drink", cells={{text=outlook.carriedWater, color=tone(outlook.carriedWaterHours)},
        outlook.endlessWater and {text="Running tap", color=colors.good} or {text=outlook.water, color=tone(outlook.waterHours)}}}
    local shown, said = 0, {farewell=true}
    for _, issue in ipairs(outlook.issues) do
        if shown < 4 then
            shown = shown + 1
            said[issue.id], said[issue.text] = true, true
            rows[#rows + 1] = {kind="text", bullet=true, text=issue.text,
                color=issue.severity >= 3 and colors.bad or issue.severity == 2 and colors.warn or colors.muted}
        end
    end
    if shown == 0 then rows[#rows + 1] = {kind="text", text="Nothing known would stop it looking after the survivor.", color=colors.good} end
    return said
end

function Views.now(window)
    local player, status, rows = window.player, window.status, {}
    Views.glances(rows, window, true)
    if status.active or status.switching then
        local label, detail, tone = activity(status)
        rows[#rows + 1] = {kind="title", text=Jobs.title(status), right=status.elapsed and elapsed(status.elapsed),
            color=colors[Jobs.colors[status.mode] or "recovery"], icon=Theme.icon(Jobs.icons[status.mode] or "Mindful")}
        gap(rows, 4)
        rows[#rows + 1] = {kind="text", text=label, color=tone, tight=detail ~= nil}
        -- A practice that is simply running needs no second sentence.
        if status.phase == "yoga" or status.phase == "meditation" then detail = nil end
        if detail then rows[#rows + 1] = {kind="text", text=detail, color=colors.muted} end
        local goal = status.tierGoal
        if goal then
            local current = goal.current and goal.current > 0 and Tiers.label(goal.kind, goal.current) or "none yet"
            rows[#rows + 1] = {kind="text", text="Goal: " .. (Tiers.label(goal.kind, goal.target) or "moodle tier") .. " (now " .. current .. ")", color=colors.tier}
        end
        local cycle = status.mode == "both" and status.cycle
        if cycle and (cycle.due == "yoga" or cycle.due == "meditation") and status.phase ~= cycle.due then
            local gate = cycle.gates and cycle.gates[cycle.due]
            rows[#rows + 1] = {kind="text", text="Next: " .. (cycle.due == "yoga" and "Yoga" or "Meditation")
                .. (gate and not gate.ready and Theme.plain(gate.reason) and (" - " .. Theme.plain(gate.reason)) or ""), color=colors.muted}
        end
        gap(rows, 2)
        skillBars(rows, status)
        chips(rows, player)
        local said
        local kitchen = status.kitchen
        if kitchen and kitchen.progress and kitchen.on then
            rows[#rows + 1] = {kind="bar", label="On the stove: " .. (Theme.plain(kitchen.dish) or "food"), right=math.floor(kitchen.progress * 100) .. "%",
                fraction=kitchen.progress, color=colors.warn}
        end
        if status.mode == "recovery" then
            gap(rows, 4)
            said = outlookRows(rows, player, status)
            gap(rows, 4)
            rows[#rows + 1] = {kind="setting", label=status.away and "Looking after everything" or "Helping while you play",
                value=status.away and "I am back" or "I am going AFK", valueColor=status.away and colors.warn or colors.recovery,
                onClick=function() Controller.setAway(player, not status.away); window:invalidate() end,
                tip="Away: it also walks for small needs, practises for relief, sleeps in bed, fills bottles and warns you out loud. "
                    .. "It starts by itself after " .. Options.awayMinutes[Options.awayIndex()] .. " minutes without input; moving or a key ends it."}
        end
        gap(rows, 4)
        rows[#rows + 1] = {kind="buttons", buttons={
            {text="Stop", color=colors.bad, onClick=function() Jobs.stop(player, "window") end,
                tip="Stops Second Nature and its own action only. Anything you or another mod queued keeps going."},
            {text="Switch", menu=true, color=colors.muted, onClick=function() window:openSwitchMenu() end,
                tip="Change to another job without stopping first."},
        }}
        Views.glances(rows, window, false)
        appendNotices(rows, notices(player, status, window.report, window.startError, said))
        return rows
    end
    local jobs, unavailable = Jobs.list(player, status)
    chips(rows, player)
    if status.phase == "stopped" or status.phase == "complete" then
        rows[#rows + 1] = {kind="text", text=Theme.plain(status.message) or "", color=status.phase == "complete" and colors.good or colors.muted}
        gap(rows, 2)
    end
    if unavailable then rows[#rows + 1] = {kind="text", text=unavailable, color=colors.warn} end
    if #jobs > 0 then
        head(rows, "Start")
        gap(rows, 5)
        for _, job in ipairs(jobs) do
            rows[#rows + 1] = {kind="job", title=job.title, sub=job.disabled and job.reason or job.sub, menu=job.menu,
                tone=job.disabled and colors.bad or job.tone and colors[job.tone], disabled=job.disabled, fraction=job.fraction,
                color=colors[job.color], icon=Theme.icon(job.icon),
                onClick=function() window:chooseJob(job) end}
        end
    end
    Views.glances(rows, window, false)
    appendNotices(rows, notices(player, status, window.report, window.startError))
    return rows
end

local supplyRows = {
    {label="Food", own="food", near="nearbyFood", need="food"}, {label="Drink", own="water", near="nearbyWater", need="water"},
    {label="Reading", own="literature", near="nearbyLiterature", need="boredom"}, {label="Painkillers", own="pain", near="nearbyPain", need="pain"},
}

function Views.supplies(window)
    local player, report, rows = window.player, window.report or {}, {}
    local range = Preferences.range(player)
    local needed = {}
    for _, need in ipairs(Jobs.needs(player)) do needed[need.id] = true end
    local nearLabel = range == "carried" and "Nearby (not used)" or (report.radius and ("Within " .. report.radius .. " tiles") or "Nearby")
    rows[#rows + 1] = {kind="columns", label="Known supplies", color=colors.muted, cells={{text="Carried"}, {text=nearLabel}}}
    for _, row in ipairs(supplyRows) do
        local own, near = report[row.own] or 0, report[row.near] or 0
        local empty = own == 0 and (near == 0 or range == "carried")
        rows[#rows + 1] = {kind="columns", label=row.label, color=empty and needed[row.need] and colors.bad or colors.text, cells={
            {text=tostring(own), color=own > 0 and colors.text or colors.faint},
            {text=tostring(near), color=near > 0 and range ~= "carried" and colors.text or colors.faint}}}
    end
    if (report.unknownContainers or 0) > 0 then
        rows[#rows + 1] = {kind="text", text=report.unknownContainers .. " containers have not been looked into.", color=colors.faint}
    end
    gap(rows, 4)
    rows[#rows + 1] = {kind="setting", label="Look for supplies", value=Views.rangeLabel(range), menu=true,
        onClick=function() window:openRangeMenu() end}
    if range == "walk" then
        rows[#rows + 1] = {kind="setting", label="Search radius", value=Options.searchRadius() .. " tiles", menu=true,
            onClick=function() window:openRadiusMenu() end}
    end
    rows[#rows + 1] = {kind="buttons", buttons={{text="Look again", onClick=function() window:lookAgain() end,
        tip="Re-read known contents now. Does not walk, collect or search anything."}}}
    local loans = Controller.loans(player)
    if #loans > 0 then
        head(rows, "Borrowed")
        for _, loan in ipairs(loans) do rows[#rows + 1] = {kind="columns", label=loan.name, cells={{text=""}, {text=loan.from}}} end
        if window.status.returnNotice then rows[#rows + 1] = {kind="text", text=window.status.returnNotice, color=colors.warn} end
    end
    local warnings = report.warnings or {}
    if #warnings > 0 then
        head(rows, "Worth knowing")
        for _, warning in ipairs(warnings) do rows[#rows + 1] = {kind="text", bullet=true, text=warning, color=colors.muted} end
    end
    return rows
end

function Views.rangeLabel(id)
    for _, entry in ipairs(Preferences.ranges) do if entry.id == id then return entry.label end end
end

function Views.log(window)
    local rows = {}
    rows[#rows + 1] = {kind="buttons", buttons={
        {text="Copy report", onClick=function() window:copyReport() end,
            tip="Copy the current state and recent events to the clipboard for a bug report."},
        {text="Detail: " .. Options.logLabel(), menu=true, onClick=function() window:openChoiceMenu("logLevel") end},
    }}
    if window.copied then rows[#rows + 1] = {kind="text", text=window.copied, color=colors.good} end
    rows[#rows + 1] = {kind="text", text=Options.logLevel() > 1 and ("Full log: Zomboid/Lua/" .. Log.fileName()) or "The log file is off.", color=colors.faint}
    local entries = Controller.recentDecisions(window.player)
    head(rows, "Recent decisions")
    if #entries == 0 then rows[#rows + 1] = {kind="text", text="Nothing yet. Start a job.", color=colors.muted} end
    for _, entry in ipairs(entries) do
        rows[#rows + 1] = {kind="entry", clock=entry.clock, text=entry.label, detail=entry.reason or entry.message,
            color=entry.code == "stopped" and colors.bad or nil}
    end
    return rows
end

local cautions = {["Trade-offs"]=true, ["Early stops"]=true, ["Multiplayer"]=true, ["Version"]=true}
local topics = {Meditation="meditation", Mindfulness="meditation", Yoga="yoga", Zen="yoga", Lessons="recovery"}

function Views.guide(window)
    local rows = {}
    local sections = Wellness.guide(window.player, window.status and window.status.progress)
    local chosen = sections[1]
    for _, section in ipairs(sections) do if section.title == window.topic then chosen = section end end
    if not chosen then return {{kind="text", text=Tiers.lifestylePresent() and "No guide available for this Lifestyle version." or "The guide covers Lifestyle: Hobbies Yoga and Meditation. Autopilot needs no setup.", color=colors.muted}} end
    window.topic = chosen.title
    local buttons = {}
    for _, section in ipairs(sections) do
        local c = colors[topics[section.title] or "meditation"]
        buttons[#buttons + 1] = {text=section.title, color=section == chosen and c or colors.faint,
            onClick=function() window.topic = section.title; window:invalidate(true) end}
        if #buttons == 3 then rows[#rows + 1] = {kind="buttons", buttons=buttons}; buttons = {} end
    end
    if #buttons > 0 then rows[#rows + 1] = {kind="buttons", buttons=buttons} end
    local accent = colors[topics[chosen.title] or "meditation"]
    if chosen.subtitle then rows[#rows + 1] = {kind="text", text=chosen.subtitle, color=accent} end
    for _, line in ipairs(chosen.lines) do
        local label, detail = line:match("^([^:]+):%s+(.+)$")
        if label and #label <= 44 then
            rows[#rows + 1] = {kind="text", text=label, color=cautions[label] and colors.warn or accent, tight=true}
            rows[#rows + 1] = {kind="text", text=detail, indent=10}
        else rows[#rows + 1] = {kind="text", text=line} end
    end
    return rows
end

local function toggle(window, rows, id)
    local option, text = Options.option(id), Options.windowText[id]
    rows[#rows + 1] = {kind="setting", label=text[1], tip=text[2], toggle=option:getValue() == true,
        onClick=function() Options.set(id, option:getValue() ~= true); window:invalidate() end}
end

local function choice(window, rows, id)
    local entry, text = Options.choice(id), Options.windowText[id]
    rows[#rows + 1] = {kind="setting", label=text[1], value=entry.short or entry.label, menu=true,
        tip=entry.help or text[2], onClick=function() window:openChoiceMenu(id) end}
end

local tones = {good=colors.good, warn=colors.warn, bad=colors.bad, muted=colors.muted}

local function count(rows, label, value, color)
    local some = (value or 0) > 0
    rows[#rows + 1] = {kind="columns", label=label, color=some and colors.text or colors.muted,
        cells={{text=""}, {text=tostring(value or 0), color=some and (color or colors.text) or colors.faint}}}
end

local function capital(text) return (text:gsub("^%l", string.upper)) end

-- The kitchen at a glance: what can cook, what there is to cook, where it keeps.
function Views.kitchen(window)
    local player, status, summary, rows = window.player, window.status or {}, window.kitchen, {}
    local cooking = Perks and Perks.Cooking and Progress.perk(player, Perks.Cooking)
    if cooking then
        rows[#rows + 1] = {kind="bar", label="Cooking " .. cooking.level, color=colors.cooking or colors.warn,
            right=cooking.capped and "Max" or string.format("%s / %s XP", Progress.number(cooking.current), Progress.number(cooking.required)),
            fraction=cooking.capped and 1 or cooking.fraction}
    end
    local dish = status.kitchen
    if dish and dish.progress and dish.on then
        rows[#rows + 1] = {kind="bar", label="On the stove: " .. (Theme.plain(dish.dish) or "food"),
            right=math.floor(dish.progress * 100) .. "%", fraction=dish.progress, color=colors.warn}
    end
    if not Options.cookMeals() then
        rows[#rows + 1] = {kind="text", text="Autopilot does not cook while " .. Options.windowText.recoveryCook[1] .. " is off.", color=colors.warn}
    end
    if not summary then
        rows[#rows + 1] = {kind="text", text="Looking around the kitchen...", color=colors.muted}
        return rows
    end
    head(rows, "Heat", "within " .. summary.radius .. " tiles")
    if #summary.heats == 0 then
        rows[#rows + 1] = {kind="text", text="No stove, microwave, grill, fireplace or campfire nearby.", color=colors.muted}
    end
    local fires = false
    for _, heat in ipairs(summary.heats) do
        fires = fires or heat.fueled
        rows[#rows + 1] = {kind="text", bullet=true, color=tones[heat.tone] or colors.text,
            text=capital(heat.name) .. ", " .. heat.tiles .. (heat.tiles == 1 and " tile" or " tiles") .. ": " .. heat.state}
    end
    head(rows, "Food")
    count(rows, "Raw, to cook", summary.raw)
    if summary.soon > 0 then count(rows, "Rots within " .. summary.soonDays .. " days", summary.soon, colors.warn) end
    count(rows, "Ready to eat", summary.ready)
    count(rows, "In the freezer", summary.frozen)
    head(rows, "Could make now")
    if not summary.dishes then
        rows[#rows + 1] = {kind="text", text="Dishes are off: turn on " .. Options.windowText.recoverySoup[1] .. " below.", color=colors.muted}
    elseif #summary.dishes == 0 then
        rows[#rows + 1] = {kind="text", text="No dish yet: " .. (summary.reason or "nothing nearby fits a recipe") .. ".", color=colors.muted}
    else
        for _, dish in ipairs(summary.dishes) do
            rows[#rows + 1] = {kind="text", bullet=true, color=colors.text,
                text=dish.name .. " in " .. dish.base .. ", " .. dish.count .. (dish.count == 1 and " ingredient" or " ingredients")
                    .. (dish.heat and (", on the " .. dish.heat) or ", no cooking")}
        end
        if (summary.more or 0) > 0 then rows[#rows + 1] = {kind="text", text="And " .. summary.more .. " more.", color=colors.muted} end
    end
    if summary.crafts and #summary.crafts > 0 then
        local more = (summary.moreCrafts or 0) > 0 and (" and " .. summary.moreCrafts .. " more") or ""
        rows[#rows + 1] = {kind="text", text="Crafts it could do: " .. table.concat(summary.crafts, ", ") .. more .. ".", color=colors.muted}
    end
    head(rows, "Keeping cold")
    count(rows, "Powered fridges", summary.fridges)
    count(rows, "Powered freezers", summary.freezers)
    if fires then
        head(rows, "For a fire")
        count(rows, "Wood", summary.wood)
        count(rows, "Paper and twigs", summary.tinder)
        count(rows, "Lighters and matches", summary.starters)
    end
    head(rows, "Settings")
    toggle(window, rows, "recoveryCook")
    toggle(window, rows, "recoverySoup")
    toggle(window, rows, "recoveryRotten")
    choice(window, rows, "cookTraining")
    choice(window, rows, "dietGoal")
    return rows
end

function Views.settings(window)
    local player, rows = window.player, {}
    head(rows, "Training")
    choice(window, rows, "cyclePolicy")
    for _, group in ipairs(Options.minimumGroups()) do
        rows[#rows + 1] = {kind="setting", label=group.label, value=group.summary, menu=true, tip=group.help,
            onClick=function() window:openMinimumMenu(group.id) end}
    end
    head(rows, "Care")
    local range = Preferences.range(player)
    rows[#rows + 1] = {kind="setting", label="Look for supplies", value=Views.rangeLabel(range), menu=true,
        onClick=function() window:openRangeMenu() end}
    if range == "walk" then
        rows[#rows + 1] = {kind="setting", label="Search radius", value=Options.searchRadius() .. " tiles", menu=true,
            onClick=function() window:openRadiusMenu() end}
    end
    toggle(window, rows, "practiceCare")
    head(rows, "Autopilot")
    choice(window, rows, "dietGoal")
    choice(window, rows, "recoveryAway")
    for _, id in ipairs(Options.autopilotToggles) do
        toggle(window, rows, id)
        if id == "recoveryCook" then choice(window, rows, "cookTraining") end
    end
    head(rows, "Body")
    choice(window, rows, "foodHover")
    head(rows, "Window and menu")
    rows[#rows + 1] = {kind="setting", label="Open and close key", value=window.capturing and (window.keyTaken and (window.keyTaken .. " is in use. Try another") or "Press a key, Esc to cancel")
        or Options.windowKeyLabel(),
        valueColor=window.capturing and colors.warn or nil, onClick=function() window:beginCapture() end,
        tip="Right click menus keep working without a key."}
    toggle(window, rows, "defaultWindowKey")
    toggle(window, rows, "generalContextMenu")
    head(rows, "Diagnostics")
    choice(window, rows, "logLevel")
    return rows
end

local glanceTones = {good=colors.good, warn=colors.warn, bad=colors.bad, muted=colors.muted}

-- The Body tab: what is coming up across every card, then each card.
function Views.body(window)
    local player, rows = window.player, {}
    local collected = Views.collect(window)
    if #collected == 0 then
        rows[#rows + 1] = {kind="text", text="Nothing to show for this survivor yet.", color=colors.muted}
        return rows
    end
    -- A card in danger (bleeding) comes before anything else, the timeline included.
    local urgent, calm = {}, {}
    for _, entry in ipairs(collected) do
        local list = entry.pill and entry.pill.urgent and urgent or calm
        list[#list + 1] = entry
    end
    local function cards(list)
        for _, entry in ipairs(list) do
            local card, pill = entry.card, entry.pill
            -- Something dangerous never stays folded away.
            local folded = Preferences.folded(player, card.id) and not (pill and pill.urgent)
            rows[#rows + 1] = {kind="card", title=card.title, collapsed=folded,
                pill=pill and {text=pill.text, color=glanceTones[pill.tone] or colors.muted},
                color=pill and glanceTones[pill.tone] or colors.muted, label=card.id,
                onClick=function() Preferences.setFolded(player, card.id, not folded); window:invalidate(true) end}
            if not folded and card.rows then
                local ok, err = pcall(card.rows, window, entry.model, rows)
                if not ok then Log.detail(player, "ui.card", "card", card.id, "part", "rows", "error", tostring(err)) end
            end
            gap(rows, 8)
        end
    end
    cards(urgent)
    local events = Dashboard.timeline(collected, 24 * 60)
    if #events > 0 then
        head(rows, "Coming up", "next 24 in-game hours")
        local all = {}
        for index, event in ipairs(events) do
            all[#all + 1] = Clock.game(event.minutes) .. ": " .. event.text
            if index <= 5 then
                rows[#rows + 1] = {kind="event", text=event.text, right=Clock.column(event.minutes),
                    color=glanceTones[event.tone] or colors.muted, tip="In " .. Clock.both(event.minutes) .. " at normal speed."}
            end
        end
        if #events > 5 then
            rows[#rows + 1] = {kind="text", text="And " .. (#events - 5) .. " more.", color=colors.faint,
                tip=table.concat(all, " <LINE> ")}
        end
        gap(rows, 6)
    end
    cards(calm)
    return rows
end

-- What the cards have to say, read once per refresh (the window clears it)
-- for every part of the view that asks.
function Views.collect(window)
    if not window.collected then window.collected = Dashboard.collect(window.player, window) end
    return window.collected
end

-- The Now tab's line per card that has something worth knowing.
-- urgent: true for the lines that go first (a wound bleeding), false for the rest.
local function glances(rows, window, urgent)
    local list = {}
    for _, entry in ipairs(Views.collect(window)) do
        if entry.glance and (entry.glance.urgent == true) == urgent then list[#list + 1] = entry end
    end
    if #list == 0 then return end
    if not urgent then gap(rows, 4); head(rows, "Body") end
    for _, entry in ipairs(list) do
        local g = entry.glance
        local buttons = {{text="Open", color=colors.muted, tip="See it in the Body tab.",
            onClick=function() window.focusCard = entry.card.id; window:show("body") end}}
        -- Something to do about it, right here (stop the bleeding).
        if g.action then table.insert(buttons, 1, {text=g.action.text, color=glanceTones[g.tone], tip=g.action.tip,
            disabled=g.action.disabled, onClick=g.action.onClick}) end
        rows[#rows + 1] = {kind="wound", title=g.text, color=glanceTones[g.tone], buttons=buttons}
    end
    if urgent then gap(rows, 4) end
end
Views.glances = glances

Views.order = {
    {id="now", title="Now"}, {id="body", title="Body"}, {id="supplies", title="Supplies"}, {id="kitchen", title="Kitchen"}, {id="log", title="Log"},
    {id="guide", title="Guide"}, {id="settings", title="Settings"},
}

-- A report a player can paste: what it is, what it is doing, what it did.
function Views.report(player, status)
    local Snap = require "AutoMindful/Snapshot"
    local lines = {"Second Nature report", "mode=" .. tostring(status.mode) .. " active=" .. tostring(status.active)
        .. " phase=" .. tostring(status.phase) .. " message=" .. tostring(status.message), Snap.player(player)}
    for _, entry in ipairs(Controller.recentDecisions(player)) do
        lines[#lines + 1] = (entry.clock or "") .. " " .. entry.label .. (entry.reason and (" - " .. entry.reason) or "")
            .. (entry.message and (" - " .. entry.message) or "")
    end
    for _, line in ipairs(Log.recent(player, 80)) do lines[#lines + 1] = line end
    return table.concat(lines, "\n")
end

return Views
