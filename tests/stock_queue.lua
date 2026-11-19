-- Exercise unmodified external stock queue/base Lua. JVM/player handles here are doubles.
package.preload.ISBaseObject=function()
    ISBaseObject={}
    function ISBaseObject:derive(kind)
        local obj={Type=kind}
        setmetatable(obj,{__index=self})
        return obj
    end
end
function instanceof() return false end
table.wipe=function(t) for k in pairs(t) do t[k]=nil end end
Events={OnTick={Add=function()end}}
for _,name in ipairs({"ClimbThroughWindowState","ClimbOverFenceState","ClimbOverWallState","ClimbState","ClimbDownState","CloseWindowState","OpenWindowState","ForceOpenState"}) do _G[name]={instance=function() return {} end} end
ISLogSystem={logAction=function()end}
LuaTimedActionNew={new=function(lua) return {lua=lua, isStarted=function()return true end, getJobDelta=function() return 0 end, hasStalled=function() return false end} end}
local function stock(path)
    if loadUpstream then loadUpstream(path)
    else assert(loadfile(assert(arg[1], "Pass the game media path") .. "/lua/" .. path))() end
end
stock("client/TimedActions/ISTimedActionQueue.lua")
stock("shared/TimedActions/ISBaseTimedAction.lua")
package.path="mods/AutoMindful/common/media/lua/client/?.lua;" .. package.path
local Y=require "AutoMindful/ActionYield"
local owner={}
local function player()
    local p={}
    function p:StartAction(a) self.native=a; a.lua:start() end
    function p:StopAllActionQueue()
        if self.native and self.native.lua then self.native.lua:stop() end
        self.native = self.afterClear
    end
    function p:getCharacterActions()
        return {contains=function(_,a) return a~=nil and a==self.native end,
                isEmpty=function() return self.native==nil end,
                size=function() return self.native and 1 or 0 end}
    end
    function p:setTimedActionToRetrigger(v) self.retrigger=v end
    function p:getTimedActionToRetrigger() return self.retrigger end
    function p:setIsFarming() end
    function p:getCurrentState() return {} end
    function p:hasTimedActions() return self.native~=nil end
    return p
end
local function action(p,name)
    local a=ISBaseTimedAction:new(p); a.Type=name
    function a:start() self.starts=(self.starts or 0)+1 end
    function a:forceCancel() self.cancels=(self.cancels or 0)+1 end
    return a
end
local function add(a) ISTimedActionQueue.add(a) end
local p=player(); local head=action(p,"Meditate"); head.autoMindfulOwner=owner
local ownTail=action(p,"Stand"); ownTail.autoMindfulOwner=owner
local first=action(p,"Workout"); local second=action(p,"Drink"); local appended=action(p,"ReentrantWork")
function head:stop()
    self.stops=(self.stops or 0)+1
    ISBaseTimedAction.stop(self)
    add(appended)
end
head.retriggerLastAction=true
local retrigger={}; function retrigger:getTable() error("A canceled owned action must not trigger previous action") end
add(head); p.retrigger=retrigger; add(first); add(ownTail); add(second)
local q=ISTimedActionQueue.getTimedActionQueue(p)
assert(Y.release(p,owner))
assert(head.stops==1 and ownTail.cancels==1 and #q.queue==3)
assert(q.queue[1]==first and q.queue[2]==second and q.queue[3]==appended)
assert(first.starts==1 and not second.starts and not appended.starts)
assert(q.current==first and p.native==first.action and not rawget(q,"resetQueue") and not rawget(q,"clearQueue"))
q:tick()
p.native=nil; first:perform()
assert(second.starts==1 and q.current==second)
p.native=nil; second:perform()
assert(appended.starts==1 and q.current==appended)
assert(Y.release(p,owner) and appended.starts==1 and p.native==appended.action)
p.native=nil; appended:perform()
assert(#q.queue==0 and q.current==nil)
print("stock ordered handoff / reentrant append / no retrigger / foreign-only release PASS")

p=player(); head=action(p,"Meditate"); head.autoMindfulOwner=owner; first=action(p,"Workout")
add(head); add(first); q=ISTimedActionQueue.getTimedActionQueue(p)
p.afterClear={}
assert(not Y.release(p,owner) and q.queue[1]==head and not first.starts)
q:tick(); assert(not first.starts and q.autoMindfulHandoff)
p.native=nil; q:tick()
assert(first.starts==1 and q.current==first and q.queue[1]==first and not rawget(q,"tick"))
q:tick(); assert(first.starts==1 and p.native==first.action)
print("stock tick defers successor until native-only work drains PASS")

p=player(); head=action(p,"Meditate"); head.autoMindfulOwner=owner; first=action(p,"Workout")
add(head); add(first); q=ISTimedActionQueue.getTimedActionQueue(p)
local unexpected={}; p.native=unexpected
assert(not Y.release(p,owner) and p.native==unexpected and q.queue[1]==head and not first.starts)
print("unrecognized native ownership fails closed PASS")
