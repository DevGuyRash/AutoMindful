-- Behaviors reported from real sessions or reproduced in review. Each block is
-- the smallest situation that used to go wrong.
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
local T,C,Q=AutoMindfulTest,AutoMindfulTest.controller,ISTimedActionQueue
local N,R,O=require "AutoMindful/Nearby",require "AutoMindful/SurvivalRoute",require "AutoMindful/Options"
local Facts=require "AutoMindful/WellnessFacts"
local function queue(p) return Q.getTimedActionQueue(p).queue end
local function step(p,n) for _=1,n or 1 do T.now=T.now+250; C.update(p) end end
local function count(p,kind) local n=0; for _,k in ipairs(p.history) do if k==kind then n=n+1 end end; return n end
SandboxVars.Text={DividerMeditationNew=true}
BehaviorResult={Failed="Failed",Succeeded="Succeeded"}
function getGameSpeed() return 1 end
function getModInfoByID() return {getModVersion=function() return Facts.version end} end
CharacterStat.STRESS,CharacterStat.UNHAPPINESS,CharacterStat.NICOTINE_WITHDRAWAL="STRESS","UNHAPPINESS","NICOTINE_WITHDRAWAL"
CharacterTrait.SMOKER="smoker"
local scout,care=false,true
O.searchNearby=function() return scout end
O.practiceCare=function() return care end
local find=N.find
ISWalkToTimedAction={new=function(_,p) return T.action(p,"ISWalkToTimedAction") end}
luautils={walkAdj=function(p) Q.add(ISWalkToTimedAction:new(p)); return true end}
local function bare(p) function p:getPrimaryHandItem() end; function p:getSecondaryHandItem() end; return p end
local function passed(text) print("PASS "..text) end

-- 50 HP or less: returning a borrowed item was cancelled as "optional work",
-- queued again, and cancelled again, so the survivor never ate or drank.
do
    local p=T.playerNew(); p.sitting=true
    p.values.HUNGER,p.hungerMoodle,p.values.THIRST=.30,1,.5
    function p:getBodyDamage() return {getOverallBodyHealth=function() return 49 end,getNumPartsBleeding=function() return 0 end} end
    local shelf=T.container(1,0); p.nearby={shelf}
    local food=T.add(shelf,T.item("Food",{hunger=-.9,baseHunger=-.9}))
    assert(C.start(p,"meditation",true))
    local age=0
    for _=1,80 do
        step(p)
        local head=queue(p)[1]
        if head then age=age+1; if age>=3 then head:perform(); age=0 end end
    end
    assert(shelf:contains(food) and count(p,"ISInventoryTransferAction")==2 and C.status(p).active,"One pickup, one return")
    local bottle=T.add(p.inventory,T.water())
    for _=1,20 do step(p); if queue(p)[1] then queue(p)[1]:perform() end end
    assert(p.values.THIRST<.5 and bottle,"Care still runs at low health")
    C.stop(p)
end
passed("low health returns a loan once and keeps caring")

-- Being hungry as well used to suppress every search for water.
do
    scout,T.client=true,true
    SafeHouse={isSafehouseAllowInteract=function() return true end,isSafehouseAllowLoot=function() return true end}
    local box=T.container(5,0)
    N.find=function() return {square=box.square,key="unknown:5:0:0",unknown=true,container=box} end
    for _,tier in ipairs({0,.4}) do
        local p=bare(T.playerNew()); p.sitting=true; p.meditation=7; p.yoga={0,0,100}
        p.data.LSMoodles.MindfulState.Value=tier
        p.values.THIRST,p.thirstMoodle,p.values.HUNGER,p.hungerMoodle=.4,2,.2,1
        assert(C.start(p,"meditation",false)); step(p,40)
        assert(T.hasHistory(p,"ISWalkToTimedAction"),"Mindfulness cannot stand in for water")
        C.stop(p)
    end
    scout,T.client,SafeHouse=false,false,nil
    N.find=find
end
passed("hunger never suppresses the search for water")

-- The first thirst icon (12%) broke off Yoga and forfeited its XP.
for _,level in ipairs({0,1,2}) do
    local p=T.playerNew(); p.yoga={5,10,100}
    assert(C.start(p,"yoga",false)); step(p,6)
    T.add(p.inventory,T.water())
    local yoga=queue(p)[1]; assert(yoga.Type=="Yoga")
    p.values.THIRST,p.thirstMoodle=level==2 and .3 or .13,level
    step(p,5)
    assert((yoga.stopped==true)==(level>=2),"moodle "..level)
    C.stop(p)
