-- Portable contracts; pass GAME/media and LIFESTYLE/common/media to exercise the
-- real timed-action effects. The native Kahlua runner can select either reference
-- tree with stock_hygiene.lua or lifestyle_hygiene.lua. No game/server is launched.
package.path = "mods/SecondNature/common/media/lua/client/?.lua;" .. package.path
local Care = require "AutoMindful/HygieneCare"
local empty = function() end
local function list(t)
    function t:size() return #self end
    function t:get(i) return self[i+1] end
    function t:isEmpty() return #self == 0 end
    function t:contains(v) for i=1,#self do if self[i]==v then return true end end return false end
    return t
end
local function script(side,path)
    if loadUpstream and HYGIENE_REFERENCE == side then loadUpstream(path); return true end
    local root = arg and arg[side == "game" and 1 or 2]
    if root and root ~= "-" then dofile(root.."/lua/"..path); return true end
    return false
end
local function class(name)
    local c={Type=name}; c.__index=c
    return setmetatable(c, {__index=ISBaseTimedAction})
end
package.loaded["TimedActions/ISBaseTimedAction"] = true
package.loaded["ISUI/ISInventoryPane"] = true
package.loaded["LSEffects/LSPerMinute"] = true
ISBaseTimedAction={new=function(self,p) return setmetatable({character=p},self) end,
    isValidStart=function()return true end,perform=empty,setOverrideHandModels=empty,
    derive=function(_,name) return class(name) end}
ISWaitWhileGettingUp={new=function(_,p) return {Type="ISWaitWhileGettingUp",character=p} end}
ISWashClothing={GetSoapRemaining=function()return 0 end}
BloodBodyPartType={MAX={index=function()return 4 end}, FromIndex=function(i)return i end}
ItemBodyLocation={}; CharacterStat={UNHAPPINESS="UNHAPPINESS"}
LSMoodHandler={PerMin={}}
CharacterTrait={TIDY="Tidy",SLOPPY="Sloppy",CLEANFREAK="CleanFreak"}
ModData={getOrCreate=function()return {SO={HNE=3}} end}
HaloTextHelper={addGoodText=empty}
function getText(t) return t end
function ZombRand() return 0 end
local calls={}; local cells={}; local player; local client=true; local receiver, pending
function newrandom() return {random=function() return 1 end} end
Events={OnInitGlobalModData={Add=empty},OnClientCommand={Add=function(f)receiver=f end}}
function sendClientCommand(p,m,c,a) pending={player=p,module=m,command=c,args=a} end
function isClient() return client end
SafeHouse={isSafehouseAllowInteract=function(s) return s.allow ~= false end,
    isSafehouseAllowLoot=function(s) return s.loot ~= false end}
function getCell() return {getGridSquare=function(_,x,y,z) return cells[x..":"..y..":"..z] end} end
luautils={getCorrectSquareForWall=function(_,sq) return sq.correct or sq end}
function instanceof(x,name) return x and x.class==name end
ComponentType={FluidContainer="fluid"}
local visual={blood={},dirt={}}
function visual:getBlood(p) return self.blood[p] or 0 end
function visual:getDirt(p) return self.dirt[p] or 0 end
function visual:setBlood(p,v) self.blood[p]=v end
function visual:setDirt(p,v) self.dirt[p]=v end
function sendHumanVisual() calls.visual=(calls.visual or 0)+1 end
function syncItemFields() calls.itemSync=(calls.itemSync or 0)+1 end
function sendItemStats() calls.itemStats=(calls.itemStats or 0)+1 end
function isServer() return client == false end
LSUtil={changeCharacterMood=empty}
function LSUtil.adjustFluid(item,n) item.amount=item.amount-n end

local nativeWash = script("game","shared/TimedActions/ISWashYourself.lua")
if not nativeWash then
    ISWashYourself=class("ISWashYourself")
    function ISWashYourself.GetRequiredWater(p)
        local n=0; for i=0,3 do if p:getHumanVisual():getBlood(i)+p:getHumanVisual():getDirt(i)>0 then n=n+1 end end
        return n
    end
    function ISWashYourself:new(p,sink) return setmetatable({character=p,sink=sink},self) end
    function ISWashYourself:isValid() return true end
