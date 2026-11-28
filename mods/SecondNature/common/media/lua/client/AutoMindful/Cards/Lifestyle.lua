-- The Lifestyle card: Zen and Mindfulness while they last, each with the
-- time its tier has left as a bar that runs from green to dark red, and a
-- way to practise for more.
local Clock = require "AutoMindful/Clock"
local Theme = require "AutoMindful/Theme"
local ZenMoodle = require "AutoMindful/ZenMoodle"
local colors = Theme.colors

local Card = {id = "lifestyle", title = "Zen and Mindfulness", order = 30}
local names = {Zen = {"Zen I", "Zen II", "Zen III", "Zen IV"}}

function Card.read(player)
    local model = {}
    for _, name in ipairs({"Zen", "MindfulState"}) do
        local rows, timer = ZenMoodle.countdown(player, name)
        if timer then model[#model + 1] = {name = name, timer = timer, label = name == "Zen" and names.Zen[timer.tier] or timer.name} end
    end
    return #model > 0 and model or nil
end

-- The pill says how much of the first one is left, like its bar.
function Card.pill(m)
    local t = m[1].timer
    local fraction = t.left / math.max(1, t.span)
    return {text = m[1].label, tone = fraction > 0.5 and "good" or fraction > 0.2 and "warn" or "bad"}
end

function Card.events(m)
    local list = {}
    for _, entry in ipairs(m) do
        list[#list + 1] = {text = entry.label .. (entry.timer.next > 0 and " fades a tier" or " ends"), minutes = entry.timer.left, tone = "muted"}
    end
    return list
end

function Card.rows(window, m, rows)
    for _, entry in ipairs(m) do
        local t = entry.timer
        local fraction = math.max(0, math.min(1, t.left / t.span))
        rows[#rows + 1] = {kind = "bar", label = entry.label, color = Theme.timeLeft(fraction), fraction = fraction,
            right = Clock.game(t.left) .. " left, " .. Clock.real(Clock.realSeconds(t.left)) .. " real"}
        if t.next > 0 then
            rows[#rows + 1] = {kind = "text", text = "Gone in " .. Clock.both(t.gone) .. ".", color = colors.faint}
        end
    end
end

return Card
