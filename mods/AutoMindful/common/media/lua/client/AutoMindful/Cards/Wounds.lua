-- The Wounds card: each hurt part, most dangerous first, every condition in
-- its colour, what comes next for it, and one click to see it through.
local Clock = require "AutoMindful/Clock"
local Controller = require "AutoMindful/Controller"
local Options = require "AutoMindful/Options"
local Theme = require "AutoMindful/Theme"
local Treat = require "AutoMindful/Treat"
local Wounds = require "AutoMindful/Wounds"
local colors = Theme.colors

local Card = {id = "wounds", title = "Wounds", order = 10}
local tones = {good = colors.good, warn = colors.warn, bad = colors.bad, muted = colors.muted}

function Card.read(player, window)
    local list = Wounds.read(player)
    if #list == 0 then return nil end
    -- Elsewhere than the Body tab only the first wound's plan is shown (its Treat button).
    local all = not window or window.view == "body"
    local model = {player = player, list = list}
    model.care, model.worst = Wounds.summary(list)
    model.allowed, model.why = Treat.allowed(player)
    model.health = math.floor((player:getBodyDamage():getOverallBodyHealth() or 100) + 0.5)
    model.bleeding = player:getBodyDamage():getNumPartsBleeding()
    -- What the First aid job (or the running job) is seeing to now.
    local status = Controller.status(player)
    local focus = status.active and status.aidFocus
    model.treating = focus and function(part) return focus.parts == nil or focus.parts[part] == true end or nil
    for index, wound in ipairs(list) do
        if wound.danger > 0 and (all or index == 1) then wound.plan = Treat.plan(player, wound.part) end
    end
    return model
end

function Card.pill(m)
    if m.care == 0 then return {text = "Healing", tone = "good"} end
    return {text = m.care .. (m.care == 1 and " needs care" or " need care"), tone = m.worst, urgent = m.worst == "bad"}
end

function Card.glance(m)
    local first = m.list[1]
    if m.care == 0 then return nil end
    local bleeding = first.part:bleeding() and not first.part:bandaged()
    local player = m.player
    local action = first.plan and first.plan.count > 0 and {text = "Treat", disabled = not m.allowed, tip = m.allowed and Treat.tip(first.plan) or m.why,
        onClick = function()
            if m.care > 1 and not bleeding then Treat.request(player, nil) else Treat.request(player, first.part) end
        end}
    if action and m.care > 1 and not bleeding then action.text = "Treat all" end
    return {text = bleeding and ("Bleeding: " .. first.name) or (m.care .. (m.care == 1 and " wound needs care" or " wounds need care")),
        tone = bleeding and "bad" or m.worst, urgent = bleeding, action = action}
end

