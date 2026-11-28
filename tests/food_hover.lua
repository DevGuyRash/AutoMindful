-- The food hover: what eating all of a food does to this survivor now,
-- against the game's calorie lines and protein band, worked by hand.
package.path = "mods/SecondNature/common/media/lua/client/?.lua;" .. package.path
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

-- ------------------------------------------------------------- food hover
do
    package.loaded["AutoMindful/Options"] = {foodHover = function() return "always" end, dietGoal = function() return "balanced" end}
    local Hover = require "AutoMindful/FoodHover"
    local function body(calories, protein)
        return {getNutrition = function() return {getWeight = function() return 80 end, getCalories = function() return calories end,
                getCarbohydrates = function() return 0 end, getLipids = function() return 0 end, getProteins = function() return protein end,
                isIncWeight = function() return false end, isIncWeightLot = function() return false end, isDecWeight = function() return false end,
                canAddFitnessXp = function() return true end} end,
            hasTrait = function() return false end, isAsleep = function() return false end, isPlayerMoving = function() return false end,
            getBodyDamage = function() return {getThermoregulator = function() return {getEnergyMultiplier = function() return 1 end} end} end,
            getModData = function() return {} end}
    end
    local beans = {kind = "Food", getCalories = function() return 400 end, getCarbohydrates = function() return 60 end,
        getLipids = function() return 4 end, getProteins = function() return 20 end, getHungerChange = function() return -0.2 end,
        isPackaged = function() return false end, getModData = function() return {} end}
    -- 800 kcal now, 400 more: past the 1000 gain line.
    local lines = Hover.lines(body(800, 40), beans)
    assert(lines[1].text == "Eating it all: +400 kcal, stored energy 800 to 1200", lines[1].text)
    assert(lines[2].text == "This starts weight gain.")
    assert(lines[3].text == "Reaches the protein bonus to Strength XP.", "40 + 20 passes 50")
    assert(lines[4].bar and lines[5].cells[1].text == "Carbs 60 g", "grams where the game prints no label")
    assert(lines[#lines].text == "Eases 20 hunger, 20 kcal for each point.", "400 kcal over 20 hunger")
    -- At -500 kcal, still below the loss line after eating: still losing.
    lines = Hover.lines(body(-500, 200), beans)
    assert(lines[1].text == "Eating it all: +400 kcal, stored energy -500 to -100" and lines[2].text == "Weight keeps going down.", lines[2].text)
    -- 40 g protein and 270 more overshoots the 300 g top of the bonus band.
    local steak = {kind = "Food", getCalories = function() return 300 end, getCarbohydrates = function() return 0 end,
        getLipids = function() return 10 end, getProteins = function() return 270 end, getHungerChange = function() return -0.1 end,
        isPackaged = function() return false end, getModData = function() return {} end}
    for _, line in ipairs(Hover.lines(body(0, 40), steak)) do
        assert(line.text ~= "Reaches the protein bonus to Strength XP.", "no bonus past 300 g")
    end
    assert(Hover.recent(nil) == nil)
end
print("PASS the food hover says what eating it does to this survivor now")
print("Food hover PASS")
