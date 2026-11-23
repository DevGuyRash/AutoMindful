-- These receipts run the real controller. With game media, dispatch the
-- unmodified stock floor sleep callbacks behind explicit engine doubles.
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
local T,C,Q=AutoMindfulTest,AutoMindfulTest.controller,ISTimedActionQueue
local Options=require "AutoMindful/Options"
local Facts=require "AutoMindful/WellnessFacts"
Options.practiceCare=function() return true end
Options.minimumTier=function(group,kind) return group=="recovery" and kind=="meditation" and 1 or 0 end
function getModInfoByID(id) if id=="LifestyleHobbies" then return {getModVersion=function() return Facts.version end} end end
MoodleType.PANIC,MoodleType.NOXIOUS_SMELL="panic","smell"
for _,stat in ipairs({"POISON","SICKNESS","FOOD_SICKNESS","ZOMBIE_INFECTION","ZOMBIE_FEVER","INTOXICATION"}) do
    CharacterStat[stat]=stat
end
SandboxVars.Text={DividerMeditationNew=true}
SandboxVars.LS={MoodUpdate=2}

local function noop() end
HaloTextHelper={addBadText=function(_,key) error("Controller reached a known stock refusal: "..tostring(key)) end}
FitnessState={instance=function() return "FitnessState" end}
GameTime={getInstance=function() return {getTimeOfDay=function() return 18 end} end}
UIManager={setFadeBeforeUI=noop,FadeOut=noop}
IsoPlayer={allPlayersAsleep=function() return false end}
function getSleepingEvent() return {setPlayerFallAsleep=noop} end
function ZombRand(min) return min end
function string:contains(part) return self:find(part,1,true)~=nil end
if not loadUpstream and arg and arg[1] then
    function loadUpstream(name) return assert(loadfile(arg[1].."/lua/"..name))() end
end
if loadUpstream then
    Events.OnPressWalkTo={Add=noop}
    loadUpstream("client/ISUI/ISWorldObjectContextMenu.lua")
    ISWorldObjectContextMenu.getBedQuality=function(_,bed) assert(bed==nil); return "floor" end
else
    function ISWorldObjectContextMenu.onSleepWalkToComplete(_,bed)
        assert(bed==nil)
        local p=T.player
        if p.fixtureRefuse then return end
        assert(p:getVariableBoolean("ExerciseEnded"),"Stock callback refuses unfinished/absent ExerciseEnded")
        Q.clear(p)
        p:setAsleep(true)
    end
    function ISWorldObjectContextMenu.onConfirmSleep(_,button,slot,bed)
        assert(button.internal=="YES")
        T.player:setVariable("ExerciseStarted",false)
        T.player:setVariable("ExerciseEnded",true)
        Q.clear(T.player)
        ISWorldObjectContextMenu.onSleepWalkToComplete(slot,bed)
    end
