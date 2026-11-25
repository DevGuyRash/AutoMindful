-- Controller integration with explicit input, square, and native queue doubles.
AutoMindfulContractHarnessOnly = true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly = nil

local T, C = AutoMindfulTest, AutoMindfulTest.controller
local Q = ISTimedActionQueue
local function queue(p) return Q.getTimedActionQueue(p).queue end
local function head(p) return queue(p)[1] end
local function step(p, ms)
    T.now = T.now + (ms or 250)
    C.update(p)
end
local function steps(p, n) for _=1,n do step(p) end end
local function count(p, kind)
    local n = 0
    for _, name in ipairs(p.history) do if name==kind then n=n+1 end end
    return n
end
local function start(p, mode)
    local ok, reason=C.start(p,mode,false)
    assert(ok,reason)
end
local function active(p, mode)
    local s=C.status(p)
    assert(s.active and s.mode==mode and #p.cards==0 and #p.halos==0, s.message)
end
local function await(p, kind, mode)
    for _=1,32 do
        step(p)
        active(p,mode)
        local a=head(p)
        if a then
            if a.Type==kind then return a end
            assert(a.Type=="stand" and a.autoMindfulOwner and a:isStarted(),
                "Unexpected diversion before "..kind..": "..tostring(a.Type))
            a:perform()
        end
    end
    error("Expected "..kind.."; "..C.status(p).message)
end
local function move(p,x,y,z)
    local square=T.square(x,y,z)
    T.loadSquare(p,square)
    p.square=square
    return square
end
local function foreign(p,a)
    assert(head(p)==a and p.nativeHead==a.action and a:isStarted()
        and a.adds==1 and a.begins==1 and not a.removes,
        "This same native foreign head should run in order, with no requeue")
    assert(not a.autoMindfulOwner and not a.stopped and not a.forceStopped and not a.cancelled,
        "AutoMindful must neither own nor cancel foreign work")
end
local function walk(p,yes)
    p.moving,p.movementInput=yes,yes
    if yes then p.sitting=false end
end
local function beginMeditation()
    local p=T.playerNew()
    p.sitting=true
    start(p,"meditation")
    return p,await(p,"Meditation","meditation")
end

local cases=0
local function test(name,run)
    run()
    cases=cases+1
    print("PASS "..name)
end

test("ordinary several-tile walking pauses and then resumes the selected training at the new same-floor square",function()
    for _, case in ipairs({{"meditation","Meditation"},{"yoga","Yoga"},{"both","Meditation"}}) do
        local mode,kind=case[1],case[2]
        local p=T.playerNew()
        p.sitting=kind=="Meditation"
        start(p,mode)
        local old=await(p,kind,mode)
        local origin=p:getSquare()
        walk(p,true)
        step(p) -- begin the walk before the first displacement
        assert(old.stopped and not old.autoMindfulFinished and not head(p))
        local destination
        for x=1,5 do
            destination=move(p,x,1,origin:getZ())
            step(p); active(p,mode)
            assert(not head(p) and count(p,kind)==1, "Do not restart while walking")
        end
        walk(p,false)
        local resumed=await(p,kind,mode)
        assert(resumed~=old and resumed.action~=old.action and resumed:isStarted() and resumed.autoMindfulOwner)
        assert(p:getSquare()==destination and p:getZ()==origin:getZ() and count(p,kind)==2
            and count(p,"ISWalkToTimedAction")==0 and count(p,"ISPathFindAction")==0,
            "Resume at the adopted square, not by walking the survivor home")
        active(p,mode)
        C.stop(p)
    end
end)

test("persistent Recovery pauses care during walking and drinks once after stopping at the new square",function()
    local p=T.playerNew()
    p.meditation,p.xp,p.yoga=10,10000,{10,0,0}
    local bottle=T.add(p.inventory,T.water({thirst=-0.8}))
    start(p,"recovery"); steps(p,10)
    walk(p,true)
    p.values.THIRST,p.thirstMoodle=0.44,4
    local destination
    for i=1,7 do
        destination=move(p,2+i,4,0)
        step(p); active(p,"recovery")
        assert(not head(p) and bottle.fluid:getAmount()==1 and count(p,"drink")==0,
            "Even needed care must not seize the queue while genuine movement is held")
    end
    walk(p,false)
    local drink=await(p,"drink","recovery")
    assert(drink.autoMindfulOwner and drink:isStarted() and p:getSquare()==destination)
    drink:perform()
    p.thirstMoodle=0
    steps(p,16)
    active(p,"recovery")
    assert(p:getSquare()==destination and p.values.THIRST<0.44 and bottle.fluid:getAmount()<1
        and count(p,"drink")==1 and not head(p) and C.status(p).cycle==nil)
    assert(count(p,"Meditation")==0 and count(p,"Yoga")==0 and count(p,"ISWalkToTimedAction")==0)
    C.stop(p)
end)

test("unknown third-party native movement and its successor are untouched before training resumes",function()
    local p,old=beginMeditation()
    local receipts={}
    local job=T.action(p,"ThirdPartyCarryTimber",function() receipts[#receipts+1]="first" end)
    local follow=T.action(p,"ThirdPartyPutTimberAway",function() receipts[#receipts+1]="second" end)
    Q.add(job); Q.add(follow); step(p)
    assert(old.stopped and not old.autoMindfulFinished)
    foreign(p,job)
    assert(queue(p)[2]==follow and not follow.begins)
    local destination
    p.moving=true -- no actual input: native action owns the motion
    for i=1,6 do
        destination=move(p,0,i,0)
        step(p); active(p,"meditation")
        foreign(p,job)
        assert(queue(p)[2]==follow and count(p,"Meditation")==1 and #receipts==0)
    end
    p.moving=false
    job:perform(); step(p)
    foreign(p,follow)
    assert(receipts[1]=="first" and not receipts[2])
    follow:perform()
    local fresh=await(p,"Meditation","meditation")
    assert(fresh~=old and fresh:isStarted() and p:getSquare()==destination)
    assert(table.concat(receipts,",")=="first,second" and not job.stopped and not follow.stopped
        and count(p,"ISWalkToTimedAction")==0 and count(p,"Meditation")==2)
    C.stop(p)
end)

test("walking out of a planned care excursion cancels our old route and never walks back to its old anchor",function()
    local options=require "AutoMindful/Options"
    local nearby=require "AutoMindful/Nearby"
    local priorSearch,priorFind=options.searchNearby,nearby.find
    local priorSpeed,priorUtils,priorWalk=getGameSpeed,luautils,ISWalkToTimedAction
    local p=T.playerNew()
    p.values.BOREDOM=25
    local origin=p:getSquare()
    local shelf=T.container(6,0)
    local book=T.add(shelf,T.item("Literature"))
    local target={square=shelf.square,key="walking-fixture-bookshelf"}
    p.available={shelf}
    options.searchNearby=function() return true end
    nearby.find=function(player,kind,here)
        if player==p and kind=="literature" and here==origin then return target end
    end
    getGameSpeed=function() return 1 end
    ISWalkToTimedAction={new=function(_,player,square)
        return T.action(player,"ISWalkToTimedAction",function() player.square=square end)
    end}
    luautils={walkAdj=function(player,square,keep)
        assert(square==shelf.square and keep)
        Q.add(ISWalkToTimedAction:new(player,square))
        return true
    end}
    start(p,"meditation")
    local outbound=await(p,"ISWalkToTimedAction","meditation")
    assert(outbound.autoMindfulOwner and outbound:isStarted())
    walk(p,true); step(p)
    local destination=move(p,0,5,0)
    steps(p,4); active(p,"meditation")
    assert(outbound.stopped and not outbound.autoMindfulFinished and not head(p))
    walk(p,false)
    local fresh=await(p,"Meditation","meditation")
    assert(fresh:isStarted() and p:getSquare()==destination and shelf:contains(book)
        and count(p,"read")==0 and count(p,"ISWalkToTimedAction")==1,
        "Do not reteach a stale route, consume its supply or force return after a deliberate relocation")
    C.stop(p)
    options.searchNearby,nearby.find=priorSearch,priorFind
    getGameSpeed,luautils,ISWalkToTimedAction=priorSpeed,priorUtils,priorWalk
end)

test("active training still stops for combat or running; Recovery yields unless explicitly canceled",function()
    local controls={
        function(p) p.running,p.rawMovementInput=true,true end,
        function(p) p.sprinting,p.rawMovementInput=true,true end,
        function(p) p.aiming=true end,
        function(p) p.attacking=true end,
        function(p) p.cancelInput=true end,
    }
    for _,mode in ipairs({"meditation","recovery"}) do
        for input,control in ipairs(controls) do
            local p=T.playerNew()
            p.sitting=true
            start(p,mode); steps(p,10)
            active(p,mode)
            control(p); steps(p,4)
            local terminal=mode=="meditation" or input==#controls
            assert(C.status(p).active==not terminal and C.status(p).phase==(terminal and "stopped" or "manual")
                and not head(p))
            p.running,p.sprinting,p.rawMovementInput,p.aiming,p.attacking,p.cancelInput=false,false,false,false,false,false
            local queued=#p.history
            steps(p,12)
            assert(C.status(p).active==not terminal and #p.history==queued and not head(p))
        end
    end
end)

test("genuine combat still stops our mode without touching matched foreign work",function()
    local p=beginMeditation()
    local job=T.action(p,"ThirdPartyInPlaceWork")
    Q.add(job); step(p)
    foreign(p,job)
    p.attacking=true
    step(p)
    assert(not C.status(p).active and C.status(p).phase=="stopped")
    foreign(p,job)
    p.attacking=false
    job:perform()
    steps(p,12)
    assert(not C.status(p).active and not head(p))
end)

test("unexpected displacement is not an ordinary walk and cannot piggyback on a stale foreign Lua head",function()
    for _, stale in ipairs({false,true}) do
        local p=beginMeditation()
        local job
        if stale then
            job=T.action(p,"ThirdPartyMismatchedHead")
            Q.add(job); step(p)
            foreign(p,job)
            p.nativeHead={} -- the queued Lua object is not the current Java handle
        end
        local unknownNative=p.nativeHead
        move(p,4,2,0)
        step(p)
        assert(not C.status(p).active and C.status(p).phase=="stopped" and #p.cards==1)
        if job then
            assert(head(p)==job and p.nativeHead==unknownNative and job.begins==1
                and not job.autoMindfulOwner and not job.stopped and not job.cancelled)
        else assert(not head(p)) end
    end
end)

test("unproven displacement to a different floor does not silently relocate training",function()
    local p=beginMeditation()
    move(p,0,0,1)
    step(p)
    assert(not C.status(p).active and C.status(p).phase=="stopped" and not head(p))
end)

test("brief walk cancellations between updates never spend the unknown interruption budget",function()
    local p,previous=beginMeditation()
    for i=1,4 do
        walk(p,true)
        local destination=move(p,i*2,0,0)
        p:StopAllActionQueue() -- stock stop while walking; no controller tick yet
        walk(p,false)
        assert(previous.stopped and not previous.autoMindfulFinished)
        local fresh=await(p,"Meditation","meditation")
        assert(fresh~=previous and p:getSquare()==destination)
        previous=fresh
    end
    C.stop(p)
end)


test("crate egress uses a genuine adjacent indoor route, rechecks drinking, and never paths back onto the crate",function()
    local options,nearby=require "AutoMindful/Options",require "AutoMindful/Nearby"
    local priorSearch,priorFind,priorBehavior=options.searchNearby,nearby.find,BehaviorResult
    BehaviorResult={Failed="Failed"}
    local priorSpeed,priorUtils,priorWalk,priorPath,priorCell=getGameSpeed,luautils,ISWalkToTimedAction,ISPathFindAction,getCell
    local function setup()
        local p=T.playerNew()
        p.values.THIRST,p.thirstMoodle=.38,1
        local room={}
        local function tile(x,y,standable,inside)
            local s=T.square(x,y)
            function s:canStand() return standable end
            function s:getRoom() return inside and room end
            T.loadSquare(p,s)
            return s
        end
        -- Three boarded windows. Two crates and a lamp on the inside.
        -- Survivor starts ON the right/middle crate, with one legal exit.
        tile(-1,-1,true,false); local outside=tile(0,-1,true,false); tile(1,-1,true,false)
        tile(-1,0,false,true)
        local origin=tile(0,0,false,true)
        tile(1,0,false,true)
        local exit=tile(0,1,true,true)
        function origin:isWindowTo(other) return other==outside end
        p.square=origin
        local stock=T.container(1,2)
        T.add(stock,T.water())
        p.available={stock}
        options.searchNearby=function() return true end
        nearby.find=function(player,kind,_,_,rejected)
            if player==p and kind=="water" and player:getSquare()==origin and not rejected.stock then
                return {square=stock.square,container=stock,key="stock"}
            end
        end
        getCell=function()
            return {getGridSquare=function(_,x,y,z) return p.loadedSquares[x..":"..y..":"..z] end}
        end
        getGameSpeed=function() return 1 end
        ISPathFindAction={pathToNearest=function(_,player,goals)
            assert(#goals==3 and goals[1]==.5 and goals[2]==1.5 and goals[3]==0,
                "The only legal endpoint is clear floor inside the room")
            return T.action(player,"ISPathFindAction",function() player.square=exit end)
        end}
        ISWalkToTimedAction={new=function(_,player,square)
            assert(square~=origin,"Never try to enter the occupied crate again")
            return T.action(player,"ISWalkToTimedAction",function() player.square=square end)
        end}
        luautils={walkAdj=function(player,square,keep)
            assert(square==stock.square and keep)
            Q.add(ISWalkToTimedAction:new(player,exit))
            return true
        end}
        start(p,"meditation")
        step(p)
        assert(head(p) and head(p).Type=="ISPathFindAction" and p:getSquare()==origin,
            "The mod may queue but may not teleport off the crate")
        return p,origin,exit
    end

    local p,origin,exit=setup()
    head(p):perform()
    local drink
    for _=1,16 do
        step(p)
        local a=head(p)
        if a then if a.Type=="drink" then drink=a end; a:perform() end
        if drink and C.status(p).phase=="meditation" then break end
    end
    assert(drink and p:getSquare()==exit and p.values.THIRST<.38 and count(p,"ISPathFindAction")==1)

    p,origin,exit=setup()
    local route=head(p)
    route.result=BehaviorResult.Failed
    route:stop()
    step(p)
    assert(head(p) and head(p).Type=="ISWalkToTimedAction" and p:getSquare()==origin,
        "A failed egress leaves the supply route eligible rather than poisoning this source's identity")
    head(p):perform()
    for _=1,16 do step(p); if head(p) then head(p):perform() end end
    assert(p:getSquare()==exit and p.values.THIRST<.38 and count(p,"ISPathFindAction")==1)

    p,origin=setup()
    route=head(p)
    route.result=BehaviorResult.Failed
    route:stop()
    -- Available in hand by the time the game settles the failed route.
    T.add(p.inventory,T.water())
    step(p)
    assert(head(p) and head(p).Type=="drink" and p:getSquare()==origin,
        "A failed native step must not prevent genuinely in-place survival care")
    head(p):perform()
    step(p)
    assert(p.values.THIRST<.38 and count(p,"ISPathFindAction")==1)
    C.stop(p)

    p,origin=setup()
    p.cancelInput=true
    head(p):stop()
    p.cancelInput=false
    step(p)
    assert(not C.status(p).active and not head(p) and p:getSquare()==origin,
        "A deliberate cancel is never treated as native path failure")

    options.searchNearby,nearby.find,BehaviorResult=priorSearch,priorFind,priorBehavior
    getGameSpeed,luautils,ISWalkToTimedAction,ISPathFindAction,getCell=priorSpeed,priorUtils,priorWalk,priorPath,priorCell
end)

print("PASS "..cases.." walking handoff integration cases (explicit game-boundary doubles)")
