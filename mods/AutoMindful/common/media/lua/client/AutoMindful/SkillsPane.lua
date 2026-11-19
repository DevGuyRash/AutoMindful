-- A readout on the stock Skills tab, not a PerkFactory perk or an actionable skill bar.
local Progress = require "AutoMindful/Progress"
AutoMindful = AutoMindful or {}
local Skills = AutoMindful.SkillsPane or {}
AutoMindful.SkillsPane = Skills
local REFRESH_MS = 250

local function isPerk(perk, key)
    return (Perks and Perks[key] and perk:getType() == Perks[key])
        or (perk.getId and perk:getId() == key)
end

local function sample(pane)
    local section
    for i, parent in ipairs(pane.sorted) do
        for _, perk in ipairs(pane.perks[parent:getType()] or {}) do
            if isPerk(perk, "Yoga") then return end -- native row takes precedence, even when collapsed
            if isPerk(perk, "Meditation") then section = i end
        end
    end
    if not section then return end
    local value = Progress.yoga(pane.char)
    if not value then return end
    local name = getTextOrNull and getTextOrNull("IGUI_perks_Yoga") or "Yoga"
    local xp = value.capped and "MAX" or (Progress.number(value.current) .. "/" .. Progress.number(value.required) .. " XP")
    return {section=section, level=name .. " " .. value.level .. "/10", short=name .. " L" .. value.level, xp=xp}
end

local function draw(pane, oldScroll)
    if not pane:isReallyVisible() or not pane.sorted or not pane.perks or not pane.collapse or not pane.buttonList or not pane.char
        or pane.char ~= getSpecificPlayer(pane.playerNum) then return end
    local t, cache = getTimestampMs(), pane.autoMindfulYogaView
    if not cache or cache.char ~= pane.char or cache.perks ~= pane.perks or cache.sorted ~= pane.sorted
        or cache.bars ~= pane.progressBars or cache.source ~= HiddenSkills or cache.nativeYoga ~= (Perks and Perks.Yoga)
        or t < cache.at or t - cache.at >= REFRESH_MS then
        -- An absent, incompatible or not-yet-loaded Lifestyle API must not take the native tab down.
        local ok, value = pcall(sample, pane)
        cache = {char=pane.char, perks=pane.perks, sorted=pane.sorted, bars=pane.progressBars,
            source=HiddenSkills, nativeYoga=Perks and Perks.Yoga, at=t, value=ok and value or nil}
        pane.autoMindfulYogaView = cache
    end
    cache.compact = false
    local v = cache.value
    if not v or pane.collapse[v.section] ~= false then return end
    local button, parent = pane.buttonList[v.section], pane.sorted[v.section]
    if not button or not parent then return end
    local metrics, font = getTextManager(), UIFont.Small
    local w, h = pane:getWidth(), pane:getHeight()
    local function width(s) return metrics:MeasureStringX(font, s) end
    local lineH = metrics:getFontHeight(font)
    -- Stock prints the category name ten pixels after its collapse button. Keep its scrollbar clear.
    local left = button:getX() + button:getWidth() + 10 + width(parent:getName()) + 10
    local right = w - 18
    local label = v.level .. "  |  " .. v.xp
    if width(label) > right-left then label = v.short .. "  " .. v.xp end
    local x, y, second
    if width(label) <= right-left then
        x, y = right-width(label), button:getY() + math.floor((button:getHeight()-lineH)/2)
    else
        -- A narrow or localized pane gets one scrollable footer, not a wider window or an overlapping label.
        -- Every stock render sets its own content height first, so this never accumulates.
        x, y = button:getX(), pane:getScrollHeight()
        label = v.level .. "  |  " .. v.xp
        if width(label) > right-x then label, second = v.level, v.xp end
        if width(label) > right-x then label = v.short end
        if width(label) > right-x or (second and width(second) > right-x) then return end
        pane:setScrollHeight(y + (second and 2 or 1) * (lineH+2) + 6)
        cache.compact = true
        if oldScroll and oldScroll < pane:getYScroll() then pane:setYScroll(oldScroll) end
    end
    pane:setStencilRect(0, 0, w, h)
    pane:drawText(label, x, y, 0.78, 0.88, 0.78, 1, font)
    if second then pane:drawText(second, x, y+lineH+2, 0.78, 0.88, 0.78, 1, font) end
    pane:clearStencilRect()
end

local function finish(pane, oldScroll, ...)
    draw(pane, oldScroll)
    return ...
end

function Skills.install()
    local class = ISCharacterInfo
    if not class or not class.render or Skills.hookedClass == class then return end
    local original = class.render
    class.render = function(pane, ...)
        local cache = pane.autoMindfulYogaView
        local oldScroll = cache and cache.compact and pane:getYScroll()
        return finish(pane, oldScroll, original(pane, ...))
    end
    Skills.hookedClass = class
end

return Skills
