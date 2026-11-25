-- The real scheduler and supply policy; the game owns every stat, action and badge.
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
local T,C,Q=AutoMindfulTest,AutoMindfulTest.controller,ISTimedActionQueue
local Options=require "AutoMindful/Options"
local Nearby=require "AutoMindful/Nearby"
local Facts=require "AutoMindful/WellnessFacts"
local enabled=true
Options.practiceCare=function() return enabled end
Options.minimumTier=function(group,kind) return group=="recovery" and kind=="meditation" and 1 or 0 end
function getModInfoByID(id) if id=="LifestyleHobbies" then return {getModVersion=function() return Facts.version end} end end
SandboxVars.Text={DividerMeditationNew=true}
SandboxVars.LS={MoodUpdate=2}
local function head(p) return Q.getTimedActionQueue(p).queue[1] end
local function step(p,ms) T.now=T.now+(ms or 250); C.update(p) end
local function steps(p,n) for i=1,n do step(p) end end
local function new(rank,hunger,critical)
    local p=T.playerNew()
    p.sitting,p.meditation,p.yoga=true,rank,{4,0,100}
    p.values.HUNGER,p.hungerMoodle=hunger,critical and 4 or 0
    p.data.AutoMindfulLastCompleted="meditation"
    function p:getPrimaryHandItem() return nil end
    function p:getSecondaryHandItem() return nil end
    return p
end
local function begin(p,mode) local ok,why=C.start(p,mode,false); assert(ok,why) end
local function untilHead(p,kind)
    for _=1,40 do
        step(p)
        local a=head(p)
        if a then
            if a.Type==kind then return a end
            assert(a.Type=="stand","Expected "..kind..", got "..a.Type.." ("..C.status(p).message..")")
            a:perform()
        end
        assert(C.status(p).active,C.status(p).message)
    end
    error("No "..kind..": "..C.status(p).message)
end
local function count(p,kind)
    local n=0; for _,k in ipairs(p.history) do if k==kind then n=n+1 end end
    return n
end
local function badge(p,v) p.data.LSMoodles.MindfulState.Value=v end
local function meal(p) return T.add(p.inventory,T.item("Food",{hunger=-.8,baseHunger=-.8,calories=320})) end
local function noCredit(p)
    local cycle=C.status(p).cycle
    if cycle then
        assert(cycle.lastCompleted=="meditation" and p.data.AutoMindfulLastCompleted=="meditation")
        assert(cycle.skills.meditation.started==0 and cycle.skills.meditation.completed==0)
    end
    assert(count(p,"eat")==0 and p.calories==2000)
end
local function waitEmpty(p)
    steps(p,8)
    assert(C.status(p).active and not head(p),C.status(p).message)
end

-- All modes use the same distinct course, even when the next XP leg
-- happens to be Meditation. Care never settles that XP turn.
for _,mode in ipairs({"recovery","both","yoga","meditation"}) do
    local p=new(6,.31)
    begin(p,mode)
    local a=untilHead(p,"Meditation")
    assert(C.status(p).phase=="practice-care" and a.autoMindfulOwner)
    step(p); assert(head(p)==a,"The default tier minimum cannot terminate hunger care above 30%")
    badge(p,.4); step(p)
    assert(a.stopped and not a.autoMindfulFinished and not head(p) and p.values.HUNGER==.31)
    noCredit(p)
    if mode=="recovery" then waitEmpty(p)
    elseif mode=="meditation" then
        local practice=untilHead(p,"Meditation")
        assert(practice~=a and C.status(p).phase=="meditation")
    else
        local yoga=untilHead(p,"Yoga")
        assert(C.status(p).phase=="yoga" and count(p,"Meditation")==1); noCredit(p)
        yoga:perform(); step(p)
        assert(C.status(p).cycle.skills.yoga.completed==1 and p.data.AutoMindfulLastCompleted=="yoga")
    end
    C.stop(p)
end
print("PASS .31 across four modes and exact scheduled Yoga turn receipt")

for _,value in ipairs({.4,.6}) do
    local p=new(6,.80,true); badge(p,value); begin(p,"both")
    waitEmpty(p); noCredit(p)
    assert(count(p,"Meditation")==0 and count(p,"Yoga")==0)
    p.values.HUNGER=.72; step(p)
    assert((C.status(p).careNotice or ""):find("hunger ease",1,true),"Only an actual decrease is relief")
    -- One badge need not suffice. On real progress, renew when it wears off.
    badge(p,.2)
    local a=untilHead(p,"Meditation")
    assert(C.status(p).phase=="practice-care")
    badge(p,.4); step(p)
    assert(a.stopped and not head(p)); noCredit(p)
    p.hungerMoodle,p.values.HUNGER=0,.05
    untilHead(p,"Yoga"); noCredit(p)
    C.stop(p)
