-- Recovery left in charge: who is at the controls, how dangerous it is, what
-- may be done about which need, and that it never quietly gives up. Waiting
-- times here are the production ones.
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
local T,C,Q=AutoMindfulTest,AutoMindfulTest.controller,ISTimedActionQueue
local N,O,Presence=require "AutoMindful/Nearby",require "AutoMindful/Options",require "AutoMindful/Presence"
local Facts=require "AutoMindful/WellnessFacts"
for key,value in pairs(T.presencePolicy) do Presence.policy[key]=value end
function getModInfoByID() return {getModVersion=function() return Facts.version end} end
function getGameSpeed() return 1 end
BehaviorResult={Failed="Failed",Succeeded="Succeeded"}
CharacterStat.STRESS,CharacterStat.UNHAPPINESS="STRESS","UNHAPPINESS"
O.practiceCare=function() return true end
local scout=false
O.searchNearby=function() return scout end
ISWalkToTimedAction={new=function(_,p) return T.action(p,"ISWalkToTimedAction") end}
luautils={walkAdj=function(p) Q.add(ISWalkToTimedAction:new(p)); return true end}
local sounds={}
function getSoundManager() return {playUISound=function(_,name) sounds[#sounds+1]=name end} end
local function queue(p) return Q.getTimedActionQueue(p).queue end
local function step(p,n,ms) for _=1,n or 1 do T.now=T.now+(ms or 250); C.update(p) end end
local function count(p,kind) local n=0; for _,k in ipairs(p.history) do if k==kind then n=n+1 end end; return n end
local function passed(text) print("PASS "..text) end
local function survivor()
    local p=T.playerNew()
    p.sitting=true
    function p:getPrimaryHandItem() end
    function p:getSecondaryHandItem() end
    return p
end
local function begin(p) assert(C.start(p,"recovery",false)) end
local function seconds(p,s) step(p,s*4) end
local function issue(p,id) for _,i in ipairs(C.outlook(p).issues) do if i.id==id then return i end end end
local function alerted(p,text) for _,a in ipairs(p.alerts) do if a.detail:find(text,1,true) then return true end end return false end

-- Presence ------------------------------------------------------------------
do
    local p=survivor(); p.sitting=false
    p.values.ENDURANCE=.5
    begin(p)
    seconds(p,8)
    assert(not p.sitting,"Someone thinking for a few seconds is not sat down")
    seconds(p,6)
    assert(p.sitting,"Left alone, the survivor rests")
    C.stop(p)
end
do
    -- The second moodle is worth a short walk sooner than the first.
    scout=true
    local find=N.find
    local shelf=T.container(6,0)
    N.find=function(_,kind) if kind=="water" then return {key="water:6",square=shelf.square,container=shelf} end end
    local function waits(moodle)
        local p=survivor(); p.values.THIRST,p.thirstMoodle=.3,moodle
        begin(p)
        for tenth=1,200 do step(p,1); if count(p,"ISWalkToTimedAction")>0 then C.stop(p); return tenth/4 end end
        C.stop(p)
    end
    local first,second,third=waits(1),waits(2),waits(3)
    assert(third<second and second<first,tostring(third).." "..tostring(second).." "..tostring(first))
    assert(third<4 and second>=5 and first>=15)
    -- A hand on the mouse is someone who is there.
    local p=survivor(); p.values.THIRST,p.thirstMoodle=.3,1
    local x=0
    function getMouseX() return x end
    function getMouseY() return 0 end
    begin(p)
    for _=1,160 do x=x+1; step(p,1) end
    assert(count(p,"ISWalkToTimedAction")==0,"Nobody is walked off while they use the mouse")
    seconds(p,20)
    assert(count(p,"ISWalkToTimedAction")==1)
    C.stop(p)
    getMouseX,getMouseY=nil,nil
    -- A need the game does not even show is only worth a walk for someone away.
    p=survivor(); p.values.THIRST=.12
    begin(p); seconds(p,100)
    assert(count(p,"ISWalkToTimedAction")==0)
    C.setAway(p,true); seconds(p,3)
    assert(count(p,"ISWalkToTimedAction")==1 and C.status(p).away,"Going AFK starts full care now")
    C.stop(p)
    N.find=find; scout=false
end
do
    local p=survivor(); begin(p)
    C.setAway(p,true); assert(C.status(p).away)
    p.movementInput=true; step(p); p.movementInput=false; step(p)
    assert(not C.status(p).away,"A step takes it back")
    step(p,100,2000)
    assert(C.status(p).away,"And minutes without input count as away")
    C.stop(p)
end
passed("small help while someone is there, everything once they are gone")

-- Danger --------------------------------------------------------------------
for _,mode in ipairs({"recovery","meditation"}) do
    local p=survivor()
    local bottle=T.add(p.inventory,T.water({thirst=-.8}))
    if mode=="recovery" then begin(p) else assert(C.start(p,mode,false)); step(p,8) end
    local practice=queue(p)[1]
    p.zombies=1; p.values.THIRST,p.thirstMoodle=.3,2
    step(p,2)
    if practice then assert(practice.stopped,"Nobody meditates in view of a zombie") end
    step(p,12)
    assert(queue(p)[1] and queue(p)[1].Type=="drink","The bottle in hand is still drunk: "..mode.." "..C.status(p).message)
    queue(p)[1]:perform(); p.thirstMoodle=0
    assert(bottle.fluid:getAmount()<1)
    step(p,40)
    assert(not queue(p)[1] and C.status(p).phase=="recovery-paused" and C.status(p).message:find("zombies are nearby",1,true),C.status(p).message)
    p.zombies,p.chasing=1,1; p.values.THIRST,p.thirstMoodle=.6,4
    step(p,20)
    assert(not queue(p)[1] and C.status(p).active,"Being chased is the player's business")
    C.stop(p)
end
do
    -- In view of zombies, only someone dying of thirst is walked anywhere.
    scout=true
    local find=N.find
    local shelf=T.container(6,0)
    N.find=function(_,kind) if kind=="water" then return {key="water:6",square=shelf.square,container=shelf} end end
    local p=survivor(); p.zombies=1; p.values.THIRST,p.thirstMoodle=.5,3
    begin(p); C.setAway(p,true); seconds(p,20)
    assert(count(p,"ISWalkToTimedAction")==0)
    p.thirstMoodle=4; seconds(p,5)
    assert(count(p,"ISWalkToTimedAction")==1)
    C.stop(p); N.find=find; scout=false
end
passed("a zombie in view holds the survivor still without starving them, in every job")

-- First aid -----------------------------------------------------------------
BodyPartType=BodyPartType or {}
BodyPartType.getDisplayName=function() return "Left Forearm" end
local function part(fields)
    local b=fields or {}
    function b:bleeding() return self.blood==true end
    function b:bandaged() return self.cover==true end
    function b:isBandageDirty() return self.filthy==true end
    function b:scratched() return self.scratch==true end
    function b:isCut() return self.open==true end
    function b:deepWounded() return self.deep==true end
    function b:getBurnTime() return self.burn or 0 end
    function b:getBleedingTime() return self.blood and 1 or 0 end
    function b:bitten() return false end
    function b:HasInjury() return self.open or self.scratch or self.blood or false end
    function b:getType() return 1 end
    function b:getStiffness() return 0 end
    return b
end
local function bandage(p,name,alcohol)
    local item=T.add(p.inventory,T.item("Normal",{}))
    item.getBandagePower=function() return 4 end
    item.getType=function() return name end
    item.isAlcoholic=function() return alcohol==true end
    item.isInfected=function() return false end
    return item
end
local refuse=false
local function drop(p,item)
    for index,entry in ipairs(p.inventory.items) do if entry==item then table.remove(p.inventory.items,index); item.container=nil; return end end
end
ISApplyBandage={new=function(_,doctor,patient,item,wound,apply)
    assert(doctor==patient)
    local a
    a=T.action(doctor,apply and "bandage" or "unbandage",function()
        if refuse then return end
        if apply then
            wound.cover,wound.filthy,wound.blood=true,nil,nil
            drop(doctor,item)
        else wound.cover=nil end
    end)
    a.item=item
    return a
end}
local function wounded(p,list)
    function p:getBodyDamage()
        return {getOverallBodyHealth=function() return p.health or 100 end,
            getNumPartsBleeding=function() local n=0; for _,b in ipairs(list) do if b.blood and not b.cover then n=n+1 end end return n end,
            getBodyParts=function() return T.list(list) end, isInfected=function() return false end, getNumPartsBitten=function() return 0 end}
    end
end
do
    local p=survivor()
    local arm,leg=part({open=true,scratch=true}),part({blood=true,open=true})
    wounded(p,{arm,leg})
    local rag=bandage(p,"RippedSheetsDirty"); local clean=bandage(p,"Bandage"); local best=bandage(p,"AlcoholBandage",true)
    begin(p); step(p,12)
    local a=queue(p)[1]
    assert(a and a.Type=="bandage" and a.item==best,"Bleeding first, with the best dressing carried")
    a:perform(); assert(leg.cover)
    step(p,8); assert(not queue(p)[1],"A scratch waits until nobody needs the hands")
    seconds(p,14)
    a=queue(p)[1]; assert(a and a.Type=="bandage" and a.item==clean); a:perform()
    arm.filthy=true; seconds(p,20)
    assert(not queue(p)[1],"A dirty dressing is not swapped for a dirty rag")
    bandage(p,"Bandage"); seconds(p,20)
    a=queue(p)[1]; assert(a and a.Type=="unbandage"); a:perform(); seconds(p,3)
    a=queue(p)[1]; assert(a and a.Type=="bandage"); a:perform()
    assert(rag and C.status(p).active)
    C.stop(p)
end
do
    local p=survivor()
    local leg=part({blood=true}); wounded(p,{leg})
    local bottle=T.add(p.inventory,T.water({thirst=-.8}))
    p.values.THIRST,p.thirstMoodle=.3,2
    begin(p); step(p,10)
    assert(queue(p)[1] and queue(p)[1].Type=="drink","Bleeding does not switch off drinking")
    queue(p)[1]:perform(); p.thirstMoodle=0
    seconds(p,12)
    assert(alerted(p,"no bandage") and issue(p,"bleeding").severity==3 and C.status(p).aidNotice and bottle)
    local rag=bandage(p,"RippedSheetsDirty"); seconds(p,8)
    assert(queue(p)[1] and queue(p)[1].item==rag,"A dirty rag still stops blood")
    queue(p)[1]:perform(); seconds(p,12)
    assert(#C.status(p).alerts==0)
    C.stop(p)
end
do
    local p=survivor(); local leg=part({}); wounded(p,{leg}); bandage(p,"Bandage")
    assert(C.start(p,"meditation",false)); step(p,8)
    local practice=queue(p)[1]; assert(practice and practice.Type=="Meditation")
    leg.blood=true; step(p,14)
    assert(practice.stopped and queue(p)[1] and queue(p)[1].Type=="bandage","Training stops for a bandage and goes on")
    queue(p)[1]:perform(); step(p,60)
    assert(queue(p)[1] and queue(p)[1].Type=="Meditation",C.status(p).message)
    C.stop(p)
end
do
    -- Refused by the game or a server: one bottle, not one bandage after another.
    local p=survivor(); local leg=part({blood=true}); wounded(p,{leg})
    bandage(p,"Bandage"); bandage(p,"Bandage"); bandage(p,"Bandage")
    local bottle=T.add(p.inventory,T.water({thirst=-.8}))
    p.values.THIRST,p.thirstMoodle=.9,4
    refuse=true
    begin(p)
    for _=1,480 do step(p); if queue(p)[1] then queue(p)[1]:perform() end end
    assert(count(p,"bandage")<=4 and bottle.fluid:getAmount()<1,"tries "..count(p,"bandage"))
    refuse=false; p.thirstMoodle=0
    for _=1,1600 do step(p); if queue(p)[1] then queue(p)[1]:perform() end end
    assert(leg.cover and count(p,"bandage")<=6)
    C.stop(p)
end
do
    -- Burns are dressed; an unstitched deep wound does not eat every bandage.
    local p=survivor()
    local burn,deep=part({burn=10}),part({deep=true,cover=true,filthy=true,open=true})
    wounded(p,{burn,deep})
    for _=1,4 do bandage(p,"Bandage") end
    begin(p)
    for _=1,400 do step(p); if queue(p)[1] then queue(p)[1]:perform() end end
    assert(burn.cover and deep.cover and deep.filthy and count(p,"bandage")==1 and count(p,"unbandage")==0)
    O.firstAid=function() return false end
    burn.cover=nil; seconds(p,40); assert(count(p,"bandage")==1,"Off means off")
    O.firstAid=function() return true end
    C.stop(p)
end
for _,mode in ipairs({"recovery","meditation"}) do
    -- Hurt on an errand: nothing may wait for the end of a trip that cannot go on.
    scout=true
    local find=N.find
    local shelf=T.container(6,0)
    N.find=function(_,kind) if kind=="water" then return {key="water:6",square=shelf.square,container=shelf} end end
    local p=survivor(); p.values.THIRST,p.thirstMoodle=.6,3
    local leg=part({}); wounded(p,{leg}); local dressing=bandage(p,"Bandage")
    if mode=="recovery" then begin(p); C.setAway(p,true) else assert(C.start(p,mode,false)) end
    for _=1,60 do
        step(p)
        local a=queue(p)[1]
        if a and a.Type=="ISWalkToTimedAction" then break elseif a then a:perform() end
    end
    assert(queue(p)[1] and queue(p)[1].Type=="ISWalkToTimedAction",C.status(p).message)
    leg.blood=true
    for _=1,120 do step(p); local a=queue(p)[1]; if a and a.Type=="bandage" then a:perform() end end
    assert(leg.cover and dressing,mode..": "..C.status(p).message)
    C.stop(p); N.find=find; scout=false
end
passed("bleeding is treated, not waited out")

-- Never quietly gives up ----------------------------------------------------
do
    local p=survivor(); begin(p)
    for n=1,4 do
        C.giveUp(p,"The return walk did not settle.")
        assert(C.status(p).active,"Only Stop ends Recovery")
        seconds(p,6)
    end
    assert(alerted(p,"did not settle"),"Trouble that keeps coming back is announced")
    local bottle=T.add(p.inventory,T.water({thirst=-.8})); p.values.THIRST,p.thirstMoodle=.3,2
    seconds(p,6); assert(queue(p)[1] and queue(p)[1].Type=="drink" and bottle,"Care at hand goes on meanwhile")
    C.stop(p,"You stopped AutoMindful.")
    assert(not C.status(p).active)
    assert(C.start(p,"meditation",false)); C.giveUp(p,"Training cannot go on.")
    assert(not C.status(p).active,"Training still says why and ends")
end
do
    scout=true
    local find,known=N.find,require("AutoMindful/SurvivalRoute").known
    local n=0
    N.find=function(_,kind,_,_,rejected)
        if kind~="water" then return end
        for index=1,9 do
            local key="water:"..index
            if not rejected[key] then
                local shelf=T.container(index,3)
                return {key=key,square=shelf.square,container=shelf}
            end
        end
    end
    local p=survivor(); p.values.THIRST,p.thirstMoodle=.6,3
    begin(p); C.setAway(p,true)
    for _=1,400 do
        step(p)
        local a=queue(p)[1]
        if a and a.Type=="ISWalkToTimedAction" then n=n+1; a.result=BehaviorResult.Failed; a:forceStop()
        elseif a then a:perform() end
        if C.status(p).boxedIn then break end
    end
    assert(n>=4 and C.status(p).boxedIn and issue(p,"boxed"),"Walk after walk failing from one spot is noticed, walks="..n)
    local far=T.square(3,0)
    T.loadSquare(p,far); p.square=far
    seconds(p,12)
    assert(not C.status(p).boxedIn,"Moving off the spot ends it")
    for _,a in ipairs(C.status(p).alerts) do assert(not a.text:find("Cannot walk to any",1,true)) end
    C.stop(p); N.find=find; scout=false
end
do
    -- Something the game will not start must not be picked again forever.
    local p=survivor(); p.values.HUNGER,p.hungerMoodle=.6,3
    local refused=T.add(p.inventory,T.item("Food",{hunger=-.6,baseHunger=-.6}))
    local other=T.add(p.inventory,T.item("Food",{hunger=-.3,baseHunger=-.3}))
    local Consumables=require "AutoMindful/Consumables"
    local consume=Consumables.consume
    Consumables.consume=function(player,item,kind) if item==refused then return false end return consume(player,item,kind) end
    begin(p)
    for _=1,200 do step(p); if queue(p)[1] then queue(p)[1]:perform(); break end end
    assert(count(p,"eat")==1 and other:getHungerChange()>-.3,"The next meal is eaten instead")
    Consumables.consume=consume
    C.stop(p)
end
do
    -- A bug is logged, waited out and announced; the survivor is not dropped.
    local p=survivor(); begin(p)
    local vehicle=p.getVehicle
    function p:getVehicle() error("test error") end
    for _=1,200 do T.now=T.now+250; Events.OnPlayerUpdate.callback(p) end
    assert(C.status(p).active and alerted(p,"keeps retrying") and p.data.AutoMindfulRecovery)
    p.getVehicle=vehicle
    T.add(p.inventory,T.water({thirst=-.8})); p.values.THIRST,p.thirstMoodle=.5,3
    for _=1,300 do T.now=T.now+250; Events.OnPlayerUpdate.callback(p); if queue(p)[1] then break end end
    assert(queue(p)[1] and queue(p)[1].Type=="drink")
    C.stop(p)
end
do
    -- The mode that follows level 10 is Recovery like any other.
    local p=survivor(); p.meditation,p.xp=9,9000
    assert(C.start(p,"meditation",false)); p.meditation,p.xp=10,10000
    for _=1,40 do step(p); if queue(p)[1] then queue(p)[1]:perform() end end
    assert(C.status(p).mode=="recovery" and p.data.AutoMindfulRecovery,C.status(p).mode)
    C.stop(p)
end
do
    local p=survivor()
    p.data.AutoMindfulRecovery=true
    for _=1,40 do T.now=T.now+250; Events.OnPlayerUpdate.callback(p) end
    assert(C.status(p).active and C.status(p).mode=="recovery","On when they left, on when they are back")
    C.stop(p); assert(p.data.AutoMindfulRecovery==nil)
    for _=1,40 do T.now=T.now+250; Events.OnPlayerUpdate.callback(p) end
    assert(not C.status(p).active,"Stopped stays stopped")
    p=survivor(); p.data.AutoMindfulRecovery=true
    O.resumeRecovery=function() return false end
    for _=1,40 do T.now=T.now+250; Events.OnPlayerUpdate.callback(p) end
    assert(not C.status(p).active)
    O.resumeRecovery=function() return true end
end
passed("only Stop ends it; setbacks back off, are announced, and it survives a reload")

-- Warnings ------------------------------------------------------------------
do
    local p=survivor(); begin(p)
    p.values.HUNGER,p.hungerMoodle=.8,4
    local before=#sounds
    seconds(p,8)
    assert(alerted(p,"nothing to eat") and #sounds==before+1)
    local said=#p.alerts
    seconds(p,60); assert(#p.alerts==said,"Once, not every few seconds")
    seconds(p,90); assert(#p.alerts==said+1,"And again while it lasts")
    T.add(p.inventory,T.item("Food",{hunger=-.9,baseHunger=-.9}))
    for _=1,40 do step(p); if queue(p)[1] then queue(p)[1]:perform(); p.hungerMoodle=0 end end
    assert(#C.status(p).alerts==0,"Over once it is over")
    C.stop(p)
end
do
    local p=survivor(); begin(p); seconds(p,6)
    assert(#p.alerts==0)
    C.setAway(p,true); seconds(p,2)
    assert(alerted(p,"Before you go"),"Leaving with nothing to eat is said at the door")
    C.stop(p)
end
passed("trouble is announced once, again while it lasts, and at the moment someone leaves")

-- Looking ahead -------------------------------------------------------------
do
    local Outlook=require "AutoMindful/Outlook"
    local hours=100
    getGameTime=function() return {getWorldAgeHours=function() return hours end,getMinutesPerDay=function() return 120 end,
        getNightsSurvived=function() return 1 end,getTimeOfDay=function() return 12 end} end
    local p=survivor()
    p.values.HUNGER,p.values.THIRST=0,0
    for _=1,13 do Outlook.sample(p,T.now); hours=hours+.1; p.values.HUNGER,p.values.THIRST=p.values.HUNGER+.002,p.values.THIRST+.005 end
    assert(math.abs(Outlook.rate(p,"food")-.02)<.001 and math.abs(Outlook.rate(p,"water")-.05)<.001,"Measured, not assumed")
    p.values.HUNGER,p.values.THIRST=.1,.1
    -- 0.6 until starving at 0.02 an hour is 30 game hours; a 0.4 meal adds 20.
    local read=Outlook.read(p,"carried")
    assert(math.abs(read.foodHours-30)<.5 and read.issues[1].severity==3)
    T.add(p.inventory,T.item("Food",{hunger=-.4,baseHunger=-.4}))
    T.add(p.inventory,T.water({thirst=-.5}))
    read=Outlook.read(p,"carried")
    assert(math.abs(read.foodHours-50)<.5 and math.abs(read.waterHours-22)<.5,read.foodHours.." "..read.waterHours)
    -- Two hours of real time per game day: 50 game hours are a little over four.
    assert(read.food=="4 h" and Outlook.duration(6)=="30 min" and Outlook.duration(24*24)=="2 days",read.food)
    p.values.HUNGER=.05
    Outlook.sample(p,T.now); hours=hours+3; Outlook.sample(p,T.now)
    assert(math.abs(Outlook.rate(p,"food")-.02)<.001,"A meal or a long gap is not a rate")
end
passed("what is left is measured against this survivor and told in real time")

-- Last resort ---------------------------------------------------------------
do
    local Fluids=require "AutoMindful/Fluids"
    local p=survivor(); p.values.THIRST,p.thirstMoodle=.9,4
    local allow=false
    O.lastResort=function() return allow end
    begin(p); seconds(p,90)
    assert(not Fluids.allowTainted,"Off means off")
    allow=true; step(p,4); assert(Fluids.allowTainted)
    p.thirstMoodle=3; step(p,8); assert(not Fluids.allowTainted,"Ends with the emergency")
    p.thirstMoodle=4; seconds(p,40); assert(not Fluids.allowTainted,"Not in the first minute")
    seconds(p,30); assert(Fluids.allowTainted)
    C.stop(p); assert(not Fluids.allowTainted,"Stop takes the permission back")
    p=survivor(); p.values.THIRST,p.thirstMoodle=.9,4
    T.add(p.inventory,T.water({thirst=-.8}))
    begin(p); p.zombies=1
    for _=1,360 do step(p) end
    assert(not Fluids.allowTainted,"Not while anything clean is left")
    C.stop(p)
    O.lastResort=function() return false end
end
passed("unsafe water only after a minute of dying of thirst, and never otherwise")
print("RECOVERY STEWARD PASS")
