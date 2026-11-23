next=nil -- shipped Kahlua compatibility
package.path='mods/AutoMindful/common/media/lua/client/?.lua;'..package.path
local P=require 'AutoMindful/PainCare'
CharacterStat={PAIN='pain',INTOXICATION='intox'}
function instanceof(i,k) return i.kind==k end

local count=0
local function test(name,f)
    f()
    count=count+1
    print("PASS "..name)
end
local function fixture(pain)
    local f={calls=0,state={},q={queue={}}}
    local p={pain=pain or 10,effect=0,delta=0,intox=0,sedative=0,md={}}
    local item={kind="DrainableComboItem",uses=10,fullType="Base.Pills",useDelta=.10000000149}
    f.p,f.item=p,item
    function p:getStats() return {get=function(_,key) return self[key] end} end
    function p:getMoodles() error("The 0–100 pain stat, not the delayed moodle, controls pills") end
    function p:getPainEffect() return self.effect end
    function p:getPainDelta() return self.delta end
    function p:getSleepingTabletEffect() return self.sedative end
    function p:getModData() return self.md end
    function p:getPlayerNum() return 0 end
    function p:hasTimedActions() return self.busy or false end
    function p:getCharacterActions() return {isEmpty=function() return not self.nativeHandle end} end
    function p:getInventory() return {contains=function(_,i) return i==item and not f.inaccessible end} end
    function item:getCurrentUses() return self.uses end
    function item:getFullType() return self.fullType end
    function item:getUseDelta() return self.useDelta end
    function item:getOnEat() return self.onEat end
    function item:getRequireInHandOrInventory() return self.requirement end
    ISTimedActionQueue={getTimedActionQueue=function() return f.q end,isPlayerDoingAction=function() return p.nativeBusy or false end}
    ISInventoryPaneContextMenu={getEatingMask=function(_,remove) assert(remove==false); return f.mask end,
        takePill=function(i,slot)
            assert(i==item and slot==0)
            f.calls=f.calls+1
            if f.noop then return end
            local a={Type="ISTakePillAction",character=p,item=item}
            f.q.current=a; f.q.queue={a}
            if f.extra then f.q.queue[2]={Type="ISTakePillAction",character=p,item=item} end
            if f.fail then error("throws after queueing once") end
        end}
    function f:tick(now)
        P.observeForeign(p,self.state,self.q.queue,now)
        P.observe(p,self.state,now)
        return P.wanted(p,self.state,now)
    end
    function f:queue(now)
        local ok,reason=P.queue(p,self.state,item,now)
        if ok then self.q.current.autoMindfulOwner=self.state end -- Controller.ownBatch
        return ok,reason
    end
    function f:finish(stopped)
        local a=assert(self.q.current)
        a.autoMindfulFinished=not stopped
        a.autoMindfulStopped=stopped
        self.q.current=nil; self.q.queue={}
    end
    function f:receipt(now) return P.receipt(p,self.state,now) end
    function f:effect(timer,delta) p.effect,p.delta=timer,delta end
    function f:phase() return p.md.AutoMindfulPainCare.phase end
    return f
end

