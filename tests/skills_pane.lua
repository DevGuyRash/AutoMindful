-- Explicit Lua UI/player doubles. stock_skills_pane.lua reuses these boundaries
-- but replaces the pane/bar implementation with untouched pinned B42 source.
package.path="mods/SecondNature/common/media/lua/client/?.lua;"..package.path
local H={now=1000,players={},reads={},writes=0,passed=0}
UIFont={Small="Small"}; Perks={None="None",Meditation="Meditation"}
function getTimestampMs() return H.now end
function getTextManager() return {getFontHeight=function()return 14 end,MeasureStringX=function(_,f,s)return #s*6 end} end
function getText(k,...) if k=="IGUI_perks_Yoga" then return "Yoga" end;return k end
function getTextOrNull(k) if k=="IGUI_perks_Yoga" then return "Yoga" end end
function getSpecificPlayer(i) return H.players[i] end
function getCore() return {getOptionFontSizeReal=function()return 6 end,getScreenHeight=function()return 1000 end,getGoodHighlitedColor=function()return {getR=function()return .2 end,getG=function()return 1 end,getB=function()return .2 end}end} end
function getPerformance()return {getUIRenderFPS=function()return 60 end}end
function getTexture(name)return {getWidth=function()return 10 end,getHeight=function()return 10 end,name=name}end
function round(n)return n end
xpSystemText={lvl="Level",unlocked="Unlocked",locked="Locked"}
UIManager={getMillisSinceLastRender=function()return 17 end}
Events={OnResolutionChange={Add=function()end},OnGameStart={Add=function()end}}
HiddenSkills={getSkill=function(p,k) assert(k=="Yoga");H.reads[p]=(H.reads[p] or 0)+1;if p.throw then error("unreadable") end;return p.yoga end}
ISPanel={}
function ISPanel:derive(kind)local o={Type=kind};o.__index=o;setmetatable(o,{__index=self});return o end
function ISPanel:new(x,y,w,h)local o={x=x,y=y,width=w,height=h,children={},draws={}};setmetatable(o,{__index=self});return o end
for _,k in ipairs({"initialise","instantiate","noBackground","setAnchorRight","setAnchorBottom","addToUIManager","removeFromUIManager","setOwner","bringToTop"})do ISPanel[k]=function()end end
function ISPanel:getX()return self.x end; function ISPanel:getY()return self.y end
function ISPanel:getWidth()return self.width end;function ISPanel:getHeight()return self.height end
function ISPanel:setX(x)self.x=x end;function ISPanel:setY(y)self.y=y end
function ISPanel:setWidth(w)self.width=w end;function ISPanel:setHeight(h)self.height=h end
function ISPanel:getAbsoluteX()return self.x end;function ISPanel:getAbsoluteY()return self.y end
function ISPanel:isMouseOver()return false end;function ISPanel:getMouseX()return 0 end
function ISPanel:setVisible(v)self.visible=v end;function ISPanel:isVisible()return self.visible~=false end
ISPanel.isReallyVisible=ISPanel.isVisible;ISPanel.getIsVisible=ISPanel.isVisible
function ISPanel:drawTextureScaled(...)end;function ISPanel:drawRect(...)end
function ISPanel:drawRectBorder(...)self.border={...}end
function ISPanel:drawTexture(...)end;function ISPanel:drawText(s,x,y)self.draws[#self.draws+1]={txt=s,x=x,y=y}end
function ISPanel:setStencilRect()end;function ISPanel:clearStencilRect()end
function ISPanel:addChild(c)c.parent=self;self.children[#self.children+1]=c end
function ISPanel:removeChild(c)for i=#self.children,1,-1 do if self.children[i]==c then table.remove(self.children,i)end end end
function ISPanel:getYScroll()return self.scroll or 0 end;function ISPanel:setYScroll(v)self.scroll=v end
function ISPanel:setScrollHeight(v)self.scrollHeight=v end;function ISPanel:getScrollHeight()return self.scrollHeight end
function ISPanel:setWidthAndParentWidth(v)self.width=v end;function ISPanel:setHeightAndParentHeight(v)self.height=v end
ISToolTip=ISPanel:derive("ISToolTip")
function ISToolTip:setDesiredPosition(x,y)self.x=x;self.y=y end
ISPanelJoypad=ISPanel:derive("ISPanelJoypad")
package.preload["ISUI/ISPanel"]=function()return ISPanel end
package.preload["ISUI/ISPanelJoypad"]=function()return ISPanelJoypad end
package.preload["ISUI/ISToolTip"]=function()return ISToolTip end
function H.perk(id)
 return {getId=function()return id end,getType=function()return id end,getName=function()return id end,
 isPassiv=function()return true end,getXpForLevel=function()return 100 end,getTotalXpForLevel=function()return 100 end}
end
function H.player(slot,yoga)
 local p={slot=slot,yoga=yoga or {3,25,100}}
 function p:getPlayerNum()return self.slot end
 function p:getModData()error("UI must not write/read persistent gameplay data")end
 function p:getPerkLevel(k)assert(k~="None","Synthetic Yoga must not query native None level");return 2 end
 function p:LevelPerk()H.writes=H.writes+1;error("XP write")end
 function p:getXp()return {getPerkBoost=function()return 0 end,getMultiplier=function()return 0 end,getXP=function()return 25 end,AddXP=function()H.writes=H.writes+1;error("XP write")end}end
 H.players[slot]=p;return p
end
function H.pane(p)
 local w=ISPanel:new(0,0,460,180);setmetatable(w,{__index=ISCharacterInfo})
 w.char=p;w.playerNum=p.slot;w.visible=true;w.scroll=-20;w.lastLevelUpTime=0;w.txtLen=60
 w.sorted={H.perk("Wellness"),H.perk("Survival")}
 w.perks={Wellness={H.perk("Meditation"),H.perk("Music")},Survival={H.perk("Trapping")}}
 w.buttonList={ISPanel:new(11,0,20,20),ISPanel:new(11,0,20,20)};w.collapse={false,false};w.progressBars={};w.progressBarLoaded=false
 return w
end
local function row(w,name)local found;for _,d in ipairs(w.draws)do if d.txt==name then assert(not found,"duplicate label "..name);found=d end end;return found end
local function bars(w)local found;for _,b in ipairs(w.progressBars)do if b.Type=="AutoMindfulYogaSkillBar" then assert(not found,"duplicate Yoga child");found=b end end;return found end
function H.render(w)w.draws={};return ISCharacterInfo.render(w)end
function H.check(n,f)f();H.passed=H.passed+1;print("PASS "..n)end
function H.run()
 package.preload["XpSystem/ISUI/ISSkillProgressBar"]=function()return ISSkillProgressBar end
 local Skills=require "AutoMindful/SkillsPane";local prior=ISCharacterInfo.render;Skills.install();local wrapper=ISCharacterInfo.render
 assert(wrapper~=prior);Skills.install();assert(wrapper==ISCharacterInfo.render)
 H.check("native slot below Meditation shifts Music/category/canvas exactly one row",function()
  local p=H.player(0);local plain=H.pane(p);prior(plain);local music,heading,height=row(plain,"Music"),row(plain,"Survival"),plain.scrollHeight
  local w=H.pane(p);local list,perks,char,new=w.perks.Wellness,w.perks,w.char,ISSkillProgressBar.new
  H.render(w);local m,y,n=row(w,"Meditation"),row(w,"Yoga"),row(w,"Music");local b=bars(w)
  assert(y and b,"Expected real Yoga row/widget, not header/footer")
  assert(y.x==m.x and y.y==m.y+20 and n.y==music.y+20 and row(w,"Survival").y==heading.y+20 and w.scrollHeight==height+20)
  assert(b:getX()==w.progressBars[1]:getX() and b:getY()==w.progressBars[1]:getY()+20)
  assert(w.char==char and w.perks==perks and w.perks.Wellness==list and #list==2 and ISSkillProgressBar.new==new)
  local count=#w.children;H.render(w);assert(#w.children==count and #w.progressBars==4 and bars(w)==b,"Repeated render duplicated or replaced stable bars")
 end)
 H.check("collapsed, native Yoga, invalid/local-player data do not invent a duplicate row",function()
  for _,kind in ipairs({"collapse","native","missing","foreign","invalid","hidden"})do
   local p=H.player(0);local w=H.pane(p)
   if kind=="collapse" then w.collapse[1]=true elseif kind=="native"then table.insert(w.perks.Wellness,H.perk("Yoga"))
   elseif kind=="hidden"then w.visible=false elseif kind=="missing"then p.yoga=false elseif kind=="foreign"then H.player(1);w.playerNum=1 elseif kind=="invalid"then p.throw=true end
   local list=w.perks.Wellness;H.render(w)
   if kind=="native"then assert(row(w,"Yoga") and #w.progressBars==4)else assert(not row(w,"Yoga"),kind)end
   assert(w.perks.Wellness==list)
  end
 end)
 H.check("collapse and reopen rebuild preserves row and subsequent layout",function()
  local w=H.pane(H.player(0));H.render(w);local height=w.scrollHeight
  w.collapse[1]=true;w.reloadSkillBar=true;H.render(w);assert(not row(w,"Yoga") and not bars(w))
  w.collapse[1]=false;w.reloadSkillBar=true;H.render(w);assert(row(w,"Yoga") and bars(w) and w.scrollHeight==height)
 end)
 H.check("split-player rows never query another survivor or mutate XP",function()
  local p,q=H.player(0,{2,12,100}),H.player(1,{7,66,200});local a,b=H.pane(p),H.pane(q)
  H.render(a);local before=H.reads[p];H.render(b);assert(H.reads[p]==before and H.reads[q])
  local bar=bars(b);assert(bar);if bar.render then bar:render()end
  assert(H.writes==0)
 end)
 H.check("live native Yoga and disappearing hidden data remove only our extra widget",function()
  local p=H.player(0);local w=H.pane(p);H.render(w);assert(bars(w))
  local list=w.perks.Wellness;table.insert(list,H.perk("Yoga"));H.now=H.now+251
  H.render(w);assert(not bars(w) and row(w,"Yoga") and #w.progressBars==4 and w.perks.Wellness==list)
  table.remove(list);w.reloadSkillBar=true;p.yoga=false;H.now=H.now+251;H.render(w)
  assert(not row(w,"Yoga") and not bars(w) and #w.progressBars==3)
  p.yoga={4,99,100};H.now=H.now+251;H.render(w);assert(bars(w) and #w.progressBars==4)
 end)
 H.check("localized Yoga expands all native bar columns consistently without retaining txtLen override",function()
  local translation=getTextOrNull
  getTextOrNull=function(k)if k=="IGUI_perks_Yoga"then return "Yoga translated extended title"end end
  local w=H.pane(H.player(0));local width=w.txtLen;H.render(w)
  assert(row(w,"Yoga translated extended title") and bars(w) and w.txtLen==width)
  for _,b in ipairs(w.progressBars)do assert(b:getX()==w.progressBars[1]:getX())end
  getTextOrNull=translation
 end)
 H.check("native exceptions restore original list, char and constructor",function()
  local w=H.pane(H.player(0));local perks,list,char,new=w.perks,w.perks.Wellness,w.char,ISSkillProgressBar.new
  w.drawText=function()error("expected native draw failure")end
  local ok=pcall(H.render,w);assert(not ok,"Original renderer failure must propagate")
  assert(w.perks==perks and w.perks.Wellness==list and w.char==char and ISSkillProgressBar.new==new)
 end)
 H.check("constructor failure after Yoga restores temporary overrides",function()
  local w=H.pane(H.player(0));local perks,list,char,txt=w.perks,w.perks.Wellness,w.char,w.txtLen
  local ctor=ISSkillProgressBar.new
  local failing=function(self,x,y,width,height,slot,perk,parent)
   if perk:getName()=="Music"then error("expected native constructor failure")end
   return ctor(self,x,y,width,height,slot,perk,parent)
  end
  ISSkillProgressBar.new=failing
  local ok=pcall(H.render,w)
  assert(ISSkillProgressBar.new==failing,"Lost caller's constructor override on failure")
  ISSkillProgressBar.new=ctor
  assert(not ok and w.perks==perks and w.perks.Wellness==list and w.char==char and w.txtLen==txt)
  H.render(w);assert(bars(w) and #w.progressBars==4 and #w.children==4,"Failed native rebuild leaked provisional children")
 end)
 if ISCharacterInfo.updateTooltipForJoypad then
 H.check("stock joypad selects Yoga child and hover without native level changes",function()
  local w=H.pane(H.player(0));H.render(w);w.joyfocus=true;w.joypadIndex=2
  ISCharacterInfo.updateTooltipForJoypad(w);assert(w.barWithTooltip==bars(w));assert(w.barWithTooltip.message or w.barWithTooltip.tooltip)
  w.joypadIndex=3;ISCharacterInfo.updateTooltipForJoypad(w);assert(w.barWithTooltip==w.progressBars[3]);assert(H.writes==0)
 end)
 end
 print("SKILLS SLOT PASS "..H.passed.." (explicit UI/player doubles)")
end
if AutoMindfulSkillsHarnessOnly then return H end
-- Portable stock-shaped render. The separate replay uses the exact B42 code.
ISSkillProgressBar=ISPanel:derive("ISSkillProgressBar")
function ISSkillProgressBar:removeTooltip()self.message=nil;if self.tooltip then self.tooltip:setVisible(false);self.tooltip:removeFromUIManager();self.tooltip=nil end end
function ISSkillProgressBar:new(x,y,w,h,slot,perk,parent)local b=ISPanel.new(self,x,y,160,10);b.perk=perk;b.char=getSpecificPlayer(slot);b.level=b.char:getPerkLevel(perk:getType());return b end
ISCharacterInfo=ISPanel:derive("ISCharacterInfo")
function ISCharacterInfo:render()
 if self.reloadSkillBar then for _,b in ipairs(self.progressBars)do self:removeChild(b)end;self.progressBars={};self.progressBarLoaded=false;self.reloadSkillBar=false end
 local y=10
 for i,parent in ipairs(self.sorted)do
  self:drawText(parent:getName(),41,y+3);self.buttonList[i]:setY(y);y=y+20
  if not self.collapse[i]then y=y+10;for _,perk in ipairs(self.perks[parent:getType()])do
   self.char:getXp():getPerkBoost(perk:getType());self.char:getXp():getMultiplier(perk:getType())
   self:drawText(perk:getName(),61,y+3)
   if not self.progressBarLoaded then local b=ISSkillProgressBar:new(71+self.txtLen,y+5,0,0,self.playerNum,perk,self);b:initialise();self:addChild(b);table.insert(self.progressBars,b)end
   y=y+20
  end end;y=y+10
 end;self:setScrollHeight(y+1);self.progressBarLoaded=true
end
H.run()
