-- Augment the existing Lifestyle HUD, not the player's moodle state.
local Info = require "AutoMindful/WellnessInfo"
local Clock = require "AutoMindful/Clock"
local Theme = require "AutoMindful/Theme"
local Zen = {}
local numerals = {"I", "II", "III", "IV"}

local function number(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function workoutBonus(player)
    local data = player:getModData()
    local baseline = data and data.LSZenActive
    local exercises = FitnessExercises and FitnessExercises.exercisesType
    if type(baseline) ~= "table" or type(exercises) ~= "table" then return end
    -- The live setting is additive and retained from the successful Yoga session,
    -- not recalculated when Zen fades. Don't assume other mods left it uniform.
    local bonus
    for key, before in pairs(baseline) do
        local now = exercises[key] and exercises[key].xpMod
        if not number(before) or not number(now) then return end
        local diff = now - before
        if diff <= 0 or (bonus and math.abs(bonus - diff) > 0.00001) then return end
        bonus = diff
    end
    return bonus
end

local function wrap(lines, tm, font, text, maxWidth)
    local line
    for word in text:gmatch("%S+") do
        local nextLine = line and (line .. " " .. word) or word
        if line and tm:MeasureStringX(font, nextLine) > maxWidth then
            lines[#lines+1] = line
            line = word
        else
            line = nextLine
        end
    end
    if line then lines[#lines+1] = line end
end

local zenNames = {"Zen I", "Zen II", "Zen III", "Zen IV"}

-- How long the tier showing now has left, live: the next drop, a bar that
-- drains toward it (green when fresh, dark red when nearly gone), and when
-- the moodle ends altogether. Real time is at normal game speed.
function Zen.countdown(player, name)
    local timer
    if name == "Zen" then timer = Info.zenCountdown(player, Clock.untilTick(10))
    else timer = Info.mindfulnessCountdown(player, (Clock.minuteOfDay() or 0) % 1) end
    if not timer then return nil end
    local function span(minutes) return Clock.game(minutes) .. " (" .. Clock.real(Clock.realSeconds(minutes)) .. " real)" end
    local nextName = name == "Zen" and zenNames[timer.next] or timer.nextName
    local rows = {{text = (nextName and ("Drops to " .. nextName) or "Ends") .. " in " .. span(timer.left)}}
    rows[#rows + 1] = {bar = math.max(0, math.min(1, timer.left / timer.span))}
    if nextName then rows[#rows + 1] = {text = "Gone in " .. span(timer.gone), muted = true} end
    return rows, timer
end

local function draw(ui, player, name, title, description)
    local x, y, w, h = ui:getX(), ui:getY(), ui:getWidth(), ui:getHeight()
    if not ui:isMouseOver() then
        local mx, my = getMouseX(), getMouseY()
        if mx < x or mx > x+w or my < y or my > y+h then return end
    end
    local details = {}
    if name == "Zen" then
        -- The same native HUD tier that Yoga and Meditation read as Level.
        local tier = ui:level()
        local suffix = numerals[tier]
        if not suffix then return end
        title = title .. " " .. suffix
        local xp, pose = Info.zenXPForPlayer(player, tier)
        if xp then details[#details+1] = string.format("- Meditation XP: +%d%% (x%.1f)", math.floor((xp-1)*100+0.5), xp) end
        if pose then details[#details+1] = string.format("- Yoga pose XP factor: +%d", pose) end
        local workout = Info.supported() and workoutBonus(player)
        if workout and workout >= 0.005 then
            details[#details+1] = string.format("- Workout XP setting: +%.2f (cached values may not update)", workout)
        end
    else
        details = Info.mindfulnessHover(player)
        if not details then return end
    end
    local font, tm = UIFont.Small, getTextManager()
    local lineHeight, pad, right = tm:getFontHeight(font), 7, -4
    local maxWidth = math.max(1, math.min(350, x - 2 * pad + right))
    local lines = {title}
    wrap(lines, tm, font, description, maxWidth)
    for _, line in ipairs(details) do wrap(lines, tm, font, line, maxWidth) end
    -- Timer lines wrap like the rest, so a large font never runs past the box.
    local timer = {}
    for _, row in ipairs(Zen.countdown(player, name) or {}) do
        if row.text then
            local wrapped = {}
            wrap(wrapped, tm, font, row.text, maxWidth)
            for _, text in ipairs(wrapped) do timer[#timer + 1] = {text = text, muted = row.muted} end
        else timer[#timer + 1] = row end
    end
    local width = 0
    for _, line in ipairs(lines) do width = math.max(width, tm:MeasureStringX(font, line)) end
    for _, row in ipairs(timer) do if row.text then width = math.max(width, tm:MeasureStringX(font, row.text)) end end
    width = math.min(width, math.max(maxWidth, 1))
    local barHeight = math.max(4, math.floor(lineHeight / 3))
    local extra = 0
    for _, row in ipairs(timer) do extra = extra + (row.bar and barHeight + 6 or lineHeight) end
    local height = lineHeight * #lines + 2 * pad + (extra > 0 and extra + 4 or 0)
    local top = math.max(0, math.min(y + math.floor((h - height) / 2), getCore():getScreenHeight() - height)) - y
    ui:drawRect(right - width - 2 * pad, top, width + 2 * pad, height, 0.75, 0, 0, 0)
    for i, line in ipairs(lines) do
        ui:drawTextRight(line, right - pad, top + pad + (i-1) * lineHeight, 1, 1, 1, i == 1 and 1 or 0.85, font)
    end
    local cy = top + pad + #lines * lineHeight + 4
    for _, row in ipairs(timer) do
        if row.bar then
            local c = Theme.timeLeft(row.bar)
            ui:drawRect(right - pad - width, cy + 2, width, barHeight, 0.35, 1, 1, 1)
            ui:drawRect(right - pad - width, cy + 2, width * row.bar, barHeight, 1, c.r, c.g, c.b)
            cy = cy + barHeight + 6
        else
            ui:drawTextRight(row.text, right - pad, cy, 1, 1, 1, row.muted and 0.6 or 1, font)
            cy = cy + lineHeight
        end
    end
    return true
end

local loggedHover
local attached = 0
-- Shared by every load of this file in one Lua state, so a reload neither wraps
-- a widget or factory twice nor leaves an old scan running.
AutoMindful = AutoMindful or {}
local shared = AutoMindful.zenMoodle or {widgets=setmetatable({}, {__mode="k"}), factories=setmetatable({}, {__mode="k"})}
AutoMindful.zenMoodle = shared
local wrappedWidgets, wrappedFactories = shared.widgets, shared.factories

local function attach(ui, player)
    if type(ui) ~= "table" or type(ui.mouseOverMoodle) ~= "function"
        or type(ui.level) ~= "function" or wrappedWidgets[ui] == ui.mouseOverMoodle then return end
    local originalHover = ui.mouseOverMoodle
    local function hover(self, hovered, title, description)
        if (hovered ~= "Zen" and hovered ~= "MindfulState") or type(title) ~= "string" or type(description) ~= "string" then
            return originalHover(self, hovered, title, description)
        end
        if draw(self, player, hovered, title, description) then
            if hovered == "Zen" and not loggedHover then
                loggedHover = true
                print("[AutoMindful] Zen tooltip rendered on Lifestyle's HUD.")
            end
        elseif hovered == "MindfulState" then
            return originalHover(self, hovered, title, description)
        end
    end
    ui.mouseOverMoodle = hover
    wrappedWidgets[ui] = hover
    attached = attached + 1
    if attached == 1 then print("[AutoMindful] Zen tooltip attached to Lifestyle's HUD.") end
end

local function attachExisting()
    local player = getPlayer and getPlayer()
    local elements = UIManager and UIManager.getUI and UIManager.getUI()
    if not player or not elements then return end
    -- Lifestyle creates these widgets on OnCreatePlayer and does not keep a
    -- public reference. Its updater distinguishes them from stock and other
    -- frameworks. The native hover supplies the name, even for existing items.
    for i = 0, elements:size()-1 do
        local element = elements:get(i)
        local ui = element and element.getTable and element:getTable()
        if type(ui) == "table" and ui.Type == "ISMoodles"
            and type(ui.updateLSMoodles) == "function" then
            attach(ui, player)
        end
    end
end

function Zen.install()
    local manager = LSMoodleManager
    if type(manager) ~= "table" or type(manager.newType) ~= "function" then return end
    local original = manager.newType
    if not wrappedFactories[original] then
        local function factory(player, name, ...)
            local ui = original(player, name, ...)
            if name == "Zen" or name == "MindfulState" then attach(ui, player) end
            return ui
        end
        wrappedFactories[factory] = true
        manager.newType = factory
    end
    attachExisting()
end

-- A server can load this mod after Lifestyle has made its moodles, and makes
-- them again after a death. Any moment can be the first one, so look now and
-- then: a widget is only wrapped once.
local lookMs, lookedAt = 2000, nil
local function look()
    local now = getTimestampMs and getTimestampMs() or 0
    if lookedAt and now >= lookedAt and now - lookedAt < lookMs then return end
    lookedAt = now
    Zen.install()
end

-- Called when the file loads, not only when a player is created: a late load
-- can come after both the player and the game have started.
function Zen.watch()
    local postDraw = Events and Events.OnPostUIDraw
    if not postDraw then return end
    if shared.look then postDraw.Remove(shared.look) end
    shared.look = look
    postDraw.Add(look)
end

function Zen.onPlayerReady()
    lookedAt = nil
    Zen.install()
    Zen.watch()
end

return Zen
