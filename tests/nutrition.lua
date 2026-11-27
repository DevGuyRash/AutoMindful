-- The Nutrition card's readings against the game's own rules, worked by
-- hand from B42's Nutrition (calorie lines, weight rates, macro decay):
-- every expected number below comes from those rules, not from the code.
package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
package.loaded["PZAPI/ModOptions"] = true
for _, name in ipairs({"ISApplyBandage", "ISRemoveGlass", "ISRemoveBullet", "ISDisinfect", "ISStitch", "ISSplint",
        "ISCleanBurn", "ISComfreyCataplasm", "ISGarlicCataplasm", "ISPlantainCataplasm"}) do
    package.loaded["TimedActions/" .. name] = true
end
local function near(a, b, tolerance) return math.abs(a - b) <= (tolerance or 1e-6) end

local now, minutesPerDay, timeOfDay = 1000, 90, 9.5
function getTimestampMs() return now end
function getGameTime()
    return {getMinutesPerDay = function() return minutesPerDay end, getTimeOfDay = function() return timeOfDay end,
        getWorldAgeHours = function() return 100 end}
end
function instanceof(value, kind) return type(value) == "table" and value.kind == kind end
CharacterTrait = {WEIGHT_GAIN = "slow", WEIGHT_LOSS = "fast", DISCIPLINED = "disciplined", NUTRITIONIST = "nutritionist",
    NUTRITIONIST2 = "nutritionist2", ILLITERATE = "illiterate"}
UIFont = {Small = 1, Medium = 2, Large = 3}
function getTextManager()
    return {getFontHeight = function() return 16 end, MeasureStringX = function(_, _, text) return #tostring(text) * 7 end}
end

local Nutrition = require "AutoMindful/Nutrition"
local Clock = require "AutoMindful/Clock"

-- ------------------------------------------------------------- the lines
do
    -- T = 1000 (+40 per kg over 80); 700 with Slow Metabolism under 90 kg,
    -- 1800 with Fast over 70 kg. L = (weight - 70) x 30, never above 0.
    local gain, loss = Nutrition.lines(80, false, false)
    assert(gain == 1000 and loss == 0, gain .. " " .. loss)
    gain, loss = Nutrition.lines(60, false, false)
    assert(gain == 200 and loss == -300, gain .. " " .. loss)
    assert(Nutrition.lines(80, true, false) == 700 and Nutrition.lines(95, true, false) == 1600)
    assert(Nutrition.lines(80, false, true) == 1800 and Nutrition.lines(65, false, true) == 400)
end
print("PASS the calorie lines move with weight and metabolism as the game's do")

do
    -- Gaining at 1800 kcal with 500 g carbs: 1.3e-5 x2 x (1800/4000) kg/s =
    -- 1.01088 kg a day. Losing at the -2200 floor: 8.5e-6 x 0.88 = 0.646272.
    local rate, boost = Nutrition.rate(80, 1800, 500, 100, false, false)
    assert(boost == 2 and near(rate * 86400, 1.01088), rate * 86400)
    rate, boost = Nutrition.rate(80, 1800, 750, 0, false, false)
    assert(boost == 3 and near(rate * 86400, 1.51632))
    assert(near(Nutrition.rate(80, -2200, 0, 0) * 86400, -0.646272))
    assert(Nutrition.rate(80, 500, 0, 0) == 0, "between the lines it holds")
end
print("PASS weight rises and falls at the game's own rates")

do
    -- Weight bands: Obese from 100, Overweight from 85, Underweight up to 75,
    -- Very Underweight up to 65, Emaciated up to 50 (applyTraitFromWeight).
    local function band(w) return Nutrition.band(w).id end
    assert(band(100) == "obese" and band(99.9) == "overweight" and band(85) == "overweight" and band(84.9) == "healthy")
    assert(band(75.1) == "healthy" and band(75) == "underweight" and band(65.1) == "underweight" and band(65) == "veryUnderweight")
    assert(band(50.1) == "veryUnderweight" and band(50) == "emaciated")
end
print("PASS weight bands sit where the game swaps the traits")

do
    -- Resting from 80 kg, 1800 kcal, 500 g carbs, 100 g fat, 120 g protein,
    -- burning 0.016 kcal/s (57.6 an hour): carbs fall 12.6 g/h, so they reach
    -- 400 after 7.94 h; protein 3.096 g/h reaches 50 after 22.6 h; calories
    -- cross 1000 after about 13.9 h and 0 after 31.25 h. Ten-minute steps.
    local s = {weight = 80, calories = 1800, carbs = 500, fat = 100, protein = 120, warmth = 1, proteinEffect = "bonus"}
    s.band, s.bandIndex = Nutrition.band(80)
    local events, week = Nutrition.project(s, 30)
    local at = {}
    for _, e in ipairs(events) do at[e.id] = e.minutes / 60 end
    assert(near(at.richEnds, 7.94, 0.17), at.richEnds)
    assert(near(at.bonusEnds, 22.6, 0.17), at.bonusEnds)
    assert(at.gainStops > 13.3 and at.gainStops < 14.0, at.gainStops)
    assert(near(at.lossStarts, 31.25, 0.17), at.lossStarts)
    -- Protein 120 - 74.3/day reaches -300 after 5.65 days.
    assert(near(at.penaltyStarts / 24, 5.65, 0.02), at.penaltyStarts / 24)
    assert(at.band3 and at.band3 > 24 * 9 and at.band3 < 24 * 12, "underweight comes after nine to twelve days")
    assert(week < 80 and week > 75, week)
    for index = 2, #events do assert(events[index].minutes >= events[index - 1].minutes, "soonest first") end
end
print("PASS the forecast runs the game's rules forward to each line")

do
    -- Food: energy shares at 4 kcal/g carbs and protein, 9 kcal/g fat.
    local chips = {kind = "Food", getCalories = function() return 720 end, getCarbohydrates = function() return 72 end,
        getLipids = function() return 45 end, getProteins = function() return 5 end, getHungerChange = function() return -0.15 end}
    local f = Nutrition.food(chips)
    assert(near(f.share.carbs, 288 / 713) and near(f.share.fat, 405 / 713) and near(f.share.protein, 20 / 713))
    assert(near(f.hunger, 0.15))
end
print("PASS a food's energy is split by where it comes from")

print("Nutrition PASS")
