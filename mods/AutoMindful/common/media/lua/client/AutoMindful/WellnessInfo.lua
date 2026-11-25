-- Display-only advice from the dependent Lifestyle mod. Never construct a
-- timed action, read another survivor, initialize moodles, or grant any XP.
local Facts = require "AutoMindful/WellnessFacts"
local Info = {}
local gap = " <LINE><LINE> "
local lineGap = " <LINE> "
local changeSeparator = " to "
local mindfulName

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

local function supported()
    return safe(function()
        local mod = getModInfoByID and getModInfoByID("LifestyleHobbies")
        return mod and tostring(mod:getModVersion()) == Facts.version
    end) == true
end

-- Lifestyle's display tier, unrelated to the player's current Yoga skill level.
-- The XP mechanisms are distinct; the pose factor is not a global multiplier.
function Info.zenEffects(tier)
    if not supported() or type(tier) ~= "number" or tier % 1 ~= 0 or tier < 1 or tier > 4 then return end
    return tier * Facts.zenExperience[1], math.ceil(tier / Facts.zenExperience[2])
end

local function rawText(key)
    local translate = getTextOrNull or getText
    local value = safe(translate, key)
    if type(value) == "string" and #value <= 2048 and value ~= key and value:match("%S") then return value end
end

local function plain(raw)
    return raw:gsub("%b<>", ""):gsub("[<>%c]", ""):match("^%s*(.-)%s*$")
end

local function unlockNote(rank)
    local unlocks = Facts.meditationUnlocks
    if rank == unlocks[1] then
        return "Unlocks " .. mindfulName(1) .. ": eases stress, panic and nicotine withdrawal"
    elseif rank == unlocks[2] then
        return "Unlocks " .. mindfulName(2) .. ": meditate with " .. mindfulName(1) .. " active; also eases pain and hunger"
    elseif rank == unlocks[3] then
        return "Unlocks " .. mindfulName(3) .. ": meditate with " .. mindfulName(2) .. " active; also restores health"
    end
end

local function noteText(line, skill, verified)
    if line:match("^[-+]+$") then return "" end
    local sign, label = line:match("^([+]+)%s+(.+)$")
    if not sign then sign, label = line:match("^(-+)%s+(.+)$") end
    local key = (label or line):lower()
    local higher = sign and sign:sub(1, 1) == "+"
    if skill == "Yoga" then
        if (higher and key == "zen state duration") or key == "unlocked zen state for a short time after performing yoga" then
            return verified and "" or (higher and "Zen lasts longer after finishing Yoga" or line)
        end
        if higher and key == "pose sequence limit" then
            return verified and "" or "Each Yoga session targets more poses before it ends"
        end
        if verified and key:match("^unlocked %a+ level poses$") then return "" end
        if key == "can teach yoga lessons" then return "Can teach Yoga to another survivor in multiplayer" end
    elseif skill == "Meditation" then
        if higher and key == "action duration" then
            return verified and "" or "An uninterrupted meditation session can run longer"
        end
        if verified and (key == "unlocked new techniques" or key == "mastered the ultimate technique"
                or key == "can meditate while wearing backpack and bags"
                or key == "new mindfulness level, improved state can be achieved by meditating while under the effects of the previous level"
                or key == "unlocked mindfulness state, achieved during long meditative sessions, can grant a variety of bonuses") then return "" end
        if key == "xp rate is reduced by boredom" then return "High boredom reduces Meditation XP" end
        if key == "can meditate while wearing backpack and bags" then return "Can start meditation without removing worn bags" end
        if key == "can teach meditation lessons" then return "Can teach Meditation to another survivor in multiplayer" end
        if sign and not higher and key == "neck pain rate" then return verified and "" or "Meditation can add less neck pain when it causes any" end
        if sign and not higher and key == "boredom rate" then return verified and "" or "Meditation can add less boredom per effect tick" end
    end
    if sign then
        if #sign == 1 then return label .. (higher and " (increases)" or " (decreases)") end
        local emphasis = #sign == 2 and "further" or #sign == 3 and "stronger" or "strongest"
        return label .. " (" .. emphasis .. (higher and " increase)" or " decrease)")
    end
    return line
