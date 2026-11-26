-- The controller, supplies, and relief policy are real. Engine, queue and
-- Lifestyle effects are explicit fixture boundaries. Never write a stat to
-- simulate an AutoMindful effect; fixture changes represent native readbacks.
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
local T,C,Q=AutoMindfulTest,AutoMindfulTest.controller,ISTimedActionQueue
local Options=require "AutoMindful/Options"
local Facts=require "AutoMindful/WellnessFacts"
local Nearby=require "AutoMindful/Nearby"
local provider=Facts.version
Options.practiceCare=function() return true end
function getModInfoByID(id) if id=="LifestyleHobbies" and provider then return {getModVersion=function() return provider end} end end
SandboxVars.Text={DividerMeditationNew=true}
CharacterStat.STRESS,CharacterStat.UNHAPPINESS="STRESS","UNHAPPINESS"
CharacterStat.NICOTINE_WITHDRAWAL,CharacterTrait.SMOKER="NICOTINE_WITHDRAWAL","smoker"

local function head(p) return Q.getTimedActionQueue(p).queue[1] end
local function step(p,ms) T.now=T.now+(ms or 250); C.update(p) end
local function steps(p,count) for i=1,count do step(p) end end
local function start(p,mode) local ok,why=C.start(p,mode or "recovery",false); assert(ok,why) end
local function count(p,action)
    local seen=0; for _,name in ipairs(p.history) do if name==action then seen=seen+1 end end
    return seen
end
local function new(rank,yoga)
    local p=T.playerNew()
    p.meditation,p.yoga,p.sitting=rank or 0,{yoga or 0,0,100},true
    p.data.AutoMindfulLastCompleted="meditation"
    function p:getPrimaryHandItem() return nil end
    function p:getSecondaryHandItem() return nil end
    local parts={{getStiffness=function() return p.stiffness or 0 end}}
    local body={getBodyParts=function() return T.list(parts) end,getOverallBodyHealth=function() return 100 end,
        getNumPartsBleeding=function() return 0 end}
    function p:getBodyDamage() return body end
    return p
end
local function await(p,kind)
    for i=1,42 do
        step(p); local action=head(p)
        if action then
            if action.Type==kind then return action end
            assert(action.Type=="stand","Wanted "..kind..", got "..action.Type)
            action:perform()
        end
        assert(C.status(p).active,C.status(p).message)
    end
    error("Missing "..kind..": "..C.status(p).message)
