-- Display-only advice from the dependent Lifestyle mod. Never construct a
-- timed action, read another survivor, initialize moodles, or grant any XP.
local Facts = require "AutoMindful/WellnessFacts"
local Info = {}
local gap = " <LINE><LINE> "
local lineGap = " <LINE> "
local zenDuration, mindfulName

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

local function poseTarget(rank)
    local current, previous = Facts.yoga[rank], Facts.yoga[rank - 1]
    if not current or not previous or current[3] == previous[3] then return end
    return "Targets " .. current[3] .. " poses per session (was " .. previous[3] .. "); linked poses can extend it"
end

local function actionLength(rank)
    local current, previous = Facts.meditationLengths[rank], Facts.meditationLengths[rank - 1]
    if not current or not previous or current == previous then return end
    local more = (current - previous) * 100 / previous
    local rounded = math.floor(more + 0.5)
    local approximate = math.abs(more - rounded) > 0.01
    return "An uninterrupted meditation session can run " .. (approximate and "about " or "")
        .. rounded .. "% longer than at rank " .. (rank - 1)
end

local function unlockNote(rank)
    local unlocks = Facts.meditationUnlocks
    if rank == unlocks[1] then
        return "Unlocks " .. mindfulName(1) .. ": reduces stress, panic and nicotine withdrawal"
    elseif rank == unlocks[2] then
        return "Meditate while " .. mindfulName(1) .. " is active to reach " .. mindfulName(2) .. ": also reduces pain and hunger"
    elseif rank == unlocks[3] then
        return "Meditate while " .. mindfulName(2) .. " is active to reach " .. mindfulName(3) .. ": also restores health"
    end
end

local function noteText(line, skill, rank, canDescribe)
    if line:match("^[-+]+$") then return "" end
    local sign, label = line:match("^([+]+)%s+(.+)$")
    if not sign then sign, label = line:match("^(-+)%s+(.+)$") end
    local key = (label or line):lower()
    local higher = sign and sign:sub(1, 1) == "+"
    if skill == "Yoga" then
        if (higher and key == "zen state duration") or key == "unlocked zen state for a short time after performing yoga" then
            local range = canDescribe() and zenDuration(rank)
            if range then return "Zen lasts " .. range .. " after successful Yoga started at this rank" end
            return higher and "Zen lasts longer after successfully finishing Yoga" or line
        end
        if higher and key == "pose sequence limit" then
            return (canDescribe() and poseTarget(rank)) or "Each Yoga session targets more poses before it ends"
        end
        local group = key:match("^unlocked (%a+) level poses$")
        if group and canDescribe() and Facts.yogaNewPoses[rank] and Facts.yoga[rank][1]:lower() == group then
            return "Adds " .. Facts.yogaNewPoses[rank] .. " " .. group .. " poses to the Yoga rotation"
        end
        if key == "can teach yoga lessons" then return "Can teach Yoga to another survivor in multiplayer" end
    elseif skill == "Meditation" then
        if higher and key == "action duration" then
            return (canDescribe() and actionLength(rank)) or "An uninterrupted meditation session can run longer"
        end
        if (key == "unlocked new techniques") and canDescribe() then
            return actionLength(rank) or line
        end
        if (key == "mastered the ultimate technique" or
            key == "new mindfulness level, improved state can be achieved by meditating while under the effects of the previous level" or
            key == "unlocked mindfulness state, achieved during long meditative sessions, can grant a variety of bonuses")
            and canDescribe() then
            return unlockNote(rank) or line
        end
        if key == "xp rate is reduced by boredom" then return "High boredom reduces Meditation XP" end
        if key == "can meditate while wearing backpack and bags" then return "Can start meditation without removing worn bags" end
        if key == "can teach meditation lessons" then return "Can teach Meditation to another survivor in multiplayer" end
        if sign and not higher and key == "neck pain rate" then return "Meditation can add less neck pain when it causes any" end
        if sign and not higher and key == "boredom rate" then return "Meditation can add less boredom per effect tick" end
    end
    if sign then
        if #sign == 1 then return label .. (higher and " (increases)" or " (decreases)") end
        local emphasis = #sign == 2 and "further" or #sign == 3 and "stronger" or "strongest"
        return label .. " (" .. emphasis .. (higher and " increase)" or " decrease)")
    end
    return line
