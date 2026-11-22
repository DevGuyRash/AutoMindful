-- Portable tests use explicit Lifestyle option/action doubles. Pass Lifestyle's
-- common/media directory to execute its installed builders, callbacks, constructors,
-- updates and performs instead (world objects, transport and PZ queue are doubled).
package.path="mods/AutoMindful/common/media/lua/client/?.lua;"..package.path
local refs=(arg and arg[1]) or loadUpstream
local function stock(path)
    if loadUpstream then return loadUpstream(path) end
    return assert(loadfile(refs.."/lua/"..path))()
end
local p, client, reads, updates, disturb, zombies, area, owner
local function noop() end
local function no() return false end
local function zero() return 0 end
local function yes() return true end
local function list(t)
    return {size=function()return #t end,get=function(_,i)return t[i+1] end,
        add=function(_,v)t[#t+1]=v end,contains=function(_,v)for _,x in ipairs(t) do if x==v then return true end end return false end}
end
function getText(key) return key end
function getTexture() return "tex" end
function getSpecificPlayer(i) return i==0 and p end
function instanceof(o,k) return o and o.kind==k or false end
function isClient() return client end
function isServer() return false end
function ZombRand(a,b) return b and a or 0 end
function getGameTime() return {getGameWorldSecondsSinceLastUpdate=function()return 18 end} end
GTLSCheck=1
Events={OnGameStart={Add=noop}}
ArrayList={new=function()return list({}) end}
CharacterTrait={SLOPPY="sloppy",CLEANFREAK="neat",TIDY="tidy",CLUMSY="clumsy",OUTDOORSMAN="outdoors"}
SandboxVars={Text={DividerHygiene=true},LSHygiene={NotEmbarrassed=false,HygieneNeedMultiplier=1}}
IsoDirections={S="S"}
SafeHouse={isSafehouseAllowInteract=function(s)return not s.forbid end,isSafehouseAllowLoot=function(s)return not s.noLoot end}
AdjacentFreeTileFinder={privTrySquare=function(s,f)return f and f:canStand() and not s.wall end}
local function sq(x,y,z)
    local s={x=x,y=y,z=z or 0,movers={},getX=function(self)return self.x end,getY=function(self)return self.y end,
        getZ=function(self)return self.z end,haveFire=function(self)return self.fire==true end,
        canStand=function(self)return not self.blocked end,getAdjacentSquare=function(self,f)return f=="S" and self.front end,
        getMovingObjects=function(self)return list(self.movers) end,canReachTo=function(self,x)return not self.wall and not x.wall end}
    return s
end
local spriteName={Fancy="fixtures_bathroom_01_0",Low="fixtures_bathroom_01_4",Hanging="fixtures_bathroom_01_8",Wooden="fixtures_bathroom_02_25",Chemical="fixtures_bathroom_02_4"}
local function fixture(group)
    local s=sq(0,1); s.front=sq(0,2)
    local o={square=s,kind="IsoObject",water=20,props={GroupName=group,CustomName="Toilet",Facing="S"},sn=spriteName[group],
        isLockedToCharacter=function(self)return self.locked end,hasWater=function(self)return self.water>0 end,
        getFluidAmount=function(self)return self.water end,getSquare=function(self)return self.square end,
        getX=function(self)return self.square.x end,getY=function(self)return self.square.y end,getZ=zero,
        hasModData=function(self)return self.data ~= nil end,getModData=function(self)
            reads=reads+1;self.data=self.data or {};return self.data end}
    function o:getSprite()return {getName=function()return self.sn end,getProperties=function()return {get=function(_,k)return self.props[k] end} end} end
    return o
end
local function container(items)
    local c={items=items or {},getItems=function(self)return list(self.items)end,getOutermostContainer=function(self)return self end,
        contains=function(self,i)return list(self.items):contains(i)end,getParent=function(self)return self.obj end,
        getSourceGrid=function(self)return self.source end,isInCharacterInventory=function(self)return self==p.inv end}
    return c
end
local function player()
    local q={queue={}}
    local h=sq(0,0)
    return {kind="IsoPlayer",md={LSMoodles={BladderNeed={Value=0.2}},bathroomNeed=30,hygieneNeed=10},square=h,q=q,inv=container(),loot=container(),
        hasModData=yes,getModData=function(self)return self.md end,getPlayerNum=zero,isFemale=function(self)return self.female end,
        getSq=noop,getSquare=function(self)return self.square end,hasTimedActions=function(self)return self.java or false end,
        getCharacterActions=function(self)return {isEmpty=function()return not self.java end}end,
        isSitOnGround=function(self)return self.sit end,isSittingOnFurniture=function(self)return self.sitting end,
        isDead=no,isAsleep=no,getVehicle=no,isOnFire=no,isRunning=no,isSprinting=no,isAiming=no,isAttacking=no,isSneaking=no,
        getStats=function()return {getNumVisibleZombies=zero,getNumChasingZombies=zero,getNumVeryCloseZombies=zero}end,
        hasTrait=function(self,t)return self.sloppy and t==CharacterTrait.SLOPPY or false end,
        isOutside=yes,isTimedActionInstant=no,getInventory=function(self)return self.inv end,
        setBlockMovement=noop,setSneaking=noop,nullifyAiming=noop,pressedMovement=no,
        getHumanVisual=function()return {} end,
        faceThisObject=noop,getEmitter=function()return {playSound=noop} end}
end
ISTimedActionQueue={getTimedActionQueue=function(p)return p.q end,isPlayerDoingAction=function(p)return p.java==true end,
    add=function(a)p.q.queue[#p.q.queue+1]=a end}
function getPlayerInventory() return {inventoryPane={inventoryPage={backpacks={{inventory=p.inv}}}},refreshBackpacks=noop} end
function getPlayerLoot() return {inventoryPane={inventoryPage={backpacks={{inventory=p.loot}}}}} end
LSMovObjs={getMovingObjects=function(_,kind,n) assert(kind=="IsoZombie" and n==8);return zombies and {1} or {} end}
LSUtil={debugPrint=noop,isObjOnSqr=function(o)return not o.removed end,
    objHasWater=function(o,n)return o:hasWater() and o:getFluidAmount()>=n end,
    isValidObj=function(o,n)return o~=nil and o.sn==n end,getValidPlayer=getSpecificPlayer,
    isCharBusy=function(p)return p:hasTimedActions() end,isCharSitting=function(p)return p.sit or p.sitting end,
    canSeeOtherPlayers=function(_,range)return disturb==range and {1} or false end,getObjTexAndText=function(name)return 1,"Object:"..name end,
    hasAdminRights=function()return owner end,
    getDummyOption=function(m,n,_,__,add,dis) local o=m[add](m,n);o.notAvailable=dis;return o end,
    walkToFront=function(p,o) assert(o.square.front==p.square); ISTimedActionQueue.add({Type="ISWalkToTimedAction",character=p});return true end,
    getSimpleTooltip=function()return {} end,getValidCharacter=function(p)return p end,
    changeCharacterMoodGroup=noop,useItem=noop}
LSHygiene={DS={Toilets={}},TF={getWaterUsage=function(g)return ({Fancy=5,Low=10,Hanging=5})[g] end,isInOuthouseArea=function()return area end}}
for _,sn in pairs(spriteName)do LSHygiene.DS.Toilets[sn]={"d1","d2","d3"} end
LSSync={transmitObjMovData=function()updates=updates+1 end,updateClientData=noop,transmit=noop}
LSCleaning={getCleaningTime=function()return 1 end}
ActionHelper={}
local function seatedAction(p,o,a)
    local path={Type="ISPathFindAction",character=p,goal={"SitOnFurniture",o,true},onCompleteArgs={p,nil,a}}
    ISTimedActionQueue.add(path)
end
ActionHelper.onRest=function(o,p,a)seatedAction(p,o,a)end
ISPathFindAction={pathToSitOnFurniture=function(_,p,o)
    return {Type="ISPathFindAction",character=p,goal={"SitOnFurniture",o,true},setOnComplete=function(self,f,...)self.onCompleteArgs={...}end,setOnFail=noop}
end}
ISBaseTimedAction={perform=noop,stop=noop}
function ISBaseTimedAction:derive(kind)local c={Type=kind}; c.__index=c;return setmetatable(c,{__index=self})end
ISBaseTimedAction.setActionAnim=noop; ISBaseTimedAction.setOverrideHandModels=noop
function ISBaseTimedAction:forceComplete()self.done=true end
BloodBodyPartType={MAX={index=zero}}
HaloTextHelper={addTextWithArrow=noop}
function getSearchMode()return {getSearchModeForPlayer=function()
    local v={setTargets=noop};local one=function()return v end
    return {getBlur=one,getDesat=one,getRadius=one,getDarkness=one,getGradientWidth=one}end,setEnabled=noop}end
TransferHelper={transferItem=function(_,i)return i end}
local function fakeAction(p,o,name)
    return {Type=name,character=p,toiletObject=o,start=function(self)p.md.IsDoingToilet=true end,
        update=function(self)p.md.bathroomNeed=p.md.bathroomNeed-2.5;self.done=p.md.bathroomNeed<=0 end,
        perform=function(self)p.md.IsDoingToilet=false end}
end
local function selectedWipe()
    return p.loot.items[1] or p.inv.items[1]
end
if refs then
    for _,name in ipairs({"ISUI/ISWorldObjectContextMenu","TimedActions/ISBaseTimedAction","Properties/Player/CleaningSkill"})do package.loaded[name]=true end
    package.loaded["LSBodyPartList"]={}
    stock("shared/Hygiene/DirtySprites.lua")
    stock("shared/Hygiene/ToiletFunctions.lua")
    stock("shared/Helper/ActionHelper.lua")
    stock("shared/TimedActions/LSFlushToilet.lua")
    package.loaded["TimedActions/LSUseToilet"]=stock("shared/TimedActions/LSUseToilet.lua")
    package.loaded["TimedActions/LSUseToiletGround"]=stock("shared/TimedActions/LSUseToiletGround.lua")
    package.loaded["Properties/TPTypes"]=stock("client/Properties/TPTypes.lua")
    stock("client/Hygiene/ToiletContextMenu.lua")
    stock("client/Hygiene/ToiletGroundContextMenu.lua")
    -- Simulate the late native post-use flush transport separately; receipt waits for it.
    LSHygiene.TF.doFlush=noop
else
    ToiletContextMenu={onAction=function(p,o,g,s,_,items,cmd)
        LSUtil.walkToFront(p,o)
        if cmd=="IsFlushAndUse"then ISTimedActionQueue.add({Type="LSFlushToilet",character=p,toiletObject=o})end
        local a=fakeAction(p,o,"LSUseToilet");a.toiletpaperItem=items[4]
        if g=="Hanging"then ISTimedActionQueue.add(a)else seatedAction(p,o,a)end
    end}
    ToiletContextMenu.doBuildMenu=function(_,m,world,o,s,_,g)
        assert(world[1]==o); local sub=m:getSubMenu(m.options[1].subOption)
        local d=o:getModData();d.movableData=d.movableData or {dirtyLevel=0,condition=0}
        sub:addOptionOnTop(getText("ContextMenu_Toilet_Use"),p,ToiletContextMenu.onAction,o,g,s,"good",{[4]=selectedWipe()},d.movableData.needFlush and not p.sloppy and "IsFlushAndUse" or "IsUse")
    end
    ToiletGroundContextMenu={doBuildMenu=function(_,m,w)
        local a=fakeAction(p,nil,"LSUseToiletGround");a.toiletpaperItem=selectedWipe()
        m:addOptionOnTop(getText("ContextMenu_Toilet_Ground"),w,function()ISTimedActionQueue.add(a)end,p,a.toiletpaperItem,"good")
    end}
end
local R=require "AutoMindful/RestroomCare"
local function reset()
    p=player();client=false;reads=0;updates=0;zombies=nil;disturb=nil;area=nil;owner=nil;SandboxVars.Text.DividerHygiene=true
    SandboxVars.LSHygiene.NotEmbarrassed=false
end
local function tier(v,raw)p.md.LSMoodles.BladderNeed.Value=v;p.md.bathroomNeed=raw end
local function arrive(o)p.square=o.square.front; return {object=o,square=o.square,care=assert(R.inspect(p,o))}end
local function waterkind(g,w)local o=fixture(g);o.water=w;return R.inspect(p,o)end
local function closeQueue()p.q.queue={};p.java=false end
local passed=0
local function test(s,f)reset(); f(); passed=passed+1;print("PASS "..s)end

test("no Lifestyle / disabled / uninitialized / raw already emptied all no-op",function()
    local old=ToiletContextMenu;ToiletContextMenu=nil
    assert(R.need(p)==0 and not R.groundAllowed(p) and not R.inspect(p,fixture("Fancy")));ToiletContextMenu=old
    SandboxVars.Text.DividerHygiene=false;assert(R.need(p)==0 and not R.snapshot(p));SandboxVars.Text.DividerHygiene=true
    p.md.hygieneNeed=nil;assert(R.need(p)==0);p.md.hygieneNeed=30
    tier(0.4,0);assert(R.need(p)==0 and not R.groundAllowed(p));p.md.LSMoodles={};assert(R.need(p)==0)
end)
test("actual fixture/ground menu thresholds; safety, seats, vehicles and privacy",function()
    tier(0,29);assert(R.need(p)==0);tier(0.2,30);assert(R.need(p)==0.2 and not R.groundAllowed(p) and not R.queueGround(p))
    tier(0.4,60);assert(R.groundAllowed(p));p.sit=true;assert(R.groundAllowed(p) and not R.queueGround(p));p.sit=false
    disturb=4;assert(not R.groundAllowed(p));SandboxVars.LSHygiene.NotEmbarrassed=true;assert(R.groundAllowed(p));zombies=true;assert(not R.groundAllowed(p))
    zombies=nil;p.square.fire=true;assert(not R.groundAllowed(p));p.square.fire=nil
    client=true;p.square.forbid=true;assert(not R.groundAllowed(p));p.square.forbid=nil
    p.java=true;assert(not R.queueGround(p)); p.java=false;p.q.queue={{Type="somebodyElse"}};assert(not R.queueGround(p));assert(#p.q.queue==1)
end)
test("remote inert exact physical probe: groups, water, uses, clogs incl zero, seats, locks, ignored decoration",function()
    local o=fixture("Fancy"); assert(R.inspect(p,o) and reads==0 and updates==0 and not o.data)
    assert(not R.accessible(p,R.inspect(p,o)));assert(not waterkind("Fancy",4) and waterkind("Fancy",5));assert(not waterkind("Low",9) and waterkind("Low",10))
    assert(not waterkind("Hanging",4) and waterkind("Hanging",5));p.female=true;assert(not waterkind("Hanging",5));p.female=false
    assert(waterkind("Wooden",0) and waterkind("Chemical",0))
    o=fixture("Wooden");o.data={movableData={uses=0}};assert(not R.inspect(p,o));o.data.movableData.uses=100
    area=true;LSHygiene.TF.outhouseAreas={{0,1}};assert(not R.inspect(p,o));o.data.movableData.uses=99;assert(R.inspect(p,o))
    area=nil;LSHygiene.TF.outhouseAreas={}
    o=fixture("Chemical");o.data={movableData={uses=0}};assert(not R.inspect(p,o))
    o=fixture("Fancy");o.data={movableData={isClogged=0}};assert(not R.inspect(p,o));o.data=nil
    o.square.wall=true;assert(not R.inspect(p,o));o.square.wall=nil;o.square.front.blocked=true;assert(not R.inspect(p,o));o.square.front.blocked=nil
    o.kind="IsoThumpable";o.locked=true;assert(not R.inspect(p,o));o.locked=nil
    local visitor={kind="IsoPlayer",getSitOnFurnitureObject=function()return o end};o.square.movers={visitor};assert(not R.inspect(p,o));o.square.movers={}
    local e=arrive(o);assert(R.accessible(p,e));disturb=8;assert(not R.accessible(p,e));disturb=nil
    client=true;o.square.forbid=true;assert(not R.inspect(p,o));o.square.forbid=nil;o.square.front.forbid=true;assert(not R.inspect(p,o));o.square.front.forbid=nil
    o.removed=true;assert(not R.accessible(p,e));o.removed=nil
    e.object=fixture("Fancy");assert(not R.accessible(p,e) and not R.queueToilet(p,e));e.object=o
    o.sn="mod_decorative_fake";assert(not R.inspect(p,o));o.sn=spriteName.Fancy;o.props.CustomName="Sink";assert(not R.inspect(p,o))
end)
test("stock exact dispatch, native preflush for non-sloppy, no duplicates, debug path harmless",function()
    owner=true;local o=fixture("Fancy");local e=arrive(o);o.data={movableData={needFlush=true,dirtyLevel=0,condition=0}}
    local b=R.snapshot(p);assert(R.queueToilet(p,e));assert(not R.queueToilet(p,e))
    assert(p.q.queue[1].Type=="ISWalkToTimedAction" and p.q.queue[2].Type=="LSFlushToilet"
        and p.q.queue[3].goal[2]==o and b.action==p.q.queue[3].onCompleteArgs[3] and b.action.toiletObject==o)
    assert(p.md.bathroomNeed==30 and not R.receipt(p,b));closeQueue();p.sloppy=true;b=R.snapshot(p);assert(R.queueToilet(p,e))
    assert(#p.q.queue==2 and p.q.queue[2].goal[2]==o and b.action.toiletObject==o)
end)
test("optional TP follows native, stale/unauthorized loot never taken",function()
    local o=fixture("Hanging");local e=arrive(o);local b=R.snapshot(p);assert(R.queueToilet(p,e));assert(not b.action.toiletpaperItem)
    closeQueue();local i={getFullType=function()return "Base.ToiletPaper" end,getContainer=function()return p.loot end,getWorldItem=no}
    p.loot.items={i};p.loot.source=p.square;client=true;p.loot.source.noLoot=true
    assert(not R.queueToilet(p,e) and #p.q.queue==0);p.loot.source.noLoot=false
    p.loot.obj={kind="IsoThumpable",isLockedToCharacter=yes,getSquare=function()return p.square end}
    tier(0.4,60);assert(not R.queueGround(p));p.loot.obj=nil;p.loot.source=sq(3,1);assert(not R.queueGround(p));p.loot.source=p.square
    b=R.snapshot(p);assert(R.queueGround(p));assert(b.action.toiletpaperItem==i)
end)
local function run(kind, late)
    -- Do not invent a drain in the effects double when installed stock is supplied:
    -- execute every update until the stock action actually forceCompletes.
    local b=R.snapshot(p);local o
    if kind=="fixture"then o=fixture("Fancy");assert(R.queueToilet(p,arrive(o))) else assert(R.queueGround(p)) end
    local a=assert(b.action);p.q.queue={a};p.java=true;a:start()
    if late=="accident"then p.md.bathroomNeed=0 end
    for n=1,150 do if a.done then break end;a:update() end
    assert(a.done and not R.receipt(p,b))
    if late=="cancel" then p.md.IsDoingToilet=false
    elseif late=="disturbed"then a.wasDisturbedBy=true;p.md.IsDoingToilet=false
    else a:perform() end
    p.q.queue={{Type="stock-postflush"}};assert(not R.receipt(p,b));closeQueue()
    -- Once-per-minute regrowth during/after the stock flush is not a second trip.
    p.md.bathroomNeed=0.1
    return R.receipt(p,b)
end
test("native seated and ground complete, receipt survives postflush regrowth",function()
    tier(0.2,30.1);assert(run("fixture"));tier(0.4,60.3);assert(run("ground"))
end)
test("no false receipt on cancellation, disturbance, accident or never-started path",function()
    tier(0.2,30);assert(not run("fixture","cancel"));tier(0.4,60);assert(not run("ground","disturbed"))
    tier(0.2,30);assert(not run("fixture","accident"))
    tier(0.2,30);local b=R.snapshot(p);assert(R.queueToilet(p,arrive(fixture("Fancy"))));closeQueue();p.md.bathroomNeed=0;assert(not R.receipt(p,b))
end)
print("restroom care: "..passed.." passed; "..(refs and "installed Lifestyle; explicit Java/MP/queue doubles" or "portable doubles"))
