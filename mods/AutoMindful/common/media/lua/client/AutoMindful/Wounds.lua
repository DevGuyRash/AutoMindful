-- Each body part as the survivor would see it on the health panel, in a
-- word or two per condition, plus how fast it is healing (measured from the
-- game's own timers over in-game time). The care itself is FirstAid's.
-- Reads only. Never shows what the survivor could not know (a zombie
-- infection, or a wound infection a low Doctor level would not spot).
local Clock = require "AutoMindful/Clock"
local FirstAid = require "AutoMindful/FirstAid"
local Wounds = {}

local function read(fn, fallback)
    local ok, value = pcall(fn)
    if ok and value ~= nil then return value end
    return fallback
end

-- Where each part sits on the body map: column, row, width, height in a
-- 12 x 24 grid, seen from the front (the survivor's left on the right).
Wounds.map = {
    Head = {5, 0, 2, 3}, Neck = {5, 3, 2, 1},
    Torso_Upper = {4, 4, 4, 4}, Torso_Lower = {4, 8, 4, 3}, Groin = {4, 11, 4, 2},
    UpperArm_R = {2, 4, 2, 4}, ForeArm_R = {1, 8, 2, 4}, Hand_R = {0, 12, 2, 2},
    UpperArm_L = {8, 4, 2, 4}, ForeArm_L = {9, 8, 2, 4}, Hand_L = {10, 12, 2, 2},
    UpperLeg_R = {4, 13, 2, 5}, LowerLeg_R = {4, 18, 2, 5}, Foot_R = {3, 23, 3, 1},
    UpperLeg_L = {6, 13, 2, 5}, LowerLeg_L = {6, 18, 2, 5}, Foot_L = {6, 23, 3, 1},
}

local rank = {bad = 3, warn = 2, good = 1, muted = 0}
Wounds.rank = rank

-- The conditions, worst first, each {text, tone}. tone: bad needs care now,
-- warn needs care, good is cared for, muted is only worth knowing.
function Wounds.tags(player, part)
    local tags = {}
    local function tag(text, tone) tags[#tags + 1] = {text = text, tone = tone} end
    local w = FirstAid.wound
    local covered = part:bandaged()
    if covered and part:getBleedingTime() > 0 then tag("Bleeding under the dressing", "warn")
    elseif part:bleeding() then tag("Bleeding", "bad") end
    if part:haveGlass() then tag("Glass in it", "bad") end
    if part:haveBullet() then tag("Bullet in it", "bad") end
    if FirstAid.infectionKnown(player, part) then tag("Infected", "bad") end
    if w.deep(part) and not w.stitched(part) then tag("Deep wound", "bad") end
    if w.bitten(part) then tag("Bite", "bad") end
    if FirstAid.fractured(part) then tag("Broken bone", "bad") end
    if w.cut(part) then tag("Laceration", "warn") end
    if w.scratched(part) then tag("Scratch", "warn") end
    if part:getBurnTime() > 0 then tag(part:isNeedBurnWash() and "Burn, needs cleaning" or "Burn", part:isNeedBurnWash() and "warn" or "muted") end
    if covered and part:isBandageDirty() then tag("Dirty dressing", "warn") end
    if not covered and FirstAid.dressable(part) and not part:bleeding() then tag("Not dressed", "warn") end
    if w.stitched(part) then
        if part:getStitchTime() > FirstAid.policy.goodStitch then tag("Stitches can come out", "muted") else tag("Stitched", "good") end
    end
    if part:getSplintFactor() > 0 then
        if part:getFractureTime() > 0 then tag("Splinted", "good") else tag("Splint can come off", "muted") end
    end
    if covered and not part:isBandageDirty() then tag("Dressed", "good") end
    if part:getAlcoholLevel() > 0 then tag("Disinfected", "good") end
    if read(function() return part:getPlantainFactor() > 0 or part:getComfreyFactor() > 0 or part:getGarlicFactor() > 0 end, false) then
        tag("Poultice", "good")
    end
    table.sort(tags, function(a, b) return rank[a.tone] > rank[b.tone] end)
    return tags
end

-- Healing measured: each timer the game counts down, sampled now and then.
local timers = {scratch = "getScratchTime", cut = "getCutTime", deep = "getDeepWoundTime", bite = "getBiteTime",
    burn = "getBurnTime", fracture = "getFractureTime", dressing = "getBandageLife"}
local samples = setmetatable({}, {__mode = "k"})
local sampleHours = 1 / 6

local function sample(part, hours)
    local now = {}
    for key, method in pairs(timers) do now[key] = read(function() return part[method](part) end, 0) end
    local seen = samples[part]
    if not seen then samples[part] = {at = hours, values = now}; return nil end
    -- Rates over the last span long enough to measure; a fresh wound starts again.
    if hours - seen.at >= sampleHours then
        local span = hours - seen.at
        local rates = {}
        for key, value in pairs(now) do
            local before = seen.values[key] or 0
            if value > 0 and before > value then rates[key] = (before - value) / span end
        end
        seen.rates, seen.at, seen.values = rates, hours, now
    elseif hours < seen.at then samples[part] = {at = hours, values = now} end
    return seen.rates, now
end

-- In-game minutes until each timer reaches zero at the rate it is going, or nil.
local function eta(part)
    local hours = Clock.worldHours()
    if not hours then return nil end
    local rates, now = sample(part, hours)
    if not rates then return nil end
    local out = {}
    for key, rate in pairs(rates) do
        if rate > 0 and (now[key] or 0) > 0 then out[key] = now[key] / rate * 60 end
    end
    return out
end

-- Every part with anything to see, most dangerous first:
-- {part, type, name, tags, tone, danger, covered, heal (minutes to heal), dirtyIn (dressing)}.
function Wounds.read(player)
    local parts = read(function() return player:getBodyDamage():getBodyParts() end, nil)
    if not parts then return {} end
    local list = {}
    for index = 0, parts:size() - 1 do
        local part = parts:get(index)
        local tags = part.bandaged and Wounds.tags(player, part) or {}
        if #tags > 0 then
            local danger = FirstAid.danger(player, part)
            local times = eta(part) or {}
            local heal
            for _, key in ipairs({"deep", "bite", "cut", "scratch", "burn", "fracture"}) do
                if times[key] then heal = math.max(heal or 0, times[key]) end
            end
            local tone = tags[1].tone
            list[#list + 1] = {part = part, type = tostring(read(function() return part:getType():toString() end, "")),
                name = FirstAid.partName(part), tags = tags, tone = tone, danger = danger, covered = part:bandaged(),
                -- An infection soaks a dressing faster: unknown, it must not show in the countdown.
                heal = heal, dirtyIn = part:bandaged() and not part:isBandageDirty()
                    and (FirstAid.infectionKnown(player, part) or not read(function() return part:isInfectedWound() end, false))
                    and times.dressing or nil,
                health = read(function() return part:getHealth() end, 100)}
        end
    end
    table.sort(list, function(a, b)
        if a.danger ~= b.danger then return a.danger > b.danger end
        return rank[a.tone] > rank[b.tone]
    end)
    return list
end

-- The parts that need something done, and the worst tone among them.
function Wounds.summary(list)
    local care, worst = 0, "muted"
    for _, wound in ipairs(list) do
        if wound.danger > 0 then care = care + 1 end
        if rank[wound.tone] > rank[worst] then worst = wound.tone end
    end
    return care, worst
end

return Wounds
