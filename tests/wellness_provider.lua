AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
local T,C=AutoMindfulTest,AutoMindfulTest.controller
local Tiers=require "AutoMindful/TierTargets"
local Facts=require "AutoMindful/WellnessFacts"
local version=Facts.version
function getModInfoByID(id)
    assert(id=="LifestyleHobbies")
    return {getModVersion=function() return version end}
end
local function head(p) return ISTimedActionQueue.getTimedActionQueue(p).queue[1] end
local function coast(p,ticks) for i=1,ticks do T.tick(p,false) end end
do
    SandboxVars.Text={DividerMeditationNew=false}
    local p=T.playerNew()
    p.meditation,p.yoga,p.sitting=10,{10,0,100},true
    for _,mode in ipairs({"meditation","yoga","both","meditateTo","yogaTo"}) do
        local ok,reason=C.start(p,mode,false,1)
        assert(not ok and reason:find("disabled",1,true),mode)
    end
    assert(C.start(p,"recovery",false))
    p.values.THIRST=.4
    T.add(p.inventory,T.water())
    for i=1,8 do T.tick(p) end
    assert(T.hasHistory(p,"drink"),"Disabled Wellness does not stop ordinary recovery supplies")
    coast(p,3)
    assert(not T.hasHistory(p,"Meditation") and not T.hasHistory(p,"Yoga"))
    C.stop(p)
end
do
    SandboxVars.Text.DividerMeditationNew=true
    local p=T.playerNew(); p.meditation=6; p.yoga={3,0,750}
    function p:getPrimaryHandItem() return nil end
    function p:getSecondaryHandItem() return nil end
    p.data.LSMoodles.MindfulState.Value=.4
    assert(Tiers.current(p,"meditation")==2 and Tiers.clamp("meditation",2,6)==2)
    version="unknown"
    assert(not Tiers.current(p,"meditation") and Tiers.clamp("meditation",2,6)==0)
    p.values.BOREDOM=40
    assert(C.start(p,"recovery",false))
    coast(p,3)
    assert(head(p) and head(p).Type=="Yoga","An optional, observed native practice still works without pinned tier metadata")
    local action=head(p)
    SandboxVars.Text.DividerMeditationNew=false
    coast(p,2)
    assert(C.status(p).active and action.stopped,"Toggling the module stops its owned optional work without stopping Recovery")
    C.stop(p)
end
print("PASS Wellness module opt-out, and unverified version safely keeps native basics without numeric tiers")
