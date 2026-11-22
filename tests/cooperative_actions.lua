-- Queue boundaries are explicit doubles. These scenarios preserve object identity
-- and exercise native-style completion chains, not real animations or networking.
return function(T, C, test, scoutTarget)
    local function queue(p) return ISTimedActionQueue.getTimedActionQueue(p).queue end
    local function began()
        local p=T.playerNew(); p.sitting=true
        assert(C.start(p,"meditation",false)); T.tick(p,false)
        assert(queue(p)[1].Type=="Meditation")
        return p,queue(p)[1]
    end
    local function untouched(action)
        assert(not action.autoMindfulOwner and not action.stopped and not action.cancelled,
            "Another action keeps its owner and is never stopped by AutoMindful")
        assert((action.begins or 0)<=1, "Foreign actions begin at most once")
        assert(action.adds==1 and not action.removes, "Foreign actions are never removed and re-added")
    end
    local function resumed(p)
        for i=1,5 do T.tick(p,false); if C.status(p).phase=="meditation" then break end end
        assert(C.status(p).active and C.status(p).phase=="meditation", "Training resumes after the foreign queue drains")
        C.stop(p)
    end
    local function withPanels(fn)
        local oldUI,oldModal,oldWorld=UIManager.getUI,UIManager.getModal,ISWorldMap_instance
        local panels={items={},modal=nil}
        UIManager.getUI=function() return T.list(panels.items) end
        UIManager.getModal=function() return panels.modal end
        ISWorldMap_instance=nil
        function panels:java(luaPanel)
            return {getTable=function() return luaPanel end,
                isVisible=function() return luaPanel.visible~=false end}
        end
        function panels:paper(slot)
            local panel={Type="ISMapWrapper",mapUI={playerNum=slot},visible=true,isCollapsed=false}
            function panel:isReallyVisible() return self.visible end
            self.items[#self.items+1]=self:java(panel)
            return panel
        end
        function panels:world(slot)
            local panel={Type="ISWorldMap",playerNum=slot,visible=true}
            function panel:isVisible() return self.visible end
            ISWorldMap_instance=panel
            self.items[#self.items+1]=self:java(panel)
            return panel
        end
        local ok,reason=pcall(fn,panels)
        UIManager.getUI,UIManager.getModal,ISWorldMap_instance=oldUI,oldModal,oldWorld
        assert(ok,reason)
    end
    test("both native map readers yield both training modes until their map panel closes",function()
        withPanels(function(panels)
            for _,mode in ipairs({"yoga","meditation"}) do
                for _,kind in ipairs({"ISReadMapItem","ISReadWorldMap"}) do
                    panels.items={}; ISWorldMap_instance=nil
                    local p=T.playerNew(); p.sitting=mode=="meditation"
                    assert(C.start(p,mode,false)); T.tick(p,false)
                    local panel
                    local map=T.action(p,kind,function()
                        if kind=="ISReadMapItem" then panel=panels:paper(p:getPlayerNum()) else panel=panels:world(p:getPlayerNum()) end
                    end)
                    ISTimedActionQueue.add(map); T.tick(p,false)
                    assert(C.status(p).active and #p.cards==0 and #p.halos==0)
                    assert(queue(p)[1]==map and p.nativeHead==map.action); untouched(map)
                    map:perform()
                    local count=#p.history
                    for i=1,8 do
                        T.now=T.now+60000
                        T.tick(p,false,2)
                        assert(C.status(p).active and #queue(p)==0 and #p.history==count and #p.cards==0)
                    end
                    -- Raw right-button pan and Escape/close are UI gestures, not
                    -- actual isAiming/attack or world displacement.
                    p.aimInput=true; p.cancelInput=true
                    T.tick(p,false); T.tick(p,false)
                    assert(C.status(p).active and #queue(p)==0 and #p.cards==0)
                    p.aimInput=false; p.cancelInput=false
                    if kind=="ISReadMapItem" then panel.isCollapsed=true else panel.visible=false end
                    for i=1,6 do T.tick(p,false); if C.status(p).phase==mode then break end end
                    assert(C.status(p).active and C.status(p).phase==mode and #p.cards==0 and #p.halos==0)
                    C.stop(p)
                end
            end
        end)
    end)
    test("native modal and lost no-queue actions pause without restart loops or stop cards",function()
        withPanels(function(panels)
            for _,mode in ipairs({"yoga","meditation"}) do
                local p=T.playerNew(); p.sitting=mode=="meditation"
                assert(C.start(p,mode,false)); T.tick(p,false)
                for cycle=1,3 do
                    assert(queue(p)[1])
                    panels.modal=panels:java({visible=true,playerNum=p:getPlayerNum()})
                    ISTimedActionQueue.clear(p) -- foreign UI invalidates training, without queuing a replacement
                    local count=#p.history
                    for i=1,6 do T.tick(p,false); assert(C.status(p).active and #queue(p)==0 and #p.history==count and #p.cards==0) end
                    panels.modal=nil
                    for i=1,6 do T.tick(p,false); if C.status(p).phase==mode then break end end
                    assert(C.status(p).phase==mode and #p.cards==0)
                end
                C.stop(p)
            end
        end)
    end)
    test("a global modal holds both modes and ordinary no-queue losses resume after quiet",function()
        withPanels(function(panels)
            for _,mode in ipairs({"yoga","meditation"}) do
                local p=T.playerNew(); p.sitting=mode=="meditation"
                assert(C.start(p,mode,false)); T.tick(p,false)
                panels.modal=panels:java({visible=true})
                ISTimedActionQueue.clear(p)
                T.tick(p,false); T.tick(p,false)
                assert(C.status(p).active and #queue(p)==0 and #p.cards==0)
                panels.modal=nil
                for i=1,6 do T.tick(p,false); if C.status(p).phase==mode then break end end
                assert(C.status(p).phase==mode)
                ISTimedActionQueue.clear(p)
                T.now=T.now+1; C.update(p)
                assert(C.status(p).active and #queue(p)==0 and #p.cards==0)
                T.now=T.now+700; C.update(p); assert(#queue(p)==0)
                for i=1,6 do T.tick(p,false); if C.status(p).phase==mode then break end end
                assert(C.status(p).phase==mode and #p.cards==0)
                C.stop(p)
            end
        end)
    end)
    test("persistent HUD hidden maps and other players panels do not block local training",function()
        withPanels(function(panels)
            panels.items={panels:java({Type="ISMiniMap",visible=true,playerNum=0}),panels:java({Type="HUD",visible=true})}
            local other=panels:paper(1); panels:world(1)
            local hidden=panels:paper(0); hidden.visible=false
            panels.modal=panels:java({visible=true,playerNum=1})
            local p,owned=began()
            T.tick(p,false); assert(queue(p)[1]==owned and C.status(p).phase=="meditation")
            C.stop(p)
        end)
    end)
    test("map UI does not hide actual aiming attacks or meaningful displacement",function()
        withPanels(function(panels)
            for _,change in ipairs({function(p) p.aiming=true end,function(p) p.attacking=true end,function(p) p.x=p:getX()+2 end}) do
                panels.items={}; ISWorldMap_instance=nil
                local p=began(); panels:world(p:getPlayerNum()); ISTimedActionQueue.clear(p)
                T.tick(p,false); assert(C.status(p).active and #queue(p)==0)
                change(p); C.update(p)
                assert(not C.status(p).active and #p.cards==1 and #queue(p)==0)
            end
        end)
    end)
    test("native-only work yields without creating Lua actions or changing posture",function()
        local p=T.playerNew(); local native={}; p.nativeHead=native
        assert(C.start(p,"meditation",false)); T.tick(p,false); T.tick(p,false)
        assert(C.status(p).active and #queue(p)==0 and p.nativeHead==native and not p.postureEvents)
        p.nativeHead=nil; resumed(p)
    end)
    test("a stale busy flag without Lua or Java action disarms after five observed seconds",function()
        local p=began()
        ISTimedActionQueue.clear(p)
        assert(#queue(p)==0 and p:getCharacterActions():isEmpty())
        function p:hasTimedActions() return true end
        T.now=T.now+1; C.update(p)
        assert(C.status(p).active and C.status(p).phase=="manual" and #p.cards==0)
        T.now=T.now+4999; C.update(p)
        assert(C.status(p).active and #p.cards==0 and #queue(p)==0)
        T.now=T.now+1; C.update(p)
        local st=C.status(p)
        assert(not st.active and st.phase=="stopped" and st.message:find("without a current action",1,true)
            and #p.cards==1 and #queue(p)==0 and p:hasTimedActions())
        for i=1,8 do T.tick(p,false) end
        assert(not C.status(p).active and #p.cards==1 and #queue(p)==0)
    end)
    local function boredomBreak(p)
        p.values.BOREDOM=40
        T.tick(p,false)
        assert(C.status(p).active and C.status(p).phase=="care", "First request a care break from owned meditation")
    end
    local function careTick(p, elapsed)
        T.now=T.now+(elapsed or 1)
        C.update(p)
        return C.status(p)
    end
    test("a bare animation flag after an intentional boredom break cannot leave training armed",function()
        for _,recovers in ipairs({false,true}) do
            local p,owned=began()
            T.add(p.inventory,T.item("Literature",{boredom=-30,data={literatureTitle="CareFixture"}}))
            owned.onStop=function() p.bareCareFlag=true end
            function p:hasTimedActions() return self.bareCareFlag or not self:getCharacterActions():isEmpty() end
            boredomBreak(p)
            assert(owned.stopped and #queue(p)==0 and p:getCharacterActions():isEmpty())
            local status=careTick(p)
            assert(status.active and status.careWaiting and status.message:find("animation",1,true))
            assert(careTick(p,4999).active and #queue(p)==0 and #p.cards==0)
            if recovers then
                p.bareCareFlag=nil
                for _=1,4 do T.tick(p,false); if queue(p)[1] then break end end
                assert(C.status(p).active and not C.status(p).careWaiting and queue(p)[1].Type=="read" and #p.cards==0)
                queue(p)[1]:perform()
                for _=1,3 do T.tick(p,false) end
                assert(C.status(p).active and C.status(p).phase=="meditation")
                C.stop(p)
            else
                status=careTick(p)
                assert(not status.active and status.phase=="stopped" and status.message:find("without a current action",1,true)
                    and #p.cards==1 and #queue(p)==0 and p:hasTimedActions())
                for _=1,10 do T.tick(p,false) end
                assert(not C.status(p).active and #p.cards==1)
                p.bareCareFlag=nil; p.values.BOREDOM=0
                assert(C.start(p,"meditation",false)); T.tick(p,false)
                assert(C.status(p).phase=="meditation")
                C.stop(p)
            end
        end
    end)
    test("a real context menu clearly pauses boredom care and closing it resumes normal reading",function()
        local p,owned=began()
        T.add(p.inventory,T.item("Literature",{boredom=-30,data={literatureTitle="CareFixture"}}))
        p.contextOpen=true
        boredomBreak(p)
        for _=1,3 do
            local status=careTick(p,60000)
            assert(status.active and status.careWaiting and status.message:find("context menu",1,true))
            assert(#queue(p)==0 and #p.cards==0 and owned.stopped)
        end
        p.contextOpen=false; T.tick(p,false)
        assert(C.status(p).phase=="reading" and not C.status(p).careWaiting and queue(p)[1].Type=="read")
        C.stop(p)
    end)
    test("an orphaned owned release is bounded only with no active action or open menu",function()
        for _,condition in ipairs({"orphan","native","foreign","context"}) do
            local p,owned=began()
            T.add(p.inventory,T.item("Literature",{boredom=-30,data={literatureTitle="CareFixture"}}))
            local q=ISTimedActionQueue.getTimedActionQueue(p)
            -- Reproduce the defensive release refusal: owned Lua head remains,
            -- but no matching current pointer or active Java action exists.
            q.current=nil; p.nativeHead=nil
            boredomBreak(p)
            local foreign,native
            if condition=="native" then native={}; p.nativeHead=native
            elseif condition=="foreign" then foreign=T.action(p,"ForeignWorkout"); ISTimedActionQueue.add(foreign)
            elseif condition=="context" then p.contextOpen=true end
            local status=careTick(p)
            assert(status.active and status.careWaiting and #p.cards==0)
            assert(careTick(p,4999).active)
            status=careTick(p)
            assert(queue(p)[1]==owned and not owned.stopped and not owned.cancelled and not owned.forceStopped)
            if condition=="orphan" then
                assert(not status.active and status.phase=="stopped" and status.message:find("could not release",1,true) and #p.cards==1)
                for _=1,3 do T.tick(p,false) end
                assert(#p.cards==1 and queue(p)[1]==owned and not owned.forceStopped)
            else
                assert(status.active and status.careWaiting and #p.cards==0 and p.nativeHead==native)
                assert(careTick(p,60000).active)
                if foreign then untouched(foreign); assert(queue(p)[2]==foreign and not foreign.begins) end
                if native then assert(p:getCharacterActions():contains(native)) end
                p.contextOpen=false
                if native then p.nativeHead=nil end
                -- Let stock retire the stale owned entry. Any genuine successor then begins normally.
                q:onCompleted(owned)
                if foreign then assert(p.nativeHead==foreign.action); untouched(foreign); foreign:perform() end
                p.values.BOREDOM=0
                for _=1,5 do T.tick(p,false); if C.status(p).phase=="meditation" then break end end
                assert(C.status(p).phase=="meditation" and #p.cards==0 and not C.status(p).careWaiting)
                C.stop(p)
            end
        end
    end)
    test("a live Java-only handle after training loss still yields for many minutes",function()
        local p=began()
        ISTimedActionQueue.clear(p)
        local native={}
        p.nativeHead=native
        for i=1,8 do
            T.now=T.now+60000; C.update(p)
            assert(C.status(p).active and C.status(p).phase=="manual" and #p.cards==0
                and #queue(p)==0 and p:getCharacterActions():contains(native))
        end
        p.nativeHead=nil
        resumed(p)
    end)
    test("stock-recognized climb or door state without a Java handle stays cooperative",function()
        local p=began()
        ISTimedActionQueue.clear(p)
        local original=ISTimedActionQueue.isPlayerDoingAction
        local recognized=true
        ISTimedActionQueue.isPlayerDoingAction=function(player)
            return (player==p and recognized) or original(player)
        end
        local ok,reason=pcall(function()
            for i=1,8 do
                T.now=T.now+60000; C.update(p)
                assert(C.status(p).active and C.status(p).phase=="manual"
                    and #p.cards==0 and #queue(p)==0 and p:getCharacterActions():isEmpty())
            end
            recognized=false
            resumed(p)
        end)
        ISTimedActionQueue.isPlayerDoingAction=original
        assert(ok,reason)
    end)
    test("unidentified or mixed native action identity forbids owned-head cancellation",function()
        for _,mixed in ipairs({false,true}) do
            local p,owned=began(); local native={}
            local foreign=T.action(p,"UnknownWorkAction")
            ISTimedActionQueue.add(foreign)
            if mixed then p.nativeAdditional={native} else p.nativeHead=native end
            T.tick(p,false); T.tick(p,false)
            assert(C.status(p).active and queue(p)[1]==owned and queue(p)[2]==foreign)
            assert(not owned.stopped and not owned.cancelled and p:getCharacterActions():contains(native))
            untouched(foreign)
            -- Once only our identified head remains, releasing it is safe again.
            p.nativeHead=owned.action; p.nativeAdditional=nil; T.tick(p,false)
            assert(queue(p)[1]==foreign and p.nativeHead==foreign.action)
            untouched(foreign); foreign:perform(); resumed(p)
        end
    end)
    test("raw aim alone uses 500ms but actual aim and attack stop immediately",function()
        local p,owned=began(); p.aimInput=true; C.update(p)
        T.now=T.now+499; C.update(p)
        assert(C.status(p).active and #p.cards==0 and queue(p)[1]==owned and not owned.stopped)
        T.now=T.now+1; C.update(p)
        assert(not C.status(p).active and #p.cards==1 and C.status(p).message:lower():find("aim",1,true))
        local gesture=began(); gesture.aimInput=true; C.update(gesture)
        T.now=T.now+499; C.update(gesture); gesture.aimInput=false; C.update(gesture)
        T.now=T.now+1000; C.update(gesture); assert(C.status(gesture).active); C.stop(gesture)
        for _,input in ipairs({"aiming","attacking"}) do
            local actual=began(); actual[input]=true; C.update(actual)
            assert(not C.status(actual).active and #actual.cards==1 and #queue(actual)==0)
            C.update(actual); assert(#actual.cards==1,"A terminal input must not produce another HUD")
        end
    end)
    test("between-sample actual aim in a native stop is terminal and explicit rearm is fresh",function()
        local p,owned=began()
        p.aiming=true
        owned:stop()
        p.aiming=false
        T.now=T.now+1; C.update(p)
        local stopped=C.status(p)
        assert(not stopped.active and stopped.phase=="stopped" and stopped.message:lower():find("aim",1,true)
            and #p.cards==1 and #queue(p)==0,"Detect real aim even when it is gone by the next player update")
        T.tick(p,false); assert(not C.status(p).active and #p.cards==1 and #queue(p)==0)
        assert(C.start(p,"meditation",false),"A legitimate explicit rearm has no sticky aim cancellation")
        T.tick(p,false)
        assert(C.status(p).active and queue(p)[1] and queue(p)[1]~=owned and #p.cards==1)
        C.stop(p,"Stopped by you."); C.update(p)
        assert(not C.status(p).active and #p.cards==2 and p.cards[2].note=="Stopped by you.")
    end)
    test("meaningful context popup shields raw aim but actual aim still ends training",function()
        local p,owned=began()
        p.contextOpen=true; p.aimInput=true
        C.update(p); T.now=T.now+800; C.update(p)
        assert(C.status(p).active and #p.cards==0 and queue(p)[1]==owned,"Right-clicking a real popup is not aiming")
        p.aiming=true; C.update(p)
        assert(not C.status(p).active and #p.cards==1 and C.status(p).message:lower():find("aim",1,true))
    end)
    test("visible nonempty single-menu child is meaningful while the native root is hidden",function()
        local p=began()
        local child={options={{name="Inspect"}},visible=true}
        function child:isVisible() return self.visible end
        function child:isReallyVisible() return self.visible end
        local root={options={},instanceMap={child}}
        function root:isVisible() return false end
        function root:isOptionSingleMenu() return true end
        local original=getPlayerContextMenu
        getPlayerContextMenu=function(slot) if slot==p:getPlayerNum() then return root end end
        local ok,reason=pcall(function()
            ISTimedActionQueue.clear(p)
            p.aimInput=true
            for i=1,6 do
                T.now=T.now+60000; C.update(p)
                assert(C.status(p).active and #queue(p)==0 and #p.cards==0)
            end
            child.visible=false; p.aimInput=false
            resumed(p)
        end)
        getPlayerContextMenu=original
        assert(ok,reason)
    end)
    test("empty or hidden context menus cannot stall an unexplained loss",function()
        for _,reason in ipairs({"empty","hidden"}) do
            local p,owned=began()
            p.contextOpen=true
            if reason=="empty" then p.contextOptions={} else p.contextHidden=true end
            ISTimedActionQueue.clear(p)
            T.now=T.now+1; C.update(p)
            assert(C.status(p).active and #queue(p)==0)
            for i=1,8 do T.tick(p,false); if queue(p)[1] then break end end
            assert(C.status(p).active and C.status(p).phase=="meditation" and #p.cards==0
                and queue(p)[1] and queue(p)[1]~=owned,reason)
            C.stop(p)
        end
    end)
    test("four consecutive unexplained training disappearances stop once and do not replay",function()
        local p,owned=began()
        for cycle=1,4 do
            assert(queue(p)[1]==owned)
            ISTimedActionQueue.clear(p)
            T.now=T.now+1; C.update(p)
            if cycle<4 then
                assert(C.status(p).active and #queue(p)==0 and #p.cards==0)
                for i=1,9 do T.tick(p,false); if queue(p)[1] then break end end
                assert(C.status(p).active and C.status(p).phase=="meditation" and queue(p)[1]~=owned)
                owned=queue(p)[1]
            end
        end
        local status=C.status(p)
        assert(not status.active and status.phase=="stopped" and status.message:lower():find("interrupt",1,true)
            and #p.cards==1 and #queue(p)==0,"Do not loop forever after unidentified native action cancellations")
        for i=1,8 do T.tick(p,false) end
        assert(not C.status(p).active and #queue(p)==0 and #p.cards==1)
    end)
    test("concrete owned stop callback appends foreign work without hiding or replacing the live queue",function()
        local p,owned=began()
        local first=T.action(p,"AlreadyQueuedForeign")
        local added=T.action(p,"CallbackAddedForeign")
        ISTimedActionQueue.add(first)
        local timed=ISTimedActionQueue.getTimedActionQueue(p)
        local originalQueue=timed.queue
        local originalReset,originalClear=timed.resetQueue,timed.clearQueue
        owned.onStop=function()
            assert(timed.queue==originalQueue and timed.queue[2]==first,
                "Concrete callback must see the real existing waiters")
            ISTimedActionQueue.add(added)
            assert(timed.queue[3]==added and not added.begins)
        end
        T.tick(p,false)
        assert(timed.queue==originalQueue and #queue(p)==2 and queue(p)[1]==first and queue(p)[2]==added)
        assert(timed.resetQueue==originalReset and timed.clearQueue==originalClear)
        assert(p.nativeHead==first.action and first.begins==1 and not added.begins)
        untouched(first); untouched(added)
        first:perform(); T.tick(p,false)
        assert(queue(p)[1]==added and p.nativeHead==added.action and added.begins==1)
        untouched(added); added:perform(); resumed(p)
    end)
    test("post-clear native-only work defers the preserved foreign tail until truly drained",function()
        local p,owned=began(); local foreign=T.action(p,"UnknownFollowup")
        ISTimedActionQueue.add(foreign)
        local native={}; local original=ISTimedActionQueue.clear
        ISTimedActionQueue.clear=function(player)
            original(player)
            if player==p then player.nativeHead=native end
        end
        local ok,reason=pcall(function()
            T.tick(p,false)
            assert(owned.stopped or owned.cancelled)
            assert(C.status(p).active and p.nativeHead==native and not foreign.begins)
            untouched(foreign)
            T.tick(p,false); T.tick(p,false)
            assert(p.nativeHead==native and not foreign.begins)
            untouched(foreign)
            p.nativeHead=nil
            T.tick(p,false)
            assert(queue(p)[1]==foreign and p.nativeHead==foreign.action and foreign.begins==1)
            untouched(foreign); T.tick(p,false); assert(foreign.begins==1)
        end)
        ISTimedActionQueue.clear=original
        assert(ok,reason)
        foreign:perform(); resumed(p)
    end)
    test("yielding a natural stand-and-scout batch removes only unstarted owned tails",function()
        local p=T.playerNew(); p.sitting=true; p.values.BOREDOM=40
        local shelf=T.container(6,0); p.available={shelf}
        scoutTarget({square=shelf.square,key="stand-scout",unknown=true,container=shelf})
        assert(C.start(p,"meditation",false)); T.tick(p,false)
        local stand,walk=queue(p)[1],queue(p)[2]
        assert(stand and stand.Type=="stand" and stand:isStarted())
        assert(walk and walk.Type=="ISWalkToTimedAction" and not walk:isStarted())
        local first=T.action(p,"UnknownFirst"); local second=T.action(p,"UnknownSecond")
        ISTimedActionQueue.add(first); ISTimedActionQueue.add(second); T.tick(p,false)
        assert(stand.stopped and walk.cancelled and not walk.begins and walk.removes==1)
        assert(#queue(p)==2 and queue(p)[1]==first and queue(p)[2]==second and p.nativeHead==first.action)
        untouched(first); untouched(second)
        C.stop(p); first:perform(); second:perform(); scoutTarget(nil)
    end)
    test("Stop waits out mismatched native ownership then clears stale work without rearming",function()
        local p,owned=began(); local native={}; p.nativeHead=native
        local foreign=T.action(p,"UnknownFollowup"); ISTimedActionQueue.add(foreign)
        C.stop(p,"Stopped by you.")
        assert(not C.status(p).active and #p.cards==1 and p.nativeHead==native)
        assert(not owned.stopped and queue(p)[1]==owned and queue(p)[2]==foreign)
        T.tick(p,false); T.tick(p,false)
        assert(p.nativeHead==native and not owned.stopped and not foreign.begins)
        local started=C.start(p,"meditation",false)
        assert(not started and not C.status(p).active and p.nativeHead==native)
        p.nativeHead=nil; T.tick(p,false)
        assert(owned.removes==1 and queue(p)[1]==foreign and p.nativeHead==foreign.action)
        untouched(foreign); foreign:perform(); T.tick(p,false); T.tick(p,false)
        assert(not C.status(p).active and #p.cards==1 and #queue(p)==0 and not p.nativeHead)
    end)
    test("busy start arms without touching posture or already running foreign work",function()
        for _,seated in ipairs({false,true}) do
            local p=T.playerNew(); p.sitting=seated
            local foreign=T.action(p,"ISFitnessAction"); ISTimedActionQueue.add(foreign)
            assert(C.start(p,"meditation",false)); T.tick(p,false)
            assert(C.status(p).active and #queue(p)==1 and queue(p)[1]==foreign)
            assert(p.sitting==seated and not p.postureEvents)
            untouched(foreign); foreign:perform(); resumed(p)
        end
    end)
    test("chair training uses native get-up before floor meditation",function()
        local p=T.playerNew(); p.furniture=true
        assert(C.start(p,"meditation",false)); T.tick(p,false)
        assert(queue(p)[1] and queue(p)[1].Type=="stand" and p.furniture and not p.postureEvents)
        queue(p)[1]:perform()
        for i=1,5 do T.tick(p,false); if C.status(p).phase=="meditation" then break end end
        assert(not p.furniture and p.sitting and C.status(p).phase=="meditation")
        C.stop(p)
    end)
    test("quiet dwell is continuous and cannot preempt a just-appended action",function()
        local p=began(); local first=T.action(p,"ISFitnessAction")
        ISTimedActionQueue.add(first); T.tick(p,false); first:perform()
        T.now=T.now+1; C.update(p)
        assert(C.status(p).active and #queue(p)==0)
        T.now=T.now+700; C.update(p); assert(#queue(p)==0)
        local second=T.action(p,"UnknownFollowup"); ISTimedActionQueue.add(second)
        T.now=T.now+100; C.update(p); untouched(second); assert(queue(p)[1]==second)
        second:perform(); T.now=T.now+1; C.update(p)
        T.now=T.now+700; C.update(p); assert(#queue(p)==0)
        resumed(p)
    end)
    test("normal completed training leaves a fairness window for queued work",function()
        local p,owned=began(); owned:perform()
        T.now=T.now+1; C.update(p)
        assert(C.status(p).active and #queue(p)==0)
        T.now=T.now+400; C.update(p); assert(#queue(p)==0)
        local foreign=T.action(p,"UnknownWorkAction"); ISTimedActionQueue.add(foreign)
        T.now=T.now+200; C.update(p)
        assert(queue(p)[1]==foreign and #queue(p)==1); untouched(foreign)
        foreign:perform(); resumed(p)
    end)
    test("observed ordinary walking reanchors without disturbing foreign work",function()
        local p=began(); local foreign=T.action(p,"ISFitnessAction")
        ISTimedActionQueue.add(foreign); T.tick(p,false)
        for i=1,6 do p.x=p:getX()+.4; p.moving=true; p.movementInput=true; T.tick(p,false); assert(C.status(p).active) end
        untouched(foreign)
        p.moving=false; p.movementInput=false; foreign:perform(); resumed(p)
    end)
    test("error hard stop leaves foreign work alone and resets on explicit restart",function()
        local p=began(); local foreign=T.action(p,"ISFitnessAction")
        ISTimedActionQueue.add(foreign); T.tick(p,false)
        local update=C.update; C.update=function() error("cooperative fixture fault") end
        Events.OnPlayerUpdate.callback(p); C.update=update
        assert(not C.status(p).active and #p.cards==1); untouched(foreign)
        foreign:perform(); T.tick(p,false); assert(not C.status(p).active)
        assert(C.start(p,"meditation",false)); resumed(p)
    end)
    test("arbitrary timed actions yield in exact identity order without a type allowlist",function()
        for _,kind in ipairs({"ISEatFoodAction","ISDrinkFluidAction","ISFitnessAction","SomeOtherModAction"}) do
            local p,owned=began()
            local first=T.action(p,kind); local second=T.action(p,"UnknownFollowup")
            ISTimedActionQueue.add(first); ISTimedActionQueue.add(second)
            T.tick(p,false)
            assert(C.status(p).active and #p.cards==0)
            assert(#queue(p)==2 and queue(p)[1]==first and queue(p)[2]==second)
            assert(p.nativeHead==first.action and ISTimedActionQueue.getTimedActionQueue(p).current==first)
            untouched(first); untouched(second)
            assert(owned.stopped or owned.cancelled)
            first:perform(); T.tick(p,false)
            assert(queue(p)[1]==second and C.status(p).active); untouched(second)
            second:perform(); resumed(p)
        end
    end)
    test("a foreign completion chain stays foreign until its final action finishes",function()
        local p=began()
        local follow=T.action(p,"ISDrinkFluidAction")
        local first=T.action(p,"ISEatFoodAction",function() ISTimedActionQueue.add(follow) end)
        ISTimedActionQueue.add(first); T.tick(p,false); untouched(first)
        first:perform(); T.tick(p,false)
        assert(C.status(p).active and #queue(p)==1 and queue(p)[1]==follow)
        untouched(follow); follow:perform(); resumed(p)
    end)
    test("native next-action start cannot donate a foreign chain to owned perform wrapping",function()
        local p,owned=began()
        local follow=T.action(p,"UnknownWorkContinuation")
        local foreign=T.action(p,"ISFitnessAction")
        function foreign:start() self.started=true; ISTimedActionQueue.add(follow) end
        -- The fixture's native-style onCompleted begins the next action inside
        -- the owned perform callback, but never executes its perform eagerly.
        ISTimedActionQueue.add(foreign); owned:perform(); T.tick(p,false)
        assert(foreign.started and #queue(p)==2 and queue(p)[1]==foreign and queue(p)[2]==follow)
        untouched(foreign); untouched(follow)
        foreign:perform(); follow:perform(); resumed(p)
    end)
    test("a long external workout does not consume the no-XP timeout budget",function()
        local p=began(); local workout=T.action(p,"ISFitnessAction")
        ISTimedActionQueue.add(workout); T.tick(p,false)
        for i=1,10 do
            T.now=T.now+60000; T.tick(p,false,1)
            untouched(workout)
            assert(C.status(p).active and C.status(p).phase=="manual" and #p.cards==0)
        end
        workout:perform()
        T.tick(p,false); T.tick(p,false); T.tick(p,false)
        assert(C.status(p).active and C.status(p).phase=="meditation", "External hours cannot trip the six-hour training watchdog")
        T.tick(p,false,.1); assert(C.status(p).active); C.stop(p)
    end)
    test("tiny movement and animation drift do not stop a stationary cooperative session",function()
        local p=began(); local foreign=T.action(p,"ISFitnessAction")
        ISTimedActionQueue.add(foreign); T.tick(p,false)
        p.x=p:getX()+.05; p.y=p:getY()+.05; p.moving=true; p.movementInput=true
        T.tick(p,false); assert(C.status(p).active); untouched(foreign)
        p.moving=false; p.movementInput=false; foreign:perform(); resumed(p)
    end)
    test("significant displacement floor changes jogging and danger end a yielded session",function()
        for _,change in ipairs({
            function(p) p.x=p:getX()+3 end,
            function(p) p.square=T.square(0,0,1) end,
            function(p) p.running=true; p.rawMovementInput=true end,
            function(p) p.sprinting=true; p.rawMovementInput=true end,
            function(p) p.zombies=1 end,
            function(p) p.aimInput=true end,
            function(p) p.attacking=true end,
            function(p) p.cancelInput=true end,
        }) do
            local p=began(); local foreign=T.action(p,"ISFitnessAction")
            ISTimedActionQueue.add(foreign); T.tick(p,false); change(p)
            T.tick(p,false); T.tick(p,false)
            assert(not C.status(p).active and #p.cards==1, "Hard stops remain effective while yielding")
            untouched(foreign); foreign:perform(); T.tick(p,false)
            assert(not C.status(p).active and #queue(p)==0, "Finishing foreign work never revives a stopped session")
        end
    end)
    test("explicit Stop preserves all queued foreign actions and forbids automatic restart",function()
        local p=began(); local first=T.action(p,"ISEatFoodAction"); local second=T.action(p,"ISFitnessAction")
        ISTimedActionQueue.add(first); ISTimedActionQueue.add(second); T.tick(p,false)
        C.stop(p,"Stopped by you.")
        assert(not C.status(p).active and queue(p)[1]==first and queue(p)[2]==second)
        untouched(first); untouched(second); first:perform(); second:perform(); T.tick(p,false)
        assert(not C.status(p).active and #queue(p)==0 and #p.cards==1)
        assert(C.start(p,"meditation",false)); T.tick(p,false)
        assert(C.status(p).active and C.status(p).phase=="meditation", "Explicit restart starts clean, without stale yield state")
        C.stop(p)
    end)
    test("external action satisfying a care need replans without redundant borrowing",function()
        local p=T.playerNew(); p.sitting=true; p.values.BOREDOM=40
        local book=T.add(p.inventory,T.item("Literature"))
        assert(C.start(p,"meditation",false)); T.tick(p,false)
        local foreign=T.action(p,"SomeOtherReadingAction",function() p.values.BOREDOM=0 end)
        ISTimedActionQueue.add(foreign); T.tick(p,false); untouched(foreign)
        foreign:perform(); resumed(p)
        assert(p.inventory:contains(book) and not p.data.AutoMindfulReadHistory,
            "Interrupted owned reading is not falsely marked complete or consumed again")
    end)
    test("manual replacement can is not attributed to an interrupted borrowed food loan",function()
        local p=T.playerNew(); p.sitting=true; p.values.HUNGER=.5
        local shelf=T.container(1,0)
        local food=T.add(shelf,T.item("Food",{replace="Base.EmptyTinCan"})); p.nearby={shelf}
        assert(C.start(p,"meditation",true))
        for i=1,6 do
            T.tick(p,false)
            if queue(p)[1] and queue(p)[1].Type=="eat" then break end
            if queue(p)[1] then queue(p)[1]:perform() end
        end
        assert(queue(p)[1] and queue(p)[1].Type=="eat" and p.inventory:contains(food))
        local supplied=T.item("InventoryItem",{fullType="Base.EmptyTinCan"})
        local foreign=T.action(p,"SomeOtherConsumption",function()
            T.remove(p.inventory,food); T.add(p.inventory,supplied); p.values.HUNGER=.05
        end)
        ISTimedActionQueue.add(foreign); T.tick(p,false); untouched(foreign)
        assert(p.nativeHead==foreign.action)
        foreign:perform()
        for i=1,12 do T.tick(p,false); if queue(p)[1] and queue(p)[1].Type~="Meditation" then queue(p)[1]:perform() end end
        assert(C.status(p).active and p.inventory:contains(supplied) and not shelf:contains(supplied),
            "Same-type appearance after a foreign action is not proof of a borrowed item's replacement")
        C.stop(p)
    end)
    test("interrupted carrying and homebound trips resolve the current permitted origin before walking",function()
        local oldCell,oldSafe,oldClient=getCell,SafeHouse,T.client
        local ok,reason=pcall(function()
            for _,stage in ipairs({"carrying","homebound"}) do
                for _,access in ipairs({"loaded","unloaded","wrong-floor","denied"}) do
                    local p=T.playerNew(); p.values.BOREDOM=40
                    local origin=p:getSquare(); local shelf=T.container(6,0)
                    local book=T.add(shelf,T.item("Literature")); p.available={shelf}
                    scoutTarget({square=shelf.square,key="interrupted-trip",unknown=true,container=shelf})
                    assert(C.start(p,"meditation",false))
                    local interrupted
                    for i=1,25 do
                        T.tick(p,false)
                        local head=queue(p)[1]
                        if head and ((stage=="carrying" and head.Type=="read") or
                            (stage=="homebound" and head.Type=="ISWalkToTimedAction" and T.hasHistory(p,"read"))) then
                            interrupted=head; break
                        end
                        if head then head:perform() end
                    end
                    assert(interrupted and p:getSquare()~=origin)
                    if stage=="carrying" then assert(p.inventory:contains(book)) else assert(shelf:contains(book)) end
                    -- Simulate a partially completed book and an ordinary action
                    -- finishing the care need; the interrupted action stays stopped.
                    p.values.BOREDOM=10
                    local foreign=T.action(p,"UnknownLocalWork",function() p.values.BOREDOM=0 end)
                    ISTimedActionQueue.add(foreign); T.tick(p,false); untouched(foreign)
                    assert(interrupted.stopped or interrupted.cancelled)
                    local refreshed=T.square(origin:getX(),origin:getY(),access=="wrong-floor" and 1 or origin:getZ())
                    local resolved=0
                    getCell=function() return {getGridSquare=function(_,x,y,z)
                        assert(x==origin:getX() and y==origin:getY() and z==origin:getZ())
                        resolved=resolved+1
                        if access~="unloaded" then return refreshed end
                    end} end
                    T.client=true
                    SafeHouse={isSafehouseAllowInteract=function(square) return access~="denied" or square~=refreshed end,
                        isSafehouseAllowLoot=function(square) return access~="denied" or square~=refreshed end}
                    foreign:perform()
                    local freshWalk=false
                    for i=1,20 do
                        T.tick(p,false)
                        local head=queue(p)[1]
                        if head and head.Type=="ISWalkToTimedAction" then
                            freshWalk=true
                            assert(access=="loaded", "Unloaded, wrong-floor or forbidden origin must not queue a return")
                        end
                        if not C.status(p).active or C.status(p).phase=="meditation" then break end
                        if head then head:perform() end
                    end
                    assert(resolved>0, "Interrupted trip must resolve origin coordinates instead of reusing a stale square")
                    if access=="loaded" then
                        assert(freshWalk and p:getSquare()==refreshed and C.status(p).phase=="meditation")
                        assert(shelf:contains(book) and C.status(p).pendingReturns==0)
                    else
                        assert(not freshWalk and not C.status(p).active and #queue(p)==0)
                    end
                    C.stop(p); scoutTarget(nil); T.client=oldClient
                    getCell,SafeHouse=oldCell,oldSafe
                end
            end
        end)
        getCell,SafeHouse,T.client=oldCell,oldSafe,oldClient
        scoutTarget(nil)
        assert(ok,reason)
    end)
    test("yielding during an outbound scout discards its stale route and replans current needs",function()
        local p=T.playerNew(); p.values.BOREDOM=40
        local origin=p:getSquare(); local shelf=T.container(6,0); T.add(shelf,T.item("Literature")); p.available={shelf}
        scoutTarget({square=shelf.square,key="cooperative-book",unknown=true,container=shelf})
        assert(C.start(p,"meditation",false)); T.tick(p,false)
        local oldWalk=queue(p)[1]
        local foreign=T.action(p,"ISEatFoodAction",function() p.values.BOREDOM=0 end)
        ISTimedActionQueue.add(foreign); T.tick(p,false); untouched(foreign)
        assert(oldWalk.stopped or oldWalk.cancelled)
        foreign:perform(); resumed(p)
        assert(p:getSquare()==origin and #shelf.items==1, "Cleared need must not resume the old outbound trip")
        scoutTarget(nil)
    end)
end
