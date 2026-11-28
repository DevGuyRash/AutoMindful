-- What to eat when there is a choice: the survivor's diet goal nudges food
-- choice by at most a sixth. It never overrides what the need itself calls for.
local Nutrition = require "AutoMindful/Nutrition"
local Diet = {nudge = 0.15}

local function number(item, method)
    local read = item[method]
    local ok, value = pcall(read, item)
    return ok and type(value) == "number" and value or 0
end

local function weight(player)
    local ok, value = pcall(function() return player:getNutrition():getWeight() end)
    return ok and type(value) == "number" and value or nil
end

-- Read lazily, once: food choice is also used where the options page is not loaded.
local options
function Diet.options()
    -- Remembered once found; until then, asked again.
    if not options then
        local ok, module = pcall(require, "AutoMindful/Options")
        options = ok and type(module) == "table" and module or nil
    end
    return options
end

-- The goal in force: Auto steers back toward a healthy weight and is
-- Balanced inside it.
function Diet.goal(player)
    local Options = Diet.options()
    local goal = Options and Options.dietGoal and Options.dietGoal() or "auto"
    if goal ~= "auto" then return goal end
    local kilograms = player and weight(player)
    if not kilograms then return "balanced" end
    -- The game's own weight bands: below healthy, eat more; above, fewer.
    local band = Nutrition.band(kilograms)
    if band.tone ~= "good" then
        for _, other in ipairs(Nutrition.bands) do
            if other.tone == "good" then return kilograms < other.upTo and "more" or "fewer" end
        end
    end
    return "balanced"
end

-- -1..1: how well one item suits the goal, per unit of hunger it relieves.
function Diet.fit(goal, item)
    if goal == "balanced" or not item or not instanceof(item, "Food") then return 0 end
    local relief = math.max(0.01, -number(item, "getHungerChange"))
    local calories = number(item, "getCalories") / relief
    local share = function(value) return math.max(-1, math.min(1, value)) end
    if goal == "protein" then return share(number(item, "getProteins") / relief / 100 - 0.2) end
    if goal == "lowcarb" then return share(0.3 - number(item, "getCarbohydrates") / relief / 250) end
    if goal == "lowfat" then return share(0.3 - number(item, "getLipids") / relief / 150) end
    -- About 2000 calories per full hunger bar is ordinary food.
    if goal == "more" then return share(calories / 2000 - 1) end
    if goal == "fewer" then return share(1 - calories / 2000) end
    return 0
end

function Diet.score(player, item)
    return Diet.fit(Diet.goal(player), item)
end

-- A utility nudged toward the goal.
function Diet.adjust(player, utility, item)
    if type(utility) ~= "number" then return utility end
    -- Scaled by size, so a negative utility moves the same way as a positive one.
    return utility + math.abs(utility) * Diet.nudge * Diet.score(player, item)
end

return Diet