end
local nativeLife=script("lifestyle","client/Hygiene/PerfumeContextMenu.lua")
if nativeLife then
    script("lifestyle","shared/LSUtil.lua")
    LSUtil.changeCharacterMood=empty -- mood/HUD is not the receipt under test
    client=false;script("lifestyle","server/LSservercommands.lua");client=true
    script("lifestyle","shared/TimedActions/LSApplyPerfumeAction.lua")
    script("lifestyle","client/Hygiene/HygieneNeed.lua")
else
    PerfumeContextMenu={UseDelta=0.005}
    LSApplyPerfumeAction=class("LSApplyPerfumeAction")
    function LSApplyPerfumeAction:new(p,item,delta) return setmetatable({character=p,item=item,useDelta=delta},self) end
    function LSApplyPerfumeAction:isValid()return true end
end

local function square(x,y,z,b)
    local s={x=x,y=y,z=z,building=b,objects=list({}),world=list({})}
    function s:getX()return self.x end;function s:getY()return self.y end;function s:getZ()return self.z end
    function s:getBuilding()return self.building end;function s:getObjects()return self.objects end
    function s:getWorldObjects()return self.world end
    function s:canReachTo(target) return not target.wall end
    cells[x..":"..y..":"..z]=s
    return s
end
local function source(s,kind)
    local o={sq=s,class=kind or "IsoObject",amount=10,water=true}
    function o:getSquare()return self.sq end; function o:getFluidAmount()return self.amount end
    function o:hasWater()return self.water and self.amount>0 end;function o:hasFluid()return self.amount>0 end
    function o:hasComponent(comp)return comp=="fluid" and self.component==true end
    function o:getFluidContainer()return {canPlayerEmpty=function()return o.emptyable~=false end} end
    function o:isLockedToCharacter()return self.locked end;function o:getMasterTrough()return self.master or self end
    function o:getItem()return self.item end;function o:useFluid(n)self.amount=self.amount-n;return n end
    function o:transmitModData()self.transmitted=true end
    local where=kind=="IsoWorldInventoryObject" and s.world or s.objects; where[#where+1]=o
    return o
end
local function setNeed(raw,bad,scent)
    player.data={hygieneNeed=raw,LSMoodles={HygieneBad={Value=bad},SmellGood={Value=scent},HygieneGood={Value=0}}}
end
local function bottle(name,fluid)
    local i={id=#player.inv+27,class="InventoryItem",amount=.030,name=name or "Base.Cologne",fluid=fluid or "Cologne",place=player.inv}
    function i:getID()return self.id end; function i:getFullType()return self.name end;function i:isSealed()return self.sealed==true end
    function i:getContainer()return self.place end
    function i:getFluidContainer()return {getPrimaryFluid=function()return i.fluid and {getFluidTypeString=function()return i.fluid end} end,
        getAmount=function()return i.amount end,adjustAmount=function(_,v)i.amount=v end} end
    i.getFluidContainerFromSelfOrWorldItem=i.getFluidContainer
    player.inv[#player.inv+1]=i
    return i
end
local queue={}; ISTimedActionQueue={add=function(a)queue[#queue+1]=a end}
local home=square(1,1,0,"house")
player={here=home,inv=list({})}
player.inv.getSoapList=function()return list({}) end;player.inv.getItems=function(self)return self end;player.inv.setDrawDirty=empty
function player:getSquare()return self.here end;function player:getX()return self.here.x+.5 end;function player:getY()return self.here.y+.5 end
function player:getBuilding()return self.here.building end;function player:getModData()return self.data end
function player:getInventory()return self.inv end;function player:getHumanVisual()return visual end
function player:isSitting()return self.seated end;function player:isTimedActionInstant()return false end
function player:getStats()return {remove=empty} end;function player:getEmitter()return {playSound=empty,isPlaying=function()return false end} end
function player:isFemale()return false end;function player:getWornItem()return nil end
function player:resetModelNextFrame()end;function player:getHoursSurvived()return 999 end
function player:isAsleep()return false end;function player:hasTrait()return false end
function player:isGodMod()return false end
SandboxVars={Text={DividerHygiene=true},LSHygiene={HygieneNeedMultiplier=1}}
local perfume=bottle("Base.Perfume","PerfumeFloral")
for _,r in ipairs({{60,.2,0,0},{60.00001,.2,0,1},{70,.2,0,1},{70.002,.4,0,2},{80,.4,0,2},
        {80.0001,.6,0,3},{90,.6,0,3},{90.001,.8,0,4},{92,.8,.001,2},{78,.4,.001,0},{65,0,0,0}})do
    setNeed(r[1],r[2],r[3]);assert(Care.need(player)==r[4],"need boundary "..r[1])
    assert(Care.item(player,perfume)==(r[3]==0 and r[4]>0),"scent must improve the current moodle")
end
setNeed(75,.4,0)
assert(Care.item(player,perfume));local cologne=bottle();assert(Care.item(player,cologne))
assert(not Care.item(player,bottle("Base.Bleach","Perfume")))
assert(not Care.item(player,bottle("Base.Perfume","Water")))
assert(not Care.item(player,bottle("Base.Shampoo","Shampoo")))
cologne.amount=.0049;assert(not Care.item(player,cologne));cologne.amount=.005;assert(Care.item(player,cologne))
cologne.sealed=true;assert(not Care.item(player,cologne));cologne.sealed=false
cologne.place={};assert(not Care.queueItem(player,cologne));cologne.place=player.inv
local b=Care.snapshot(player,cologne)
assert(Care.queueItem(player,cologne,b) and #queue==1 and queue[1].item==cologne and queue[1].useDelta==.005)
assert(not Care.receipt(player,b,"item"))
cologne.place={};assert(not queue[1]:isValidStart() and not queue[1]:isValid());cologne.place=player.inv
if nativeLife then queue[1]:perform() else player.data.LSMoodles.SmellGood.Value=1 end
assert(player.data.hygieneNeed==75 and not Care.receipt(player,b,"item"),"client effect alone is not a debit")
if nativeLife then
    -- Exercise the installed helper's client-only path: no local debit, same-item
    -- request, actual upstream server receiver re-resolves the item by ID and syncs.
    queue[1]:complete()
    assert(receiver and pending and pending.module=="LS" and pending.command=="AdjustFluidItem"
        and pending.args[1]==cologne and pending.args[2]==.005 and not Care.receipt(player,b,"item"))
    client=false;receiver(pending.module,pending.command,pending.player,pending.args);client=true
    assert(calls.itemSync==1 and calls.itemStats==1,"server did not sync bottle debit")
else cologne.amount=0 end
assert(Care.receipt(player,b,"item") and not Care.item(player,perfume))
if nativeLife then
    AdjustHygieneNeed(player,player.data)
    assert(player.data.LSMoodles.HygieneBad.Value==0 and player.data.hygieneNeed>70,"perfume masks; it didn't wash")
end

queue={};setNeed(94,.8,0);visual.blood[0]=.7;visual.dirt[1]=.8
local sinkSquare=square(2,1,0,"house");local sink=source(sinkSquare)
perfume.place=player.inv
assert(Care.item(player,perfume), "A four-stage moodle can get useful partial relief")
assert(Care.inspect(player,sink), "A body wash is also a valid follow-up")
local partial=Care.snapshot(player,perfume)
player.data.LSMoodles.SmellGood.Value=1
assert(not Care.receipt(player,partial,"item"),"No partial-relief receipt without the actual dose")
perfume.amount=partial.amount-partial.dose
assert(Care.receipt(player,partial,"item") and not Care.item(player,perfume),"Partial relief counts once, not a second dose")
local e=assert(Care.inspect(player,sink));assert(Care.accessible(player,e))
assert(Care.validTarget(player,{care=e,square=sinkSquare,object=sink}));assert(not Care.validTarget(player,{care=e,square=home,object=sink}))
sink.amount=.99; assert(not Care.validTarget(player,e));sink.amount=1
sink.water=false;assert(not Care.inspect(player,sink));sink.water=true
sinkSquare.wall=true;assert(not Care.accessible(player,e));sinkSquare.wall=false
sinkSquare.building="other";assert(Care.validTarget(player,e) and not Care.accessible(player,e));sinkSquare.building="house"
sinkSquare.allow=false;assert(not Care.inspect(player,sink));sinkSquare.allow=true
home.allow=false;assert(not Care.accessible(player,e));home.allow=true
local old=sinkSquare.objects; sinkSquare.objects=list({});assert(not Care.validTarget(player,e));sinkSquare.objects=old
cells["2:1:0"]=square(2,1,0,"house");assert(not Care.inspect(player,sink));cells["2:1:0"]=sinkSquare
local spot=square(7,7,0,"other");local dist=source(spot);local remote=assert(Care.inspect(player,dist))
assert(not Care.accessible(player,remote) and not Care.queueWash(player,remote))
spot.allow=false;assert(not Care.validTarget(player,remote));spot.allow=true
local appliance=source(spot,"IsoClothingWasher");assert(not Care.inspect(player,appliance))
local locked=source(spot,"IsoThumpable");locked.locked=true;assert(not Care.inspect(player,locked))
dist.component=true;dist.emptyable=false;assert(not Care.inspect(player,dist));dist.emptyable=true;assert(Care.inspect(player,dist))
local dryer=source(spot,"IsoClothingDryer");assert(not Care.inspect(player,dryer));assert(Care.inspect(player,dist));dist.component=false;assert(not Care.inspect(player,dist))
local ground=source(home,"IsoWorldInventoryObject");ground.item=perfume
assert(Care.inspect(player,ground));ground.component=true;assert(not Care.inspect(player,ground));ground.component=false
home.loot=false;assert(not Care.inspect(player,ground));home.loot=true
perfume.sealed=true;assert(not Care.inspect(player,ground));perfume.sealed=false
assert(#queue==0,"inert scout or ineligible route queued an action")
player.seated=true;b=Care.snapshot(player)
assert(Care.queueWash(player,e) and #queue==2 and queue[1].Type=="ISWaitWhileGettingUp" and queue[2].Type=="ISWashYourself" and queue[2].sink==sink)
player.seated=false;sink.amount=0;assert(not queue[2]:isValidStart() and not queue[2]:isValid());sink.amount=1
assert(not Care.receipt(player,b,"wash"))
if nativeWash then
    queue[2]:perform();assert(not Care.receipt(player,b,"wash"),"client completion by itself proves nothing")
    queue[2]:complete()
    assert(sink.amount==0 and calls.visual==1 and sink.transmitted,"authoritative completion must consume available water and send the human visual")
else visual:setBlood(0,0);sink.amount=0 end
assert(Care.receipt(player,b,"wash") and player.data.hygieneNeed==94)
sink.amount=10;b=Care.snapshot(player)
assert(Care.queueWash(player,e));if nativeWash then queue[#queue]:complete() else visual:setDirt(1,0) end
assert(Care.receipt(player,b,"wash"))
assert(not Care.inspect(player,sink) and not Care.queueWash(player,e),"never wash clothing or start a no-op for clean body")
if nativeLife then
    AdjustHygieneNeed(player,player.data)
    assert(player.data.hygieneNeed<94 and player.data.hygieneNeed>90,"washed body improves Lifestyle need on later native minute")
end
visual.dirt[0]=.5
SandboxVars.Text.DividerHygiene=false
assert(Care.need(player)==0 and not Care.item(player,perfume) and not Care.inspect(player,sink))
SandboxVars.Text.DividerHygiene=true;player.data={}
assert(Care.need(player)==0 and not Care.item(player,perfume))
print("PASS: hygiene policy, candidate/receipt identity, native wash-only cost and fragrance mask gates; actual stock wash="..tostring(nativeWash)..", actual Lifestyle="..tostring(nativeLife))
