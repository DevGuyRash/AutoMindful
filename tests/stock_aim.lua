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
    test("native actual-aim stop retains foreign identities (callback append="..tostring(during)..")",function()
        local p=player(); local own=begin(p)
        local first,second=T.action(p,"ISFitnessAction"),T.action(p,"ISReadWorldMap")
        ISTimedActionQueue.add(first)
        if during then own.onStop=function() ISTimedActionQueue.add(second) end else ISTimedActionQueue.add(second) end
        p.contextOpen=true; p.aiming=true
        p:StopAllActionQueue() -- outside Controller.update, actual aim only seen in stop callback
        p.aiming=false; p.aimInput=false -- released before next controller poll
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
        p.aiming=true; p:StopAllActionQueue(); p.aiming=false
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
        p.aiming=true
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
        p.aiming=false; step(p,3)
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
print("stock aim/controller integration: "..passed.." passed (native/player boundaries doubled)")

assert(failed==0,tostring(failed).." stock aim integration regression(s)")
