-- The kitchen: raw food is cooked on a powered stove, taken out once cooked
-- (or before it burns), and the stove is always turned off again.
AutoMindfulContractHarnessOnly=true
if loadTest then loadTest("contracts.lua") else assert(loadfile("tests/contracts.lua"))() end
AutoMindfulContractHarnessOnly=nil
local T=AutoMindfulTest
local Kitchen=require "AutoMindful/Kitchen"
local Fetch=require "AutoMindful/Fetch"
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
    function item:getMinutesToCook() return self.minutes or 30 end
    function item:getMinutesToBurn() return 60 end
    function item:getCookingTime() return self.time or 0 end
    function item:isFavorite() return self.favorite or false end
    function item:getActualWeight() return self.weight or 0.3 end
    function item:getOffAge() return self.offAge or 2 end
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
local parts={available=function() return false end, stat=function(p,k) return p.values[k] or 0 end,
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
Options.makeSoup=function() return false end
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
    assert(s.kitchenSkip["stove:1:0:0"],"A stove without power is not tried again for a while")
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
    assert(Kitchen.ledger(p)==nil and s.kitchenSkip[raw:getID()],"Nothing to clean up, and the dish waits before another try")
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
    assert(Kitchen.ledger(p) and p.inventory:contains(raw),"Fetched; the next step takes it to the stove")
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
do
    -- A batch: what cooks in about the same time goes in together; each comes
    -- out when done; the stove goes off with the last; leftovers go cold.
    squares={}
    local p=survivor(0,0); local s=state()
    local oven=stove(1,0)
    local fridge=T.container(-1,0); fridge.square=square(-1,0)
    function fridge:getType() return "fridge" end
    function fridge:isPowered() return true end
    fridge.square.objects={{getContainerCount=function() return 1 end,getContainerByIndex=function() return fridge end}}
    local a=T.add(fridge,food({name="Chicken"}))
    local b=T.add(fridge,food({name="Steak",minutes=40}))
    local slow=T.add(fridge,food({name="Roast",minutes=120}))
    local mine=T.add(p.inventory,food({name="Jerky",cookable=false}))
    assert(Kitchen.meal(p,s,1000) and Kitchen.ledger(p).stage=="fetching"); run(); Kitchen.settle(p,s,1050,false); s.pending=nil
    assert(Kitchen.meal(p,s,1060)); run(); Kitchen.settle(p,s,1100,false); s.pending=nil
    assert(oven.container:contains(a) and oven.container:contains(b) and not oven.container:contains(slow),"Two dishes in, the slow roast waits")
    assert(oven.on and Kitchen.ledger(p).name=="Chicken and 1 more")
    a.time,a.cooked=31,true
    assert(Kitchen.duty(p,s,2000,true) and s.message:find("Chicken out",1,true),s.message)
    run(); Kitchen.settle(p,s,2100,false); s.pending=nil
    assert(oven.on and p.inventory:contains(a) and oven.container:contains(b),"The chicken is out, the steak cooks on")
    assert(Kitchen.duty(p,s,2200,true) and s.phase=="kitchen-watch" and s.message:find("Steak",1,true),s.message)
    b.time,b.cooked=41,true
    assert(Kitchen.duty(p,s,3000,true)); run(); Kitchen.settle(p,s,3100,false); s.pending=nil
    assert(not oven.on and p.inventory:contains(b),"The last one out, the stove off")
    assert(not Kitchen.duty(p,s,3200,true) and Kitchen.ledger(p)==nil)
    p.values.HUNGER=0
    function p:getStats() return {get=function(_,k) return k=="HUNGER" and 0 or 0 end} end
    function p:getMoodles() return {getMoodleLevel=function() return 0 end} end
    assert(Kitchen.store(p,s,4000),"Not hungry: the leftovers go in the fridge")
    run()
    assert(fridge:contains(a) and fridge:contains(b) and fridge:contains(slow) and p.inventory:contains(mine),"Cooked food back in the fridge; the roast never left it; carried food stays carried")
    passed("several dishes cook together, come out one by one, and the rest is kept cold")
end
do
    -- Power blinks during the take-out: the stove is off with a raw dish inside.
    squares={}
    local p=survivor(0,0); local s=state()
    local oven=stove(1,0)
    local raw=T.add(p.inventory,food())
    Kitchen.meal(p,s,1000); run(); Kitchen.settle(p,s,1100,false); s.pending=nil
    oven.container.off=true
    assert(Kitchen.duty(p,s,2000,true)); queued={}
    oven.on=false; oven.container.off=nil
    Kitchen.settle(p,s,2100,true); s.pending=nil
    assert(Kitchen.urgent(p) and Kitchen.duty(p,s,2200,true) and s.phase=="kitchen","An off stove with food inside is emptied, not watched: "..tostring(s.phase))
    run()
    assert(p.inventory:contains(raw))
    passed("a dish left in a cold stove is taken out")
end
do
    -- Cut short over and over: it stops pretending and turns the heat off.
    squares={}
    local p=survivor(0,0); local s=state()
    local oven=stove(1,0)
    local raw=T.add(p.inventory,food())
    Kitchen.meal(p,s,1000); run(); Kitchen.settle(p,s,1100,false); s.pending=nil
    raw.cooked=true
    for attempt=1,6 do Kitchen.duty(p,s,2000+attempt,true); queued={}; Kitchen.settle(p,s,2000+attempt,true); s.pending=nil end
    assert(not Kitchen.duty(p,s,3000,true) and s.kitchenNotice:find("could not reach",1,true))
    local kinds={}; for _,a in ipairs(queued) do kinds[#kinds+1]=a.Type end
    assert(table.concat(kinds,",")=="toggle","Beside the stove, the heat goes off: "..table.concat(kinds,","))
    run()
    assert(not oven.on)
    passed("endless interruptions still end with the stove off")
end

do
    -- Bread becomes toast, a new item: never put in, so nothing burns unseen.
    local toast=food({name="Bread slices"})
    function toast:getReplaceOnCooked() return {size=function() return 1 end} end
    assert(not Kitchen.cookable(toast))
    passed("food that turns into another item is not cooked")
end
do
    -- From the yard, the kitchen through the back door still counts.
    squares={}
    local p=survivor(0,0); local s=state()
    function p:getSquare() local here=squares["0:0"]; here.getBuilding=function() return nil end; return here end
    local oven=stove(2,0)
    T.add(p.inventory,food())
    assert(Kitchen.meal(p,s,1000),"An indoor stove is found from just outside")
    passed("a survivor outdoors still finds the kitchen")
end
do
    -- Wild food keeps its own eating effect: left raw, as before.
    assert(not Kitchen.cookable(food({onEat="RecipeCodeOnEat.consumeWildFoodGeneric"})))
    passed("food with any eating effect is not cooked")
end
do
    -- Practice: nobody hungry, raw food in the fridge that would spoil is cooked
    -- for XP and put back cold; long-keeping and carried food is left alone.
    squares={}
    local p=survivor(0,0); local s=state()
    p.values.HUNGER=0
    function p:getStats() return {get=function() return 0 end} end
    function p:getMoodles() return {getMoodleLevel=function() return 0 end} end
    local oven=stove(1,0)
    local fridge=T.container(-1,0); fridge.square=square(-1,0)
    function fridge:getType() return "fridge" end
    function fridge:isPowered() return true end
    fridge.square.objects={{getContainerCount=function() return 1 end,getContainerByIndex=function() return fridge end}}
    local soon=T.add(fridge,food({name="Chicken",rotsAt=2}))
    local keeps=T.add(fridge,food({name="Jerky",offAge=30,rotsAt=40}))
    local mine=T.add(p.inventory,food({name="Steak"}))
    local mode="off"
    Options.cookTraining=function() return mode end
    assert(not Kitchen.practice(p,s,1000),"Off: nothing is cooked for practice")
    mode="spoiling"; s.practiceNext=nil
    assert(Kitchen.practice(p,s,2000) and Kitchen.ledger(p).reason=="practice","Spoiling food is cooked for practice")
    assert(#Kitchen.ledger(p).items==1 and Kitchen.ledger(p).item==soon:getID(),"Only what would spoil, not the jerky or the carried steak")
    run(); Kitchen.settle(p,s,2100,false); s.pending=nil
    assert(Kitchen.meal(p,s,2200)); run(); Kitchen.settle(p,s,2300,false); s.pending=nil
    soon.time,soon.cooked=31,true
    assert(Kitchen.duty(p,s,3000,true)); run(); Kitchen.settle(p,s,3100,false); s.pending=nil
    assert(not Kitchen.duty(p,s,3200,true))
    assert(Kitchen.store(p,s,4000)); run()
    assert(fridge:contains(soon) and soon.cooked and p.inventory:contains(mine),"Cooked and back in the fridge; the steak stays carried")
    -- Tired, or no fridge to put it back in: no practice.
    s.practiceNext=nil; local more=T.add(fridge,food({name="Chicken",rotsAt=2}))
    p.values.FATIGUE=.7
    assert(not Kitchen.practice(p,s,5000),"A tired survivor is not kept up by practice")
    p.values.FATIGUE=0; s.practiceNext=nil
    function fridge:isPowered() return false end
    assert(not Kitchen.practice(p,s,6000),"Nowhere cold to put it back: no practice")
    passed("cooking practice uses spoiling food from the cupboards and puts it back cold")
end
do
    local p=T.playerNew()
    local perk={getXpForLevel=function(_,level) return level*100 end,getTotalXpForLevel=function(_,level) return level*(level+1)*50 end}
    function p:getPerkLevel() return 2 end
    function p:getXp() return {getXP=function() return 400 end} end
    local Progress=require "AutoMindful/Progress"
    local value=Progress.perk(p,perk)
    assert(value.level==2 and value.current==100 and value.required==300,"Level 2: 100 of 300 XP into level 3")
    assert(Progress.perk(p,nil)==nil)
    passed("any perk's progress is read the same way")
end
do
    -- Cooking 10: nothing left to learn, so no practice.
    squares={}
    local p=survivor(0,0); local s=state()
    p.values.HUNGER=0
    function p:getStats() return {get=function() return 0 end} end
    function p:getMoodles() return {getMoodleLevel=function() return 0 end} end
    stove(1,0)
    local fridge=T.container(-1,0); fridge.square=square(-1,0)
    function fridge:getType() return "fridge" end
    function fridge:isPowered() return true end
    fridge.square.objects={{getContainerCount=function() return 1 end,getContainerByIndex=function() return fridge end}}
    T.add(fridge,food({rotsAt=2}))
    Options.cookTraining=function() return "all" end
    Perks.Cooking={getXpForLevel=function() return 0 end,getTotalXpForLevel=function() return 0 end}
    function p:getPerkLevel() return 10 end
    function p:getXp() return {getXP=function() return 0 end} end
    assert(not Kitchen.practice(p,s,1000),"Level 10 stops practice")
    function p:getPerkLevel() return 3 end
    s.practiceNext=nil
    assert(Kitchen.practice(p,s,2000),"Below 10 it practises")
    Perks.Cooking=nil
    passed("cooking practice stops at level 10")
end
-- The game's evolved recipes, as the game would list them.
local Dish=require "AutoMindful/Dish"
local recipes={}
local function evolved(def)
    local r={def=def}
    function r:getUntranslatedName() return def.name end
    function r:getBaseItem() return def.base end
    function r:getFullResultItem() return def.result end
    function r:isCookable() return def.cookable end
    function r:getMinimumWater() return def.water or 0 end
    function r:getMaxItems() return def.max or 6 end
    function r:isHidden() return false end
    function r:isAllowFrozenItem() return false end
    function r:getPossibleItems()
        local l={}
        for kind in pairs(def.takes) do l[#l+1]={getFullType=function() return kind end} end
        return T.list(l)
    end
    function r:getItemRecipe(item) return def.takes[item:getFullType()] and {getUse=function() return 15 end} or nil end
    -- The game's own check, simplified: what it takes, in the inventory.
    function r:getItemsCanBeUse(player,base)
        local l={}
        for _,item in ipairs(player:getInventory().items) do if item~=base and def.takes[item:getFullType()] then l[#l+1]=item end end
        return T.list(l)
    end
    recipes[#recipes+1]=r
    return r
end
function getEvolvedRecipes() return T.list(recipes) end
RecipeManager={getEvolvedRecipe=function(base)
    local l={}
    for _,r in ipairs(recipes) do if r.def.base==base:getFullType() or r.def.result==base:getFullType() then l[#l+1]=r end end
    return T.list(l)
end}
ArrayList={new=function() local l={items={}}; function l:add(x) self.items[#self.items+1]=x end; return l end}
local soupTakes={["Base.Potato"]=true,["Base.Carrots"]=true,["Base.Salt"]=true,["Base.Pepper"]=true}
evolved({name="Soup",base="Base.Pot",result="Base.PotOfSoupRecipe",cookable=true,water=.9,takes=soupTakes})
evolved({name="Salad",base="Base.Bowl",result="Base.Salad",cookable=false,takes={["Base.Lettuce"]=true,["Base.Tomato"]=true,["Base.Wine"]=true}})
evolved({name="HotDrink",base="Base.Mugl",result="Base.HotDrink",cookable=true,water=1,takes={["Base.Coffee2"]=true}})
-- Adding: the first ingredient turns the base into the dish.
local made
local function adding(p,turns)
    made=nil
    ISAddItemInRecipe={new=function(_,player,r,base,item) return {Type="add",isValid=function() return true end,perform=function()
        if item.name=="Potato" and not item.halved then item.halved=true; item.hunger=(item.hunger or -.5)/2
        else T.remove(p.inventory,item) end
        if turns[base:getFullType()] then
            T.remove(p.inventory,base)
            made=T.add(p.inventory,food({name=turns[base:getFullType()].name,fullType=turns[base:getFullType()].type,minutes=50,hunger=-.2,
                cookable=r.def.cookable}))
            function made:getMinutesToBurn() return 100 end
            turns[base:getFullType()]=nil
        end
    end} end}
end
local function cupboard(x,y,kind)
    local c=T.container(x,y); c.square=square(x,y)
    function c:getType() return kind or "counter" end
    function c:isPowered() return true end
    c.square.objects={{getContainerCount=function() return 1 end,getContainerByIndex=function() return c end}}
    return c
end
do
    -- Soup: an empty pot, the sink, two ingredients from the fridge. The pot
    -- becomes a new item when the first goes in, then it cooks like any dish.
    squares={}; Dish.reset()
    local p=survivor(0,0); local s=state()
    local oven=stove(1,0)
    local fridge=cupboard(-1,0,"fridge")
    local sink={water=10000,sq=square(0,2)}
    function sink:hasWater() return true end
    function sink:isTaintedWater() return false end
    function sink:getFluidAmount() return self.water end
    function sink:getSquare() return self.sq end
    sink.sq.objects={sink}
    Fluid={Water="Water"}
    local fluid={amount=0}
    function fluid:getAmount() return self.amount end
    function fluid:isEmpty() return self.amount<=0 end
    function fluid:isPureFluid() return true end
    local pot=T.add(p.inventory,T.item("InventoryItem",{fullType="Base.Pot",fluid=fluid}))
    function pot:getActualWeight() return 1 end
    local potato=T.add(fridge,food({name="Potato",fullType="Base.Potato"}))
    local carrot=T.add(fridge,food({name="Carrots",fullType="Base.Carrots"}))
    local salt=T.add(fridge,food({name="Salt",fullType="Base.Salt",cookable=false,hunger=0}))
    local pepper=T.add(fridge,food({name="Pepper",fullType="Base.Pepper",cookable=false,hunger=0}))
    for _,spice in ipairs({salt,pepper}) do function spice:isSpice() return true end end
    for _,item in ipairs({potato,carrot}) do function item:isSpice() return false end end
    ISTakeWaterAction={new=function(_,player,item) return {Type="fill",isValid=function() return true end,perform=function() item.fluid.amount=1.5 end} end}
    adding(p,{["Base.Pot"]={name="Pot of Soup",type="Base.PotOfSoupRecipe"}})
    Options.makeSoup=function() return true end
    local function batch() run(); Kitchen.settle(p,s,T.now or 0,false); s.pending=nil end
    assert(Kitchen.meal(p,s,1000) and Kitchen.ledger(p).stage:find("^dish"),"A soup starts instead of cooking one by one")
    assert(Kitchen.ledger(p).recipe=="Soup")
    assert(s.rejected[potato:getID()] and s.rejected[carrot:getID()],"The ingredients are kept out of ordinary eating")
    assert(s.rejected[pot:getID()],"The pot is kept for the soup too")
    local held=0
    for _,spice in ipairs({salt,pepper}) do if s.rejected[spice:getID()] then held=held+1 end end
    assert(held==1,"One spice for the soup, not both: "..held)
    batch() -- fetched from the fridge
    assert(p.inventory:contains(potato) and p.inventory:contains(carrot))
    for _=1,8 do
        local entry=Kitchen.ledger(p)
        if not entry or entry.stage=="cooking" then break end
        assert(Kitchen.duty(p,s,2000,true),"Each dish step queues something: "..tostring(entry.stage))
        batch()
    end
    local entry=Kitchen.ledger(p)
    local soupItem=made
    assert(entry and entry.stage=="cooking" and oven.on and oven.container:contains(soupItem),"The soup is on the stove: "..tostring(entry and entry.stage))
    Kitchen.duty(p,s,2500,true)
    assert(s.rejected[soupItem:getID()],"Not eaten out of the stove while it cooks")
    assert(fluid.amount>=.9,"Filled at the sink")
    assert(not p.inventory:contains(potato) and not p.inventory:contains(carrot),"Both went in")
    soupItem.cooked,soupItem.time=true,51
    assert(Kitchen.duty(p,s,3000,true)); batch()
    assert(not oven.on and p.inventory:contains(soupItem),"Cooked, out, stove off")
    Kitchen.duty(p,s,3100,true)
    assert(not Kitchen.ledger(p),"Done")
    assert(not s.rejected[soupItem:getID()],"Once cooked and out, the soup may be eaten")
    Options.makeSoup=function() return false end
    passed("a soup is made from a pot, the sink and the fridge with one spice, then cooked, even when an ingredient goes in by parts")
end
do
    -- A salad needs no stove: a bowl from the cupboard, greens from the fridge.
    -- Wine is never put in, and hot drinks are not dishes.
    squares={}; Dish.reset()
    local p=survivor(0,0); local s=state()
    local shelf=cupboard(-1,0)
    local fridge=cupboard(1,0,"fridge")
    local bowl=T.add(shelf,T.item("InventoryItem",{fullType="Base.Bowl"}))
    function bowl:getActualWeight() return .2 end
    local lettuce=T.add(fridge,food({name="Lettuce",fullType="Base.Lettuce",cookable=false}))
    local tomato=T.add(fridge,food({name="Tomato",fullType="Base.Tomato",cookable=false}))
    local wine=T.add(fridge,food({name="Wine",fullType="Base.Wine",cookable=false,alcohol=true}))
    for _,item in ipairs({lettuce,tomato,wine}) do function item:isSpice() return false end end
    assert(not Dish.catalog().byBase["Base.Mugl"],"Hot drinks are not made")
    adding(p,{["Base.Bowl"]={name="Salad",type="Base.Salad"}})
    Options.makeSoup=function() return true end
    local function batch() run(); Kitchen.settle(p,s,T.now or 0,false); s.pending=nil end
    assert(Kitchen.meal(p,s,1000),"A salad, with no stove anywhere")
    assert(Kitchen.ledger(p).recipe=="Salad" and not Kitchen.ledger(p).cookable)
    assert(not s.rejected[wine:getID()],"Never wine")
    for _=1,8 do
        if not Kitchen.ledger(p) then break end
        batch()
        if Kitchen.ledger(p) then Kitchen.duty(p,s,2000,true) end
    end
    assert(not Kitchen.ledger(p) and made and p.inventory:contains(made),"Made and ready to eat")
    assert(fridge:contains(wine) and not p.inventory:contains(lettuce) and not p.inventory:contains(tomato),"The greens went in")
    assert(not s.rejected[made:getID()],"Free to be eaten")
    -- Practice: what spoils soon becomes a salad, which goes on the list for the fridge.
    squares={}; Dish.reset()
    p=survivor(0,0); s=state(); p.values.HUNGER=0
    function p:getStats() return {get=function() return 0 end} end
    function p:getMoodles() return {getMoodleLevel=function() return 0 end} end
    Options.cookTraining=function() return "spoiling" end
    shelf=cupboard(-1,0); fridge=cupboard(1,0,"fridge")
    bowl=T.add(shelf,T.item("InventoryItem",{fullType="Base.Bowl"}))
    function bowl:getActualWeight() return .2 end
    lettuce=T.add(fridge,food({name="Lettuce",fullType="Base.Lettuce",cookable=false,rotsAt=1}))
    tomato=T.add(fridge,food({name="Tomato",fullType="Base.Tomato",cookable=false,rotsAt=2}))
    local fresh=T.add(fridge,food({name="Tomato",fullType="Base.Tomato",cookable=false}))
    for _,item in ipairs({lettuce,tomato,fresh}) do function item:isSpice() return false end end
    adding(p,{["Base.Bowl"]={name="Salad",type="Base.Salad"}})
    assert(Kitchen.practice(p,s,1000),"Practice makes a dish of what spoils")
    assert(not s.rejected[fresh:getID()],"Food that keeps is left for later")
    for _=1,8 do
        if not Kitchen.ledger(p) then break end
        batch()
        if Kitchen.ledger(p) then Kitchen.duty(p,s,2000,true) end
    end
    local list=p:getModData().AutoMindfulLeftovers or {}
    assert(made and list[#list]==made:getID(),"The practice salad is put away cold")
    Options.makeSoup=function() return false end
    Options.cookTraining=function() return "off" end
    passed("a salad is made without a stove and never with wine, and practice dishes go to the fridge")
end
do
    -- The game's rules, and ours: rotten only from Cooking 7 and when allowed,
    -- never poison, burnt or sealed food, dangerous raw food only into a cooked dish.
    Dish.reset()
    local soup,salad=Dish.catalog().byBase["Base.Pot"][1],Dish.catalog().byBase["Base.Bowl"][1]
    local base=T.item("InventoryItem",{fullType="Base.Pot"})
    local bad=food({name="Potato",fullType="Base.Potato",rotten=true})
    Options.rottenRecipes=function() return true end
    assert(not Dish.usable(soup,bad,6,base),"Not below Cooking 7")
    assert(Dish.usable(soup,bad,7,base),"From Cooking 7, as the game allows")
    Options.rottenRecipes=function() return false end
    assert(not Dish.usable(soup,bad,10,base),"Never when turned off")
    assert(not Dish.usable(soup,food({fullType="Base.Potato",poison=true}),10,base),"Never poison")
    assert(not Dish.usable(soup,food({fullType="Base.Potato",burnt=true}),10,base),"Never burnt")
    local sealed=food({fullType="Base.Potato"}); function sealed:getOpeningRecipe() return "OpenCannedFood" end
    assert(not Dish.usable(soup,sealed,10,base),"Sealed food is opened first")
    local raw=food({fullType="Base.Lettuce",cookable=false,rawDanger=true})
    assert(not Dish.usable(salad,raw,10,base),"Dangerous raw food never into a salad")
    assert(Dish.usable(soup,food({fullType="Base.Potato",rawDanger=true}),0,base),"But into a soup that is cooked")
    assert(not Dish.usable(soup,food({fullType="Base.Lettuce"}),10,base),"Only what the recipe takes")
    passed("ingredients follow the game's rules for Cooking level, and never poison, burnt, sealed or raw-dangerous food uncooked")
end
do
    -- Only dishes that feed: chum is bait. A bowl of water takes no salad; a full
    -- burger takes nothing more; a frying pan in hand stays a weapon. A sandwich
    -- is made cold, an omelette is cooked, bacon goes in a sandwich only cooked.
    local saved=getScriptManager
    function getScriptManager() return {FindItem=function(_,kind) return {getHungerChange=function() return kind=="Base.Chum" and 0 or -20 end} end} end
    evolved({name="AddBaitToChum",base="Base.Chum",result="Base.Chum",cookable=false,takes={["Base.Bread"]=true}})
    local sandwich=evolved({name="Sandwich",base="Base.BreadSlices",result="Base.Sandwich",cookable=true,takes={["Base.Cheese"]=true,["Base.Bacon"]=true}})
    -- As the game answers: false when it must be cooked first and is not.
    function sandwich:needToBeCooked(item) return item:getFullType()~="Base.Bacon" or item:isCooked() end
    evolved({name="Omelette",base="Base.OmeletteRecipe",result="Base.OmeletteRecipe",cookable=false,takes={["Base.Cheese"]=true}})
    evolved({name="Stir",base="Base.Pan",result="Base.PanFriedVegetables",cookable=true,takes={["Base.Carrots"]=true}})
    Dish.reset()
    local catalog=Dish.catalog()
    assert(not catalog.byBase["Base.Chum"],"Chum is not a dish")
    assert(not catalog.byBase["Base.BreadSlices"][1].cookable,"A sandwich is made cold")
    local fluid={amount=.5}
    function fluid:getAmount() return self.amount end
    function fluid:isEmpty() return self.amount<=0 end
    function fluid:isPureFluid() return true end
    Fluid={Water="Water"}
    local wetBowl=T.item("InventoryItem",{fullType="Base.Bowl",fluid=fluid})
    assert(not Dish.recipesFor(wetBowl),"A bowl of water takes no salad")
    local wetPot=T.item("InventoryItem",{fullType="Base.Pot",fluid=fluid})
    assert(Dish.recipesFor(wetPot),"But a pot of water takes a soup")
    local burger=food({fullType="Base.BreadSlices",cookable=false})
    function burger:haveExtraItems() return true end
    function burger:getExtraItems() return T.list({1,2,3,4,5,6}) end
    assert(not Dish.recipesFor(burger),"A full one takes nothing more")
    local pan=T.item("InventoryItem",{fullType="Base.Pan"})
    function pan:isEquipped() return true end
    assert(not Dish.recipesFor(pan),"The frying pan in hand stays a weapon")
    local def=catalog.byBase["Base.BreadSlices"][1]
    local slices=food({fullType="Base.BreadSlices",cookable=false})
    assert(not Dish.usable(def,food({fullType="Base.Bacon",cookable=true}),10,slices),"Bacon goes in a sandwich cooked")
    assert(Dish.usable(def,food({fullType="Base.Bacon",cookable=true,cooked=true}),10,slices))
    -- An omelette is raw egg: planned only with a stove, and then cooked.
    squares={}
    local p=survivor(0,0)
    local egg=T.add(p.inventory,food({name="Omelette",fullType="Base.OmeletteRecipe",rawDanger=true}))
    local cheese=T.add(p.inventory,food({name="Cheese",fullType="Base.Cheese",cookable=false}))
    for _,item in ipairs({egg,cheese}) do function item:isSpice() return false end end
    local found={bases={{item=egg,carried=true}},ingredients={{item=cheese,carried=true}},taps={}}
    assert(not Dish.plan(p,found,"meal",function() return nil end,{},1000),"No omelette without a stove")
    local plan=Dish.plan(p,found,"meal",function() return {object={}} end,{},1000)
    assert(plan and plan.def.name=="Omelette" and plan.cook,"With a stove it is cooked")
    getScriptManager=saved
    Dish.reset()
    passed("only feeding dishes; a wet bowl, a full base and a pan in hand are left alone; sandwiches cold, omelettes and bacon cooked")
end
do
    -- Mildly hungry: cook rather than eat raw, but leftovers come first.
    squares={}
    local p=survivor(0,0); local s=state()
    p.values.HUNGER=.2
    function p:getMoodles() return {getMoodleLevel=function(_,kind) return kind==MoodleType.HUNGRY and 1 or 0 end} end
    stove(1,0)
    local raw=T.add(p.inventory,food({name="Potato"}))
    assert(Kitchen.prefer(p,s,1000) and Kitchen.ledger(p),"Cooks the potato instead of eating it raw")
    queued={}; Kitchen.settle(p,s,1100,true); s.pending=nil
    squares={}; p=survivor(0,0); s=state(); p.values.HUNGER=.2
    function p:getMoodles() return {getMoodleLevel=function(_,kind) return kind==MoodleType.HUNGRY and 1 or 0 end} end
    stove(1,0); T.add(p.inventory,food({name="Potato"}))
    T.add(p.inventory,food({name="Leftover stew",cooked=true}))
    assert(not Kitchen.prefer(p,s,1000) and not Kitchen.ledger(p),"Leftovers are eaten first")
    function p:getMoodles() return {getMoodleLevel=function(_,kind) return kind==MoodleType.HUNGRY and 2 or 0 end} end
    passed("cooking comes before eating raw, after leftovers")
end
do
    -- No power: the propane grill in the yard cooks instead, and is turned off.
    squares={}
    local p=survivor(0,0); local s=state()
    local sq=square(2,0)
    local c=T.container(2,0); c.square=sq
    function c:getType() return "barbecuepropane" end
    local grill={kind="IsoBarbecue",container=c,lit=false,fuel=true,sq=sq}
    function grill:isPropaneBBQ() return true end
    function grill:isLit() return self.lit end
    function grill:hasFuel() return self.fuel end
    function grill:getContainer() return self.container end
    function grill:getSquare() return self.sq end
    sq.objects={grill}
    ISBBQToggle={new=function(_,player,bbq) return {Type="grill",isValid=function() return bbq:isPropaneBBQ() and bbq:hasFuel() end,
        perform=function() bbq.lit=not bbq.lit end} end}
    local raw=T.add(p.inventory,food())
    assert(Kitchen.meal(p,s,1000) and Kitchen.ledger(p).x==2,"The grill is used when there is no stove")
    run(); Kitchen.settle(p,s,1100,false); s.pending=nil
    assert(grill.lit and c:contains(raw),"Lit with the dish on it")
    assert(Kitchen.duty(p,s,1200,true) and s.message:find("near the grill",1,true),s.message)
    grill.fuel=false
    assert(Kitchen.duty(p,s,1300,true) and s.message:find("propane ran out",1,true),s.message)
    for _,action in ipairs(queued) do assert(action.Type~="grill","Out of propane it cannot be switched, and need not be") end
    run()
    assert(p.inventory:contains(raw),"The dish is taken back")
    passed("a propane grill cooks when there is no stove, and runs out safely")
end
do
    -- From indoors: a grill in the yard counts, the yard's crate does not, and
    -- a stove indoors comes first.
    squares={}
    local p=survivor(0,0); local s=state()
    local yard=square(3,0); yard.getBuilding=function() return nil end
    local c=T.container(3,0); c.square=yard
    function c:getType() return "barbecuepropane" end
    local grill={kind="IsoBarbecue",container=c,lit=false}
    function grill:isPropaneBBQ() return true end
    function grill:isLit() return self.lit end
    function grill:hasFuel() return true end
    function grill:getContainer() return self.container end
    function grill:getSquare() return yard end
    local crate=T.container(3,1); local crateSquare=square(3,1); crateSquare.getBuilding=function() return nil end; crate.square=crateSquare
    T.add(crate,food({name="Yard food"}))
    crateSquare.objects={{getContainerCount=function() return 1 end,getContainerByIndex=function() return crate end}}
    yard.objects={grill}
    local found=Kitchen.scan(p,{},1000)
    assert(#found.stoves==1 and found.stoves[1].object==grill,"The yard grill is seen from indoors")
    for _,entry in ipairs(found.food) do assert(entry.container~=crate,"The yard crate is not a pantry") end
    local oven=stove(2,0)
    found=Kitchen.scan(p,{},1000)
    assert(found.stoves[1].object==oven,"A stove indoors comes before the grill")
    passed("from indoors the yard is only for a grill, and a stove comes first")
end
do
    -- A microwave: on a timer, never with metal, and food from the floor.
    squares={}
    local p=survivor(0,0); local s=state()
    local msq=square(1,0)
    local mc=T.container(1,0); mc.square=msq
    function mc:getType() return "microwave" end
    function mc:isPowered() return true end
    local micro={kind="IsoStove",container=mc,on=false,sq=msq}
    function micro:getContainer() return self.container end
    function micro:getSquare() return self.sq end
    function micro:Activated() return self.on end
    function micro:getObjectIndex() return 1 end
    function micro:getX() return 1 end
    function micro:getY() return 0 end
    function micro:getZ() return 0 end
    msq.objects={micro}
    ISBaseTimedAction={derive=function(self,name) local c={Type=name}; c.__index=c; return setmetatable(c,{__index=self}) end,
        new=function(class,character) return setmetatable({character=character},class) end, perform=function() end}
    local commands={}
    function sendClientCommand(_,module,command,args) commands[#commands+1]=args; micro.on=true end
    -- On the floor two squares away.
    local floor=square(-1,0)
    local raw=food({name="Chicken"})
    function raw:getMetalValue() return 0 end
    local world={item=raw,sq=floor}
    function world:getItem() return self.item end
    function world:getSquare() return self.sq end
    function floor:getWorldObjects() return T.list(world.item and {world} or {}) end
    ISGrabItemAction={new=function(_,player,w) return {Type="grab",isValid=function() return true end,perform=function()
        local item=w.item; w.item=nil; T.add(p.inventory,item) end} end}
    local pot=T.add(p.inventory,T.item("InventoryItem",{fullType="Base.Pot"}))
    function pot:getMetalValue() return 40 end
    assert(not Kitchen.accepts(micro,pot) and Kitchen.accepts(micro,raw),"Nothing metal in a microwave")
    assert(Kitchen.meal(p,s,1000) and Kitchen.ledger(p).stage=="fetching","Food on the floor is fetched")
    run(); Kitchen.settle(p,s,1100,false); s.pending=nil
    assert(p.inventory:contains(raw),"Picked up from the floor")
    assert(Kitchen.meal(p,s,1200)); run(); Kitchen.settle(p,s,1300,false); s.pending=nil
    assert(micro.on and mc:contains(raw) and commands[1] and commands[1].timer==(30+10)*60,"In, and the timer set for the cooking time and a little more")
    raw.cooked,raw.time=true,31
    assert(Kitchen.duty(p,s,2000,true)); run()
    assert(not micro.on and p.inventory:contains(raw),"Out, and off")
    passed("a microwave cooks on a timer, nothing metal goes in, and food is fetched from the floor")
end
do
    -- A stove the survivor can never reach: three tries, then a rest.
    squares={}
    local p=survivor(0,0); local s=state()
    stove(1,0)
    local raw=T.add(p.inventory,food())
    for attempt=1,3 do
        s.kitchenNext=nil
        assert(Kitchen.meal(p,s,1000*attempt),"Tries again: "..attempt)
        queued={}; Kitchen.settle(p,s,1000*attempt+1,true); s.pending=nil
    end
    s.kitchenNext=nil
    assert(not Kitchen.meal(p,s,5000) and s.kitchenSkip[raw:getID()],"Three refused walks: left alone for a while")
    passed("an unreachable stove is not tried forever")
end
do
    -- What the game counts as metal, and what is already inside.
    ItemTag=ItemTag or {}; ItemTag.HAS_METAL=ItemTag.HAS_METAL or "HasMetal"
    local metalTag=ItemTag.HAS_METAL
    local squareM=square(5,5); local mc=T.container(5,5); mc.square=squareM
    function mc:getType() return "microwave" end
    function mc:isPowered() return true end
    local micro={kind="IsoStove",container=mc,sq=squareM}
    function micro:getContainer() return self.container end
    function micro:getSquare() return self.sq end
    function micro:Activated() return false end
    squareM.objects={micro}
    local tin=food({name="Open beans"}); function tin:getMetalValue() return 0 end
    function tin:hasTag(tag) return tag==metalTag end
    local fish=food({name="Fish"}); function fish:getMetalValue() return 0 end; function fish:isBadInMicrowave() return true end
    local leg=food({name="Chicken"}); function leg:getMetalValue() return 0 end
    assert(not Kitchen.accepts(micro,tin),"A tagged tin is metal")
    local grillLike={object=micro}
    assert(Kitchen.accepts(micro,fish),"Food that tastes bad from a microwave may still go in when nothing else can cook it")
    assert(Kitchen.accepts(micro,leg))
    local fork=T.add(mc,T.item("InventoryItem",{name="Fork"})); function fork:getMetalValue() return 10 end
    local found=Kitchen.scan(survivor(5,6),{},1000)
    for _,s in ipairs(found.stoves) do assert(s.object~=micro,"A fork inside: the microwave is not used") end
    passed("nothing metal goes into a microwave, and nothing goes in with metal already there")
end
local function fireplace(x,y,lit,fuel)
    local sq=square(x,y)
    local c=T.container(x,y); c.square=sq
    function c:getType() return "fireplace" end
    local f={kind="IsoFireplace",container=c,lit=lit,fuel=fuel or 0,sq=sq}
    function f:isFireInteractionObject() return true end
    function f:getContainer() return self.container end
    function f:getSquare() return self.sq end
    function f:isLit() return self.lit end
    function f:getFuelAmount() return self.fuel end
    function f:getObjectIndex() return 1 end
    sq.objects={f}
    return f
end
local function material(kind,props)
    local item=T.item("InventoryItem",props or {})
    function item:getType() return kind end
    function item:getActualWeight() return 1 end
    function item:getCurrentUses() return 10 end
    return item
end
do
    -- No power: a fireplace is fuelled and lit from what is in the cupboards,
    -- cooks the dish, and is put out again.
    squares={}
    local p=survivor(0,0); local s=state()
    ISCampingMenu={isValidFuel=function() return true end,isValidTinder=function() return true end,
        getFuelDurationForItem=function(item) return item:getType()=="Log" and 360 or 20 end}
    function getCampingFuelMax() return 480 end
    local fp=fireplace(1,0,false,0)
    ISBBQAddFuel={new=function(_,player,obj,item,minutes) return {Type="fuel",isValid=function() return true end,perform=function()
        T.remove(p.inventory,item); obj.fuel=obj.fuel+minutes end} end}
    ISBBQLightFromLiterature={new=function(_,player,item,lighter,obj) return {Type="light",isValid=function() return true end,perform=function()
        T.remove(p.inventory,item); obj.lit=true end} end}
    ISBBQExtinguish={new=function(_,player,obj) return {Type="out",isValid=function() return obj.lit end,perform=function() obj.lit=false end} end}
    local shed=T.container(-1,0); shed.square=square(-1,0)
    shed.square.objects={{getContainerCount=function() return 1 end,getContainerByIndex=function() return shed end}}
    local drawer=T.container(0,1); drawer.square=square(0,1)
    drawer.square.objects={{getContainerCount=function() return 1 end,getContainerByIndex=function() return drawer end}}
    local log=T.add(shed,material("Log"))
    local paper=T.add(drawer,material("Newspaper"))
    local matches=T.add(drawer,material("Matches"))
    local raw=T.add(p.inventory,food())
    assert(Kitchen.meal(p,s,1000) and Kitchen.ledger(p).fire,"A fire, planned with what is nearby")
    for step=1,4 do
        run(); Kitchen.settle(p,s,1000+step,false); s.pending=nil
        local entry=Kitchen.ledger(p)
        if not entry or entry.stage~="fetching" then break end
        assert(Kitchen.duty(p,s,1100+step,true),"Next place to fetch from")
    end
    assert(fp.lit and fp.fuel>=360 and fp.container:contains(raw),"Fuelled, lit, dish in: "..tostring(fp.fuel))
    assert(Kitchen.ledger(p).lit,"Lit here, so put out here")
    raw.cooked,raw.time=true,31
    assert(Kitchen.duty(p,s,2000,true)); run()
    assert(not fp.lit and p.inventory:contains(raw),"Out, and put out")
    passed("a fireplace is fuelled, lit, cooks and is put out")
end
do
    -- A fire someone else lit is borrowed and left burning.
    squares={}
    local p=survivor(0,0); local s=state()
    local fp=fireplace(1,0,true,300)
    local raw=T.add(p.inventory,food())
    assert(Kitchen.meal(p,s,1000) and Kitchen.ledger(p).borrowed,"Borrowed")
    run(); Kitchen.settle(p,s,1100,false); s.pending=nil
    assert(fp.container:contains(raw) and not Kitchen.ledger(p).lit,"In, but not ours to put out")
    raw.cooked,raw.time=true,31
    assert(Kitchen.duty(p,s,2000,true)); run()
    assert(fp.lit and p.inventory:contains(raw),"Taken out; the fire still burns")
    assert(Kitchen.ended(p)==nil,"Stop leaves it alone")
    passed("a fire someone else lit is borrowed and left burning")
end
do
    -- Tinder is never also burned as fuel; nothing is fed or lit without our dish
    -- inside; a fire someone else lit meanwhile is not ours.
    local Fire=require "AutoMindful/Fire"
    squares={}
    local fp=fireplace(1,0,false,0)
    local twigs=material("Twigs"); local log=material("Log")
    local plan=Fire.plan(fp,30,{fuel={{item=twigs},{item=log}},tinder={{item=twigs}},starters={{item=material("Matches")}}})
    for _,f in ipairs(plan.fuel) do assert(f.item~=twigs,"The tinder is kept for lighting") end
    local p=survivor(0,0)
    T.add(p.inventory,log); local paper=T.add(p.inventory,material("Newspaper")); local m=T.add(p.inventory,material("Matches"))
    local dish=T.add(p.inventory,food())
    local actions={}
    ISTimedActionQueue.add=function(a) actions[#actions+1]=a; return a end
    local lit=false
    Fire.start(p,fp,{fuel={log:getID()},tinder=paper:getID(),starter=m:getID()},dish,function() lit=true end)
    for _,a in ipairs(actions) do assert(not a:isValid(),"No dish inside yet: nothing is fed or lit") end
    T.add(fp.container,dish)
    fp.lit=true
    assert(not actions[#actions]:isValid(),"Someone else lit it meanwhile: our light does not run")
    ISTimedActionQueue.add=function(action) queued[#queued+1]=action; return action end
    assert(not lit)
    passed("tinder is not burned as fuel, and only our dish and our light make a fire ours")
end
do
    -- Nothing ready, nothing raw, but the freezer is full: two come out to thaw,
    -- and no more while those are still thawing. Leftovers go to the freezer
    -- when no fridge has room for all of them.
    local function cold(x,kind,powered)
        local c=T.container(x,0); c.square=square(x,0)
        function c:getType() return kind end
        function c:isPowered() return powered end
        c.square.objects={{getContainerCount=function() return 1 end,getContainerByIndex=function() return c end}}
        return c
    end
    local function calm(p)
        p.values.HUNGER=0
        function p:getStats() return {get=function() return 0 end} end
        function p:getMoodles() return {getMoodleLevel=function() return 0 end} end
    end
    -- No stove or fire: only cooked leftovers come out, raw meat stays frozen.
    squares={}
    local p=survivor(0,0); local s=state(); calm(p)
    local fz=cold(-1,"freezer",true)
    local raw=T.add(fz,food({name="Frozen chicken",frozen=true}))
    local stew=T.add(fz,food({name="Frozen stew",frozen=true,cooked=true}))
    assert(Kitchen.thaw(p,s,1000),"Leftovers come out without a stove"); run()
    assert(p.inventory:contains(stew) and fz:contains(raw),"Raw meat waits for a heat source")
    assert(not Kitchen.thaw(p,s,1000+Kitchen.policy.thawMs+1),"Not while the stew is still thawing")
    -- With a stove: two of three, and not more while those thaw.
    squares={}
    p=survivor(0,0); s=state(); calm(p)
    stove(1,0)
    fz=cold(-1,"freezer",true)
    local a=T.add(fz,food({name="Frozen chicken",frozen=true}))
    local b=T.add(fz,food({name="Frozen steak",frozen=true}))
    local c=T.add(fz,food({name="Frozen pork",frozen=true}))
    -- Frozen food in a fridge or a dead freezer is not a freezer's.
    local fridge=cold(-2,"fridge",true)
    local warm=T.add(fridge,food({name="Pork in the fridge",frozen=true}))
    local dead=T.add(cold(-3,"freezer",false),food({name="Pork in a dead freezer",frozen=true}))
    assert(Kitchen.thaw(p,s,1000),"Taken out to thaw")
    run()
    local out=0
    for _,item in ipairs({a,b,c}) do if p.inventory:contains(item) then out=out+1 end end
    assert(out==2,"Two at a time: "..out)
    assert(not p.inventory:contains(warm) and not p.inventory:contains(dead))
    assert(not Kitchen.thaw(p,s,2000),"Not again straight away")
    assert(not Kitchen.thaw(p,s,1000+Kitchen.policy.thawMs+1),"Not while two are thawing in the pocket")
    -- Leftovers: the fridge has room for one, so both go to the freezer.
    for _,item in ipairs({a,b}) do T.remove(p.inventory,item) end
    function fridge:hasRoomFor(_,what) return type(what)~="number" or what<=0.3 end
    local one=T.add(p.inventory,food({name="Cooked chicken",cooked=true}))
    local two=T.add(p.inventory,food({name="Cooked steak",cooked=true}))
    p:getModData().AutoMindfulLeftovers={one:getID(),two:getID()}
    assert(Kitchen.store(p,s,3000)); run()
    assert(fz:contains(one) and fz:contains(two),"Kept together in the freezer")
    passed("frozen food comes out to thaw only when nothing else is left, one meal at a time, and leftovers can go in the freezer")
end
do
    -- What a body lying in the house carries is fetched like the floor; an
    -- animal carcass is not, and a body taken away is not walked to.
    squares={}
    local p=survivor(0,0); local s=state()
    stove(1,0)
    local function body(x,animal)
        local sq=square(x,0)
        local pockets=T.container(x,0)
        local b={kind="IsoDeadBody",sq=sq}
        function b:isAnimal() return animal end
        function b:isFakeDead() return false end
        function b:getReanimateTime() return self.rising or -1 end
        function b:getStaticMovingObjectIndex()
            for i,o in ipairs(self.sq.bodies) do if o==self then return i-1 end end
            return -1
        end
        function b:getContainer() return pockets end
        function b:getSquare() return self.sq end
        sq.bodies={b}
        function sq:getStaticMovingObjects() return T.list(self.bodies) end
        return b,pockets
    end
    local _,deer=body(-2,true)
    local carcass=T.add(deer,food({name="Venison"}))
    local dead,pockets=body(-1,false)
    local raw=T.add(pockets,food({name="Chicken"}))
    local found=Kitchen.scan(p,{},1000)
    assert(#found.food==1 and found.food[1].item==raw,"Only the dead survivor's pockets: "..#found.food)
    assert(Fetch.present(found.food[1]))
    dead.sq.bodies={}
    assert(not Fetch.present(found.food[1]),"The body is gone")
    dead.sq.bodies={dead}
    dead.rising=5
    assert(#Kitchen.scan(p,{},1000).food==0,"Not from a body about to get up")
    dead.rising=nil
    T.add(pockets,material("Matches"))
    assert(#Kitchen.scan(p,{},1000).starters==0,"Only food from the dead")
    assert(Kitchen.meal(p,s,1000) and Kitchen.ledger(p).stage=="fetching","Fetched from the body")
    run(); Kitchen.settle(p,s,1100,false)
    assert(p.inventory:contains(raw) and deer:contains(carcass),"Taken from the pockets, not the carcass")
    passed("food a body carries is fetched like the floor's, but not a carcass, a body getting up, or anything but food")
end
do
    -- The Kitchen tab's summary: each heat and what it needs, food, cold.
    squares={}
    local p=survivor(0,0)
    local dead=stove(1,0); dead.container.off=true
    local busy=stove(3,0); T.add(busy.container,food({name="Someone's pie"}))
    local place=fireplace(-2,0,false,0)
    local shelf=T.container(-1,0); shelf.square=square(-1,0)
    shelf.square.objects={{getContainerCount=function() return 1 end,getContainerByIndex=function() return shelf end}}
    T.add(shelf,food({name="Chicken",rotsAt=1}))
    T.add(shelf,material("Log"))
    local summary=Kitchen.summary(p,1000)
    local states={}
    for _,heat in ipairs(summary.heats) do states[heat.tiles]=heat.state end
    assert(states[1]=="No power" and states[3]=="Something is already inside","Stove states: "..tostring(states[1]).." / "..tostring(states[3]))
    assert(states[2]=="Not lit: needs paper or twigs, a lighter or matches","A fire says all it is missing: "..tostring(states[2]))
    -- Ours, while the food is still being fetched, is not yet cooking.
    dead.container.off=false
    p:getModData().AutoMindfulKitchen={stage="fetching",name="Chicken",x=1,y=0,z=0}
    local mine=Kitchen.summary(p,1000).heats[1]
    assert(mine.state=="Getting food for Chicken","Not cooking yet: "..mine.state)
    assert(summary.heats[1].tiles==1 and summary.raw==1 and summary.soon==1 and summary.wood>=1 and summary.starters==0, string.format("raw=%d soon=%d wood=%d starters=%d",summary.raw,summary.soon,summary.wood,summary.starters))
    passed("the kitchen summary says what each heat source needs and what there is to cook")
end
