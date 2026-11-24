-- Called by mindfulness_native.lua with the installed game and Lifestyle sources.
-- Survivor reported standing on the center crate, boarded windows behind, lamp to one side.
-- The log proves failed walks, critical hunger, low HP, then death; it has no collision
-- graph, per-need stat readings, active badge or cause of death. The two room graphs below
-- deliberately differ by one legal exit. They are inputs, not reconstructions of map data.
return function(prepare,step,head,count,tapAt,stockDrinker)
    local T,C=AutoMindfulTest,AutoMindfulTest.controller
    local nearby=require "AutoMindful/Nearby"
    package.loaded["AutoMindful/Nearby"]=nil
    for k,v in pairs(require "AutoMindful/Nearby") do nearby[k]=v end

    loadStockLua("shared/luautils.lua")
    loadStockLua("client/Vehicles/TimedActions/ISPathFindAction.lua")
    BehaviorResult={Failed="Failed",Succeeded="Succeeded"}
    function getGameSpeed() return 1 end
    local function noop() end
    ArrayList={new=function()
        local entries={}
        local a=T.list(entries)
        function a:add(v) entries[#entries+1]=v end
        function a:clear() for i=#entries,1,-1 do entries[i]=nil end end
        return a
    end}
    IsoDirections={}
    for name,xy in pairs({W={-1,0},E={1,0},N={0,-1},S={0,1},
            NW={-1,-1},NE={1,-1},SW={-1,1},SE={1,1}}) do
        local x,y=xy[1],xy[2]
        local d={x=x,y=y,getX=function() return x end,getY=function() return y end}
        function d:ToVector() return d end
        function d:isDiagonal() return x~=0 and y~=0 end
        IsoDirections[name]=d
    end
    IsoFlagType={collideW="W",collideN="N"}
    AdjacentFreeTileFinder={isTileOrAdjacent=function(_,s) return s:canStand() end}

    -- Stock handles preferred/alternate sets, callbacks and cancellation. The Java
    -- pathfinder reports failure for disconnected components, success for the one
    -- reachable diagonal approach. Receiving a location request is not arrival.
    function ISPathFindAction:begin()
        local a=self
        self.action={setPathfinding=noop,setAllowedWhileDraggingCorpses=noop,
            forceStop=function() a.requestStop=true end,forceComplete=function() a.requestComplete=true end}
        self.character.nativeHead=self.action
        self:start()
    end
    function ISPathFindAction:forceStop() self.action:forceStop() end
    function ISPathFindAction:forceComplete() self.action:forceComplete() end
    ISWalkToTimedAction={new=function(_,p,s)
        local a=T.action(p,"ISWalkToTimedAction",function() p.square=s end)
        a.location=s
        return a
    end}

    local function replay(sealed)
        -- Stress the delayed batch in the escapable room; for the sealed room use
        -- the logged server's automatic mood flush setting. Clocks remain fixture inputs.
        SandboxVars.LS.MoodUpdate=sealed and 1 or 7
        SandboxVars.DayLength=sealed and 6 or 4
        local p=prepare(6,"HUNGER",.80)
        p.values.THIRST,p.thirstMoodle,p.hungerMoodle=.90,4,4
        p.values.HEALTH,p.sitting,p.kind=51,false,"IsoPlayer"
        p.getCurrentSquare,p.setPath2=p.getSquare,noop
        stockDrinker(p)
        local here,room=p:getSquare(),{}
        local function tile(x,y,standing)
            local s=(x==0 and y==0) and here or T.square(x,y)
            s.edges={}
            function s:canStand() return standing==true end
            function s:isFree() return self:canStand() end
            function s:getRoom() return room end
            function s:has() return false end
            function s:getObjects() return T.list({}) end
            function s:getWorldObjects() return T.list({}) end
            function s:getAdjacentSquare(d) return getCell():getGridSquare(x+d.x,y+d.y,0) end
            T.loadSquare(p,s)
            return s
        end
        local function link(a,b) a.edges[#a.edges+1]=b; b.edges[#b.edges+1]=a end
        local function connected(start,target)
            if not target then return false end
            local seen,queue,at={[start]=true},{start},1
            while queue[at] do
                local s=queue[at]; at=at+1
                if s==target then return true end
                for _,other in ipairs(s.edges) do
                    if not seen[other] then seen[other]=true; queue[#queue+1]=other end
                end
            end
            return false
        end
        --                 (-1)   (0)    (1)
        -- y=-1              W     W      W     boarded window boundary
        -- y= 0              C     C*     L     *survivor starts here
        -- y= 1                    S            unreported south side: two cases
        for x=-1,1 do tile(x,-1,false) end
        tile(-1,0,false); tile(0,0,false); tile(1,0,false)
        function here:isWindowTo(s) return s:getY()==-1 end
        local south=tile(0,1,true)
        if not sealed then link(here,south) end
        local hereToSink=south
        for x=0,5 do local s=tile(x,2,true); link(hereToSink,s); hereToSink=s end
        local diagonal=tile(5,1,true); link(hereToSink,diagonal)
        local dirty=tapAt(p,tile(1,1,false),true)
        local blocked=tapAt(p,tile(3,-1,false))
        local isolated=tile(3,-2,true)  -- clear at the fixture, not connected to the player
        local good=tapAt(p,tile(6,0,false))
        tile(6,-1,true)                -- clean sink's cardinal pocket also disconnected

        local route={cancel=noop}
        local denied,arrivals,backToCrate=0,0,false
        function route:pathToNearestTable(points)
            self.destination,self.primary=nil,false
            for i=1,#points,3 do
                local s=getCell():getGridSquare(math.floor(points[i]),math.floor(points[i+1]),points[i+2])
                if s==isolated then self.primary=true end
                if connected(p:getSquare(),s) then self.destination=s; break end
            end
        end
        function route:update()
            if not self.destination then
                if self.primary then denied=denied+1 end
                return BehaviorResult.Failed
            end
            p.square=self.destination
            if self.destination==diagonal then arrivals=arrivals+1 end
            return BehaviorResult.Succeeded
        end
        function p:getPathFindBehavior2() return route end
        local function stepRoute(a)
            if a.Type=="ISWalkToTimedAction" then
                if a.location==here and p:getSquare()~=here then backToCrate=true end
                if a.location:canStand() and connected(p:getSquare(),a.location) then a:perform()
                else a.result=BehaviorResult.Failed; a:stop() end
                return true
            end
            if a.Type~="ISPathFindAction" then return false end
            a:update()
            if a.requestStop then a:stop() elseif a.requestComplete then a:perform() end
            return true
        end

        local low,acquired,observed
        for second=1,480 do
            local action=head(p)
            if not low and (sealed and denied>0 and second>=8 or not sealed and action and action.Type=="ISTakeWaterAction") then
                if not sealed then assert(action.waterObject==good and p:getSquare()==diagonal and not good.sample) end
                p.values.HEALTH,low=49,second
                C.update(p) -- HP change reaches scheduler before the drink's native complete()
            end
            step(p,second,stepRoute)
            if not acquired and p.data.LSMoodles.MindfulState.Value>=.4 then
                acquired=second
                assert(p.values.HUNGER==.8,"an acquired badge does not feed the survivor")
            end
            if not observed and (C.status(p).careNotice or ""):find("hunger ease",1,true) then
                observed=second
                assert(acquired and observed>acquired and p.values.HUNGER<.8,"readback, not a tier, must confirm relief")
            end
            if p.values.HUNGER<.70 then p.hungerMoodle=3 end -- fixture: crossing the default stage-four threshold
            if observed and second>=220 then break end
        end
        local message=C.status(p).message
        assert(denied>0,"the closer source should report a real failed approach")
        if sealed then
            assert(arrivals==0 and p:getSquare()==here and good.refills==0 and p.values.THIRST==.90,
                "there is no exit: no water/position change can be reported")
        else
            assert(arrivals>0,"no successful route to clean alternate after the blocked source; last state: "..message)
            assert(not backToCrate and p:getSquare()~=here,"sent survivor back onto the obstructed crate")
            assert(low and good.refills==1 and good.sample.disposed and p.values.THIRST==0,
                "stock did not complete the available safe drink across the 50 HP boundary")
        end
        assert(dirty.refills==0 and blocked.refills==0,"unsafe or out-of-reach source consumed")
        assert(low and acquired and observed and acquired>low,
            (sealed and "sealed" or "open").." crate: no verified native hunger relief while at 49 HP: "..message)
        assert(p.values.HEALTH==49 and count(p,"eat")==0 and p.calories==2000 and C.status(p).active)
        print(("NATIVE PASS %s crate: %s; at 49 HP, switched to Strong, hunger %.3f at %ds; no calories or HP granted"):
            format(sealed and "sealed" or "escapable",sealed and "stayed on crate; no water" or "stock diagonal route and drink",
                p.values.HUNGER,observed))
        C.stop(p)
    end
    replay(false)
    replay(true)
end
