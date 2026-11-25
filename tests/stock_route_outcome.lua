-- Run the unmodified B42 stock ISPathFindAction.lua against the controller's
-- queue and a deferred Java boundary double. No game client/server is launched.
AutoMindfulContractHarnessOnly = true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly = nil
local T, Controller = AutoMindfulTest, AutoMindfulTest.controller
local RouteOutcome = require "AutoMindful/RouteOutcome"
local noop = function() end
BehaviorResult = {Failed="Failed", Succeeded="Succeeded", Working="Working"}
ISBaseTimedAction = {}
function ISBaseTimedAction:derive(name)
    local cls = {Type=name}
    cls.__index = cls
    return setmetatable(cls, {__index=self})
end
function ISBaseTimedAction:new(character)
    return setmetatable({character=character}, self)
end
function ISBaseTimedAction:begin()
    local a=self
    self.action = {
        setPathfinding=noop, setAllowedWhileDraggingCorpses=noop,
        forceStop=function() a.requestedStop=true end,
        forceComplete=function() a.requestedComplete=true end,
    }
    self.character.nativeHead = self.action
    self:start()
end
function ISBaseTimedAction:forceStop() self.action:forceStop() end
function ISBaseTimedAction:forceComplete() self.action:forceComplete() end
function ISBaseTimedAction:stop()
    ISTimedActionQueue.getTimedActionQueue(self.character):resetQueue()
    self.character.nativeHead = nil
end
function ISBaseTimedAction:perform()
    self.character.nativeHead = nil
    ISTimedActionQueue.getTimedActionQueue(self.character):onCompleted(self)
