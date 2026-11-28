package.path = "mods/SecondNature/common/media/lua/client/?.lua;" .. package.path
local Tiers = require "AutoMindful/TierTargets"

local function close(actual, expected)
    assert(math.abs(actual - expected) < .00001, tostring(actual) .. " vs " .. tostring(expected))
end

local data = {LSMoodles={MindfulState={Value=0, Level=3},Zen={Value=0, Level=4}}}
local player = {getModData=function() return data end}
local unknown = {hasModData=function() return false end, getModData=function() error("Must not initialize data") end}
assert(Tiers.current(nil,"yoga") == nil and Tiers.current(unknown,"yoga") == nil)
assert(Tiers.current(player,"other") == nil and Tiers.current({}, "meditation") == nil)
for _, test in ipairs({
    {"meditation","MindfulState",{{0,0},{.1999,0},{.2,1},{.3999,1},{.4,2},{.5999,2},{.6,3},{1,3}}},
    {"yoga","Zen",{{0,0},{.1499,0},{.15,1},{.2999,1},{.30,2},{.4999,2},{.50,3},{.6999,3},{.70,4},{1,4}}},
}) do
    local kind, key, cases = test[1], test[2], test[3]
    for _, case in ipairs(cases) do
        data.LSMoodles[key].Value = case[1]
        assert(Tiers.current(player,kind) == case[2], kind .. " current after Value changes")
    end
    for _, invalid in ipairs({false,".4",-1,2,math.huge,0/0}) do
        data.LSMoodles[key].Value = invalid
        assert(Tiers.current(player,kind) == nil, kind .. " bad Value must not use old Level")
    end
end
data.LSMoodles.Zen.Value, data.LSMoodles.MindfulState.Value = .5, .6
local second = {getModData=function() return {LSMoodles={MindfulState={Value=0},Zen={Value=.25}}} end}
assert(Tiers.current(second,"meditation") == 0 and Tiers.current(second,"yoga") == 1)
assert(Tiers.current(player,"meditation") == 3 and Tiers.current(player,"yoga") == 3)
SandboxVars = {Text={DividerMeditationNew=false}}
assert(Tiers.current(player,"meditation") == nil and Tiers.current(player,"yoga") == nil)
SandboxVars.Text.DividerMeditationNew = true
assert(Tiers.current(player,"meditation") == 3 and Tiers.current(player,"yoga") == 3)
print("PASS live per-survivor moodle Values, native boundaries, disabled, stale and unavailable reads")

