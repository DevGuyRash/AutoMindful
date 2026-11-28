-- Let the stock Skills pane lay out one extra read-only row. Lifestyle owns Yoga's XP.
local Progress = require "AutoMindful/Progress"
AutoMindful = AutoMindful or {}
local Skills = AutoMindful.SkillsPane or {}
AutoMindful.SkillsPane = Skills
local REFRESH_MS = 250

local function isPerk(perk, key)
    return (perk.getId and perk:getId() == key) or (Perks[key] and perk:getType() == Perks[key])
end

local function rowName(row) return row.name end
-- B42's parent renderer asks only for boost and multiplier. Give those two reads
-- the real, inert stock enum. The Yoga descriptor itself never goes to Java.
local function rowType() return Perks.None end

local function project(pane, state)
    local group, anchor
    for _, parent in ipairs(pane.sorted) do
        local key = parent:getType()
        for i, perk in ipairs(pane.perks[key] or {}) do
            if isPerk(perk, "Yoga") then return end -- upstream owns its visible row, even in a collapsed group
            if isPerk(perk, "Meditation") then group, anchor = key, i end
        end
    end
    if not group or not Progress.yoga(pane.char) then return end
    local name = getTextOrNull and getTextOrNull("IGUI_perks_Yoga")
    if not name or name == "" then name = "Yoga" end
    local row = state.row
    row.name = name
    local view, rows = {}, {}
    for key, list in pairs(pane.perks) do view[key] = list end
    for i, perk in ipairs(view[group]) do
        rows[#rows+1] = perk
        if i == anchor then rows[#rows+1] = row end
    end
    view[group] = rows
    return {view=view, rows=rows, group=group, meditation=pane.perks[group][anchor], char=pane.char,
        width=math.max(pane.txtLen, getTextManager():MeasureStringX(UIFont.Small, name))}
end

local function current(pane, state)
    if not (Perks and Perks.None and pane.char and pane.char == getSpecificPlayer(pane.playerNum)
        and pane.sorted and pane.perks and pane.collapse and pane.progressBars and pane:isReallyVisible()) then
        state.cache = nil
        return nil
    end
    local t, c = getTimestampMs(), state.cache
    if c and not pane.reloadSkillBar and pane.progressBarLoaded and c.char == pane.char and c.perks == pane.perks
        and c.sorted == pane.sorted and c.native == Perks.Yoga and c.source == HiddenSkills
        and c.txtLen == pane.txtLen and t >= c.at and t-c.at < REFRESH_MS then return c.slot end
    -- Optional or not-yet-ready Lifestyle data must not take down the native Skills tab.
    local ok, slot = pcall(project, pane, state)
    state.cache = {at=t, char=pane.char, perks=pane.perks, sorted=pane.sorted, native=Perks.Yoga,
        source=HiddenSkills, txtLen=pane.txtLen, slot=ok and slot or nil}
    return state.cache.slot
end

local function sameSlot(a, b)
    if a == b then return true end
    if not a or not b or a.char ~= b.char or a.group ~= b.group or a.width ~= b.width or #a.rows ~= #b.rows then return false end
    for i, perk in ipairs(a.rows) do if perk ~= b.rows[i] then return false end end
    return true
end

local function render(pane, original, yogaBar, ...)
    local barClass = ISSkillProgressBar
    if not barClass or not barClass.new then return original(pane, ...) end
    local state = pane.autoMindfulYogaRow
    if not state then
        state = {row={getName=rowName, getType=rowType}}
        pane.autoMindfulYogaRow = state
    end
    if state.rendering then return original(pane, ...) end
    local slot = current(pane, state)
    if not slot and not state.last and not state.bar then return original(pane, ...) end
    if pane.progressBarLoaded and not sameSlot(state.last, slot) then pane.reloadSkillBar = true end
    local rebuild = pane.reloadSkillBar or not pane.progressBarLoaded
    local selected, oldIndex, oldYoga, hadTooltip
    if rebuild then
        oldYoga, oldIndex = state.bar, pane.joypadIndex
        selected = oldIndex and pane.progressBars[oldIndex]
        hadTooltip = selected and pane.barWithTooltip == selected
        if oldYoga then oldYoga:onMouseMoveOutside() end
        if hadTooltip and selected ~= oldYoga then selected:onMouseMoveOutside() end
        if hadTooltip or (oldYoga and pane.barWithTooltip == oldYoga) then pane.barWithTooltip = nil end
        state.bar = nil
    end
    local perks, width, stockNew = pane.perks, pane.txtLen, barClass.new
    state.last, state.rendering = slot, true
    if slot then
        -- Only the one pane sees this private list, and only while its stock
        -- render runs. Native labels, row spacing, scroll extent and joypad
        -- order now all come from the same unmodified stock layout calculation.
        pane.perks, pane.txtLen = slot.view, slot.width
        if rebuild then
            barClass.new = function(class, x, y, w, h, playerNum, perk, owner, ...)
                if class == barClass and perk == state.row and owner == pane then
                    local neighbor = pane.progressBars[#pane.progressBars]
                    if neighbor and neighbor.perk ~= slot.meditation then neighbor = nil end
                    state.bar = yogaBar:new(x, y, w, h, playerNum, perk, owner, neighbor)
                    return state.bar
                end
                return stockNew(class, x, y, w, h, playerNum, perk, owner, ...)
            end
        end
    end

    local function finish(ok, ...)
        -- Restore before returning or propagating an unrelated stock/mod error.
        if slot then
            pane.perks, pane.txtLen = perks, width
            if rebuild then barClass.new = stockNew end
        end
        state.rendering = nil
        if not ok then pane.reloadSkillBar = true; error((...), 0) end
        if rebuild and selected then
            local target = selected == oldYoga and state.bar or nil
            local index = math.min(oldIndex, #pane.progressBars)
            for i, bar in ipairs(pane.progressBars) do
                if (target and bar == target) or (selected.perk and bar.perk == selected.perk) then index=i; break end
            end
            pane.joypadIndex = index > 0 and index or nil
            if hadTooltip and pane.joyfocus then pane:updateTooltipForJoypad() end
        end
        return ...
    end
    return finish(pcall(original, pane, ...))
end

function Skills.install()
    local class = ISCharacterInfo
    if not class or not class.render or Skills.hookedClass == class then return end
    local yogaBar = require "AutoMindful/YogaSkillBar"
    require("AutoMindful/WellnessInfo").installMeditationTooltip(ISSkillProgressBar)
    local original = class.render
    class.render = function(pane, ...) return render(pane, original, yogaBar, ...) end
    Skills.hookedClass = class
end

return Skills
