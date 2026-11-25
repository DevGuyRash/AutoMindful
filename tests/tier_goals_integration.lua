-- Controller contracts with explicit native action, clock and moodle doubles.
-- Stock Meditation writes its Value during update; successful Yoga at perform.
AutoMindfulContractHarnessOnly = true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly = nil
local T,C,Q=AutoMindfulTest,AutoMindfulTest.controller,ISTimedActionQueue
local Options=require "AutoMindful/Options"
local Facts=require "AutoMindful/WellnessFacts"
local config
Options.minimumTier=function(group,kind) return config[group][kind] or 0 end
Options.practiceCare=function() return config.utility end
function getModInfoByID(id) if id=="LifestyleHobbies" then return {getModVersion=function() return Facts.version end} end end
CharacterStat.STRESS="STRESS"
CharacterStat.INTOXICATION="INTOXICATION"

local function head(p) return Q.getTimedActionQueue(p).queue[1] end
local function step(p,ms) T.now=T.now+(ms or 250); C.update(p) end
local function count(p,kind)
    local n=0
    for _,name in ipairs(p.history) do if name==kind then n=n+1 end end
    return n
end
local function new(m,y)
    config={rotation={},capped={},recovery={},utility=false}
    SandboxVars.Text={DividerMeditationNew=true}
    local p=T.playerNew()
    p.sitting=true
    p.meditation,p.xp,p.yoga=m,m*100,{y,0,100}
    function p:getPrimaryHandItem() return nil end
    function p:getSecondaryHandItem() return nil end
    function p:getPainEffect() return 0 end
    function p:getPainDelta() return 0 end
    function p:getSleepingTabletEffect() return 0 end
    return p
end
local function nativeTier(p,kind,value)
    local key=kind=="meditation" and "MindfulState" or "Zen"
    p.data.LSMoodles[key].Value=value
end
local function begin(p,mode,tier)
    local ok,reason=C.start(p,mode,false,tier)
    assert(ok,reason)
end
local function await(p,kind)
    for _=1,60 do
        step(p)
        local a=head(p)
        if a then
            if a.Type==kind then
                assert(a.autoMindfulOwner and a:isStarted())
                return a
            end
            assert(a.Type=="stand", "Wanted "..kind..", got "..tostring(a.Type))
            a:perform()
        end
        assert(C.status(p).active,C.status(p).message)
    end
    error("No "..kind..": "..C.status(p).message)
end
local function activeGoal(p,kind,tier,current)
    local s=C.status(p)
    assert(s.active,s.message)
    local g=assert(s.tierGoal,s.message)
    assert(g.kind==kind and g.target==tier and g.current==current,s.message)
end
local function settles(p)
    for _=1,20 do
        step(p)
        if not C.status(p).active then return C.status(p) end
    end
    error("Expected settled mode: "..C.status(p).message)
end
for _,kind in ipairs({"Meditation","Yoga"}) do
    local option=ZenWellnessContextMenu.Options[kind]
    function option.onAction(_,self,p)
        assert(not head(p) and not p.nativeHead,"Native destructive clear must never run over another job")
        assert(p:isSitOnGround()==(kind=="Meditation"),"Native practice requires exact posture")
        assert(not self.canPerform(p),"Fresh native gate must precede every action")
        Q.clear(p)
        Q.add(T.action(p,kind,function()
            if p.finishPractice then p:finishPractice(kind) end
        end))
    end
end

local cases=0
local function test(name,fn) fn(); cases=cases+1; print("PASS "..name) end