end
local function noLedger(p)
    assert(C.status(p).active and C.status(p).cycle==nil and p.data.AutoMindfulLastCompleted=="meditation" and #p.cards==0)
end

do
    local p=new(10,10)
    p.sitting,p.values.ENDURANCE=false,.82
    start(p); steps(p,18)
    assert(p.sitting and p.postureEvents==1 and C.status(p).phase=="resting","Autopilot should sit at an ordinary meaningful deficit")
    for _,value in ipairs({.88,.96,.9999,1}) do
        p.values.ENDURANCE=value; p.hours=p.hours+1; steps(p,12)
        assert(C.status(p).phase==(value==1 and "recovery-idle" or "resting"))
        assert(p.values.ENDURANCE==value and p.postureEvents==1 and not head(p) and #p.history==0)
        noLedger(p)
    end
    C.stop(p)
    local retry=new()
    retry.sitting,retry.values.ENDURANCE=false,.4
    function retry:reportEvent(name) assert(name=="EventSitOnGround"); self.requests=(self.requests or 0)+1 end
    start(retry); steps(retry,220)
    assert(retry.requests==1 and not head(retry) and retry.values.ENDURANCE==.4,"Declined posture must not be spammed")
    C.stop(retry)
    local tiny=new()
    tiny.sitting,tiny.values.ENDURANCE=false,.995
    start(tiny); steps(tiny,25)
    assert(not tiny.postureEvents and not head(tiny) and C.status(tiny).phase=="resting")
    C.stop(tiny)
end
print("PASS persistent Autopilot leaves native endurance to reach exact full with one posture request or no churn near full")

do
    local p=new()
    p.values.HUNGER,p.values.THIRST=.099,.099
    local food=T.add(p.inventory,T.item("Food",{hunger=-.8,baseHunger=-.8,calories=500}))
    local water=T.add(p.inventory,T.water({thirst=-.8}))
    local volume=water.fluid:getAmount()
    start(p); steps(p,15)
    assert(not head(p) and #p.history==0)
    p.values.HUNGER,p.values.THIRST=.10,.10
    local drink=await(p,"drink")
    drink:perform()
    assert(water.fluid:getAmount()<volume and p.values.THIRST<.1)
    p.values.THIRST=.014 -- small native drift following a real drink receipt
    local eat=await(p,"eat"); eat:perform()
    steps(p,12)
    assert(not head(p) and count(p,"drink")==1 and count(p,"eat")==1 and p.calories>2000 and food:getHungerChange()>-.8)
    assert(p.values.THIRST==.014 and p.values.HUNGER<.10)
    noLedger(p); C.stop(p)
    local normal=new()
    normal.values.HUNGER,normal.values.THIRST=.10,.10
    T.add(normal.inventory,T.water({thirst=-.8}))
    T.add(normal.inventory,T.item("Food",{hunger=-.8,baseHunger=-.8,calories=500}))
    start(normal,"meditation"); await(normal,"Meditation")
    assert(count(normal,"drink")==0 and count(normal,"eat")==0); C.stop(normal)
end
print("PASS early confirmed food/water with exact native consumption, not microsips, and unchanged normal training threshold")

do
    local p=new(6)
    p.values.HUNGER=.12
    start(p); steps(p,20)
    assert(not head(p) and count(p,"Meditation")==0,"A mild lack of food should not spend minutes acquiring a new hunger buff")
    p.values.HUNGER=.16
    local meditation=await(p,"Meditation")
    assert(C.status(p).phase=="practice-care")
    p.data.LSMoodles.MindfulState.Value=.4; step(p)
    p.values.HUNGER=.12; step(p)
    assert(meditation.stopped and not head(p) and (C.status(p).careNotice or ""):find("hunger ease",1,true))
    noLedger(p); C.stop(p)
end
print("PASS native Strong hunger fallback still requires a meaningful need, real tier, and real stat readback")

do
    local p=new(6,4)
    p.values.BOREDOM=16
    local book=T.add(p.inventory,T.item("Literature",{boredom=-15,data={literatureTitle="EarlyReading"}}))
    start(p); local read=await(p,"read");read:perform()
    assert(p.inventory:contains(book) and p.read.EarlyReading==T.nights and p.values.BOREDOM==1)
    noLedger(p); C.stop(p)
    for _,input in ipairs({{"PANIC",12,3,"Meditation"},{"STRESS",.31,0,"Meditation"},
            {"NICOTINE_WITHDRAWAL",.25,0,"Meditation"},{"UNHAPPINESS",21,0,"Meditation"},
            {"BOREDOM",18,0,"Yoga"},{"stiffness",10,0,"Yoga"}}) do
        local a=new(input[3],4)
        if input[1]=="stiffness" then a.stiffness=input[2] else a.values[input[1]]=input[2] end
        a.traits.smoker=input[1]=="NICOTINE_WITHDRAWAL"
        start(a)
        await(a,input[4])
        assert(C.status(a).phase=="practice-care"); noLedger(a); C.stop(a)
    end
end
print("PASS earlier real reading, panic, stress, smoker withdrawal, unhappiness, boredom and body-part stiffness")

do
    for _,blocked in ipairs({"provider","boredom","pain","non-smoker","native"}) do
        local p=new()
        if blocked=="provider" then provider=nil; p.values.UNHAPPINESS=30
        elseif blocked=="boredom" then p.values.UNHAPPINESS,p.values.BOREDOM=30,8
        elseif blocked=="pain" then p.values.UNHAPPINESS,p.values.PAIN=30,6
        elseif blocked=="non-smoker" then p.values.NICOTINE_WITHDRAWAL=.27
        else p.values.UNHAPPINESS,p.nativeMeditationBoredomLimit=30,-1 end
        start(p); steps(p,24); assert(not head(p) and #p.history==0,blocked)
        C.stop(p); provider=Facts.version
    end
    local p=new(3,4); p.values.UNHAPPINESS=30
    start(p)
    local meditation=await(p,"Meditation")
    p.values.BOREDOM=7
    step(p)
    assert(meditation.stopped and p.values.UNHAPPINESS==30 and not head(p)
        and not (C.status(p).careNotice or ""):find("showed relief",1,true))
    C.stop(p)
end
print("PASS no presumed Unhappiness effect at unknown provider or in uncomfortable or native-blocked context")

do
    local p=new()
    p.sitting=false
    p.values.HUNGER,p.values.STRESS=.16,.65
    local far=T.square(6,0)
    local walk=0
    local prior,use=Nearby.find,Options.searchNearby
    local unknown=false
    Options.searchNearby=function() return true end
    Nearby.find=function(_,kind)
        if kind~="food" then return end
        return {unknown=unknown,key="food:6:0:0",square=far}
    end
    function getGameSpeed() return 1 end
    luautils={walkAdj=function(player,square,keep)
        assert(player==p and square==far and keep)
        walk=walk+1; Q.add(T.action(p,"ISWalkToTimedAction")); return true
    end}
    start(p);steps(p,8)
    assert(walk==0 and not head(p),"Do not scout or churn practice on the first short idle gap when a confirmed supply can still win")
    local foreign=T.action(p,"ForeignTreeChop")
    Q.add(foreign); steps(p,16)
    assert(head(p)==foreign and foreign.action==p.nativeHead and foreign.begins==1 and not foreign.stopped and walk==0)
    foreign:perform(); steps(p,8)
    assert(not head(p) and walk==0,"A foreign action resets low-priority travel grace")
    await(p,"ISWalkToTimedAction")
    assert(walk==1); C.stop(p)
    unknown=true
    local other=new()
    other.sitting=false; other.values.HUNGER,other.values.THIRST=.12,.12
    T.client=true; start(other); steps(other,32)
    assert(not head(other) and C.status(other).phase=="recovery-idle" and walk==1)
    C.stop(other); T.client=false
    Nearby.find,Options.searchNearby=prior,use
end
print("PASS mild known stock waits out idle grace and player work; no speculative travel for trivial needs")

do
    local p=new(6)
    p.values.HUNGER,p.values.THIRST,p.values.FATIGUE=.12,.12,.65
    T.add(p.inventory,T.water({thirst=-.8}))
    T.add(p.inventory,T.item("Food",{hunger=-.8,baseHunger=-.8,calories=500}))
    start(p)
    for _=1,40 do
        step(p)
        if head(p) then head(p):perform() end
        if p:isAsleep() then break end
    end
    assert(p:isAsleep() and not head(p) and T.hasHistory(p,"eat") and T.hasHistory(p,"drink"),
        "A sip and a bite before eight hours without either, then sleep")
    C.stop(p)
    p=new()
    p.values.STRESS=.35
    start(p)
    local relaxing=await(p,"Meditation")
    p.values.THIRST=.12
    T.add(p.inventory,T.water({thirst=-.8}))
    steps(p,7)
    assert(head(p)==relaxing and not relaxing.stopped,"Mild preventive water may not break a useful active practice")
    p.values.THIRST=.16
    local drink=await(p,"drink")
    assert(relaxing.stopped and not relaxing.autoMindfulFinished)
    drink:perform(); C.stop(p)
end
print("PASS a small need is met before sleep but never breaks an ongoing relief action; ordinary water still wins")
