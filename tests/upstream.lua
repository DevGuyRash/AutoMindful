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
function ISBaseTimedAction:perform() ISTimedActionQueue.getTimedActionQueue(self.character):removeFromQueue(self) end
function ISBaseTimedAction:stop() ISTimedActionQueue.getTimedActionQueue(self.character).queue={} end
function ISBaseTimedAction:forceStop() self:stop() end
function ISBaseTimedAction:forceComplete() self:perform() end
function ISBaseTimedAction:forceCancel() self.cancelled=true end
loadUpstream("client/Helper/HSMng.lua")
loadUpstream("shared/TimedActions/LSMeditateAction.lua")
loadUpstream("shared/TimedActions/LSYogaAction.lua")
loadUpstream("client/ISMeditation/ZenWellnessContextMenu.lua")
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
                a.action={setUseProgressBar=noop}
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
    if not C.status(p).active then break end
end
local status=C.status(p)
assert(status.phase == "complete",status.message)
assert(status.meditation == 10 and status.yoga == 10,"Both real upstream action paths must reach their maximum")
assert(poses > 10 and medTicks > 10 and sessions > 2,"Real upstream repeated actions must run")
assert(failedPoses > 0,"Pose failures must be exercised by the deterministic random sequence")
assert(T.hasHistory(p,"read"),"Boredom recovery must use a provision and resume")
print("UPSTREAM PASS real Lifestyle action logic and hidden-skill thresholds reach 10/10; poses="..poses.." failed="..failedPoses.." meditationUpdates="..medTicks)
print("UPSTREAM SCOPE accelerated action clock; modeled player, queues, mood application and raw-metadata XP receiver; not native engine or multiplayer progression")
