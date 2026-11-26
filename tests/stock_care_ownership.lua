-- Real installed stock queue, path, drinking and clothing Lua. Only the
-- Java action stack, replicated equipment, and item/world handles are doubles.
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
local T,C=AutoMindfulTest,AutoMindfulTest.controller
local function stock(path)
    if loadUpstream then return loadUpstream(path) end
    return assert(loadfile(assert(arg[1],"Pass the installed game media directory").."/lua/"..path))()
end
local function noop() end
package.preload.ISBaseObject=function()
    ISBaseObject={}
    function ISBaseObject:derive(kind) return setmetatable({Type=kind},{__index=self}) end
end
table.wipe=function(t) for key in pairs(t) do t[key]=nil end end
Events.OnTick={Add=noop}
for _,kind in ipairs({"ClimbThroughWindowState","ClimbOverFenceState","ClimbOverWallState","ClimbState",
        "ClimbDownState","CloseWindowState","OpenWindowState","ForceOpenState"}) do _G[kind]={instance=function() return {} end} end
ISInventoryPage={}
ISLogSystem={logAction=noop}
DebugType={Action={warn=noop}}
function triggerEvent() end
function sendEquip() end
function isForceDropHeavyItem() return false end
function isServer() return false end
function getPlayerHotbar() return nil end
function getGameSpeed() return 1 end
function getTextManager() return {getFontHeight=function() return 14 end} end
UIFont={Small="Small"}
CharacterActionAnims={Drink="Drink"}
ItemTag.CAN_EAT="CanEat"
ItemTag.WEARABLE="Wearable"
ItemTag.REPLACE_PRIMARY="ReplacePrimary"
ItemBodyLocation=setmetatable({}, {__index=function(_,key) return key end})
ISCraftingUI={ReturnItemToOriginalContainer=noop}
package.preload["ISUI/ISToolTip"]=function() return true end
stock("client/TimedActions/ISTimedActionQueue.lua")
stock("shared/TimedActions/ISBaseTimedAction.lua")
stock("shared/TimedActions/ISWearClothing.lua")
stock("shared/TimedActions/ISUnequipAction.lua")
stock("shared/TimedActions/ISDrinkFluidAction.lua")
stock("shared/TimedActions/ISEatFoodAction.lua")
ISToolTip=ISBaseObject:derive("ISToolTip")
local containers=ISInventoryPaneContextMenu.getContainers
stock("client/ISUI/ISInventoryPaneContextMenu.lua")
ISInventoryPaneContextMenu.transferIfNeeded=function(p,item) assert(item:getContainer()==p:getInventory()) end
ISInventoryPaneContextMenu.getContainers=containers
stock("client/Vehicles/TimedActions/ISPathFindAction.lua")
BehaviorResult={Failed="Failed",Working="Working"}

