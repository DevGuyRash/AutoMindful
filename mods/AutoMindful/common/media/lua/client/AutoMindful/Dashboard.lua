-- The Body tab is a stack of cards. A feature joins it by registering one:
--   Dashboard.register{id, title, order,
--       read = function(player, window) return model or nil end,   -- nil: no card
--       pill = function(model) return {text, tone} or nil end,      -- the head's status
--       glance = function(model) return {text, tone, urgent} or nil end, -- the Now tab line
--       events = function(model) return {{text, minutes, tone}} end, -- the Coming up timeline
--       rows = function(window, model, rows) ... end}                 -- the card's body
-- Every part but read is optional. Nothing here draws; Views turns it into rows.
local Log = require "AutoMindful/Log"
local Dashboard = {cards = {}}

function Dashboard.register(card)
    for index, known in ipairs(Dashboard.cards) do
        if known.id == card.id then Dashboard.cards[index] = card; card = nil; break end
    end
    if card then Dashboard.cards[#Dashboard.cards + 1] = card end
    table.sort(Dashboard.cards, function(a, b) return (a.order or 50) < (b.order or 50) end)
end

-- One card failing to read the game must not take the tab down with it.
local function guarded(player, card, part, ...)
    local fn = card[part]
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
    Log.detail(player, "ui.card", "card", card.id, "part", part, "error", tostring(value))
end

-- What every card has to say now: {card, model, pill, glance, events}.
function Dashboard.collect(player, window)
    local out = {}
    for _, card in ipairs(Dashboard.cards) do
        local model = guarded(player, card, "read", player, window)
        if model then
            out[#out + 1] = {card = card, model = model, pill = guarded(player, card, "pill", model),
                glance = guarded(player, card, "glance", model), events = guarded(player, card, "events", model) or {}}
        end
    end
    return out
end

-- Every card's coming events, soonest first, within `minutes` (in-game).
function Dashboard.timeline(collected, minutes)
    local list = {}
    for _, entry in ipairs(collected) do
        for _, event in ipairs(entry.events) do
            if event.minutes and event.minutes >= 0 and (not minutes or event.minutes <= minutes) then
                list[#list + 1] = {text = event.text, minutes = event.minutes, tone = event.tone, card = entry.card.id}
            end
        end
    end
    table.sort(list, function(a, b) return a.minutes < b.minutes end)
    return list
end

Dashboard.guarded = guarded
return Dashboard
