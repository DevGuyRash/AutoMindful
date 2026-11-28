-- Read-only lifecycle/visual geometry contract with explicit Java/UI doubles.
package.path = "mods/SecondNature/common/media/lua/client/?.lua;" .. package.path
local function no() end
local function forbidden() error("Yoga must never call native perk/XP APIs") end
local function panel(name)
    local t = {Type=name}
    function t:derive(n)
        local child = panel(n)
        child.__index = child
        return setmetatable(child, {__index=self})
    end
    return t
end
ISPanel = panel("ISPanel")
function ISPanel:new(x,y,w,h)
    return setmetatable({x=x,y=y,w=w,h=h, draws={}, hovered=false, mouseX=0}, {__index=self})
end
ISPanel.noBackground = no
function ISPanel:getAbsoluteX() return self.x end
function ISPanel:getAbsoluteY() return self.y end
function ISPanel:getHeight() return self.h end
function ISPanel:isMouseOver() return self.hovered end
function ISPanel:getMouseX() return self.mouseX end
function ISPanel:drawTextureScaled(tex, x,y,w,h,a,r,g,b) table.insert(self.draws,{tex,x,y,w,h,a,r,g,b}) end
function ISPanel:drawRect(x,y,w,h,a,r,g,b) self:drawTextureScaled("primitive-fill",x,y,w,h,a,r,g,b) end
function ISPanel:drawRectBorder(x,y,w,h,a,r,g,b) self:drawTextureScaled("primitive-border",x,y,w,h,a,r,g,b) end
ISSkillProgressBar=ISPanel:derive("native")
function ISSkillProgressBar:removeTooltip()
    self.message = nil
    if self.tooltip then self.tooltip:setVisible(false); self.tooltip:removeFromUIManager(); self.tooltip = nil end
end
ISSkillProgressBar.onMouseUp, ISSkillProgressBar.activate = forbidden, forbidden
package.loaded["XpSystem/ISUI/ISSkillProgressBar"] = true
package.loaded["ISUI/ISToolTip"] = true
ISToolTip = {}
local added, removed=0, 0
function ISToolTip:new()
    return {initialise=no, addToUIManager=function() added=added+1 end,
        isMouseOver=function() return false end, getHeight=function() return 20 end,
        setOwner=function(self, owner) self.owner=owner end, setVisible=no,
        removeFromUIManager=function() removed=removed+1 end,
        setDesiredPosition=function(self,x,y) self.x=x;self.y=y end}
end

UIFont = {Small={}}
local fontHeight, spacing = 16, 2
function getTextManager() return {getFontHeight=function(_,font) assert(font==UIFont.Small); return fontHeight end} end
function getCore() return {getOptionFontSizeReal=function() return spacing end, getScreenHeight=function() return 106 end} end
function getText(key,x,y) assert(key=="IGUI_XP_tooltipxp"); return x .. " / " .. y .. " XP" end
xpSystemText = {lvl="Level", locked="Locked", unlocked="Unlocked"}
local assets
function getTexture(p) return assets and p:match("SkillUnit_(%w+)") or nil end

