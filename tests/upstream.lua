local T = assert(AutoMindfulTest)
local C = T.controller
local noop = function() end
HaloTextHelper = {addTextWithArrow=noop, addBadText=noop, addGoodText=noop}
LSNoteMng = {addToQueue=noop}
LSSync = {updateClientData=noop}
Metabolics = {Fitness="Fitness", FitnessHeavy="FitnessHeavy"}
GTLSCheck = 1
function getCore() return {getScreenWidth=function() return 1280 end, getScreenHeight=function() return 900 end} end
function getTexture(path) return path end
function getSoundManager() return {playUISound=noop} end
function LSupdateZenBonus() end
function forceDropHeavyItems() end
function getGameTime() return {getGameWorldSecondsSinceLastUpdate=function() return 120 end,getNightsSurvived=function() return T.nights end} end
local randomState = 73
function ZombRand(low, high)
    if not high then high,low=low,0 end
    randomState = (randomState*16807)%2147483647
    return low+math.floor((randomState/2147483647)*(high-low))
end
local moodNames = {Boredom="BOREDOM", Pain="PAIN", Endurance="ENDURANCE", Stress="STRESS", Unhappiness="UNHAPPINESS", Nicotine_Withdrawal="NICOTINE"}
LSUtil = {
    getCharacterMood=function(p,name) return p.values[moodNames[name]] or 0 end,
    changeCharacterMoodGroup=function(p,changes)
        for name,args in pairs(changes) do local key=moodNames[name]; if key then p.values[key]=math.max(0,(p.values[key] or 0)+args[1]) end end
    end,
    addPainBodyPart=function(p,_,change) p.values.PAIN=math.max(0,p.values.PAIN+change) end,
    reduceAllStiffness=noop,
    truncateToTwoDecimals=function(n) return math.floor(n*100)/100 end,
}
ISBaseTimedAction = {}
function ISBaseTimedAction:derive(name)
    local derived = {Type=name}
    derived.__index=derived
    return setmetatable(derived,{__index=self})
end
function ISBaseTimedAction:setActionAnim(name) self.animation=name end
function ISBaseTimedAction:setOverrideHandModels() end
function ISBaseTimedAction:begin()
    self.action={setUseProgressBar=noop, forceStop=function() self:stop() end}
    self.character.nativeHead=self.action
end
function ISBaseTimedAction:isStarted() return self.testStarted == true end
function ISBaseTimedAction:perform()
    if self.character.nativeHead==self.action then self.character.nativeHead=nil end
    ISTimedActionQueue.getTimedActionQueue(self.character):onCompleted(self)
end
function ISBaseTimedAction:stop()
    if self.character.nativeHead==self.action then self.character.nativeHead=nil end
    ISTimedActionQueue.getTimedActionQueue(self.character):resetQueue()
end
function ISBaseTimedAction:forceStop() self:stop() end
function ISBaseTimedAction:forceComplete() self:perform() end
function ISBaseTimedAction:forceCancel() self.cancelled=true end
loadUpstream("client/Helper/HSMng.lua")
loadUpstream("shared/TimedActions/LSMeditateAction.lua")
loadUpstream("shared/TimedActions/LSYogaAction.lua")
loadUpstream("client/ISMeditation/ZenWellnessContextMenu.lua")
-- Run the installed, unmodified gate methods before the progression replay.
-- Stats, player, and inventory stay explicit doubles here, not live gameplay.
do
    local p = T.playerNew()
    function p:getMaxWeight() error("Yoga/Meditation must not read player carry capacity to admit") end
    function p:getInventoryWeight() error("Yoga/Meditation must not read inventory weight to admit") end
    local square = p:getSquare()
    function square:getObjects() return T.list({}) end
    p.values.PAIN, p.values.STRESS, p.values.BOREDOM = 60, 1, 60
    local yoga, med = ZenWellnessContextMenu.Options.Yoga, ZenWellnessContextMenu.Options.Meditation
    local oldExhaustion, oldMat, oldEmbarrassment = SandboxVars.Yoga.Exhaustion, SandboxVars.Yoga.RequiresMat, SandboxVars.Yoga.Embarrassment
    SandboxVars.Yoga.RequiresMat, SandboxVars.Yoga.Embarrassment = false, 1
    for _,rule in ipairs({{1,0},{2,.8},{3,.6},{4,.3}}) do
        SandboxVars.Yoga.Exhaustion = rule[1]
        p.values.ENDURANCE = rule[2]
        local blocked, reason = yoga.canPerform(p,"",nil)
        assert(blocked == (rule[1] ~= 1) and (not blocked or reason == getText("Tooltip_Action_Exhausted")), "Installed Lifestyle Yoga boundary")
        p.values.ENDURANCE = rule[2]+.01
        assert(not yoga.canPerform(p,"",nil), "Pain/stress/boredom do not impose another Yoga start gate")
    end
    SandboxVars.Yoga.RequiresMat = true
    local blocked, reason = yoga.canPerform(p,"",nil)
    assert(blocked and reason == getText("Tooltip_Yoga_MissingMat"))
    SandboxVars.Yoga.RequiresMat, SandboxVars.Yoga.Embarrassment = false, 2
    p.data.LSMoodles.Embarrassed.Level = 1
    blocked, reason = yoga.canPerform(p,"",nil)
    assert(blocked and reason == getText("ContextMenu_Embarrassed"))
    SandboxVars.Yoga.Exhaustion, SandboxVars.Yoga.RequiresMat, SandboxVars.Yoga.Embarrassment = oldExhaustion, oldMat, oldEmbarrassment
    p.values.ENDURANCE, p.values.BOREDOM = 0, 30
    assert(not med.canPerform(p,"",nil), "Meditation allows exact boredom 30 and ignores pain/stress/endurance at admission")
    p.values.BOREDOM = 30.01
    blocked, reason = med.canPerform(p,"",nil)
    assert(blocked and reason == " <RED>" .. getText("ContextMenu_Meditate_Bored"))
    print("UPSTREAM PASS licensed Lifestyle Yoga endurance/mat/embarrassment and Meditation boredom admission")
