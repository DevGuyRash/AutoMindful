-- The survivor's nutrition as the game keeps it, and where it is heading.
-- Every number is read live from the game's Nutrition object; the rules are
-- the game's own (zombie.characters.BodyDamage.Nutrition, B42), so the
-- projection runs them forward instead of guessing a trend. Reads only.
local Nutrition = {}

-- The game's constants. Rates are per in-game second.
local rules = {
    calories = {low = -2200, high = 3700}, macros = {low = -500, high = 1000},
    decay = {carbs = 0.0035, fat = 0.00113, protein = 0.00086},
    burn = {asleep = 0.003, resting = 0.016, walking = 0.078, running = 0.13, sprinting = 0.169},
    gain = {line = 1000, slow = 700, fast = 1800, perKg = 40, rate = 1.3e-5, full = 4000, rich = 400, richer = 700},
    loss = {perKg = 30, from = 70, rate = 8.5e-6, full = 2500},
    protein = {bonus = 50, bonusTop = 300, penalty = -300},
    weight = {floor = 35},
}
Nutrition.rules = rules

-- Weight bands, lightest first: the trait the game gives at each weight.
-- upTo: the heaviest weight in the band (inclusive), as applyTraitFromWeight.
Nutrition.bands = {
    {id = "emaciated", label = "Emaciated", upTo = 50, tone = "bad"},
    {id = "veryUnderweight", label = "Very underweight", upTo = 65, tone = "bad"},
    {id = "underweight", label = "Underweight", upTo = 75, tone = "warn"},
    {id = "healthy", label = "Healthy weight", upTo = 85, below = true, tone = "good"},
    {id = "overweight", label = "Overweight", upTo = 100, below = true, tone = "warn"},
    {id = "obese", label = "Obese", upTo = math.huge, tone = "bad"},
}