local survivor = {getPerkLevel=forbidden,getXp=forbidden,LevelPerk=forbidden}
local other = {getPerkLevel=forbidden,getXp=forbidden,LevelPerk=forbidden}
local samples = {[survivor]={0,3,12}, [other]={10,nil,nil}}
local calls={}
HiddenSkills={getSkill=function(p,id) assert(id=="Yoga"); calls[p]=(calls[p] or 0)+1; return samples[p] end}
getSpecificPlayer=forbidden -- display must use parent.char, not look up another local survivor
local Bar=require "AutoMindful/YogaSkillBar"
assert(Bar==AutoMindful.YogaSkillBar)
local pane={char=survivor,progressBars={}}
local bar=Bar:new(12,80,0,0,1,{getType=forbidden},pane)
pane.progressBars[1]=bar
assert(bar.x==12 and bar.y==80 and bar.cellSize==11 and bar.cellStride==13 and bar.w==130 and bar.h==11)
bar:render()
assert(bar.level==0 and #bar.draws==11 and bar.draws[1][1]=="primitive-border")
assert(bar.draws[2][1]=="primitive-fill" and bar.draws[2][4]==2.75 and bar.draws[11][2]==117)
assets=true; bar.draws={}; bar.hovered=true; bar:onMouseMove();bar:render()
assert(bar.draws[1][1]=="Border" and bar.draws[2][1]=="Fill","late-loaded native assets replace primitives")
assert(bar.tooltip.description=="Yoga Level 1 <LINE> 3 / 12 XP" and bar.tooltip.owner==bar and bar.tooltip.followMouse)
samples[survivor]={4,2.5,20}
bar.mouseX=62; bar:onMouseMove(); bar:render(); assert(bar.tooltip.description=="Yoga Level 5 <LINE> 2.5 / 20 XP")
bar.mouseX=39; bar:onMouseMove();bar:render();assert(bar.tooltip.description=="Yoga Level 4 <LINE> Unlocked")
samples[survivor]={4,20,20};bar.draws={};bar.mouseX=52;bar:onMouseMove();bar:render()
local thresholdBorder=bar.draws[10]
assert(bar.level==4 and thresholdBorder[1]=="Border" and thresholdBorder[2]==52
    and thresholdBorder[7]==1 and thresholdBorder[8]==1 and thresholdBorder[9]==1
    and bar.tooltip.description=="Yoga Level 5 <LINE> 20 / 20 XP","Show ready color without inventing level-up")
bar.mouseX=104;bar:onMouseMove();bar:render();assert(bar.tooltip.description=="Yoga Level 9 <LINE> Locked")
bar.mouseX=130;bar:onMouseMove();bar:render();assert(not bar.tooltip and added==1 and removed==1)
bar.mouseX=-1;bar:onMouseMove();assert(not bar.tooltip)
pane.char=other
pane.joyfocus=true;pane.joypadIndex=1
bar.hovered=false;bar.draws={};bar:updateTooltip(10);bar:render()
assert(bar.level==10 and #bar.draws==20 and calls[other]>0)
assert(bar.tooltip.description=="Yoga Level 10 <LINE> Unlocked <LINE> MAX" and not bar.tooltip.followMouse)
assert(bar.tooltip.x==12 and bar.tooltip.y==59)
bar:onMouseMoveOutside(); assert(not bar.tooltip)
bar:render(); assert(bar.tooltip, "selected joypad tooltip survives mouse exit")
pane.joyfocus=false;bar.hovered=true;bar:render();assert(not bar.tooltip and added==removed,"lose focus closes tooltip even if the mouse remains over another rank")
bar:activate();bar:onMouseUp()
bar.viewDescriptor={getName=function() return "Ioga" end}
bar.hovered=true;bar.mouseX=117;bar:onMouseMove();bar:render()
assert(bar.tooltip.description=="Ioga Level 10 <LINE> Unlocked <LINE> MAX")
HiddenSkills.getSkill=function() error("upstream skill changed between pane and bar") end
bar.draws={};bar:render();assert(#bar.draws==10 and not bar.progress)
assert(bar.tooltip.description=="Ioga Level 10 <LINE> XP unavailable")
bar.viewDescriptor=nil
HiddenSkills=nil;bar.draws={};bar:render();assert(#bar.draws==10 and bar.level==0)
bar.hovered=true;bar.mouseX=0;bar:onMouseMove();bar:render()
assert(bar.tooltip.description=="Yoga Level 1 <LINE> XP unavailable")
bar:removeTooltip();assert(not bar.tooltip and added==removed)
fontHeight,spacing=24,4
local neighbor={getHeight=function() return 11 end,getWidth=function() return 130 end}
local matching=Bar:new(12,80,0,0,1,nil,pane,neighbor)
assert(matching.h==11 and matching.w==130 and matching.cellStride==13,"Use adjacent native bar geometry after live settings change")
neighbor.getWidth=function() return 100 end
local fallback=Bar:new(12,80,0,0,1,nil,pane,neighbor)
assert(fallback.h==15 and fallback.w==190 and fallback.cellStride==19,"Reject undersized native geometry and use current formula")

-- Tooltips follow the hovered rank. Unknown providers keep their localized
-- notes; verified upstream facts augment the unmodified XP status.
local locale = {
    UI_LSHS_Yoga_1 = "Setup flavor, not an effect. <LINE> o Begins a short Zen state <LINE>",
    UI_LSHS_Yoga_3 = "<RGB:1,1,1>o Intermediate poses <LINE> o Longer Zen <LINE> o Intermediate poses <LINE><IMAGE:ignored.png>",
    UI_LSHS_Yoga4 = "More poses",
    UI_LSHS_Yoga_7 = "UI_LSHS_Yoga_7", -- older environments can return a key for missing text
    UI_LSHS_Yoga_9 = "   ",
    UI_LSHS_Yoga_General = "Do not repeat generic rank hints",
    UI_LSHS_Yoga_10_mp = "o Teach Yoga",
}
function getTextOrNull(key) return locale[key] end
local multiplayer=false
function isClient() return multiplayer end
local data={WasTaughtLast="Yoga",LSMoodles={WasTaughtSkill={Value=.19}}}
local modReads=0
function survivor:hasModData() return true end
function survivor:getModData() modReads=modReads+1; return data end
function other:hasModData() return false end
function other:getModData() error("Must not initialize missing player data") end
local checkedVersion="unverified"
function getModInfoByID(id)
    assert(id=="LifestyleHobbies")
    return {getModVersion=function() return checkedVersion end}
end
HiddenSkills={getSkill=function(p,id) assert(id=="Yoga"); calls[p]=(calls[p] or 0)+1; return samples[p] end}
bar.viewDescriptor=nil
pane.char, samples[survivor] = survivor, {0,3,12}
local function expect(cell,text)
    local before=calls[pane.char] or 0
    bar:updateTooltip(cell)
    assert(calls[pane.char]==before+1, "Hover must not add another HiddenSkills read")
    assert(bar.message == text,"wanted ["..text.."] but got ["..tostring(bar.message).."]")
end

SandboxVars={Yoga={YogaXPMultiplier=1}}
expect(0,"Yoga Level 1 <LINE> 3 / 12 XP <LINE><LINE> - Begins a short Zen state")
expect(2,"Yoga Level 3 <LINE> Locked <LINE><LINE> - Intermediate poses <LINE> - Longer Zen")
expect(3,"Yoga Level 4 <LINE> Locked <LINE><LINE> - More poses")
expect(4,"Yoga Level 5 <LINE> Locked")
expect(6,"Yoga Level 7 <LINE> Locked")
expect(8,"Yoga Level 9 <LINE> Locked")
expect(9,"Yoga Level 10 <LINE> Locked")
multiplayer=true
expect(9,"Yoga Level 10 <LINE> Locked <LINE><LINE> - Teach Yoga")
SandboxVars.Yoga.YogaXPMultiplier=1.75
expect(9,"Yoga Level 10 <LINE> Locked <LINE><LINE> - Teach Yoga <LINE> Yoga XP setting: x1.75")
expect(1,"Yoga Level 2 <LINE> Locked <LINE><LINE> Yoga XP setting: x1.75")
data.LSMoodles.WasTaughtSkill.Value=.2
checkedVersion="0.4.0.3"
local verifiedRankOne="Yoga Level 1 <LINE> 3 / 12 XP <LINE><LINE> - Zen duration: locked to 20m-30m in-game after a successful finish"
    .. " <LINE> - Completion bonus cap: 10 to 15 base XP <LINE> - Max fall chance per roll: 55% to 45%"
    .. " <LINE> - Begins a short Zen state <LINE> Yoga XP setting: x1.75"
expect(0,verifiedRankOne.." <LINE> Yoga lesson boost active")
checkedVersion="0.4.9"
expect(0,"Yoga Level 1 <LINE> 3 / 12 XP <LINE><LINE> - Begins a short Zen state <LINE> Yoga XP setting: x1.75")
checkedVersion="0.4.0.3"
data.WasTaughtLast="Meditation"
expect(0,verifiedRankOne)
data.WasTaughtLast="Yoga"
SandboxVars.Yoga.YogaXPMultiplier=1
expect(1,"Yoga Level 2 <LINE> Locked <LINE><LINE> - Pose target per session: 2 to 3 <LINE> - Completion bonus cap: 15 to 20 base XP"
    .. " <LINE> - Max fall chance per roll: 45% to 25% <LINE> Yoga lesson boost active")
data.LSMoodles.WasTaughtSkill.Value=.19
checkedVersion="unverified"
SandboxVars.Yoga.YogaXPMultiplier=.5
expect(1,"Yoga Level 2 <LINE> Locked <LINE><LINE> Yoga XP setting: x0.5")
local readBefore=modReads
pane.char=other
expect(9,"Yoga Level 10 <LINE> Unlocked <LINE> MAX <LINE><LINE> - Teach Yoga")
expect(2,"Yoga Level 3 <LINE> Unlocked <LINE><LINE> - Intermediate poses <LINE> - Longer Zen")
assert(modReads==readBefore,"Capped or different survivor must not read the prior survivor's data")

pane.char=survivor
samples[survivor]={9,81,9000}
expect(9,"Yoga Level 10 <LINE> 81 / 9000 XP <LINE><LINE> - Teach Yoga <LINE> Yoga XP setting: x0.5")
for _,invalid in ipairs({{},false,0,-1,"1.5",math.huge,0/0}) do
    SandboxVars.Yoga.YogaXPMultiplier=invalid
    expect(6,"Yoga Level 7 <LINE> Unlocked")
end
SandboxVars=nil
expect(9,"Yoga Level 10 <LINE> 81 / 9000 XP <LINE><LINE> - Teach Yoga")
locale.UI_LSHS_Yoga_5="o Newly translated effect" -- never cache missing rank text
expect(4,"Yoga Level 5 <LINE> Unlocked <LINE><LINE> - Newly translated effect")
getTextOrNull=function() error("Optional provider temporarily unavailable") end
expect(4,"Yoga Level 5 <LINE> Unlocked")
assert(data.WasTaughtLast=="Yoga" and data.LSMoodles.WasTaughtSkill.Value==.19)

-- Use stock doLayout's interface as a double: next visible frame must use the
-- new description's dimensions, not the previous short tooltip's size.
local makeTip = ISToolTip.new
function ISToolTip:new(...)
    local tip = makeTip(self, ...)
    function tip:doLayout()
        local large = self.description:find("Long translated note",1,true)
        self.w, self.h = large and 140 or 75, large and 70 or 22
    end
    function tip:getWidth() return self.w or 0 end
    function tip:getHeight() return self.h or 0 end
    return tip
end
local oldCore = getCore
function getCore()
    local base=oldCore()
    base.getScreenWidth=function() return 220 end
    return base
end
bar:removeTooltip()
bar.x,bar.y,bar.hovered=185,66,true
locale.UI_LSHS_Yoga_4="Long translated note <LINE> Extra detail"
function getTextOrNull(key) return locale[key] end
bar.mouseX=65;bar:onMouseMove();bar:render()
assert(bar.tooltip.x<=145 and bar.tooltip.y+bar.tooltip:getHeight()<=106)
bar.mouseX=39;bar:onMouseMove();bar:render()
assert(bar.tooltip.x==80 and bar.tooltip.y==0 and bar.tooltip:getHeight()==70,
    "The first long-tooltip placement uses the newly measured width and height")
print("yoga-bar: PASS (read-only Yoga sample, ten native cells, hover, joypad, max/unavailable, late assets)")