local function ranks(kind, expected, caps)
    local rows = Tiers.choices(kind)
    assert(#rows == #expected + 1 and rows[1].tier == 0 and rows[1].label == "No minimum")
    for tier, rank in ipairs(expected) do
        assert(rows[tier+1].tier == tier and rows[tier+1].rank == rank)
        assert(Tiers.clamp(kind,tier,rank) == tier)
        assert(Tiers.clamp(kind,tier,rank-1) < tier)
    end
    for rank = 0, 10 do
        assert(Tiers.clamp(kind,#expected,rank) == caps[rank+1], kind .. " reachable at " .. rank)
    end
    assert(Tiers.clamp(kind,#expected,nil) == 0 and Tiers.clamp(kind,#expected,10.5) == 0)
    assert(Tiers.clamp(kind,-1,9) == 0 and Tiers.clamp(kind,0,10) == 0 and Tiers.clamp(kind,1.1,10) == 0)
end
ranks("meditation",{3,6,10},{0,0,0,1,1,1,2,2,2,2,3})
ranks("yoga",{1,3,3,6},{0,1,1,3,3,3,4,4,4,4,4})
assert(Tiers.clamp("other",4,10) == 0 and #Tiers.choices("other") == 0)
function getTextOrNull(key)
    if key == "Moodles_MindfulState_L2" then return "Localized Strong" end
    if key == "Moodles_Zen_L1" then return "Localized Zen" end
    return key
end
assert(Tiers.label("meditation",2) == "Localized Strong" and Tiers.label("meditation",3) == "Perfect Mindfulness")
assert(Tiers.label("yoga",2) == "Localized Zen II" and Tiers.label("yoga",4) == "Localized Zen IV")
assert(Tiers.label("yoga",5) == nil and Tiers.label("other",2) == nil)
print("PASS ordered localized choices and rank clamps, including freshly earned Zen skipping II")

local life = arg and arg[1]
if not readReference and life then
    function readReference(name)
        local f = assert(io.open(life .. "/" .. name, "rb"))
        local text = f:read("*a")
        f:close()
        return text
    end
end
if readReference then
    local context = readReference("lua/client/ISMeditation/ZenWellnessContextMenu.lua")
    local action = readReference("lua/shared/TimedActions/LSYogaAction.lua")
    assert(action:match('skillLevel ~= 0 and not self%.doFailState then self%.playerData%.LSMoodles%["Zen"%]%.Value = 0%.25%*self%.efficiency'))
    assert(action:match('o%.efficiency = Args%[3%]'))
    local manager = readReference("lua/client/LSMoodleManager.lua")
    local nativeCuts = {}
    for value, tier in manager:gmatch("if value >= (%d+%.%d+) then%s+return (%d)") do
        nativeCuts[tonumber(tier)] = tonumber(value)
    end
    assert(nativeCuts[1] == .15 and nativeCuts[2] == .30 and nativeCuts[3] == .50 and nativeCuts[4] == .70)
    for rank = 1, 10 do
        local earned = tonumber(context:match("l" .. rank .. '%s*=%s*%{"%a+",%d+,(%d+),'))
        assert(earned, "native Yoga efficiency " .. rank)
        data.LSMoodles.Zen.Value = .25 * earned
        assert(Tiers.current(player, "yoga") == Tiers.clamp("yoga", 4, rank))
    end
    local med = readReference("lua/shared/TimedActions/LSMeditateAction.lua")
    assert(med:find("self.skillLevel > 2",1,true) and med:find("skillLevel > 5",1,true) and med:find("skillLevel == 10",1,true))
    print("PASS installed Lifestyle provider threshold/earn predicate source cross-check")
end

local bg = "media/ui/Moodles/32/_Moodles_BGsolid.png"
local border = "media/ui/Moodles/32/_Moodles_BGoutline.png"
local neutral, count = .45, {}
Color = {gray={getRedFloat=function() return neutral end,getGreenFloat=function() return neutral end,getBlueFloat=function() return neutral end}}
function getCore() return {getGoodHighlitedColor=function()
    return {getR=function() return .1 end,getG=function() return 1 end,getB=function() return .4 end}
end} end
local function available(path)
    count[path]=(count[path] or 0)+1
    if path == "media/ui/moodles/MindfulState2.png" or path == "media/ui/yoga_icon.png"
            or path == "media/ui/moodles/Zen.png" or path == bg or path == border then return path end
end
function getTexture(path)
    return available(path)
end
for kind, tiers in pairs({meditation={3},yoga={1,2,3,4}}) do
    for _, tier in ipairs(tiers) do
        local tex,tint,back,outline = Tiers.texture(kind,tier)
        assert(tex == "media/ui/moodles/" .. (kind == "meditation" and "MindfulState2.png" or "Zen.png"))
        assert(back == bg and outline == border)
        close(tint.r,neutral + (.1-neutral)*tier/4)
        close(tint.g,neutral + (1-neutral)*tier/4)
        close(tint.b,neutral + (.4-neutral)*tier/4)
    end
end
assert(count["media/ui/moodles/Zen.png"] == 1 and count[bg] == 1 and count[border] == 1)
assert(Tiers.texture("meditation",2) == nil, "missing icon leaves text menu usable")
function getTexture(path)
    if path == "media/ui/meditation_icon.png" then return path end
    error("Optional texture disappeared")
end
assert(Tiers.texture("meditation",2) == "media/ui/meditation_icon.png")
getCore = nil
local found, tint = Tiers.texture("meditation",3)
assert(found and Tiers.texture("other",3) == nil and Tiers.texture("yoga",.3) == nil)
close(tint.r,.125); close(tint.g,.875); close(tint.b,.125)
print("PASS appropriate Lifestyle asset, shared Zen glyph with exact native tint, and safe missing-art fallback")


package.loaded["AutoMindful/TierTargets"] = nil
local fresh = require "AutoMindful/TierTargets"
local fail = {getName=function() return "EngineErrorTexture" end}
local bad = {isFailure=function() return true end}
local art = {getName=function() return "Zen.png" end}
local zen = "media/ui/moodles/Zen.png"
local mounted = true
function fileExists(path) return mounted and path == zen end
local atlasSeen = {}
function getTexture(path)
    assert(path == zen or not path:find("media/",1,true), "unmounted loose asset must not reach native texture loading")
    atlasSeen[path] = true
    if path == "FavoriteStar" then return bad end
    if path == zen then return fail end
    return path
end
local med, medTint = fresh.texture("meditation",2)
local low, lowTint = fresh.texture("yoga",1)
local high, highTint = fresh.texture("yoga",4)
assert(med == "Item_Candle" and low == "Item_Dumbbell" and high == low)
assert(medTint.g > lowTint.g and lowTint.g < highTint.g and atlasSeen[zen])
mounted = false
atlasSeen = {}
fresh.texture("yoga",3)
assert(not atlasSeen[zen], "unmounted art should be skipped")
mounted = true
function getTexture(path) if path == zen then return art end end
assert(fresh.texture("yoga",3) == art, "when mounted later, don't keep an earlier atlas fallback")
print("PASS loose VFS admission, native error/failure sentinel rejection and real B42 atlas fallbacks")
