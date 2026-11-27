-- The Nutrition card: weight and where it is heading, in one sentence first,
-- then the calorie balance and the three macros, and the details on demand.
-- Colours are relative to the diet goal: green moves toward it, amber away.
local Clock = require "AutoMindful/Clock"
local Diet = require "AutoMindful/Diet"
local Nutrition = require "AutoMindful/Nutrition"
local Options = require "AutoMindful/Options"
local Theme = require "AutoMindful/Theme"
local colors = Theme.colors

local Card = {id = "nutrition", title = "Nutrition", order = 20}
local tones = {good = colors.good, warn = colors.warn, bad = colors.bad, muted = colors.muted}

local cache = setmetatable({}, {__mode = "k"})
local projectMs, horizonDays = 2000, 60

-- The projection is a few thousand steps: once every two seconds is plenty.
local function project(player, s)
    local now = getTimestampMs()
    local seen = cache[player]
    if seen and now >= seen.at and now - seen.at < projectMs then return seen.events, seen.week end
    local events, week = Nutrition.project(s, horizonDays)
    cache[player] = {at = now, events = events, week = week}
    return events, week
end

-- Which way the goal wants calories to go: 1 up, -1 down, 0 hold.
local function direction(goal) return goal == "more" and 1 or goal == "fewer" and -1 or 0 end

function Card.read(player)
    local s = Nutrition.read(player)
    if not s then return nil end
    s.events, s.week = project(player, s)
    s.goal = Diet.goal(player)
    s.setGoal = Options.dietGoal and Options.dietGoal() or "auto"
    local hover = AutoMindful and AutoMindful.FoodHover and AutoMindful.FoodHover.recent(player)
    s.hover = hover
    return s
end

local function trendText(s)
    if s.perDay == 0 then return "Steady" end
    return string.format("%s%.2f kg/day", s.perDay > 0 and "+" or "-", math.abs(s.perDay))
end

-- Toward the goal is good; away is a warning; holding is neutral.
local function trendTone(s)
    local want = direction(s.goal)
    if s.perDay == 0 then return want == 0 and colors.good or colors.muted end
    local moving = s.perDay > 0 and 1 or -1
    if want == 0 then return s.band.tone == "good" and colors.muted or ((s.weight < 80) == (moving > 0) and colors.good or colors.warn) end
    return moving == want and colors.good or colors.warn
end

local function when(minutes) return Clock.game(minutes) .. ", " .. Clock.real(Clock.realSeconds(minutes)) .. " real" end

-- The one event worth leading with: a change of weight band, else the next change.
local function headline(s)
    for _, event in ipairs(s.events) do
        if event.id:find("^band") then return event end
    end
    return s.events[1]
end

function Card.pill(s) return {text = s.band.label, tone = s.band.tone} end

function Card.glance(s)
    local lead = headline(s)
    local away = trendTone(s) == colors.warn
    local soon = lead and lead.id:find("^band") and lead.minutes < 3 * 1440
    if not (soon or away or s.proteinEffect == "penalty") then return nil end
    local text = string.format("%.1f kg, %s", s.weight, trendText(s):lower())
    if soon then text = text .. "; " .. lead.text:lower() .. " in " .. Clock.game(lead.minutes) end
    return {text = text, tone = soon and "warn" or "muted"}
end

-- Starting to lose or stopping gaining is only news against the goal.
local function eventTone(s, event)
    local want = direction(s.goal)
    if event.id == "lossStarts" then return want > 0 and "warn" or want < 0 and "good" or "muted" end
    if event.id == "gainStops" then return want > 0 and "warn" or "muted" end
    return event.tone
end