end
local rawPerks = readReference("perks.txt")
local meditation = assert(rawPerks:match("perk%s+Meditation%s*{(.-)}"),"Native Meditation perk metadata missing")
local totals, total = {}, 0
for level=1,10 do
    total=total+assert(tonumber(meditation:match("xp"..level.."%s*=%s*(%d+)")))
    totals[level]=total
end
local p=T.playerNew()
function p:getPerkLevel(perk) if perk == Perks.Meditation then return self.meditation end return 0 end
function p:getWornItems() return T.list({}) end
function p:isSeatedInVehicle() return false end
function p:isTimedActionInstant() return false end
function p:isFemale() return false end
function p:getPrimaryHandItem() return nil end
function p:getSecondaryHandItem() return nil end
function p:setPrimaryHandItem() end
function p:setSecondaryHandItem() end
function p:setMetabolicTarget() end
function p:getEmitter() return {playSound=function() return 1 end, stopSound=noop, isPlaying=function() return true end} end
function p:shouldBeTurning() return false end
local square=p:getSquare()
function square:getObjects() return T.list({}) end
function p:getSquare() return square end
function sendClientCommand(player, module, command, args)
    assert(module == "LS","Unexpected upstream command module")
    if command == "AddXP" and args[1] == "Meditation" then
        player.xp=player.xp+args[2]
        while player.meditation < 10 and player.xp >= totals[player.meditation+1] do player.meditation=player.meditation+1 end
    end
