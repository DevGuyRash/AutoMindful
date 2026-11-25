-- Controller integration against UNMODIFIED external B42 queue/base Lua.
-- Player/JVM native stack, training action and foreign action bodies are doubles;
-- this proves callback/queue ordering, not real-game animation or UI behavior.
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
local T,C=AutoMindfulTest,AutoMindfulTest.controller
package.preload.ISBaseObject=function()
    ISBaseObject={}
    function ISBaseObject:derive(kind) local o={Type=kind}; setmetatable(o,{__index=self}); return o end
end
table.wipe=function(t) for k in pairs(t) do t[k]=nil end end
Events.OnTick={Add=function() end}
for _,name in ipairs({"ClimbThroughWindowState","ClimbOverFenceState","ClimbOverWallState","ClimbState","ClimbDownState","CloseWindowState","OpenWindowState","ForceOpenState"}) do
    _G[name]={instance=function() return {} end}
end
ISLogSystem={logAction=function() end}
DebugType={Action={warn=function() end}}
local function stock(path,short)
    if loadUpstream then loadUpstream(path)
    else
        local root=assert(arg[1],"Pass external stock media root or directory containing queue.lua/base.lua")
        local f=loadfile(root.."/lua/"..path) or loadfile(root.."/"..short)
        assert(f,"Missing external unmodified stock source")()
    end
end
stock("client/TimedActions/ISTimedActionQueue.lua","queue.lua")
stock("shared/TimedActions/ISBaseTimedAction.lua","base.lua")
LuaTimedActionNew={new=function(a)
    return {lua=a,isStarted=function() return true end,hasStalled=function() return false end,
        getJobDelta=function() return 0 end,
        forceStop=function() a:stop() end}
end}
function T.action(p,kind,effect)
    local a=ISBaseTimedAction:new(p); a.Type=kind; a.maxTime=1
    function a:start() self.starts=(self.starts or 0)+1 end
    function a:stop()
        self.stops=(self.stops or 0)+1
        if self.onStop then self:onStop() end
        ISBaseTimedAction.stop(self)
    end
    function a:perform() if effect then effect() end; ISBaseTimedAction.perform(self) end
    function a:forceCancel() self.cancels=(self.cancels or 0)+1 end
    return a
end
local function player()
    local p=T.playerNew(); p.sitting=true
    function p:StartAction(a)
        assert(not self.clearing,"Successor began inside Java StopAllActionQueue clear")
        assert(not self.nativeHead,"Starting successor stole a native handle")
        self.nativeHead=a; a.lua:start()
    end
    function p:StopAllActionQueue()
        self.clearing=true
        local old=self.nativeHead
        if old then old.lua:stop() end
        -- Java removes its native handles AFTER Lua stop/reset callbacks.
        self.nativeHead=nil; self.nativeAdditional=nil; self.clearing=false
    end
    function p:getCurrentState() return {} end
    function p:setIsFarming() end
    function p:setTimedActionToRetrigger(a) self.retrigger=a end
    function p:getTimedActionToRetrigger() return self.retrigger end
    function p:hasTimedActions() return self.nativeHead~=nil end
    return p
end
local function step(p,n) for i=1,n or 1 do T.tick(p,false) end end
local function begin(p)
    assert(C.start(p,"meditation",false)); step(p)
    local a=ISTimedActionQueue.getTimedActionQueue(p).queue[1]
    assert(a and a.Type=="Meditation" and a.starts==1 and p.nativeHead==a.action,"No begun owned meditation")
    return a
end
local function finish(p,a)
    assert(p.nativeHead==a.action and a.starts==1)
    p.nativeHead=nil -- Java lifecycle boundary double, not controller progress.
    a:perform()
end
local passed,failed=0,0
local function test(name,f)
    local ok,err=pcall(f)
    if ok then passed=passed+1; print("PASS "..name)
    else failed=failed+1; print("FAIL "..name..": "..tostring(err)) end