test("explicit tier never clamps down, starts already-active or guesses unknown",function()
    local p=new(6,3)
    assert(not C.start(p,"meditateTo",false,3))
    assert(not C.start(p,"yogaTo",false,4))
    assert(not C.start(p,"meditateTo",false,nil))
    assert(not C.start(p,"meditateTo",false,1.5))
    nativeTier(p,"meditation",.4)
    local ok,reason=C.start(p,"meditateTo",false,1)
    assert(not ok and reason:find("already active",1,true))
    SandboxVars.Text.DividerMeditationNew=false
    assert(not C.start(p,"yogaTo",false,3))
    assert(not head(p) and #p.history==0 and #p.cards==0)
end)

test("Meditate To uses live tier, not displayed cache, XP or mere action completion",function()
    local p=new(10,0)
    begin(p,"meditateTo",2)
    local a=await(p,"Meditation")
    p.data.LSMoodles.MindfulState.Level=3
    nativeTier(p,"meditation",.2)
    p.xp=p.xp+200
    step(p)
    activeGoal(p,"meditation",2,1)
    assert(head(p)==a and C.status(p).cycle==nil)
    nativeTier(p,"meditation",.4)
    local s=settles(p)
    assert(s.phase=="complete" and s.message:find("Strong Mindfulness",1,true))
    assert(a.stopped and not a.autoMindfulFinished and count(p,"Meditation")==1 and #p.cards==1)
end)

test("Yoga To naturally repeats a failed pose session, then accepts a higher raw Zen tier",function()
    local p=new(0,6)
    begin(p,"yogaTo",3)
    local first=await(p,"Yoga")
    p.data.LSMoodles.Zen.Level=4
    step(p)
    assert(head(p)==first and not first.stopped)
    first:perform()
    local second=await(p,"Yoga")
    assert(second~=first)
    function p:finishPractice() nativeTier(self,"yoga",.75) end
    second:perform()
    local s=settles(p)
    assert(s.phase=="complete" and not second.stopped and count(p,"Yoga")==2 and count(p,"Meditation")==0)
end)

test("explicit Yoga To stops after four completed attempts without the tier",function()
    local p=new(0,6)
    begin(p,"yogaTo",4)
    for _=1,4 do await(p,"Yoga"):perform() end
    local s=settles(p)
    assert(s.phase=="stopped" and s.message:find("four completed",1,true) and count(p,"Yoga")==4)
end)

test("the tier stall budget excludes foreign work, but bounds stuck owned practice",function()
    local p=new(6,6)
    local foreign=T.action(p,"Workout")
    Q.add(foreign)
    begin(p,"yogaTo",4)
    step(p,500000)
    assert(C.status(p).active and head(p)==foreign and foreign.begins==1 and not foreign.stopped)
    foreign:perform()
    local a=await(p,"Yoga")
    for _=1,195 do
        step(p,2500)
        if not C.status(p).active then break end
    end
    local s=C.status(p)
    assert(not s.active and s.message:find("eight minutes",1,true) and a.stopped, s.message)
end)

test("capped Both owes the same selected tier through native misses and foreign handoffs",function()
    local p=new(10,10)
    config.capped.meditation=2
    p.data.AutoMindfulLastCompleted="yoga"
    begin(p,"both")
    local first=await(p,"Meditation")
    nativeTier(p,"meditation",.2)
    first:perform()
    local second=await(p,"Meditation")
    activeGoal(p,"meditation",2,1)
    assert(C.status(p).cycle.lastCompleted=="yoga" and C.status(p).cycle.due=="meditation")
    local foreign=T.action(p,"Workout")
    Q.add(foreign)
    step(p);step(p)
    assert(head(p)==foreign and foreign.begins==1 and not foreign.stopped and second.stopped)
    foreign:perform()
    local third=await(p,"Meditation")
    nativeTier(p,"meditation",.4)
    step(p)
    assert(third.stopped and not third.autoMindfulFinished)
    assert(C.status(p).cycle.lastCompleted=="meditation")
    assert(C.status(p).cycle.skills.meditation.completed==1,"Only native perform counts as physical completion")
    await(p,"Yoga")
    C.stop(p)
end)

test("below-cap Train Both clamps the rotation option per rank and keeps XP completion",function()
    local p=new(5,3)
    config.rotation.meditation=3
    p.data.AutoMindfulLastCompleted="yoga"
    begin(p,"both")
    local first=await(p,"Meditation")
    activeGoal(p,"meditation",1,0)
    first:perform()
    local second=await(p,"Meditation")
    nativeTier(p,"meditation",.2)
    step(p)
    assert(second.stopped and C.status(p).cycle.lastCompleted=="meditation")
    await(p,"Yoga")
    C.stop(p)

    local ender=new(9,10)
    config.rotation.meditation=3
    begin(ender,"both")
    local final=await(ender,"Meditation")
    ender.meditation=10
    final:perform()
    for _=1,20 do step(ender) end
    local status=C.status(ender)
    assert(status.active and status.mode=="recovery" and count(ender,"Meditation")==1)
    C.stop(ender)
end)

test("a pre-existing capped minimum keeps one native leg, not an empty rotation",function()
    local p=new(10,10)
    config.capped.meditation=1
    p.data.AutoMindfulLastCompleted="yoga"
    nativeTier(p,"meditation",.2)
    begin(p,"both")
    local a=await(p,"Meditation")
    step(p);step(p);step(p)
    assert(head(p)==a and not a.stopped and C.status(p).cycle.lastCompleted=="yoga")
    a:perform()
    await(p,"Yoga")
    assert(C.status(p).cycle.lastCompleted=="meditation")
    C.stop(p)
end)

test("already-satisfied pins allow cooperative rotation in either direction, including an owed leg",function()
    local p=new(10,10)
    config.capped.meditation,config.capped.yoga=2,2
    nativeTier(p,"meditation",.4); nativeTier(p,"yoga",.5)
    p.data.AutoMindfulLastCompleted="yoga"
    begin(p,"both")
    for _,kind in ipairs({"Meditation","Yoga"}) do
        for i=1,2 do
            local practice=await(p,kind)
            local foreign=T.action(p,"IndependentJob")
            Q.add(foreign); step(p)
            local native=foreign.action
            for _=1,6 do
                step(p)
                assert(head(p)==foreign and p.nativeHead==native and not foreign.autoMindfulOwner and foreign.begins==1 and not foreign.stopped)
            end
            assert(practice.stopped and not practice.autoMindfulFinished)
            foreign:perform()
        end
        local due=kind=="Meditation" and "yoga" or "meditation"
        local c=C.status(p).cycle
        assert(c.due==due and c.lastCompleted=="yoga" and p.data.AutoMindfulLastCompleted=="yoga")
        assert(c.skills.meditation.completed==0 and c.skills.yoga.completed==0)
    end
    await(p,"Meditation"); C.stop(p)
end)

test("optional tier failures keep normal capped practice and rearm after a setting change",function()
    local p=new(10,10)
    config.capped.meditation=1
    p.data.AutoMindfulLastCompleted="yoga"
    begin(p,"both")
    for _=1,4 do await(p,"Meditation"):perform() end
    local yoga=await(p,"Yoga")
    local s=C.status(p)
    assert(s.active and s.tierNotice:find("Continuing normal",1,true) and s.cycle.lastCompleted=="meditation")
    yoga:perform()
    local regular=await(p,"Meditation")
    assert(C.status(p).tierGoal==nil)
    regular:perform()
    yoga=await(p,"Yoga")
    config.capped.meditation=2
    yoga:perform()
    await(p,"Meditation")
    activeGoal(p,"meditation",2,0)
    C.stop(p)
end)

test("a newly impossible optional native gate or corrupt tier does not disarm training",function()
    local p=new(10,10)
    config.capped.yoga=4
    p.data.AutoMindfulLastCompleted="meditation"
    begin(p,"both")
    local first=await(p,"Yoga")
    first:perform()
    p.yogaBlocked="Tooltip_Yoga_MissingMat"
    await(p,"Meditation")
    assert(C.status(p).tierNotice:find("Lifestyle kept blocking",1,true))
    C.stop(p)

    p=new(10,10)
    config.capped.meditation=2
    p.data.AutoMindfulLastCompleted="yoga"
    begin(p,"both")
    local a=await(p,"Meditation")
    nativeTier(p,"meditation","unknown")
    step(p)
    assert(head(p)==a and not a.stopped and C.status(p).tierGoal==nil and C.status(p).tierNotice)
    a:perform()
    await(p,"Yoga")
    C.stop(p)
end)

test("Recovery minimum never starts idle buff work or continues after need resolves",function()
    local p=new(10,10)
    config.utility,config.recovery.meditation=true,2
    p.data.AutoMindfulLastCompleted="yoga"
    begin(p,"recovery")
    for _=1,12 do step(p) end
    assert(not head(p) and count(p,"Meditation")==0)
    p.values.STRESS=.8
    local a=await(p,"Meditation")
    nativeTier(p,"meditation",.2)
    p.values.STRESS=.6
    step(p)
    activeGoal(p,"meditation",2,1)
    assert(head(p)==a and not a.stopped,"A still-actionable need can continue to the configured tier")
    p.values.STRESS=.2
    step(p)
    for _=1,12 do step(p) end
    assert(a.stopped and C.status(p).active and not head(p) and count(p,"Meditation")==1)
    assert(C.status(p).cycle==nil and p.data.AutoMindfulLastCompleted=="yoga")
    C.stop(p)
end)

test("utility minima apply during training, with at most one fresh same-need retry",function()
    local p=new(5,6)
    config.utility,config.recovery.yoga=true,4
    p.data.AutoMindfulLastCompleted="meditation"
    p.values.BOREDOM=45
    begin(p,"meditation")
    local first=await(p,"Yoga")
    activeGoal(p,"yoga",4,0)
    first:perform()
    local retry=await(p,"Yoga")
    assert(retry~=first and count(p,"Yoga")==2 and C.status(p).cycle.lastCompleted=="meditation")
    retry:perform()
    for _=1,20 do step(p) end
    assert(count(p,"Yoga")==2 and C.status(p).cycle.skills.yoga.completed==0)
    C.stop(p)
end)

test("a naturally completed below-minimum Yoga utility is not retried after relief",function()
    local p=new(4,6)
    config.utility,config.recovery.yoga=true,4
    p.values.BOREDOM=45
    begin(p,"recovery")
    local first=await(p,"Yoga")
    function p:finishPractice() self.values.BOREDOM=0 end
    first:perform()
    for _=1,24 do step(p) end
    assert(C.status(p).active and not head(p) and count(p,"Yoga")==1)
    C.stop(p)
end)

test("direct urgent water wins even when a care tier is not met",function()
    local p=new(10,10)
    config.utility,config.recovery.meditation=true,3
    p.values.STRESS=.8
    T.add(p.inventory,T.water({thirst=-.8}))
    begin(p,"recovery")
    local a=await(p,"Meditation")
    p.values.THIRST,p.thirstMoodle=.45,4
    local drink=await(p,"drink")
    assert(a.stopped and not drink.stopped and C.status(p).tierGoal==nil)
    drink:perform()
    p.thirstMoodle=0
    C.stop(p)
end)

print("PASS "..cases.." runtime tier-goal contracts")
