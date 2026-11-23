-- Choose optional comfort work. The controller owns native admission, actions,
-- and observations. Nothing here changes stats or spends a training turn.
local Facts = require "AutoMindful/WellnessFacts"
local PracticeCare = {}

local effects = {
    boredom={stat="BOREDOM", read="BOREDOM", max=100},
    unhappiness={stat="UNHAPPINESS", read="UNHAPPINESS", max=100},
    stiffness={stat="STIFFNESS", max=100}, -- BodyPart stiffness is not the PAIN stat.
    pain={stat="PAIN", read="PAIN", max=100, tier=2},
    stress={stat="STRESS", read="STRESS", max=1, tier=1},
    withdrawal={stat="NICOTINE_WITHDRAWAL", read="NICOTINE_WITHDRAWAL", max=1, tier=1},
    panic={stat="PANIC", read="PANIC", max=100, tier=1},
    hunger={stat="HUNGER", read="HUNGER", max=1, tier=2},
    health={stat="HEALTH", read="HEALTH", max=100, tier=3, rising=true},
}
local limits = {
    [1]={[0]=90000},
    [2]={[0]=240000,[1]=180000},
    [3]={[0]=420000,[1]=370000,[2]=240000},
}

local function number(value, max)
    if type(value) == "number" and value >= 0 and value <= max then return value end
end

local function rank(value)
    return number(value, 10) and value == math.floor(value) and value or nil
end

local function measure(readings, need)
    local effect = effects[need]
    if type(readings) ~= "table" or not effect then return nil end
    local value = readings[need]
    if value == nil and effect.read then value = readings[effect.read] end
    return number(value, effect.max)
end

local function mindTier(readings)
    if type(readings) ~= "table" then return nil end
    local value = readings.mindTier
    if value == nil then value = readings.MIND_TIER end
    return number(value, 3) and value == math.floor(value) and value or nil
end

function PracticeCare.nativeTier(value, level)
    level = rank(level)
    if not level or not number(value, 1) then return nil end
    -- Under rank 3 Lifestyle clears even an old saved badge. At >=3 its
    -- ongoing effects use the *active* tier, not a second unlock check.
    if level < Facts.meditationUnlocks[1] then return 0 end
    return value>=0.6 and 3 or value>=0.4 and 2 or value>=0.2 and 1 or 0
end

local function course(kind, need, maxMs)
    return {kind=kind, need=need, stat=effects[need].stat, maxMs=maxMs}
end

local function yogaBudget(level)
    -- Leave time for a native pose sequence, including terminal parent phases.
    -- Stopping early penalizes XP and may withhold Zen.
    if level < 4 then return 240000 end
    if level < 8 then return 330000 end
    return 450000
end

local function calmMeditation(boredom, pain)
    return boredom and boredom <= 5 and pain and pain <= 5
end

-- Lower start thresholds belong to passive Recovery only. Keep the same
-- trigger when rechecking an active course with an optional tier target.
function PracticeCare.needsRelief(need,kind,level,value,recovery,sleepBlocked)
    local effect=effects[need]
    if not effect or not number(value,effect.max) then return false end
    if need=="stress" then
        if kind=="yoga" then return value>=(recovery and 0.55 or 0.65) end
        return value>=(recovery and 0.30 or 0.50)
    end
    if need=="withdrawal" then return value>=(recovery and 0.25 or 0.35) end
    if need=="panic" then return value>=(sleepBlocked and 5 or recovery and 12 or 25) end
    if need=="unhappiness" then return recovery==true and value>=20 end
    if need=="stiffness" then return value>=(level>=3 and (recovery and 10 or 12.5) or (recovery and 15 or 20)) end
    if need=="boredom" then
        if recovery then return value>=(level>=3 and 18 or 24) end
        return value>30 or (level>=3 and value>=25)
    end
    return false
end

-- In the pinned native Meditation action, Boredom <= 5 neutralizes even
-- Couch Potato's aversion. The resulting Unhappiness delta is negative
-- at any rank and positive strength setting. Yoga doesn't change this stat.
function PracticeCare.unhappinessContext(boredom,pain)
    return calmMeditation(boredom,pain)==true
end

-- The ordinary supply trigger is not an upper limit on the native effect.
function PracticeCare.hungry(value)
    return number(value,1)~=nil and value>=0.15
end

function PracticeCare.hungerUnlocked(level)
    return rank(level)~=nil and level>=Facts.meditationUnlocks[effects.hunger.tier]
end

-- Already-active native effects need no posture, equipment or new action.
-- Acquisition requires the *current* rank and the caller's live native gate.
function PracticeCare.hungerPlan(value,level,tier,ready)
    if not PracticeCare.hungry(value) or not rank(level) or level<Facts.meditationUnlocks[1]
            or not number(tier,3) or tier~=math.floor(tier) then return end
    local effect=effects.hunger
    local plan={target="hunger",targetTier=effect.tier}
    if tier>=effect.tier then return nil,plan end
    if ready and PracticeCare.hungerUnlocked(level) then
        plan.kind,plan.need,plan.stat="meditation","mindfulness",effect.stat
        plan.recovery,plan.fromTier,plan.maxMs=true,tier,limits[effect.tier][tier]
        return plan
    end