test("plain stock Base.Pills, not a different medicine, mod item or empty pack",function()
    local f=fixture(); local i=f.item
    assert(P.eligible(i))
    for _,t in ipairs({"Other.Pills","Base.PillsBeta","Base.PillsSleepingTablets","Base.PillsVitamins","Base.PillsAntiDep"}) do
        i.fullType=t; assert(not P.eligible(i))
    end
    i.fullType="Base.Pills"; i.kind="Food"; assert(not P.eligible(i)); i.kind="DrainableComboItem"
    i.uses=0; assert(not P.eligible(i)); i.uses=1.5; assert(not P.eligible(i)); i.uses=1
    i.onEat="Custom"; assert(not P.eligible(i)); i.onEat=nil
    i.requirement={}; assert(not P.eligible(i)); i.requirement=nil
    i.useDelta=.2; assert(not P.eligible(i)); i.useDelta=.1; assert(P.eligible(i))
end)
test("at 10 immediately, no increase or moodle; below 10 is not eligible",function()
    local f=fixture(9.99); assert(not f:tick(0))
    f.p.pain=10
    assert(f:tick(250) and f:tick(1000) and f:tick(2000) and f:queue(2000))
    assert(f.calls==1 and f:phase()=="submitted" and not f:queue(2000))
    local plateau=fixture(27); assert(plateau:tick(0) and plateau:queue(0))
end)
test("no action while mask, intoxication, sedative, native activity or holder blocks it",function()
    local f=fixture(); assert(f:tick(0))
    f.mask=true; assert(not f:queue(0)); f.mask=nil
    f.p.intox=.01; assert(not f:queue(0)); f.p.intox=0
    f.p.sedative=.01; assert(not f:queue(0)); f.p.sedative=0
    f.p.busy=true; assert(not f:queue(0)); f.p.busy=nil
    f.p.nativeHandle=true; assert(not f:queue(0)); f.p.nativeHandle=nil
    f.p.nativeBusy=true; assert(not f:queue(0)); f.p.nativeBusy=nil
    f.q.current={}; assert(not f:queue(0)); f.q.current=nil
    f.q.queue={{Type="NativeAction"}}; assert(not f:queue(0)); f.q.queue={}
    f.inaccessible=true; assert(not f:queue(0)); f.inaccessible=nil
    assert(f.calls==0 and f:phase()=="initial" and f:queue(0))
end)
test("requires exact action completion plus the paired native effect, not use count",function()
    local f=fixture(21); assert(f:tick(0) and f:queue(0))
    f:effect(5400,.45); assert(not f:tick(100)); assert(f:phase()=="submitted")
    f:effect(0,0); f:finish(false)
    assert(not f:tick(200)); assert(f:receipt(200)=="pending")
    f.item.uses=9; assert(f:receipt(400)=="pending")
    f:effect(5400,0); assert(not f:tick(450)); assert(f:receipt(450)=="pending")
    f:effect(5400,.45); assert(not f:tick(500)); assert(f:receipt(500)=="confirmed")
    assert(f:phase()=="active" and f.calls==1 and not f:queue(500))
end)
test("waits for both native effect fields to clear, crosses no more than one dose",function()
    local f=fixture(24); assert(f:tick(0) and f:queue(0))
    f:finish(false); f:effect(5400,.45); assert(not f:tick(200)); assert(f:receipt(200)=="confirmed")
    f:effect(-.2,.45); assert(not f:tick(1000) and not f:tick(2000)) -- stock expiry frame before delta clears
    f:effect(.2,0); assert(not f:tick(2250)) -- presence of either still blocks
    f:effect(-.2,0); assert(not f:tick(2500) and not f:tick(3499))
    assert(f:tick(3500) and f:queue(3500) and not f:queue(3500) and f.calls==2)
end)
test("at exactly 10 after wear-off there is no repeat; strictly above 10 does repeat",function()
    local f=fixture(10); assert(f:tick(0) and f:queue(0))
    f:finish(false); f:effect(5400,.45); assert(not f:tick(100)); assert(f:receipt(100)=="confirmed")
    f:effect(0,0); assert(not f:tick(1000) and not f:tick(2000))
    assert(f:phase()=="wornOff" and not f:queue(2000))
    for t=3000,35000,1000 do assert(not f:tick(t)) end
    f.p.pain=10.01
    assert(f:tick(35500) and f:queue(35500) and f.calls==2)
end)
test("stable new pain episode may again use inclusive ten, no brief-dip reset",function()
    local f=fixture(18); f:effect(5400,.45); assert(not f:tick(0))
    f:effect(0,0); assert(not f:tick(1000)); assert(f:tick(2000)); assert(f:phase()=="wornOff")
    f.p.pain=9
    assert(not f:tick(2250)); f.p.pain=10; assert(not f:tick(3250) and f:phase()=="wornOff")
    f.p.pain=8
    for t=4000,34000,1000 do assert(not f:tick(t)) end
    f.p.pain=10
    assert(f:tick(35000) and f:phase()=="initial" and f:queue(35000))
end)
test("pre-existing effects and Stop/start never discard a confirmed active dose",function()
    local f=fixture(18); f:effect(.5,.45)
    assert(not f:tick(0) and f:phase()=="active")
    f.state={}; f:effect(-.5,.45); assert(not f:tick(5000))
    f:effect(-.5,0); assert(not f:tick(5500)); assert(f:tick(6500) and f:queue(6500))
    f:finish(false); f:effect(5400,.45); assert(not f:tick(7000)); assert(f:phase()=="active")
    f.state={} -- confirmed by observation even if UI did not poll before stopping
    f:effect(0,0); assert(not f:tick(9000)); assert(f:tick(10000))
end)
test("uncertain completion, timeout and Stop/start cannot replay the same episode",function()
    local f=fixture(18); assert(f:tick(0) and f:queue(0)); f:finish(false)
    assert(f:receipt(1000)=="pending" and f:receipt(9000)=="unconfirmed")
    f.state={}; assert(not f:tick(10000) and f:phase()=="uncertain")
    f:effect(5400,.45); assert(not f:tick(11000)) -- late/unattributed is not re-labelled
    f:effect(0,0); assert(not f:tick(12000) and not f:tick(13000) and not f:queue(13000))
    assert(f.calls==1)
    local restarted=fixture(16); assert(restarted:tick(0) and restarted:queue(0))
    restarted:finish(false); restarted.state={}
    assert(not restarted:tick(1000) and not restarted:queue(1000) and restarted:phase()=="uncertain")
end)
test("failed, refused or ambiguous dispatches never authorize a retry",function()
    for _,k in ipairs({"fail","noop","extra"}) do
        local f=fixture(17); f[k]=true; assert(f:tick(0) and not f:queue(0))
        assert(f.calls==1 and f:phase()=="uncertain")
        f.q.queue={};f.q.current=nil
        assert(not f:tick(1000) and not f:queue(1000))
    end
    local f=fixture(17); assert(f:tick(0) and f:queue(0)); f:finish(true)
    f:effect(5400,.45); assert(f:receipt(1000)=="unconfirmed" and f:phase()=="uncertain")
end)
test("foreign pill overrides even apparently successful automatic action",function()
    local f=fixture(18); assert(f:tick(0) and f:queue(0)); f:finish(false)
    f:effect(5400,.45); f.q.queue={{Type="ISTakePillAction"}}
    assert(not f:tick(100) and f:receipt(100)=="unconfirmed" and f:phase()=="uncertain")
    f.q.queue={}; f:effect(0,0)
    assert(not f:tick(1000) and not f:tick(2000) and not f:queue(2000))
    assert(f.calls==1)
end)
test("foreign plain vitamins wait their turn without poisoning initial or confirmed medication",function()
    local f=fixture(18)
    local vitamin=setmetatable({fullType="Base.PillsVitamins",useDelta=.20000000298},{__index=f.item})
    f.q.queue={{Type="ISTakePillAction",character=f.p,item=vitamin}}
    assert(not f:tick(0) and not f:queue(0) and f:phase()=="initial")
    f.q.queue={}
    assert(f:tick(250) and f:queue(250) and f.calls==1)
    f:finish(false)
    f.q.queue={{Type="ISTakePillAction",character=f.p,item=vitamin}}
    f:effect(5400,.45)
    assert(not f:tick(500) and f:receipt(500)=="confirmed" and f:phase()=="active")
    f:effect(0,0)
    assert(not f:tick(1250) and f:phase()=="active")
    f.q.queue={}
    assert(not f:tick(1500) and f:tick(2500) and f:queue(2500) and f.calls==2)
end)
test("lookalike vitamins with hooks, unknown medicines and unreadable items remain ambiguous",function()
    for _,altered in ipairs({
        {onEat="MyMod.ReplacePillEffect"}, {requirement={}}, {useDelta=.1}, {kind="Food"},
        {fullType="Other.PillsVitamins"}, {fullType="Base.PillsSleepingTablets"},
        {getOnEat=function() error("Unknown script") end},
    }) do
        local f=fixture(18)
        local base=setmetatable({fullType="Base.PillsVitamins",useDelta=.2},{__index=f.item})
        local vitamin=setmetatable(altered,{__index=base})
        f.q.queue={{Type="ISTakePillAction",character=f.p,item=vitamin}}
        assert(not f:tick(0) and f:phase()=="uncertain")
        f.q.queue={}
        assert(not f:tick(1000) and not f:queue(1000) and f.calls==0)
    end
end)
test("stale, invalid, or rewound samples do not establish wear-off",function()
    local f=fixture(18); f:effect(.01,.45); assert(not f:tick(0))
    f:effect(-.1,0); assert(not f:tick(1000) and not f:tick(4000) and not f:tick(200))
    f.p.delta=-.01; assert(not f:tick(800)); f.p.delta=0
    assert(not f:tick(1000) and not f:tick(1999) and f:tick(2000))
    assert(not P.wanted(f.p,f.state,4001))
    f.p.sedative=-.02; assert(f:tick(4100) and f:queue(4100))
end)
test("legacy attempted latch stays conservative until a newly observed clear interval",function()
    local f=fixture(18); f.p.md.AutoMindfulPainCare={attempted=true}
    assert(not f:tick(0) and f:phase()=="legacy")
    for t=1000,35000,1000 do f.p.pain=10; assert(not f:tick(t)) end
    f.p.pain=6
    for t=36000,66000,1000 do assert(not f:tick(t)) end
    f.p.pain=10
    assert(f:tick(67000) and f:queue(67000))
end)
test("legacy latch can recover only after an observed paired effect actually wears off",function()
    local f=fixture(23); f.p.md.AutoMindfulPainCare={attempted=true}
    f:effect(5400,0); assert(not f:tick(0) and f:phase()=="legacy")
    f:effect(0,0); assert(not f:tick(1000) and not f:tick(2000) and f:phase()=="legacy")
    f:effect(5400,.45); assert(not f:tick(3000) and f:phase()=="active")
    f:effect(-.02,.45); assert(not f:tick(4000) and f:phase()=="active")
    f:effect(-.02,0); assert(not f:tick(5000) and f:tick(6000) and f:queue(6000))
end)
test("concurrent foreign pill prevents a legacy observation from unlocking retries",function()
    local f=fixture(23); f.p.md.AutoMindfulPainCare={attempted=true}
    f.q.queue={{Type="ISTakePillAction"}}
    f:effect(5400,.45); assert(not f:tick(0) and f:phase()=="uncertain")
    f.q.queue={}; f:effect(0,0)
    assert(not f:tick(1000) and not f:tick(2000) and not f:queue(2000))
end)
print("pain care policy: "..count.." passed")
