-- Says so, out loud, when Recovery cannot keep the survivor safe by itself.
-- One problem is announced once, again after a while if it is still there, and
-- never again once it is over.
local HUD = require "AutoMindful/CompletionHUD"
local Log = require "AutoMindful/Log"
local Options = require "AutoMindful/Options"
local Theme = require "AutoMindful/Theme"

local Alerts = {}
local active = {}
local firstRepeatMs, repeatLimitMs, sameTroubleMs = 120000, 900000, 600000

function Alerts.raise(player, id, text, now, audible)
    local mine = active[player] or {}
    active[player] = mine
    local alert = mine[id]
    -- Trouble that comes and goes is one trouble, not a new one each time.
    if alert and alert.over and now - alert.over > sameTroubleMs then alert = nil end
    if alert then alert.text, alert.over = text, nil end
    if alert and now >= alert.at and now < alert.nextAt then return false end
    local count = alert and alert.count + 1 or 1
    mine[id] = {text=text, at=now, since=alert and alert.since or now, count=count,
        nextAt=now + math.min(repeatLimitMs, firstRepeatMs * 2 ^ (count - 1))}
    Log.headline(player, "alert", "id", id, "text", text, "count", count, "audible", audible == true)
    Alerts.notice(player, "Autopilot needs you", text)
    if HaloTextHelper and HaloTextHelper.addBadText then pcall(HaloTextHelper.addBadText, player, text) end
    if audible and Options.alertSound() then
        -- Interface sound: the player hears it, the world does not.
        pcall(function() getSoundManager():playUISound("ZombieSurprisedPlayer") end)
    end
    return true
end

-- A short card that needs no session. The HUD is shared with another mod, so
-- every card carries its own brand.
function Alerts.notice(player, title, detail)
    HUD.show(player:getPlayerNum(), {brand=Theme.brandMark, theme="mindful", status="stopped", title=title, detail=detail})
end

function Alerts.clear(player, id)
    local mine = active[player]
    if mine and mine[id] and not mine[id].over then
        mine[id].over = getTimestampMs()
        Log.event(player, "alert.over", "id", id, "lastedS", math.floor((mine[id].over - mine[id].since) / 1000))
    end
end

function Alerts.list(player)
    local result = {}
    for id, alert in pairs(active[player] or {}) do
        if not alert.over then result[#result + 1] = {id=id, text=alert.text, since=alert.since} end
    end
    table.sort(result, function(a, b) return a.since < b.since end)
    return result
end

function Alerts.forget(player) active[player] = nil end

return Alerts
