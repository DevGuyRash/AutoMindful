-- Display-only advice from the dependent Lifestyle mod. Never construct a
-- timed action, read another survivor, initialize moodles, or grant any XP.
local Facts = require "AutoMindful/WellnessFacts"
local Info = {}
local gap = " <LINE><LINE> "
local lineGap = " <LINE> "
local zenDuration

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

local function rawText(key)
    local translate = getTextOrNull or getText
    local value = safe(translate, key)
    if type(value) == "string" and #value <= 2048 and value ~= key and value:match("%S") then return value end
end

local function plain(raw)
    return raw:gsub("%b<>", ""):gsub("[<>%c]", ""):match("^%s*(.-)%s*$")
end

local function noteText(line, yogaRank, canDescribe)
    if line:match("^[-+]+$") then return "" end
    local sign, label = line:match("^([+]+)%s+(.+)$")
    if not sign then sign, label = line:match("^(-+)%s+(.+)$") end
    local key = (label or line):lower()
    local higher = sign and sign:sub(1, 1) == "+"
    if yogaRank and ((higher and key == "zen state duration") or
        key == "unlocked zen state for a short time after performing yoga") then
        local range = canDescribe() and zenDuration(yogaRank)
        if range then return "Zen after successful Yoga: " .. range .. " in-game min" end
        return higher and "Zen lasts longer" or line
    end
    if higher and key == "pose sequence limit" then
        local row = yogaRank and canDescribe() and Facts.yoga[yogaRank]
        return row and ("Nominal pose limit: " .. row[3]) or "Longer pose sequences"
    end
    if higher and key == "action duration" then return "Longer meditation sessions" end
    if sign and not higher and key == "neck pain rate" then return "Neck pain builds more slowly" end
    if sign and not higher and key == "boredom rate" then return "Boredom builds more slowly" end
    if sign then
        if #sign == 1 then return label .. (higher and " (increases)" or " (decreases)") end
        local emphasis = #sign == 2 and "further" or #sign == 3 and "stronger" or "strongest"
        return label .. " (" .. emphasis .. (higher and " increase)" or " decrease)")
    end
    return line
end

