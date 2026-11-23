-- Controller scheduling with explicit native queue, clock, and Lifestyle doubles.
AutoMindfulContractHarnessOnly = true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly = nil
local T, C = AutoMindfulTest, AutoMindfulTest.controller

local function queue(p)
    return ISTimedActionQueue.getTimedActionQueue(p).queue
end

local function step(p)
    T.now = T.now + 250
    C.update(p)
end

local function await(p, kind, pending)
    for _ = 1, 32 do
        step(p)
        local head = queue(p)[1]
        assert(C.status(p).active, C.status(p).message)
        if head and head.Type == kind then return head end
        if head and head ~= pending then
            assert(head.Type == "stand", "Expected " .. kind .. ", found " .. tostring(head.Type))
            head:perform()
        end
    end
    error("Did not admit " .. kind .. ": " .. C.status(p).message)
end

for _, kind in ipairs({"Meditation", "Yoga"}) do
    local option = ZenWellnessContextMenu.Options[kind]
    local onAction = option.onAction
    function option.onAction(world, self, p)
        assert(not queue(p)[1] and not p.nativeHead, "Lifestyle's native clear must never reach foreign work")
        assert(p:isSitOnGround() == (kind == "Meditation"), "Native posture gate")
        assert(not self.canPerform(p), "Cannot dispatch while the current Lifestyle gate is closed")
        ISTimedActionQueue.clear(p)
        return onAction(world, self, p)
    end
end

local function count(p, kind)
    local n = 0
    for _, seen in ipairs(p.history) do if seen == kind then n = n + 1 end end
    return n
end

local function clearBoredom(p)
    p.values.BOREDOM = 0
end

local function startWithYogaBlocked(limit, meditationLevel)
    local p = T.playerNew()
    local level = meditationLevel or 5
    p.sitting, p.meditation, p.xp, p.yoga = true, level, level * 100 + 10, {3, 90, 750}
    p.values.ENDURANCE, p.nativeYogaLimit = .24, limit or .60
    assert(C.start(p, "both", false))
    return p, await(p, "Meditation")
end

local function finishMeditationForYogaTurn(p, meditation)
    local xp = p.xp
    meditation:perform()
    clearBoredom(p)
    assert(p.xp > xp, "Fixture must give an observed native Meditation completion")
    assert(p.yoga[1] == 3 and p.yoga[2] == 90 and count(p, "Yoga") == 0)
end

local function assertUntouchedFitness(p, action, native)
    assert(queue(p)[1] == action and p.nativeHead == native)
    assert(action.begins == 1 and not action.stopped and not action.cancelled and not action.forceStopped)
    assert(not action.autoMindfulOwner, "The workout must never become AutoMindful-owned")
end

