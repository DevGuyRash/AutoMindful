AutoMindfulContractHarnessOnly = true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly = nil
local T = AutoMindfulTest
local C = T.controller
CharacterStat.INTOXICATION = "INTOXICATION"

local function queued(p) return ISTimedActionQueue.getTimedActionQueue(p).queue end
local function pill(container, uses, fullType)
    local item = T.item("DrainableComboItem",{fullType=fullType or "Base.Pills",name="Painkillers",uses=uses or 5})
    function item:getCurrentUses() return self.uses end
    function item:getUseDelta() return self:getFullType()=="Base.PillsVitamins" and 0.2 or 0.1 end
    function item:getOnEat() return nil end
    function item:getReplaceOnDeplete() return nil end
    return T.add(container,item)
end
do
    local pain = require "AutoMindful/PainCare"
    local calls=0
    local function item(kind, name)
        local i=T.item(kind,{fullType=name})
        function i:getCurrentUses()
            calls=calls+1
            error("Drainable-only accessor called on an unrelated item")
        end
        return i
    end
    assert(not pain.eligible(item("Food","Base.Corn")))
    assert(not pain.eligible(item("InventoryItem","Base.Pills")))
    assert(not pain.eligible(item("DrainableComboItem","Base.OtherDrainable")))
    assert(calls==0,"Nonstock or wrong-type items must be rejected before drainable-only access")
end
local function survivor()
    local p = T.playerNew()
    p.values.PAIN,p.painMoodle = 6,0
    p.doses,p.pillRequests = 0,0
    function p:getPainEffect() return self.effect or 0 end
    function p:getPainDelta() return self.painDelta or 0 end
    function p:getSleepingTabletEffect() return self.sedative or 0 end
    return p
end

-- A native-call fixture, not an implementation of pill dosing in the mod.
-- Delayed acknowledgement models native/replicated updates after the timed action drains.
ISInventoryPaneContextMenu.takePill=function(item, slot)
    local p = getSpecificPlayer(slot)
    assert(slot == p:getPlayerNum() and item:getContainer() == p:getInventory())
    p.pillRequests=p.pillRequests+1
    local action = T.action(p,"ISTakePillAction",function()
        if p.dropPainReceipt then return end
        local function applied()
            assert(item.uses>0)
            item.uses=item.uses-1
            p.doses=p.doses+1
            p.effect,p.painDelta = 5400,0.45
        end
        if p.delayPainReceipt then p.pendingPainReceipt=applied else applied() end
    end)
    action.item=item
    ISTimedActionQueue.add(action)
end

local function advance(p, untilReady, max)
    for _=1,max or 22 do
        T.tick(p,false)
        if untilReady() then return end
        local a=queued(p)[1]
        if a and a.Type~="Meditation" and a.Type~="Yoga" and a.Type~="LSMeditateAction" then a:perform() end
    end
    assert(untilReady(), "Did not reach expected next step: " .. C.status(p).phase .. " " .. tostring(C.status(p).message))
end

local function begin(p, mode, collect)
    p.sitting=mode~="yoga"
    assert(C.start(p,mode,collect))
    advance(p,function() return queued(p)[1] and
        (queued(p)[1].Type=="Meditation" or queued(p)[1].Type=="Yoga" or queued(p)[1].Type=="LSMeditateAction") end)
    return queued(p)[1]
end
local function rise(p)
    for _,pain in ipairs({11,12,14,16}) do
        p.values.PAIN,p.painMoodle=pain,1
        T.tick(p,false)
        if p.pillRequests>0 then break end
    end
end
local function nextPill(p)
    advance(p,function() return queued(p)[1] and queued(p)[1].Type=="ISTakePillAction" end)
    return queued(p)[1]
end

