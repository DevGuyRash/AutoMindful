local Progress = {}

local function sample(level, current, required, total)
    local capped = level >= 10
    return {level=level, current=capped and 0 or math.max(0, current), required=capped and 0 or required,
        fraction=capped and 1 or math.max(0, math.min(1, required > 0 and current / required or 0)),
        total=total, capped=capped}
end

function Progress.snapshot(player)
    local result = {}
    if not player then return result end
    local perk = Perks and Perks.Meditation
    if perk and perk.getXpForLevel and perk.getTotalXpForLevel then
        local level, total = player:getPerkLevel(perk), player:getXp():getXP(perk)
        local required = level < 10 and perk:getXpForLevel(level + 1) or 0
        result.meditation = sample(level, total - perk:getTotalXpForLevel(level), required, total)
    end
    local yoga = HiddenSkills and HiddenSkills.getSkill and HiddenSkills.getSkill(player, "Yoga")
    if yoga then result.yoga = sample(yoga[1], yoga[2], yoga[3]) end
    return result
end

function Progress.number(value)
    if value == math.floor(value) then return tostring(value) end
    return string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
end

function Progress.xpText(value)
    if not value then return "XP unavailable" end
    if value.capped then return "MAX" end
    return string.format("%s / %s XP (%.1f%%)", Progress.number(value.current), Progress.number(value.required), value.fraction * 100)
end

function Progress.text(value)
    if not value then return "XP unavailable" end
    return string.format("Level %d / 10 - %s", value.level, Progress.xpText(value))
end

function Progress.change(previous, current)
    if not previous or not current then return nil end
    local difference
    if previous.total and current.total then difference = current.total - previous.total
    elseif current.level == previous.level then
        if current.capped then return nil end
        difference = current.current - previous.current
    elseif current.level == previous.level + 1 and not current.capped then
        difference = previous.required - previous.current + current.current
    end
    if difference and math.abs(difference) >= 0.005 then
        return {amount=difference, positive=difference > 0}
    end
    local levels = current.level - previous.level
    if levels ~= 0 then return {levels=levels, positive=levels > 0} end
end

return Progress
