-- Read-only lifecycle/visual geometry contract with explicit Java/UI doubles.
package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
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
print("yoga-bar: PASS (read-only Yoga sample, ten native cells, hover, joypad, max/unavailable, late assets)")
