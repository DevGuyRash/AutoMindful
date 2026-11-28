-- Under a food's tooltip: what eating all of it would do to this survivor
-- now, not a grade for the food. Calories before and after against the lines
-- where weight starts to rise or fall, where the energy comes from, each
-- macro coloured by what it does for this survivor, and a word on the diet goal.
-- Chains ISToolTipInv.render (other mods wrap or replace it); draws nothing
-- the game's own tooltip already says.
local Diet = require "AutoMindful/Diet"
local Nutrition = require "AutoMindful/Nutrition"
local Options = require "AutoMindful/Options"
local Theme = require "AutoMindful/Theme"
local colors = Theme.colors

AutoMindful = AutoMindful or {}
local Hover = AutoMindful.FoodHover or {}
AutoMindful.FoodHover = Hover
local shared = AutoMindful.foodHoverHook or {depth = 0}
AutoMindful.foodHoverHook = shared

-- Where the energy comes from: hues apart from the good/warn/bad colours.
Hover.hues = {carbs = {r=0.50, g=0.66, b=0.92, a=1}, fat = {r=0.40, g=0.80, b=0.80, a=1}, protein = {r=0.76, g=0.60, b=0.94, a=1}}
local goalWords = {more = "gaining weight", fewer = "losing weight", protein = "high protein", lowcarb = "low carb", lowfat = "low fat"}

local function read(fn, fallback)
    local ok, value = pcall(fn)
    if ok and value ~= nil then return value end
    return fallback
end

local function trait(player, name)
    return read(function() return player:hasTrait(CharacterTrait[name]) end, false) == true
end

-- As the game decides whether to print the nutrition label.
function Hover.readable(player, item)
    if trait(player, "NUTRITIONIST") or trait(player, "NUTRITIONIST2") then return true end
    if not read(function() return item:isPackaged() end, false) then return false end
    if trait(player, "ILLITERATE") or read(function() return player:tooDarkToRead() end, false) then return false end
    return not read(function() return item:getModData().NoLabel end, false)
end

local function kcal(value) return string.format("%d", math.floor(value + 0.5)) end

