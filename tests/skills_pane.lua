-- Skills UI contracts. With installed/mirrored media, also run unmodified render.
package.path = "mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
local passed, now = 0, 1000
local function check(name, fn) fn(); passed=passed+1; print("PASS "..name) end

UIFont={Small="Small"}
function getTextManager()
    return {getFontHeight=function() return 14 end,
        MeasureStringX=function(_,font,txt) assert(font==UIFont.Small); return #txt*6 end}
end
function getTimestampMs() return now end
local players, reads = {}, {}
function getSpecificPlayer(index) return players[index] end
local function player(index,yoga)
    local p={index=index, yoga=yoga}
    function p:getPlayerNum() return self.index end
    function p:getModData() error("Skills readout must not touch save/mod data") end
    function p:getXp() return {getPerkBoost=function()return 0 end,getMultiplier=function()return 0 end} end
    players[index]=p
    return p
end
HiddenSkills={getSkill=function(p,kind)
    assert(kind=="Yoga"); reads[p]=(reads[p] or 0)+1
    if p.throw then error("Unavailable Lifestyle record") end
    return p.yoga
end}

local function perk(id,label)
    return {getId=function()return id end,getType=function()return id end,getName=function()return label or id end}
end
local med, yoga, exercise = perk("Meditation","Concentration lokale"), perk("Yoga","Yoga"), perk("Fitness")
Perks={Meditation=med}
local function button(x,y)
    local b={x=x,y=y,width=20,height=20}
    function b:getX() return self.x end
    function b:getY() return self.y end
    function b:getWidth() return self.width end
    function b:getHeight() return self.height end
    function b:setY(v) self.y=v end
    return b
end
local function pane(p,width,label)
    local w={char=p,playerNum=p.index,width=width or 460,height=180,visible=true,scroll=-30,scrollHeight=250,
        sorted={perk("Passive"),perk("Wellness",label or "Wellness"),perk("Survival")},
        perks={Passive={exercise},Wellness={med},Survival={perk("Trapping")}},
        buttonList={button(11,10),button(11,100),button(11,150)},collapse={false,false,false},
        draws={},children={},progressBars={},progressBarLoaded=true,txtLen=42,lastLevelUpTime=0}
    function w:isVisible() return self.visible end
    w.getIsVisible,w.isReallyVisible=w.isVisible,w.isVisible
    function w:getWidth() return self.width end
    function w:getHeight() return self.height end
    function w:getScrollHeight() return self.scrollHeight end
    function w:getYScroll() return self.scroll end
    function w:setYScroll(v) self.scroll=v end
    function w:setScrollHeight(n) self.scrollHeight=n; self.scroll=math.max(self.scroll,-math.max(0,n-self.height)) end
    function w:setStencilRect(...) self.stencil=true end
    function w:clearStencilRect() self.stencil=false end
    function w:drawTexture() end
    function w:setWidthAndParentWidth(v) self.width=v end
    function w:setHeightAndParentHeight(v) self.height=v end
    function w:drawText(txt,x,y,_,_,_,_,font)
        self.draws[#self.draws+1]={txt=txt,x=x,y=y,font=font}
    end
    function w:addChild() error("Yoga readout is not a widget") end
    function w:removeChild() error("Yoga readout must not remove native widgets") end
    return w
end
local function yogaDraws(w)
    local out={}
    for _,d in ipairs(w.draws) do if d.txt:find("Yoga",1,true) then out[#out+1]=d end end
    return out
end
local function render(w)
    w.draws={}
    return ISCharacterInfo.render(w,"sentinel")
end
local function displays(w,level,xp,required)
    local rows, text = yogaDraws(w), {}
    for _,d in ipairs(rows) do text[#text+1]=d.txt end
    for _,d in ipairs(w.draws) do
        if d.txt:find("XP",1,true) and not d.txt:find("Yoga",1,true) then text[#text+1]=d.txt end
    end
    text=table.concat(text," ")
    assert(#rows==1, "Expected exactly one added labeled Yoga draw; got "..#rows.." ("..text..")")
    assert(text:find(tostring(level),1,true) and text:find(tostring(xp),1,true)
        and text:find(tostring(required),1,true) and text:find("XP",1,true),"Expected level/current/required XP: "..text)
    return rows[1]
end

local a=player(0,{3,175,750})
local b=player(1,{7,25,2000})
local original=function(self,sentinel)
    self:setScrollHeight(250)
    self.buttonList[2]:setY(100)
    self:drawText(self.sorted[2]:getName(),41,103,1,1,1,1,UIFont.Small)
    return sentinel,nil,8
end
ISCharacterInfo={render=original}
local Skills = require "AutoMindful/SkillsPane"
Skills.install()
local wrapped=ISCharacterInfo.render
assert(wrapped~=original)
Skills.install()
assert(ISCharacterInfo.render==wrapped,"Repeated install must not stack render hooks")

check("draws once on the existing Meditation group heading and preserves vanilla values",function()
    local w=pane(a)
    local first,second,third=render(w)
    local d=displays(w,3,175,750)
    assert(first=="sentinel" and second==nil and third==8)
    assert(d.x >= 41+6*#"Wellness" and d.y>=100 and d.y<120,"Stay on the native heading after its title")
    assert(#w.children==0 and #w.perks.Wellness==1 and #w.buttonList==3)
    assert(w.width==460 and w.scrollHeight==250 and w.scroll==-30 and not w.stencil)
    render(w); displays(w,3,175,750)
end)

check("reads, caches, and refreshes only the owning local survivor",function()
    local wa,wb=pane(a),pane(b)
    render(wa); displays(wa,3,175,750)
    render(wb); displays(wb,7,25,2000)
    local before=reads[b]
    a.yoga={4,210,900}; now=now+250
    render(wa); displays(wa,4,210,900)
    assert(reads[b]==before)
    local stale=pane(a); stale.playerNum=1
    render(stale); assert(#yogaDraws(stale)==0)
end)

check("does not duplicate a native Yoga perk or draw when hidden or collapsed",function()
    for _,reason in ipairs({"native","collapsed","invisible"}) do
        local w=pane(a)
        if reason=="native" then w.perks.Passive[#w.perks.Passive+1]=yoga
        elseif reason=="collapsed" then w.collapse[2]=true
        else w.visible=false end
        render(w); assert(#yogaDraws(w)==0,reason)
    end
end)

check("handles missing and unreadable game data without drawing invented XP",function()
    local w=pane(a); w.perks.Wellness={}
    render(w); assert(#yogaDraws(w)==0,"Without a visible Meditation group there is no body for the Yoga readout")
    for _,data in ipairs({false,{},{"bad",175,750},{-1,175,750},{3,0,-1},{3,0/0,750}}) do
        local p=player(4,data)
        local v=pane(p); render(v); assert(#yogaDraws(v)==0)
    end
    local p=player(5,{3,175,750}); p.throw=true
    local v=pane(p); render(v); assert(#yogaDraws(v)==0)
end)

check("a vanished or incomplete Lifestyle API clears a cached Yoga readout",function()
    local w=pane(a)
    local original=HiddenSkills
    render(w); displays(w,4,210,900)
    HiddenSkills=nil
    render(w); assert(#yogaDraws(w)==0)
    HiddenSkills={}
    now=now+250
    render(w); assert(#yogaDraws(w)==0)
    HiddenSkills=original
    render(w); displays(w,4,210,900)
end)

check("a regenerated native Yoga row wins without reinstalling the render hook",function()
    local w=pane(a)
    render(w); displays(w,4,210,900)
    local registered = {}
    Perks.Yoga=registered
    local alias=perk("RegisteredWellnessSkill", "Yoga")
    function alias:getType() return registered end
    w.perks.Passive[#w.perks.Passive+1]=alias
    now=now+250
    render(w); assert(#yogaDraws(w)==0)
    Skills.install()
    assert(ISCharacterInfo.render==wrapped, "Rebuild must not add a second hook")
    render(w); assert(#yogaDraws(w)==0 and w.perks.Passive[2]==alias)
    Perks.Yoga=nil
end)

check("shows a named max state without a fictitious xp requirement",function()
    local w=pane(player(6,{10,0,0}))
    render(w)
    local rows=yogaDraws(w)
    assert(#rows==1 and rows[1].txt:find("MAX",1,true) and not rows[1].txt:find("/0",1,true))
end)

check("narrow localized heading uses a measured, stable scrollable footer",function()
    local w=pane(a,165,"Translated heading that uses the entire row")
    render(w)
    local row=displays(w,4,210,900)
    local extended=w.scrollHeight
    assert(row.y>=250 and row.x>=0 and row.x+#row.txt*6<=w.width, "Yoga footer must not clip the label")
    assert(extended>250 and w.width==165)
    w.scroll=-math.min(extended-w.height,90)
    local positioned=w.scroll
    render(w); displays(w,4,210,900)
    assert(w.scrollHeight==extended and w.scroll==positioned, "Repeated renders neither grow the footer nor lose the scroll position")
    assert(#w.children==0 and #w.buttonList==3 and #w.perks.Wellness==1 and not w.stencil)
    local impossible=pane(a,35,"Translated heading")
    render(impossible)
    assert(#yogaDraws(impossible)==0 and impossible.scrollHeight==250
        and impossible.width==35 and not impossible.stencil,"Impossible layout must not clip, grow, or create controls")
end)

if loadUpstream or (arg and arg[1]) then
    package.preload["ISUI/ISPanelJoypad"]=function()
        ISPanelJoypad={}
        function ISPanelJoypad:derive() return {} end
    end
    ISSkillProgressBar={updateAlpha=function() end}
    Events={OnResolutionChange={Add=function() end}}
    UIManager={getMillisSinceLastRender=function() return 17 end}
    function getCore() return {getOptionFontSizeReal=function() return 6 end} end
    local rel="client/XpSystem/ISUI/ISCharacterInfo.lua"
    if loadUpstream then loadUpstream(rel) else assert(loadfile(arg[1].."/lua/"..rel))() end
    local vanilla=ISCharacterInfo.render
    Skills.install()
    assert(ISCharacterInfo.render~=vanilla,"Install can bind when the declared stock class loads")
    check("unmodified stock render owns vanilla XP rows and layout",function()
        local w=pane(a)
        render(w)
        local d=displays(w,4,210,900)
        local native=0
        for _,draw in ipairs(w.draws) do if draw.txt==med:getName() then native=native+1 end end
        assert(native==1 and d.y>=w.buttonList[2]:getY() and d.y<w.buttonList[2]:getY()+20)
        assert(w.width==460 and #w.children==0 and #w.perks.Wellness==1 and not w.stencil)
    end)
end
print("SKILLS PANE PASS "..passed.." cases; drawing and game boundary doubles are explicit")