end
-- And never to go and look inside something unknown.
do
    scout,T.client=true,true
    SafeHouse={isSafehouseAllowInteract=function() return true end,isSafehouseAllowLoot=function() return true end}
    local box=T.container(5,0)
    N.find=function() return {square=box.square,key="unknown:5:0:0",unknown=true,container=box} end
    local p=T.playerNew(); p.yoga={5,10,100}
    assert(C.start(p,"yoga",false)); step(p,6)
    local yoga=queue(p)[1]
    p.values.THIRST,p.thirstMoodle=.3,2
    step(p,20)
    assert(not yoga.stopped)
    C.stop(p); scout,T.client,SafeHouse=false,false,nil; N.find=find
end
passed("a practice is only broken off for a pressing need with a confirmed answer")

-- Sources that cannot be reached were retried every 15 seconds for hours.
for _,case in ipairs({{kind="literature",mode="meditation",fail="path"},{kind="water",mode="yoga",fail="reach"}}) do
    scout=true
    local box=T.container(5,0)
    local target={square=box.square,key=case.kind..":5:0:0",container=box,routeLayout="L",routeScope="S"}
    N.find=function(_,kind,_,_,rejected)
        if kind~=case.kind or R.blocked(rejected,target.key,target,"L",T.now) then return end
        return target
    end
    local p=T.playerNew(); p.sitting=case.mode=="meditation"; p.yoga={5,10,100}
    if case.kind=="literature" then p.values.BOREDOM=22 else p.values.THIRST,p.thirstMoodle=.13,1 end
    assert(C.start(p,case.mode,false))
    for _=1,480 do
        step(p)
        local head=queue(p)[1]
        if head and head.Type=="ISWalkToTimedAction" then
            if case.fail=="path" then head.result="Failed"; head:stop() else head:perform() end
        elseif head and head.Type=="stand" then head:perform() end
    end
    assert(count(p,"ISWalkToTimedAction")<=3,case.kind.." "..count(p,"ISWalkToTimedAction"))
    C.stop(p); scout=false; N.find=find
end
passed("an unreachable source is not retried on a timer")

-- Failures lengthen the wait even when the surroundings keep changing.
do
    local rejected,now,target={},1000,{key="k",square=T.square(5,0),routeScope="S"}
    local waits={}
    for attempt=1,4 do
        target.routeLayout="layout"..attempt
        R.reject(rejected,target,"water",now)
        local wait=0
        while R.blocked(rejected,"k",target,"changed",now+wait) do wait=wait+1000 end
        waits[attempt]=wait; now=now+wait
    end
    assert(waits[1]==15000 and waits[2]==60000 and waits[3]==240000 and waits[4]==900000,table.concat(waits,","))
end
passed("a door that opens and closes cannot restart the search from the top")

-- A locked house: every fixture behind one door earned its own walk there and
-- back (seen in the running game, four walks for one bathroom).
do
    local bathroom,rejected,now={},{},1000
    local function tile(room) return {getRoom=function() return room end} end
    local home=tile(nil)
    assert(not R.rejectRoom(rejected,{key="a",square=tile(bathroom),routeLayout="closed"},home,now))
    assert(not R.roomBlocked(rejected,tile(bathroom),home,"closed",now),"One fixture may just be boxed in")
    assert(R.rejectRoom(rejected,{key="b",square=tile(bathroom),routeLayout="closed"},home,now))
    assert(R.roomBlocked(rejected,tile(bathroom),home,"closed",now+3600000),"Its neighbors are ruled out while nothing changed")
    assert(not R.roomBlocked(rejected,tile({}),home,"closed",now) and not R.roomBlocked(rejected,tile(nil),home,"closed",now))
    assert(not R.roomBlocked(rejected,tile(bathroom),tile(bathroom),"closed",now),"Being inside is proof of a way in")
    assert(R.roomBlocked(rejected,tile(bathroom),home,"open",now+30000) and not R.roomBlocked(rejected,tile(bathroom),home,"open",now+61000))
    assert(not R.rejectRoom(rejected,{square=tile(nil)},home,now),"Open ground has no door")