function Card.events(s)
    local list = {}
    for _, event in ipairs(s.events) do
        if event.minutes <= 7 * 1440 then list[#list + 1] = {text = event.text, minutes = event.minutes, tone = eventTone(s, event)} end
    end
    return list
end

-- How much it takes: what to eat to stop losing, or what keeps it steady.
local function advice(s)
    local day = math.floor(s.restHour * 24 / 10 + 0.5) * 10
    if s.calories < s.lossLine then
        local need = math.ceil((s.lossLine - s.calories) / 10) * 10
        return string.format("About %d kcal stops the weight loss; then about %d a day at rest holds it.", need, day)
    end
    if s.calories > s.gainLine then
        local hours = (s.calories - s.gainLine) / math.max(1, s.restHour)
        return "Gaining until about " .. Clock.game(hours * 60) .. " of rest burns it back to the steady zone."
    end
    return string.format("Steady. About %d kcal a day at rest keeps it here.", day)
end

local function calorieZones(s)
    local want = direction(s.goal)
    local r = Nutrition.rules.calories
    local losing = want < 0 and colors.good or colors.warn
    local gaining = want > 0 and colors.good or colors.warn
    return {
        {from = r.low, to = s.lossLine, color = losing, label = "Losing"},
        {from = s.lossLine, to = s.gainLine, color = want == 0 and colors.good or colors.muted, label = "Steady"},
        {from = s.gainLine, to = r.high, color = gaining, label = "Gaining"},
    }
end

local function zoneColor(zones, value)
    for _, zone in ipairs(zones) do if value >= zone.from and value <= zone.to then return zone.color end end
    return colors.text
end

local function macros(s)
    local r, g, p = Nutrition.rules.macros, Nutrition.rules.gain, Nutrition.rules.protein
    local function fraction(value) return (value - r.low) / (r.high - r.low) end
    local function mark(value) return (value - r.low) / (r.high - r.low) end
    local gainingGood = direction(s.goal) > 0
    local function rich(value)
        if value > g.richer then return "Gain x3", gainingGood and colors.good or colors.warn end
        if value > g.rich then return "Gain x2", gainingGood and colors.good or colors.warn end
        return nil, colors.muted
    end
    local carbNote, carbColor = rich(s.carbs)
    local fatNote, fatColor = rich(s.fat)
    local proteinNote, proteinColor = "Below the bonus", colors.muted
    if s.proteinEffect == "bonus" then proteinNote, proteinColor = "Strength XP x1.5", colors.good
    elseif s.proteinEffect == "penalty" then proteinNote, proteinColor = "Strength XP x0.7", colors.bad
    elseif s.protein >= p.bonusTop then proteinNote = "Above the bonus" end
    local hover = s.hover and s.hover.food
    local function after(value, add) return hover and fraction(math.max(r.low, math.min(r.high, value + add))) or nil end
    return {kind = "gauges", cells = {
        {label = "Carbs", value = math.floor(s.carbs + 0.5) .. " g", fraction = fraction(s.carbs), mark = mark(g.rich),
            color = carbColor == colors.muted and colors.faint or carbColor, note = carbNote or "", noteColor = carbColor,
            ghost = after(s.carbs, hover and hover.carbs or 0)},
        {label = "Fat", value = math.floor(s.fat + 0.5) .. " g", fraction = fraction(s.fat), mark = mark(g.rich),
            color = fatColor == colors.muted and colors.faint or fatColor, note = fatNote or "", noteColor = fatColor,
            ghost = after(s.fat, hover and hover.fat or 0)},
        {label = "Protein", value = math.floor(s.protein + 0.5) .. " g", fraction = fraction(s.protein), mark = mark(p.bonus),
            color = proteinColor == colors.muted and colors.faint or proteinColor, note = proteinNote, noteColor = proteinColor,
            ghost = after(s.protein, hover and hover.protein or 0)},
    }}
end

local activityNames = {asleep = "Asleep", resting = "Resting", walking = "Walking", running = "Running", sprinting = "Sprinting"}

function Card.rows(window, s, rows)
    local lead = headline(s)
    local sub
    if lead then
        sub = lead.text .. " in " .. when(lead.minutes) .. ", at rest without food."
    else sub = "No change ahead while resting." end
    rows[#rows + 1] = {kind = "headline", big = string.format("%.1f kg", s.weight), word = s.band.label,
        wordColor = tones[s.band.tone], right = trendText(s), rightColor = trendTone(s), sub = sub}
    local zones = calorieZones(s)
    local r = Nutrition.rules.calories
    local food = s.hover and s.hover.food
    rows[#rows + 1] = {kind = "meter", label = "Calories", right = string.format("%d kcal", math.floor(s.calories + 0.5))
            .. (food and string.format("  to %d", math.floor(math.max(r.low, math.min(r.high, s.calories + food.calories)) + 0.5)) or ""),
        low = r.low, high = r.high, value = s.calories, zones = zones, color = zoneColor(zones, s.calories),
        ghost = food and math.max(r.low, math.min(r.high, s.calories + food.calories)) or nil,
        ticks = {s.lossLine, s.gainLine}}
    rows[#rows + 1] = {kind = "text", text = advice(s), color = colors.muted}
    rows[#rows + 1] = macros(s)
    local open = window.cardDetail and window.cardDetail.nutrition
    rows[#rows + 1] = {kind = "setting", label = open and "Fewer details" or "More details", value = "",
        onClick = function()
            window.cardDetail = window.cardDetail or {}
            window.cardDetail.nutrition = not open or nil
            window:invalidate(true)
        end}
    if not open then return end
    -- The weight scale, zoomed to the survivor: each band shaded, where a week resting would take it.
    local low, high = math.floor(s.weight - 15), math.ceil(s.weight + 15)
    local bandZones, from = {}, Nutrition.rules.weight.floor
    for _, band in ipairs(Nutrition.bands) do
        local to = math.min(band.upTo, 200)
        bandZones[#bandZones + 1] = {from = from, to = to, color = tones[band.tone], label = band.label}
        from = to
    end
    rows[#rows + 1] = {kind = "meter", label = "Weight", right = s.week and string.format("in 7 days at rest: %.1f kg", s.week) or nil,
        low = low, high = high, value = s.weight, ghost = s.week, zones = bandZones, color = tones[s.band.tone]}
    if #s.events > 0 then
        rows[#rows + 1] = {kind = "text", text = "At rest without food:", color = colors.faint, tight = true}
        for _, event in ipairs(s.events) do
            rows[#rows + 1] = {kind = "event", text = event.text, right = Clock.column(event.minutes),
                color = tones[eventTone(s, event)] or colors.muted, tip = "In " .. when(event.minutes) .. " at normal speed."}
        end
    end
    local facts = {}
    if s.slow then facts[#facts + 1] = "Slow metabolism: gains above " .. math.floor(s.gainLine) .. " kcal."
    elseif s.fast then facts[#facts + 1] = "Fast metabolism: gains only above " .. math.floor(s.gainLine) .. " kcal." end
    facts[#facts + 1] = string.format("%s: burns about %d kcal per in-game hour%s.", activityNames[s.activity] or "Resting",
        math.floor(s.burnHour + 0.5), s.warmth > 1.05 and string.format(" (keeping warm x%.1f)", s.warmth) or "")
    if s.fitnessBlocked then facts[#facts + 1] = "Fitness XP is blocked at this weight." end
    for _, fact in ipairs(facts) do rows[#rows + 1] = {kind = "text", bullet = true, text = fact, color = colors.muted} end
    for _, id in ipairs({"dietGoal", "foodHover"}) do
        local entry, text = Options.choice(id), Options.windowText[id]
        rows[#rows + 1] = {kind = "setting", label = text[1], value = entry.short or entry.label, menu = true,
            tip = entry.help or text[2], onClick = function() window:openChoiceMenu(id) end}
    end
end

return Card
