-- The kitchen: raw food is cooked on a powered stove, taken out once cooked
-- (or before it burns), and the stove is always turned off again.
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
local T=AutoMindfulTest
local Kitchen=require "AutoMindful/Kitchen"
local Options=require "AutoMindful/Options"
local function passed(text) print("PASS "..text) end

-- World -----------------------------------------------------------------------
local squares={}
local function square(x,y)
    local s=T.square(x,y,0)
    s.objects={}
    function s:getObjects() return T.list(self.objects) end
    function s:getBuilding() return "house" end
    squares[x..":"..y]=s
    return s
end
function getCell() return {getGridSquare=function(_,x,y,z) return z==0 and squares[x..":"..y] or nil end} end
Storage=require "AutoMindful/Storage"
Storage.permitted=function() return true end

local function stove(x,y)
    local s=square(x,y)
    local c=T.container(x,y); c.square=s
    function c:getType() return "stove" end
    function c:isPowered() return not self.off end
    local o={kind="IsoStove",container=c,on=false,sq=s}
    function o:getContainer() return self.container end
    function o:getSquare() return self.sq end
    function o:Activated() return self.on end
    function o:getObjectIndex() return 1 end
    function o:getMaxTemperature() return 200 end
    s.objects[#s.objects+1]=o
    return o
end

local function food(properties)
    local p=properties or {}
    local item=T.item("Food",p)
    item.name=p.name or "Chicken"
    function item:isCookable() return self.cookable ~= false end
    function item:getMinutesToCook() return 30 end
    function item:getMinutesToBurn() return 60 end
    function item:getCookingTime() return self.time or 0 end
    function item:getOffAge() return 2 end
    function item:isFavorite() return self.favorite or false end
    return item
end

-- Actions ---------------------------------------------------------------------
local queued={}
ISTimedActionQueue={add=function(action) queued[#queued+1]=action; return action end}
ISToggleStoveAction={new=function(_,player,object)
    return {Type="toggle",object=object,isValid=function(self) return self.object:getObjectIndex() ~= -1 end,
        perform=function(self) if self:isValid() then self.object.on=not self.object.on end end}
end}
ISInventoryTransferUtil={newInventoryTransferAction=function(_,item,from,to)
    return {Type="transfer",item=item,from=from,to=to,isValid=function(self) return self.from:contains(self.item) end,perform=function(self)
        T.remove(self.from,self.item); T.add(self.to,self.item) end}
end}
local walks=0
luautils={walkAdj=function() walks=walks+1; return true end}

local function survivor(x,y)
    local p=T.playerNew()
    local here=square(x or 0,y or 0)
    p.inventory.square=here
    function p:getSquare() return here end
    function p:isDead() return false end
    function p:getModData() self.modData=self.modData or {}; return self.modData end
    function p:getInventory() return self.inventory end
    p.values.HUNGER=.3
    return p
end
local phase
local parts={available=function() return false end,
    setPhase=function(state,name,message) state.phase,state.message=name,message end,
    ownBatch=function(player,state,name,message,fn)
        queued={}
        fn()
        state.pending=#queued>0 and queued or nil
        phase,state.phase,state.message=name,name,message
        return #queued>0
    end}
Kitchen.bind(parts)
Options.cookMeals=function() return true end
local function run() for _,action in ipairs(queued) do action:perform() end; queued={} end
local function state() return {active=true,rejected={}} end

-- Food rules --------------------------------------------------------------------
do
    assert(Kitchen.cookable(food()),"Raw chicken is worth cooking")
    for _,bad in ipairs({{rotten=true},{burnt=true},{frozen=true},{cooked=true},{poison=true},{favorite=true},{cookable=false},
            {sickness=.1},{onEat="Poison"},{hunger=0}}) do
        assert(not Kitchen.cookable(food(bad)),"Cooking does not make this one worth it")
    end
    passed("only safe raw food is cooked")
end

-- Start, cook, finish -------------------------------------------------------------
do
    squares={}
    local p=survivor(0,0); local s=state()
    local oven=stove(1,0)
    local raw=T.add(p.inventory,food())
    assert(Kitchen.meal(p,s,1000),"Starts cooking when only raw food is known")
    run()
    assert(oven.on and oven.container:contains(raw),"The chicken is in the oven and the oven is on")
    assert(Kitchen.ledger(p) and Kitchen.ledger(p).item==raw:getID(),"The stove is written down")
    Kitchen.settle(p,s,1100)
    s.pending=nil
    raw.time=10
    assert(Kitchen.duty(p,s,2000,true) and s.phase=="kitchen-watch" and s.message:find("33%",1,true),"Watches while it cooks: "..tostring(s.message))
    assert(not Kitchen.urgent(p),"Watching is not urgent")
    raw.time, raw.cooked = 31, true
    assert(Kitchen.urgent(p),"A cooked dish is urgent")
    assert(Kitchen.duty(p,s,3000,true) and phase=="kitchen")
    local kinds={}; for _,a in ipairs(queued) do kinds[#kinds+1]=a.Type end
    assert(table.concat(kinds,",")=="toggle,transfer","Off first, then out: "..table.concat(kinds,","))
    run()
    assert(not oven.on and p.inventory:contains(raw),"Stove off, dish in hand")
    assert(not Kitchen.duty(p,s,3100,true) and Kitchen.ledger(p)==nil,"Nothing left to look after")
    passed("cooks, takes the dish out and turns the stove off")
end

-- Burning, power cuts, danger ---------------------------------------------------
do
    squares={}
    local p=survivor(0,0); local s=state()
    local oven=stove(1,0)
    local raw=T.add(p.inventory,food())
    Kitchen.meal(p,s,1000); run(); Kitchen.settle(p,s,1100)
    raw.time=49
    assert(Kitchen.urgent(p) and Kitchen.duty(p,s,2000,true) and s.message:find("before it burns",1,true),"Out before it burns: "..s.message)
    run()
    assert(not oven.on and not oven.container:contains(raw))
    passed("takes the dish out well before it burns")
end
do
    squares={}
    local p=survivor(0,0); local s=state()
    local oven=stove(1,0)
    local raw=T.add(p.inventory,food())
    Kitchen.meal(p,s,1000); run(); Kitchen.settle(p,s,1100)
    oven.container.off=true
    assert(Kitchen.duty(p,s,2000,true) and s.message:find("power went off",1,true))
    assert(s.rejected["stove:1:0:0"],"A stove without power is not tried again for a while")
    run()
    assert(not oven.on and p.inventory:contains(raw),"Switched off and the dish taken out")
    passed("a power cut ends the dish safely")
end
do
    squares={}
    local p=survivor(0,0); local s=state()
    local oven=stove(5,0)
    local raw=T.add(p.inventory,food())
    Kitchen.meal(p,s,1000); run(); Kitchen.settle(p,s,1100)
    raw.cooked=true
    walks=0
    assert(not Kitchen.duty(p,s,2000,false),"No walking while zombies are about")
    assert(s.kitchenNotice:find("once it is safe",1,true) and walks==0 and oven.on)
    assert(Kitchen.duty(p,s,3000,true),"Then it goes")
    run()
    assert(not oven.on)
    passed("in danger it waits to walk, and says so")
end

-- Stop, other people's stoves, guards ---------------------------------------------
do
    squares={}
    local p=survivor(0,0); local s=state()
    local oven=stove(1,0)
    local raw=T.add(p.inventory,food())
    Kitchen.meal(p,s,1000); run(); Kitchen.settle(p,s,1100)
    assert(Kitchen.ended(p)=="Turning the stove off.")
    run()
    assert(not oven.on and p.inventory:contains(raw),"Stop beside the stove turns it off")
    squares={}
    p=survivor(0,0); s=state(); oven=stove(6,0); raw=T.add(p.inventory,food())
    Kitchen.meal(p,s,1000); run(); Kitchen.settle(p,s,1100)
    local message=Kitchen.ended(p)
    assert(message:find("still on with Chicken inside",1,true) and oven.on and #queued==0,"Stop far away only warns: "..message)
    passed("Stop turns the stove off when beside it and warns otherwise")
end
do
    squares={}
    local p=survivor(0,0); local s=state()
    local busy=stove(1,0); T.add(busy.container,food({name="Their soup"}))
    local lit=stove(-1,0); lit.on=true
    T.add(p.inventory,food())
    assert(not Kitchen.meal(p,s,1000) and s.kitchenNotice:find("no powered stove",1,true),"Other people's cooking is left alone")
    passed("a stove in use is never borrowed")
end
do
    squares={}
    local p=survivor(0,0)
    local oven=stove(1,0)
    local toggle
    ISTimedActionQueue.add=function(action) toggle=action end
    local s=state(); T.add(p.inventory,food())
    Kitchen.meal(p,s,1000)
    oven.on=true
    assert(toggle.Type=="toggle" and not toggle:isValid(),"Someone else lit it first: the toggle does not switch it off")
    ISTimedActionQueue.add=function(action) queued[#queued+1]=action; return action end
    passed("a toggle only ever moves the stove the intended way")
end
do
    squares={}
    local p=survivor(0,0); local s=state()
    stove(1,0)
    local raw=T.add(p.inventory,food())
    Kitchen.meal(p,s,1000)
    queued={} -- the walk failed; nothing reached the stove
    Kitchen.settle(p,s,1100)
    assert(Kitchen.ledger(p)==nil and s.rejected[raw:getID()],"Nothing to clean up, and the dish waits before another try")
    passed("a batch that never reached the stove leaves nothing behind")
end

do
    -- Three failed attempts: it alerts, refuses to sleep, and tries again later.
    squares={}
    local p=survivor(0,0); local s=state()
    local oven=stove(1,0)
    local raw=T.add(p.inventory,food())
    Kitchen.meal(p,s,1000); run(); Kitchen.settle(p,s,1100)
    raw.cooked=true
    assert(Kitchen.duty(p,s,1500,true)); queued={}; Kitchen.settle(p,s,1501,true); s.pending=nil
    assert(Kitchen.ledger(p).tries==0,"Cut short by danger or the player is not a failed try")
    for attempt=1,3 do assert(Kitchen.duty(p,s,2000+attempt,true)); queued={}; Kitchen.settle(p,s,2000+attempt,false); s.pending=nil end
    assert(not Kitchen.duty(p,s,3000,true) and Kitchen.lit(p),"Out of attempts, the stove is still lit")
    assert(s.kitchenNotice:find("could not reach",1,true))
    assert(Kitchen.duty(p,s,3000+Kitchen.policy.againMs,true) or Kitchen.duty(p,s,3001+Kitchen.policy.againMs,true),"And later it tries again")
    run()
    assert(not oven.on)
    passed("an unreachable lit stove is never forgotten")
end
do
    -- Nobody watching: a card, not an action.
    squares={}
    local p=survivor(0,0); local s=state()
    local oven=stove(1,0)
    local raw=T.add(p.inventory,food())
    Kitchen.meal(p,s,1000); run(); Kitchen.settle(p,s,1100)
    local cards=#p.cards
    Kitchen.duty(p,s,2000,true)
    Kitchen.watchdog(p,5000)
    assert(#p.cards==cards,"Watched a moment ago")
    Kitchen.watchdog(p,2000+Kitchen.policy.unwatchedMs)
    assert(#p.cards==cards+1 and p.cards[#p.cards].detail:find("nothing is watching",1,true),"Unwatched: a card")
    assert(#queued==0 and oven.on,"It never acts unasked")
    raw.time=50
    Kitchen.watchdog(p,2000+Kitchen.policy.unwatchedMs+Kitchen.policy.warnMs)
    assert(p.cards[#p.cards].detail:find("about to burn",1,true))
    passed("an unwatched lit stove raises a card")
end
do
    squares={}
    local p=survivor(0,0)
    local oven=stove(1,0)
    local actions={}
    ISTimedActionQueue.add=function(action) actions[#actions+1]=action; return action end
    local s=state(); local raw=T.add(p.inventory,food())
    Kitchen.meal(p,s,1000)
    local into,light=actions[#actions-1],actions[#actions]
    T.add(oven.container,food({name="Their soup"}))
    assert(not into:isValid(),"Someone started cooking there meanwhile: our dish stays out")
    assert(not light:isValid(),"And the stove is not lit for food that is not ours")
    ISTimedActionQueue.add=function(action) queued[#queued+1]=action; return action end
    passed("the stove is checked again when the actions run")
end

do
    -- From the fridge: fetched first, then the walk to the stove is decided from there.
    squares={}
    local p=survivor(0,0); local s=state()
    local oven=stove(1,0)
    local fridge=T.container(4,0); fridge.square=square(4,0)
    fridge.square.objects={{getContainerCount=function() return 1 end,getContainerByIndex=function() return fridge end}}
    local raw=T.add(fridge,food())
    assert(Kitchen.meal(p,s,1000) and Kitchen.ledger(p).stage=="fetching")
    local kinds={}; for _,a in ipairs(queued) do kinds[#kinds+1]=a.Type end
    assert(table.concat(kinds,",")=="transfer","Only the fetch in the first batch: "..table.concat(kinds,","))
    run(); Kitchen.settle(p,s,1100,false); s.pending=nil
    assert(Kitchen.ledger(p).stage=="ready" and p.inventory:contains(raw))
    walks=0
    assert(Kitchen.meal(p,s,1200),"Then to the stove")
    run(); Kitchen.settle(p,s,1300,false)
    assert(oven.on and oven.container:contains(raw) and Kitchen.ledger(p).lit,"In and lit")
    passed("food from a fridge is fetched, then cooked")
end
do
    -- Someone else lit the stove while the survivor walked over.
    squares={}
    local p=survivor(0,0); local s=state()
    local oven=stove(1,0)
    T.add(p.inventory,food())
    Kitchen.meal(p,s,1000)
    oven.on=true
    for _,a in ipairs(queued) do if a:isValid() then a:perform() end end; queued={}
    Kitchen.settle(p,s,1100,false)
    assert(Kitchen.ledger(p)==nil and oven.on,"Theirs: left on, nothing claimed")
    assert(Kitchen.ended(p)==nil,"Stop does not touch it either")
    passed("a stove someone else lit is never turned off")
end
do
    squares={}
    local p=survivor(0,0); local s=state()
    local oven=stove(1,0)
    T.add(p.inventory,food())
    Kitchen.meal(p,s,1000); run(); Kitchen.settle(p,s,1100)
    squares={}
    assert(not Kitchen.lit(p),"A stove out of sight is not known to be on, so sleep is not blocked forever")
    passed("an unloaded stove does not block sleep")
end