end
do
    scout=true
    local near,far=T.container(4,0),T.container(8,0); T.add(far,T.water())
    local first={square=near.square,key="water:4",container=near,routeLayout="L",routeScope="S"}
    local second={square=far.square,key="water:8",container=far,routeLayout="L",routeScope="S"}
    N.find=function(_,kind,_,_,rejected)
        if kind~="water" then return end
        for _,target in ipairs({first,second}) do
            if not R.blocked(rejected,target.key,target,"L",T.now) then return target end
        end
    end
    local walks={}
    ISWalkToTimedAction={new=function(_,p,square)
        local a=T.action(p,"ISWalkToTimedAction",function() if square then p.square=square end end)
        walks[#walks+1]=square
        return a
    end}
    luautils={walkAdj=function(p,square) Q.add(ISWalkToTimedAction:new(p,square)); return true end}
    local p=T.playerNew(); p.sitting=true; p.values.THIRST,p.thirstMoodle=.3,1
    p.available={far}; p.nearby={}
    local home=p:getSquare()
    function getCell() return {getGridSquare=function(_,x,y,z) return x==home:getX() and y==home:getY() and home or T.square(x,y,z) end} end
    assert(C.start(p,"meditation",false))
    for _=1,60 do
        step(p)
        local head=queue(p)[1]
        if head and head.Type=="ISWalkToTimedAction" then
            if #walks==1 then p.square=T.square(2,0); p.x,p.y=2.5,.5; head.result="Failed"; head:stop()
            else p.x,p.y=nil,nil; head:perform() end
        elseif head and head.Type~="Meditation" then head:perform() end
        if #walks>=2 then break end
    end
    assert(walks[1]==near.square and walks[2]==far.square,"The next known source is tried from here, not from home")
    C.stop(p); scout=false; N.find=find
end
passed("one blocked room is one failure, and the next source is tried on the way")

-- A drink whose receipt was late was never offered again for the whole session.
do
    local p=T.playerNew(); p.sitting=true; p.values.THIRST,p.thirstMoodle=.3,1
    T.add(p.inventory,T.water())
    p.refuseCare=true
    assert(C.start(p,"meditation",false))
    for _=1,40 do step(p); local head=queue(p)[1]; if head and head.Type=="drink" then head:perform() end end
    assert(count(p,"drink")==1,"Not immediately")
    p.refuseCare=false
    for _=1,600 do
        step(p)
        local head=queue(p)[1]
        p.values.BOREDOM=0
        if head then head:perform() end
        if p.values.THIRST<.01 then break end
    end
    assert(p.values.THIRST<.01 and count(p,"drink")==2)
    C.stop(p)
end
passed("an unconfirmed drink is tried again later")

-- Recovery ended, half-alive, when the game refused to let it sit.
do
    local p=bare(T.playerNew()); p.values.STRESS=.4; p.meditation=2
    function p:reportEvent() end
    assert(C.start(p,"recovery",false))
    step(p,160)
    assert(C.status(p).active,"One awkward tile does not end Recovery")
    C.stop(p)
end
-- A zombie glimpsed through a window ended training that takes days.
for _,mode in ipairs({"meditation","yoga","recovery"}) do
    local p=T.playerNew(); p.sitting=mode~="yoga"
    assert(C.start(p,mode,false)); step(p,8)
    local before=count(p,"Meditation")+count(p,"Yoga")
    p.zombies=1; step(p); p.zombies=0; step(p,20)
    assert(C.status(p).active and (mode=="recovery" or C.status(p).phase=="recovery-paused"))
    for _=1,60 do step(p); local head=queue(p)[1]; if head and head.Type=="stand" then head:perform() end end
    if mode~="recovery" then assert(count(p,"Meditation")+count(p,"Yoga")>before,"It carries on by itself") end
    C.stop(p)
end
passed("danger and awkward posture pause instead of ending the job")

-- Taking over again and again used to be answered within a second each time.
do
    local p=T.playerNew(); p.sitting=true
    assert(C.start(p,"meditation",false)); step(p,8)
    local function takeOver() p.movementInput=true; step(p); p.movementInput=false end
    local function quiet()
        for n=1,60 do step(p); if queue(p)[1] then return n*250 end end
        return 15000
    end
    local first=(takeOver() or quiet())
    local last
    for _=1,4 do takeOver(); last=quiet() end
    assert(first<3000 and last>=7000,first.." "..last)
    C.stop(p)
end
passed("repeated takeovers are given more room each time")

-- Changing jobs needed a separate Stop.
do
    local p=T.playerNew(); p.sitting=true
    assert(C.start(p,"meditation",false)); step(p,6)
    local old=queue(p)[1]
    assert(C.launch(p,"recovery",false))
    step(p,4)
    assert(old.stopped and C.status(p).active and C.status(p).mode=="recovery" and #p.cards==0,"No stopped card for a switch")
    p.movementInput=true
    assert(C.launch(p,"meditation",false)); step(p,50); p.movementInput=false
    assert(C.status(p).active and C.status(p).mode=="meditation","Walking while you switch pauses the new job, it does not lose both")
    assert(C.launch(p,"recovery",false)); step(p,8)
    local ok,reason=C.launch(p,"recovery",false)
    assert(not ok and reason)
    ZenWellnessContextMenu.Options.Saved,ZenWellnessContextMenu.Options.Yoga=ZenWellnessContextMenu.Options.Yoga,nil
    ok=C.launch(p,"yoga",false)
    ZenWellnessContextMenu.Options.Yoga,ZenWellnessContextMenu.Options.Saved=ZenWellnessContextMenu.Options.Saved,nil
    assert(not ok and C.status(p).mode=="recovery" and C.status(p).active,"A refused switch keeps the running job")
    C.stop(p)
end
passed("jobs can be switched directly")
print("REGRESSIONS PASS")