-- The lines to draw, each {text, color, bar}, or nil for nothing to add.
function Hover.lines(player, item)
    local mode = Options.foodHover()
    if mode == "off" then return nil end
    if mode == "label" and not Hover.readable(player, item) then return nil end
    local food = Nutrition.food(item)
    if not food or (food.calories == 0 and food.carbs == 0 and food.fat == 0 and food.protein == 0) then return nil end
    local s = Nutrition.read(player)
    local goal = Diet.goal(player)
    local lines = {}
    -- Calories: now, and after eating it all, against the gain and loss lines.
    if s then
        local after = math.max(Nutrition.rules.calories.low, math.min(Nutrition.rules.calories.high, s.calories + food.calories))
        local effect, tone
        if s.calories <= s.gainLine and after > s.gainLine then
            effect, tone = "This starts weight gain.", goal == "more" and colors.good or colors.warn
        elseif s.calories < s.lossLine and after >= s.lossLine then
            effect, tone = "This stops the weight loss.", goal == "fewer" and colors.warn or colors.good
        elseif after > s.gainLine then
            effect, tone = "Weight keeps going up.", goal == "more" and colors.good or colors.warn
        elseif after < s.lossLine then
            effect, tone = "Weight keeps going down.", goal == "fewer" and colors.good or colors.muted
        end
        lines[#lines + 1] = {text = "Eating it all: +" .. kcal(food.calories) .. " kcal, stored energy " .. kcal(s.calories) .. " to " .. kcal(after),
            color = colors.text}
        lines[#lines + 1] = {text = effect or "Weight stays steady.", color = tone or colors.muted}
        local p = Nutrition.rules.protein
        local protein = s.protein + food.protein
        if s.protein <= p.bonus and protein > p.bonus and protein < p.bonusTop then
            lines[#lines + 1] = {text = "Reaches the protein bonus to Strength XP.", color = colors.good}
        elseif s.proteinEffect == "penalty" and protein >= p.penalty then
            lines[#lines + 1] = {text = "Ends the low-protein penalty to Strength XP.", color = colors.good}
        end
    else
        lines[#lines + 1] = {text = kcal(food.calories) .. " kcal", color = colors.text}
    end
    -- Where the energy comes from, then the grams in the same hues.
    if food.share then lines[#lines + 1] = {bar = food.share} end
    local function gram(value) return string.format("%d g", math.floor(value + 0.5)) end
    local rich = s and (s.calories + food.calories > s.gainLine) and goal ~= "more"
    local function macroColor(kind, value)
        if s and kind ~= "protein" and rich and (s[kind] + value > Nutrition.rules.gain.rich) then return colors.warn end
        local p = Nutrition.rules.protein
        if s and kind == "protein" and s.protein <= p.bonus and s.protein + value > p.bonus and s.protein + value < p.bonusTop then return colors.good end
        return colors.text
    end
    -- The game prints the grams on a label it can read: then say what it does not, the share of energy.
    local labelled = Hover.readable(player, item)
    local function amount(kind)
        if labelled and food.share then return string.format("%d%%", math.floor(food.share[kind] * 100 + 0.5)) end
        return gram(food[kind])
    end
    lines[#lines + 1] = {cells = {
        {text = "Carbs " .. amount("carbs"), hue = Hover.hues.carbs, color = macroColor("carbs", food.carbs)},
        {text = "Fat " .. amount("fat"), hue = Hover.hues.fat, color = macroColor("fat", food.fat)},
        {text = "Protein " .. amount("protein"), hue = Hover.hues.protein, color = macroColor("protein", food.protein)},
    }}
    if labelled and food.share then lines[#lines + 1] = {text = "Share of its energy.", color = colors.faint} end
    -- The diet goal, when there is one to speak of.
    local fit = read(function() return Diet.fit(goal, item) end, 0)
    if goalWords[goal] and math.abs(fit) >= 0.15 then
        lines[#lines + 1] = {text = (fit > 0 and "Suits " or "Works against ") .. goalWords[goal] .. ".", color = fit > 0 and colors.good or colors.warn}
    end
    if food.hunger > 0.001 then
        local points = math.floor(food.hunger * 100 + 0.5)
        lines[#lines + 1] = {text = string.format("Eases %d hunger, %d kcal for each point.", points, math.floor(food.calories / (food.hunger * 100) + 0.5)),
            color = colors.muted}
    end
    Hover.last = {player = player, food = food, at = getTimestampMs()}
    return lines
end

-- The food under the pointer a moment ago, for the Body tab's "after" markers.
function Hover.recent(player)
    local last = Hover.last
    if last and last.player == player and getTimestampMs() - last.at < 1500 then return last end
end

local function measure(lines, font)
    local line = Theme.line(font)
    local width, height = 0, 0
    for _, row in ipairs(lines) do
        if row.bar then height = height + 10
        elseif row.cells then
            local w = 0
            for _, cell in ipairs(row.cells) do w = w + Theme.width(cell.text, font) + line + 4 end
            width, height = math.max(width, w), height + line
        else width, height = math.max(width, Theme.width(row.text, font)), height + line end
    end
    return width, height
end

function Hover.draw(tip)
    if ISContextMenu.instance and ISContextMenu.instance.visibleCheck then return end
    local item = tip.item
    if not item or not instanceof(item, "Food") then return end
    local player = read(function() return tip.tooltip:getCharacter() end, nil) or (getPlayer and getPlayer())
    if not player then return end
    local lines = Hover.lines(player, item)
    if not lines then return end
    local font, pad = UIFont.Small, 6
    local line = Theme.line(font)
    local contentW, contentH = measure(lines, font)
    local w = math.max(tip.width, contentW + pad * 2)
    local h = contentH + pad * 2
    -- Below the tooltip; above it when the screen ends first, and never past its right edge.
    local top = tip.height
    if tip:getY() + tip.height + h > getCore():getScreenHeight() and tip:getY() - h >= 0 then top = -h end
    local left = math.min(0, getCore():getScreenWidth() - 1 - (tip:getX() + w))
    if tip:getX() + left < 0 then left = -tip:getX() end
    local bg, border = tip.backgroundColor or {r=0, g=0, b=0, a=0.8}, tip.borderColor or {r=0.4, g=0.4, b=0.4, a=1}
    tip:drawRect(left, top, w, h, math.max(bg.a or 0.8, 0.8), bg.r, bg.g, bg.b)
    tip:drawRectBorder(left, top, w, h, border.a or 1, border.r, border.g, border.b)
    local y, x0, width = top + pad, left + pad, w - pad * 2
    for _, row in ipairs(lines) do
        if row.bar then
            local x = x0
            for _, kind in ipairs({"carbs", "fat", "protein"}) do
                local part = math.floor(width * row.bar[kind] + 0.5)
                local c = Hover.hues[kind]
                if part > 0 then tip:drawRect(x, y + 2, math.min(part, x0 + width - x), 6, 1, c.r, c.g, c.b) end
                x = x + part
            end
            y = y + 10
        elseif row.cells then
            local x = x0
            for _, cell in ipairs(row.cells) do
                local c = cell.hue
                tip:drawRect(x, y + math.floor(line / 2) - 3, 6, 6, 1, c.r, c.g, c.b)
                tip:drawText(cell.text, x + 10, y, cell.color.r, cell.color.g, cell.color.b, 1, font)
                x = x + 10 + Theme.width(cell.text, font) + line - 6
            end
            y = y + line
        else
            tip:drawText(row.text, x0, y, row.color.r, row.color.g, row.color.b, 1, font)
            y = y + line
        end
    end
end

-- Wrapped once per load. Another mod may wrap this wrapper, or replace it and
-- be wrapped again at game start; only the outermost of ours draws.
function Hover.install()
    local class = ISToolTipInv
    if not class or type(class.render) ~= "function" or class.render == shared.wrapper then return end
    local original = class.render
    local function render(self, ...)
        shared.depth = shared.depth + 1
        local ok, err = pcall(original, self, ...)
        shared.depth = shared.depth - 1
        if not ok then error(err, 0) end
        if shared.depth == 0 then
            local drawn, failure = pcall(Hover.draw, self)
            if not drawn and not shared.logged then
                shared.logged = true
                print("[AutoMindful] Food tooltip skipped: " .. tostring(failure))
            end
        end
    end
    shared.wrapper = render
    class.render = render
end

return Hover
