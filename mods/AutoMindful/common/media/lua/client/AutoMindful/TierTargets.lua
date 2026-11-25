local Facts = require "AutoMindful/WellnessFacts"

local Tiers = {}

function Tiers.wellnessEnabled()
    return not (SandboxVars and SandboxVars.Text and SandboxVars.Text.DividerMeditationNew == false)
end

function Tiers.providerCompatible()
    -- In-game registry mismatch cannot certify the private tier table.
    if not getModInfoByID then return true end -- portable fixtures use pinned upstream
    local ok, version = pcall(function()
        local mod = getModInfoByID("LifestyleHobbies")
        return mod and tostring(mod:getModVersion())
    end)
    return ok and version == Facts.version
end
function Tiers.providerMismatch()
    return getModInfoByID ~= nil and getModInfoByID("LifestyleHobbies") ~= nil and not Tiers.providerCompatible()
end

local kinds = {
    meditation = {
        key="MindfulState", thresholds={0.2, 0.4, 0.6}, ranks=Facts.meditationUnlocks,
        names={"Mindfulness", "Strong Mindfulness", "Perfect Mindfulness"},
        icons={"MindfulState.png", "MindfulState1.png", "MindfulState2.png"},
        fallback="media/ui/meditation_icon.png", atlas={"FavoriteStar", "Item_Candle"},
    },
    yoga = {
        key="Zen", thresholds={0.15, 0.30, 0.50, 0.70}, ranks={},
        names={"I", "II", "III", "IV"}, icons={"Zen.png"},
        fallback="media/ui/yoga_icon.png", atlas={"Item_Dumbbell"},
    },
}

local function tierOf(value, thresholds)
    for tier = #thresholds, 1, -1 do
        if value >= thresholds[tier] then return tier end
    end
    return 0
end

-- Lifestyle awards .25 * Yoga efficiency only after a successful nonzero-rank
-- session. The Moodle manager's visible thresholds can skip a displayed tier.
local yoga = kinds.yoga
for rank = 1, 10 do
    for tier = 1, tierOf(0.25 * Facts.yoga[rank][2], yoga.thresholds) do
        if not yoga.ranks[tier] then yoga.ranks[tier] = rank end
    end
end

function Tiers.clamp(kind, tier, skill)
    local spec = kinds[kind]
    if not spec or not Tiers.providerCompatible() or type(tier) ~= "number" or tier < 1 or tier % 1 ~= 0
            or type(skill) ~= "number" or not (skill >= 0 and skill <= 10) or skill % 1 ~= 0 then return 0 end
    for target = math.min(tier, #spec.ranks), 1, -1 do
        if skill >= spec.ranks[target] then return target end
    end
    return 0
end

local function moodleData(player, key)
    if not player or not player.getModData or (player.hasModData and not player:hasModData()) then return end
    local data = player:getModData()
    local moodles = type(data) == "table" and data.LSMoodles
    local moodle = type(moodles) == "table" and moodles[key]
    if type(moodle) == "table" then return moodle.Value end
end

function Tiers.current(player, kind)
    local spec = kinds[kind]
    if not spec or not Tiers.wellnessEnabled() or not Tiers.providerCompatible() then return nil end
    local ok, value = pcall(moodleData, player, spec.key)
    -- Lifestyle's rendered Level can lag the action that just changed Value.
    if not ok or type(value) ~= "number" or not (value >= 0 and value <= 1) then return nil end
    return tierOf(value, spec.thresholds)
end

local function translate(key, fallback)
    local fromGame = getTextOrNull and getTextOrNull(key)
    if type(fromGame) == "string" and fromGame ~= "" and fromGame ~= key then return fromGame end
    return fallback
end

function Tiers.label(kind, tier)
    local spec = kinds[kind]
    if not spec then return nil end
    if tier == 0 then return "No minimum" end
    local name = spec.names[tier]
    if not name then return nil end
    if kind == "yoga" then return translate("Moodles_Zen_L1", "Zen") .. " " .. name end
    return translate("Moodles_MindfulState_L" .. tier, name)
end

function Tiers.choices(kind)
    local spec = kinds[kind]
    if not spec then return {} end
    local rows = {{tier=0, label=Tiers.label(kind, 0), rank=0}}
    for tier, rank in ipairs(spec.ranks) do
        rows[#rows + 1] = {tier=tier, label=Tiers.label(kind, tier), rank=rank}
    end
    return rows
end

local function positiveTint(tier)
    if not Color or not Color.gray or not getCore then return nil end
    local core = getCore()
    if not core or not core.getGoodHighlitedColor then return nil end
    local gray, good = Color.gray, core:getGoodHighlitedColor()
    if not good then return nil end
    local weight = tier / 4
    return {
        r=gray:getRedFloat() * (1 - weight) + good:getR() * weight,
        g=gray:getGreenFloat() * (1 - weight) + good:getG() * weight,
        b=gray:getBlueFloat() * (1 - weight) + good:getB() * weight,
    }
end

local function usable(texture)
    if not texture then return false end
    local ok, good = pcall(function()
        local name = texture.getName and texture:getName()
        return name ~= "EngineErrorTexture" and name ~= "EngineErrorTexture.png"
            and not (texture.isFailure and texture:isFailure())
            and not (texture.isDestroyed and texture:isDestroyed())
            and (not texture.isReady or texture:isReady())
    end)
    return ok and good
end

local textures = {}
local function texture(path, loose)
    if usable(textures[path]) then return textures[path] end
    textures[path] = nil
    if not getTexture then return nil end
    if loose and fileExists then
        -- Avoid adding a LuaBuddy-unmounted path to the engine's texture miss cache.
        local ok, present = pcall(fileExists, path)
        if not ok or not present then return nil end
    end
    local ok, value = pcall(getTexture, path)
    if ok and usable(value) then textures[path] = value; return value end
end

-- Stock context menus accept one tinted icon. Panels may instead draw the
-- tinted solid and white outline behind the unmodified glyph, as Lifestyle does.
function Tiers.texture(kind, tier)
    local spec = kinds[kind]
    if not spec or type(tier) ~= "number" or tier % 1 ~= 0 or tier < 0 or tier > #spec.ranks then return nil end
    local base = spec.icons[1]
    local file, root = spec.icons[tier] or base, "media/ui/moodles/"
    local icon = texture(root .. file, true)
    if not icon and file ~= base then icon = texture(root .. base, true) end
    icon = icon or texture(spec.fallback, true)
    if not icon then
        for _, key in ipairs(spec.atlas) do
            icon = texture(key)
            if icon then break end
        end
    end
    if not icon then return nil end
    local ok, tint = pcall(positiveTint, tier)
    if not ok or not tint then
        -- The installed B42 defaults: Color.gray (.5,.5,.5), Good (0,1,0).
        local gray = (1 - tier / 4) / 2
        tint = {r=gray, g=gray + tier / 4, b=gray}
    end
    return icon, tint, texture("media/ui/Moodles/32/_Moodles_BGsolid.png", true),
        texture("media/ui/Moodles/32/_Moodles_BGoutline.png", true)
end

return Tiers
