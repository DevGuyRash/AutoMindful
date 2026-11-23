-- Decide a Train Both turn without touching the player or timed action queue.
-- The controller owns eligibility, the in-flight action and native receipts.
local TrainingCycle = {}

local function skill(kind)
    if kind == "meditation" or kind == "yoga" then return kind end
end

function TrainingCycle.normalizePolicy(policy)
    if policy == "lowest" or policy == "closest" then return policy end
    return "alternate"
end

local function needed(entry)
    if type(entry) ~= "table" or entry.needed ~= true then return false end
    if entry.allowCapped == true then return true end
    local progress = entry.progress
    return type(progress) ~= "table" or (progress.capped ~= true and progress.level ~= 10)
end

local function progressRank(entry)
    local progress = entry.progress
    if type(progress) ~= "table" then return nil end
    local level, fraction = progress.level, progress.fraction
    if type(level) ~= "number" or not (level >= 0 and level < 10 and level == math.floor(level))
            or type(fraction) ~= "number" or not (fraction >= 0 and fraction <= 1) then return nil end
    -- Meditation exposes cumulative XP; Yoga exposes XP within its rank. Only
    -- level and the fraction of the next rank are directly comparable here.
    return level + fraction
end

local function preference(policy, lastCompleted, meditation, yoga)
    if policy ~= "alternate" then
        local m, y = progressRank(meditation), progressRank(yoga)
        if m and y and m ~= y then
            if policy == "lowest" then return m < y and "meditation" or "yoga" end
            return m > y and "meditation" or "yoga"
        end
    end
    return lastCompleted == "meditation" and "yoga" or "meditation"
end

-- Entries are { needed = boolean, eligible = boolean, progress = sample, allowCapped = boolean }.
-- Owed means the policy preferred a skill its native rules did not yet allow.
-- A fallback (even a completed one) cannot spend that skill's turn.
function TrainingCycle.choose(policy, lastCompleted, owed, meditation, yoga)
    local mNeeded, yNeeded = needed(meditation), needed(yoga)
    if not mNeeded and not yNeeded then return {reason = "complete"} end
    if (owed ~= "meditation" or not mNeeded) and (owed ~= "yoga" or not yNeeded) then owed = nil end

    local desired = owed
    if not desired then
        if not mNeeded then desired = "yoga"
        elseif not yNeeded then desired = "meditation"
        else desired = preference(TrainingCycle.normalizePolicy(policy), lastCompleted, meditation, yoga) end
    end
    local mReady = mNeeded and meditation.eligible == true
    local yReady = yNeeded and yoga.eligible == true
    if (desired == "meditation" and mReady) or (desired == "yoga" and yReady) then
        return {kind = desired, preferred = desired, owed = owed, reason = "ready"}
    end
    local fallback = mReady and "meditation" or yReady and "yoga" or nil
    return {kind = fallback, preferred = desired, owed = desired, reason = fallback and "fallback" or "blocked"}
end

-- Call only after verified native completion of this skill's practice (not
-- queueing, a posture change, incidental XP, or an interrupted action).
function TrainingCycle.complete(lastCompleted, owed, kind)
    local completed = skill(kind)
    owed = skill(owed)
    if not completed then return skill(lastCompleted), owed end
    if completed == owed then owed = nil end
    return completed, owed
end

return TrainingCycle