end
if loadUpstream then loadUpstream("client/Vehicles/TimedActions/ISPathFindAction.lua")
else assert(loadfile(assert(arg[1], "Pass GAME/media").."/lua/client/Vehicles/TimedActions/ISPathFindAction.lua"))() end
local function player()
    local p=T.playerNew()
    p.kind="IsoPlayer"
    p.result=BehaviorResult.Working
    local route={
        update=function() return p.result end,
        cancel=noop,
        pathToNearestTable=function(_,path)
            p.pathCalls[#p.pathCalls+1]=path
        end,
    }
    p.pathCalls={}
    function p:getPathFindBehavior2() return route end
    function p:setPath2() end
    return p
end
local preferred, alternate = {3.5,0.5,0}, {4.5,0.5,0}
local function ownField(a,k)
    for key, value in pairs(a) do if key==k then return value end end
end
local function makePath(p)
    return ISPathFindAction:pathToNearestPreferred(p,preferred,alternate)
end

do
    local p=player()
    local a=makePath(p)
    local n=0
    local function onFail(x,y,z,w)
        assert(x=="one" and y==nil and z=="three" and w==false, "preserve prior callback and all its exact arguments")
        n=n+1
    end
    a:setOnFail(onFail,"one",nil,"three",false)
    local args=a.onFailArgs
    RouteOutcome.observe(a)
    a:begin()
    assert(p.pathCalls[1]==preferred)
    p.result=BehaviorResult.Working
    a:update()
    assert(not RouteOutcome.failed(a) and not a.requestedStop and n==0)
    p.result=BehaviorResult.Failed
    a:update()
    -- 42.22.2 sets the diagonal goal and then still calls onFail + forceStop
    -- in this frame. The observer neither fixes nor removes this stock behavior.
    assert(p.pathCalls[2]==alternate and a.goal[4]==true)
    assert(n==1 and a.onFailFunc==onFail and a.onFailArgs==args)
    assert(not ownField(a,"forceStop"), "restore inherited engine hook, even in Kahlua")
    assert(a.result==nil and a.requestedStop and RouteOutcome.failed(a))
    assert(p.nativeHead==a.action,"Java boundary may not drain before update returns")
    a:stop()
    assert(RouteOutcome.failed(a) and not p.nativeHead)
end

do
    -- A patched/modded native update can continue the diagonal attempt after
    -- notifying the caller. No terminal marker unless it really requests a stop.
    local p=player()
    local a=makePath(p)
    local stockUpdate=a.update
    local priorCalls=0
    a:setOnFail(function() priorCalls=priorCalls+1 end)
    function a:update()
        if not self.goal[4] and p.result==BehaviorResult.Failed then
            self.goal[4]=true
            p:getPathFindBehavior2():pathToNearestTable(self.goal[3])
            local args=self.onFailArgs
            self.onFailFunc(args[1],args[2],args[3],args[4])
            return -- stock dispatcher is allowed to continue the alternative
        end
        return stockUpdate(self)
    end
    RouteOutcome.observe(a)
    a:begin()
    p.result=BehaviorResult.Failed; a:update()
    assert(priorCalls==1 and p.pathCalls[2]==alternate and not RouteOutcome.failed(a) and not a.requestedStop)
    p.cancelInput=true; a:update()
    assert(a.requestedStop and not RouteOutcome.failed(a), "manual cancel after a fallback notification is not failure")
    a:stop()
end

do
    local p=player()
    local a=makePath(p)
    RouteOutcome.observe(a)
    a:begin()
    p.result=BehaviorResult.Succeeded; a:update()
    assert(not a.requestedStop and a.requestedComplete and not RouteOutcome.failed(a))
    assert(not ownField(a,"onFailFunc") and not ownField(a,"onFailArgs"))
    a:perform()
end

do
    local p=player()
    local a=makePath(p)
    local n=0
    a:setRunActionsAfterFailing(true)
    RouteOutcome.observe(a)
    a:begin()
    p.result=BehaviorResult.Failed; a:update()
    assert(a.requestedStop and not a.requestedComplete, "an observer must not add behavior to a missing onFail binding")
    a:stop()
    a=makePath(p)
    RouteOutcome.observe(a)
    -- Native/mod code can register a callback *after* the action is owned.
    a:setOnFail(function() n=n+1 end)
    a:setRunActionsAfterFailing(true)
    a:begin(); a:update()
    assert(n==1 and a.requestedComplete and not a.requestedStop and not RouteOutcome.failed(a))
    a:perform()
end

local Nearby, Options = require "AutoMindful/Nearby", require "AutoMindful/Options"
local function first(p) return ISTimedActionQueue.getTimedActionQueue(p).queue[1] end
local function has(p,kind)
    for _, entry in ipairs(p.history) do if entry==kind then return true end end
end
Options.searchNearby = function() return true end
function getGameSpeed() return 1 end
function getCell()
    return {getGridSquare=function(_,x,y,z)
        return T.player and T.player.loadedSquares[x..":"..y..":"..z]
    end}
end
ISWalkToTimedAction={new=function(_,p,s)
    local a=T.action(p,"ISWalkToTimedAction",function() p.square=s end)
    a.location=s
    return a
end}
luautils = luautils or {}
function luautils.walkAdjObject(p,o,diag,keep)
    assert(diag and keep)
    ISTimedActionQueue.add(makePath(p))
    return true
end
function luautils.walkAdj(p,s,keep)
    assert(keep)
    ISTimedActionQueue.add(ISWalkToTimedAction:new(p,T.square(s:getX()-1,s:getY(),s:getZ())))
    return true
end
local function setup()
    local p=player()
    local origin=p:getSquare()
    p.values.THIRST=.35
    local other=T.container(6,0)
    local item=T.add(other,T.water())
    p.available={other}
    local blocked=T.square(3,0)
    local obj={getMasterObject=function(self)return self end}
    local target={key="blocked",object=obj,square=blocked}
    local alternateTarget={key="bottle",square=other.square,container=other,item=item}
    Nearby.find=function(_,kind,_,_,rejected)
        if kind=="water" then
            if not rejected.blocked then return target end
            if not rejected.bottle then return alternateTarget end
        end
    end
    assert(Controller.start(p,"meditation",false))
    T.tick(p,false)
    assert(first(p) and first(p).Type=="ISPathFindAction")
    return p,origin,other
end

do
    local p,origin,other=setup()
    local a=first(p)
    p.square=T.square(1,0) -- the game got part-way before its no-route stop
    p.moving=true -- residual native motion; no pressed movement
    p.result=BehaviorResult.Failed; a:update()
    assert(a.requestedStop and a.result==nil)
    a:stop()
    T.tick(p,false)
    assert(Controller.status(p).active and first(p) and first(p).Type=="ISWalkToTimedAction"
        and first(p).location:getX()==other.square:getX()-1,
        "native failure ends neither the session nor the outing: the next known source is tried from here")
    p.moving=false
    first(p):perform()
    for _=1,22 do
        T.tick(p,false)
        local head=first(p)
        if head and head.Type=="Meditation" then break end
        if head then head:perform() end
    end
    assert(has(p,"drink") and has(p,"Meditation") and p:getSquare()==origin,
        "use next known route and resume training at home")
    Controller.stop(p)
end

do
    local p,origin=setup()
    local a=first(p)
    p.square=T.square(1,0)
    p.cancelInput=true
    p.result=BehaviorResult.Failed
    a:update()
    assert(a.requestedStop and not RouteOutcome.failed(a))
    a:stop(); p.cancelInput=false
    T.tick(p,false)
    assert(not Controller.status(p).active and not first(p) and p:getSquare()~=origin,
        "released manual cancel must not become an automatic walk back")
end
print("PASS: stock B42 path failure evidence, fallback and prior callback unchanged; alternate tried on the way, then exact home; no manual reversal")

-- Use the shipped path constructors and update(), not an invented 'successful
-- fallback' action. Only the navmesh result and local map are boundary doubles.
do
    local Routes=require "AutoMindful/SurvivalRoute"
    local p=player()
    function p:getCurrentSquare() return self:getSquare() end
    local geometry={}
    local function square(x,y)
        local k=x..":"..y
        if geometry[k] then return geometry[k] end
        local s=T.square(x,y)
        function s:getAdjacentSquare(d) return square(self.x+d.dx,self.y+d.dy) end
        geometry[k]=s; return s
    end
    IsoDirections={}
    for k,v in pairs({N={0,-1},S={0,1},W={-1,0},E={1,0},NE={1,-1},NW={-1,-1},SE={1,1},SW={-1,1}}) do
        local d={dx=v[1],dy=v[2]}
        function d:isDiagonal() return self.dx~=0 and self.dy~=0 end
        function d:ToVector()
            local n=self:isDiagonal() and math.sqrt(2) or 1
            return {getX=function()return self.dx/n end,getY=function()return self.dy/n end}
        end
        IsoDirections[k]=d
    end
    function luautils.tableContains(t,v) for _,e in ipairs(t) do if e==v then return true end end end
    function luautils.getCorrectSquareForWall(_,s) return s end
    ArrayList={new=function()
        local a={}
        return {add=function(_,x)a[#a+1]=x end,get=function(_,n)return a[n+1] end,
            size=function()return #a end,clear=function() a={} end}
    end}
    AdjacentFreeTileFinder={isTileOrAdjacent=function() return true end}
    local savedCell=getCell
    function getCell() return {getGridSquare=function(_,x,y,z) return z==0 and square(x,y) or nil end} end
    local source=square(5,0)
    local obj={getSquare=function()return source end}
    function obj:getSpriteGridObjectsIncludingSelf(t) t:add(self) end
    for _,world in ipairs({true,false}) do
        local fresh=player()
        fresh.getCurrentSquare=p.getCurrentSquare
        local winner=square(6,1) -- every cardinal point and three other diagonal points are disconnected
        local current
        local pf={cancel=noop,pathToNearestTable=function(_,goals) current=goals end}
        function pf:update()
            for i=1,#current,3 do
                if math.floor(current[i])==winner.x and math.floor(current[i+1])==winner.y then
                    fresh.square=winner; return BehaviorResult.Succeeded
                end
            end
            return BehaviorResult.Failed
        end
        function fresh:getPathFindBehavior2() return pf end
        assert(Routes.walk(fresh,source,world and obj or nil))
        local a=first(fresh)
        assert(a and a.Type=="ISPathFindAction" and a.goal[1]=="Nearest" and #current==24)
        a:update(); assert(a.requestedComplete and not a.requestedStop and fresh:getSquare()==winner,
            "one native route must be allowed to settle on the only reachable interaction side")
        a:perform()
    end
    getCell=savedCell
end
print("PASS: installed B42 fixture and cupboard route constructors actually submit the only reachable diagonal in a single native path")