end

local function appendNote(lines, note)
    if not note then return end
    local entry = "- " .. note
    for _, line in ipairs(lines) do if line:lower() == entry:lower() then return end end
    lines[#lines + 1] = entry
end

local function addNotes(lines, text, decorate)
    if not text then return end
    local bullets, fallback = {}, {}
    for raw in text:gsub("<[Ll][Ii][Nn][Ee]>", "\n"):gmatch("[^\r\n]+") do
        local line = plain(raw)
        local bullet = line:match("^o%s+(.+)$") or line:match("^[-*]%s+(.+)$") or line:match("^•%s+(.+)$")
        if bullet then bullets[#bullets + 1] = bullet
        elseif line ~= "" then fallback[#fallback + 1] = line end
    end
    -- First-rank notes can introduce their actual bulleted effects with prose.
    local before = #lines
    for _, line in ipairs(#bullets > 0 and bullets or fallback) do
        line = decorate and decorate(line) or noteText(line)
        if line ~= "" and #line <= 160 then appendNote(lines, line) end
        if #lines - before >= 4 then break end
    end
end

local function addRankNotes(lines, skill, rank, native, verified)
    local prefix = skill == "Yoga" and "UI_LSHS_Yoga" or "UI_LSPerk_Meditation"
    local stem = prefix .. "_" .. rank
    local function decorate(line) return noteText(line, skill, verified) end
    addNotes(lines, native or rawText(stem) or rawText(prefix .. rank), decorate)
    if safe(isClient) == true then
        addNotes(lines, rawText(stem .. "_mp") or rawText(prefix .. rank .. "_mp"), decorate)
    end
end

local function playerData(player)
    return safe(function()
        if not player or not player.hasModData or not player:hasModData() then return nil end
        local data = player:getModData()
        return type(data) == "table" and data or nil
    end)
end

local function moodle(data, name)
    local moodles = data and data.LSMoodles
    local value = type(moodles) == "table" and moodles[name]
    return type(value) == "table" and value or nil
end

-- Do not infer relief from a rank or countdown. This indicates only a tier
-- currently capable of a native effect, not whether a stat has changed.
function Info.activeStrong(player)
    if not supported() or not (SandboxVars and SandboxVars.Text and SandboxVars.Text.DividerMeditationNew) then return false end
    local current=moodle(playerData(player),"MindfulState")
    local value=current and current.Value
    return type(value)=="number" and value>=Facts.mindfulnessActivation[3] and value<=1
end

local function real(number)
    return type(number) == "number" and number == number and math.abs(number) < math.huge
end

local function settings(skill)
    local value = type(SandboxVars) == "table" and SandboxVars[skill]
    return type(value) == "table" and value or {}
end

local function yogaSetting()
    local value = settings("Yoga").YogaXPMultiplier
    if real(value) and value > 0 and value ~= 1 then return "Yoga XP setting: x" .. tostring(value) end
end

local function lessonActive(data, skill)
    local lesson = moodle(data, "WasTaughtSkill")
    return lesson and data.WasTaughtLast == skill and real(lesson.Value) and lesson.Value >= 0.2
end

mindfulName = function(index)
    local native = rawText("Moodles_MindfulState_L" .. index)
    return native and plain(native) or ({"Mindfulness","Strong Mindfulness","Perfect Mindfulness"})[index]
end

local function hasTrait(player, name)
    return safe(function()
        local trait = CharacterTrait and CharacterTrait[name]
        if player and trait and player.hasTrait then return player:hasTrait(trait) end
    end)
end

local function durationFor(player, level)
    local row = Facts.duration[level]
    local mode = settings("Meditation").MindfulnessDuration
    if not real(mode) or mode % 1 ~= 0 then return nil end
    local scale = Facts.durationScale[mode]
    if not row or not scale then return nil end
    local disciplined = hasTrait(player, "DISCIPLINED")
    if type(disciplined) ~= "boolean" then return nil end
    return row[disciplined and 2 or 1] * scale
end

local function readableTime(minutes, compact)
    -- Kahlua's tostring can include a decimal for a whole number.
    minutes = math.floor(minutes + 0.5)
    if minutes < 60 then return string.format("%dm", minutes) end
    local hours, rest = math.floor(minutes / 60), minutes % 60
    if compact then return string.format("%dh%02dm", hours, rest) end
    return hours .. "h" .. (rest > 0 and (" " .. rest .. "m") or "")
end

local function zenRange(rank, compact)
    local row = real(rank) and rank > 0 and Facts.yoga[rank]
    local ticks = row and Facts.zenTicks[row[2]]
    if ticks then
        return readableTime((ticks - 1) * Facts.zenTickMinutes, compact) .. (compact and "-" or " to ")
            .. readableTime(ticks * Facts.zenTickMinutes, compact)
    end
end

local function number(value)
    return (string.format("%.2f", math.floor(value * 100 + 0.5) / 100):gsub("0+$", ""):gsub("%.$", ""))
end

local function addDelta(lines, label, before, after, units)
    if before ~= nil and after ~= nil and before ~= after then
        appendNote(lines, label .. ": " .. before .. changeSeparator .. after .. (units or ""))
    end
end

local function percent(value) return number(value) .. "%" end

local function yogaRankChanges(lines, rank)
    local previous, row = Facts.yoga[rank - 1], Facts.yoga[rank]
    local options = settings("Yoga")
    local oldZen, zen = zenRange(rank - 1, true), zenRange(rank, true)
    addDelta(lines, "Zen duration", oldZen or "locked", zen, " in-game after a successful finish")
    if Facts.yogaNewPoses[rank] then
        local pool = 0
        for level = 0, rank - 1 do pool = pool + (Facts.yogaNewPoses[level] or 0) end
        local added = Facts.yogaNewPoses[rank]
        addDelta(lines, "Pose pool", pool, pool + added, " (+" .. added .. " " .. row[1] .. ")")
    end
    addDelta(lines, "Pose target per session", previous[3], row[3])
    addDelta(lines, "Completion bonus cap", Facts.yogaCompletionCap[rank - 1], Facts.yogaCompletionCap[rank],
        rank == 10 and " base XP (Fitness/Nimble only at rank 10)" or " base XP")
    if row[2] ~= previous[2] then
        local strength = Facts.yogaStrengthScale[options.StrengthMultiplier] or 1
        local function relief(label, coefficient, formatter)
            return label .. " " .. formatter(previous[2] * coefficient) .. changeSeparator .. formatter(row[2] * coefficient)
        end
        appendNote(lines, "Relief per pose (no aids): " .. relief("stress", Facts.yogaRelief[1] * 100, percent)
            .. ", " .. relief("pain", Facts.yogaRelief[2] * strength, number)
            .. ", " .. relief("stiffness", Facts.yogaRelief[3] * strength, number))
    end
    local fail = Facts.yogaFallScale[options.FailChance] or 1
    local function failChance(level, scale)
        return math.max(0, math.floor(math.min(Facts.yogaFallCap, Facts.yogaFallRoll[level] * scale)) - Facts.yogaFallRankOffset * level)
    end
    local maxScale = 0
    for _, scale in ipairs(Facts.yogaFallScale) do maxScale = math.max(maxScale, scale) end
    local oldFail, newFail = failChance(rank - 1, fail), failChance(rank, fail)
    local fallProof = failChance(rank - 1, maxScale) > 0 and failChance(rank, maxScale) == 0
    if oldFail ~= newFail then
        addDelta(lines, "Max fall chance per roll", percent(oldFail), percent(newFail),
            fallProof and " (new sessions: zero on every setting)" or "")
    elseif fallProof then
        appendNote(lines, "New sessions: 0% fall chance on every setting")
    end
    if rank == 10 then
        appendNote(lines, "Early-stop penalty: Yoga XP and Zen deductions" .. changeSeparator .. "none")
        if safe(isClient) == true then appendNote(lines, "Can teach Yoga to another survivor in multiplayer") end
    end
end

function Info.yogaTooltip(player, progress, rank)
    if not real(rank) or rank % 1 ~= 0 or rank < 1 or rank > 10 then return "" end
    local lines, verified = {}, supported()
    if verified then yogaRankChanges(lines, rank) end
    addRankNotes(lines, "Yoga", rank, nil, verified)
    if progress and not progress.capped then
        local multiplier = yogaSetting()
        if multiplier then lines[#lines + 1] = multiplier end
        if verified and lessonActive(playerData(player), "Yoga") then
            lines[#lines + 1] = "Yoga lesson boost active"
        end
    end
    return #lines > 0 and (gap .. table.concat(lines, lineGap)) or ""
end

local function addSessionChange(lines, rank, player)
    local before, after = Facts.meditationLengths[rank - 1], Facts.meditationLengths[rank]
    if before == after then return end
    local day = safe(function() return getGameTime():getMinutesPerDay() end)
    local instant = safe(function() return player:isTimedActionInstant() end)
    if instant == true then return end
    if real(day) and day > 0 then
        -- Stock ISReadABook/ISResearchRecipe convert each world minute to
        -- two times the live minutes-per-day in BaseAction time units.
        -- These are base limits, before illness/injury/temperature modifiers.
        local old = readableTime(before / (day * 2), true)
        local new = readableTime(after / (day * 2), true)
        if old ~= new and old ~= "0m" then
            addDelta(lines, "Base session limit (approx)", old, new, " in-game")
            return
        end
    end
    addDelta(lines, "Base session limit", before, after, " action ticks")
end

local function meditationRankChanges(lines, rank, player)
    local options = settings("Meditation")
    local disc = hasTrait(player, "DISCIPLINED")
    local traitSlot = disc == true and 2 or 1
    local buffEnabled = settings("Text").DividerMeditationNew ~= false
    local duration, previous = Facts.duration[rank], Facts.duration[rank - 1]
    if buffEnabled and duration then
        appendNote(lines, unlockNote(rank))
        local scale = Facts.durationScale[options.MindfulnessDuration]
        local scope = not scale and " (default setting)" or type(disc) ~= "boolean" and " (no trait assumed)" or ""
        scale = scale or 1
        addDelta(lines, "Mindfulness duration", previous and readableTime(previous[traitSlot] * scale, true) or "locked",
            readableTime(duration[traitSlot] * scale, true), " in-game per tier" .. scope)
    end
    addSessionChange(lines, rank, player)
    if rank == Facts.meditationUnlocks[1] and not options.KeepBags then
        appendNote(lines, "Worn bags: removed" .. changeSeparator .. "can stay on")
    end
    if buffEnabled and duration then
        local scale = Facts.mindfulnessEffectScale[options.EffectMultiplier] or 1
        local effect = Facts.mindfulnessEffect
        local before, after = (previous and effect[rank - 1][traitSlot] or 0) * scale, effect[rank][traitSlot] * scale
        local relief = Facts.mindfulnessRelief
        addDelta(lines, "Mindfulness stress/panic relief", number(before * relief[1]), number(after * relief[1]), " points per in-game minute")
        if rank >= Facts.meditationUnlocks[2] then
            if rank == Facts.meditationUnlocks[2] then before = 0 end
            local function hunger(value)
                local precision = 10 ^ relief[4]
                return percent(-math.floor(-value * relief[3] * precision + 0.5) * 100 / precision)
            end
            appendNote(lines, "Strong relief per in-game minute: pain " .. number(before * relief[2]) .. changeSeparator .. number(after * relief[2])
                .. ", hunger " .. hunger(before) .. changeSeparator .. hunger(after))
        end
    else
        local t = Facts.meditationEarlyStress
        local scale = Facts.meditationStrengthScale[options.StrengthMultiplier] or 1
        local trait = disc and t[1] or hasTrait(player, "COUCHPOTATO") and t[2] or 0
        local function calm(level) return percent(100 * t[6] * ((2 + trait + level / t[3]) * scale + t[5])) end
        addDelta(lines, "Early stress relief (boredom at most " .. t[4] .. ")", calm(rank - 1), calm(rank), " per tick")
    end
    if rank == 10 and safe(isClient) == true then appendNote(lines, "Can teach Meditation to another survivor in multiplayer") end
end

local function compactMeditation(bar, cell)
    local perk, message = bar.perk, bar.message
    if not perk or not real(cell) or cell < 0 or cell > 9 or cell % 1 ~= 0 or type(message) ~= "string" then return end
    local id = perk.getId and perk:getId()
    if id ~= "Meditation" then return end
    local rank, key = cell + 1, "IGUI_perks_" .. id .. "_Description"
    local native = rawText(key) or key
    local first, last = message:find(gap .. native, 1, true)
    if not first or message:find(gap, 1, true) ~= first then return end -- only the leading stock description block
    local suffix = message:sub(last + 1)
    local rankText = rawText(key .. rank)
    if rankText then
        local expected = gap .. rankText
        if suffix:sub(1, #expected) ~= expected then return end
        suffix = suffix:sub(#expected + 1)
    end
    -- Only replace recognized stock description sections, not unrelated lines.
    if suffix ~= "" and suffix:sub(1, #lineGap) ~= lineGap and suffix:sub(1, #gap) ~= gap then return end
    local lines, verified = {}, supported()
    if verified then meditationRankChanges(lines, rank, bar.char) end
    addRankNotes(lines, "Meditation", rank, rankText, verified)
    if #lines == 0 then return end
    local effect = #lines > 0 and (gap .. table.concat(lines, lineGap)) or ""
    return message:sub(1, first - 1) .. effect .. suffix
end

function Info.installMeditationTooltip(class)
    if not class or type(class.updateTooltip) ~= "function" or Info.meditationClass == class then return end
    local previous = class.updateTooltip
    class.updateTooltip = function(bar, cell, ...)
        local function finish(...)
            local message = safe(compactMeditation, bar, cell)
            if message then bar.message = message end
            return ...
        end
        return finish(previous(bar, cell, ...))
    end
    Info.meditationClass = class
end

local function mindfulnessAmounts(rank, tier, traitSlot, settingScale, healFactor)
    local row = Facts.mindfulnessEffect[rank]
    if not row or not tier then return end
    local strength = row[traitSlot] * settingScale
    local coefficients = Facts.mindfulnessRelief
    local result = {stress=strength * coefficients[1], panic=strength * coefficients[1],
        nicotine=strength * Facts.mindfulnessNicotine * 100}
    if tier >= 2 then
        local precision = 10 ^ coefficients[4]
        result.pain = strength * coefficients[2]
        result.hunger = -math.floor(-strength * coefficients[3] * precision + 0.5) * 100 / precision
    end
    if tier >= 3 then
        result.healing = healFactor * (rank == Facts.meditationUnlocks[3] and Facts.mindfulnessHealing[traitSlot + 1] or 1)
    end
    return result
end

local function mindfulnessTier(value)
    if not real(value) then return end
    local native = Facts.mindfulnessActivation
    for tier = 3, 1, -1 do
        if value >= native[tier + 1] then return tier end
    end
end

local function perkLevel(player, key)
    return safe(function()
        local perk = Perks and Perks[key]
        if player and perk then return player:getPerkLevel(perk) end
    end)
end

function Info.zenXPForPlayer(player, tier)
    local meditation, pose = Info.zenEffects(tier)
    local caps = Facts.zenExperience
    if meditation and (perkLevel(player, "Meditation") or 0) >= caps[3] then meditation = nil end
    -- Fitness and Nimble still benefit from successful Yoga poses at Yoga cap.
    if pose and (perkLevel(player, "Fitness") or 0) >= caps[5] and (perkLevel(player, "Nimble") or 0) >= caps[6] then
        local yoga = safe(function() return HiddenSkills.getLevel(player, "Yoga") end)
        if real(yoga) and yoga >= caps[4] then pose = nil end
    end
    return meditation, pose
end

function Info.mindfulnessHover(player)
    if not supported() or not settings("Text").DividerMeditationNew then return end
    local rank, disciplined = perkLevel(player, "Meditation"), hasTrait(player, "DISCIPLINED")
    if not real(rank) or rank < Facts.mindfulnessActivation[1] or type(disciplined) ~= "boolean" then return end
    local current = moodle(playerData(player), "MindfulState")
    -- Lifestyle's generic HUD tier need not match the effect thresholds.
    -- Use the unrounded Value as the native per-minute function does.
    local tier = mindfulnessTier(current and current.Value)
    if not tier then return end
    local options = settings("Meditation")
    local heal = real(options.HealFactor) and options.HealFactor or Facts.mindfulnessHealing[1]
    local effects = mindfulnessAmounts(rank, tier, disciplined and 2 or 1,
        Facts.mindfulnessEffectScale[options.EffectMultiplier] or 1, heal)
    if not effects then return end
    local lines = {"Per in-game minute (before stat limits):",
        "- Stress: -" .. number(effects.stress) .. " percentage points",
        "- Panic: -" .. number(effects.panic) .. " points"}
    if hasTrait(player, "SMOKER") == true then
        lines[#lines+1] = "- Nicotine withdrawal: -" .. number(effects.nicotine) .. " percentage points"
    end
    if effects.pain then
        lines[#lines+1] = "- Pain: -" .. number(effects.pain) .. " points"
        lines[#lines+1] = "- Hunger: -" .. number(effects.hunger) .. " percentage points"
    end
    if effects.healing and effects.healing ~= 0 then
        lines[#lines+1] = "- Health: " .. (effects.healing > 0 and "+" or "") .. number(effects.healing)
            .. " points shared across damaged body parts"
    end
    return lines, effects
end

local function mindfulnessRates(lines, heading, rank, tier, traitSlot, settingScale, healFactor)
    local effects = mindfulnessAmounts(rank, tier, traitSlot, settingScale, healFactor)
    if not effects then return end
    lines[#lines + 1] = heading .. ": Relief per in-game minute"
    if math.abs(effects.stress - effects.nicotine) < 0.00001 then
        lines[#lines + 1] = "Stress and nicotine withdrawal: -" .. number(effects.stress) .. " percentage points each"
    else
        lines[#lines + 1] = "Stress: -" .. number(effects.stress) .. " percentage points"
        lines[#lines + 1] = "Nicotine withdrawal: -" .. number(effects.nicotine) .. " percentage points"
    end
    lines[#lines + 1] = "Panic: -" .. number(effects.panic) .. " points on the 0-100 scale"
    if effects.pain then
        lines[#lines + 1] = "Pain: -" .. number(effects.pain) .. " points on the 0-100 scale"
        lines[#lines + 1] = "Hunger: -" .. number(effects.hunger) .. " percentage points"
    end
    if effects.healing then
        lines[#lines + 1] = "Healing: +" .. number(effects.healing) .. " health points shared across damaged body parts"
    end
end

function Info.guide(player, progress)
    if not supported() then
        local notes = {}
        addNotes(notes, rawText("IGUI_perks_Meditation_Description"))
        return {
            {title="Skill details", subtitle="Lifestyle version not verified", lines={
                "Version: Exact effect and duration details are not verified for this Lifestyle version.",
                "Rank notes: Hover a box in Character Info > Skills to see the available Lifestyle notes.",
            }},
            {title="Meditation",subtitle="Notes from your installed version",lines=notes},
        }
    end

    local data = playerData(player)
    local meditationOptions = settings("Meditation")
    local meditation = {
        "Direct relief: Reduces stress and, for smokers, nicotine withdrawal while you meditate. It can also ease unhappiness. The rate varies with focus, mood, traits and settings.",
        "Trade-offs: Boredom and neck pain can build. Boredom above 30/100 blocks starting, and high boredom reduces Meditation XP.",
        "Focus and traits: Uninterrupted practice builds focus. Disciplined reaches Mindfulness sooner; Couch Potato makes Meditation less effective.",
        "Endurance: Recovery makes room for normal rest when you are idle. Lifestyle meditation does not directly refill endurance.",
    }
    if meditationOptions.KeepBags then
        meditation[#meditation + 1] = "Bags: Your settings keep worn bags on at all ranks. Heavy items in your hands may still be put down."
    else
        meditation[#meditation + 1] = "Bags: Worn bags can stay on from rank 3. Heavy items in your hands may still be put down."
    end

    local unlocks = Facts.meditationUnlocks
    local mindful = {
        "Rank " .. unlocks[1] .. " | " .. mindfulName(1) .. ": Long Meditation unlocks relief from stress, panic and nicotine withdrawal.",
        "Rank " .. unlocks[2] .. " | " .. mindfulName(2) .. ": Meditate with " .. mindfulName(1) .. " active. It also reduces pain and hunger, without adding calories or hydration.",
        "Rank " .. unlocks[3] .. " | " .. mindfulName(3) .. ": Meditate with " .. mindfulName(2) .. " active. It also restores general health by healing damaged body parts.",
        "After you stop: The effects continue and fade one tier at a time. The game may apply accumulated stat changes in batches.",
    }
    local rank = progress and progress.meditation and progress.meditation.level
    local minutes = durationFor(player, rank)
    local disabled = settings("Text").DividerMeditationNew == false
    if disabled then
        mindful[#mindful + 1] = "Current settings: Mindfulness mood effects are disabled."
    elseif minutes then
        mindful[#mindful + 1] = "Current duration: " .. readableTime(minutes, true) .. " in-game per tier at rank " .. rank
            .. " with your current settings and traits."
    else
        local first, last = Facts.duration[unlocks[1]], Facts.duration[unlocks[3]]
        mindful[#mindful + 1] = "Standard duration: " .. readableTime(first[1], true) .. "-" .. readableTime(last[1], true)
            .. " in-game per tier across ranks, or " .. readableTime(first[2], true) .. "-" .. readableTime(last[2], true) .. " with Disciplined."
    end
    local disc = hasTrait(player, "DISCIPLINED")
    local traitSlot = disc == true and 2 or 1
    local configuredScale = Facts.mindfulnessEffectScale[meditationOptions.EffectMultiplier]
    local configuredHeal = meditationOptions.HealFactor
    if not real(configuredHeal) or configuredHeal < 0 then configuredHeal = nil end
    local scale, heal = configuredScale or 1, configuredHeal or Facts.mindfulnessHealing[1]
    if not disabled then
        local scope = disc == true and "Disciplined" or disc == false and "no Disciplined" or "trait not available; assuming no Disciplined"
        if not configuredScale or not configuredHeal then scope = scope .. "; defaults used where settings are unavailable" end
        mindful[#mindful + 1] = "Rates per in-game minute: Values below use " .. scope
            .. ". These are rates, not totals. For example, 9 percentage points takes a stat from 30% to 21%."
        for tier, unlock in ipairs(unlocks) do
            mindfulnessRates(mindful, "Rank " .. unlock .. " | " .. mindfulName(tier), unlock,tier,traitSlot,scale,heal)
        end
    end
    local current = moodle(data, "MindfulState")
    local value = current and current.Value
    local tier = mindfulnessTier(value)
    if not disabled and tier then
        local remaining = data.MindfulnessMinutes
        mindful[#mindful + 1] = "Active now: " .. mindfulName(tier) .. (real(remaining) and remaining > 0
            and (" | " .. readableTime(math.ceil(remaining), true) .. " in-game left in this tier.") or " | No current countdown available.")
        if Facts.mindfulnessEffect[rank] then
            mindfulnessRates(mindful, "Active effects", rank,tier,traitSlot,scale,heal)
        end
    end

    local groups, last = {}, nil
    for level = 0, 10 do
        local group = Facts.yoga[level][1]
        if group ~= last then groups[#groups + 1] = group .. " at " .. level; last = group end
    end
    local yoga = {
        "Relief: Each successful pose and the final rest reduce boredom by 5. Stress, pain and stiffness relief improve with Yoga pose tiers.",
        "XP: Successful poses can award Yoga, Fitness and Nimble XP. Failed poses earn no pose XP.",
        "Getting started: Stand before starting. Lifestyle checks your synced endurance, embarrassment and mat settings.",
        "Waiting on endurance: In Yoga training, AutoMindful can use Meditation while Lifestyle blocks Yoga for low endurance. It gives Yoga back the turn as soon as it can start.",
        "Pose pool: " .. table.concat(groups, ", ") .. ". Linked poses can extend a session; a fall can end it early.",
        "Early stops: Below rank 10, stopping after earning pose XP can remove Yoga XP and shorten an existing Zen.",
    }
    local setting = yogaSetting()
    if setting then yoga[#yoga + 1] = setting .. " (current sandbox; separate from Zen and lessons)." end

    -- These are three different native mechanisms, not one global XP bonus.
    -- LSMeditateAction:adjustStatsGetChanges, LSYogaAction:grantXP/fitnessBonus.
    local zenMeditation, zenPose = {}, {}
    for i = 1, 4 do
        local multiplier, addend = Info.zenEffects(i)
        zenMeditation[i], zenPose[i] = string.format("x%.1f", multiplier), string.format("%d", addend)
    end
    local zen = {
        "How to earn: Finish Yoga successfully at Yoga rank 1 or higher. Your starting rank sets the initial Zen strength.",
        "Meditation XP: Zen tiers 1-4 multiply the action's base Meditation XP by "
            .. table.concat(zenMeditation, ", ", 1, 3) .. " or " .. zenMeditation[4] .. ". Mood and game XP settings still apply.",
        "Yoga pose XP: Zen tiers 1-4 add " .. table.concat(zenPose, ", ")
            .. " to the pose's XP factor respectively. Successful poses can award Yoga, Fitness and Nimble XP. This is not a general multiplier for those skills.",
        "Regular workouts: Lifestyle raises the exercise's XP setting. Build 42 can keep an already-loaded value, so extra workout XP is not guaranteed.",
        "Fade: Zen weakens every 10 in-game minutes. There is no separate built-in countdown.",
    }
    local yogaRank = progress and progress.yoga and progress.yoga.level
    local zenPeriod = zenRange(yogaRank)
    if zenPeriod then
        zen[#zen + 1] = "Started at rank " .. yogaRank .. ": about " .. zenPeriod .. " in-game after successful Yoga."
    end
    local currentZen = moodle(data, "Zen")
    local zenTier = currentZen and currentZen.Level
    if real(zenTier) and zenTier % 1 == 0 and zenTier >= 1 and zenTier <= 4 then
        local meditationXP, poseBonus = Info.zenEffects(zenTier)
        if meditationXP then
            zen[#zen + 1] = "Active now: Zen tier " .. zenTier .. " | Meditation XP x" .. string.format("%.1f", meditationXP)
                .. " | Yoga pose XP factor +" .. poseBonus .. "."
        end
    end
    local lesson = data and data.WasTaughtLast
    local lessonLines = {
        "Multiplayer: A survivor at rank 10 can teach that skill. The temporary XP boost applies only to the taught skill.",
    }
    local lessonProgress = type(lesson) == "string" and progress and progress[lesson:lower()]
    if (lesson == "Yoga" or lesson == "Meditation") and lessonActive(data, lesson)
        and not (lessonProgress and lessonProgress.capped) then
        lessonLines[#lessonLines + 1] = "Active now: " .. lesson .. " lesson boost."
    end
    return {
        {title="Meditation", subtitle="The floor-seated practice", lines=meditation},
        {title="Mindfulness", subtitle="The lasting effect of Meditation", lines=mindful},
        {title="Yoga", subtitle="Poses for relief and training", lines=yoga},
        {title="Zen", subtitle="The temporary XP boost from Yoga", lines=zen},
        {title="Lessons", subtitle="Learn from another survivor", lines=lessonLines},
    }
end

Info.supported = supported
return Info
