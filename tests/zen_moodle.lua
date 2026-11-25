if package.path then package.path="mods/AutoMindful/common/media/lua/client/?.lua;"..package.path end
if not loadUpstream and arg and arg[1] then
    function loadUpstream(name) return assert(loadfile(arg[1].."/lua/"..name))() end
end
local Zen = require "AutoMindful/ZenMoodle"
local function noop() end
local supported = true
function getModInfoByID(id)
    assert(id == "LifestyleHobbies")
    return {getModVersion=function() return supported and "0.4.0.3" or "99" end}
end
local painted, rect, mx, my = {}, nil, 905, 707
local classes = {}
UIFont={Small=1,Medium=2,Large=3}
LS_AMcache={mf_cached=true}
Events={OnPlayerDeath={Add=noop},OnCreatePlayer={Add=noop}}
Color={gray={getRedFloat=function() return 0 end,getGreenFloat=function() return 0 end,getBlueFloat=function() return 0 end}}
function getMouseX() return mx end
function getMouseY() return my end
local core={getScreenWidth=function() return 960 end,getScreenHeight=function() return 720 end,
    getOptionMoodleSize=function() return 1 end}
function getCore() return core end
Registries={MOODLE_TYPE={values=function() return {size=function() return 0 end} end}}
SandboxVars={Debug={}}
function getTextManager()
    return {getFontHeight=function() return 13 end, MeasureStringX=function(_,_,s) return 6*#s end}
end
ISUIElement={}
function ISUIElement:derive(name)
    local cls=setmetatable({}, {__index=self})
    classes[#classes+1]=cls
    return cls
end
function ISUIElement:new() return {} end
function ISUIElement:isMouseOver() return false end
function ISUIElement:addToUIManager() end
function ISUIElement:getX() return 900 end
function ISUIElement:getY() return 700 end
function ISUIElement:getWidth() return 32 end
function ISUIElement:getHeight() return 32 end
function ISUIElement:drawRect(x,y,w,h) rect={x=x,y=y,w=w,h=h} end
function ISUIElement:drawTextRight(s) painted[#painted+1]=s end
function getPlayerScreenTop() return 0 end
local md={LSMoodles={Zen={Value=.2,Level=0},Other={Value=.8,Level=0}},LSZenActive={squats=.4,press=.6}}
local p={getModData=function() return md end,getMoodles=function() return {} end}
FitnessExercises={exercisesType={squats={xpMod=.7},press={xpMod=.9}}}
if loadUpstream then
    loadUpstream("client/LSMoodleManager.lua")
else
    LSMoodleManager={newType=function(player,name)
        local cls=ISUIElement:derive("ISMoodles")
        function cls:level()
            local value=player:getModData().LSMoodles[name].Value
            if value >= .7 then return 4 elseif value >= .5 then return 3 elseif value >= .3 then return 2 elseif value >= .15 then return 1 end
            return 0
        end
        function cls:mouseOverMoodle(_,title,description)
            self:drawTextRight(title)
            self:drawTextRight(description)
        end
        return setmetatable({}, {__index=cls})
    end}
    function LSMoodleManager.createType(player,name) LSMoodleManager.newType(player,name):addToUIManager() end
end
Zen.install()
local wrapped=LSMoodleManager.newType
Zen.install()
assert(wrapped == LSMoodleManager.newType)
LSMoodleManager.createType(p,"Other") -- enables upstream renderer
local otherClass=classes[#classes]
local other=LSMoodleManager.newType(p,"Other")
assert(other.mouseOverMoodle == classes[#classes].mouseOverMoodle and otherClass)
local icon=LSMoodleManager.newType(p,"Zen")
assert(icon.mouseOverMoodle ~= classes[#classes].mouseOverMoodle)
local desc="A clear mind and a centered chi will help you improve your body faster. Namaste!"
local function render()
    painted,rect={},nil
    icon:mouseOverMoodle("Zen","Zen",desc)
    return table.concat(painted," ")
end
for i, marker in ipairs({"I","II","III","IV"}) do
    md.LSMoodles.Zen.Value=({.2,.31,.51,.71})[i]
    local out=render()
    assert(painted[1] == "Zen "..marker)
    assert(out:find(desc,1,true))
    assert(out:find(string.format("Meditation XP: +%d%% (x%.1f)", 110*i-100, 1.1*i),1,true))
    assert(out:find("Yoga pose XP factor: +"..math.ceil(i/2),1,true))
    assert(out:find("- Workout XP setting: +0.30",1,true))
    assert(rect and rect.y+700+rect.h<=720 and rect.x+900>=0)
end
assert(md.LSMoodles.Zen.Level == 0 and md.LSMoodles.Zen.Value == .71)
FitnessExercises.exercisesType.press.xpMod=1.2
assert(not render():find("Workout",1,true),"Unequal exercise deltas must not be attributed to Zen")
supported=false
assert(painted and not render():find("XP",1,true) and painted[1]=="Zen IV")
mx,my=0,0
assert(render()=="" and not rect)
mx,my=905,707
md.LSMoodles.Zen.Value=0
assert(render()=="" and not rect)
print(loadUpstream and "PASS actual Lifestyle Zen widget factory, tier thresholds and hover hook with UI doubles"
    or "PASS Zen tiers, original description, distinct effects, and hover with portable doubles")