end
-- Drive the installed action implementations' own forceStop paths. Only the
-- player, native clock/animation and audio output below are modeled.
function p:getDescriptor() return {isFemale=function() return false end} end
p.data.PlayerVoice=0
package.preload["TimedActions/PlayerVoiceTracks"]=function() return loadUpstream("client/TimedActions/PlayerVoiceTracks.lua") end
for _,v in ipairs({{"both","LSMeditateAction"},{"both","LSYogaAction"},{"meditation","LSMeditateAction"},{"yoga","LSYogaAction"}}) do
    local mode,target=v[1],v[2]; local med=target=="LSMeditateAction"
    p.sitting=med; p.values.BOREDOM=med and 0 or 10
    assert(C.start(p,mode,false)); T.tick(p,false)
    local q=ISTimedActionQueue.getTimedActionQueue(p); local original=q.queue[1]
    assert(original and original.Type==target,"Upstream did not queue "..target)
    original:waitToStart(); original:start(); original.testStarted=true
    local cards=#p.cards
    if med then p.data.IsMeditationDisturbed=true; p.values.BOREDOM=10
    else p.sitting=true; p.values.BOREDOM=0 end
    original:update()
    assert(original.autoMindfulStopped and not original.autoMindfulFinished,"Upstream did not cancel its action")
    if med then assert(not p.data.IsMeditationDisturbed,"Native stop did not clear its disturbance") else p.sitting=false end
    for i=1,8 do T.tick(p,false); if q.queue[1] then break end end
    assert(q.queue[1] and q.queue[1]~=original and q.queue[1].Type==target
        and C.status(p).active and C.status(p).mode==mode and #p.cards==cards,"Resume failed "..mode.."/"..target)
    C.stop(p,"test cleanup")
    print("UPSTREAM PASS actual Lifestyle cancellation and same-leg recovery: "..mode.."/"..target)
end
for i=1,32 do T.add(p.inventory,T.item("Literature")) end
p.values.BOREDOM=35
assert(C.start(p,"both",false))
local poses, failedPoses, medTicks, sessions = 0,0,0,0
for tick=1,200000 do
    T.now=T.now+1000
    p.hours=p.hours+0.001
    C.update(p)
    local a=ISTimedActionQueue.getTimedActionQueue(p).queue[1]
    if a then
        if a.Type == "LSYogaAction" or a.Type == "LSMeditateAction" then
            if not a.testStarted then
                a:waitToStart()
                a:start()
                a.testStarted=true
                sessions=sessions+1
            end
            local previousPoses=a.poseCount or 0
            a:update()
            if (a.poseCount or 0) > previousPoses then poses=poses+1; if a.doFailState then failedPoses=failedPoses+1 end end
            if a.Type == "LSMeditateAction" then
                medTicks=medTicks+1
                a.testElapsed=(a.testElapsed or 0)+120
                if a.testElapsed >= a.maxTime then a:perform() end
            end
        else a:perform() end
    end
    if not C.status(p).active or C.status(p).mode=="recovery" then break end
end
local status=C.status(p)
assert(status.active and status.mode == "recovery",status.message)
assert(status.meditation == 10 and status.yoga == 10,"Both real upstream action paths must reach their maximum")
assert(poses > 10 and medTicks > 10 and sessions > 2,"Real upstream repeated actions must run")
assert(failedPoses > 0,"Pose failures must be exercised by the deterministic random sequence")
assert(T.hasHistory(p,"read"),"Boredom recovery must use a provision and resume")
print("UPSTREAM PASS real Lifestyle action logic and hidden-skill thresholds reach 10/10; poses="..poses.." failed="..failedPoses.." meditationUpdates="..medTicks)
print("UPSTREAM SCOPE accelerated action clock; modeled player, queues, mood application and raw-metadata XP receiver; not native engine or multiplayer progression")
C.stop(p) -- End the continuing Recovery before the separate Yoga interruption fixture.

-- Read the installed hidden-skill tuple on each side of real grantXP/stop.
-- Only the clock, player and waiting foreign queue owner are modeled.
do
    local q=ISTimedActionQueue.getTimedActionQueue(p)
    local oldRandom,oldExhaust=ZombRand,SandboxVars.Yoga.Exhaustion
    ZombRand=function(low,high)
        if low==100 and high==nil then return 99 end -- deterministic successful native pose roll
        return oldRandom(low,high)
    end
    SandboxVars.Yoga.Exhaustion=1
    p.data.LSHiddenSkills.Yoga={3,100,750}
    p.values.ENDURANCE,p.values.HUNGER,p.values.THIRST,p.sitting=1,.05,0,false
    local last=p.data.AutoMindfulLastCompleted
    assert(C.start(p,"yoga",false))
    local rounds,prior=0,100
    for n=1,12 do
        for _=1,30 do
            T.now=T.now+250; C.update(p)
            if q.queue[1] then break end
        end
        local a=assert(q.queue[1],C.status(p).message)
        assert(a.Type=="LSYogaAction" and a.autoMindfulOwner)
        a:waitToStart(); a:start(); a.testStarted=true
        T.now=T.now+250; C.update(p)
        for _=1,32 do
            a:update()
            if a.poseCount>0 then break end
        end
        local gross=HiddenSkills.getSkill(p,"Yoga")[2]
        assert(a.poseCount==1 and gross>prior,"Expected a real pose gain at interruption "..n)
        p.hours=p.hours+.51
        T.now=T.now+250; C.update(p)
        local foreign=T.action(p,"OtherProducer")
        ISTimedActionQueue.add(foreign)
        T.now=T.now+250; C.update(p)
        local retained=HiddenSkills.getSkill(p,"Yoga")[2]
        assert(a.autoMindfulStopped and not a.autoMindfulFinished and retained<=prior)
        prior,rounds=retained,n
        local handle=foreign.action
        p.hours=p.hours+12
        for _=1,6 do
            T.now=T.now+250; C.update(p)
            assert(q.queue[1]==foreign and p.nativeHead==handle and foreign.begins==1 and not foreign.stopped
                and not foreign.cancelled and not foreign.autoMindfulOwner)
        end
        assert(C.status(p).active==(n<12),"Foreign hours and provisional pose gains must not own the clock")
        foreign:perform()
    end
    local s=C.status(p)
    assert(rounds==12 and prior==0 and not s.active and s.cycle.skills.yoga.completed==0
        and s.cycle.skills.yoga.positiveXPGains==0 and p.data.AutoMindfulLastCompleted==last)
    print("UPSTREAM PASS 12 interrupted real Lifestyle poses, native retained XP 100->0, bounded at 6.12 owned hours; 144 foreign hours excluded")
    ZombRand,SandboxVars.Yoga.Exhaustion=oldRandom,oldExhaust
end