end

function PracticeCare.healingEnabled(factor)
    -- Lifestyle defaults a missing option to 2. An explicit 0 is valid and
    -- disables health recovery, independent of all other tier effects.
    return factor==nil or (number(factor,10)~=nil and factor>0)
end

local function effectEnabled(target,readings)
    return target~="health" or PracticeCare.healingEnabled(type(readings)=="table" and readings.healFactor)
end

local function mindfulness(input, m, y, yogaPain, boredom, pain, canStart)
    if input.mindfulEnabled ~= true then return nil end
    local level, tier = rank(input.meditationRank), mindTier(input)
    if not level or level < Facts.meditationUnlocks[1] or tier == nil then return nil end
    local hunger, panic, health = measure(input, "hunger"), measure(input, "panic"), measure(input, "health")
    local stress, withdrawal = measure(input, "stress"), measure(input, "withdrawal")
    local safeStart = canStart and m and input.preferTraining ~= "meditation"
        and boredom and boredom <= 5 and pain and pain < 20 and hunger and hunger <= 0.30
    local function match(need, applies, acquire)
        if not applies then return nil end
        local effect = effects[need]
        local desired = effect.tier
        local target = {target=need, targetTier=desired}
        if tier >= desired then return nil, target end
        if acquire and safeStart and level >= Facts.meditationUnlocks[desired] then
            target.kind, target.need, target.stat = "meditation", "mindfulness", effect.stat
            target.recovery, target.fromTier, target.maxMs = true, tier, limits[desired][tier]
            return target
        end
    end
    -- Dangers and direct resources are checked by the controller first.
    -- Basic is for substantial panic, or enough residual panic to prevent sleep.
    local attempt, passive, passivePanic
    if (input.recovery==true or input.sleepRelief==true) and not input.hungerOnly then
        attempt, passive = match("panic", PracticeCare.needsRelief("panic","meditation",level,panic,input.recovery,input.sleepBlocked), true)
        if attempt then return attempt end
        passivePanic=passive -- Basic is already easing panic; building Strong need not displace it.
    end
    if input.confirmedFood==false then
        attempt,passive=PracticeCare.hungerPlan(hunger,level,tier,m and input.acquireHunger~=false and input.preferTraining~="meditation"
            and (canStart or input.renewHunger==true or input.hungerOnly==true))
        if attempt or passive then return attempt,passive end
    end
    if passivePanic then return nil,passivePanic end
    if input.hungerOnly or (input.recovery~=true and input.sleepRelief~=true) then return nil end
    if hunger and hunger <= 0.30 then
        attempt, passive = match("pain", hunger<0.15 and pain and pain>=10 and pain<20 and input.painTreatment==false
            and not input.painReliefActive,
            not yogaPain and not (y and input.preferTraining=="yoga"))
        if attempt or passive then return attempt, passive end
    end
    if input.recovery~=true then return nil end
    -- Perfect heals general health, not the source of a wound or illness.
    -- Only offer it for mild, stable loss without a competing symptom.
    attempt, passive = match("health", PracticeCare.healingEnabled(input.healFactor) and input.healthSafe==true and health and health>=75 and health<95
        and hunger and hunger<0.15 and pain and pain<=5 and panic and panic<5, true)
    if attempt or passive then return attempt, passive end
    attempt, passive = match("withdrawal", PracticeCare.needsRelief("withdrawal","meditation",level,withdrawal,true), false)
    if passive then return nil, passive end
    return match("stress", PracticeCare.needsRelief("stress","meditation",level,stress,true), false)
end

