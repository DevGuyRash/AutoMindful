-- Is someone at the controls? Recovery helps differently while you work, while
-- you pause for a moment, and while you are away for hours. Nothing here acts;
-- it only says how long the survivor has been left alone.
local Options = require "AutoMindful/Options"

local Presence = {}
local seen = {}

-- Milliseconds the survivor must have been left alone before each kind of help
-- may take over their body. Supplies at hand and dying needs are not listed:
-- those never wait.
Presence.policy = {
    posture = 10000,    -- sit down, read, practise for relief, wash
    topUp = 10000,      -- preventive bites and sips within reach
    pressing = 5000,    -- walk for a second moodle
    due = 15000,        -- walk for a first moodle
    early = 30000,      -- walk for a need the game does not show yet
    explore = 30000,    -- look into containers nobody has opened
    sleep = 60000,
}

local function entry(player)
    local e = seen[player]
    if not e then e = {}; seen[player] = e end
    return e
end

function Presence.touch(player, now)
    local e = entry(player)
    e.input = now
    e.pinned = nil
end

-- Reads only. The mouse and keyboard belong to the first player; everyone's
-- movement and aim come from the survivor.
function Presence.observe(player, now)
    local e = entry(player)
    if not e.input then e.input = now end
    if player:pressedMovement(true) or player:isAiming() or player:isAttacking() then
        e.input, e.pinned = now, nil
        return
    end
    if player:getPlayerNum() ~= 0 or not getMouseX then return end
    local x, y = getMouseX(), getMouseY()
    local clicked = isMouseButtonDown and (isMouseButtonDown(0) or isMouseButtonDown(1))
    if x ~= e.x or y ~= e.y or clicked then
        e.x, e.y, e.input = x, y, now
    end
end

function Presence.key(now)
    local player = getSpecificPlayer and getSpecificPlayer(0)
    if player then Presence.touch(player, now) end
end

function Presence.aloneMs(player, now)
    local e = entry(player)
    local input = e.input or now
    if now < input then e.input, input = now, now end
    return now - input
end

-- "I am going AFK" counts from the click, whatever the mouse does afterwards.
-- A key, a step or an aim takes it back.
function Presence.pin(player, away)
    entry(player).pinned = away or nil
end

function Presence.pinned(player) return entry(player).pinned == true end

function Presence.away(player, now)
    return Presence.pinned(player) or Presence.aloneMs(player, now) >= Options.awayMs()
end

function Presence.forget(player) seen[player] = nil end

return Presence
