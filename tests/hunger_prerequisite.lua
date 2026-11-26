-- Real Controller admission and owned queue. The fixture, not AutoMindful,
-- delivers each native boredom/hunger effect.
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil

local T,C,Q=AutoMindfulTest,AutoMindfulTest.controller,ISTimedActionQueue
local Options=require "AutoMindful/Options"
local Facts=require "AutoMindful/WellnessFacts"
local enabled=true
Options.practiceCare=function() return enabled end
function getModInfoByID(id) if id=="LifestyleHobbies" then return {getModVersion=function() return Facts.version end} end end
SandboxVars.Text={DividerMeditationNew=true}

local function head(p) return Q.getTimedActionQueue(p).queue[1] end
local function step(p,ms) T.now=T.now+(ms or 250); C.update(p) end
local function steps(p,n) for i=1,n do step(p) end end
local function player(mode)
    local p=T.playerNew()
    p.sitting,p.meditation,p.yoga=true,6,{4,0,100}
    p.values.HUNGER,p.hungerMoodle,p.values.BOREDOM=.8,4,38
    p.nativeMeditationBoredomLimit=32
    p.data.AutoMindfulLastCompleted="meditation"
    function p:getPrimaryHandItem() return nil end
    function p:getSecondaryHandItem() return nil end
    function p:getBodyDamage()
        return {getOverallBodyHealth=function() return p.health or 100 end,getNumPartsBleeding=function() return p.bleeding or 0 end}
    end
    local ok,reason=C.start(p,mode,false)
    assert(ok,reason)
    return p
end
local function untilHead(p,kind)
    for _=1,40 do
        step(p)
        local action=head(p)
        if action then
            if action.Type==kind then return action end
            assert(action.Type=="stand","Expected "..kind..", got "..action.Type.." ("..C.status(p).message..")")
            action:perform()
        end
        assert(C.status(p).active,C.status(p).message)
    end
    error("No "..kind..": "..C.status(p).message)
end
local function count(p,kind)
    local n=0; for _,k in ipairs(p.history) do if k==kind then n=n+1 end end
    return n
end
local function noCredit(p)
    local cycle=C.status(p).cycle
    if cycle then
        assert(cycle.lastCompleted=="meditation" and cycle.skills.yoga.started==0 and cycle.skills.meditation.started==0
            and cycle.skills.yoga.completed==0 and cycle.skills.meditation.completed==0)
    end
    assert(p.calories==2000 and count(p,"eat")==0)
end
local function confirmNative(p)
    local m=untilHead(p,"Meditation")
    assert(C.status(p).phase=="practice-care" and m.autoMindfulOwner and p.values.HUNGER==.8)
    p.data.LSMoodles.MindfulState.Value=.4
    step(p)
    assert(m.stopped and not head(p) and p.values.HUNGER==.8)
    p.values.HUNGER=.72
    step(p)
    assert((C.status(p).careNotice or ""):find("hunger ease",1,true),"Only the witnessed native hunger drop counts")
    noCredit(p)
end

for _,mode in ipairs({"recovery","both"}) do
    local p=player(mode)
    T.add(p.inventory,T.item("Literature",{boredom=-25,data={literatureTitle="HungerPrerequisiteFixture"}}))
    local book=untilHead(p,"read")
    assert(p.values.BOREDOM==38 and count(p,"Yoga")==0 and p.values.HUNGER==.8)
    book:perform()
    assert(p.values.BOREDOM<32 and p.values.HUNGER==.8)
    confirmNative(p)
    assert(count(p,"read")==1 and count(p,"Yoga")==0)
    C.stop(p)
end
print("PASS owned eligible book unlocks native starvation Meditation in Autopilot and training")

do
    local p=player("both")
    local yoga=untilHead(p,"Yoga")
    steps(p,4)
    assert(head(p)==yoga and not yoga.stopped and C.status(p).phase=="practice-care",
        "Existing hunger must not kill the one Yoga course that can unblock its own relief")
    noCredit(p)
    yoga:perform()
    assert(p.values.BOREDOM==23 and p.values.HUNGER==.8)
    confirmNative(p)
    assert(count(p,"Yoga")==1 and count(p,"Meditation")==1)
    C.stop(p)
end
print("PASS bounded native Yoga clears tracker-specific boredom without paying a training turn")

do
    local p=player("recovery")
    local yoga=untilHead(p,"Yoga")
    -- Model the game's boredom flush from a successful pose before the
    -- Yoga action's terminal phase. Never wait out the full routine once
    -- the native gate confirms that the prerequisite has cleared.
    p.values.BOREDOM=32
    step(p)
    assert(yoga.stopped and not head(p) and p.values.HUNGER==.8)
    confirmNative(p)
    C.stop(p)
end
print("PASS native boredom flush can hand off to hunger Meditation before Yoga finishes")

do
    local p=player("recovery")
    local yoga=untilHead(p,"Yoga")
    step(p,500000)
    assert(yoga.stopped and p.values.BOREDOM==38 and p.values.HUNGER==.8)
    for _=1,10 do step(p,200000) end
    assert(not head(p) and count(p,"Yoga")==1 and count(p,"Meditation")==0)
    assert(C.status(p).message:find("Boredom",1,true),C.status(p).message)
    C.stop(p)
end
print("PASS failed or timed-out Yoga cannot loop during the same starvation episode")

do
    local p=player("recovery")
    local yoga=untilHead(p,"Yoga")
    p.values.THIRST,p.thirstMoodle=.6,4
    T.add(p.inventory,T.water({thirst=-.8}))
    local drink=untilHead(p,"drink")
    assert(yoga.stopped and drink.autoMindfulOwner and p.values.BOREDOM==38)
    C.stop(p)
end
print("PASS newly critical thirst preempts hunger-prerequisite Yoga")

for _,why in ipairs({"disabled","rank","nativeYoga","health","bleeding"}) do
    local p=player("recovery")
    if why=="disabled" then enabled=false
    elseif why=="rank" then p.meditation=5
    elseif why=="nativeYoga" then p.yogaBlocked=getText("Tooltip_Action_Exhausted")
    elseif why=="health" then p.health=49
    else p.bleeding=1 end
    steps(p,16)
    assert(C.status(p).active and not head(p) and count(p,"Yoga")==0 and count(p,"Meditation")==0,why)
    C.stop(p); enabled=true
end
print("PASS low HP, real danger, rank, disabled practice or native Yoga gate never force Yoga")
