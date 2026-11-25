-- Augment the existing Lifestyle HUD, not the player's moodle state.
local Info = require "AutoMindful/WellnessInfo"
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
    local width = 0
    for _, line in ipairs(lines) do width = math.max(width, tm:MeasureStringX(font, line)) end
    local height = lineHeight * #lines + 2 * pad
    local top = math.max(0, math.min(y + math.floor((h - height) / 2), getCore():getScreenHeight() - height)) - y
    ui:drawRect(right - width - 2 * pad, top, width + 2 * pad, height, 0.75, 0, 0, 0)
    for i, line in ipairs(lines) do
        ui:drawTextRight(line, right - pad, top + pad + (i-1) * lineHeight, 1, 1, 1, i == 1 and 1 or 0.85, font)
    end
    return true
end

local loggedHover
local attached = 0
local wrappedWidgets = setmetatable({}, {__mode="k"})
local wrappedFactories = setmetatable({}, {__mode="k"})

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

function Zen.onPlayerReady()
    lookedAt = nil
    Zen.install()
    local postDraw = Events.OnPostUIDraw
    if postDraw then
        postDraw.Remove(look)
        postDraw.Add(look)
    end
end

return Zen
