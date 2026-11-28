-- Second Nature in the game's Health tab: one button after Fitness, one
-- weight line beside the game's hint, however often the methods are wrapped.
package.path = "mods/SecondNature/common/media/lua/client/?.lua;" .. package.path
package.loaded["PZAPI/ModOptions"] = true
for _, name in ipairs({"ISApplyBandage", "ISRemoveGlass", "ISRemoveBullet", "ISDisinfect", "ISStitch", "ISSplint",
        "ISCleanBurn", "ISComfreyCataplasm", "ISGarlicCataplasm", "ISPlantainCataplasm"}) do
    package.loaded["TimedActions/" .. name] = true
end
local function near(a, b, tolerance) return math.abs(a - b) <= (tolerance or 1e-6) end

local now, minutesPerDay, timeOfDay = 1000, 90, 9.5
function getTimestampMs() return now end
function getGameTime()
    return {getMinutesPerDay = function() return minutesPerDay end, getTimeOfDay = function() return timeOfDay end,
        getWorldAgeHours = function() return 100 end}
end
function instanceof(value, kind) return type(value) == "table" and value.kind == kind end
CharacterTrait = {WEIGHT_GAIN = "slow", WEIGHT_LOSS = "fast", DISCIPLINED = "disciplined", NUTRITIONIST = "nutritionist",
    NUTRITIONIST2 = "nutritionist2", ILLITERATE = "illiterate"}
UIFont = {Small = 1, Medium = 2, Large = 3}
function getTextManager()
    return {getFontHeight = function() return 16 end, MeasureStringX = function(_, _, text) return #tostring(text) * 7 end}
end

local Nutrition = require "AutoMindful/Nutrition"
local Clock = require "AutoMindful/Clock"

-- ------------------------------------------------------------ health panel
do
    package.loaded["ISUI/ISButton"], package.loaded["ISUI/ISToolTip"] = true, true
    local Theme = require "AutoMindful/Theme"
    local function widget(x, y, w, h)
        local b = {x = x, y = y, width = w, height = h, visible = true, Type = "ISButton"}
        function b:initialise() end
        function b:instantiate() end
        function b:setVisible(v) self.visible = v end
        function b:getIsVisible() return self.visible end
        function b:setX(v) self.x = v end
        function b:setY(v) self.y = v end
        function b:getX() return self.x end
        function b:getY() return self.y end
        function b:getHeight() return self.height end
        function b:getRight() return self.x + self.width end
        return b
    end
    ISButton = {new = function(_, x, y, w, h, title) local b = widget(x, y, w, h); b.title = title; return b end}
    ISToolTip = {new = function() return {initialise = function() end, setVisible = function() end} end}
    function getText() return "Right click to show Treatment menu" end
    function getCore() return {getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end} end
    local lines = 0
    ISHealthPanel = {}
    function ISHealthPanel.createChildren(self)
        self.fitness = widget(140, 8, 100, 22)
        self.children = {self.fitness}
    end
    function ISHealthPanel.render(self) self.rendered = (self.rendered or 0) + 1 end
    function ISHealthPanel.update(self) self.width = 380 end
    function ISHealthPanel.doBodyPartContextMenu() end
    -- The treatment side is Treat's (and the Controller's); the panel only asks it.
    package.loaded["AutoMindful/Treat"] = package.loaded["AutoMindful/Treat"] or {}
    local Panel = require "AutoMindful/HealthPanel"
    Panel.install()
    -- Another mod wraps render after us; ours is wrapped again at game start.
    local theirs = ISHealthPanel.render
    ISHealthPanel.render = function(self) theirs(self); self.theirs = (self.theirs or 0) + 1 end
    Panel.install()
    local nutritionBody = {getWeight = function() return 72 end, getCalories = function() return -400 end, getCarbohydrates = function() return 0 end,
        getLipids = function() return 0 end, getProteins = function() return 0 end, isIncWeight = function() return false end,
        isIncWeightLot = function() return false end, isDecWeight = function() return true end, canAddFitnessXp = function() return true end}
    local panel = {width = 380, height = 420, character = {isLocalPlayer = function() return true end, getNutrition = function() return nutritionBody end,
        hasTrait = function() return false end, isAsleep = function() return false end, isPlayerMoving = function() return false end,
        getBodyDamage = function() return {getThermoregulator = function() return {getEnergyMultiplier = function() return 1 end} end} end}}
    function panel:addChild(child) self.children[#self.children + 1] = child end
    function panel:getChildren() return self.children end
    function panel:drawTextRight(text) lines = lines + 1; self.line = text end
    function panel:setWidthAndParentWidth(w) self.width = w end
    ISHealthPanel.createChildren(panel)
    ISHealthPanel.render(panel)
    assert(panel.rendered == 1 and panel.theirs == 1 and lines == 1, "the game's render once, the other mod's once, ours once")
    assert(panel.secondNature and panel.secondNature.x == 246, "right after Fitness, whatever other buttons do")
    -- 72 kg is underweight (65 to 75); -400 kcal is below the loss line (72 - 70) x 30 = 60 -> 0.
    -- 110 px beside the game's hint: whole phrases only.
    assert(panel.line == "72.0 kg", panel.line)
    panel.width = 600; lines = 0; ISHealthPanel.render(panel)
    -- Losing at -400 kcal: 8.5e-6 x (400 / 2500) x 86400 = 0.1175 kg a day.
    assert(panel.line == "72.0 kg, underweight, -0.12 kg a day", panel.line)
    ISHealthPanel.update(panel)
    assert(panel.width >= panel.secondNature:getRight() + 8, "the tab widens to show it")
    panel.otherPlayer = {}
    ISHealthPanel.render(panel)
    assert(not panel.secondNature.visible and lines == 1, "nothing of ours on someone else's panel")
end
print("PASS the Health tab: one button after Fitness, one weight line, however often it is wrapped")
print("Health panel PASS")
