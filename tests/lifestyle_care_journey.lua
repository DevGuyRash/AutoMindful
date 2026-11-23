-- Controller journeys use explicit Lifestyle action/receipt doubles. Separately
-- the adapters are exercised against installed stock/Lifestyle definitions.
local R,H={},{}
package.loaded["AutoMindful/RestroomCare"]=R
package.loaded["AutoMindful/HygieneCare"]=H
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
local T,C=AutoMindfulTest,AutoMindfulTest.controller
local options=require "AutoMindful/Options"
local scout=false
options.searchNearby=function()return scout end
options.searchRadius=function()return 6 end
function getGameSpeed()return 1 end
local genericInstanceof=instanceof
function instanceof(value,kind)
    if type(value)=="table" and value.isFixture and kind=="IsoObject" then return true end
    return genericInstanceof(value,kind)
end
BehaviorResult={Failed="Failed"}
ISWalkToTimedAction={new=function(_,p,square)
    local a=T.action(p,"ISWalkToTimedAction",function()p.square=square end)
    a.location=square
    function a:update() end
    return a
end}
luautils=luautils or {}
luautils.walkAdjObject=function(p,o,diagonal,keep)
    assert(diagonal and keep)
    ISTimedActionQueue.add(ISWalkToTimedAction:new(p,o.front))
    return true
end
function R.need(p)return p.urge or 0 end
function R.groundAllowed(p)return (p.urge or 0)>=.4 and not p.noPrivacy end
function H.need(p)return p.filth or 0 end
function H.item(p,item)return H.need(p)>0 and item.fragrance==true end
for kind, adapter in pairs({restroom=R,hygiene=H}) do
    adapter.inspect=function(p,o)
        if o.kind==kind and not o.unavailable then
            return {object=o,square=o.square,front=o.front}
        end
    end
    adapter.accessible=function(p,e)return e and not e.object.unavailable and p:getSquare()==e.front end
    adapter.snapshot=function(p,item)return {before=p.receipts or 0,item=item} end
    adapter.receipt=function(p,b,route)return p.receipts>b.before end