-- Reproduce the live handoff: finished practice, a foreign set starts on the
-- same queue boundary, then hands a seated survivor back at 24% endurance.
do
    local p, first = startWithYogaBlocked()
    local origin = p:getSquare()
    local sets = 0
    local workout = T.action(p, "ISFitnessAction", function()
        sets = sets + 1
        p.values.ENDURANCE, p.sitting = .24, true
    end)
    function workout:start() p.sitting = false end
    ISTimedActionQueue.add(workout)
    finishMeditationForYogaTurn(p, first)
    local native = workout.action
    p.values.ENDURANCE = .90
    for _ = 1, 5 do
        step(p)
        assertUntouchedFitness(p, workout, native)
        assert(count(p, "Yoga") == 0 and C.status(p).active)
    end
    workout:perform()
    local interim = await(p, "Meditation")
    assert(interim ~= first and sets == 1 and p.values.ENDURANCE == .24)

    -- A normal Meditation stat tick can grant XP without ending its action.
    p.xp = p.xp + 2
    local tickXP = p.xp
    p.values.ENDURANCE = .60
    for _ = 1, 5 do
        step(p)
        assert(queue(p)[1] == interim and not interim.stopped and count(p, "Yoga") == 0)
    end
    p.values.ENDURANCE = .65
    local yoga = await(p, "Yoga", interim)
    assert(interim.stopped and p.xp == tickXP, "Release only owned interim Meditation; never force its XP award")
    assert(sets == 1 and not workout.stopped and not workout.cancelled and workout.begins == 1)
    assert(count(p, "Yoga") == 1 and yoga.begins == 1 and p.nativeHead == yoga.action)
    assert(C.status(p).mode == "both" and p:getSquare() == origin and #p.cards == 0)
    yoga:perform()
    assert(p.yoga[1] == 4, "Completion requires the fixture's native Yoga action, not the scheduler")
    await(p, "Meditation")
    C.stop(p)
    print("PASS fitness relinquishes at 24%, interim Meditation earns a tick, and Yoga starts at 65%")
end

-- If urgent care and Yoga become available at the same instant, care wins;
-- taking a drink must not silently pay Yoga's owed turn.
do
    local p, first = startWithYogaBlocked()
    local water = T.add(p.inventory, T.water())
    finishMeditationForYogaTurn(p, first)
    local interim = await(p, "Meditation")
    p.values.ENDURANCE, p.values.THIRST, p.thirstMoodle = .70, .30, 4
    local drink = await(p, "drink", interim)
    assert(interim.stopped and count(p, "Yoga") == 0 and count(p, "drink") == 1)
    step(p)
    assert(queue(p)[1] == drink and not drink.stopped, "Ready Yoga must not interrupt an admitted drink")
    drink:perform()
    p.thirstMoodle = 0
    await(p, "Yoga")
    assert(p.values.THIRST < .30 and p.inventory:contains(water) and count(p, "drink") == 1)
    assert(count(p, "Yoga") == 1 and #p.cards == 0)
    C.stop(p)
    print("PASS urgent care interrupts intermittent Meditation without consuming the owed Yoga turn")
end

-- The server-selected gate can close again during a posture action.
-- A preparation queued while eligible is not permission to start Yoga later.
do
    local p, first = startWithYogaBlocked(.80)
    finishMeditationForYogaTurn(p, first)
    local interim = await(p, "Meditation")
    p.values.ENDURANCE = .61
    step(p); step(p)
    assert(queue(p)[1] == interim and not interim.stopped)
    p.values.ENDURANCE, p.nativeYogaLimit = .70, .60
    local stand = await(p, "stand", interim)
    p.nativeYogaLimit = .80
    stand:perform()
    for _ = 1, 6 do
        step(p)
        local head = queue(p)[1]
        assert(C.status(p).active and count(p, "Yoga") == 0)
        assert(not head or (head.Type == "Meditation" and head ~= interim),
            "A reclosed gate may safely wait or meditate, not continue standing or dispatch Yoga")
    end
    local fallback = queue(p)[1]
    p.nativeYogaLimit = .60
    await(p, "Yoga", fallback)
    assert(count(p, "Yoga") == 1 and #p.cards == 0)
    C.stop(p)
    print("PASS server-controlled Yoga gate is honored again after preparation and remains owed")
end

-- An explicit stop cancels only the owned session even though Yoga is due and
-- the queue holds someone else's fresh workout.
do
    local p, first = startWithYogaBlocked()
    finishMeditationForYogaTurn(p, first)
    local interim = await(p, "Meditation")
    local workout = T.action(p, "ISFitnessAction")
    ISTimedActionQueue.add(workout)
    p.values.ENDURANCE = .90
    C.stop(p, "Stopped by you.")
    local native = workout.action
    for _ = 1, 6 do step(p) end
    assert(interim.stopped and not C.status(p).active and #p.cards == 1)
    assert(C.status(p).phase == "stopped" and count(p, "Yoga") == 0)
    assertUntouchedFitness(p, workout, native)
    workout:perform()
    for _ = 1, 6 do step(p) end
    assert(not queue(p)[1] and not C.status(p).active and #p.cards == 1)
    print("PASS explicit Stop releases only owned interim Meditation and never re-arms Yoga")
end

-- Exercise is allowed to take the first opening. If it has already queued
-- while the gate opens, never clear it to enforce the new Yoga preference.
do
    local p, first = startWithYogaBlocked()
    finishMeditationForYogaTurn(p, first)
    local interim = await(p, "Meditation")
    local workout = T.action(p, "ISFitnessAction")
    ISTimedActionQueue.add(workout)
    p.values.ENDURANCE = .90
    step(p)
    if queue(p)[1] == interim then interim:perform() end
    local native = workout.action
    for _ = 1, 5 do
        step(p)
        assertUntouchedFitness(p, workout, native)
        assert(count(p, "Yoga") == 0 and C.status(p).active)
    end
    workout:perform()
    await(p, "Yoga")
    assert(count(p, "Yoga") == 1 and workout.begins == 1 and #p.cards == 0)
    C.stop(p)
    print("PASS Yoga debt survives ready-to-start race with a queued foreign workout")
end

do
    local p, first = startWithYogaBlocked()
    finishMeditationForYogaTurn(p, first)
    p.nativeYogaLimit = nil -- the synchronized server setting disables the exhaustion gate
    await(p, "Yoga")
    assert(p.values.ENDURANCE == .24 and count(p, "Yoga") == 1)
    C.stop(p)
    print("PASS a server-disabled exhaustion gate admits owed Yoga without a local endurance floor")
end

do
    local p = T.playerNew()
    p.sitting, p.meditation, p.xp, p.yoga = true, 5, 510, {10, 0, 0}
    p.values.BOREDOM = 45 -- native Meditation denial; no eligible literature
    assert(C.start(p, "both", false))
    for _ = 1, 12 do
        step(p)
        assert(count(p, "Yoga") == 0 and count(p, "Meditation") == 0)
        assert(C.status(p).phase ~= "complete")
    end
    C.stop(p)
    print("PASS an already-capped Yoga skill is not retrained as Both's boredom fallback")
end

do
    local p, first = startWithYogaBlocked(nil, 0)
    finishMeditationForYogaTurn(p, first)
    p.nativeYogaLimit = nil
    for i = 1, 7 do
        local yoga = await(p, "Yoga")
        -- Advance the mock game clock with the same native handle running.
        p.hours = p.hours + 1
        if i > 3 then p.yoga[2] = p.yoga[2] - 1 end
        step(p)
        if i < 7 then
            assert(C.status(p).active and queue(p)[1] == yoga)
            local workout
            if i == 2 then
                workout = T.action(p, "ISFitnessAction")
                ISTimedActionQueue.add(workout)
            end
            p.noXP = true
            yoga:perform()
            p.noXP = false
            if workout then
                local native = workout.action
                -- It is not safe to attribute the next poll's time to
                -- Yoga: a foreign set owns the intervening game hours.
                p.hours = p.hours + 9
                for _ = 1, 4 do
                    step(p)
                    assert(C.status(p).active)
                    assertUntouchedFitness(p, workout, native)
                end
                workout:perform()
            end
            local meditation = await(p, "Meditation")
            local before = p.xp
            meditation:perform()
            clearBoredom(p)
            assert(p.xp > before, "Another skill makes progress between stalled Yoga practices")
        end
    end
    local status = C.status(p)
    assert(not status.active and status.phase == "stopped" and #p.cards == 1)
    assert(status.message:find("Yoga", 1, true) and status.message:find("no XP", 1, true))
    print("PASS only verified Yoga time charges its watchdog despite Meditation XP, Yoga deductions and foreign time")
end

-- A producer waiting for a quiet native queue can become ready midway
-- through a long Meditation, not just on natural completion. Poll later
-- than the prior 500 ms gap and give it an unfamiliar action type.
do
    local p, meditation = startWithYogaBlocked()
    local history=p.data.AutoMindfulLastCompleted
    for i=1,24 do step(p) end
    p.values.ENDURANCE=.96
    step(p)
    assert(meditation.stopped and queue(p)[1]==nil and p.data.AutoMindfulLastCompleted==history)
    assert(C.status(p).cycle.skills.meditation.completed==0)
    for i=1,3 do step(p); assert(queue(p)[1]==nil,"Leave the queue open for late producers") end
    local later=T.action(p,"UnrelatedLateProducer",function() p.values.ENDURANCE=.28 end)
    ISTimedActionQueue.add(later)
    local native=later.action
    for i=1,7 do step(p); assertUntouchedFitness(p,later,native) end
    later:perform()
    await(p,"Meditation")
    assert(p.data.AutoMindfulLastCompleted==history)
    C.stop(p)
    print("PASS recovery gives a delayed generic producer an idle window, then practice resumes")
end

do
    local p, first = startWithYogaBlocked()
    for i=1,24 do step(p) end
    p.values.ENDURANCE=.96
    step(p)
    assert(first.stopped)
    local second=await(p,"Meditation")
    for i=1,30 do step(p); assert(queue(p)[1]==second and not second.stopped) end
    local map={playerNum=p:getPlayerNum(), isVisible=function() return true end}
    ISWorldMap_instance=map
    step(p)
    assert(second.stopped and C.status(p).active)
    for i=1,10 do step(p);assert(queue(p)[1]==nil and C.status(p).active) end
    ISWorldMap_instance=nil
    await(p,"Meditation")
    C.stop(p)
    print("PASS no repeated yield at stable recovery; an owned world-map dialog pauses and resumes")
end

do
    local p, meditation = startWithYogaBlocked()
    T.add(p.inventory,T.water())
    for i=1,24 do step(p) end
    p.values.ENDURANCE=.96
    step(p)
    assert(meditation.stopped and not queue(p)[1])
    p.thirstMoodle,p.values.THIRST=4,.60
    step(p)
    assert(queue(p)[1] and queue(p)[1].Type=="drink","Urgent care bypasses the idle window")
    C.stop(p)
    print("PASS urgent care does not wait for the brief cooperative recovery window")
end

do
    local p, first = startWithYogaBlocked()
    local speed=getGameSpeed
    getGameSpeed=function() return 0 end
    ISWorldMap_instance={playerNum=p:getPlayerNum(),isVisible=function() return true end}
    assert(Events.OnTickEvenPaused.callback)
    Events.OnTickEvenPaused.callback()
    assert(queue(p)[1]==first,"Paused inspection must never manipulate actions")
    ISWorldMap_instance=nil
    getGameSpeed=speed
    p.cancelInput=true
    step(p)
    assert(C.status(p).active,"Escape closed an observed paused map, not training")
    p.cancelInput=false
    step(p)
    assert(C.status(p).active and queue(p)[1]==first)
    p.cancelInput=true
    step(p)
    assert(not C.status(p).active,"A later world Escape is still a hard stop")
    print("PASS paused map close is distinguished from a later explicit stop")
end

do
    local p, first = startWithYogaBlocked()
    for i=1,24 do step(p) end
    p.StopAllActionQueue=function() end -- native stop was requested, not yet drained
    p.values.ENDURANCE=.96
    step(p)
    for i=1,7 do step(p); assert(p.nativeHead==first.action and queue(p)[1]==first) end
    p.nativeHead=nil
    step(p)
    for i=1,3 do step(p); assert(queue(p)[1]==nil,"Late native drain cannot consume the idle window") end
    local manual=T.action(p,"LateProducerAfterNativeDrain")
    ISTimedActionQueue.add(manual)
    step(p)
    assertUntouchedFitness(p,manual,manual.action)
    manual:perform()
    await(p,"Meditation")
    C.stop(p)
    print("PASS idle window begins after a draining native handle, not at release request")
end

-- Retain the exact installed admission predicates when supplied; keep the
-- existing ownership-asserting native action doubles and observable queue.
if not loadUpstream and arg and arg[1] then
    local reference=arg[1]
    loadUpstream=function(name) return assert(loadfile(reference.."/lua/"..name))() end
end
local installedGate=type(loadUpstream)=="function"
if installedGate then
    local fixtures=ZenWellnessContextMenu.Options
    LSUtil={getCharacterMood=function(p,name) return p.values[name:upper()] or 0 end}
    function getTexture(path) return path end
    loadUpstream("client/ISMeditation/ZenWellnessContextMenu.lua")
    for name,option in pairs(ZenWellnessContextMenu.Options) do option.onAction=fixtures[name].onAction end
end
T.client=true -- Model the client-side, server-synchronized SandboxVars path.

local assumedLimits={[2]=.80,[3]=.60,[4]=.30}
local function serverMode(p,mode)
    SandboxVars.Yoga.Exhaustion=mode
    p.nativeYogaLimit=assumedLimits[mode]
end

local function yogaOnly(mode,endurance)
    local p=T.playerNew()
    p.sitting,p.meditation,p.xp,p.yoga=true,10,1000,{3,90,750}
    p.values.ENDURANCE=endurance
    p.noXP=true
    function p:getPrimaryHandItem() return self.held end
    function p:getSecondaryHandItem() return nil end
    function p:getWornItems() return T.list({}) end
    local square=p:getSquare()
    function square:getObjects() return T.list({}) end
    SandboxVars.Yoga.RequiresMat,SandboxVars.Yoga.Embarrassment=false,2
    serverMode(p,mode)
    return p
end

local function startYoga(p)
    assert(C.start(p,"yoga",false))
    return p
end

do
    local p=startYoga(yogaOnly(3,.24))
    local meditation=await(p,"Meditation")
    p.values.ENDURANCE=.60
    T.now=T.now+31000; p.hours=p.hours+7
    step(p)
    assert(queue(p)[1]==meditation and not meditation.stopped,"Threshold is inclusive, not a local timer or XP target")
    assert(C.status(p).cycle.skills.meditation.started==0 and C.status(p).cycle.skills.meditation.completed==0)
    p.values.ENDURANCE=.6001
    step(p)
    assert(meditation.stopped and not meditation.autoMindfulFinished and p.xp==1000 and C.status(p).active,
        "Release the owned interim action on the first eligible poll without forcing XP")
    await(p,"Yoga")
    assert(C.status(p).mode=="yoga" and p.values.ENDURANCE==.6001 and count(p,"Yoga")==1)
    C.stop(p)
    print("PASS Yoga-only interim Meditation at capped rank; nearest native eligibility rather than 30s, 95%, 100%, or XP")
end

do
    local p=startYoga(yogaOnly(1,.24))
    await(p,"Yoga")
    assert(count(p,"Meditation")==0)
    C.stop(p)
    p=yogaOnly(4,.30); p.values.BOREDOM=35; startYoga(p)
    for _=1,4 do step(p) end
    assert(C.status(p).phase=="resting" and count(p,"Meditation")==0 and count(p,"Yoga")==0)
    p.values.ENDURANCE=.301; await(p,"Yoga"); C.stop(p)
    p=yogaOnly(3,.24); p.held={isForceDropHeavyItem=function() return true end}; startYoga(p)
    for _=1,4 do step(p) end
    assert(C.status(p).phase=="resting" and count(p,"Meditation")==0 and p.held)
    C.stop(p)
    print("PASS disabled native gate starts Yoga directly; blocked Meditation or unsafe gear falls back to rest")
end

do
    local p=yogaOnly(3,.24)
    SandboxVars.Yoga.RequiresMat=true
    p.yogaBlocked=getText("Tooltip_Yoga_MissingMat")
    startYoga(p); step(p)
    assert(not C.status(p).active and count(p,"Meditation")==0 and count(p,"Yoga")==0)
    p=yogaOnly(3,.24); p.data.LSMoodles.Embarrassed.Level=1; startYoga(p)
    local meditation=await(p,"Meditation")
    p.values.ENDURANCE=.61; p.yogaBlocked=getText("ContextMenu_Embarrassed")
    step(p)
    assert(meditation.stopped,"Release when the native blocker ceases to be exhaustion even if Yoga is still denied")
    for _=1,4 do step(p) end
    assert(C.status(p).active and count(p,"Meditation")==1 and count(p,"Yoga")==0)
    p.data.LSMoodles.Embarrassed.Level=0; p.yogaBlocked=nil
    await(p,"Yoga"); C.stop(p)
    print("PASS missing mat and embarrassment are distinct; Meditation never continues to cover a changed blocker")
end

do
    local p=startYoga(yogaOnly(3,.24))
    local meditation=await(p,"Meditation")
    p.values.ENDURANCE=.61
    local stand=await(p,"stand",meditation)
    serverMode(p,2); stand:perform()
    local interim=await(p,"Meditation")
    assert(interim~=meditation and count(p,"Yoga")==0,"Re-read changed server setting after standing")
    p.values.ENDURANCE=.80; step(p); assert(queue(p)[1]==interim)
    p.values.ENDURANCE=.801; await(p,"Yoga",interim); C.stop(p)
    print("PASS live server changes are honored after posture and at the exact 80% boundary")
end

do
    local p=startYoga(yogaOnly(3,.24))
    local meditation=await(p,"Meditation")
    local workout=T.action(p,"DifferentModAction")
    ISTimedActionQueue.add(workout)
    p.values.ENDURANCE=.61; step(p)
    assert(meditation.stopped and count(p,"Yoga")==0)
    local native=workout.action
    for _=1,6 do step(p); assertUntouchedFitness(p,workout,native) end
    workout:perform(); await(p,"Yoga"); C.stop(p)
    p=startYoga(yogaOnly(3,.24)); T.add(p.inventory,T.water())
    meditation=await(p,"Meditation")
    p.values.ENDURANCE,p.values.THIRST,p.thirstMoodle=.61,.30,4
    local drink=await(p,"drink",meditation)
    assert(meditation.stopped and count(p,"Yoga")==0)
    drink:perform(); p.thirstMoodle=0; await(p,"Yoga"); C.stop(p)
    print("PASS native Yoga readiness never clears someone else's action and urgent water still wins")
end

do
    local p=yogaOnly(3,.24); p.sitting=false
    local originalSit=p.reportEvent
    function p:reportEvent(event) originalSit(self,event); self.values.ENDURANCE=.61 end
    startYoga(p); await(p,"Yoga")
    assert(count(p,"Meditation")==0,"Do not admit Meditation if eligibility changes during sitting")
    C.stop(p)
    p=startYoga(yogaOnly(3,.24)); p.meditation=5
    local first=await(p,"Meditation")
    first:perform()
    local nextBridge=await(p,"Meditation")
    assert(nextBridge~=first and C.status(p).cycle.skills.meditation.completed==0 and not p.data.AutoMindfulLastCompleted)
    p.values.ENDURANCE=.62; await(p,"Yoga",nextBridge); C.stop(p)
    print("PASS a natural interim finish does not count as a training turn and can resume only while exhausted")
end

-- A new max-rank session practices when idle rather than waiting for a
-- symptom, trains no capped-skill XP, and never owns another scheduler's turn.
do
    local p=T.playerNew()
    p.meditation,p.yoga,p.noXP,p.sitting=10,{10,0,0},true,true
    assert(C.start(p,"both",false))
    assert(C.status(p).backgroundPractice==true)
    local meditation=await(p,"Meditation")
    p.hours=p.hours+7; step(p)
    assert(queue(p)[1]==meditation and C.status(p).active,"A capped skill is not an XP watchdog failure")
    local workout=T.action(p,"IndependentWorkoutAction")
    ISTimedActionQueue.add(workout)
    for _=1,6 do step(p) end
    local native=workout.action
    assertUntouchedFitness(p,workout,native)
    workout:perform()
    local nextMed=await(p,"Meditation")
    assert(nextMed~=meditation and C.status(p).cycle.skills.meditation.completed==0)
    nextMed:perform()
    local yoga=await(p,"Yoga")
    assert(C.status(p).cycle.lastCompleted=="meditation")
    yoga:perform()
    await(p,"Meditation")
    assert(C.status(p).cycle.lastCompleted=="yoga")
    C.stop(p)
    print("PASS capped Both alternates without XP and yields to foreign work")
end

do
    for _,mode in ipairs({"meditation","yoga"}) do
        local p=T.playerNew()
        p.noXP,p.sitting=true,mode=="meditation"
        if mode=="meditation" then p.meditation=10 else p.yoga={10,0,0} end
        local kind=mode=="meditation" and "Meditation" or "Yoga"
        assert(C.start(p,mode,false) and C.status(p).backgroundPractice)
        local first=await(p,kind)
        first:perform()
        assert(await(p,kind)~=first)
        assert(count(p,kind=="Yoga" and "Meditation" or "Yoga")==0)
        C.stop(p)
    end
    print("PASS capped single modes stay on their selected skill when no relief is needed")
end

do
    local p=startYoga(yogaOnly(3,.24))
    C.stop(p)
    p.yoga={10,0,0}
    assert(C.start(p,"yoga",false) and C.status(p).backgroundPractice)
    local bridge=await(p,"Meditation")
    step(p)
    assert(queue(p)[1]==bridge,"Capped Yoga does not prematurely stop the endurance bridge")
    p.values.ENDURANCE=.62
    await(p,"Yoga",bridge)
    assert(C.status(p).cycle.skills.meditation.completed==0)
    C.stop(p)
    print("PASS capped Yoga can still use Meditation only as an endurance bridge")
end

print("SCHEDULER INTEGRATION PASS 22 cases; "..(installedGate and "installed Lifestyle predicates; " or "mock Lifestyle predicates; ")
    .."explicit game-boundary doubles, not live player or XP evidence")
