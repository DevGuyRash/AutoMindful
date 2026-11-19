next=nil -- shipped Kahlua compatibility
package.path='mods/AutoMindful/common/media/lua/client/?.lua;'..package.path
local P=require 'AutoMindful/PainCare'
CharacterStat={PAIN='pain',INTOXICATION='intox'}; MoodleType={PAIN='pain'}
function instanceof(i,k) return i.kind==k end
local p,s,item,calls,mask,q,fail
local function reset()
 calls=0; mask=false; q={queue={}};fail=false;s={}
 p={pain=11,moodle=1,effect=0,delta=0,intox=0,sedative=0,md={},busy=false}
 function p:getStats() return {get=function(_,key)return self[key] end} end
 function p:getMoodles() return {getMoodleLevel=function()return self.moodle end} end
 function p:getPainEffect()return self.effect end
 function p:getPainDelta()return self.delta end
 function p:getSleepingTabletEffect()return self.sedative end
 function p:getModData()return self.md end
 function p:getPlayerNum()return 0 end
 function p:hasTimedActions()return self.busy end
 function p:getCharacterActions()return {isEmpty=function()return not self.nativeHandle end}end
 function p:getInventory()return {contains=function(_,i)return i==item end} end
 item={kind='DrainableComboItem',uses=10,onEat=nil,fullType='Base.Pills'}
 function item:getCurrentUses()return self.uses end
 function item:getFullType()return self.fullType end
 function item:getUseDelta()return 0.10000000149 end
 function item:getOnEat()return self.onEat end
 function item:getRequireInHandOrInventory()return nil end
 ISTimedActionQueue={getTimedActionQueue=function()return q end,isPlayerDoingAction=function()return p.nativeBusy or false end}
 ISInventoryPaneContextMenu={getEatingMask=function(_,remove)assert(remove==false);return mask end,
 takePill=function(i,slot)assert(i==item and slot==0);calls=calls+1;if fail then error('after enqueue')end end}
end
local function rising(latched)
 P.observe(p,s,0);p.pain=12;P.observe(p,s,1000);p.pain=13;P.observe(p,s,2000)
 if not latched then assert(P.wanted(p,s,2000)) end
end
reset();assert(P.eligible(item));item.onEat='Custom';assert(not P.eligible(item));item.onEat=nil
item.uses=0;assert(not P.eligible(item));item.uses=1.5;assert(not P.eligible(item));item.uses=10
item.fullType='Other.Pills';assert(not P.eligible(item))
reset();for n=0,10000,250 do P.observe(p,s,n);assert(not P.wanted(p,s,n))end
reset();rising();P.observe(p,s,2250);assert(P.wanted(p,s,2250));p.pain=12.99;P.observe(p,s,2500);assert(not P.wanted(p,s,2500))
reset();rising();assert(not P.wanted(p,s,4001));P.observe(p,s,5000);assert(not P.wanted(p,s,5000))
reset();rising();for n=2250,10250,250 do P.observe(p,s,n)end;assert(not P.wanted(p,s,10250))
reset();rising();mask=true;assert(not P.wanted(p,s,2000));assert(not P.queue(p,s,item,2000));assert(calls==0);mask=false
p.intox=1;assert(not P.queue(p,s,item,2000));p.intox=0;p.sedative=1;assert(not P.queue(p,s,item,2000));p.sedative=0
p.busy=true;assert(not P.queue(p,s,item,2000));p.busy=false
assert(P.queue(p,s,item,2000));assert(calls==1);assert(not P.queue(p,s,item,2000));assert(P.receipt(p,s,2100)=='pending')
item.uses=9;assert(P.receipt(p,s,2500)=='pending');p.effect=5400;p.delta=.45;assert(P.receipt(p,s,3000)=='confirmed')
local previous=s;s={};p.effect=0;p.delta=0;rising(true);assert(not P.wanted(p,s,2000))
p.pain=10;p.moodle=0;for n=3000,34000,1000 do P.observe(p,s,n)end
p.pain=11;p.moodle=1;P.observe(p,s,35000);p.pain=12;P.observe(p,s,36000);assert(P.wanted(p,s,36000))
reset();rising();assert(P.queue(p,s,item,2000));assert(P.receipt(p,s,2100)=='pending');assert(P.receipt(p,s,10100)=='unconfirmed');assert(not P.wanted(p,s,2000))
reset();rising();fail=true;assert(not P.queue(p,s,item,2000));assert(calls==1);assert(P.receipt(p,s,2000)=='unconfirmed');assert(not P.queue(p,s,item,2000));assert(calls==1)
reset();P.observeForeign(p,s,{{Type='ISTakePillAction',item=item}},0);rising(true);assert(not P.wanted(p,s,2000));s={};rising(true);assert(not P.wanted(p,s,2000))
reset();rising();p.effect=2;assert(not P.wanted(p,s,2000))
reset();p.effect=100;P.observe(p,s,0);p.effect=0;rising(true);assert(not P.wanted(p,s,2000))
reset();p.effect=-0.01;p.sedative=-0.01;rising();assert(P.queue(p,s,item,2000))
reset();P.observeForeign(p,s,{{Type='ISTakePillAction',item=item,autoMindfulOwner=s}},0);rising()
reset();p.getPainEffect=nil;local wanted,reason=P.wanted(p,s,0);assert(not wanted and reason==nil)
reset();item.fullType='Base.PillsSleepingTablets'
P.observeForeign(p,s,{{Type='ISTakePillAction',item=item}},0)
-- Client action has ended, but its sedative packet has not arrived yet.
item.fullType='Base.Pills';rising(true);assert(not P.queue(p,s,item,2000));assert(calls==0)
reset();P.observeForeign(p,s,{{Type='ISTakePillAction'}},0);rising(true);assert(not P.wanted(p,s,2000))
reset();P.observeForeign(p,s,{{Type='ISEatFoodAction',item=item},{Type='ISFitnessAction'}},0);rising()
reset();rising();p.nativeHandle=true;assert(not P.queue(p,s,item,2000));assert(calls==0)
p.nativeHandle=false;p.nativeBusy=true;assert(not P.queue(p,s,item,2000));assert(calls==0)
reset();P.observeForeign(p,s,{{Type='ISTakePillAction'}},0);p.pain=10;p.moodle=0
for n=0,40000,1000 do
 P.observe(p,s,n);P.observeForeign(p,s,{{Type='ISTakePillAction',autoMindfulOwner=s}},n)
end
assert(p.md.AutoMindfulPainCare.attempted)
for n=41000,69000,1000 do P.observe(p,s,n);P.observeForeign(p,s,{},n)end
assert(p.md.AutoMindfulPainCare.attempted)
P.observe(p,s,70000);assert(p.md.AutoMindfulPainCare.attempted)
P.observe(p,s,71000);assert(not p.md.AutoMindfulPainCare.attempted)
print('pain care policy passed')