end
print("PASS active Strong/Perfect passive, verified relief enables bounded renewal, no calorie or turn credit")

for _,mode in ipairs({"both","recovery"}) do
    local p=new(6,.80,true)
    p.sitting=false
    begin(p,mode)
    local a=untilHead(p,"Meditation")
    assert(C.status(p).phase=="practice-care"); steps(p,3); assert(head(p)==a)
    step(p,245000); steps(p,12)
    assert(a.stopped and not head(p) and count(p,"Meditation")==1 and count(p,"eat")==0)
    assert(C.status(p).active and C.status(p).message:lower():find("food",1,true),C.status(p).message)
    do
        step(p,300000); steps(p,8); assert(not head(p) and count(p,"Meditation")==1)
        meal(p); local food=untilHead(p,"eat"); food:perform(); assert(p.calories>2000); C.stop(p)
    end
end
print("PASS critical owned timeout keeps Training and Recovery watching for real food without retry loops")

do
    local p=new(6,.80,true); badge(p,.4); begin(p,"recovery")
    waitEmpty(p); step(p,90000); steps(p,8)
    assert(C.status(p).active and not head(p) and C.status(p).message:lower():find("food",1,true))
    badge(p,.2); step(p,300000); steps(p,8)
    assert(not head(p) and count(p,"Meditation")==0,"A stale badge with no receipt cannot re-arm critical acquisition")
    C.stop(p)
end
print("PASS bounded passive window with no native hunger change")

for _,why in ipairs({"rank","native","disabled","sleep","thirst","unsafe","held"}) do
    local p=new(why=="rank" and 5 or 6,.8,true)
    if why=="native" then p.values.BOREDOM,p.yogaBlocked=35,getText("Tooltip_Action_Exhausted")
    elseif why=="disabled" then enabled=false
    elseif why=="thirst" then p.values.THIRST,p.thirstMoodle=.8,4
    elseif why=="held" then function p:getPrimaryHandItem() return {isForceDropHeavyItem=function() return true end} end
    elseif why=="sleep" then p.values.FATIGUE=.8 end
    begin(p,"recovery")
    if why=="unsafe" then p.zombies=1 end
    steps(p,14)
    if why=="thirst" or why=="sleep" then
        assert(count(p,"Meditation")==1 and head(p) and not p:isAsleep(),
            "Only disproven water routes, not dehydration itself, permit a bounded hunger attempt; never sleep through starvation")
    else assert(count(p,"Meditation")==0 and not head(p),why) end
    if why=="unsafe" then assert(C.status(p).active and C.status(p).phase=="recovery-paused") end
    C.stop(p); enabled=true
end
print("PASS lower rank, native gate, option, sleep, critical thirst, danger and held gear")

for _,when in ipairs({"initial","mid","foreign","water"}) do
    local p=new(6,.31,when=="foreign" or when=="water")
    if when=="initial" then meal(p) end
    begin(p,"recovery")
    if when~="initial" then
        local a=untilHead(p,"Meditation")
        if when=="foreign" then
            local job=T.action(p,"ForeignWorkout")
            Q.add(job); meal(p); step(p); steps(p,5)
            assert(head(p)==job and job.begins==1 and job.action==p.nativeHead and not job.autoMindfulOwner and not job.stopped)
            job:perform()
        elseif when=="water" then
            T.add(p.inventory,T.water({thirst=-.8})); p.values.THIRST,p.thirstMoodle=.8,4
            local drink=untilHead(p,"drink"); assert(a.stopped); drink:perform(); C.stop(p)
        else meal(p) end
    end
    if when~="water" then
        local eat=untilHead(p,"eat"); eat:perform()
        assert(count(p,"Meditation")==((when=="initial") and 0 or 1) and p.calories>2000 and p.values.HUNGER<.31)
        C.stop(p)
    end
end
print("PASS real meal at start or mid-course, queued player action, and newly critical thirst all win")

do
    local p=new(8,.55); p.values.BOREDOM,p.values.PAIN=23,21
    begin(p,"recovery")
    local a=untilHead(p,"Meditation"); steps(p,4); assert(head(p)==a)
    p.values.PAIN=40; steps(p,3)
    assert(a.stopped and not a.autoMindfulFinished); C.stop(p)
end
print("PASS live native eligibility above old calm comfort bounds, with observed deterioration guard")