local function addNotes(lines, seen, text, decorate)
    if not text then return end
    local bullets, fallback = {}, {}
    for raw in text:gsub("<[Ll][Ii][Nn][Ee]>", "\n"):gmatch("[^\r\n]+") do
        local line = plain(raw)
        local bullet = line:match("^o%s+(.+)$") or line:match("^[-*]%s+(.+)$") or line:match("^•%s+(.+)$")
        if bullet then bullets[#bullets + 1] = bullet
        elseif line ~= "" then fallback[#fallback + 1] = line end
    end
    -- First-rank notes can introduce their actual bulleted effects with prose.
    for _, line in ipairs(#bullets > 0 and bullets or fallback) do
        line = decorate and decorate(line) or noteText(line)
        local key = line:lower()
        if line ~= "" and not seen[key] and #line <= 160 and #lines < 4 then
            seen[key] = true
            lines[#lines + 1] = "- " .. line
        end
    end
end

local function rankNotes(skill, rank, native, decorate)
    local prefix = skill == "Yoga" and "UI_LSHS_Yoga" or "UI_LSPerk_Meditation"
    local stem = prefix .. "_" .. rank
    local lines, seen = {}, {}
    addNotes(lines, seen, native or rawText(stem) or rawText(prefix .. rank), decorate)
    if safe(isClient) == true then
        addNotes(lines, seen, rawText(stem .. "_mp") or rawText(prefix .. rank .. "_mp"), decorate)
    end
    return lines
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

local function mindfulName(index)
    local native = rawText("Moodles_MindfulState_L" .. index)
    return native and plain(native) or ({"Mindfulness","Strong Mindfulness","Perfect Mindfulness"})[index]
end

local function durationFor(player, level)
    local row = Facts.duration[level]
    local mode = settings("Meditation").MindfulnessDuration
    if not real(mode) or mode % 1 ~= 0 then return nil end
    local scale = Facts.durationScale[mode]
    if not row or not scale then return nil end
    local disciplined = safe(function()
        if player and CharacterTrait and CharacterTrait.DISCIPLINED and player.hasTrait then
            return player:hasTrait(CharacterTrait.DISCIPLINED)
        end
    end)
    if type(disciplined) ~= "boolean" then return nil end
    return row[disciplined and 2 or 1] * scale
end

zenDuration = function(rank)
    local row = real(rank) and rank > 0 and Facts.yoga[rank]
    local ticks = row and Facts.zenTicks[row[2]]
    if ticks then return ((ticks - 1) * Facts.zenTickMinutes) .. "-" .. (ticks * Facts.zenTickMinutes) end
end

function Info.yogaTooltip(player, progress, rank)
    local verified
    local function canDescribe()
        if verified == nil then verified = supported() end
        return verified
    end
    local lines = rankNotes("Yoga", rank, nil, function(line)
        return noteText(line, rank, canDescribe)
    end)
    -- Lifestyle has no localized note on some ranks. Keep a small source-
    -- checked factual fallback, not an exact chance guess or a copied note.
    local row = Facts.yoga[rank]
    if #lines == 0 and row and canDescribe() then
        lines[1] = "- " .. row[1] .. " poses; nominal sequence: " .. row[3]
        if rank >= Facts.noFallRank then lines[2] = "- Avoids the native pose-fall roll" end
    end
    if not progress.capped then
        local multiplier = yogaSetting()
        if multiplier then lines[#lines + 1] = multiplier end
        if lessonActive(playerData(player), "Yoga") and canDescribe() then
            lines[#lines + 1] = "Yoga lesson boost active"
        end
    end
    return #lines > 0 and (gap .. table.concat(lines, lineGap)) or ""
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
    local lines = rankNotes("Meditation", rank, rankText)
    if #lines == 0 then
        if supported() then
            for tier, unlock in ipairs(Facts.meditationUnlocks) do
                if rank == unlock then
                    lines[1] = "- " .. mindfulName(tier) .. " available through meditation"
                    if tier == 1 then lines[2] = "- Worn bags can stay on" end
                    break
                end
            end
        elseif native ~= key then
            return -- no verified detail to replace the named upstream description
        end
    end
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

function Info.guide(player, progress)
    if not supported() then
        local notes = {}
        addNotes(notes, {}, rawText("IGUI_perks_Meditation_Description"))
        return {
            {title="Skill details", lines={
                "Rank tooltips use the available notes from Lifestyle. Hover a box in Character Info > Skills.",
                "Exact effect and duration details are not verified for this Lifestyle version.",
            }},
            {title="Meditation",lines=notes},
        }
    end

    local data, lines = playerData(player), {}
    local unlocks = Facts.meditationUnlocks
    lines[1] = "Meditate long enough to earn each tier. Higher tiers add to the previous effects, then fade one tier at a time."
    lines[2] = "Rank " .. unlocks[1] .. " | " .. mindfulName(1) .. ": reduces stress, panic and nicotine withdrawal."
    lines[3] = "Rank " .. unlocks[2] .. " | " .. mindfulName(2) .. ": also reduces pain and hunger."
    lines[4] = "Rank " .. unlocks[3] .. " | " .. mindfulName(3) .. ": also restores general health."
    local rank = progress and progress.meditation and progress.meditation.level
    local minutes = durationFor(player, rank)
    if minutes then
        lines[#lines + 1] = "At rank " .. rank .. ": " .. (minutes % 1 == 0 and string.format("%.0f", minutes) or tostring(minutes)) .. " in-game min per tier with your current settings and trait; not total duration."
    else
        local first, last = Facts.duration[unlocks[1]], Facts.duration[unlocks[3]]
        lines[#lines + 1] = "At standard settings: " .. first[1] .. "-" .. last[1] .. " in-game min per tier across supported ranks ("
            .. first[2] .. "-" .. last[2] .. " with Disciplined). Server settings can shorten or lengthen each tier."
    end
    local current = moodle(data, "MindfulState")
    local value = current and current.Value
    if real(value) and value >= 0.2 then
        local tier = value >= 0.6 and 3 or value >= 0.4 and 2 or 1
        local remaining = data.MindfulnessMinutes
        lines[#lines + 1] = "Active: " .. mindfulName(tier) .. (real(remaining) and remaining > 0
            and (" | " .. math.ceil(remaining) .. " in-game min remaining in this tier.") or " | No current countdown available.")
    end

    local groups, last = {}, nil
    for level = 0, 10 do
        local group = Facts.yoga[level][1]
        if group ~= last then groups[#groups + 1] = group .. " at " .. level; last = group end
    end
    local yoga = {
        "Start standing. Successful poses reduce boredom, stress, pain and stiffness, and can award Yoga, Fitness and Nimble XP. Failed poses give no pose XP.",
        "The pose pool grows as ranks rise: " .. table.concat(groups, ", ") .. ". Linked poses can extend a sequence.",
        "At rank " .. Facts.noFallRank .. ", the checked version's native pose-fall roll can no longer trigger. Interruptions still matter.",
        "A deployed mat can help and may be required by sandbox settings. Stopping early can remove earned Yoga XP.",
    }
    local setting = yogaSetting()
    if setting then yoga[#yoga + 1] = setting .. " (before pose, Zen or lesson effects)." end

    local zen = {
        "A successful Yoga finish grants Zen if your Yoga rank is at least 1 when you finish.",
        "Zen can increase later Meditation and Yoga XP, and can improve regular exercise XP. That's separate from the Fitness and Nimble XP a Yoga pose itself can award.",
        "Zen fades on ten-minute in-game ticks. Starting strength depends on Yoga rank. Early Yoga cancellation can shorten it; there is no separate built-in countdown.",
    }
    local yogaRank = progress and progress.yoga and progress.yoga.level
    local zenPeriod = zenDuration(yogaRank)
    if zenPeriod then
        zen[#zen + 1] = "Started at rank " .. yogaRank .. ": normally " .. zenPeriod .. " in-game min after successful Yoga."
    end
    local currentZen = moodle(data, "Zen")
    if currentZen and real(currentZen.Level) and currentZen.Level > 0 then zen[#zen + 1] = "Zen is active." end
    local lesson = data and data.WasTaughtLast
    local lessonLines = {
        "In multiplayer, Lifestyle lets a survivor with rank 10 teach that skill. Its temporary lesson boost applies only to the skill taught.",
    }
    local lessonProgress = type(lesson) == "string" and progress and progress[lesson:lower()]
    if (lesson == "Yoga" or lesson == "Meditation") and lessonActive(data, lesson)
        and not (lessonProgress and lessonProgress.capped) then
        lessonLines[#lessonLines + 1] = lesson .. " lesson boost active."
    end
    return {
        {title="Meditation", lines={
            "Use the normal floor-seated action. It reduces stress; boredom and neck pain can build, especially early on. Boredom above 30 prevents starting.",
            "Rank " .. unlocks[1] .. " keeps worn bags on; separate heavy-item rules still apply. Disciplined helps you reach Mindfulness sooner and extends its duration. Couch Potato makes meditation less effective.",
            "Rank hover keeps the actual stock XP and perk boost. More focus and less aversion can improve results; training doesn't set a fixed XP rate.",
        }},
        {title="Mindfulness", lines=lines},
        {title="Yoga", lines=yoga},
        {title="Zen", lines=zen},
        {title="Lessons", lines=lessonLines},
    }
end

return Info