local function queue(p) return ISTimedActionQueue.getTimedActionQueue(p) end
local function head(p) return queue(p).queue[1] end
LuaTimedActionNew={new=function(a)
    return {lua=a,isStarted=function() return true end,hasStalled=function() return false end,
        setAllowedWhileDraggingCorpses=noop,setPathfinding=noop,getJobDelta=function() return 0 end,
        forceStop=function() a.nativeRequestedStop=true end}
end}
local function player()
    local p=T.playerNew(); p.sitting=false; p.kind="IsoPlayer"
    p.worn={}
    function p:isTimedActionInstant() return true end
    function p:getTimedActionTimeModifier() return 1 end
    function p:getCurrentState() return {} end
    function p:setIsFarming() end
    function p:startWearing(slot,item) self.worn[slot]=item end
    function p:setWornItem(slot,item) self:startWearing(slot,item); self.wearCount=(self.wearCount or 0)+1 end
    function p:removeWornItem(item)
        for k,v in pairs(self.worn) do if v==item then self.worn[k]=nil end end
    end
    function p:getWornItem(slot) return self.worn[slot] end
    function p:getWornItems()
        local entries={}
        for slot,item in pairs(self.worn) do
            entries[#entries+1]={getLocation=function() return slot end,getItem=function() return item end}
        end
        function entries:contains(item)
            for _,entry in ipairs(self) do if entry:getItem()==item then return true end end
            return false
        end
        return T.list(entries)
    end
    function p:getPrimaryHandItem() return nil end
    function p:getSecondaryHandItem() return nil end
    function p:getHumanVisual() return {getHairModel=function() return {contains=function() return false end} end} end
    function p:getInventory() return self.inventory end
    function p.inventory:setDrawDirty() end
    function p:getEmitter() return {isPlaying=function() return false end} end
    function p:setTimedActionToRetrigger(a) self.retrigger=a end
    function p:getTimedActionToRetrigger() return self.retrigger end
    function p:hasTimedActions() return self.nativeHead~=nil end
    function p:StartAction(handle)
        assert(not self.nativeHead,"A new action stole a draining Java head")
        self.nativeHead=handle
        handle.lua.starts=(handle.lua.starts or 0)+1
        -- Dress/drink animation setup isn't needed; stock perform, stop, and
        -- complete below exercise both the exact equip mutation and queue.
        if handle.lua.Type=="ISPathFindAction" then handle.lua:start() end
    end
    function p:StopAllActionQueue()
        local a=self.nativeHead and self.nativeHead.lua
        if a then a:stop() end
        self.nativeHead=nil
    end
    local route={pathToNearestTable=noop,update=function() return p.pathResult or BehaviorResult.Working end,
        cancel=function() if p.onCancelRoute then p.onCancelRoute() end end}
    function p:getPathFindBehavior2() return route end
    function p:setPath2() end
    return p
end
local function action(p,kind)
    local a=ISBaseTimedAction:new(p); a.Type=kind; a.maxTime=1
    return a
end
local function perform(p,a,apply)
    assert(head(p)==a and p.nativeHead==a.action and a.starts==1)
    if apply then assert(a:complete()) end
    p.nativeHead=nil
    a:perform()
end
local function tick(p,count) for _=1,count or 1 do T.tick(p,false) end end
local nearby, options=require "AutoMindful/Nearby",require "AutoMindful/Options"
local function route(mode)
    local p=player(); p.values.THIRST=.35
    options.searchNearby=function() return true end
    local square=T.square(3,0)
    local obj={getMasterObject=function(self) return self end}
    nearby.find=function(_,kind)
        if kind=="water" then return {key="blocked",object=obj,square=square} end
    end
    luautils={walkAdjObject=function(walker)
        ISTimedActionQueue.add(ISPathFindAction:pathToNearest(walker,{2.5,0.5,0}))
        return true
    end}
    assert(C.start(p,mode or "meditation",false))
    if mode=="recovery" then
        -- Recovery must not send an outbound walk until a continuous idle gap.
        local function idleSample()
            T.now=T.now+250
            C.update(p)
        end
        for _=1,7 do idleSample() end
        assert(not head(p),"Autopilot scouted before the idle grace elapsed")
        for _=1,12 do
            if head(p) then break end
            idleSample()
        end
    else
        tick(p,mode and 3 or 1)
    end
    assert(head(p) and head(p).Type=="ISPathFindAction")
    return p,head(p)
end
local function clothing(p,slot,name)
    local item=T.add(p.inventory,T.item("InventoryItem",{name=name,fullType="Base."..name}))
    function item:IsClothing() return true end
    function item:IsInventoryContainer() return false end
    function item:getCategory() return "Clothing" end
    function item:getBodyLocation() return slot end
    function item:isBroken() return false end
    function item:isWorn() return p:getWornItem(slot)==self end
    function item:getUnequipSound() return nil end
    function item:getClothingItem() return nil end
    function item:setJobDelta() end
    return item
end
local function drinking()
    options.searchNearby=function() return false end
    local p=player()
    local mask=clothing(p,ItemBodyLocation.MASK,"Respirator")
    local glasses=clothing(p,ItemBodyLocation.EYES,"Glasses")
    p:startWearing(ItemBodyLocation.MASK,mask); p:startWearing(ItemBodyLocation.EYES,glasses)
    local bottle=T.add(p.inventory,T.water())
    function bottle.fluid:getFilledRatio() return self.amount end
    function bottle:getEatSound() return "" end
    function bottle.fluid:getCustomDrinkSound() return "" end
    function bottle:getEatType() return nil end
    function bottle:getEatTime() return 1 end
    function bottle:setJobDelta() end
    p.values.THIRST=.35
    assert(C.start(p,"meditation",false)); tick(p)
    assert(head(p) and head(p).Type=="ISUnequipAction" and head(p).item==mask)
    perform(p,head(p),not T.client)
    assert(head(p) and head(p).Type=="ISDrinkFluidAction" and queue(p).queue[2].Type=="ISWearClothing")
    return p,mask,glasses
end

local passed,failed=0,0
local function test(name,run)
    local ok,why=pcall(run)
    if ok then passed=passed+1; print("PASS "..name)
    else failed=failed+1; print("FAIL "..name..": "..tostring(why)) end
end

test("outbound native failure keeps foreign identities and order until Java drains",function()
    local p,walk=route()
    local workout,map=action(p,"AutoAllExercise"),action(p,"ISReadWorldMap")
    ISTimedActionQueue.add(workout); ISTimedActionQueue.add(map)
    p.pathResult=BehaviorResult.Failed; walk:update()
    assert(walk.nativeRequestedStop and walk.autoMindfulPathFailed)
    local q=queue(p)
    walk:stop()
    assert(#q.queue==3 and q.queue[1]==walk and q.queue[2]==workout and q.queue[3]==map
        and not workout.starts and not map.starts,"Native outbound stop erased, reordered or prematurely started foreign work")
    assert(p.nativeHead==walk.action)
    p.nativeHead=nil; q:tick()
    assert(head(p)==workout and workout.starts==1 and not map.starts)
    perform(p,workout); assert(head(p)==map and map.starts==1)
    perform(p,map); assert(not head(p) and not q.autoMindfulHandoff)
end)

test("a waiter appended inside outbound stop survives; released world cancel stays canceled",function()
    local p,walk=route()
    local map=action(p,"ISReadWorldMap")
    p.onCancelRoute=function() ISTimedActionQueue.add(map) end
    p.cancelInput=true
    walk:update()
    assert(walk.nativeRequestedStop and not walk.autoMindfulPathFailed)
    walk:stop(); p.cancelInput=false
    assert(head(p)==walk and queue(p).queue[2]==map and not map.starts)
    p.nativeHead=nil; tick(p)
    assert(head(p)==map and map.starts==1 and not C.status(p).active)
    perform(p,map); tick(p,4); assert(not head(p) and not C.status(p).active and #p.cards==1)
end)

test("manual movement interrupts a Autopilot route without an automatic walk back",function()
    local p,walk=route("recovery")
    local job=action(p,"UnrelatedWalkAndChop")
    ISTimedActionQueue.add(job)
    p.movementInput,p.running=true,true
    walk:update(); assert(walk.nativeRequestedStop and not walk.autoMindfulPathFailed)
    walk:stop()
    p.movementInput,p.running=false,false
    p.square=T.square(5,2,1)
    local relocated=p.square
    p.values.THIRST=0
    p.nativeHead=nil; tick(p)
    assert(C.status(p).active and head(p)==job and job.starts==1 and not job.autoMindfulOwner)
    perform(p,job); tick(p,6)
    assert(C.status(p).active and not head(p) and p.square==relocated
        and C.status(p).phase=="recovery-idle" and #p.cards==0)
    C.stop(p)
end)

test("stock wear restores only the exact temporarily removed mask after a workout",function()
    local p,mask,glasses=drinking()
    assert(not p:getWornItem(ItemBodyLocation.MASK))
    local workout=action(p,"AutoAllExercise"); ISTimedActionQueue.add(workout)
    tick(p); assert(head(p)==workout and workout.starts==1 and workout.autoMindfulOwner==nil)
    p.values.THIRST=0 -- no second drink needed while testing cleanup
    perform(p,workout)
    tick(p,4)
    local restore=head(p)
    assert(restore and restore.Type=="ISWearClothing" and restore.item==mask and restore:isValid(),
        "The native wear action was lost when handing off to foreign work")
    perform(p,restore,true); tick(p)
    assert(p:getWornItem(ItemBodyLocation.MASK)==mask and p:getWornItem(ItemBodyLocation.EYES)==glasses and p.wearCount==1)
end)

test("explicitly stopping restores the mask without restarting training",function()
    local p,mask=drinking()
    assert(not p:getWornItem(ItemBodyLocation.MASK))
    C.stop(p,"Stopped manually.")
    p.values.THIRST=0
    tick(p,4)
    local restore=head(p)
    assert(restore and restore.Type=="ISWearClothing" and restore.item==mask)
    perform(p,restore,true); tick(p,4)
    assert(p:getWornItem(ItemBodyLocation.MASK)==mask and p.wearCount==1
        and not head(p) and not C.status(p).active and C.status(p).phase=="stopped")
end)

test("a manually chosen replacement mask stays on, with no automatic rewear",function()
    local p,old,glasses=drinking()
    local replacement=clothing(p,ItemBodyLocation.MASK,"ReplacementRespirator")
    local manual=ISWearClothing:new(p,replacement)
    ISTimedActionQueue.add(manual)
    tick(p); assert(head(p)==manual and not manual.autoMindfulOwner)
    p.values.THIRST=0
    perform(p,manual,true); tick(p,4)
    assert(p:getWornItem(ItemBodyLocation.MASK)==replacement and p.inventory:contains(old))
    assert(p:getWornItem(ItemBodyLocation.EYES)==glasses and p.wearCount==1)
    assert(not head(p) or head(p).Type~="ISWearClothing")
end)

test("a server-delayed unequip and rewear both require observed equipment receipts",function()
    T.client=true
    local p,mask=drinking()
    assert(p:getWornItem(ItemBodyLocation.MASK)==mask)
    local workout=action(p,"AutoAllExercise"); ISTimedActionQueue.add(workout)
    tick(p); assert(head(p)==workout)
    p.values.THIRST=0
    perform(p,workout); tick(p,3)
    assert(not head(p),"Client animation alone authorized a rewear")
    p:removeWornItem(mask) -- remote unequip actually applied
    tick(p)
    local restore=head(p)
    assert(restore and restore.Type=="ISWearClothing" and restore.item==mask and restore:isValid())
    perform(p,restore) -- not authoritative on the client
    tick(p,3)
    assert(not head(p) and not p:getWornItem(ItemBodyLocation.MASK),"Retried before equipment sync")
    p:startWearing(ItemBodyLocation.MASK,mask)
    tick(p,3)
    assert(p:getWornItem(ItemBodyLocation.MASK)==mask and (not head(p) or head(p).Type~="ISWearClothing"))
    T.client=false
end)

local consumables=require "AutoMindful/Consumables"
local function meal(p)
    function p.inventory:getFirstTagEvalRecurse() return nil end
    function p.inventory:getFirstTypeEvalRecurse() return nil end
    function p.inventory:containsID(id) return self:getItemById(id)~=nil end
    local food=T.add(p.inventory,T.item("Food",{hunger=-.4,baseHunger=-.4}))
    food.getEatType,food.getCustomEatSound,food.getCustomMenuOption=noop,noop,noop
    food.getEatTime=function() return 1 end
    food.getAge=function() return 0 end
    food.getOffAgeMax=function() return 1000000000 end
    food.getOnEat=noop
    food.setJobDelta=noop
    p.values.HUNGER=.2
    function p:Eat(i,quantity)
        assert(i==food and quantity>0)
        self.bites=(self.bites or 0)+1
    end
    return food
end

test("pre-dispatch: queue skips only the unsafe meal, including a replaced MP item with the same ID",function()
    for _,client in ipairs({false,true}) do
        T.client=client
        local p=player()
        local food=meal(p)
        local first=action(p,"ManualTask")
        ISTimedActionQueue.add(first)
        assert(consumables.consume(p,food,"food"))
        local eating=queue(p).queue[2]
        local nextManual=action(p,"AutoAllExercise")
        ISTimedActionQueue.add(nextManual)
        if client then
            local changed=meal(p); changed.id=food:getID(); changed.poisonPower=1
            T.remove(p.inventory,food)
        else food.rotten=true end
        perform(p,first)
        assert(not eating.starts and head(p)==nextManual and nextManual.starts==1 and not p.bites,
            "unsafe meal was submitted or the unrelated successor was lost")
    end
    T.client=false
end)

test("a rotten meal neither completes nor takes a partial bite on stock SP cancellation",function()
    T.client=false
    local p=player(); local food=meal(p)
    assert(consumables.consume(p,food,"food"))
    local eating=head(p); assert(eating and eating.starts==1)
    local other=action(p,"ManualMap"); ISTimedActionQueue.add(other)
    food.rotten=true
    eating.action.getJobDelta=function() return .5 end
    eating:complete() -- no intervening Lua validity or controller poll
    assert(not p.bites,"native complete ate a rotten item")
    eating:stop() -- stock stop's serverStop also eats a fraction
    assert(not p.bites and not other.starts,"stock partial bite or premature successor")
    p.nativeHead=nil; queue(p):tick()
    assert(head(p)==other and other.starts==1,"only the unsafe meal may be stopped")
    -- This is a deliberate manual choice: automatic safety must never hook the class.
    ISEatFoodAction:new(p,food,.5):complete()
    assert(p.bites==1,"manual actions were intercepted")
end)

test("liquid food: clean first sip, zero later sips after contamination, including native completion",function()
    T.client=false
    local p=drinking()
    local drink=head(p); local bottle=drink.item
    bottle.syncItemFields=noop
    function p:DrinkFluid(i,frac)
        assert(i==bottle and frac>0)
        self.sips=(self.sips or 0)+1; i.fluid.amount=i.fluid.amount*(1-frac)
    end
    drink:updateEat(.25); assert(p.sips==1)
    local before=bottle.fluid.amount
    bottle.fluid.isTainted=function() return true end
    drink:updateEat(.75); drink:complete()
    assert(p.sips==1 and bottle.fluid.amount==before,"stock incremental/final sip drank the changed mixture")
end)

assert(failed==0,tostring(failed).." stock care ownership regression(s)")
print("stock care ownership: "..passed.." passed (actual stock Lua with native boundaries doubled)")
