-- Unmodified B42.22 sources pinned at 3b21e63fe4905a0a300a4021d05d01a9bb534729.
-- Native/JVM inventory, animation, dose effect and server transport are doubles.
-- Explicit complete() calls below model the engine authority boundary in tests
-- only. Production must queue the stock action, never invoke complete/perform.
local function stock(path)
    if loadUpstream then return loadUpstream(path) end
    return assert(loadfile(assert(arg[1],"Pass external game media root").."/lua/"..path))()
end
ISBaseObject={}
function ISBaseObject:derive(kind) local o={Type=kind}; setmetatable(o,{__index=self}); return o end
package.preload.ISBaseObject=function() return ISBaseObject end
stock("shared/TimedActions/ISBaseTimedAction.lua")
package.preload["TimedActions/ISBaseTimedAction"]=function() return ISBaseTimedAction end
package.preload["ISUI/ISToolTip"]=function() return true end
package.preload["TimedActions/ISInventoryTransferUtil"]=function() return true end
stock("shared/TimedActions/ISTakePillAction.lua")
ISToolTip=ISBaseObject:derive("ISToolTip")
function getTextManager() return {getFontHeight=function() return 14 end} end
UIFont={Small="Small"}
stock("client/ISUI/ISInventoryPaneContextMenu.lua")
local client,server=false,false
function isClient() return client end
function isServer() return server end
function getText(s) return s end
ItemTag={SMOKABLE="Smokable"}
CharacterActionAnims={Eat="Eat",TakePills="TakePills"}
ISLogSystem={logAction=function() end}
local effectsSent=0
function sendPlayerEffects(p) effectsSent=effectsSent+1; assert(p) end
local function item(id,kind)
    local i={id=id,kind=kind or "Base.Pills",uses=10,container={setDrawDirty=function() end}}
    function i:getID() return self.id end
    function i:getFullType() return self.kind end
    function i:getCurrentUsesFloat() return self.uses end
    function i:getUseDelta() return 1 end
    function i:getEatTime() return 0 end
    function i:getEatType() return nil end
    function i:hasTag() return false end
    function i:getRequireInHandOrInventory() return nil end
    function i:getCustomMenuOption() return nil end
    function i:setJobType(v) self.jobType=v end
    function i:setJobDelta(v) self.jobDelta=v end
    function i:getContainer() return self.container end
    return i
end
local function player()
    local p={items={},doseCalls=0,netEffect=0,queue={},completed=0}
    p.inventory={contains=function(_,i) return p.items[i.id]==i end,
        containsID=function(_,id) return p.items[id]~=nil end,
        getItemById=function(_,id) return p.items[id] end}
    function p:getInventory() return self.inventory end
    function p:getPlayerNum() return 0 end
    function p:isTimedActionInstant() return false end
    function p:setIsFarming() end
    function p:getBodyDamage() return {JustTookPill=function(_,i)
        self.doseCalls=self.doseCalls+1; i.uses=i.uses-1
        -- Deliberately separate applied dose from delayed client effect receipt.
        self.pendingEffect=1
    end} end
    return p