end

local function appendNote(lines, note)
    if not note or #lines >= 4 then return end
    local entry = "- " .. note
    for _, line in ipairs(lines) do if line == entry then return end end
    lines[#lines + 1] = entry
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

mindfulName = function(index)
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

local function readableTime(minutes)
    if minutes < 60 then return minutes .. "m" end
    local hours, rest = math.floor(minutes / 60), minutes % 60
    return hours .. "h" .. (rest > 0 and (" " .. rest .. "m") or "")
end

zenDuration = function(rank)
    local row = real(rank) and rank > 0 and Facts.yoga[rank]
    local ticks = row and Facts.zenTicks[row[2]]
    if ticks then
        return "about " .. readableTime((ticks - 1) * Facts.zenTickMinutes) .. " to "
            .. readableTime(ticks * Facts.zenTickMinutes) .. " in-game"
    end
end

function Info.yogaTooltip(player, progress, rank)
    if not real(rank) or rank % 1 ~= 0 or rank < 1 or rank > 10 then return "" end
    local verified
    local function canDescribe()
        if verified == nil then verified = supported() end
        return verified
    end
    local lines = rankNotes("Yoga", rank, nil, function(line)
        return noteText(line, "Yoga", rank, canDescribe)
    end)
    if canDescribe() then
        local row, previous = Facts.yoga[rank], Facts.yoga[rank - 1]
        if row and previous and row[2] > previous[2] then
            appendNote(lines, "Successful poses ease more stress, pain and stiffness")
        end
        if #lines == 0 then
            appendNote(lines, poseTarget(rank))
            if #lines == 0 then
                local cap, old = Facts.yogaCompletionCap[rank], Facts.yogaCompletionCap[rank - 1]
                if cap and old and cap ~= old then
                    appendNote(lines, "Completion bonus capped at " .. cap .. " XP before multipliers (was " .. old .. "); the actual bonus varies")
                end
            end
        end
        if rank == Facts.noFallRank then appendNote(lines, "Even the hardest pose-fall roll cannot trigger") end
        if rank == 10 then appendNote(lines, "Stopping early no longer deducts Yoga XP or Zen") end
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
    local verified = supported()
    local lines = rankNotes("Meditation", rank, rankText, function(line)
        return noteText(line, "Meditation", rank, function() return verified end)
    end)
    if verified then
        if #lines == 0 then appendNote(lines, unlockNote(rank)) end
        if Facts.duration[rank] then
            local current = durationFor(bar.char, rank)
            local previous = durationFor(bar.char, rank - 1)
            local scope = " with current settings"
            if not current then
                scope = " at standard settings"
                current = Facts.duration[rank][1]
                previous = Facts.duration[rank - 1] and Facts.duration[rank - 1][1]
            end
            local before = previous and (" (was " .. previous .. ")") or ""
            appendNote(lines, current .. " in-game min per Mindfulness tier" .. before .. scope)
        end
    elseif #lines == 0 and native ~= key then
        return -- no verified detail to replace the named upstream description
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
        "The pose pool grows as ranks rise: " .. table.concat(groups, ", ") .. ". A linked pose can extend the target; a fall can end the sequence early.",
        "Higher ranks make the same fall-prone pose safer. Harder poses and sandbox can change the odds. By rank " .. Facts.noFallRank .. ", even the hardest native roll cannot trigger.",
        "Each successful pose and final rest eases boredom by the same amount at every rank. Stress, pain and stiffness relief get stronger with the Yoga pose tiers.",
        "A deployed mat can help and may be required. Below rank 10, stopping after earning XP can take back Yoga XP and shorten an existing Zen. A failed pose itself earns no XP and does not grant new Zen.",
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
        zen[#zen + 1] = "Started at rank " .. yogaRank .. ": " .. zenPeriod .. " after successful Yoga."
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
            "Rank hover keeps the actual stock XP and perk boost. Higher ranks extend some action limits and can add less boredom per effect update. Focus, traits, current mood and settings change the amount; this is separate from Mindfulness duration.",
        }},
        {title="Mindfulness", lines=lines},
        {title="Yoga", lines=yoga},
        {title="Zen", lines=zen},
        {title="Lessons", lines=lessonLines},
    }
end

return Info