end
for _,during in ipairs({false,true}) do
    test("native attack stop retains foreign identities (callback append="..tostring(during)..")",function()
        local p=player(); local own=begin(p)
        local first,second=T.action(p,"ISFitnessAction"),T.action(p,"ISReadWorldMap")
        ISTimedActionQueue.add(first)
        if during then own.onStop=function() ISTimedActionQueue.add(second) end else ISTimedActionQueue.add(second) end
        p.contextOpen=true; p.attacking=true
        p:StopAllActionQueue() -- outside Controller.update, the attack is only seen in the stop callback
        p.attacking=nil; p.aimInput=false -- released before next controller poll
        step(p,3)
        assert(not C.status(p).active,"Actual combat interruption remained armed behind stale context menu")
        assert(#p.cards==1 and p.cards[1].title=="Meditation session stopped","Expected one terminal stopped card")
        local q=ISTimedActionQueue.getTimedActionQueue(p)
        assert(q.queue[1]==first and q.queue[2]==second and #q.queue==2,"Foreign waiter lost or reordered")
        assert(not first.cancels and not second.cancels and not first.stops and not second.stops,"Foreign action canceled")
        assert(first.starts==1 and not second.starts and p.nativeHead==first.action,"Foreign head not handed off once")
        assert(own.stops==1,"Owned stop invoked recursively")
        finish(p,first); assert(q.queue[1]==second and second.starts==1)
        finish(p,second); step(p,3)
        assert(#p.cards==1 and not C.status(p).active and #q.queue==0,"Stopped session rearmed or duplicate HUD")
        p.contextOpen=false
        begin(p); assert(#p.cards==1,"Explicit rearm emitted terminal card")
        C.stop(p,"test cleanup")
    end)
end
for _,immediateArm in ipairs({false,true}) do
    test("sole callback-appended waiter with immediate rearm="..tostring(immediateArm),function()
        local p=player(); local own=begin(p)
        local foreign=T.action(p,"ISReadWorldMap")
        local q=ISTimedActionQueue.getTimedActionQueue(p)
        local beforeTick=q.tick
        local resetCalls,clearCalls=0,0
        local stockReset,stockClear=q.resetQueue,q.clearQueue
        q.resetQueue=function(self) resetCalls=resetCalls+1; return stockReset(self) end
        q.clearQueue=function(self) clearCalls=clearCalls+1; return stockClear(self) end
        local reset,clear=q.resetQueue,q.clearQueue
        own.onStop=function() ISTimedActionQueue.add(foreign) end
        p.attacking=true; p:StopAllActionQueue(); p.attacking=nil
        assert(q.resetQueue==reset and q.clearQueue==clear,"Per-instance queue methods were not restored")
        assert(q.queue[1]==own and q.queue[2]==foreign and not foreign.starts,"Handoff happened inside native clear")
        if immediateArm then
            assert(C.start(p,"meditation",false),"Fresh explicit arm after native stop was blocked")
            assert(#p.cards==1 and C.status(p).active)
        else
            -- Exercise stock OnTick before the next controller update.
            q:tick(); assert(q.tick==beforeTick,"Deferred tick hook did not restore inherited tick")
            step(p)
            assert(not C.status(p).active and #p.cards==1)
        end
        assert(q.queue[1]==foreign and #q.queue==1 and foreign.starts==1 and not foreign.cancels)
        assert(own.stops==1 and p.nativeHead==foreign.action)
        finish(p,foreign); step(p,5)
        assert(#p.cards==1,"Stopped HUD repeated")
        if immediateArm then
            assert(C.status(p).active and p.nativeHead and p.nativeHead.lua.Type=="Meditation","New session failed to resume")
            C.stop(p,"test cleanup")
        else
            assert(not C.status(p).active and not p.nativeHead,"Old session rearmed itself")
        end
    end)
end
for _,entry in ipairs({"update","stop","error"}) do
    test("concrete stop callback reentry/failure: "..entry,function()
        local p=player(); local own=begin(p)
        local q=ISTimedActionQueue.getTimedActionQueue(p)
        local priorTick,priorReset,priorClear=q.tick,q.resetQueue,q.clearQueue
        local first,second=T.action(p,"ISFitnessAction"),T.action(p,"ISReadMapItem")
        ISTimedActionQueue.add(first)
        own.onStop=function()
            ISTimedActionQueue.add(second)
            if entry=="stop" then C.stop(p,"explicit reentrant stop") else C.update(p) end
            q:tick() -- even reentrant stock ticking cannot advance within stop
            assert(own.stops==1 and not first.starts and not second.starts,"Reentrant stop started/canceled native work")
            if entry=="error" then error("intentional concrete stop failure") end
        end
        p.attacking=true
        local ok,err=pcall(function() p:StopAllActionQueue() end)
        assert(ok==(entry~="error"),"Unexpected native callback success/failure")
        assert(q.resetQueue==priorReset and q.clearQueue==priorClear,"Failure/reentry leaked queue overrides")
        assert(own.stops==1 and not first.starts and not second.starts)
        if entry=="error" then
            assert(tostring(err):find("intentional concrete stop failure",1,true),"Concrete error was swallowed")
            -- The JVM boundary is not supplied here: retain its native handle
            -- after the throwing callback, prove no handoff, then model drain.
            C.update(p); q:tick()
            assert(p.nativeHead==own.action and not first.starts,"Error path stole a still-live native handle")
            p.nativeHead=nil; p.clearing=false
        end
        p.attacking=nil; step(p,3)
        assert(not C.status(p).active and #p.cards==1)
        assert(q.tick==priorTick and not q.autoMindfulHandoff,"Deferred wrapper leaked after drain")
        assert(q.queue[1]==first and q.queue[2]==second and #q.queue==2)
        assert(first.starts==1 and not second.starts and not first.cancels and not second.cancels)
        finish(p,first); finish(p,second); step(p,3)
        assert(#p.cards==1 and not C.status(p).active and not p.nativeHead)
    end)
end
test("ordinary workout/map queued takeover stays resumable and preserves successors",function()
    local p=player(); local own=begin(p)
    local workout,map=T.action(p,"ISFitnessAction"),T.action(p,"ISReadMapItem")
    ISTimedActionQueue.add(workout); ISTimedActionQueue.add(map)
    step(p,3)
    local q=ISTimedActionQueue.getTimedActionQueue(p)
    assert(C.status(p).active and #p.cards==0,"Ordinary foreign takeover became a terminal stop")
    assert(q.queue[1]==workout and q.queue[2]==map and #q.queue==2)
    assert(workout.starts==1 and not map.starts and not workout.cancels and not map.cancels)
    finish(p,workout); finish(p,map); step(p,5)
    assert(C.status(p).active and #p.cards==0 and p.nativeHead and p.nativeHead.lua.Type=="Meditation")
    C.stop(p,"test cleanup")
end)
-- In the running game a 150 ms right-click on the ground reports isAiming()
-- before its context menu opens, and ended the session.
test("a right-click that briefly reports aim is not combat; holding aim is",function()
    local p=player(); local own=begin(p)
    p.aiming=true; p:StopAllActionQueue(); p.aiming=false
    p.contextOpen=true; step(p,2); p.contextOpen=false
    assert(C.status(p).active and #p.cards==0 and own.stops==1)
    step(p,8)
    assert(C.status(p).active and p.nativeHead and p.nativeHead.lua.Type=="Meditation","It carries on by itself")
    p.aiming=true
    for _=1,8 do step(p) end
    assert(not C.status(p).active and #p.cards==1 and C.status(p).message:find("aiming",1,true))
    p.aiming=false
end)
-- Raw RMB/menu gesture is not evidence of actual combat. It remains resumable.
test("raw UI interruption holds then resumes without terminal toast",function()
    local p=player(); local own=begin(p)
    p.contextOpen=true; p.aimInput=true; p.aiming=false
    p:StopAllActionQueue(); p.aimInput=false
    step(p,4)
    assert(C.status(p).active and #p.cards==0 and not p.nativeHead,"Context interaction restarted training or stopped session")
    p.contextOpen=false; step(p,5)
    assert(C.status(p).active and #p.cards==0 and p.nativeHead and p.nativeHead.lua.Type=="Meditation","Raw gesture did not resume")
    C.stop(p,"test cleanup")
end)
-- Do not confuse a vanished training action with an explicit user Stop.
-- Exercise stock base:stop (which normally resets the entire queue) with both
-- pre-existing and callback-appended work and the intervening JVM clear.
for _,kind in ipairs({"Meditation","Yoga"}) do
    for _,mode in ipairs({kind:lower(),"both"}) do
        test("native unexplained stop hands both waiters over exactly once and resumes "..mode.."/"..kind,function()
            local p=player(); local isMeditation=kind=="Meditation"; p.sitting=isMeditation
            p.values.BOREDOM=isMeditation and 0 or 10
            assert(C.start(p,mode,true)); step(p)
            local q=ISTimedActionQueue.getTimedActionQueue(p); local own=q.queue[1]
            assert(own and own.Type==kind and own.starts==1)
            local first,second=T.action(p,"UnrecognizedPlayerAction"),T.action(p,"ISReadMapItem")
            ISTimedActionQueue.add(first); own.onStop=function() ISTimedActionQueue.add(second) end
            p:StopAllActionQueue(); assert(not first.starts and not second.starts)
            q:tick()
            assert(q.queue[1]==first and q.queue[2]==second and #q.queue==2 and first.starts==1)
            assert(not second.starts and not first.cancels and not second.cancels and own.stops==1)
            step(p); assert(C.status(p).active and #p.cards==0 and p.nativeHead==first.action)
            p.values.BOREDOM=isMeditation and 10 or 0
            finish(p,first); finish(p,second); step(p,5)
            assert(C.status(p).active and C.status(p).mode==mode and #p.cards==0)
            assert(q.queue[1]~=own and q.queue[1].Type==kind and q.queue[1].starts==1 and p.nativeHead==q.queue[1].action)
            C.stop(p,"test cleanup")
        end)
    end
end
for _,control in ipairs({"running","sprinting","cancelInput","attacking"}) do
    test("between-poll hard stop remains terminal after "..control.." clears",function()
        local p=player(); local old=begin(p)
        local other=T.action(p,"UnknownWorkout")
        old.onStop=function() ISTimedActionQueue.add(other) end
        p[control]=true
        p.rawMovementInput=control=="running" or control=="sprinting"
        p:StopAllActionQueue(); p[control]=nil; p.rawMovementInput=nil
        step(p,4)
        assert(not C.status(p).active and #p.cards==1 and p.nativeHead==other.action)
        assert(other.starts==1 and not other.stops and not other.cancels and old.stops==1)
        finish(p,other); step(p,7); assert(not C.status(p).active and #p.cards==1 and not p.nativeHead)
    end)
end
for _,control in ipairs({"running","sprinting"}) do
    test(control.." flag without raw movement cannot disarm an owned head or make a native loss terminal",function()
        local p=player(); local old=begin(p); local q=ISTimedActionQueue.getTimedActionQueue(p)
        local other=T.action(p,"UnrelatedAction")
        p[control]=true
        step(p); assert(q.queue[1]==old and not old.stops and C.status(p).active and #p.cards==0)
        ISTimedActionQueue.add(other)
        p:StopAllActionQueue(); p[control]=nil
        q:tick(); step(p)
        assert(C.status(p).active and #p.cards==0 and q.queue[1]==other and other.starts==1
            and not other.cancels and not other.stops and old.stops==1)
        finish(p,other); step(p,5)
        assert(C.status(p).active and q.queue[1]~=old and q.queue[1].Type=="Meditation" and #p.cards==0)
        C.stop(p,"test cleanup")
    end)
end
test("Escape on an inspection that opened between polls is a pause, not a player Stop",function()
    local p=player(); begin(p)
    local prev=ISWorldMap_instance
    ISWorldMap_instance={playerNum=p:getPlayerNum(),isVisible=function() return true end}
    p.cancelInput=true; p:StopAllActionQueue(); ISWorldMap_instance=prev
    step(p); p.cancelInput=false; step(p,5)
    assert(C.status(p).active and C.status(p).phase=="meditation" and #p.cards==0)
    C.stop(p,"test cleanup")
end)
test("a proven undrained canceled owned handle disarms without stealing a real queued action",function()
    local p=player(); local own=begin(p)
    local q=ISTimedActionQueue.getTimedActionQueue(p)
    local first=T.action(p,"UnrelatedWorkout"); ISTimedActionQueue.add(first)
    own:stop() -- simulated native stop enters Lua, but does not release its Java handle
    local handle=own.action
    assert(own.stops==1 and p.nativeHead==handle and not first.starts)
    T.now=T.now+4999; C.update(p)
    assert(C.status(p).active and not first.starts and not first.cancels)
    T.now=T.now+1; C.update(p)
    assert(not C.status(p).active and #p.cards==1 and q.queue[2]==first and p.nativeHead==handle and not first.starts and own.stops==1)
    p.nativeHead=nil; q:tick(); step(p,3)
    assert(q.queue[1]==first and #q.queue==1 and first.starts==1 and not first.cancels and not first.stops)
    finish(p,first); step(p,7)
    assert(not C.status(p).active and #p.cards==1 and not p.nativeHead)
end)
test("a genuinely unrelated native handle during a held handoff has no timeout and cannot be stolen",function()
    local p=player(); local own=begin(p); local q=ISTimedActionQueue.getTimedActionQueue(p)
    local first=T.action(p,"AnotherUnknownAction"); ISTimedActionQueue.add(first)
    own:stop(); local foreignHandle={}; p.nativeHead=foreignHandle
    for _=1,3 do T.now=T.now+60000; C.update(p); q:tick() end
    assert(C.status(p).active and #p.cards==0 and q.queue[2]==first and p.nativeHead==foreignHandle and not first.starts)
    p.nativeHead=nil; q:tick(); step(p)
    assert(p.nativeHead==first.action and first.starts==1 and not first.cancels and not first.stops)
    finish(p,first); step(p,6)
    assert(C.status(p).active and p.nativeHead.lua.Type=="Meditation" and #p.cards==0)
    C.stop(p,"test cleanup")
end)
for _,input in ipairs({"aim","run","cancel"}) do
    test("Recovery owns only its drink at a native stop boundary ("..input..")",function()
        local p=player()
        T.add(p.inventory,T.water({thirst=-0.8}))
        p.values.THIRST,p.thirstMoodle,p.values.ENDURANCE=.48,4,.6
        assert(C.start(p,"recovery",false)); step(p,4)
        local q=ISTimedActionQueue.getTimedActionQueue(p)
        local own=q.queue[1]
        assert(own and own.Type=="drink" and own.autoMindfulOwner)
        local first,second=T.action(p,"ISChopTreeAction"),T.action(p,"UnrelatedToolJob")
        ISTimedActionQueue.add(first); ISTimedActionQueue.add(second)
        if input=="aim" then p.aiming=true
        elseif input=="run" then p.running,p.rawMovementInput=true,true
        elseif input=="cancel" then p.cancelInput=true end
        own:stop() -- Java calls Lua before its handle has drained
        p.aiming,p.running,p.rawMovementInput,p.cancelInput=false,false,false,false
        assert(q.queue[1]==own and q.queue[2]==first and q.queue[3]==second
            and not first.starts and not second.starts,"A stock stop erased or started someone else's work")
        p.nativeHead=nil; q:tick(); step(p)
        assert(first.starts==1 and not second.starts and not first.autoMindfulOwner and not first.cancels)
        assert(C.status(p).active and #p.cards==0,"Only Stop ends Recovery; Escape steps back")
        finish(p,first); assert(q.queue[1]==second and second.starts==1 and not second.cancels)
        finish(p,second); step(p,5)
        assert(C.status(p).active and #p.cards==0 and q.queue[1]~=own and q.queue[1].Type=="drink")
        C.stop(p,"test cleanup")
    end)
end
test("Recovery waits out an unrelated Java-only action with no Lua queue entry",function()
    local p=player()
    local nativeOnly={}
    p.nativeHead=nativeOnly
    p.values.THIRST,p.thirstMoodle=.48,4
    T.add(p.inventory,T.water({thirst=-0.8}))
    assert(C.start(p,"recovery",false)); step(p,5)
    local q=ISTimedActionQueue.getTimedActionQueue(p)
    assert(C.status(p).active and p.nativeHead==nativeOnly and #q.queue==0)
    p.nativeHead=nil
    step(p)
    assert(#q.queue==0)
    step(p,3)
    assert(q.queue[1] and q.queue[1].Type=="drink")
    C.stop(p)
end)
print("stock aim/controller integration: "..passed.." passed (native/player boundaries doubled)")

assert(failed==0,tostring(failed).." stock aim integration regression(s)")
