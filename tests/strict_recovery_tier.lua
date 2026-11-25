-- The actual Recovery scheduler, with native action/clock/receipt boundaries doubled.
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
local T,C,Q=AutoMindfulTest,AutoMindfulTest.controller,ISTimedActionQueue
local Options=require "AutoMindful/Options"
local Facts=require "AutoMindful/WellnessFacts"
CharacterStat.STRESS,CharacterStat.INTOXICATION="STRESS","INTOXICATION"
local enabled,select,provider,speed
Options.strictRecoveryTier=function() return enabled end
Options.practiceCare=function() return true end
Options.minimumTier=function(group,kind) return group=="recovery" and select[kind] or 0 end
function getModInfoByID(id) if id=="LifestyleHobbies" then return {getModVersion=function() return provider end} end end
function getGameSpeed() return speed end
local function head(p) return Q.getTimedActionQueue(p).queue[1] end
local function step(p,ms) T.now=T.now+(ms or 250); C.update(p) end
local function steps(p,n,ms) for _=1,n do step(p,ms) end end
local function count(p,id)
    local n=0; for _,kind in ipairs(p.history) do if kind==id then n=n+1 end end
    return n
end
local function badge(p,kind,v)
    p.data.LSMoodles[kind=="yoga" and "Zen" or "MindfulState"].Value=v
end
local function survivor(m,y)
    enabled,select,provider,speed=true,{meditation=3,yoga=4},Facts.version,1
    SandboxVars.Text={DividerMeditationNew=true}
    local p=T.playerNew()
    p.meditation,p.yoga,p.sitting=m or 6,{y or 0,0,100},not y
    p.data.AutoMindfulLastCompleted="yoga"
    function p:getPrimaryHandItem() return nil end
    function p:getSecondaryHandItem() return nil end
    function p:getPainEffect() return 0 end
    function p:getPainDelta() return 0 end
    function p:getSleepingTabletEffect() return 0 end
    return p
end
local function start(p,mode,tier)
    local ok,why=C.start(p,mode or "recovery",false,tier)
    assert(ok,why)
end
local function await(p,wanted)
    for _=1,30 do
        step(p)
        assert(C.status(p).active,C.status(p).message)
        local a=head(p)
        if a then
            if a.Type==wanted then return a end
            assert(a.Type=="stand",wanted.." beside "..a.Type)
            a:perform()
        end
    end
    error("Expected "..wanted.."; "..C.status(p).message)
end
local function target(p,kind,tier,current)
    local status=C.status(p)
    local wanted=assert(status.tierGoal,status.message)
    assert(wanted.kind==kind and wanted.target==tier and wanted.current==current,status.message)
    assert(status.active and not status.cycle and p.data.AutoMindfulLastCompleted=="yoga")
end
local function untouched(p,a)
    assert(head(p)==a and p.nativeHead==a.action and a.begins==1 and not a.autoMindfulOwner and not a.stopped and not a.cancelled)
end
for _,kind in ipairs({"Meditation","Yoga"}) do
    local menu=ZenWellnessContextMenu.Options[kind]
    function menu.onAction(_,self,p)
        assert(not head(p) and not p.nativeHead and not self.canPerform(p))
        Q.clear(p)
        if p.refusePractice then return end
        Q.add(T.action(p,kind,function()
            if p.finishedPractice then p:finishedPractice(kind) end
        end))
    end
end
local n=0
local function test(name,fn) fn(); n=n+1; print("PASS "..name) end

test("strict is opt-in, no useful need means no pursuit or upkeep",function()
    local p=survivor(10)
    start(p); steps(p,20)
    assert(not head(p) and not C.status(p).tierGoal and count(p,"Meditation")==0)
    C.stop(p)
    p=survivor()
    enabled=false; p.values.STRESS=.57
    start(p); local a=await(p,"Meditation")
    p.values.STRESS=.12
    step(p)
    assert(a.stopped and not head(p) and not C.status(p).tierGoal)
    steps(p,12,20000); assert(count(p,"Meditation")==1 and C.status(p).active)
    C.stop(p)
end)