end
local stockConfirm,stockComplete=ISWorldObjectContextMenu.onConfirmSleep,ISWorldObjectContextMenu.onSleepWalkToComplete
local inStock=false
function ISWorldObjectContextMenu.onConfirmSleep(...)
    local p=T.player
    assert(p.exerciseEnded==nil and not p.exerciseStarted and not p.fitness)
    assert(p:isLocalPlayer() and #Q.getTimedActionQueue(p).queue==0 and p:getCharacterActions():isEmpty())
    p.nativeConfirm=(p.nativeConfirm or 0)+1
    inStock=true
    stockConfirm(...)
    inStock=false
end
function ISWorldObjectContextMenu.onSleepWalkToComplete(...)
    local p=T.player
    assert(#Q.getTimedActionQueue(p).queue==0 and p:getCharacterActions():isEmpty())
    p.nativeSleep=(p.nativeSleep or 0)+1
    if not p.fixtureRefuse then stockComplete(...) end
end

local function head(p) return Q.getTimedActionQueue(p).queue[1] end
local function step(p,ms) T.now=T.now+(ms or 250); C.update(p) end
local function steps(p,n) for _=1,n do step(p) end end
local function new(rank)
    local p=T.playerNew()
    p.sitting,p.meditation,p.yoga=true,rank or 0,{0,0,100}
    p.values.FATIGUE,p.exerciseEnded,p.health=.65,true,85
    p.painMoodle,p.panicMoodle,p.smellMoodle=0,0,0
    function p:getPrimaryHandItem() return nil end
    function p:getSecondaryHandItem() return nil end
    function p:getSleepingTabletEffect() return self.tablet or 0 end
    function p:getPainEffect() return self.painEffect or 0 end
    function p:getPainDelta() return self.painDelta or 0 end
    function p:isCurrentState(state) return state=="FitnessState" and self.fitness==true end
    function p:getVariableBoolean(key)
        assert(key=="ExerciseEnded" or key=="ExerciseStarted")
        if key=="ExerciseEnded" then return self.exerciseEnded==true end
        return self.exerciseStarted==true
    end
    function p:getVariableString(key)
        assert(key=="ExerciseEnded")
        return self.exerciseEnded==nil and "" or tostring(self.exerciseEnded)
    end
    function p:setVariable(key,value)
        assert(inStock,"AutoMindful must never write exercise flags")
        if key=="ExerciseEnded" then self.exerciseEnded=value else self.exerciseStarted=value end
        self.nativeFlagWrites=(self.nativeFlagWrites or 0)+1
    end
    local original=p.getMoodles
    function p:getMoodles()
        local md=original(self)
        local get=md.getMoodleLevel
        function md:getMoodleLevel(k)
            if k==MoodleType.PANIC then return p.panicMoodle end
            if k==MoodleType.NOXIOUS_SMELL then return p.smellMoodle end
            return get(self,k)
        end
        return md
    end
    local body={getOverallBodyHealth=function() return p.health end,getNumPartsBleeding=function() return 0 end,
        isInfected=function() return false end,getNumPartsBitten=function() return 0 end}
    function p:getBodyDamage() return body end
    function p:setAsleep(value) self.asleep=value end
    function p:setBed(bed) assert(bed==nil) end
    function p:setBedType(kind) assert(kind=="floor") end
    function p:setForceWakeUpTime(value) assert(type(value)=="number") end
    function p:setAsleepTime(t) assert(t==0) end
    return p
end
local function start(p,mode)
    local ok,why=C.start(p,mode,false)
    assert(ok,why)
end
local function await(p,kind)
    for _=1,36 do
        step(p)
        local a=head(p)
        if a then assert(a.Type==kind,"Wanted "..kind..", got "..a.Type); return a end
        assert(C.status(p).active,C.status(p).message)
    end
    error("Did not admit "..kind.."; "..C.status(p).message)
end
local function slept(p,viaConfirmation)
    steps(p,12)
    assert(p:isAsleep() and p.nativeSleep==1 and not head(p),C.status(p).message)
    assert((p.nativeConfirm==1)==viaConfirmation and (p.nativeFlagWrites==2)==viaConfirmation)
    C.stop(p)
end

do
    local p=new()
    p.values.PANIC=2  -- stock Panic moodle is still absent
    start(p,"yoga"); slept(p,false)
    p=new()
    p.exerciseEnded=nil
    start(p,"recovery"); slept(p,true)
    p=new()
    p.tablet,p.painMoodle,p.panicMoodle=2000,2,1
    p.values.PAIN,p.values.PANIC=40,25
    start(p,"recovery"); slept(p,false)
    p=new()
    p.painMoodle,p.values.FATIGUE=2,.86
    start(p,"recovery"); slept(p,false)
end
print("PASS raw panic is not a native blocker; absent exercise flag uses vanilla admission, tablet and fatigue exceptions apply")

for _,block in ipairs({"panic","pain","exercise","started","fitness","cooldown","smell","refusal"}) do
    local p=new()
    if block=="panic" then p.panicMoodle,p.values.PANIC=1,6
    elseif block=="pain" then p.painMoodle,p.values.FATIGUE=2,.85
    elseif block=="exercise" then p.exerciseEnded=false
    elseif block=="started" then p.exerciseStarted=true
    elseif block=="fitness" then p.exerciseEnded=nil; p.fitness=true
    elseif block=="cooldown" then p.hours=1
    elseif block=="smell" then p.smellMoodle=1
    elseif block=="refusal" then p.fixtureRefuse=true end
    start(p,"recovery"); steps(p,14); step(p,35000); steps(p,12)
    assert(C.status(p).phase=="recovering" and not p:isAsleep() and not head(p),block..": "..C.status(p).message)
    assert((p.nativeSleep or 0)==(block=="refusal" and 1 or 0) and not p.nativeFlagWrites and not p.nativeConfirm,block)
    C.stop(p)
end
print("PASS stock refusal gates do not force sleeps or spam callbacks")

for _,mode in ipairs({"both","recovery"}) do
    local p=new(6)
    p.painMoodle,p.values.PAIN,p.values.HUNGER=2,31,.31
    local food=T.add(p.inventory,T.item("Food",{hunger=-.8,baseHunger=-.8,calories=420}))
    local pill=T.add(p.inventory,T.item("DrainableComboItem",{fullType="Base.Pills",uses=4}))
    function pill:getCurrentUses() return self.uses end
    function pill:getUseDelta() return .1 end
    function pill:getOnEat() return nil end
    local take=ISInventoryPaneContextMenu.takePill
    ISInventoryPaneContextMenu.takePill=function(item,slot)
        assert(item==pill and slot==p:getPlayerNum())
        local a=T.action(p,"ISTakePillAction",function()
            p.painEffect,p.painDelta,p.painMoodle,p.values.PAIN=5400,.3,0,5
            item.uses=item.uses-1
        end)
        a.item=item; Q.add(a)
    end
    start(p,mode)
    local eat=await(p,"eat")
    eat:perform()
    assert(food and p.calories>2000 and not p.nativeSleep and pill.uses==4)
    local dose=await(p,"ISTakePillAction")
    dose:perform()
    assert(pill.uses==3)
    slept(p,false)
    ISInventoryPaneContextMenu.takePill=take
end
print("PASS confirmed meal then exact native painkiller receipt before admissible sleep in Both and Recovery")

do
    local p=new(3)
    p.panicMoodle,p.values.PANIC=1,6
    p.data.AutoMindfulLastCompleted="yoga"
    start(p,"meditation")
    local meditation=await(p,"Meditation")
    assert(C.status(p).phase=="practice-care" and C.status(p).cycle.skills.meditation.started==0 and not p.nativeSleep)
    p.data.LSMoodles.MindfulState.Value=.2
    step(p); assert(meditation.stopped and not head(p))
    p.panicMoodle,p.values.PANIC=0,2
    slept(p,false)
end
print("PASS native panic blocked sleep gets bounded utility before waiting, without crediting a training turn")

do
    local p=new()
    p.exerciseEnded=nil
    local job=T.action(p,"ISFitnessAction",function() p.exerciseEnded=true end)
    Q.add(job)
    start(p,"recovery"); steps(p,12)
    assert(head(p)==job and p.nativeHead==job.action and job.begins==1 and not job.stopped and not p.nativeSleep)
    job:perform()
    slept(p,false)
end
print("PASS existing workout and native handle are never canceled for sleep")

local function readyHealth(healFactor,badge)
    local p=new(10)
    p.values.FATIGUE=0
    p.data.LSMoodles.MindfulState.Value=badge or 0
    SandboxVars.Meditation.HealFactor=healFactor
    return p
end
do
    local p=readyHealth(0,0)
    start(p,"recovery"); steps(p,24)
    assert(C.status(p).active and not head(p) and p.health==85)
    C.stop(p)
    p=readyHealth(0,.6)
    start(p,"recovery"); steps(p,10)
    p.health=88 -- unrelated healing must not be credited to an effect set to zero
    steps(p,10)
    assert(not head(p) and not (C.status(p).careNotice or ""):find("health improve",1,true))
    C.stop(p)
    p=readyHealth(2,.4)
    start(p,"recovery")
    local a=await(p,"Meditation")
    assert(C.status(p).phase=="practice-care")
    SandboxVars.Meditation.HealFactor=0
    step(p)
    assert(a.stopped and not head(p))
    C.stop(p)
    p=readyHealth(0,0); p.values.HUNGER=.38
    start(p,"recovery")
    local hunger=await(p,"Meditation")
    p.data.LSMoodles.MindfulState.Value=.4
    step(p)
    assert(hunger.stopped and not head(p))
    p.values.HUNGER=.34
    step(p)
    assert((C.status(p).careNotice or ""):find("hunger ease",1,true) and p.calories==2000)
    C.stop(p)
end
print("PASS zero HealFactor suppresses Perfect utility and false receipts, not Strong hunger relief")
