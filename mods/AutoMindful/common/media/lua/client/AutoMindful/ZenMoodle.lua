-- Augment the existing Lifestyle Zen icon, not the player's moodle state.
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

local function draw(ui, player, title, description)
    local x, y, w, h = ui:getX(), ui:getY(), ui:getWidth(), ui:getHeight()
    if not ui:isMouseOver() then
        local mx, my = getMouseX(), getMouseY()
        if mx < x or mx > x+w or my < y or my > y+h then return end
    end
    -- Ask the original widget for the current tier. Its Value-to-Level rules
    -- stay upstream and updates are reflected immediately on the same icon.
    local tier = ui:level()
    local suffix = numerals[tier]
    if not suffix then return end
    local font, tm = UIFont.Small, getTextManager()
    local lineHeight, pad, right = tm:getFontHeight(font), 7, -4
    local maxWidth = math.max(1, math.min(350, x - 2 * pad + right))
    local lines = {title .. " " .. suffix}
    wrap(lines, tm, font, description, maxWidth)
    local xp, pose = Info.zenEffects(tier)
    if xp then
        wrap(lines, tm, font, string.format("- Meditation XP: +%d%% (x%.1f)", math.floor((xp-1)*100+0.5), xp), maxWidth)
        wrap(lines, tm, font, string.format("- Yoga pose XP factor: +%d", pose), maxWidth)
        local workout = workoutBonus(player)
        if workout and workout >= 0.005 then
            wrap(lines, tm, font, string.format("- Workout XP setting: +%.2f (cached values may not update)", workout), maxWidth)
        end
    end
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
local wrappedWidgets = setmetatable({}, {__mode="k"})
local wrappedFactories = setmetatable({}, {__mode="k"})

local function attach(ui, player)
    if type(ui) ~= "table" or type(ui.mouseOverMoodle) ~= "function"
        or type(ui.level) ~= "function" or wrappedWidgets[ui] == ui.mouseOverMoodle then return end
    local originalHover = ui.mouseOverMoodle
    local function hover(self, hovered, title, description)
        if hovered ~= "Zen" or type(title) ~= "string" or type(description) ~= "string" then
            return originalHover(self, hovered, title, description)
        end
        if draw(self, player, title, description) and not loggedHover then
            loggedHover = true
            print("[AutoMindful] Zen tooltip rendered on Lifestyle's HUD.")
        end
    end
    ui.mouseOverMoodle = hover
    wrappedWidgets[ui] = hover
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
            if name == "Zen" then attach(ui, player) end
            return ui
        end
        wrappedFactories[factory] = true
        manager.newType = factory
    end
    attachExisting()
end

local function afterUIRegistration()
    Events.OnPostUIDraw.Remove(afterUIRegistration)
    Zen.install()
end

function Zen.onPlayerReady()
    Zen.install()
    -- UIManager can defer AddUI until it updates. Scan once after the native
    -- UI draw, not on every frame, so late client loads can adopt existing UI.
    local postDraw = Events.OnPostUIDraw
    if postDraw then
        postDraw.Remove(afterUIRegistration)
        postDraw.Add(afterUIRegistration)
    end
end

return Zen
