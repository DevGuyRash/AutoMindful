-- Moodle tier countdowns against Lifestyle's own decay (LSPerTenMinutes,
-- doMindfulnessDuration) and the sandbox day length, worked by hand: every
-- expected number below comes from those rules, not from the code.
package.path = "mods/SecondNature/common/media/lua/client/?.lua;" .. package.path
local function near(a, b, tolerance) return math.abs(a - b) <= (tolerance or 1e-6) end

local now, minutesPerDay, timeOfDay = 1000, 90, 9.5
function getTimestampMs() return now end
function getGameTime()
    return {getMinutesPerDay = function() return minutesPerDay end, getTimeOfDay = function() return timeOfDay end,
        getWorldAgeHours = function() return 100 end}
end
CharacterTrait = {DISCIPLINED = "disciplined"}
UIFont = {Small = 1, Medium = 2, Large = 3}
function getTextManager()
    return {getFontHeight = function() return 16 end, MeasureStringX = function(_, _, text) return #tostring(text) * 7 end}
end
local Clock = require "AutoMindful/Clock"

-- --------------------------------------------------------------- the clock
do
    -- A 90 real-minute day: an in-game hour is 3.75 real minutes.
    assert(Clock.dayMinutes() == 90 and near(Clock.realSeconds(60), 225))
    assert(Clock.game(45) == "45 min" and Clock.game(125) == "2 h 5 min" and Clock.game(1500) == "1 d 1 h" and Clock.game(1440) == "1 d")
    assert(Clock.real(40) == "40 s" and Clock.real(3725) == "1 h 2 min" and Clock.real(600) == "10 min")
    assert(Clock.column(60) == "1 h, 4 min real", Clock.column(60))
    -- 09:30 in game: Lifestyle's next ten-minute tick is at 09:40.
    assert(near(Clock.untilTick(10), 10)); timeOfDay = 9 + 37 / 60; assert(near(Clock.untilTick(10), 3))
    minutesPerDay = 0; assert(Clock.dayMinutes() == 60, "a broken setting falls back to the default hour"); minutesPerDay = 90
end
print("PASS game time turns into real time from the day length")

-- ----------------------------------------------------------- Zen, Mindfulness
function getModInfoByID() return {getModVersion = function() return "0.4.0.3" end} end
SandboxVars = {Text = {DividerMeditationNew = true}, Meditation = {MindfulnessDuration = 2}}
Perks = {Meditation = "meditation"}
local Info = require "AutoMindful/WellnessInfo"
local data = {LSMoodles = {Zen = {Value = 1}, MindfulState = {Value = 0}}}
local rank, disciplined = 6, false
local survivor = {hasModData = function() return true end, getModData = function() return data end,
    getPerkLevel = function() return rank end, hasTrait = function(_, trait) return trait == "disciplined" and disciplined end}
do
    -- Lifestyle: -0.02 every ten minutes, gone below 0.2; HUD tiers at
    -- 0.15/0.3/0.5/0.7. From each Yoga strength (Value 0.25 x efficiency)
    -- the ticks to the first drop and to the end are 3/3, 1/15, 3/28, 15/40.
    for _, case in ipairs({{1, 4, 15, 40}, {0.75, 4, 3, 28}, {0.5, 3, 1, 15}, {0.25, 1, 3, 3}}) do
        data.LSMoodles.Zen.Value = case[1]
        local t = Info.zenCountdown(survivor, 10)
        assert(t.tier == case[2] and t.left == case[3] * 10 and t.gone == case[4] * 10,
            case[1] .. ": " .. t.tier .. " " .. t.left .. " " .. t.gone)
        assert(t.left <= t.span, "a tier never has more left than it lasts")
    end
    data.LSMoodles.Zen.Value = 0.5
    assert(Info.zenCountdown(survivor, 4).left == 4, "the first tick comes when the clock says")
    data.LSMoodles.Zen.Value = 0
    assert(Info.zenCountdown(survivor, 10) == nil)
end
print("PASS Zen counts down tick by tick as Lifestyle decays it")

do
    -- Strong Mindfulness (Value 0.45) with 25 minutes on the counter: it drops
    -- the minute after the counter reaches 0, so 26 minutes; then Mindfulness
    -- lasts the full duration: 30 minutes at rank 6, x1 at the default setting.
    data.LSMoodles.MindfulState.Value, data.MindfulnessMinutes = 0.45, 25
    local t = Info.mindfulnessCountdown(survivor, 0)
    assert(t.tier == 2 and t.left == 26 and t.gone == 56 and t.next == 1, t.tier .. " " .. t.left .. " " .. t.gone)
    disciplined = true
    assert(Info.mindfulnessCountdown(survivor, 0.5).gone == 25.5 + 60, "Disciplined doubles it at rank 6")
    data.MindfulnessMinutes = false
    assert(Info.mindfulnessCountdown(survivor, 0) == nil, "no countdown until Lifestyle starts one")
end
print("PASS Mindfulness counts down a minute at a time, then a tier at a time")

do
    local Theme = require "AutoMindful/Theme"
    local full, empty, half = Theme.timeLeft(1), Theme.timeLeft(0), Theme.timeLeft(0.5)
    assert(full.g > full.r and full.g > 0.7, "strong green when fresh")
    assert(empty.r > empty.g * 3 and empty.r < 0.7, "dark red when nearly gone")
    assert(half.r > 0.8 and half.g > 0.6, "amber halfway")
end
print("PASS time left runs from strong green to dark red")
print("Countdowns PASS")
