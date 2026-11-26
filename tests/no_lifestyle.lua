-- Without Lifestyle: Hobbies, Autopilot still starts, drinks and eats, and
-- Yoga and Meditation say what they need instead of breaking.
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
local T,C,Q=AutoMindfulTest,AutoMindfulTest.controller,ISTimedActionQueue
local Presence=require "AutoMindful/Presence"
for key,value in pairs(T.presencePolicy) do Presence.policy[key]=value end
function getGameSpeed() return 1 end
BehaviorResult={Failed="Failed",Succeeded="Succeeded"}
CharacterStat.STRESS,CharacterStat.UNHAPPINESS="STRESS","UNHAPPINESS"
function getSoundManager() return {playUISound=function() end} end
HiddenSkills,ZenWellnessContextMenu,Perks.Meditation=nil,nil,nil
local function queue(p) return Q.getTimedActionQueue(p).queue end
local function step(p,n) for _=1,n or 1 do T.now=T.now+250; C.update(p) end end
local function survivor()
    local p=T.playerNew(); p.sitting=true
    function p:getPrimaryHandItem() end
    function p:getSecondaryHandItem() end
    return p
end

do
    local p=survivor()
    local ok,message=C.start(p,"yoga",false)
    assert(not ok and tostring(message):find("Lifestyle",1,true),"Yoga names what it needs: "..tostring(message))
    ok,message=C.start(p,"meditation",false)
    assert(not ok and tostring(message):find("Lifestyle",1,true),"Meditation names what it needs: "..tostring(message))
    print("PASS yoga and meditation explain the missing mod")
end
do
    local p=survivor()
    local bottle=T.add(p.inventory,T.water({thirst=-.8}))
    p.values.THIRST,p.thirstMoodle=.3,2
    assert(C.start(p,"recovery",false))
    step(p,16)
    assert(queue(p)[1] and queue(p)[1].Type=="drink","Autopilot drinks without Lifestyle: "..C.status(p).message)
    queue(p)[1]:perform(); p.thirstMoodle=0
    assert(bottle.fluid:getAmount()<1)
    step(p,200)
    assert(C.status(p).active,"Autopilot keeps running: "..C.status(p).message)
    C.stop(p)
    print("PASS autopilot runs without Lifestyle")
end