local function real(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function read(fn, fallback)
    local ok, value = pcall(fn)
    if ok and value ~= nil then return value end
    return fallback
end

function Nutrition.band(weight)
    for index, band in ipairs(Nutrition.bands) do
        if band.below and weight < band.upTo or not band.below and weight <= band.upTo then return band, index end
    end
    return Nutrition.bands[#Nutrition.bands], #Nutrition.bands
end

local function trait(player, name)
    return read(function() return player:hasTrait(CharacterTrait[name]) end, false) == true
end

-- Above this many calories weight goes up; below lossLine it goes down.
function Nutrition.lines(weight, slow, fast)
    local g = rules.gain
    local gain = g.line
    if slow and weight < 90 then gain = g.slow end
    if fast and weight > 70 then gain = g.fast end
    gain = gain + (weight - 80) * g.perKg
    return gain, math.min(0, (weight - rules.loss.from) * rules.loss.perKg)
end

-- Kilograms per in-game second at these values, and the speed-up for a rich diet.
function Nutrition.rate(weight, calories, carbs, fat, slow, fast)
    local gainLine, lossLine = Nutrition.lines(weight, slow, fast)
    if calories > gainLine then
        local g, boost = rules.gain, 1
        if carbs > g.richer or fat > g.richer then boost = 3 elseif carbs > g.rich or fat > g.rich then boost = 2 end
        return g.rate * boost * math.min(calories / g.full, 1), boost
    end
    if calories < lossLine then
        return -rules.loss.rate * math.min(-calories / rules.loss.full, 1), 1
    end
    return 0, 1
end

-- What the survivor is doing, as the game counts calories for it.
local function activity(player)
    if read(function() return player:isAsleep() end, false) then return "asleep" end
    local moving = read(function() return player:isPlayerMoving() end, false)
    if moving and read(function() return player:isRunning() end, false) then return "running" end
    if moving and read(function() return player:isSprinting() end, false) then return "sprinting" end
    if moving then return "walking" end
    return "resting"
end

-- Warmth costs energy: the game multiplies resting and sleeping burn by this.
local function thermal(player)
    local value = read(function() return player:getBodyDamage():getThermoregulator():getEnergyMultiplier() end, 1)
    return real(value) and value > 0 and value or 1
end

-- What the current action costs: the game multiplies resting burn by it
-- (reading 0.5, building and barricading 8, cleaning 5).
local function effort(player)
    local value = read(function()
        local queue = ISTimedActionQueue.getTimedActionQueue(player).queue
        return queue[1] and queue[1].caloriesModifier
    end, 1)
    return real(value) and value > 0 and value or 1
end

-- Calories burned per in-game second for an activity at this weight.
-- factor: the action's multiplier, for resting and sleep only, as the game does.
function Nutrition.burn(kind, weight, warmth, factor)
    local rate = rules.burn[kind] or rules.burn.resting
    if kind == "asleep" or kind == "resting" then rate = rate * (warmth or 1) * (factor or 1) end
    return rate * weight / 80
end

-- The live state, or nil when this survivor has no nutrition (sandbox off).
function Nutrition.read(player)
    if SandboxVars and SandboxVars.Nutrition == false then return nil end
    local n = read(function() return player:getNutrition() end, nil)
    if not n then return nil end
    local s = {
        weight = read(function() return n:getWeight() end, nil), calories = read(function() return n:getCalories() end, nil),
        carbs = read(function() return n:getCarbohydrates() end, nil), fat = read(function() return n:getLipids() end, nil),
        protein = read(function() return n:getProteins() end, nil),
    }
    for _, key in ipairs({"weight", "calories", "carbs", "fat", "protein"}) do if not real(s[key]) then return nil end end
    s.slow, s.fast = trait(player, "WEIGHT_GAIN"), trait(player, "WEIGHT_LOSS")
    s.gainLine, s.lossLine = Nutrition.lines(s.weight, s.slow, s.fast)
    local rate, boost = Nutrition.rate(s.weight, s.calories, s.carbs, s.fat, s.slow, s.fast)
    s.perDay, s.boost = rate * 86400, boost
    -- The game's own flags: they say which way it moved this moment.
    s.gaining = read(function() return n:isIncWeight() end, rate > 0) == true
    s.gainingFast = read(function() return n:isIncWeightLot() end, boost > 1) == true
    s.losing = read(function() return n:isDecWeight() end, rate < 0) == true
    s.band, s.bandIndex = Nutrition.band(s.weight)
    s.activity, s.warmth = activity(player), thermal(player)
    s.effort = effort(player)
    s.burnHour = Nutrition.burn(s.activity, s.weight, s.warmth, s.effort) * 3600
    s.restHour = Nutrition.burn("resting", s.weight, s.warmth) * 3600
    local p = rules.protein
    s.proteinEffect = s.protein > p.bonus and s.protein < p.bonusTop and "bonus" or s.protein < p.penalty and "penalty" or nil
    s.fitnessBlocked = read(function() return not n:canAddFitnessXp() end, false) == true
    return s
end

local function clamp(value, range) return math.max(range.low, math.min(range.high, value)) end

-- What happens if the survivor eats nothing more and rests: the next time
-- each line is crossed, in in-game minutes. Runs the game's rules forward
-- in ten-minute steps for up to `days` in-game days. Also returns the
-- weight a week of that would leave.
function Nutrition.project(s, days)
    local step, limit = 600, (days or 30) * 86400
    local w, cal, carbs, fat, protein = s.weight, s.calories, s.carbs, s.fat, s.protein
    local events, seen = {}, {}
    local function event(id, text, seconds, tone)
        if seen[id] then return end
        seen[id] = true
        events[#events + 1] = {id = id, text = text, minutes = seconds / 60, tone = tone}
    end
    local startRate = Nutrition.rate(w, cal, carbs, fat, s.slow, s.fast)
    local startBand = s.bandIndex
    local wasRich = carbs > rules.gain.rich or fat > rules.gain.rich
    local p = rules.protein
    local wasBonus, wasPenalty = protein > p.bonus and protein < p.bonusTop, protein < p.penalty
    local t, week = 0, nil
    while t < limit do
        local burn = Nutrition.burn("resting", w, s.warmth)
        cal = clamp(cal - burn * step, rules.calories)
        carbs = clamp(carbs - rules.decay.carbs * step, rules.macros)
        fat = clamp(fat - rules.decay.fat * step, rules.macros)
        protein = clamp(protein - rules.decay.protein * step, rules.macros)
        local rate = Nutrition.rate(w, cal, carbs, fat, s.slow, s.fast)
        w = math.max(rules.weight.floor, w + rate * step)
        t = t + step
        if not week and t >= 7 * 86400 then week = w end
        if startRate > 0 and rate <= 0 then event("gainStops", "Stops gaining weight", t, "muted") end
        if startRate >= 0 and rate < 0 then event("lossStarts", "Starts losing weight", t, "warn") end
        if wasRich and startRate > 0 and rate > 0 and carbs <= rules.gain.rich and fat <= rules.gain.rich then
            event("richEnds", "Fast weight gain ends", t, "muted")
        end
        local bonus = protein > p.bonus and protein < p.bonusTop
        if wasBonus and not bonus then event("bonusEnds", "Protein bonus to Strength XP ends", t, "warn") end
        if not wasBonus and protein > p.bonus and bonus then event("bonusStarts", "Protein bonus to Strength XP starts", t, "good") end
        if not wasPenalty and protein < p.penalty then event("penaltyStarts", "Low protein starts slowing Strength XP", t, "bad") end
        local band, index = Nutrition.band(w)
        if index ~= startBand then
            event("band" .. index, band.label, t, band.tone)
            startBand = index
        end
        -- Everything at its floor: weight now falls at one steady rate, so the
        -- rest is worked out directly instead of stepped through.
        if cal <= rules.calories.low and carbs <= rules.macros.low and fat <= rules.macros.low and protein <= rules.macros.low then
            local fall = -Nutrition.rate(w, cal, carbs, fat, s.slow, s.fast)
            if fall > 0 then
                if not week then week = math.max(rules.weight.floor, w - fall * (7 * 86400 - t)) end
                for lower = index - 1, 1, -1 do
                    local edge = Nutrition.bands[lower].upTo
                    local at = t + (w - edge) / fall
                    if edge >= rules.weight.floor and at <= limit then
                        event("band" .. lower, Nutrition.bands[lower].label, at, Nutrition.bands[lower].tone)
                    end
                end
            end
            break
        end
    end
    table.sort(events, function(a, b) return a.minutes < b.minutes end)
    return events, week or w
end

-- Food as the survivor would eat all of it: calories and grams, and where
-- the calories come from (carbs and protein 4 kcal/g, fat 9).
function Nutrition.food(item)
    if not item or not (instanceof and instanceof(item, "Food")) then return nil end
    local f = {calories = read(function() return item:getCalories() end, 0), carbs = read(function() return item:getCarbohydrates() end, 0),
        fat = read(function() return item:getLipids() end, 0), protein = read(function() return item:getProteins() end, 0),
        hunger = read(function() return -item:getHungerChange() end, 0)}
    for key, value in pairs(f) do if not real(value) then f[key] = 0 end end
    local energy = f.carbs * 4 + f.fat * 9 + f.protein * 4
    f.share = energy > 0 and {carbs = f.carbs * 4 / energy, fat = f.fat * 9 / energy, protein = f.protein * 4 / energy} or nil
    return f
end

return Nutrition
