-- Unmodified Lifestyle 0.4.0.3 menu, Meditation action, Mindfulness effects
-- and mood accumulator flush. Native player/clock/queue/network are doubles.
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
if not loadUpstream and arg and arg[1] then
    function loadUpstream(name) return assert(loadfile(arg[1].."/lua/"..name))() end
end
assert(loadUpstream,"The mindfulness-native fixture requires the installed Lifestyle media path")
local T,C=AutoMindfulTest,AutoMindfulTest.controller
local Facts=require "AutoMindful/WellnessFacts"
local Q=ISTimedActionQueue
local function noop() end
require("AutoMindful/Options").practiceCare=function() return true end
function getModInfoByID(id)
    if id=="LifestyleHobbies" then return {getModVersion=function() return Facts.version end} end
end

for _, name in ipairs({"STRESS","NICOTINE_WITHDRAWAL","UNHAPPINESS","POISON","SICKNESS","FOOD_SICKNESS",
        "ZOMBIE_INFECTION","ZOMBIE_FEVER","INTOXICATION"}) do CharacterStat[name]=name end
CharacterTrait.SMOKER="smoker"
HaloTextHelper={addTextWithArrow=noop,addBadText=noop,addGoodText=noop}
Metabolics={Fitness="Fitness"}
GTLSCheck=1 -- 120 real minutes per game day, 1x speed.
LSMoodHandler={PerMin={}}
SandboxVars.Text={DividerMeditationNew=true}
SandboxVars.Meditation.EffectMultiplier,SandboxVars.Meditation.MindfulnessDuration=2,2
SandboxVars.Meditation.HealFactor=2
SandboxVars.Yoga.Exhaustion=1
SandboxVars.LS={MoodUpdate=7,ModdataUpdate=12} -- moods every 30 game minutes
SandboxVars.DayLength=4
T.client,T.sleepNeeded=true,false

for _, name in ipairs({"EveryOneMinute","EveryTenMinutes","EveryHours","EveryDays"}) do
    Events[name]={Add=function(fn) Events[name].callback=fn end}
end
local world, pending
function getGameTime()
    return {getGameWorldSecondsSinceLastUpdate=function() return 12 end,
        getMinutesPerDay=function() return 120 end,getWorldAgeHours=function() return world/60 end,
        getNightsSurvived=function() return T.nights end}
end
function getPlayer() return T.player end
function getTexture(path) return path end
function ZombRand() return 0 end
function sendClientCommand(_,module,command,_)
    assert(module=="LS" and (command=="AddXP" or command=="dropHeavyItems" or command=="SavePlayerData"),command)
end

