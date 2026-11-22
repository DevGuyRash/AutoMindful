-- Select optional comfort work; the controller owns admission, native actions,
-- receipts, and retries. Nothing here changes stats or spends a training turn.
local Facts = require "AutoMindful/WellnessFacts"
local PracticeCare = {}

local effects = {
    boredom={stat="BOREDOM", read="BOREDOM", max=100},
    stiffness={stat="PAIN", max=100}, -- BodyPart stiffness is not the PAIN stat.
    pain={stat="PAIN", read="PAIN", max=100},
    stress={stat="STRESS", read="STRESS", max=1},
    withdrawal={stat="NICOTINE_WITHDRAWAL", read="NICOTINE_WITHDRAWAL", max=1},
}
local hungerEffect = {stat="HUNGER", read="HUNGER", max=1}
local function number(value, max)
    if type(value) == "number" and value >= 0 and value <= max then return value end
end

local function rank(value)
    return number(value, 10) and value == math.floor(value) and value or nil
end

local function measure(readings, need, override)
    local effect = override or effects[need]
    if type(readings) ~= "table" or not effect then return nil end
    local value = readings[need]
    if value == nil and effect.read then value = readings[effect.read] end
    return number(value, effect.max)
end

local function course(kind, need, maxMs)
    return {kind=kind, need=need, stat=effects[need].stat, maxMs=maxMs}
end

local function yogaBudget(level)
    -- Allow time for the normal-speed native pose sequence, including a
    -- terminal pose's parent chain. Do not stop a successful pose early for
    -- comfort alone: Lifestyle applies an XP penalty and may withhold Zen.
    if level < 4 then return 240000 end
    if level < 8 then return 330000 end
    return 450000
end

local function calmMeditation(boredom, pain)
    return boredom and boredom <= 5 and pain and pain <= 5
end

local function mindTier(readings)
    if type(readings) ~= "table" then return nil end
    local value = readings.mindTier
    if value == nil then value = readings.MIND_TIER end
    return number(value, 3) and value == math.floor(value) and value or nil
end

local function strongCourse(input, m, y, boredom, pain)
    if not m or m < Facts.meditationUnlocks[2] or input.mindfulEnabled ~= true
            or input.preferTraining == "meditation" or not boredom or boredom > 5
            or not pain or pain >= 20 then return nil end
    local tier = mindTier(input)
    if tier == nil or tier >= 2 then return nil end
    local hunger = measure(input, "hunger", hungerEffect)
    if not hunger or hunger > 0.30 then return nil end
    local target, stat
    if hunger >= 0.15 then
        -- A meal still supplies calories; an unknown inventory is not a
        -- confirmed absence. Strong Mindfulness never stands in for food.
        if input.confirmedFood ~= false then return nil end
        target, stat = "hunger", hungerEffect.stat
    elseif pain >= 10 and input.painTreatment == false
            and not (y and input.preferTraining == "yoga") then
        target, stat = "pain", effects.pain.stat
    end
    if not target then return nil end
    -- The native timer advances with the world clock. From tier 1, Strong
    -- alone needs roughly 125 wall seconds at normal speed; from tier 0
    -- the first tier adds about 42 seconds. These are limits, not promises.
    return {kind="meditation", need="mindfulness", stat=stat, target=target,
        recovery=true, fromTier=tier, targetTier=2, maxMs=tier == 0 and 240000 or 180000}
end

-- now and nextAt use the same monotonic-ms clock. "confirmed" literature
-- and painTreatment=true mean a quicker, eligible care action is usable now.
-- A preferred training kind is one that would actually start at this boundary.
function PracticeCare.choose(input)
    if type(input) ~= "table" or not number(input.now, math.huge) or input.now == math.huge then return nil end
    if input.nextAt ~= nil and (not number(input.nextAt, math.huge) or input.now < input.nextAt) then return nil end
    if input.reading == "confirmed" or input.painTreatment == true then return nil end

    local y = input.yogaReady == true and rank(input.yogaRank)
    local m = input.meditationReady == true and rank(input.meditationRank)
    local boredom, pain = measure(input, "boredom"), measure(input, "pain")
    local stress, stiffness = measure(input, "stress"), measure(input, "stiffness")
    local yogaNeed
    if y then
        -- Native Meditation rejects boredom above 30. More experienced
        -- Yoga is reasonable sooner, not a larger boredom drop per pose.
        if boredom and (boredom > 30 or (y >= 3 and boredom >= 25)) then yogaNeed = "boredom"
        elseif stiffness and stiffness >= (y >= 3 and 12.5 or 20) then yogaNeed = "stiffness"
        elseif pain and pain >= (y >= 3 and 15 or 25) then yogaNeed = "pain" end
    end
    if yogaNeed then
        if input.preferTraining ~= "yoga" then return course("yoga", yogaNeed, yogaBudget(y)) end
        return nil
    end

    if input.recovery == true then
        local withdrawal = measure(input, "withdrawal")
        if withdrawal and withdrawal >= 0.35 then
            -- Both native actions directly lower a smoker's withdrawal at
            -- any rank, even without Mindfulness. Prefer a ready scheduled
            -- practice; start short Meditation only with low drawbacks.
            local med = m and calmMeditation(boredom, pain)
            if (y and input.preferTraining == "yoga") or (med and input.preferTraining == "meditation") then return nil end
            local choice = med and course("meditation", "withdrawal", 30000)
                or y and course("yoga", "withdrawal", yogaBudget(y))
            if choice then choice.recovery=true; return choice end
        end
        local strong = strongCourse(input, m, y, boredom, pain)
        if strong then return strong end
    end

    if not stress or stress < 0.5 or (y and input.preferTraining == "yoga") then return nil end
    -- Even at high rank, ordinary Meditation can raise boredom and neck
    -- pain. Do not start it for comfort when those already need attention.
    if m and m >= Facts.meditationUnlocks[2] and calmMeditation(boredom, pain) then
        if input.preferTraining ~= "meditation" then return course("meditation", "stress", 30000) end
        return nil
    end
    if y and y >= 3 and stress >= 0.65 then return course("yoga", "stress", yogaBudget(y)) end
end

-- A real native tier can be observed before the matching per-minute effect
-- settles. Don't report the tier itself as symptom relief.
function PracticeCare.acquired(attempt, readings)
    if type(attempt) ~= "table" or attempt.recovery ~= true or attempt.need ~= "mindfulness"
            or attempt.targetTier ~= 2 or (attempt.fromTier ~= 0 and attempt.fromTier ~= 1) then return false end
    local tier = mindTier(readings)
    return tier ~= nil and tier >= attempt.targetTier
end

-- The caller snapshots course.before before dispatch, either as a single
-- value for the target or a readings table. Only a real matching fall counts.
function PracticeCare.improved(attempt, readings)
    if type(attempt) ~= "table" then return false end
    local need = attempt.need
    local override
    if need == "mindfulness" then
        if not PracticeCare.acquired(attempt, readings) then return false end
        need = attempt.target
        if need == "hunger" then override = hungerEffect
        elseif need ~= "pain" then return false end
    elseif need == "withdrawal" and attempt.recovery ~= true then return false end
    local effect = override or effects[need]
    if not effect then return false end
    local before = type(attempt.before) == "table" and measure(attempt.before, need, override)
        or number(attempt.before, effect.max)
    local after = measure(readings, need, override)
    if before == nil or after == nil then return false end
    if attempt.need == "mindfulness" then
        -- Ignore negligible floating-point drift in these delayed receipts.
        return before - after > (need == "hunger" and 0.0001 or 0.01)
    end
    return after < before
end

return PracticeCare