end
local current
function getSpecificPlayer(slot) assert(slot==0); return current end
ISTimedActionQueue={getTimedActionQueue=function(p)
    return {onCompleted=function(_,a) p.completed=p.completed+1 end,
        resetQueue=function() p.resets=(p.resets or 0)+1 end}
end,add=function(a) current.queue[#current.queue+1]=a end}
local function native(a)
    a.action={setOverrideHandModelsObject=function() end,
        setAnimVariable=function() end,setActionAnim=function() end,getJobDelta=function() return .5 end}
end
local passed=0
local function test(name,f) f(); passed=passed+1; print("PASS "..name) end

test("single-player identity validation and native perform/complete separation",function()
    client,server=false,false; current=player()
    local i=item(1); current.items[1]=i
    local a=ISTakePillAction:new(current,i); native(a)
    assert(a:isValid() and a.maxTime==165 and not a.stopOnAim and a.stopOnRun)
    a:start(); a:update(); a:perform()
    assert(i.uses==10 and current.doseCalls==0 and current.completed==1,"perform incorrectly proves consumption")
    assert(a:complete()); assert(i.uses==9 and current.doseCalls==1 and effectsSent==0)
    current.items[1]=item(1)
    assert(not a:isValid(),"SP accepts different item identity")
end)

test("MP ID validation rebinds canonical item at start; completion is authoritative",function()
    client,server=true,false; current=player()
    local stale,canonical=item(7),item(7); current.items[7]=canonical
    local a=ISTakePillAction:new(current,stale); native(a)
    assert(a:isValid()); a:start(); assert(a.item==canonical)
    a:perform(); assert(current.doseCalls==0 and canonical.uses==10 and stale.uses==10)
    server=true; client=false -- model server executing completion, not client queue drain
    assert(a:complete()); assert(current.doseCalls==1 and effectsSent==1 and canonical.uses==9 and stale.uses==10)
    assert(current.netEffect==0 and current.pendingEffect==1,"Queue completion must not invent replicated effect")
    current.netEffect=current.pendingEffect; current.pendingEffect=nil -- explicit transport boundary
    assert(current.netEffect==1)
    current.items[7]=nil; assert(not a:isValid())
end)

test("native cancellation neither consumes a dose nor applies an effect",function()
    client,server=true,false; current=player(); local i=item(8); current.items[8]=i
    local a=ISTakePillAction:new(current,i); native(a); a:start(); a:stop()
    assert(i.uses==10 and current.doseCalls==0 and current.resets==1 and i.jobDelta==0)
end)

-- Preserve the complete stock takePill/onPillsItems implementation. Only its
-- transfer/mask/container-return dependencies are explicit queue-boundary spies.
local calls={}
ISInventoryPane={getActualItems=function(items) return items end}
ISInventoryPaneContextMenu.transferIfNeeded=function(p,i)
    calls[#calls+1]="transfer"; ISTimedActionQueue.add({Type="transfer",item=i,character=p})
end
ISInventoryPaneContextMenu.getEatingMask=function(p,remove)
    assert(remove); calls[#calls+1]="mask"; ISTimedActionQueue.add({Type="unmask",character=p}); return "mask-item"
end
ISWearClothing={new=function(_,p,mask,duration) assert(mask=="mask-item" and duration==50); return {Type="wear",character=p} end}
ISCraftingUI={ReturnItemToOriginalContainer=function(p,i)
    calls[#calls+1]="return"; ISTimedActionQueue.add({Type="return",item=i,character=p})
end}
test("stock single-selection entry queues one dose with transfer/mask/return order",function()
    client,server=false,false; current=player(); calls={}
    local selected,other=item(9),item(10)
    ISInventoryPaneContextMenu.onPillsItems({selected,other},0)
    local q=current.queue
    assert(#q==5 and q[1].Type=="transfer" and q[2].Type=="unmask" and q[3].Type=="ISTakePillAction" and q[4].Type=="wear" and q[5].Type=="return")
    assert(q[1].item==selected and q[3].item==selected and q[5].item==selected)
    assert(current.doseCalls==0 and selected.uses==10 and other.uses==10)
    assert(table.concat(calls,",")=="transfer,mask,return")
end)

test("stock entry is intentionally not a painkiller guard",function()
    current=player(); local unsafe=item(11,"Base.PillsSleepingTablets")
    ISInventoryPaneContextMenu.takePill(unsafe,0)
    assert(current.queue[3].item==unsafe,"Upstream changed: reassess selector requirements")
    -- Production selector must require Base.Pills; stock takePill alone cannot
    -- distinguish painkillers from other medicines or consumable substances.
end)
-- Run the real stock menu, timed action and AutoMindful medication guard
-- together. Model Java JustTookPill's separate vitamin/analgesic branches and
-- the network arrival of the positive effect/delta explicitly.
package.path='mods/SecondNature/common/media/lua/client/?.lua;'..package.path
local PainCare=require "AutoMindful/PainCare"
CharacterStat={PAIN="pain",INTOXICATION="intox"}
function instanceof(i,k) return i and i.drainable and k=="DrainableComboItem" end
ISInventoryPaneContextMenu.transferIfNeeded=function() end
ISInventoryPaneContextMenu.getEatingMask=function() return nil end
ISCraftingUI.ReturnItemToOriginalContainer=function() end
ISTimedActionQueue.getTimedActionQueue=function(p)
    return {queue=p.queue,onCompleted=function(_,a) assert(table.remove(p.queue,1)==a) end}
end
ISTimedActionQueue.isPlayerDoingAction=function(p) return #p.queue>0 end

local function packageOfPills(id,fullType,useDelta)
    local i=item(id,fullType)
    i.drainable=true
    function i:getUseDelta() return useDelta end
    function i:getCurrentUses() return self.uses end
    function i:getOnEat() return nil end
    return i
end

local function medFixture()
    local p=player()
    current=p
    local vitamin=packageOfPills(20,"Base.PillsVitamins",.20000000298)
    local bottle=packageOfPills(21,"Base.Pills",.10000000149)
    p.items[20],p.items[21]=vitamin,bottle
    p.pain,p.intox,p.netEffect,p.netDelta,p.fatigue=18,0,0,0,.35
    function p:getModData() self.data=self.data or {}; return self.data end
    function p:getStats() return {get=function(_,k) return self[k] end} end
    function p:getPainEffect() return self.netEffect end
    function p:getPainDelta() return self.netDelta end
    function p:getSleepingTabletEffect() return 0 end
    function p:hasTimedActions() return #self.queue>0 end
    function p:getCharacterActions() return {isEmpty=function() return #self.queue==0 end} end
    function p:getBodyDamage()
        return {JustTookPill=function(_,i)
            i.uses=i.uses-1
            if i==vitamin then p.fatigue=0
            else
                assert(i==bottle)
                p.doseCalls=p.doseCalls+1
                p.pendingEffect=5400
            end
        end}
    end
    return p,vitamin,bottle
end

local function tickPain(p,state,now)
    PainCare.observeForeign(p,state,p.queue,now)
    PainCare.observe(p,state,now)
    return PainCare.wanted(p,state,now)
end

test("a stock vitamin action waits normally, changes fatigue, and leaves analgesic eligibility intact",function()
    client,server=false,false
    local p,vitamin,bottle=medFixture()
    local state={}
    ISInventoryPaneContextMenu.takePill(vitamin,0)
    local a=p.queue[1]; native(a)
    assert(a.Type=="ISTakePillAction" and a.item==vitamin and a:isValid())
    assert(not tickPain(p,state,0) and not PainCare.queue(p,state,bottle,0))
    assert(p.data.AutoMindfulPainCare.phase=="initial")
    a:start(); a:perform()
    assert(a:complete())
    assert(#p.queue==0 and vitamin.uses==9 and p.fatigue==0 and p.netEffect==0 and p.doseCalls==0)
    assert(tickPain(p,state,500) and PainCare.queue(p,state,bottle,500))
    assert(#p.queue==1 and p.queue[1].item==bottle and not PainCare.queue(p,state,bottle,500))
end)

test("an exact stock MP pill can confirm after a foreign successor, then only repeat after wear-off",function()
    client,server=true,false
    local p,_,bottle=medFixture()
    local state={}
    assert(tickPain(p,state,0) and PainCare.queue(p,state,bottle,0))
    local a=p.queue[1]; native(a); a.autoMindfulOwner=state; a:start()
    local successor={Type="NativePlayerAction"}
    ISTimedActionQueue.add(successor)
    a:perform(); a.autoMindfulFinished=true
    assert(p.queue[1]==successor and p.doseCalls==0 and bottle.uses==10)
    assert(not tickPain(p,state,250))
    PainCare.detach(p,state,250)
    assert(not tickPain(p,state,750) and p.data.AutoMindfulPainCare.phase=="submitted")
    client,server=false,true
    assert(a:complete())
    client,server=true,false
    p.netEffect,p.netDelta=p.pendingEffect,.45
    assert(not tickPain(p,state,1000) and p.data.AutoMindfulPainCare.phase=="active")
    assert(p.queue[1]==successor and not successor.autoMindfulOwner and p.doseCalls==1 and bottle.uses==9)
    p.queue={}
    p.netEffect,p.netDelta=-.2,.45
    assert(not tickPain(p,state,1500) and not tickPain(p,state,2500))
    p.netDelta=0
    assert(not tickPain(p,state,2750) and tickPain(p,state,3750))
    assert(PainCare.queue(p,state,bottle,3750) and not PainCare.queue(p,state,bottle,3750))
end)

print("stock pain lifecycle: "..passed.." passed; native/server boundaries doubled")