for _,h in ipairs({.4,.8}) do
    local p=new(6,h,h>=.8)
    p.values.FATIGUE,p.values.PANIC=.65,35
    MoodleType.PANIC="panic"
    local old=p.getMoodles
    function p:getMoodles()
        local moodles=old(self)
        local read=moodles.getMoodleLevel
        function moodles:getMoodleLevel(k) if k==MoodleType.PANIC then return p.panicMoodle end; return read(self,k) end
        return moodles
    end
    p.panicMoodle=2
    begin(p,"recovery")
    local a=untilHead(p,"Meditation"); steps(p,6)
    assert(head(p)==a and not a.stopped and not p:isAsleep(),"Stock-rejected sleep may not cancel or poison hunger care")
    if h<.8 then p.panicMoodle=0 -- a raw panic number alone is not a stock sleep restriction
    else function p:getSleepingTabletEffect() return 2000 end end -- existing native effect; no medication used
    steps(p,16)
    if h<.8 then assert(p:isAsleep() and a.stopped and not head(p))
    else assert(not p:isAsleep() and head(p)==a and not a.stopped,"Never initiate sleep through unserved starvation") end
    C.stop(p)
end
print("PASS admissible sleep can preempt ordinary care, not an unserved survival crisis")

do
    local p=new(6,.80,true); badge(p,.4); begin(p,"recovery")
    waitEmpty(p); p.values.HUNGER=.70; step(p)
    badge(p,.20); p.values.HUNGER=.85
    local a=untilHead(p,"Meditation")
    badge(p,.40); step(p); assert(a.stopped)
    step(p,5500) -- do not read the previous notification as a new result
    p.values.HUNGER=.72; step(p)
    assert(not (C.status(p).careNotice or ""):find("hunger ease",1,true),
        "An oscillating critical reading that remains above the previous low cannot fund a new renewal")
    badge(p,.20); step(p,30000); steps(p,12)
    assert(C.status(p).active and not head(p) and count(p,"Meditation")==1)
    C.stop(p)
end
print("PASS repeated critical hunger oscillations cannot restart native acquisition indefinitely")

-- Exercise first native moodles below old numeric thresholds at the scheduler
-- boundary, including interruption of an already-started practice.
for _,mode in ipairs({"both","meditation","yoga","recovery"}) do
    for _,k in ipairs({"food","water"}) do
        local p=new(6,.01)
        begin(p,mode)
        if mode=="recovery" then steps(p,6)
        else untilHead(p,mode=="meditation" and "Meditation" or "Yoga") end
        local food=k=="food"
        p.values[food and "HUNGER" or "THIRST"]=.08
        if food then meal(p); p.hungerMoodle=1 else T.add(p.inventory,T.water()); p.thirstMoodle=1 end
        local a=untilHead(p,food and "eat" or "drink")
        local v=p.values[food and "HUNGER" or "THIRST"]
        a:perform()
        assert(p.values[food and "HUNGER" or "THIRST"]<v and C.status(p).active)
        C.stop(p)
    end
end
print("PASS first native hunger/thirst moodle admits native portions during Recovery or training")

-- Missing critical water must never veto a safe meal, and crossing 50 must
-- not stop an already-owned portion or native drink. The original session
-- remains alive even after resources run out; no fixture stats move on queue.
for _,mode in ipairs({"both","recovery"}) do
    local p=new(0,.92,true)
    local getBody=p.getBodyDamage
    function p:getBodyDamage()
        local body=getBody(self)
        function body:getOverallBodyHealth() return p.hp or 65 end
        return body
    end
    p.values.THIRST,p.thirstMoodle=.92,4
    T.add(p.inventory,T.water({poison=true}))
    T.add(p.inventory,T.item("Food",{rawDanger=true}))
    begin(p,mode)
    steps(p,12)
    assert(C.status(p).active and not head(p) and count(p,"eat")==0 and count(p,"drink")==0 and not p:isAsleep())
    p.hp=1
    local calories=p.calories
    local foreign=T.action(p,"PlayerTakingAction")
    Q.add(foreign); meal(p); steps(p,6)
    assert(head(p)==foreign and not foreign.stopped and not foreign.autoMindfulOwner)
    foreign:perform()
    local eat=untilHead(p,"eat")
    assert(eat.autoMindfulOwner and p.calories==calories and p.values.HUNGER==.92)
    p.hp=.2; steps(p,6)
    assert(head(p)==eat and not eat.stopped)
    eat:perform(); assert(p.calories>calories and p.values.HUNGER<.92)
    p.hungerMoodle=0
    local water=T.add(p.inventory,T.water({thirst=-1}))
    local drink=untilHead(p,"drink"); p.hp=.01; steps(p,4)
    assert(head(p)==drink and not drink.stopped and p.values.THIRST==.92)
    drink:perform(); p.thirstMoodle=0; steps(p,8)
    assert(C.status(p).active and p.values.THIRST<.92 and water.fluid.amount<1)
    assert(not head(p) and count(p,"Meditation")==0 and count(p,"Yoga")==0)
    p.hp=80
    if mode=="both" then untilHead(p,"Yoga") else steps(p,8); assert(C.status(p).active) end
    C.stop(p)