test("strict Meditation survives ordinary relief and stops on real Value, not HUD/XP",function()
    local p=survivor()
    p.values.STRESS=.57
    start(p); local a=await(p,"Meditation")
    target(p,"meditation",2,0)
    p.values.STRESS=.15
    p.data.LSMoodles.MindfulState.Level=3; p.xp=500
    step(p); target(p,"meditation",2,0); assert(head(p)==a)
    badge(p,"meditation",.2)
    step(p); target(p,"meditation",2,1); assert(head(p)==a)
    badge(p,"meditation",.4)
    step(p); assert(a.stopped and not a.autoMindfulFinished and not head(p) and not C.status(p).tierGoal)
    badge(p,"meditation",0); steps(p,15,30000)
    assert(count(p,"Meditation")==1 and C.status(p).active and #p.cards==0)
    C.stop(p)
end)

test("foreign takeover preserves the pending target and never spends its active budget",function()
    local p=survivor(); p.values.STRESS=.60
    start(p); local a=await(p,"Meditation")
    p.values.STRESS=.10
    local foreign=T.action(p,"ManualWorkout"); Q.add(foreign)
    steps(p,4); untouched(p,foreign); assert(a.stopped)
    steps(p,30,20000); untouched(p,foreign); target(p,"meditation",2,0)
    foreign:perform()
    local b=await(p,"Meditation"); assert(b~=a)
    badge(p,"meditation",.4); step(p)
    assert(b.stopped and not C.status(p).tierGoal and C.status(p).active)
    C.stop(p)
end)

test("a real tier observed during foreign work satisfies the objective without cancel or credit",function()
    local p=survivor(); p.values.STRESS=.60
    start(p); await(p,"Meditation")
    p.values.STRESS=.10
    local foreign=T.action(p,"ManualWorkout"); Q.add(foreign)
    steps(p,3); untouched(p,foreign)
    badge(p,"meditation",.4); steps(p,3); untouched(p,foreign)
    local status=C.status(p)
    assert(not status.tierGoal and status.tierNotice:find("is active",1,true))
    foreign:perform(); badge(p,"meditation",0); steps(p,15)
    assert(not head(p) and count(p,"Meditation")==1 and #p.cards==0)
    C.stop(p)
end)

test("critical water interrupts the exact owned course and preserves the pending target",function()
    local p=survivor(); p.values.STRESS=.60
    start(p); local a=await(p,"Meditation")
    p.values.STRESS=.10
    T.add(p.inventory,T.water({thirst=-.8})); p.thirstMoodle,p.values.THIRST=4,.8
    step(p); assert(a.stopped)
    local drink=await(p,"drink"); target(p,"meditation",2,0)
    drink:perform(); p.thirstMoodle=0
    local b=await(p,"Meditation")
    assert(b~=a and p.values.THIRST<.15)
    badge(p,"meditation",.4); step(p)
    assert(b.stopped and not C.status(p).tierGoal and C.status(p).active)
    C.stop(p)
end)

test("a distant book cannot churn a strict course; a readable local book takes priority",function()
    local p=survivor(); p.values.STRESS=.60
    local nearby=require "AutoMindful/Nearby"
    local previousFind,previousSearch=nearby.find,Options.searchNearby
    local shelf=T.container(6,0)
    local book=T.add(shelf,T.item("Literature",{boredom=-40,data={literatureTitle="StrictRemote"}}))
    nearby.find=function(_,kind)
        if kind=="literature" then return {kind=kind,item=book,container=shelf,square=shelf:getSourceGrid(),key="remote-book"} end
    end
    Options.searchNearby=function() return true end
    start(p); local a=await(p,"Meditation")
    p.values.STRESS,p.values.BOREDOM=.1,22
    steps(p,7); assert(head(p)==a and not a.stopped)
    T.add(p.inventory,T.item("Literature",{boredom=-40,data={literatureTitle="StrictLocal"}}))
    step(p); assert(a.stopped)
    local read=await(p,"read"); target(p,"meditation",2,0); read:perform()
    local b=await(p,"Meditation"); assert(b~=a)
    badge(p,"meditation",.4); step(p); assert(not C.status(p).tierGoal)
    C.stop(p)
    nearby.find,Options.searchNearby=previousFind,previousSearch
end)

test("the actual native utility tier is a floor; emergency hunger does not seed a strict objective",function()
    local p=survivor(); select.meditation=1; p.values.HUNGER=.40
    start(p); local a=await(p,"Meditation"); target(p,"meditation",2,0)
    badge(p,"meditation",.2); step(p); assert(head(p)==a)
    badge(p,"meditation",.4); step(p); assert(a.stopped and not C.status(p).tierGoal)
    C.stop(p)

    for _,strict in ipairs({true,false}) do
        p=survivor(6); select.meditation=1; enabled=strict; p.hungerMoodle,p.values.HUNGER=4,.8
        start(p); a=await(p,"Meditation")
        badge(p,"meditation",.2); step(p); assert(head(p)==a)
        badge(p,"meditation",.4); step(p)
        assert(a.stopped and not head(p) and not C.status(p).tierGoal)
        assert(C.status(p).message:find("matching effect",1,true) and p.values.HUNGER==.8)
        p.hungerMoodle,p.values.HUNGER=0,.10; steps(p,15)
        assert(count(p,"Meditation")==1 and not head(p))
        C.stop(p)
    end
end)

test("strict Yoga waits for natural finish and a real post-action Zen value",function()
    local p=survivor(0,6); p.values.BOREDOM=34
    start(p); local a=await(p,"Yoga"); target(p,"yoga",4,0)
    p.values.BOREDOM=0; p.data.LSMoodles.Zen.Level=4
    steps(p,5); assert(head(p)==a)
    a:perform()
    local b=await(p,"Yoga"); assert(a~=b and not a.stopped)
    badge(p,"yoga",.72); step(p)
    assert(head(p)==b and not b.stopped,"Early stock Yoga stop can subtract Zen")
    function p:finishedPractice(kind) assert(kind=="Yoga"); badge(p,"yoga",.75) end
    local foreign=T.action(p,"ManualWorkout"); Q.add(foreign)
    b:perform(); step(p); untouched(p,foreign)
    assert(not b.stopped and not C.status(p).tierGoal)
    foreign:perform(); steps(p,15)
    assert(not head(p) and C.status(p).active and count(p,"Yoga")==2)
    C.stop(p)
end)

test("max-rank Yoga has no native Zen penalty and can release on an observed target",function()
    local p=survivor(0,10); p.values.BOREDOM=35
    start(p); local a=await(p,"Yoga")
    p.values.BOREDOM=0
    badge(p,"yoga",.75); step(p)
    assert(a.stopped and not head(p) and not C.status(p).tierGoal and C.status(p).active)
    C.stop(p)
end)

test("explicit Stop clears a pending strict tier without touching a player's action",function()
    local p=survivor(); p.values.STRESS=.60
    start(p); await(p,"Meditation")
    p.values.STRESS=.05
    local foreign=T.action(p,"ManualWorkout"); Q.add(foreign)
    steps(p,3); untouched(p,foreign); target(p,"meditation",2,0)
    C.stop(p); untouched(p,foreign)
    assert(not C.status(p).tierGoal and not C.status(p).active)
    foreign:perform(); steps(p,10); assert(not head(p) and count(p,"Meditation")==1)
end)

test("strict awaits a live native gate without a blind retry; changed minimum can be retargeted",function()
    local p=survivor(0,6); p.values.BOREDOM=35
    start(p); await(p,"Yoga"); p.values.BOREDOM=0
    local foreign=T.action(p,"ManualWorkout"); Q.add(foreign); steps(p,5)
    p.nativeYogaLimit,p.values.ENDURANCE=.6,.4
    foreign:perform()
    steps(p,20); target(p,"yoga",4,0); assert(not head(p) and count(p,"Yoga")==1)
    select.yoga=2; step(p); target(p,"yoga",2,0)
    p.values.ENDURANCE=.8; await(p,"Yoga")
    select.yoga=0; step(p)
    assert(not head(p) and not C.status(p).tierGoal and C.status(p).active)
    C.stop(p)
end)

test("strict cancels incompatible, unreachable, and disabled targets without stopping Recovery",function()
    for _,reason in ipairs({"version","settings","rank","checkbox"}) do
        local p=survivor(10); p.values.STRESS=.61
        start(p); local a=await(p,"Meditation")
        p.values.STRESS=.1
        if reason=="version" then provider="future"
        elseif reason=="settings" then SandboxVars.Text.DividerMeditationNew=false
        elseif reason=="rank" then p.meditation=6
        else enabled=false end
        step(p); assert(a.stopped and not C.status(p).tierGoal and C.status(p).active,reason)
        C.stop(p)
    end
end)

test("four real unproductive practices or repeated empty menu admissions bound the goal",function()
    local p=survivor(0,6); p.values.BOREDOM=35
    start(p)
    for _=1,4 do await(p,"Yoga"):perform() end
    steps(p,15)
    local s=C.status(p)
    assert(not s.tierGoal and s.active and count(p,"Yoga")==4 and s.tierNotice:find("four completed",1,true))
    C.stop(p)
    p=survivor(); p.values.STRESS=.60; p.refusePractice=true
    start(p); steps(p,45)
    s=C.status(p)
    assert(s.active and not s.tierGoal and not head(p) and s.tierNotice:find("could not start",1,true))
    C.stop(p)
end)

test("paused and unobserved wall time are not practice; eight active minutes without progress are bounded",function()
    local p=survivor(); p.values.STRESS=.60
    start(p); local a=await(p,"Meditation")
    p.values.STRESS=.15
    speed=0; steps(p,20,2500); assert(head(p)==a and C.status(p).tierGoal)
    speed=1; step(p,600000); assert(head(p)==a and C.status(p).tierGoal)
    for _=1,195 do if not head(p) then break end; step(p,2500) end
    local s=C.status(p)
    assert(a.stopped and not head(p) and s.active and not s.tierGoal and s.tierNotice:find("eight minutes",1,true))
    C.stop(p)
end)

test("an explicit tier goal does not inherit the strict objective",function()
    local a
    local p=survivor(); p.values.STRESS=.05
    start(p,"meditateTo",2); a=await(p,"Meditation")
    badge(p,"meditation",.4); step(p)
    assert(a.stopped and C.status(p).phase=="complete" and not C.status(p).active)
end)

print("strict Recovery: "..n.." cases passed")