-- Model the engine/network APIs, not each Lifestyle effect. The original
-- bundle chooses which statistic, how much, and when to send to this receiver.
LSUtil={
    round=function(v,n) local p=10^n; return math.floor(v*p+0.5)/p end,
    getCharacterMood=function(p,name) return p.values[name:upper()] or 0 end,
    changeCharacterMoodGroup=function(p,changes)
        for name,args in pairs(changes) do
            if name~="Nicotine_Withdrawal" or p.traits.smoker then
                pending[#pending+1]={at=T.now+3000,p=p,stat=name:upper(),delta=args[1]}
            end
        end
    end,
    addGeneralHealth=function(p,amount)
        pending[#pending+1]={at=T.now+3000,p=p,stat="HEALTH",delta=amount}
    end,
    addPainBodyPart=noop, -- Native neck pain is a separate body-part field.
}

ISBaseTimedAction={}
function ISBaseTimedAction:derive(name)
    local kind={Type=name}
    kind.__index=kind
    return setmetatable(kind,{__index=self})
end
function ISBaseTimedAction:setActionAnim() end
function ISBaseTimedAction:isStarted() return self.action~=nil end
function ISBaseTimedAction:begin()
    self.action={setUseProgressBar=noop,forceStop=function() self:stop() end}
    self.character.nativeHead=self.action
    self:start()
end
function ISBaseTimedAction:stop()
    if self.character.nativeHead==self.action then self.character.nativeHead=nil end
    Q.getTimedActionQueue(self.character):resetQueue()
end
function ISBaseTimedAction:perform()
    if self.character.nativeHead==self.action then self.character.nativeHead=nil end
    Q.getTimedActionQueue(self.character):onCompleted(self)
end
function ISBaseTimedAction:forceStop() self:stop() end
function ISBaseTimedAction:forceCancel() self.cancelled=true end
loadUpstream("shared/TimedActions/LSMeditateAction.lua")
loadUpstream("client/ISMeditation/ZenWellnessContextMenu.lua")
loadUpstream("client/ISMeditation/Mindfulness.lua")

local function prepare(rank, stat, value, mode)
    world,pending=0,{}
    LSMoodHandler.PerMin,LSMoodHandler.PerTenMin,LSMoodHandler.PerHour={},{},{}
    loadUpstream("client/ZLSUpdate.lua")
    Events.OnGameStart.callback()
    local p=T.playerNew()
    p.sitting,p.meditation,p.values[stat]=true,rank,value
    p.values.HEALTH=p.values.HEALTH or 100
    if stat=="NICOTINE_WITHDRAWAL" then p.traits.smoker=true end
    local body={getOverallBodyHealth=function() return p.values.HEALTH end,getNumPartsBleeding=function() return 0 end,
        isInfected=function() return false end,getNumPartsBitten=function() return 0 end}
    function p:getBodyDamage() return body end
    function p:getPrimaryHandItem() return nil end
    function p:getSecondaryHandItem() return nil end
    function p:setPrimaryHandItem() end
    function p:setSecondaryHandItem() end
    function p:getWornItems() return T.list({}) end
    function p:isSeatedInVehicle() return false end
    function p:isTimedActionInstant() return false end
    function p:setMetabolicTarget() end
    function p:getEmitter() return {playSound=function() return 1 end,stopSound=noop,isPlaying=function() return true end} end
    p.data.AutoMindfulLastCompleted="meditation" -- Yoga stays owed if survival care runs during Both
    assert(C.start(p,mode or "recovery",false))
    return p
end

local function step(p,second,stepRoute)
    local previous=math.floor(world+0.0001)
    T.now,world=T.now+1000,second/5
    local minute=math.floor(world+0.0001)
    local action=Q.getTimedActionQueue(p).queue[1]
    if action then
        if action.Type=="LSMeditateAction" then action:update()
        elseif action.Type=="stand" then action:perform()
        elseif action.Type=="ISTakeWaterAction" then
            assert(action:isValid() and action:complete()); action:perform()
        elseif stepRoute and stepRoute(action) then -- route callback delivered at the Java boundary
        else error("Unexpected action: "..tostring(action.Type)) end
    end
    if minute>previous then
        local md=p:getModData()
        -- Same condition as Lifestyle's EveryOneMinute dispatcher.
        if md.LSMoodles.MindfulState.Value>0 or (md.MindfulnessMinutes and md.MindfulnessMinutes>0) then
            AdjustPlayerMindfulness(p)
        end
        Events.EveryOneMinute.callback()
        if minute%10==0 then Events.EveryTenMinutes.callback() end
        if minute%60==0 then Events.EveryHours.callback() end
    end
    local i=1
    while i<=#pending do
        local r=pending[i]
        if T.now>=r.at then
            local max=(r.stat=="HUNGER" or r.stat=="STRESS" or r.stat=="NICOTINE_WITHDRAWAL") and 1 or 100
            r.p.values[r.stat]=math.max(0,math.min(max,(r.p.values[r.stat] or 0)+r.delta))
            table.remove(pending,i)
        else i=i+1 end
    end
    C.update(p)
end
local function count(p,kind)
    local n=0
    for _, name in ipairs(p.history) do if kind==name then n=n+1 end end
    return n
end
local function head(p) return Q.getTimedActionQueue(p).queue[1] end

for _, fixture in ipairs({{0,"STRESS",0.70},{0,"NICOTINE_WITHDRAWAL",0.60}}) do
    local p=prepare(fixture[1],fixture[2],fixture[3])
    for second=1,60 do
        step(p,second)
        if p.values[fixture[2]]<fixture[3] and not head(p) then break end
    end
    assert(count(p,"LSMeditateAction")==1 and not head(p) and p.values[fixture[2]]<fixture[3])
    assert((C.status(p).careNotice or ""):find("showed relief",1,true) and p.data.LSMoodles.MindfulState.Value==0)
    C.stop(p)
    print("NATIVE PASS rank zero direct "..fixture[2].." with delayed stat readback and no Mindfulness")
end

for _, fixture in ipairs({{3,"PANIC",45,"panic ease",1},{6,"HUNGER",0.23,"hunger ease",2},
        {10,"HEALTH",85,"health improve",3},{10,"HEALTH",4,"health improve",3}}) do
    local rank,stat,before,label,wanted=fixture[1],fixture[2],fixture[3],fixture[4],fixture[5]
    local p=prepare(rank,stat,before)
    local lastTier,acquiredAt,observedAt,pose=0
    for second=1,430 do
        step(p,second)
        pose=pose or head(p)
        local value=p.data.LSMoodles.MindfulState.Value
        local tier=math.floor(value*5+0.0001)
        if not acquiredAt and tier>lastTier then
            assert(tier==lastTier+1,"Lifestyle must supply each prerequisite itself")
            lastTier=tier
        end
        if not acquiredAt and tier==wanted then
            acquiredAt=T.now
            assert(pose and pose.autoMindfulStopped and not head(p) and p.values[stat]==before)
            assert(not (C.status(p).careNotice or ""):find(label,1,true),"Tier acquisition is not a relief receipt")
        end
        if (C.status(p).careNotice or ""):find(label,1,true) then
            observedAt=T.now
            assert(not head(p) and (stat=="HEALTH" and p.values[stat]>before or stat~="HEALTH" and p.values[stat]<before))
            if stat=="PANIC" then assert(tier==0,"Test must prove a real flush after native tier decay") end
            break
        end
    end
    assert(acquiredAt and observedAt and observedAt>acquiredAt and lastTier==wanted,
        ("No tier/receipt for %s at rank %s: tier %i, current %.3f, status %s"):format(stat,rank,lastTier,p.values[stat],tostring(C.status(p).message)))
    if stat~="HEALTH" then assert(observedAt-acquiredAt>15000,"Receipt must be safely outside the old 15s window") end
    assert(C.status(p).active and count(p,"LSMeditateAction")==1 and C.status(p).cycle==nil)
    print(("NATIVE PASS rank %d tier %d: %s readback %.3f -> %.3f after %.0fs queue-free"):format(
        rank,wanted,stat,before,p.values[stat],(observedAt-acquiredAt)/1000))
    C.stop(p)
end

-- Actual installed Meditation can reduce Unhappiness when starting
-- calm. Confirm the matching native stat; stress or a tier is not evidence.
do
    for _,couch in ipairs({false,true}) do
        local p=prepare(0,"UNHAPPINESS",21)
        p.traits.couchpotato=couch
        SandboxVars.Meditation.StrengthMultiplier=couch and 1 or 2
        for second=1,64 do
            step(p,second)
            if p.values.UNHAPPINESS<21 and not head(p) then break end
        end
        assert((C.status(p).careNotice or ""):find("showed relief",1,true)
            and p.values.UNHAPPINESS<21 and count(p,"LSMeditateAction")==1 and not head(p)
            and p.data.LSMoodles.MindfulState.Value==0 and C.status(p).cycle==nil,
            "Expected direct native Unhappiness relief, not a tier or a training turn")
        print(("NATIVE PASS calm rank-0 %s: Unhappiness 21 -> %.3f"):
            format(couch and "Couch Potato at x0.5 strength" or "Meditation at default strength",p.values.UNHAPPINESS))
        C.stop(p)
    end
    SandboxVars.Meditation.StrengthMultiplier=nil
end

-- Only speculative MP loot is visible. This replay uses the installed menu,
-- Meditation action, per-minute tier decay, mood accumulator and delayed receiver.
-- It does not model ordinary metabolism or assert a guaranteed duration/meal.
do
    local nearby,opts=require "AutoMindful/Nearby",require "AutoMindful/Options"
    local previous,search=nearby.find,opts.searchNearby
    opts.searchNearby=function() return true end
    for _,critical in ipairs({false,true}) do
        local before=critical and .8 or .40
        local p=prepare(6,"HUNGER",before)
        p.hungerMoodle=critical and 4 or 0
        if critical then p.values.THIRST=.2 end -- ordinary thirst with no confirmed drink is not a competing survival action
        local unknown=T.container(1,0)
        local seen=0
        nearby.find=function(_,kind)
            if kind=="food" or critical and kind=="water" then
                seen=seen+1; return {unknown=true,key="unknown:crate",container=unknown,square=unknown:getSourceGrid()}
            end
        end
        local pose,acquired,observed
        for second=1,520 do
            step(p,second)
            pose=pose or head(p)
            if not acquired and p.data.LSMoodles.MindfulState.Value>=.4 then
                acquired=T.now
                assert(pose and pose.autoMindfulOwner and pose.autoMindfulStopped and not head(p) and p.values.HUNGER==before)
            end
            if (C.status(p).careNotice or ""):find("hunger ease",1,true) then
                observed=T.now
                assert(not head(p) and p.values.HUNGER<before and p.calories==2000)
                break
            end
        end
        assert(seen>0 and acquired and observed and observed>acquired and C.status(p).active,
            "No native hunger receipt with unconfirmed MP loot: "..C.status(p).message)
        assert(count(p,"LSMeditateAction")==1 and count(p,"eat")==0 and C.status(p).cycle==nil)
        print(("NATIVE PASS %s no-food/unknown MP storage: %.3f -> %.3f, delayed stat after native Strong: %.0fs; calories unchanged"):format(critical and "critical" or "ordinary",before,p.values.HUNGER,(observed-acquired)/1000))
        C.stop(p)
    end
    nearby.find,opts.searchNearby=previous,search
end
print("PASS 9 pinned Lifestyle utility cases with actual tier/effect/flush Lua and explicit game/network doubles")

-- Run this combined leg when the stock game *and* Lifestyle references exist.
-- The installed water action calculates the drink amount and completes it. The
-- fixture models the Java-side unmetered pipe, DrinkFluid and action/network clocks.
if not loadStockLua and arg and arg[2] then
    function loadStockLua(name) return assert(loadfile(arg[2].."/lua/"..name))() end
end
if loadStockLua then
    local captured=require "AutoMindful/WaterSources"
    package.loaded["AutoMindful/WaterSources"]=nil
    for _,name in ipairs({"TimedActions/ISTakeWaterAction","TimedActions/ISWearClothing"}) do package.loaded[name]=true end
    local actual=require "AutoMindful/WaterSources"
    for k,v in pairs(actual) do captured[k]=v end
    package.loaded["AutoMindful/WaterSources"]=actual
    function ISBaseTimedAction:new(character) return setmetatable({character=character},self) end
    function ISBaseTimedAction:setOverrideHandModels() end
    loadStockLua("shared/TimedActions/ISTakeWaterAction.lua")
    luautils={getCorrectSquareForWall=function(_,square) return square end}
    SafeHouse={isSafehouseAllowInteract=function() return true end,isSafehouseAllowLoot=function() return true end}
    FluidContainer={DisposeContainer=function(sample) assert(sample.drunk);sample.disposed=true end}
    -- Keep the real native Yoga admission out of this scenario, without manufacturing a turn.
    local opts=require "AutoMindful/Options"
    opts.searchNearby=function() return true end
    local function tapAt(p,sq,tainted)
        local tap={kind="IsoObject",refills=0}
        function tap:getMasterObject() return self end
        function tap:getSquare() return sq end
        function tap:isTaintedWater() return tainted==true end
        function tap:hasWater() return true end
        function tap:hasFluid() return true end
        function tap:getFluidAmount() return 10000 end
        function tap:getFluidCapacity() return 10000 end
        function tap:getUsesExternalWaterSource() return false end
        function tap:getFluidContainer() return nil end
        function tap:getPrimaryFluid() return Fluid.Water end
        function tap:getProperties() return nil end
        function tap:getContainerCount() return 0 end
        function tap:getSpriteGridObjectsIncludingSelf(parts) parts:add(self) end
        function tap:moveFluidToTemporaryContainer(amount)
            self.refills=self.refills+1
            self.sample={source=self,amount=amount}
            return self.sample
        end
        function sq:getObjects() return T.list({tap}) end
        function sq:getWorldObjects() return T.list({}) end
        T.loadSquare(p,sq)
        return tap
    end
    local function stockDrinker(p)
        function p:reportEvent(e) self.sitting=(e=="EventSitOnGround") end
        function p:hasFullInventory() return false end
        function p:playSound() end
        function p:DrinkFluid(sample,fraction)
            assert(sample==sample.source.sample and not sample.source:isTaintedWater() and fraction==1 and sample.amount>0)
            assert(self:getSquare():canReachTo(sample.source:getSquare()),"remote drink")
            p.values.THIRST=math.max(0,p.values.THIRST-sample.amount*.5)
            sample.drunk=true
            if p.values.THIRST<.01 then p.thirstMoodle=0 end
        end
    end
    for _,mode in ipairs({"recovery","both"}) do
        local p=prepare(6,"HUNGER",.8,mode)
        p.hungerMoodle=4
        local tap=tapAt(p,T.square(1,0))
        local here=p:getSquare()
        function here:getObjects() return T.list({}) end
        function here:getWorldObjects() return T.list({}) end
        stockDrinker(p)
        local original,interrupted,secondPose,acquired,observed
        for second=1,560 do
            local a=head(p)
            if a and a.Type=="LSMeditateAction" then
                if not original then original=a
                elseif a~=original then secondPose=a end
                if second>=10 and not interrupted then
                    interrupted=second; p.values.THIRST,p.thirstMoodle=.8,4
                end
            end
            step(p,second)
            if secondPose and p.data.LSMoodles.MindfulState.Value>=.4 then acquired=acquired or second end
            if (C.status(p).careNotice or ""):find("hunger ease",1,true) then observed=second;break end
        end
        assert(interrupted and original.autoMindfulStopped and secondPose and secondPose.autoMindfulStopped and acquired and observed and observed>acquired,
            mode.." did not resume real Strong acquisition: "..C.status(p).message)
        assert(C.status(p).active and count(p,"ISTakeWaterAction")==1 and count(p,"LSMeditateAction")==2 and not head(p))
        assert(p.values.THIRST==0 and tap.refills==1 and tap.sample.disposed and tap:getFluidAmount()==10000)
        assert(p.values.HUNGER<.8 and count(p,"eat")==0 and p.calories==2000 and p:getSquare()==here)
        local cycle=C.status(p).cycle
        if mode=="both" then
            assert(cycle.lastCompleted=="meditation" and cycle.skills.meditation.completed==0 and cycle.skills.yoga.completed==0)
        end
        print(("NATIVE PASS %s: hungry with no food, owned Meditation yields to critical thirst, stock drink from adjacent mains (%.2f L, no debit), resumed native Strong -> H %.3f; no turn/meal/calories"):format(mode,tap.sample.amount,p.values.HUNGER))
        C.stop(p)
    end
    local incident=loadTest and loadTest("survival_incident_replay.lua") or assert(loadfile("tests/survival_incident_replay.lua"))()
    incident(prepare,step,head,count,tapAt,stockDrinker)

end