end
print("PASS both modes: low HP neither stops safe intake nor takes foreign control; no training until health returns")

-- A native tier is not food and a missed water route may not reset a hunger
-- receipt. A real drink, not merely an unchanged thirsty moodle, takes over.
for _,mode in ipairs({"both","recovery"}) do
    local p=new(6,.81,true); badge(p,.4)
    p.values.THIRST,p.thirstMoodle=.88,4; begin(p,mode)
    steps(p,20)
    assert(not head(p) and C.status(p).active and C.status(p).message:lower():find("water",1,true))
    p.values.HUNGER=.75; step(p)
    assert((C.status(p).careNotice or ""):find("hunger ease",1,true) and p.calories==2000)
    local water=T.add(p.inventory,T.water({thirst=-1}))
    local drink=untilHead(p,"drink"); drink:perform()
    assert(water.fluid.amount<1 and p.values.THIRST<.88)
    C.stop(p)
end
print("PASS both modes: a dried-up critical water search permits an actual native hunger receipt, then a newly usable drink wins")

for _,mode in ipairs({"recovery","yoga"}) do
    local p=new(6,.01); begin(p,mode)
    if mode=="yoga" then untilHead(p,"Yoga") else steps(p,6) end
    p.hungerMoodle,p.values.HUNGER=1,.07
    local med=untilHead(p,"Meditation")
    assert(C.status(p).phase=="practice-care" and count(p,"eat")==0)
    badge(p,.4); step(p)
    assert(med.stopped and p.values.HUNGER==.07 and p.calories==2000)
    C.stop(p)
end
print("PASS first hunger moodle reuses the native bounded Strong fallback, even inside an ordinary Yoga turn")

-- Reproduce the live report: a hunger course opens while endurance is low,
-- skill rank changes arrive before the badge, and a real foreign action may
-- take a turn without converting unfinished care into an XP completion.
for _,which in ipairs({"med-only","yoga-only","both-one-med","both-one-yoga","both-same-tick"}) do
    local mode=which=="med-only" and "meditation" or which=="yoga-only" and "yoga" or "both"
    local p=new(9,.75)
    p.yoga={9,90,100}
    p.values.ENDURANCE,p.nativeYogaLimit,p.hungerMoodle=.25,.60,3
    begin(p,mode)
    local med=untilHead(p,"Meditation")
    assert(C.status(p).phase=="practice-care")
    steps(p,5) -- A real training leg would arm the endurance handoff here.
    if which~="yoga-only" and which~="both-one-yoga" then p.meditation=10 end
    if which~="med-only" and which~="both-one-med" then p.yoga={10,0,0} end
    p.values.ENDURANCE=1
    steps(p,20)
    assert(head(p)==med and not med.stopped and #p.cards==0,
        which..": neither XP cap nor recovered endurance interrupts a hunger course")
    if which=="both-same-tick" then
        local dose=T.action(p,"ForeignPainkiller")
        Q.add(dose); step(p)
        assert(head(p)==dose and dose.begins==1 and not dose.stopped and not dose.autoMindfulOwner)
        dose:perform()
        med=untilHead(p,"Meditation")
        assert(C.status(p).mode=="recovery" and C.status(p).phase=="practice-care" and #p.cards==1)
    end
    badge(p,.4); step(p)
    assert(med.stopped and p.values.HUNGER==.75 and p.calories==2000,"Badge is not a food receipt")
    p.values.HUNGER,p.hungerMoodle=.06,0
    if which=="both-one-med" or which=="both-one-yoga" then
        untilHead(p,which=="both-one-med" and "Yoga" or "Meditation")
        assert(C.status(p).mode=="both" and #p.cards==0,which..": train the remaining skill")
        if which=="both-one-med" then p.yoga={10,0,0} else p.meditation=10 end
        local a=head(p); a:perform()
    end
    steps(p,20)
    assert(C.status(p).mode=="recovery" and C.status(p).active and #p.cards==1,
        which..": switch to ongoing Recovery once the selected skills cap")
    C.stop(p); assert(#p.cards==1)
end
print("PASS one or both mid-training caps, endurance recovery, foreign dose, and rank-complete Recovery")

do
    local p=new(5,.75); p.sitting=true
    begin(p,"meditation")
    local xp=untilHead(p,"Meditation")
    assert(C.status(p).phase=="meditation")
    p.meditation,p.hungerMoodle=6,3
    step(p)
    assert(xp.stopped,"Newly unlocked hunger care owns the next meditation, not the XP leg")
    untilHead(p,"Meditation")
    assert(C.status(p).phase=="practice-care")
    C.stop(p)
end
print("PASS a mid-course level 6 unlock rechecks the native hunger utility immediately")
