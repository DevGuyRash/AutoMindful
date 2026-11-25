-- Controller-level model: actual game state, Lua/Java actions and the clock are doubled.
return function(T, C, test)
    local function queue(p) return ISTimedActionQueue.getTimedActionQueue(p).queue end
    local function step(p, ms) T.now=T.now+(ms or 250); C.update(p) end
    local function await(p, kind)
        for _=1,40 do
            step(p)
            local head=queue(p)[1]
            if head then
                if head.Type==kind then return head end
                assert(head.Type=="stand", "Unexpected action: "..tostring(head.Type).." instead of "..kind)
                head:perform()
            end
            assert(C.status(p).active,"Session ended: "..tostring(C.status(p).message))
        end
        error("Did not resume "..kind)
    end
    local cases={{"meditation","Meditation"},{"yoga","Yoga"},{"both","Meditation"},{"both","Yoga"}}
    local function start(mode,kind)
        local p=T.playerNew()
        p.sitting=kind=="Meditation"
        p.values.BOREDOM=kind=="Yoga" and 10 or 0
        assert(C.start(p,mode,true))
        return p
    end
    for _,v in ipairs(cases) do
        test(v[1].."/"..v[2]..": canceled leg is retried only after quiet; selected mode and spot survive",function()
            local mode,kind=v[1],v[2]
            local p=start(mode,kind); local old=await(p,kind); local spot=p:getSquare()
            old:stop() -- no Cancel key or other hard stop
            p.values.BOREDOM=kind=="Meditation" and 10 or 0 -- would otherwise flip a Both-mode planner
            step(p,1); step(p,1); step(p,749)
            assert(not queue(p)[1] and C.status(p).active and #p.cards==0)
            local fresh=await(p,kind)
            assert(fresh~=old and old.stopped and fresh.begins==1)
            assert(C.status(p).mode==mode and C.status(p).collectNearby and p:getSquare()==spot and #p.cards==0)
            C.stop(p)
        end)
    end

    local function withAdmission(kind, filter, fn)
        local option=ZenWellnessContextMenu.Options[kind]
        local original=option.onAction; local attempts=0
        option.onAction=function(a,b,p)
            attempts=attempts+1
            if filter(attempts,p) then return original(a,b,p) end
        end
        local ok,err=pcall(fn,function() return attempts end)
        option.onAction=original
        assert(ok,err)
    end
    for _,v in ipairs(cases) do
        test(v[1].."/"..v[2]..": one silent admission retries the same admissible step, never another session",function()
            local mode,kind=v[1],v[2]
            withAdmission(kind,function(n) return n>1 end,function(count)
                local p=start(mode,kind); step(p)
                assert(count()==1 and C.status(p).active and not queue(p)[1] and #p.cards==0)
                p.values.BOREDOM=kind=="Meditation" and 10 or 0
                step(p,1); step(p,1); step(p,749)
                assert(count()==1 and not queue(p)[1])
                local head=await(p,kind)
                assert(count()==2 and head.begins==1 and C.status(p).mode==mode and #p.cards==0)
                C.stop(p)
            end)
        end)
    end
    test("silent admissions and dropped actions share one finite backoff; an unrelated UI does not reset failures",function()
        withAdmission("Meditation",function(n) return n%2==0 end,function(count)
            local p=start("both","Meditation"); step(p,1)
            for loss=1,4 do
                local q=queue(p)
                assert(count()==loss)
                if loss%2==0 then assert(q[1]); q[1]:stop() end
                step(p,1)
                if loss<4 then
                    if loss==2 then
                        -- A map is legitimate work, not evidence the interrupted training progressed.
                        local map=T.action(p,"ISReadMapItem")
                        ISTimedActionQueue.add(map); step(p,1)
                        assert(queue(p)[1]==map and not map.stopped and not map.cancelled)
                        map:perform()
                    end
                    step(p,1); step(p,750*2^(loss-1)-1)
                    assert(count()==loss and not queue(p)[1],"Shortened retry "..loss)
                    step(p,1)
                end
            end
            for _=1,6 do step(p,9000) end
            assert(count()==4 and not C.status(p).active and #p.cards==1 and not queue(p)[1])
        end)
    end)
    test("a full native completion replenishes the retry budget and Both alternates after it, not after a cancellation",function()
        local p=start("both","Meditation"); local med=await(p,"Meditation")
        for i=1,3 do med:stop(); med=await(p,"Meditation") end
        local foreign=T.action(p,"OtherPlayersQueuedWork")
        ISTimedActionQueue.add(foreign); med:perform() -- foreign becomes current before the controller observes completion
        p.values.BOREDOM=0
        step(p); assert(queue(p)[1]==foreign and not foreign.stopped and not foreign.cancelled)
        foreign:perform()
        local yoga=await(p,"Yoga"); yoga:stop(); await(p,"Yoga")
        assert(C.status(p).mode=="both" and #p.cards==0)
        C.stop(p)
    end)
    test("preparing gear without queuing practice never credits or advances the missing Both leg",function()
        local p=start("both","Meditation")
        local option=ZenWellnessContextMenu.Options.Meditation
        local original=option.onAction
        option.onAction=function() ISTimedActionQueue.add(T.action(p,"ISUnequipAction")) end
        step(p); option.onAction=original
        local prep=queue(p)[1]; assert(prep and prep.Type=="ISUnequipAction"); prep:perform()
        p.values.BOREDOM=10 -- a fresh Both planner would choose Yoga
        local fresh=await(p,"Meditation")
        assert(fresh~=prep and C.status(p).mode=="both" and #p.cards==0)
        C.stop(p)
    end)
    test("an explicit Stop during a synchronous upstream admission remains terminal",function()
        local p=start("both","Meditation")
        withAdmission("Meditation",function() C.stop(p,"Stopped by you."); return false end,function(count)
            step(p); for _=1,10 do step(p,3500) end
            assert(not C.status(p).active and C.status(p).phase=="stopped" and C.status(p).message=="Stopped by you.")
            assert(count()==1 and #p.cards==1 and not queue(p)[1])
        end)
    end)
    test("a pending retry honors explicit Stop, death, danger, disability and completion without rearming",function()
        for _,control in ipairs({"stop","death","danger","disable","goal"}) do
            local p=start("both","Meditation"); await(p,"Meditation"):stop()
            step(p,1); assert(C.status(p).active and #p.cards==0)
            local option=ZenWellnessContextMenu.Options.Meditation
            if control=="stop" then C.stop(p,"Stopped by you.")
            elseif control=="death" then p.dead=true; Events.OnPlayerDeath.callback(p)
            elseif control=="danger" then p.zombies=1
            elseif control=="disable" then ZenWellnessContextMenu.Options.Meditation=nil
            else p.meditation=10; p.yoga[1]=10 end
            for _=1,8 do step(p,3000) end
            ZenWellnessContextMenu.Options.Meditation=option
            p.zombies=nil; p.dead=nil
            for _=1,8 do step(p,3000) end
            local s=C.status(p)
            if control=="goal" then assert(s.active and s.mode=="recovery",control)
            else assert(not s.active and s.phase=="stopped",control) end
            assert(not queue(p)[1] and #p.cards==1,control)
        end
    end)
    test("a canceled Both leg neither repeats a consumed portion nor loses a pending exact-origin loan",function()
        local p=T.playerNew(); p.sitting=true; p.values.THIRST=.25
        local origin=p:getSquare(); local shelf=T.container(1,0); local bottle=T.add(shelf,T.water())
        p.nearby={shelf}; assert(C.start(p,"both",true))
        local drink
        for _=1,12 do
            step(p)
            local head=queue(p)[1]
            if head and head.Type=="drink" then drink=head; break end
            if head then head:perform() end
        end
        assert(drink and p.inventory:contains(bottle) and C.status(p).pendingReturns==1)
        shelf.reject=true -- formal return unavailable, still the same original box
        drink:perform()
        local amount=bottle.fluid:getAmount(); assert(amount>0 and amount<1)
        local med=await(p,"Meditation"); med:stop(); p.values.BOREDOM=10
        local fresh=await(p,"Meditation")
        assert(fresh~=med and p.inventory:contains(bottle) and C.status(p).pendingReturns==1 and p:getSquare()==origin)
        fresh:stop(); C.stop(p,"Stopped by you."); shelf.reject=false
        for _=1,12 do T.tick(p) end
        local drinks=0; for _,kind in ipairs(p.history) do if kind=="drink" then drinks=drinks+1 end end
        assert(drinks==1 and bottle.fluid:getAmount()==amount and shelf:contains(bottle))
        local status=C.status(p)
        assert(not status.active and status.phase=="stopped" and status.pendingReturns==0 and not queue(p)[1] and #p.cards==1)
    end)
    test("a goal reached on the last missing action completes, rather than consuming the retry budget",function()
        local p=start("both","Meditation"); local head=await(p,"Meditation")
        for _=1,3 do head:stop(); head=await(p,"Meditation") end
        p.meditation=10; p.yoga[1]=10; head:stop()
        for _=1,8 do step(p,1000) end
        assert(C.status(p).active and C.status(p).mode=="recovery" and #p.cards==1 and not queue(p)[1])
    end)
    test("a retry re-admits current Lifestyle requirements and does not repeat an ineligible or capped leg",function()
        local p=start("both","Meditation"); await(p,"Meditation"):stop()
        p.values.BOREDOM=40
        await(p,"Yoga"); assert(C.status(p).mode=="both")
        C.stop(p)
        p=start("both","Yoga"); await(p,"Yoga"):stop()
        p.yoga[1]=10; await(p,"Meditation"); C.stop(p)
        p=start("yoga","Yoga"); await(p,"Yoga"):stop()
        p.yogaBlocked=getText("Tooltip_Yoga_MissingMat")
        for _=1,12 do step(p) end
        assert(not C.status(p).active and C.status(p).message==p.yogaBlocked and not queue(p)[1])
    end)
end