function Card.events(m)
    local list = {}
    for _, wound in ipairs(m.list) do
        if wound.dirtyIn then list[#list + 1] = {text = "Dressing on the " .. wound.name:lower() .. " soaks through", minutes = wound.dirtyIn, tone = "warn"} end
        if wound.heal then list[#list + 1] = {text = wound.name .. " heals", minutes = wound.heal, tone = "good"} end
    end
    return list
end

-- What comes next for a part, in one line.
local function nextLine(wound)
    local plan = wound.plan
    if wound.treating then return "Being seen to now.", colors.recovery end
    if plan and #plan.steps > 0 then
        local text = "Next: " .. plan.steps[1]
        if #plan.steps > 1 then text = text .. ", then " .. (#plan.steps - 1) .. " more" end
        return text, colors.muted
    end
    if plan and #plan.missing > 0 then return "Needs " .. plan.missing[1] .. ", none nearby.", colors.warn end
    local parts = {}
    if wound.heal then parts[#parts + 1] = "heals in about " .. Clock.game(wound.heal) end
    if wound.dirtyIn then parts[#parts + 1] = "dressing soaks through in about " .. Clock.game(wound.dirtyIn) end
    if #parts == 0 then return wound.danger > 0 and "Nothing to do for it right now." or "Healing.", wound.danger > 0 and colors.muted or colors.good end
    return (table.concat(parts, "; "):gsub("^%l", string.upper)) .. ".", colors.good
end

local function dressingMenu(window, player, wound)
    local menu = window:menu()
    local current = Treat.dressingName(wound.part)
    if current then menu:addOption("On it now: " .. current .. (wound.part:isBandageDirty() and ", dirty" or "")) end
    local choices = Treat.dressings(player)
    if #choices == 0 then
        local option = menu:addOption("No clean dressing within reach")
        if option then option.notAvailable = true end
        return
    end
    for index, choice in ipairs(choices) do
        menu:addOption((wound.covered and "Replace with " or "Dress with ") .. choice.name .. ", " .. choice.where .. (index == 1 and ", best" or ""), player,
            function() Treat.request(player, wound.part, {change = true, prefer = choice.item}) end)
    end
end

function Card.rows(window, m, rows)
    local player = window.player
    -- The whole body first, as the game's own panel rates it.
    if m.health then
        local healthTone = m.health < 40 and colors.bad or m.health < 75 and colors.warn or colors.good
        local bleeding = m.bleeding or 0
        local summary = "Health " .. m.health .. "%"
        if bleeding > 0 then summary = summary .. ", bleeding from " .. bleeding .. (bleeding == 1 and " part" or " parts") end
        rows[#rows + 1] = {kind = "text", text = summary .. ".", color = bleeding > 0 and colors.bad or healthTone}
    end
    if not m.allowed then rows[#rows + 1] = {kind = "text", text = m.why, color = colors.bad}
    elseif m.why then rows[#rows + 1] = {kind = "text", text = m.why, color = colors.warn} end
    local treatable, tips = 0, {}
    for _, wound in ipairs(m.list) do
        local plan = wound.plan
        wound.treating = m.treating and m.treating(wound.part) and plan and plan.count > 0
        local tags = {}
        for _, tag in ipairs(wound.tags) do tags[#tags + 1] = {text = tag.text, color = tones[tag.tone]} end
        local sub, subColor = nextLine(wound)
        local buttons = {}
        -- A part with something still to do is never shown as cared for.
        local tone = wound.tone
        if plan and plan.count > 0 and tone == "good" then tone = "warn" end
        if plan and plan.count > 0 then
            treatable = treatable + 1
            local bleeder = Treat.bleedingElsewhere(player, wound.part)
            local tip = Treat.tip(plan, bleeder and "Any wound that is bleeding is dressed first." or nil)
            tips[#tips + 1] = wound.name .. ": " .. Treat.cost(plan)
            buttons[#buttons + 1] = {text = wound.treating and "Treating" or "Treat", color = tones[tone] or colors.recovery,
                disabled = not m.allowed or wound.treating, tip = tip, onClick = function() Treat.request(player, wound.part) end}
        end
        if wound.covered or (plan and plan.count > 0) then
            -- Quiet until it matters: shown on hover unless the dressing is dirty or soaking through.
            local due = wound.covered and (wound.part:isBandageDirty() or (wound.dirtyIn and wound.dirtyIn < 180))
            buttons[#buttons + 1] = {text = "Dressing", menu = true, color = colors.muted, disabled = not m.allowed,
                hoverOnly = not due and not (plan and plan.count > 0),
                tip = wound.covered and "Choose a fresh dressing for this part." or "Choose what to dress it with.",
                onClick = function() dressingMenu(window, player, wound) end}
        end
        local detail = {}
        if plan then
            local cost = Treat.cost(plan)
            if cost then detail[#detail + 1] = cost .. "." end
            if #plan.missing > 0 then detail[#detail + 1] = "Not found nearby: " .. table.concat(plan.missing, "; ") .. "." end
        end
        if wound.heal then detail[#detail + 1] = "Heals in about " .. Clock.both(wound.heal) .. " at this rate." end
        if wound.dirtyIn then detail[#detail + 1] = "The dressing soaks through in about " .. Clock.both(wound.dirtyIn) .. "." end
        rows[#rows + 1] = {kind = "wound", title = wound.name, tags = tags, sub = sub, subColor = subColor,
            color = tones[tone], buttons = buttons, tip = #detail > 0 and table.concat(detail, " <LINE> ") or nil}
    end
    if treatable > 1 then
        rows[#rows + 1] = {kind = "buttons", buttons = {{text = "Treat all " .. treatable, color = colors.bad, disabled = not m.allowed,
            tip = "Every wound in turn, most dangerous first: <LINE> " .. table.concat(tips, " <LINE> "),
            onClick = function() Treat.request(player, nil) end}}}
    end
    local option, text = Options.option("recoveryFirstAid"), Options.windowText.recoveryFirstAid
    rows[#rows + 1] = {kind = "setting", label = "Autopilot treats wounds by itself", tip = text and text[2], toggle = option:getValue() == true,
        onClick = function() Options.set("recoveryFirstAid", option:getValue() ~= true); window:invalidate() end}
end

return Card
