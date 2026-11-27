-- Colors, icons and measured text. Neutral charcoal like the stock panels; one
-- accent per kind of work so a glance says what is running.
local Theme = {}
-- The mod's name wherever a player reads it. The mod ID stays AutoMindful.
Theme.brand = "Second Nature"
Theme.brandMark = string.upper(Theme.brand)

local function rgb(r, g, b, a) return {r=r, g=g, b=b, a=a or 1} end

Theme.colors = {
    window = rgb(0.045, 0.047, 0.050, 0.97),
    raised = rgb(1, 1, 1, 0.045),
    hover = rgb(1, 1, 1, 0.10),
    line = rgb(1, 1, 1, 0.13),
    border = rgb(0.36, 0.37, 0.38, 1),
    text = rgb(0.92, 0.92, 0.90),
    muted = rgb(0.62, 0.63, 0.63),
    faint = rgb(0.43, 0.44, 0.44),
    meditation = rgb(0.45, 0.76, 0.68),
    yoga = rgb(0.93, 0.70, 0.36),
    both = rgb(0.76, 0.76, 0.52),
    tier = rgb(0.72, 0.62, 0.90),
    recovery = rgb(0.46, 0.68, 0.90),
    care = rgb(0.92, 0.52, 0.56),
    good = rgb(0.49, 0.80, 0.49),
    warn = rgb(0.95, 0.72, 0.36),
    bad = rgb(0.93, 0.43, 0.38),
}

-- Time left as colour: strong green when a span has just begun, through
-- amber and red to dark red as it runs out. fraction: 1 full .. 0 empty.
local timeStops = {
    {0, rgb(0.62, 0.10, 0.08)}, {0.25, rgb(0.90, 0.30, 0.22)}, {0.5, rgb(0.96, 0.74, 0.28)}, {1, rgb(0.26, 0.82, 0.38)},
}
function Theme.timeLeft(fraction)
    fraction = math.max(0, math.min(1, fraction or 0))
    for index = 2, #timeStops do
        local low, high = timeStops[index - 1], timeStops[index]
        if fraction <= high[1] then
            local t = (fraction - low[1]) / (high[1] - low[1])
            local a, b = low[2], high[2]
            return rgb(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
        end
    end
    return timeStops[#timeStops][2]
end

-- Shipped art first; a client-only loader that restores Lua without mounting
-- loose images gets a symbol from the game's own texture packs instead.
local stock = {
    Yoga="Item_Dumbbell", Meditate="Item_Candle", Endurance="Moodle_Icon_Endurance", Mindful="FavoriteStar", Bandage="Item_Bandage",
}
local cache = {}

-- A texture still loading is fine: it appears a frame later. Treating it as
-- missing would leave a menu on its fallback symbol.
function Theme.usable(texture)
    if not texture then return false end
    local ok, good = pcall(function()
        local name = texture.getName and texture:getName()
        return name ~= "EngineErrorTexture" and name ~= "EngineErrorTexture.png"
            and not (texture.isFailure and texture:isFailure()) and not (texture.isDestroyed and texture:isDestroyed())
    end)
    return ok and good
end

local function lookup(key)
    if not getTexture or not key then return nil end
    local ok, texture = pcall(getTexture, key)
    if ok and Theme.usable(texture) then return texture end
end

-- fileExists consults the game's file system, so an unmounted path never
-- reaches the engine's texture miss cache. Only a real texture is cached.
function Theme.file(path)
    if Theme.usable(cache[path]) then return cache[path] end
    cache[path] = nil
    if fileExists then
        local ok, exists = pcall(fileExists, path)
        if ok and exists then cache[path] = lookup(path) end
    end
    return cache[path]
end

function Theme.icon(name)
    return Theme.file("media/ui/AutoMindful/" .. name .. ".png") or lookup(stock[name])
end

function Theme.preload()
    for name in pairs(stock) do Theme.icon(name) end
end

local moodles = {
    water="Status_Thirst", food="Status_Hunger", fatigue="Mood_Sleepy", endurance="Mood_Exhausted", boredom="Mood_Bored",
    stress="Mood_Stressed", unhappiness="Mood_Sad", pain="Mood_Pained", panic="Mood_Panicked",
    bleeding="Status_Bleeding", zombies="Mood_Scared", health="Status_InjuredMajor",
}
function Theme.moodle(need)
    return moodles[need] and Theme.file("media/ui/Moodles/48/" .. moodles[need] .. ".png")
end

function Theme.line(font) return getTextManager():getFontHeight(font or UIFont.Small) end
function Theme.width(text, font) return getTextManager():MeasureStringX(font or UIFont.Small, text) end

-- Lifestyle and the game hand out rich-text markup; these rows draw plain text.
function Theme.plain(text)
    if type(text) ~= "string" then return nil end
    local value = text:gsub("%b<>", " "):gsub("[%c]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if value ~= "" then return value end
end

-- One leading unit plus its continuation bytes: whole characters both in
-- Kahlua (UTF-16 units) and in portable Lua (UTF-8 bytes).
local function glyphs(word) return word:gmatch("[^\128-\191][\128-\191]*") end

function Theme.wrap(text, width, font)
    local lines, line = {}, ""
    for word in tostring(text or ""):gmatch("%S+") do
        local joined = line == "" and word or (line .. " " .. word)
        if Theme.width(joined, font) <= width then line = joined
        else
            if line ~= "" then lines[#lines + 1] = line end
            line = word
            if Theme.width(word, font) > width then -- never cut a translated word mid-character
                line = ""
                for glyph in glyphs(word) do
                    if line ~= "" and Theme.width(line .. glyph, font) > width then
                        lines[#lines + 1] = line
                        line = ""
                    end
                    line = line .. glyph
                end
            end
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

function Theme.fit(text, width, font)
    text = tostring(text or "")
    if Theme.width(text, font) <= width then return text end
    local out = ""
    for glyph in glyphs(text) do
        if Theme.width(out .. glyph .. "...", font) > width then break end
        out = out .. glyph
    end
    return out .. "..."
end

return Theme
