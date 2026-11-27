-- Game time in the player's own time. The sandbox day length makes an
-- in-game hour a real minute or several; this is the one place that knows.
-- Reads only. Real times are at normal speed: fast-forward and sleep shorten them.
local Clock = {}

local function real(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end

local function clock() return getGameTime and getGameTime() or nil end

-- Real minutes one in-game day takes at normal speed (the sandbox Day Length).
function Clock.dayMinutes()
    local ok, minutes = pcall(function() return clock():getMinutesPerDay() end)
    return ok and real(minutes) and minutes > 0 and minutes or 60
end

-- Real seconds for a span of in-game minutes.
function Clock.realSeconds(gameMinutes) return gameMinutes * Clock.dayMinutes() * 60 / 1440 end

-- In-game minutes since midnight, with the fraction of the current minute.
function Clock.minuteOfDay()
    local ok, hours = pcall(function() return clock():getTimeOfDay() end)
    if ok and real(hours) then return hours * 60 end
end

-- In-game hours since the world began, for rates measured over time.
function Clock.worldHours()
    local ok, hours = pcall(function() return clock():getWorldAgeHours() end)
    if ok and real(hours) then return hours end
end

-- In-game minutes until the game's next tick of every `period` minutes.
function Clock.untilTick(period)
    local minute = Clock.minuteOfDay()
    if not minute then return period end
    local left = period - minute % period
    return left > 0 and left or period
end

local function plural(count, word) return count .. " " .. word end

-- "3 d 4 h", "5 h 20 min", "12 min": an in-game span, two units at most.
function Clock.game(minutes)
    minutes = math.max(0, math.floor((minutes or 0) + 0.5))
    if minutes < 60 then return plural(minutes, "min") end
    local hours = math.floor(minutes / 60)
    if hours < 24 then
        local rest = minutes % 60
        return hours .. " h" .. (rest > 0 and (" " .. rest .. " min") or "")
    end
    local days, rest = math.floor(hours / 24), hours % 24
    return days .. " d" .. (rest > 0 and (" " .. rest .. " h") or "")
end

-- "40 s", "12 min", "1 h 5 min": a real span, two units at most.
function Clock.real(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    if seconds < 60 then return seconds .. " s" end
    local minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 60 then return minutes .. " min" end
    local hours, rest = math.floor(minutes / 60), minutes % 60
    if hours < 24 then return hours .. " h" .. (rest > 0 and (" " .. rest .. " min") or "") end
    return math.floor(hours / 24) .. " d " .. hours % 24 .. " h"
end

-- Short, for a column: "5 h 20 min, 13 min real".
function Clock.column(minutes)
    return Clock.game(minutes) .. ", " .. Clock.real(Clock.realSeconds(minutes)) .. " real"
end

-- An in-game span and what it is in real time: "5 h 20 min, 13 min real".
function Clock.both(minutes)
    return Clock.game(minutes) .. ", " .. Clock.real(Clock.realSeconds(minutes)) .. " real"
end

return Clock