end
local function act(p,name,task)
    assert(not p:isSitting(),"Care must wait for standing")
    ISTimedActionQueue.add(T.action(p,name,function()
        p.careLog[#p.careLog+1]=name
        p.receipts=p.receipts+1
        task()
    end))
    return true
end
function R.queueToilet(p,e)
    assert(R.accessible(p,e) and e.object.exact)
    return act(p,"LSUseToilet",function()p.urge=0 end)
end
function R.queueGround(p)
    assert(R.groundAllowed(p))
    return act(p,"LSUseToiletGround",function()p.urge=0 end)
end
function H.queueItem(p,item,baseline)
    assert(item:getContainer()==p.inventory and item==baseline.item)
    return act(p,"LSApplyPerfumeAction",function()p.filth=0 end)
end
function H.queueWash(p,e)
    assert(H.accessible(p,e) and e.object.exact)
    return act(p,"ISWashYourself",function()p.filth=0 end)
end
local function tile(p,x,y)
    local s=T.square(x,y); s.objects={}
    function s:getObjects()return T.list(self.objects)end
    T.loadSquare(p,s);return s
end
local function survivor()
    local p=T.playerNew()
    p.square=tile(p,0,0);p.sitting=true;p.careLog={};p.receipts=0
    return p
end
local function fixture(p,kind,x,y,valid)
    local square,front=tile(p,x,y),tile(p,x-1,y)
    local ob={kind=kind,square=square,front=front,exact=valid,unavailable=not valid,isFixture=true}
    function ob:getSquare()return self.square end
    function ob:getMasterObject()return self end
    function ob:getObjectName()return "IsoObject" end
    function ob:getSprite()
        return {getName=function()return "fixture_"..kind end,getProperties=function()return nil end}
    end
    square.objects[#square.objects+1]=ob
    return ob
end
local function q(p)return ISTimedActionQueue.getTimedActionQueue(p).queue end
local function training(a)return a and (a.Type=="Meditation" or a.Type=="LSMeditateAction" or a.Type=="Yoga") end
local function untilRun(p,cond,n)
    for _=1,n or 40 do
        T.tick(p,false)
        if cond() then return end
        local a=q(p)[1]
        if a and not training(a) then
            if p.measureWalk and a.Type=="ISWalkToTimedAction" then
                a:update()
                T.now=T.now+p.measureWalk
                a:update()
            end
            a:perform()
        end
    end
    assert(cond(),C.status(p).phase..": "..tostring(C.status(p).message))
end

do
    scout=true
    local p=survivor()
    fixture(p,"restroom",4,0,true); p.urge=.4
    assert(C.start(p,"meditation",true))
    untilRun(p,function()return q(p)[1] and q(p)[1].Type=="LSUseToilet"end)
    local head=q(p)[1]; local progress=0
    function head.action:getJobDelta()return progress end
    T.tick(p,false); T.now=T.now+61000; C.update(p)
    assert(C.status(p).active and q(p)[1]==head,"A polling gap is not witnessed care time")
    for i=1,65 do progress=i/100; T.tick(p,false) end
    assert(C.status(p).active and q(p)[1]==head,"The native action is still doing work")
    for i=1,64 do T.tick(p,false) end
    assert(not C.status(p).active and head.stopped and #p.careLog==0 and p.receipts==0)
    print("PASS long pause and progressing restroom action versus 60s confirmed stall; no manufactured relief")
end
do
    scout=true
    local p=survivor();local home=p.square
    fixture(p,"restroom",2,0,false)
    local usable=fixture(p,"restroom",4,0,true)
    p.urge=.4
    assert(C.start(p,"meditation",true))
    untilRun(p,function()return q(p)[1] and q(p)[1].Type=="LSUseToilet"end)
    assert(p.square==usable.front,"use exact permitted toilet even when ground relief is unlocked")
    q(p)[1]:perform()
    untilRun(p,function()return training(q(p)[1])end)
    assert(p.square==home and #p.careLog==1 and p.careLog[1]=="LSUseToilet")
    C.stop(p)
end
do
    scout=true;local p=survivor();local home=p.square
    p.urge=.2
    assert(C.start(p,"meditation",true))
    untilRun(p,function()return training(q(p)[1])end)
    assert(#p.careLog==0,"do not use ground at the first urgency tier")
    p.urge=.4;p.noPrivacy=true
    for _=1,3 do T.tick(p,false) end
    assert(training(q(p)[1]),"private ground option must continue training until usable")
    p.noPrivacy=false
    untilRun(p,function()return q(p)[1] and q(p)[1].Type=="LSUseToiletGround"end)
    q(p)[1]:perform();untilRun(p,function()return training(q(p)[1])end)
    assert(p.square==home and #p.careLog==1 and p.careLog[1]=="LSUseToiletGround")
    C.stop(p)
end
do
    scout=true;local p=survivor();local home=p.square
    fixture(p,"hygiene",3,0,true)
    local perfume=T.add(p.inventory,T.item("InventoryItem",{fullType="Base.Perfume"}))
    perfume.fragrance=true;p.filth=1
    assert(C.start(p,"meditation",true))
    untilRun(p,function()return q(p)[1] and q(p)[1].Type=="LSApplyPerfumeAction"end)
    assert(p.square==home,"use the effective carried item before a wash trip")
    q(p)[1]:perform();untilRun(p,function()return training(q(p)[1])end)
    assert(#p.careLog==1 and p.careLog[1]=="LSApplyPerfumeAction")
    C.stop(p)
end
do
    scout=true;local p=survivor();local home=p.square
    local source=fixture(p,"hygiene",3,0,true)
    p.filth=4
    assert(C.start(p,"both",true))
    untilRun(p,function()return q(p)[1] and q(p)[1].Type=="ISWashYourself"end)
    assert(p.square==source.front)
    q(p)[1]:perform();untilRun(p,function()return training(q(p)[1])end)
    assert(p.square==home and #p.careLog==1 and p.careLog[1]=="ISWashYourself")
    C.stop(p)
end
do
    scout=false;local p=survivor();p.urge=.2;p.filth=3
    fixture(p,"hygiene",3,0,true)
    assert(C.start(p,"meditation",false))
    untilRun(p,function()return training(q(p)[1])end)
    assert(#p.careLog==0)
    C.stop(p)
end
do
    scout=true
    local p=survivor();local home=p.square
    local learned=fixture(p,"restroom",5,2,true)
    p.urge=.2
    assert(C.start(p,"meditation",true))
    untilRun(p,function()return q(p)[1] and q(p)[1].Type=="LSUseToilet"end)
    assert(p.square==learned.front)
    q(p)[1]:perform();untilRun(p,function()return training(q(p)[1])end)
    assert(p.square==home,"learn only from a successful round trip")
    C.stop(p)
    -- A closer usable fixture was added after training stopped. No wider scan
    -- is needed while the previously proven trip is still available.
    local fresh=fixture(p,"restroom",3,-1,true)
    p.urge=.2;p.sitting=true
    assert(C.start(p,"meditation",true))
    untilRun(p,function()return q(p)[1] and q(p)[1].Type=="LSUseToilet"end)
    assert(p.square==learned.front,"recall successful fixtures across Stop/Start")
    q(p)[1]:perform();untilRun(p,function()return training(q(p)[1])end)
    assert(p.square==home and #p.careLog==2)
    C.stop(p)
    local adjacent=fixture(p,"restroom",1,-1,true)
    adjacent.front=home
    p.urge=.2; p.sitting=true
    assert(C.start(p,"meditation",true))
    untilRun(p,function()return q(p)[1] and q(p)[1].Type=="LSUseToilet"end)
    assert(p.square==home,"a native-usable nearby fixture wins over memorized travel")
    q(p)[1]:perform();untilRun(p,function()return training(q(p)[1])end)
    C.stop(p)
    adjacent.unavailable=true
    learned.unavailable=true
    p.urge=.2;p.sitting=true
    assert(C.start(p,"meditation",true))
    untilRun(p,function()return q(p)[1] and q(p)[1].Type=="LSUseToilet"end)
    assert(p.square==fresh.front,"unusable remembered target yields to live scan")
    C.stop(p)
end
do
    scout=true
    local p=survivor(); local home=p.square
    fixture(p,"restroom",4,1,true)
    p.urge=.2
    local memory=require "AutoMindful/ScoutMemory"
    local remember=memory.remember
    local observed={}
    memory.remember=function(m,target,now,sample)
        observed[#observed+1]={target=target,sample=sample}
        return remember(m,target,now,sample)
    end
    p.measureWalk=900
    assert(C.start(p,"meditation",true))
    untilRun(p,function()return q(p)[1] and q(p)[1].Type=="LSUseToilet"end)
    T.now=T.now+23000 -- using the toilet/replication delay is not walking time
    q(p)[1]:perform(); untilRun(p,function()return training(q(p)[1])end)
    assert(p.square==home and #observed==1 and observed[1].sample and observed[1].sample.ms==1800)
    assert(observed[1].sample.x==0 and observed[1].sample.y==0 and observed[1].sample.z==0)
    C.stop(p)
    p.measureWalk=2800 -- frozen update gap; still remember venue, not elapsed route
    p.urge=.2; p.sitting=true
    assert(C.start(p,"meditation",true))
    untilRun(p,function()return q(p)[1] and q(p)[1].Type=="LSUseToilet"end)
    q(p)[1]:perform(); untilRun(p,function()return training(q(p)[1])end)
    assert(p.square==home and #observed==2 and not observed[2].sample)
    C.stop(p)
    memory.remember=remember
end
do
    scout=true
    local p=survivor();local home=p.square
    local nearby=require "AutoMindful/Nearby"
    local memory=require "AutoMindful/ScoutMemory"
    local originalFind,originalWalk,originalRemember=nearby.find,luautils.walkAdj,memory.remember
    local a,b=fixture(p,"first-shelf",4,0,true),fixture(p,"other-shelf",4,1,true)
    local function bind(o)
        local c=T.container(); c.square=o.square
        function c:getParent()return o end
        function c:getType()return "shelves" end
        function c:isExplored()return true end
        function o:getContainerCount()return 1 end
        function o:getContainerByIndex(i)if i==0 then return c end end
        return c
    end
    local ac,bc=bind(a),bind(b)
    local fallback,wide,learned,blockedRoute=ac,0,{},nil
    nearby.find=function(_,kind,origin)
        assert(origin==home,"No additional radius scan while away on a known path")
        if kind=="literature" then
            wide=wide+1
            return {square=fallback.square,container=fallback,key=kind..":"..fallback.square.x..":"..fallback.square.y..":0"}
        end
    end
    luautils.walkAdj=function(pl,square)
        if square==blockedRoute then return false end
        local o=square==a.square and a or b
        ISTimedActionQueue.add(ISWalkToTimedAction:new(pl,o.front))
        return true
    end
    memory.remember=function(m,target,now,sample)
        if target.kind=="literature" then learned[#learned+1]=target.container end
        return originalRemember(m,target,now,sample)
    end
    local function book(c,title)
        return T.add(c,T.item("Literature",{boredom=-60,data={literatureTitle=title}}))
    end
    local function begin()
        p.values.BOREDOM=45; p.sitting=true
        assert(C.start(p,"meditation",true))
    end
    local function readAt(o,title)
        untilRun(p,function()return q(p)[1] and q(p)[1].Type=="read"end)
        assert(p.square==o.front)
        q(p)[1]:perform()
        assert(p.read[title] and p.values.BOREDOM==0,"The exact shelf supplied the native action")
    end
    local function homeAndStop()
        untilRun(p,function()return training(q(p)[1])end)
        assert(p.square==home)
        C.stop(p)
    end
    p.available={ac}
    book(ac,"proved first")
    begin()
    readAt(a,"proved first")
    untilRun(p,function()return q(p)[1] and q(p)[1].location==home end)
    assert(#learned==0,"An away-from-home receipt must not publish a route yet")
    homeAndStop()
    assert(wide==1 and #learned==1 and learned[1]==ac)

    -- Both walls are reachable at A's front; the other shelf is enumerated
    -- first by native loot. Recall must re-select only A, not the first book.
    p.available={bc,ac};fallback,wide=bc,0
    book(bc,"alternate")
    book(ac,"proved second")
    begin()
    readAt(a,"proved second")
    homeAndStop()
    assert(wide==0 and #learned==2 and learned[2]==ac and not p.read.alternate)

    -- A stocked remembered source can become dry while the walk is in flight.
    local last=book(ac,"removed while walking")
    begin()
    untilRun(p,function()return q(p)[1] and q(p)[1].location==a.front end)
    assert(wide==0)
    T.remove(ac,last)
    q(p)[1]:perform()
    T.tick(p,false)
    assert(q(p)[1] and q(p)[1].location==home and not p.read.alternate and #learned==2,
        "Don't use an alternate adjacent shelf or learn a failed path")
    readAt(b,"alternate")
    homeAndStop()
    assert(wide==1 and #learned==3 and learned[3]==bc)

    -- A refusal before native walking also falls back once, without stopping
    -- the session, training twice, or polling a different floor.
    book(bc,"unreachable")
    book(ac,"fallback")
    blockedRoute,fallback,wide=b.square,ac,0
    begin()
    readAt(a,"fallback")
    homeAndStop()
    assert(wide==1 and #learned==4 and not p.read.unreachable)
    nearby.find,luautils.walkAdj,memory.remember=originalFind,originalWalk,originalRemember
    print("PASS exact bookshelf recollection avoids a radius scan, rejects late stock loss, and falls back once")
end
print("PASS Lifestyle care ordering, successful walking time, exact target, learned locations and training resumption")
