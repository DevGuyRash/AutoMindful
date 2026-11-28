-- A bite between somebody else's actions, over the game's own queue, base
-- action and queue-actions action. Characters and items are doubles.
local media=not loadUpstream and assert(arg and arg[1],"Pass the game media path")
package.path="mods/SecondNature/common/media/lua/client/?.lua;" .. package.path
package.preload.ISBaseObject=function()
    ISBaseObject={}
    function ISBaseObject:derive(kind)
        local o={Type=kind}; setmetatable(o,{__index=self}); o.__index=o
        return o
    end
end
function instanceof() return false end
table.wipe=function(t) for k in pairs(t) do t[k]=nil end end
Events={OnTick={Add=function() end}}
for _,name in ipairs({"ClimbThroughWindowState","ClimbOverFenceState","ClimbOverWallState","ClimbState","ClimbDownState","CloseWindowState","OpenWindowState","ForceOpenState"}) do _G[name]={instance=function() return {} end} end
ISLogSystem={logAction=function() end}
local running
LuaTimedActionNew={new=function(lua)
    local java={lua=lua}
    function java:isStarted() return self.started==true end
    function java:getJobDelta() return 0 end
    function java:hasStalled() return false end
    function java:setPathfinding() end
    function java:setAllowedWhileDraggingCorpses() end
    function java:forceStop() self.lua:stop() end
    function java:forceComplete() self.complete=true end
    return java
end}
package.loaded["TimedActions/ISBaseTimedAction"]=true
local function stock(path)
    if loadUpstream then loadUpstream(path) else assert(loadfile(media.."/lua/"..path))() end
end
stock("client/TimedActions/ISTimedActionQueue.lua")
stock("shared/TimedActions/ISBaseTimedAction.lua")
stock("client/TimedActions/ISQueueActionsAction.lua")
package.loaded["TimedActions/ISQueueActionsAction"]=true

