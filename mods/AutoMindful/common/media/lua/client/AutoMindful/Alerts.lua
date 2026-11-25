-- Says so, out loud, when Recovery cannot keep the survivor safe by itself.
-- One problem is announced once, again after a while if it is still there, and
-- never again once it is over.
local HUD = require "AutoMindful/CompletionHUD"
local Log = require "AutoMindful/Log"
local Options = require "AutoMindful/Options"

local Alerts = {}
local active = {}
local firstRepeatMs, repeatLimitMs = 120000, 900000

function Alerts.raise(player, id, text, now, audible)
    local mine = active[player] or {}
    active[player] = mine
    local alert = mine[id]
    if alert and alert.text ~= text then alert.text = text end
    if alert and now >= alert.at and now < alert.nextAt then alert.seen = now; return false end
    local count = alert and alert.count + 1 or 1
    mine[id] = {text=text, at=now, seen=now, since=alert and alert.since or now, count=count,
        nextAt=now + math.min(repeatLimitMs, firstRepeatMs * 2 ^ (count - 1))}
    Log.headline(player, "alert", "id", id, "text", text, "count", count, "audible", audible == true)
    HUD.show(player:getPlayerNum(), {title="Recovery needs you", detail=text})
    if HaloTextHelper and HaloTextHelper.addBadText then pcall(HaloTextHelper.addBadText, player, text) end
    if audible and Options.alertSound() then
        -- Interface sound: the player hears it, the world does not.
        pcall(function() getSoundManager():playUISound("ZombieSurprisedPlayer") end)
    end
    return true
end

function Alerts.clear(player, id)
    local mine = active[player]
    if mine and mine[id] then
        Log.event(player, "alert.over", "id", id, "lastedS", math.floor((getTimestampMs() - mine[id].since) / 1000))
        mine[id] = nil
    end
end

function Alerts.list(player)
    local result = {}
    for id, alert in pairs(active[player] or {}) do result[#result + 1] = {id=id, text=alert.text, since=alert.since} end
    table.sort(result, function(a, b) return a.since < b.since end)
    return result
end

function Alerts.forget(player) active[player] = nil end

return Alerts