for _,mode in ipairs({"meditation","both"}) do
    local p=survivor(); local bottle=pill(p.inventory,5)
    local old=begin(p,mode,false)
    p.values.PAIN=9.99; T.tick(p,false)
    assert(p.pillRequests==0 and queued(p)[1]==old)
    p.values.PAIN,p.painMoodle=10,0 -- flat at the threshold, before its first moodle refresh
    local action=nextPill(p)
    assert(old.stopped and action.item==bottle and p.pillRequests==1 and C.status(p).phase=="paincare")
    action:perform()
    assert(p.doses==1 and bottle.uses==4)
    advance(p,function() return queued(p)[1] and (queued(p)[1].Type=="Meditation" or queued(p)[1].Type=="Yoga") end)
    p.values.PAIN=18
    for i=1,15 do T.tick(p,false) end
    assert(C.status(p).active and p.pillRequests==1 and bottle.uses==4 and #p.cards==0)
    C.stop(p)
end
print("PASS meditation and Both take the first dose at a plateau of exactly 10 despite delayed moodle; no active-effect overlap")

do
    local p=survivor(); local bottle=pill(p.inventory,5)
    begin(p,"meditation",false)
    p.values.PAIN=10
    nextPill(p):perform()
    local function meditate() return queued(p)[1] and queued(p)[1].Type=="Meditation" end
    advance(p,meditate)
    p.values.PAIN,p.effect,p.painDelta=17,-0.25,.45
    for i=1,3 do T.tick(p,false) end
    assert(meditate() and p.doses==1 and p.pillRequests==1,"Expiry overshoot with a nonzero delta is still active")
    p.values.PAIN,p.painDelta=10,0
    for i=1,8 do T.tick(p,false) end
    assert(meditate() and p.doses==1 and p.pillRequests==1,"Exactly 10 must not trigger a repeat")
    p.values.PAIN=10.05
    nextPill(p):perform()
    assert(p.doses==2 and p.pillRequests==2 and bottle.uses==3)
    advance(p,meditate)
    for i=1,12 do T.tick(p,false) end
    assert(p.pillRequests==2 and p.doses==2,"Never queue two doses while the second effect is active")
    C.stop(p)
end
print("PASS continuous meditation re-doses only above 10 after the exact prior effect wears off")

local yoga=survivor(); pill(yoga.inventory,5)
local pose=begin(yoga,"yoga",false)
yoga.values.PAIN=10
for i=1,4 do T.tick(yoga,false) end
assert(queued(yoga)[1]==pose and not pose.stopped and yoga.pillRequests==0,
    "Pain care alone must never terminate a genuine native yoga pose")
pose:perform()
nextPill(yoga):perform()
advance(yoga,function() return queued(yoga)[1] and queued(yoga)[1].Type=="Yoga" end)
assert(yoga.doses==1 and C.status(yoga).active)
local nextPose=queued(yoga)[1]
yoga.values.PAIN,yoga.effect,yoga.painDelta=17,-.1,0
for i=1,4 do T.tick(yoga,false) end
assert(queued(yoga)[1]==nextPose and not nextPose.stopped and yoga.pillRequests==1)
nextPose:perform()
nextPill(yoga):perform()
assert(yoga.doses==2 and yoga.pillRequests==2 and C.status(yoga).active)
C.stop(yoga)
print("PASS yoga finishes each legal pose before a first or eligible repeat dose")

for _,mode in ipairs({"empty","existing","intoxicated","nonstock"}) do
    local p=survivor()
    if mode=="empty" then pill(p.inventory,0)
    elseif mode=="nonstock" then pill(p.inventory,5,"Base.ModPainkiller")
    else
        pill(p.inventory,5)
        if mode=="existing" then p.effect=0.3 else p.values.INTOXICATION=0.3 end
    end
    local old=begin(p,"meditation",true); rise(p)
    assert(p.pillRequests==0 and queued(p)[1]==old, "Unsafe or unavailable medicine is skipped: "..mode)
    C.stop(p)
end
print("PASS existing effect, empty and nonstock bottles, intoxication never auto-dose")

local loan=survivor()
local shelf=T.container(1,0); local bottle=pill(shelf,5)
loan.nearby={shelf}; loan.delayPainReceipt=true
begin(loan,"meditation",true); rise(loan)
local use=nextPill(loan)
assert(use.item==bottle and loan.inventory:contains(bottle) and C.status(loan).pendingReturns==1)
use:perform()
for i=1,3 do T.tick(loan,false) end
assert(loan.inventory:contains(bottle) and C.status(loan).pendingReturns==1
    and C.status(loan).phase=="paincare" and loan.doses==0 and loan.pillRequests==1,
    "Do not return the loan or replay the pill while native use is unconfirmed")
loan.pendingPainReceipt()
advance(loan,function() return shelf:contains(bottle) and C.status(loan).pendingReturns==0
    and queued(loan)[1] and queued(loan)[1].Type=="Meditation" end)
assert(loan.pillRequests==1 and loan.doses==1 and bottle.uses==4)
C.stop(loan)
print("PASS adjacent loan waits for native acknowledgement, returns same bottle, and resumes")

for _,abandon in ipairs({false,true}) do
    local p=survivor(); local own=pill(p.inventory,5)
    p.dropPainReceipt=true
    begin(p,"meditation",false); rise(p)
    local dose=nextPill(p)
    if abandon then
        local foreign=T.action(p,"NativeManualWork")
        ISTimedActionQueue.add(foreign);T.tick(p,false)
        assert(queued(p)[1]==foreign and foreign.begins==1 and not foreign.stopped and not foreign.autoMindfulOwner)
        foreign:perform()
    else dose:perform() end
    for i=1,20 do T.tick(p,false) end
    assert(p.pillRequests==1 and p.doses==0 and own.uses==5 and C.status(p).active,
        "No premature retry after ambiguous native completion or ordinary takeover")
    C.stop(p)
end
print("PASS foreign action identity is preserved and ambiguous completion or cancellation never redoses")

do
    local p=survivor()
    local bottle=pill(p.inventory,5)
    local vitamin=pill(p.inventory,5,"Base.PillsVitamins")
    begin(p,"meditation",false)
    local takesVitamin=T.action(p,"ISTakePillAction",function()
        vitamin.uses=vitamin.uses-1
        p.values.FATIGUE=0.15
    end)
    takesVitamin.item=vitamin
    ISTimedActionQueue.add(takesVitamin)
    p.values.PAIN=18
    T.tick(p,false)
    assert(queued(p)[1]==takesVitamin and p.nativeHead==takesVitamin.action and not takesVitamin.stopped
        and not takesVitamin.autoMindfulOwner and p.pillRequests==0)
    assert(p.data.AutoMindfulPainCare.phase=="initial","Plain vitamins are not an ambiguous analgesic episode")
    takesVitamin:perform()
    local action=nextPill(p)
    assert(action.item==bottle and p.pillRequests==1 and p.doses==0 and vitamin.uses==4)
    action:perform()
    assert(bottle.uses==4 and p.doses==1)
    C.stop(p)
end
print("PASS manual plain vitamins do not lock out a subsequent legitimate painkiller")

for _,timing in ipairs({"immediate","delayed","too late"}) do
    local p=survivor()
    local bottle=pill(p.inventory,5)
    p.delayPainReceipt=timing~="immediate"
    begin(p,"meditation",false)
    p.values.PAIN=18
    local dose=nextPill(p)
    local foreign=T.action(p,"NativeManualWork")
    local child=T.action(p,"NativeManualChild")
    function foreign:start() ISTimedActionQueue.add(child) end
    ISTimedActionQueue.add(foreign)
    dose:perform() -- stock completion starts the foreign successor in the same call
    local handle=foreign.action
    T.tick(p,false)
    assert(queued(p)[1]==foreign and queued(p)[2]==child and p.nativeHead==handle
        and foreign.begins==1 and not foreign.autoMindfulOwner and not child.autoMindfulOwner)
    assert(p.pillRequests==1)
    if timing=="delayed" then
        for _=1,2 do T.tick(p,false) end
        assert(p.doses==0 and p.data.AutoMindfulPainCare.phase=="submitted")
        p.pendingPainReceipt()
        T.tick(p,false)
    elseif timing=="too late" then
        for _=1,9 do T.tick(p,false) end
        assert(p.data.AutoMindfulPainCare.phase=="uncertain","The detached receipt has the same acknowledgement deadline")
        p.pendingPainReceipt()
        T.tick(p,false)
    end
    assert(p.data.AutoMindfulPainCare.phase==(timing=="too late" and "uncertain" or "active"))
    assert(p.doses==1 and p.pillRequests==1 and bottle.uses==4 and not foreign.stopped)
    foreign:perform()
    assert(queued(p)[1]==child and p.nativeHead==child.action and child.begins==1 and not child.stopped)
    child:perform()
    p.effect,p.painDelta=-0.1,0
    T.tick(p,false)
    assert(p.pillRequests==1,"Never repeat on the first zero sample")
    if timing=="too late" then
        for _=1,15 do T.tick(p,false) end
        assert(p.pillRequests==1 and p.doses==1 and bottle.uses==4,"A late unattributable effect must not permit a retry")
    else
        p.delayPainReceipt=false
        local repeated=nextPill(p)
        assert(repeated~=dose and repeated.item==bottle and p.pillRequests==2)
        repeated:perform()
        for _=1,6 do T.tick(p,false) end
        assert(p.pillRequests==2 and p.doses==2 and bottle.uses==3,"Exactly one repeat after a confirmed effect wore off")
    end
    C.stop(p)
end
print("PASS immediate and bounded delayed owned receipts survive foreign successors without touching their queue")

local restarted=survivor()
pill(restarted.inventory,5)
restarted.dropPainReceipt=true
begin(restarted,"meditation",false); rise(restarted)
nextPill(restarted):perform()
C.stop(restarted,"Stopped by you.")
begin(restarted,"meditation",false)
rise(restarted)
for i=1,12 do T.tick(restarted,false) end
assert(restarted.pillRequests==1 and restarted.doses==0,"Stop/start cannot retry an uncleared pain episode")
restarted.values.PAIN,restarted.painMoodle=6,0
for i=1,32 do T.tick(restarted,false) end
restarted.dropPainReceipt=false
for _,pain in ipairs({11,12,14,16}) do
    restarted.values.PAIN,restarted.painMoodle=pain,1
    T.tick(restarted,false)
end
nextPill(restarted):perform()
assert(restarted.pillRequests==2 and restarted.doses==1,"A genuinely cleared interval permits a different episode")
C.stop(restarted)
print("PASS restart retains attempted dose; only a newly observed clear period rearms")

do
    -- Use the actual Nearby scanner with a deliberately tiny loaded map.
    local stub = package.loaded["AutoMindful/Nearby"]
    package.loaded["AutoMindful/Nearby"] = nil
    local real = require "AutoMindful/Nearby"
    stub.find, stub.scan, stub.invalidate = real.find, real.scan, real.invalidate
    local options = require "AutoMindful/Options"
    options.searchNearby = function() return true end
    function getGameSpeed() return 1 end
    BehaviorResult={Failed="Failed"}
    ISWalkToTimedAction={new=function(_,p,tile)
        return T.action(p,"ISWalkToTimedAction",function() p.square=tile end)
    end}
    luautils={walkAdj=function(p,tile,keep)
        assert(keep); ISTimedActionQueue.add(ISWalkToTimedAction:new(p,T.square(tile:getX()-1,tile:getY())))
        return true
    end}
    local p=survivor()
    local function floor(p)
        local tile=p:getSquare()
        function tile:getObjects() return T.list({}) end
        tile.getWorldObjects=tile.getObjects
        return tile
    end
    local origin=floor(p)
    local pantry=T.container(6,0)
    local target=pantry:getSourceGrid()
    local distant=pill(pantry,5)
    p.available={pantry}
    function pantry:isExplored() return true end
    local furniture={}
    function furniture:hasWater() return false end
    function furniture:getContainerCount() return 1 end
    function furniture:getContainerByIndex() return pantry end
    function target:getObjects() return T.list({furniture}) end
    function target:getWorldObjects() return T.list({}) end
    function getCell() return {getGridSquare=function(_,x,y,z)
        if x==6 and y==0 and z==0 then return target end
        if x==0 and y==0 and z==0 then return origin end
    end} end
    begin(p,"meditation",false)
    rise(p)
    local use=nextPill(p)
    assert(use.item==distant and p:getSquare()~=origin and p.inventory:contains(distant)
        and C.status(p).pendingReturns==1)
    use:perform()
    advance(p,function() return p:getSquare()==origin and pantry:contains(distant)
        and C.status(p).pendingReturns==0 and queued(p)[1] and queued(p)[1].Type=="Meditation" end)
    assert(p.doses==1 and p.pillRequests==1 and distant.uses==4)
    C.stop(p)

    p=survivor()
    origin=floor(p)
    p.available={pantry}
    begin(p,"meditation",false);rise(p)
    T.tick(p,false)
    local walk=queued(p)[1]
    if walk and walk.Type=="stand" then walk:perform(); walk=queued(p)[1] end
    assert(walk and walk.Type=="ISWalkToTimedAction")
    p.square=T.square(3,0) -- explicit native motion boundary while the owned walk is active
    p.values.PAIN,p.painMoodle=6,0
    advance(p,function() return p:getSquare()==origin and queued(p)[1] and queued(p)[1].Type=="Meditation" end)
    assert(p.pillRequests==0 and p.doses==0 and pantry:contains(distant) and distant.uses==4
        and C.status(p).pendingReturns==0)
    C.stop(p)
end
print("PASS distant known stock scouts, consumes once and returns; loss of eligibility returns without borrowing")
print("pain-journey: PASS (game effect and timed-action boundaries are explicit doubles)")