-- "confirmed" literature and painTreatment=true mean ordinary care wins.
-- The second return is a passive observation, never an action or a wait.
function PracticeCare.choose(input)
    if type(input) ~= "table" or not number(input.now, math.huge) or input.now == math.huge then return nil end
    if input.nextAt ~= nil and not number(input.nextAt, math.huge) then return nil end
    if input.reading == "confirmed" or input.painTreatment == true then return nil end
    local canStart = not input.nextAt or input.now >= input.nextAt
    local y = input.yogaReady == true and rank(input.yogaRank)
    local m = input.meditationReady == true and rank(input.meditationRank)
    local boredom, pain = measure(input, "boredom"), measure(input, "pain")
    local stress, stiffness = measure(input, "stress"), measure(input, "stiffness")
    local yogaPain = y and not input.painReliefActive and pain and pain >= (y >= 3 and 15 or 25)
    local yogaNeed
    if y then
        -- Lifestyle applies the same boredom relief per successful pose.
        if PracticeCare.needsRelief("boredom","yoga",y,boredom,input.recovery) then yogaNeed="boredom"
        elseif PracticeCare.needsRelief("stiffness","yoga",y,stiffness,input.recovery) then yogaNeed="stiffness" end
    end
    -- Only a real, actionable hunger fallback may outrank optional comfort Yoga.
    -- A native Meditation blocker, confirmed treatment or helpful scheduled leg still wins.
    local attempt,passive=mindfulness(input,m,y,yogaPain,boredom,pain,canStart)
    if input.hungerOnly or (attempt and attempt.target=="hunger") then return attempt,passive end
    if yogaNeed and canStart then
        if input.preferTraining ~= "yoga" then return course("yoga", yogaNeed, yogaBudget(y)) end
        return nil
    end

    if attempt or passive then return attempt, passive end
    if not canStart then return nil end
    if yogaPain then
        if input.preferTraining ~= "yoga" then return course("yoga", "pain", yogaBudget(y)) end
        return nil
    end

    -- Both native practices can lower stress and smokers' withdrawal even
    -- at rank zero; only Meditation can build Mindfulness.
    local comfortable = m and calmMeditation(boredom, pain)
    local function direct(need, allowYoga)
        if (y and input.preferTraining == "yoga") or (comfortable and input.preferTraining == "meditation") then return nil end
        if comfortable then return course("meditation", need, 30000) end
        if y and allowYoga then return course("yoga", need, yogaBudget(y)) end
    end
    if input.recovery == true then
        local withdrawal = measure(input, "withdrawal")
        if PracticeCare.needsRelief("withdrawal","meditation",m,withdrawal,true) then
            local attempt = direct("withdrawal", true)
            if attempt then attempt.recovery=true; return attempt end
            if y and input.preferTraining=="yoga" or comfortable and input.preferTraining=="meditation" then return nil end
        end
    end
    if PracticeCare.needsRelief("stress","meditation",m,stress,input.recovery) then
        return direct("stress",PracticeCare.needsRelief("stress","yoga",y,stress,input.recovery))
    end
    if input.recovery==true and input.unhappinessReady==true and comfortable
            and PracticeCare.needsRelief("unhappiness","meditation",m,measure(input,"unhappiness"),true) then
        return direct("unhappiness",false)
    end
end

function PracticeCare.acquired(attempt, readings)
    if type(attempt) ~= "table" or attempt.recovery ~= true or attempt.need ~= "mindfulness" then return false end
    local effect = effects[attempt.target]
    local from, after = number(attempt.fromTier, 3), mindTier(readings)
    return effect ~= nil and effect.tier ~= nil and effectEnabled(attempt.target,readings) and attempt.targetTier == effect.tier and from ~= nil and from == math.floor(from)
        and from < attempt.targetTier and after ~= nil and after >= attempt.targetTier
end

local function changed(target, before, readings, minimum)
    local effect = effects[target]
    if not effect then return false end
    local old = type(before) == "table" and measure(before, target) or number(before, effect.max)
    local after = measure(readings, target)
    if old == nil or after == nil then return false end
    local improved = effect.rising and after - old or old - after
    return improved > minimum
end

-- A badge isn't relief. Capture the target *after* seeing the native tier;
-- queued Lifestyle effects may flush after that tier has expired.
function PracticeCare.watch(plan, readings)
    local effect = type(plan) == "table" and effects[plan.target]
    local active = mindTier(readings)
    if not effect or not effect.tier or not effectEnabled(plan.target,readings) or plan.targetTier~=effect.tier or not active or active<effect.tier then return nil end
    local before = measure(readings, plan.target)
    if not before then return nil end
    return {target=plan.target, targetTier=effect.tier, before=before}
end

function PracticeCare.observed(watch, readings)
    local effect = type(watch) == "table" and effects[watch.target]
    return type(effect)=="table" and effect.tier ~= nil and effectEnabled(watch.target,readings) and watch.targetTier==effect.tier
        and changed(watch.target, watch.before, readings, effect.max==1 and 0.0001 or 0.01)
end

function PracticeCare.improved(attempt, readings)
    if type(attempt) ~= "table" then return false end
    if attempt.need == "mindfulness" then
        return PracticeCare.acquired(attempt, readings)
            and PracticeCare.observed({target=attempt.target,targetTier=attempt.targetTier,before=attempt.before}, readings)
    end
    if attempt.need=="withdrawal" and attempt.recovery~=true
            or attempt.need=="panic" or attempt.need=="health" or attempt.need=="hunger" then return false end
    return changed(attempt.need, attempt.before, readings, 0)
end

-- Pinned Lifestyle ZLSUpdate.lua: automatic mode follows the day-length
-- preset; explicit MoodUpdate controls the accumulator flush. Perfect's
-- general-health effect uses its own per-minute callback, not this batch.
local configuredMinutes = {false,1,2,5,10,15,30,60,120}
function PracticeCare.receiptMinutes(target, moodUpdate, dayLength)
    if target=="health" then return 3 end
    local configured = configuredMinutes[moodUpdate]
    if configured then return configured + 2 end
    local day = number(dayLength, 27) or 4
    local automatic = day==1 and 120 or day==2 and 30 or day==3 and 15 or day<=6 and 10
        or day<=14 and 5 or day<=22 and 2 or 1
    return automatic + 2
end

return PracticeCare