MoodleType={THIRST="thirst",HUNGRY="hungry",FOOD_EATEN="full"}
CharacterStat={THIRST="THIRST",HUNGER="HUNGER"}
local now=100000
function getTimestampMs() return now end
local entry,rejected,eaten
package.loaded["AutoMindful/Log"]={event=function() end,change=function() end,error=function(_,where,message) error(where..": "..tostring(message)) end}
package.loaded["AutoMindful/Snapshot"]={item=tostring,action=tostring}
local maskTracked
package.loaded["AutoMindful/MaskRestore"]={capture=function(p) return p.mask end,track=function(mask,batch) maskTracked=#batch; return mask end}
package.loaded["AutoMindful/Danger"]={read=function(p) return p.danger or "clear" end}
package.loaded["AutoMindful/Supplies"]={choose=function(_,kind,nearby) assert(nearby==false,"Only what is carried"); return entry and entry.kind==kind and entry or nil end,
    rejectScoutIntake=function(_,item) rejected=item end}
local intake
package.loaded["AutoMindful/Consumables"]={restoredThreshold=1e-6,consume=function(p) if intake then intake(p) end end}
local Interject=require "AutoMindful/Interject"

local function survivor()
    local p={stats={THIRST=.1,HUNGER=.1},moodles={}}
    function p:getStats() return {get=function(_,k) return p.stats[k] end} end
    function p:getMoodles() return {getMoodleLevel=function(_,k) return p.moodles[k] or 0 end} end
    function p:StartAction(java)
        self.native=java; java.started=true; java.lua:start()
    end
    function p:StopAllActionQueue() end
    function p:getCharacterActions() return {contains=function(_,a) return a==p.native end,isEmpty=function() return p.native==nil end} end
    function p:setTimedActionToRetrigger(v) self.retrigger=v end
    function p:getTimedActionToRetrigger() return self.retrigger end
    function p:setIsFarming() end
    function p:isAsleep() return false end
    function p:isDraggingCorpse() return false end
    function p:pressedMovement() return self.moving or false end
    function p:pressedCancelAction() return false end
    function p:isAiming() return self.aim or false end
    function p:isAttacking() return false end
    return p
end
local function work(p,name)
    local a=ISBaseTimedAction.new(ISBaseTimedAction:derive(name),p)
    a.Type=name
    function a:isValid() return true end
    function a:start() self.starts=(self.starts or 0)+1 end
    function a:forceCancel() self.cancelled=true end
    return a
end
local function finish(p)
    local timed=ISTimedActionQueue.getTimedActionQueue(p)
    local head=timed.queue[1]
    p.native=nil
    head:perform()
end
-- The engine completes an action that asked for it on its next update.
local function settle(p)
    for _=1,6 do
        local head=ISTimedActionQueue.getTimedActionQueue(p).queue[1]
        if head and head.action and head.action.complete then finish(p) end
    end
end
local function names(p)
    local out={}
    for _,a in ipairs(ISTimedActionQueue.getTimedActionQueue(p).queue) do out[#out+1]=a.autoMindfulInterject and "chooser" or a.Type end
    return table.concat(out," ")
end
local function consider(p,state) return Interject.consider(p,state,ISTimedActionQueue.getTimedActionQueue(p).queue,now) end

-- A row of trees.
do
    local p,state=survivor(),{rejected={},active=true,recovery=true}
    local trees={work(p,"chop1"),work(p,"chop2"),work(p,"chop3")}
    for _,tree in ipairs(trees) do ISTimedActionQueue.add(tree) end
    assert(not consider(p,state),"Nothing due, nothing placed")
    entry={kind="food",owned=true,item={getID=function() return 9 end},description={}}
    p.stats.HUNGER,p.moodles.hungry=.3,1
    local meal
    intake=function(who)
        meal=work(who,"eat")
        function meal:perform() p.stats.HUNGER=0; p.moodles.hungry=0; eaten=true; ISBaseTimedAction.perform(self) end
        ISTimedActionQueue.add(meal)
        ISTimedActionQueue.add(work(who,"putBack"))
    end
    assert(consider(p,state)=="food" and names(p)=="chop1 chooser chop2 chop3")
    now=now+500; assert(not consider(p,state) and names(p)=="chop1 chooser chop2 chop3","One at a time")
    finish(p); settle(p)
    assert(names(p)=="eat putBack chop2 chop3",names(p))
    finish(p); finish(p)
    assert(eaten and names(p)=="chop2 chop3" and trees[2].starts==1 and not trees[2].cancelled and not trees[3].cancelled)
    now=now+1000; consider(p,state)
    assert(not state.interject and not rejected)
    finish(p); finish(p); assert(names(p)=="" and trees[3].starts==1)
end
-- Gone by the time its turn comes: the rest of the row must not notice.
do
    local p,state=survivor(),{rejected={},active=true,recovery=true}
    local a,b=work(p,"chop1"),work(p,"chop2")
    ISTimedActionQueue.add(a); ISTimedActionQueue.add(b)
    p.moodles.hungry,p.stats.HUNGER=2,.5
    entry={kind="food",owned=true,item={getID=function() return 9 end},description={}}
    assert(consider(p,state)=="food")
    entry=nil
    finish(p); settle(p)
    assert(names(p)=="chop2" and b.starts==1 and not b.cancelled,"Finding nothing must not reset the queue")
end
-- A mod that only ever queues one action still leaves room for a sip.
do
    local p,state=survivor(),{rejected={},active=true,recovery=true}
    ISTimedActionQueue.add(work(p,"loop1"))
    p.moodles.thirst,p.stats.THIRST=1,.2
    entry={kind="water",owned=true,item={getID=function() return 1 end},description={}}
    intake=function(who) ISTimedActionQueue.add(work(who,"drink")) end
    assert(consider(p,state)=="water")
    ISTimedActionQueue.add(work(p,"loop2"))
    finish(p); settle(p)
    assert(names(p)=="drink loop2")
    finish(p); now=now+1000
    for _=1,60 do now=now+250; consider(p,state) end
    assert(rejected==entry.item,"A sip that changed nothing is not repeated at once")
end
-- A bite that cannot be finished is not the end of the row. Walking off is.
for _,walking in ipairs({false,true}) do
    local p,state=survivor(),{rejected={},active=true,recovery=true}
    local a,b,c=work(p,"chop1"),work(p,"chop2"),work(p,"chop3")
    for _,tree in ipairs({a,b,c}) do ISTimedActionQueue.add(tree) end
    p.moodles.hungry,p.stats.HUNGER=2,.5
    entry={kind="food",owned=true,item={getID=function() return 1 end},description={}}
    intake=function(who) ISTimedActionQueue.add(work(who,"fetch")); ISTimedActionQueue.add(work(who,"eat")) end
    assert(consider(p,state)=="food"); finish(p); settle(p)
    assert(names(p)=="fetch eat chop2 chop3",names(p))
    local timed=ISTimedActionQueue.getTimedActionQueue(p)
    p.moving=walking
    timed.queue[1]:stop(); p.native=nil; timed:tick(); timed:tick()
    assert(names(p)==(walking and "" or "chop2 chop3"),names(p))
    if not walking then assert(b.starts==1 and not b.cancelled and not c.cancelled) end
end
-- Stopped, or the need gone, before its turn came.
for _,case in ipairs({"stopped","fed"}) do
    local p,state=survivor(),{rejected={},active=true,recovery=true}
    ISTimedActionQueue.add(work(p,"chop1")); ISTimedActionQueue.add(work(p,"chop2"))
    p.moodles.hungry,p.stats.HUNGER=2,.5
    local ate=false
    entry={kind="food",owned=true,item={getID=function() return 1 end},description={}}
    intake=function(who) ate=true; ISTimedActionQueue.add(work(who,"eat")) end
    assert(consider(p,state)=="food")
    if case=="stopped" then state.active=false else p.moodles.hungry=0 end
    finish(p); settle(p)
    assert(not ate and names(p)=="chop2",case)
end
-- No drink ready must not hide the meal that is.
do
    local p,state=survivor(),{rejected={},active=true,recovery=true}
    ISTimedActionQueue.add(work(p,"chop1"))
    p.moodles.hungry,p.moodles.thirst=2,4
    entry={kind="food",owned=true,item={getID=function() return 1 end},description={}}
    assert(consider(p,state)=="food")
end
-- A mask comes off for the bite; if the bite is cut short someone remembers it.
do
    local p,state=survivor(),{rejected={},active=true,recovery=true}
    p.mask={}
    ISTimedActionQueue.add(work(p,"chop1")); ISTimedActionQueue.add(work(p,"chop2"))
    p.moodles.hungry,p.stats.HUNGER=2,.5
    entry={kind="food",owned=true,item={getID=function() return 1 end},description={}}
    intake=function(who) for _,n in ipairs({"unmask","eat","mask"}) do ISTimedActionQueue.add(work(who,n)) end end
    assert(consider(p,state)=="food"); finish(p); settle(p)
    assert(names(p)=="unmask eat mask chop2" and state.maskRestore==p.mask and maskTracked==3)
    local unmask=ISTimedActionQueue.getTimedActionQueue(p).queue[1]
    finish(p); assert(unmask.autoMindfulFinished)
end
-- When not to.
do
    for _,case in ipairs({"engaged","aim","unready"}) do
        local p,state=survivor(),{rejected={},active=true,recovery=true}
        ISTimedActionQueue.add(work(p,"chop1"))
        p.moodles.hungry,p.stats.HUNGER=3,.6
        entry={kind="food",owned=true,item={getID=function() return 9 end},description={needsOpening=case=="unready" or nil}}
        if case=="engaged" then p.danger="engaged" elseif case=="aim" then p.aim=true end
        assert(not consider(p,state) and names(p)=="chop1",case)
    end
end
print("PASS one ready bite or sip between someone else's actions; their queue keeps its order and every action")
