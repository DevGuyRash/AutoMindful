local runtime = "mods/AutoMindful/common/media/lua/client/"
package.path = runtime .. "?.lua;" .. package.path
package.loaded["AutoMindful/WaterSources"] = {scan=function() return {} end, choose=function() return nil end}
for _, name in ipairs({"TimedActions/ISTimedActionQueue", "TimedActions/ISReadABook", "TimedActions/ISDrinkFluidAction", "TimedActions/ISWaitWhileGettingUp", "ISUI/ISWorldObjectContextMenu", "ISUI/ISInventoryPaneContextMenu", "TimedActions/ISInventoryTransferUtil", "TimedActions/ISBaseTimedAction", "TimedActions/ISDropWorldItemAction"}) do
    package.preload[name] = function() return true end
end
local T = {now = 0, nights = 50, client = false, sleepNeeded = true, sleepAllowed = true}
AutoMindfulTest = T
CharacterStat = {HUNGER="HUNGER", THIRST="THIRST", BOREDOM="BOREDOM", ENDURANCE="ENDURANCE", FATIGUE="FATIGUE", PAIN="PAIN", PANIC="PANIC"}
CharacterTrait = {ILLITERATE="illiterate", DISCIPLINED="disciplined", COUCHPOTATO="couchpotato"}
ItemTag = {UNINTERESTING="uninteresting", PICTUREBOOK="picturebook", PICTURE="picture"}
MoodleType = {FOOD_EATEN="food", PAIN="pain", HUNGRY="hungry", THIRST="thirst"}
Perks = {Meditation="Meditation", Fitness="Fitness", Nimble="Nimble"}
Fluid = {Water="Water"}
SkillBook = {Cooking=true}
SandboxVars = {Yoga={KeepBags=true}, Meditation={KeepBags=true}, LSMeditation={RemoveLevitation=false}}
Events = {}
for _, name in ipairs({"OnPlayerUpdate", "OnPlayerDeath", "OnGameStart"}) do Events[name] = {Add=function() end} end
function getTimestampMs() return T.now end
function getGameTime() return {getNightsSurvived=function() return T.nights end} end
HaloTextHelper = {addBadText=function(player,text) player.halos[#player.halos+1]=text end}
function isClient() return T.client end
function getServerOptions() return {getBoolean=function(_, key) return key == "SleepNeeded" and T.sleepNeeded or key == "SleepAllowed" and T.sleepAllowed end} end
function getText(key) return key end
function instanceof(item, kind) return item.kind == kind end
function getPlayerInventory() return T.player and T.player.inventoryPage end
function getPlayerLoot() return T.player and T.player.lootPage end
function getPlayerContextMenu() return T.player and {isVisible=function() return T.player.contextOpen or false end} end
function getSpecificPlayer() return T.player end
function T.list(items)
    return {size=function() return #items end, get=function(_, index) return items[index+1] end, isEmpty=function() return #items == 0 end, contains=function(_, value) for _, item in ipairs(items) do if item == value then return true end end return false end}
end
function T.square(x,y,z)
    local square = {x=x or 0,y=y or 0,z=z or 0}
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    function square:canReachTo(other) return not other.blocked and self.z==other:getZ() and math.abs(self.x-other:getX())<=1 and math.abs(self.y-other:getY())<=1 end
    return square
end
function T.container(x, y)
    local c = {items={},square=T.square(x,y)}
    function c:getItems() return T.list(self.items) end
    function c:getOutermostContainer() return self.root or self end
    function c:getType() return self.floor and "floor" or "container" end
    function c:hasRoomFor() return not self.full end
    function c:getSourceGrid() return self.square end
    function c:getContainingItem() return self.containingItem end
    function c:getItemById(id)
        for _, item in ipairs(self.items) do
            if item:getID()==id then return item end
            local nested = item.kind == "InventoryContainer" and item:getInventory()
            local found = nested and nested:getItemById(id)
            if found then return found end
        end
    end
    function c:contains(item) for _, candidate in ipairs(self.items) do if candidate==item then return true end end return false end
    return c
end

local nextID = 0
function T.item(kind, properties)
    nextID = nextID + 1
    local i = properties or {}
    i.kind, i.id, i.tags, i.data = kind, nextID, i.tags or {}, i.data or {}
    function i:getID() return self.id end
    function i:getFullType() return self.fullType or ("Base."..self.kind) end
    function i:getModule() return "Base" end
    function i:getOpeningRecipe() return self.openingRecipe end
    function i:getReplaceOnUseFullType() return self.replace end
    function i:getBaseHunger() return self.baseHunger or -0.5 end
    function i:getHungChange() return self:getHungerChange() end
    function i:getThirstChange() return self.thirst or 0 end
    function i:isWorn() return self.worn or false end
    function i:getScriptItem() return {isCantEat=function() return self.cantEat or false end} end
    function i:getContainer() return self.container end
    function i:getInventory() return self.inventory end
    function i:getWorldItem() return self.world end
    function i:getDisplayName() return self.name or self.kind end
    function i:getBoredomChange() return self.boredom or (self.kind == "Literature" and -20 or 0) end
    function i:getHungerChange() return self.hunger or -0.5 end
    function i:getCalories() return self.calories or 1000 end
    function i:getSkillTrained() return self.skill end
    function i:hasTag(tag) return self.tags[tag] end
    function i:hasModData() for _ in pairs(self.data) do return true end return false end
    function i:getModData() return self.data end
    function i:getFluidContainer() return self.fluid end
    function i:getRequireInHandOrInventory() return nil end
    for method, property in pairs({isRotten="rotten", isBurnt="burnt", isFrozen="frozen", isTainted="tainted", isPoison="poison", isAlcoholic="alcohol", isSealed="sealed", isbDangerousUncooked="rawDanger", isCooked="cooked"}) do
        i[method] = function(self) return self[property] or false end
    end
    function i:getPoisonPower() return self.poisonPower or 0 end
    function i:getFoodSicknessChange() return self.sickness or 0 end
    return i
end
function T.water(properties)
    local p = properties or {}
    local f = {amount=1}
    function f:isEmpty() return self.amount <= 0 end
    function f:canPlayerEmpty() return not p.locked end
    function f:getCapacity() return p.capacity or 1 end
    function f:getAmount() return self.amount end
    function f:isPureFluid() return not p.mixed end
    function f:isPoisonous() return p.poison or false end
    function f:isTainted() return p.tainted or false end
    function f:getProperties() return {
        getHungerChange=function() return (p.hunger or 0)*f.amount end,
        getThirstChange=function() return (p.thirst or -0.5)*f.amount end,
        getCalories=function() return (p.calories or 0)*f.amount end,
        getPoison=function() return p.poison and 1 or 0 end,
        getFoodSicknessChange=function() return p.sickness or 0 end,
        getAlcohol=function() return p.alcohol and 1 or 0 end,
    } end
    return T.item("Water", {fluid=f,worn=p.worn})
end
function T.remove(container,item)
    for index, candidate in ipairs(container.items) do if candidate==item then table.remove(container.items,index); item.container=nil; return end end
end
function T.world(square)
    return {getSquare=function() return square end,getOffX=function() return .4 end,
        getOffY=function() return .6 end,getOffZ=function() return 0 end,getFluidContainer=function() return nil end}
end

function T.add(container, item)
    container.items[#container.items+1] = item
    item.container = container
    if container.floor then
        item.world = item.world or T.world(container.square)
        item.world:getSquare().floorContainer = container
    else
        if item.world and item.world:getFluidContainer() then item.fluid=item.world:getFluidContainer() end
        item.world=nil
    end
    return item
end
function T.playerNew()
    local p = {inventory=T.container(), values={HUNGER=0.05, THIRST=0, BOREDOM=0, ENDURANCE=1, FATIGUE=0, PAIN=0, PANIC=0}, meditation=0, xp=0, yoga={0,0,100}, hours=10, calories=2000, read={}, printRead={}, history={}, traits={}}
    p.halos={}
    p.inventoryPage={}
    p.lootPage={refreshBackpacks=function()
        p.refreshCount=(p.refreshCount or 0)+1
        if p.available then
            p.nearby={}
            for _,container in ipairs(p.available) do
                if p:getSquare():canReachTo(container:getSourceGrid()) then p.nearby[#p.nearby+1]=container end
            end
        end
    end}
    p.data = {LSMoodles={Embarrassed={Value=0,Level=0}, MindfulState={Value=0,Level=0}, WasTaughtSkill={Value=0,Level=0}, Zen={Value=0,Level=0}}}
    function p:getModData() return self.data end
    function p:getInventory() return self.inventory end
    function p:isLocalPlayer() return true end
    function p:getPlayerNum() return 0 end
    function p:getStats() return {get=function(_, name) return p.values[name] or 0 end, getNumVisibleZombies=function() return p.zombies or 0 end, getNumChasingZombies=function() return 0 end, getNumVeryCloseZombies=function() return 0 end} end
    function p:getBodyDamage() return {getOverallBodyHealth=function() return 100 end, getNumPartsBleeding=function() return 0 end} end
    function p:getNutrition() return {getCalories=function() return p.calories end} end
    function p:getMoodles() return {getMoodleLevel=function(_, kind) return kind == "pain" and p.painMoodle or kind == "food" and p.foodMoodle or kind == "hungry" and p.hungerMoodle or kind == "thirst" and p.thirstMoodle or 0 end} end
    function p:getPerkLevel(perk) return perk == "Meditation" and self.meditation or 0 end
    function p:getXp() return {getXP=function() return p.xp end} end
    function p:getHoursSurvived() return self.hours end
    function p:getLastHourSleeped() return 0 end
    function p:getSquare() return self.square or self.inventory:getSourceGrid() end
    function p:isSitOnGround() return self.sitting or false end
    function p:isSitting() return self.sitting or false end
    function p:reportEvent() self.sitting = true end
    function p:setVariable() end
    function p:tooDarkToRead() return self.dark or false end
    function p:hasTrait(trait) return self.traits[trait] end
    function p:getReadLiterature() return {get=function(_,title) local value=p.read[title]; return value==true and T.nights or value end} end
    function p:isLiteratureRead(title)
        local last=self.read[title]
        return last==true or (type(last)=="number" and T.nights < last+(SandboxVars.LiteratureCooldown or 45))
    end
    function p:getReadPrintMedia() local ids={} for id in pairs(self.printRead) do ids[#ids+1]=id end return T.list(ids) end
    function p:hasTimedActions() return #ISTimedActionQueue.getTimedActionQueue(self).queue > 0 end
    function p:isDead() return self.dead or false end
    function p:isOnFire() return false end
    function p:getVehicle() return nil end
    function p:isPlayerMoving() return self.moving or false end
    function p:isAiming() return self.aiming or false end
    function p:isDraggingCorpse() return false end
    function p:isAsleep() return self.asleep or false end
    function p:isSittingOnFurniture() return false end
    T.player = p
    return p
end
ISTimedActionQueue = {queues={}}
function ISTimedActionQueue.getTimedActionQueue(player)
    if not ISTimedActionQueue.queues[player] then
        local q = {queue={}}
        function q:removeFromQueue(action) for index, entry in ipairs(self.queue) do if entry == action then table.remove(self.queue,index) return end end end
        ISTimedActionQueue.queues[player] = q
    end
    return ISTimedActionQueue.queues[player]
end
function ISTimedActionQueue.add(action)
    if not action.ignoreAction then
        local q = ISTimedActionQueue.getTimedActionQueue(action.character)
        q.queue[#q.queue+1] = action
        action.character.history[#action.character.history+1] = action.Type
    end
end
function ISTimedActionQueue.clear(player)
    local q = ISTimedActionQueue.getTimedActionQueue(player)
    if q.queue[1] then q.queue[1]:stop() end
    q.queue = {}
end
function T.action(player, kind, effect)
    local a = {character=player, Type=kind, effect=effect}
    function a:perform() if self.effect then self.effect() end ISTimedActionQueue.getTimedActionQueue(self.character):removeFromQueue(self) end
    function a:stop() self.stopped=true; ISTimedActionQueue.getTimedActionQueue(self.character).queue={} end
    function a:forceCancel() self.cancelled=true end
    function a:isValid() return true end
    return a
end
ISReadABook = {new=function(_, p, item) return T.action(p,"read",function()
    if not p.refuseCare then
        p.values.BOREDOM=math.max(0,p.values.BOREDOM+item:getBoredomChange())
        if item.data.literatureTitle then p.read[item.data.literatureTitle]=T.nights end
    end
end) end}
ISDrinkFluidAction = {new=function(_, p, item, percentage)
    p.drinkPercentage = percentage
    return T.action(p,"drink",function()
        if not p.refuseCare then
            local relief=-item.fluid:getProperties():getThirstChange()
            p.values.THIRST=math.max(0,p.values.THIRST-relief*percentage)
            item.fluid.amount=item.fluid.amount*(1-percentage)
        end
    end)
end}
ISWaitWhileGettingUp = {new=function(_, p) return T.action(p,"stand",function() p.sitting=false end) end}
ISWearClothing = {new=function(_,p) return T.action(p,"wear") end}
ISWorldObjectContextMenu = {onSleepWalkToComplete=function() T.player.asleep=true end}
ISInventoryPaneContextMenu = {
    getEatingMask=function() return nil end,
    onDrinkFluid=function(item,portion,p) ISTimedActionQueue.add(ISDrinkFluidAction:new(p,item,portion)) end,
    eatItem=function(item, fraction)
        local p=T.player
        ISTimedActionQueue.add(T.action(p,"eat",function()
            if not p.refuseCare then
                local remaining=-item:getHungerChange()
                local eaten=math.min(remaining,-item:getBaseHunger()*fraction)
                local ratio=eaten/remaining
                p.values.HUNGER=math.max(-0.1,p.values.HUNGER-eaten)
                p.calories=p.calories+item:getCalories()*ratio
                item.hunger=-(remaining-eaten)
                item.calories=item:getCalories()*(1-ratio)
                if item.hunger >= -0.000001 then
                    T.remove(item:getContainer(),item)
                    if item.replace then T.add(p.inventory,T.item("InventoryItem",{fullType=item.replace})) end
                end
            end
        end))
    end,
    getContainers=function(player)
        local all={player.inventory}
        for _, container in ipairs(player.nearby or {}) do all[#all+1]=container end
        return T.list(all)
    end,
}
ISInventoryTransferUtil = {newInventoryTransferAction=function(p,item,source,target)
    local action=T.action(p,"ISInventoryTransferAction",function() T.remove(source,item); T.add(target,item) end)
    function action:isValid() return not target.reject end
    return action
end}
ISDropWorldItemAction = {new=function(_,p,item,square)
    local action=T.action(p,"ISDropWorldItemAction",function()
        T.remove(p.inventory,item)
        item.world=T.world(square)
        T.add(assert(square.floorContainer),item)
    end)
    function action:isValid() return not square.full and p:getSquare():canReachTo(square) end
    return action
end}

HiddenSkills = {getSkill=function(p) return p.yoga end, getLevel=function(p) return p.yoga[1] end}
ZenWellnessContextMenu = {Options={}}
for _, kind in ipairs({"Yoga", "Meditation"}) do
    ZenWellnessContextMenu.Options[kind] = {
        canPerform=function(p) if kind == "Yoga" then return p.yogaBlocked ~= nil, p.yogaBlocked end return p.values.BOREDOM > 30, "bored" end,
        onAction=function(_, _, p)
            ISTimedActionQueue.add(T.action(p,kind,function()
                if not p.noXP then if kind == "Meditation" then p.meditation=math.min(10,p.meditation+1); p.xp=p.xp+1 else p.yoga[1]=math.min(10,p.yoga[1]+1); p.yoga[2]=p.yoga[2]+1 end end
                p.values.BOREDOM = kind == "Meditation" and p.values.BOREDOM+10 or math.max(0,p.values.BOREDOM-15)
            end))
        end,
    }
end
local C = require "AutoMindful/Controller"
T.controller = C
function T.tick(p, finish, gameHours)
    T.now = T.now+1000
    p.hours = p.hours+(gameHours or 0.01)
    C.update(p)
    local action = ISTimedActionQueue.getTimedActionQueue(p).queue[1]
    if finish ~= false and action then action:perform() end
end
function T.run(p, limit)
    for i=1,limit or 400 do
        T.tick(p)
        if not C.status(p).active then return C.status(p) end
    end
    error("Automation did not terminate")
end
function T.check(condition, message) assert(condition,message) end
local passed = 0
local function test(name, fn) fn(); passed=passed+1; print("PASS "..name) end
local function hasHistory(p,kind) for _, entry in ipairs(p.history) do if entry == kind then return true end end return false end
T.hasHistory = hasHistory

test("both targets reach 10 with model provisions and native boundary actions",function()
    local p=T.playerNew(); p.values.BOREDOM=40; p.values.HUNGER=0.25; p.values.THIRST=0.25
    T.add(p.inventory,T.item("Food")); T.add(p.inventory,T.water())
    for i=1,20 do T.add(p.inventory,T.item("Literature")) end
    assert(C.start(p,"both",false)); local s=T.run(p)
    assert(s.phase == "complete" and s.meditation == 10 and s.yoga == 10)
    assert(hasHistory(p,"read") and hasHistory(p,"eat") and hasHistory(p,"drink"))
end)
test("single targets stop at 10 and leave the other skill unchanged",function()
    for _, mode in ipairs({"yoga","meditation"}) do
        local p=T.playerNew(); for i=1,20 do T.add(p.inventory,T.item("Literature")) end
        assert(C.start(p,mode,false)); local s=T.run(p)
        assert(s.phase == "complete")
        assert(mode == "yoga" and s.yoga == 10 and s.meditation == 0 or mode == "meditation" and s.meditation == 10 and s.yoga == 0)
    end
end)
test("missing drink stock is not a start gate at ordinary thirst",function()
    local p=T.playerNew(); p.values.THIRST=0.3; assert(C.start(p,"both",false))
    T.tick(p); T.tick(p,false)
    assert(C.status(p).active and hasHistory(p,"Meditation") and C.status(p).careNotice)
    C.stop(p)
end)
test("empty food and drink reserves allow mild needs and low calories without interrupting an allowed session",function()
    for _, mode in ipairs({"yoga","meditation"}) do
        local p=T.playerNew(); p.values.HUNGER=.3; p.values.THIRST=.3; p.calories=100
        p.values.BOREDOM=20; p.yogaBlocked=mode=="meditation" and "mat" or nil
        assert(C.start(p,mode,false)); T.tick(p,false)
        if mode=="meditation" then T.tick(p,false) end
        local action=ISTimedActionQueue.getTimedActionQueue(p).queue[1]
        assert(action and C.status(p).active and C.status(p).careNotice)
        for i=1,4 do T.tick(p,false) end
        assert(C.status(p).active and ISTimedActionQueue.getTimedActionQueue(p).queue[1]==action and not action.stopped,
            "Optional care without usable stock must not repeatedly interrupt native training")
        C.stop(p)
    end
end)
test("native maximum hunger and thirst moodles stop only when that critical need cannot be restored",function()
    for _, kind in ipairs({"food","water"}) do
        local p=T.playerNew()
        if kind=="food" then p.values.HUNGER=.8; p.hungerMoodle=4 else p.values.THIRST=.9; p.thirstMoodle=4 end
        assert(C.start(p,"yoga",false)); T.tick(p,false)
        assert(not C.status(p).active and not hasHistory(p,"Yoga"))
        assert(C.status(p).message:find(kind=="food" and "Starving to Death" or "Dying of Thirst",1,true))
    end
end)
test("without literature the native meditation boredom limit remains authoritative",function()
    local p=T.playerNew(); p.values.BOREDOM=20; p.yogaBlocked="mat"
    assert(C.start(p,"meditation",false)); T.tick(p,false); T.tick(p,false)
    assert(C.status(p).active and hasHistory(p,"Meditation"))
    p.values.BOREDOM=31; T.tick(p,false); T.tick(p,false)
    assert(not C.status(p).active and C.status(p).message:find("above 30 boredom",1,true))
end)
test("water uses native fluid portions and waits for the native fullness gate",function()
    local p=T.playerNew(); p.values.THIRST=0.2; p.foodMoodle=3
    T.add(p.inventory,T.water()); assert(C.start(p,"yoga",false)); T.tick(p)
    assert(C.status(p).active and not hasHistory(p,"drink"))
    p.foodMoodle=0; T.tick(p)
    assert(hasHistory(p,"drink") and p.drinkPercentage == 0.4)
    C.stop(p)
end)
test("sleep follows server rules and resumes after waking",function()
    T.client=true; T.sleepNeeded=true; T.sleepAllowed=false
    local p=T.playerNew(); p.values.FATIGUE=0.65; assert(C.start(p,"yoga",false)); T.tick(p)
    assert(not C.status(p).active and not p.asleep)
    T.sleepAllowed=true; assert(C.start(p,"yoga",false)); T.tick(p); assert(p.asleep)
    p.asleep=false; p.values.FATIGUE=0; T.tick(p); assert(hasHistory(p,"Yoga"))
    C.stop(p); T.client=false
end)
test("foreign queued action survives while actual training is cancelled",function()
    local p=T.playerNew(); assert(C.start(p,"yoga",false)); T.tick(p,false)
    local q=ISTimedActionQueue.getTimedActionQueue(p); local owned=q.queue[1]
    local foreign=T.action(p,"manual"); ISTimedActionQueue.add(foreign); T.tick(p,false)
    assert(not C.status(p).active and owned.stopped)
    assert(#q.queue == 1 and q.queue[1] == foreign and not foreign.cancelled and not foreign.stopped)
end)
test("refused care cannot loop indefinitely",function()
    for _, kind in ipairs({"food","water","literature"}) do
        local p=T.playerNew(); p.refuseCare=true; p.yogaBlocked="mat"
        if kind == "food" then p.values.HUNGER=0.3 elseif kind == "water" then p.values.THIRST=0.3 else p.values.BOREDOM=40 end
        for i=1,3 do T.add(p.inventory,kind == "food" and T.item("Food") or kind == "water" and T.water() or T.item("Literature")) end
        assert(C.start(p,"meditation",false)); local s=T.run(p,40); assert(s.phase == "stopped")
    end
end)
test("zero XP watchdog spans completed sessions",function()
    local p=T.playerNew(); p.noXP=true; assert(C.start(p,"yoga",false))
    for i=1,10 do T.tick(p,true,1); if not C.status(p).active then break end end
    assert(not C.status(p).active and C.status(p).phase == "stopped")
end)
test("embarrassment recovery resumes yoga without literature",function()
    local p=T.playerNew(); p.values.BOREDOM=40; p.yogaBlocked="ContextMenu_Embarrassed"
    assert(C.start(p,"both",false)); T.tick(p); T.tick(p); assert(C.status(p).active and not hasHistory(p,"Yoga"))
    p.yogaBlocked=nil; T.tick(p); T.tick(p); assert(hasHistory(p,"Yoga")); C.stop(p)
end)
test("supplies reject unsafe food and useless or read literature",function()
    local S=require "AutoMindful/Supplies"; local p=T.playerNew()
    for _, prop in ipairs({{rotten=true},{rawDanger=true},{poison=true},{sealed=true},{alcohol=true},{frozen=true},{sickness=1}}) do T.add(p.inventory,T.item("Food",prop)) end
    local good=T.add(p.inventory,T.item("Food"))
    T.add(p.inventory,T.item("Literature",{skill="Cooking"})); T.add(p.inventory,T.item("Literature",{tags={uninteresting=true}}))
    p.read.story=true; T.add(p.inventory,T.item("Literature",{data={literatureTitle="story"}}))
    p.printRead[7]=true; T.add(p.inventory,T.item("Literature",{data={printMedia={id=7}}}))
    T.add(p.inventory,T.water({tainted=true})); T.add(p.inventory,T.water({alcohol=true})); T.add(p.inventory,T.water({capacity=5}))
    local scan=S.scan(p,false); assert(#scan.food == 1 and scan.food[1].item == good and #scan.literature == 0 and #scan.water == 0)
end)
test("nearby collection is opt-in and respects adjacent range and capacity",function()
    local S=require "AutoMindful/Supplies"; local p=T.playerNew(); local near=T.container(1,0); local far=T.container(2,0)
    T.add(near,T.item("Food")); T.add(far,T.item("Food")); p.nearby={near,far}
    assert(#S.scan(p,false).food == 0 and #S.scan(p,true).food == 1)
    p.inventory.full=true; assert(not S.choose(p,"food",true,{}))
    p.inventory.full=false; assert(S.choose(p,"food",true,{}).item == near.items[1])
end)
test("nearby portable bags use their native world anchor when source grid is absent",function()
    local S=require "AutoMindful/Supplies"; local p=T.playerNew()
    local source,far=T.container(1,0),T.container(2,0)
    for _,container in ipairs({source,far}) do
        local square=container.square; container.square=nil
        container.containingItem=T.item("InventoryContainer",{inventory=container,
            world={getSquare=function() return square end,getFluidContainer=function() return nil end}})
        T.add(container,T.item("Food"))
    end
    p.nearby={source,far}
    assert(S.report(p,true).nearbyFood==1)
    local item=source.items[1]; local loan=S.loan(p,item)
    T.remove(source,item); T.add(p.inventory,item)
    local action,notice=S.returnAction(p,loan)
    assert(action and not notice)
    action:perform()
    assert(source:contains(item) and not p.inventory:contains(item))
end)
test("floor provisions use each world item's square when the synthetic container has no grid",function()
    local S=require "AutoMindful/Supplies"; local p=T.playerNew(); local floor=T.container(); floor.floor=true
    function floor:getSourceGrid() return nil end
    local function ground(x, z)
        return {getSquare=function() return {getX=function() return x end, getY=function() return 0 end, getZ=function() return z end} end,
            getFluidContainer=function() return nil end}
    end
    T.add(floor,T.item("Food",{world=ground(1,0)}))
    T.add(floor,T.item("Food",{world=ground(2,0)}))
    T.add(floor,T.item("Food",{world=ground(0,1)}))
    local bottle=T.water(); local fluid=bottle.fluid; bottle.fluid=nil
    bottle.world=ground(0,0)
    function bottle.world:getFluidContainer() return fluid end
    T.add(floor,bottle)
    p.nearby={floor}
    assert(#S.scan(p,false).food == 0 and #S.scan(p,true).food == 1)
    assert(#S.scan(p,true).water == 1 and S.choose(p,"water",true,{}).item == bottle)
end)
test("missing Lifestyle rejects start but status and preparation remain usable",function()
    local upstream=ZenWellnessContextMenu; ZenWellnessContextMenu=nil
    local p=T.playerNew(); local started,message=C.start(p,"both",false)
    assert(not started and type(message) == "string" and not C.status(p).active)
    assert(type(C.prepare(p,false).message) == "string")
    ZenWellnessContextMenu=upstream
end)
test("inventory transfers pause and resume care without cancelling the training loop",function()
    local p=T.playerNew(); p.values.BOREDOM=40
    T.add(p.inventory,T.item("Literature"))
    assert(C.start(p,"meditation",false)); T.tick(p,false)
    local transfer=T.action(p,"ISInventoryTransferAction",function() T.add(p.inventory,T.item("Food")) end)
    ISTimedActionQueue.add(transfer)
    T.tick(p,false)
    assert(C.status(p).active and C.status(p).phase=="manual", "Training must remain active while your inventory transfer finishes.")
    local queue=ISTimedActionQueue.getTimedActionQueue(p).queue
    assert(#queue==1 and queue[1]==transfer and not transfer.cancelled)
    transfer:perform()
    for i=1,6 do T.tick(p) end
    assert(C.status(p).active and hasHistory(p,"Meditation"),"care must resume after the manual inventory transfer")
    assert(#p.halos==0,"allowed inventory work must not report cancellation")
    C.stop(p)
end)
test("movement cancels once with a visible reason while brief context gestures do not",function()
    local p=T.playerNew(); assert(C.start(p,"yoga",false)); T.tick(p,false)
    p.aiming=true; T.now=T.now+100; C.update(p)
    p.contextOpen=true; T.now=T.now+100; C.update(p)
    assert(C.status(p).active)
    p.aiming=false; p.contextOpen=false
    p.moving=true; T.now=T.now+1000; C.update(p); C.update(p)
    assert(not C.status(p).active and #p.halos==1 and p.halos[1]:find("moved",1,true))
end)
test("live preparation reflects movement inventory changes and collection permission",function()
    local p=T.playerNew(); local shelf=T.container(5,0)
    T.add(shelf,T.item("Food")); p.available={shelf}; p.nearby={}
    assert(C.prepare(p,false,true).nearbyFood==0)
    p.square=T.square(5,0)
    local near=C.prepare(p,false,true)
    assert(near.food==0 and near.nearbyFood==1 and #near.warnings>0)
    T.add(p.inventory,T.item("Food"))
    assert(C.prepare(p,false,true).food==1)
    p.square=T.square(0,0)
    assert(C.prepare(p,false,true).nearbyFood==0)
    assert(C.start(p,"yoga",false)); T.tick(p,false)
    local action=ISTimedActionQueue.getTimedActionQueue(p).queue[1]
    C.setCollectNearby(p,true)
    assert(C.status(p).active and C.status(p).collectNearby)
    C.prepare(p,true,true)
    assert(ISTimedActionQueue.getTimedActionQueue(p).queue[1]==action and not action.stopped)
    C.stop(p)
end)
test("borrowed literature returns to its original container and meditation resumes",function()
    local p=T.playerNew(); p.values.BOREDOM=40
    local shelf=T.container(1,0)
    local book=T.add(shelf,T.item("Literature"))
    p.nearby={shelf}
    assert(C.start(p,"meditation",true)); local status=T.run(p)
    assert(status.phase=="complete" and status.meditation==10)
    assert(shelf:contains(book) and not p.inventory:contains(book))
    assert(status.pendingReturns==0 and hasHistory(p,"read") and hasHistory(p,"Meditation"))
end)
test("borrowed resources keep their origin when native synchronization replaces the Lua item reference",function()
    local p=T.playerNew(); p.values.BOREDOM=40
    local shelf=T.container(1,0); local original=T.add(shelf,T.item("Literature"))
    p.nearby={shelf}; assert(C.start(p,"meditation",true)); T.tick(p)
    T.remove(p.inventory,original)
    local synchronized=T.item("Literature"); synchronized.id=original.id; T.add(p.inventory,synchronized)
    local status=T.run(p)
    assert(status.phase=="complete" and shelf:contains(synchronized) and not p.inventory:contains(synchronized))
end)
test("borrowed drinks return the same partly filled bottle and preserve owned items",function()
    local p=T.playerNew(); p.values.THIRST=.25
    local shelf=T.container(1,0); local bottle=T.add(shelf,T.water())
    local owned=T.add(p.inventory,T.item("InventoryItem",{fullType="Base.EmptyBottle"}))
    p.nearby={shelf}; assert(C.start(p,"yoga",true))
    for i=1,8 do T.tick(p) end
    assert(shelf:contains(bottle) and bottle.fluid.amount==.5)
    assert(p.inventory:contains(owned) and not p.inventory:contains(bottle))
    C.stop(p)
end)
test("consuming borrowed food returns only its new native empty container",function()
    local p=T.playerNew(); p.values.HUNGER=.5
    local shelf=T.container(1,0)
    T.add(shelf,T.item("Food",{replace="Base.EmptyTinCan"}))
    local owned=T.add(p.inventory,T.item("InventoryItem",{fullType="Base.EmptyTinCan"}))
    p.nearby={shelf}; assert(C.start(p,"yoga",true))
    for i=1,8 do T.tick(p) end
    assert(#shelf.items==1 and shelf.items[1]:getFullType()=="Base.EmptyTinCan")
    assert(shelf.items[1]~=owned and p.inventory:contains(owned))
    C.stop(p)
end)
test("cancelled borrowing keeps unreachable items and returns them when the source is reachable again",function()
    local p=T.playerNew(); p.values.BOREDOM=40
    local shelf=T.container(1,0); local book=T.add(shelf,T.item("Literature"))
    p.nearby={shelf}; assert(C.start(p,"meditation",true)); T.tick(p)
    assert(p.inventory:contains(book))
    p.square=T.square(5,0); p.moving=true; T.now=T.now+1000; C.update(p)
    p.moving=false; T.now=T.now+1000; C.update(p)
    assert(not C.status(p).active and C.status(p).pendingReturns==1 and C.status(p).returnNotice)
    assert(p.inventory:contains(book))
    p.square=T.square(0,0)
    for i=1,4 do T.tick(p) end
    assert(shelf:contains(book) and C.status(p).pendingReturns==0)
end)
test("an unavailable original container keeps the borrowed resource without stopping the loop",function()
    local p=T.playerNew(); p.values.BOREDOM=40
    local shelf=T.container(1,0); local book=T.add(shelf,T.item("Literature"))
    p.nearby={shelf}; assert(C.start(p,"meditation",true)); T.tick(p)
    shelf.reject=true
    for i=1,5 do T.tick(p) end
    assert(C.status(p).active and C.status(p).returnNotice and p.inventory:contains(book))
    shelf.reject=false
    for i=1,4 do T.tick(p) end
    assert(shelf:contains(book))
    C.stop(p)
end)
test("rereads use native cooldown and oldest native reading dates after unread titles",function()
    local S=require "AutoMindful/Supplies"; local p=T.playerNew()
    local unread=T.add(p.inventory,T.item("Literature",{data={literatureTitle="unread"}}))
    local oldest=T.add(p.inventory,T.item("Literature",{data={literatureTitle="oldest"}}))
    local newer=T.add(p.inventory,T.item("Literature",{data={literatureTitle="newer"}}))
    local recent=T.add(p.inventory,T.item("Literature",{data={literatureTitle="recent"}}))
    p.read.oldest=1; p.read.newer=2; p.read.recent=49
    local report=S.report(p,false)
    assert(report.unreadLiterature==1 and report.rereadLiterature==2 and report.cooldownLiterature==1)
    assert(S.choose(p,"literature",false,{}).item==unread)
    T.remove(p.inventory,unread)
    assert(S.choose(p,"literature",false,{}).item==oldest)
    p.read.oldest=T.nights
    assert(S.choose(p,"literature",false,{}).item==newer)
    p.read.newer=T.nights
    assert(not S.choose(p,"literature",false,{}))
    T.nights=95
    assert(S.choose(p,"literature",false,{}).item==recent,"native cooldown expiry must make the oldest title usable again")
    T.nights=50
end)
test("borrowed books return to their original floor square and carried bag",function()
    for _, floorSource in ipairs({true,false}) do
        local p=T.playerNew(); p.values.BOREDOM=40
        local source=T.container(1,0)
        if floorSource then source.floor=true; p.nearby={source}
        else
            source.root=p.inventory
            T.add(p.inventory,T.item("InventoryContainer",{inventory=source}))
        end
        local book=T.add(source,T.item("Literature"))
        assert(C.start(p,"meditation",floorSource)); local status=T.run(p)
        assert(status.phase=="complete" and source:contains(book) and not p.inventory:contains(book))
        if floorSource then assert(book:getWorldItem():getSquare()==source.square) end
    end
end)
test("returned carried-bag items complete and manual bag moves return from the current container",function()
    local S=require "AutoMindful/Supplies"; local p=T.playerNew()
    local origin, other=T.container(),T.container(); origin.root=p.inventory; other.root=p.inventory
    T.add(p.inventory,T.item("InventoryContainer",{inventory=origin}))
    T.add(p.inventory,T.item("InventoryContainer",{inventory=other}))
    local book=T.add(origin,T.item("Literature")); local loan={origin=origin,items={book}}
    local action,notice,complete=S.returnAction(p,loan)
    assert(not action and not notice and complete,"An item already in its source must not queue another return")
    T.remove(origin,book); T.add(other,book)
    action,notice,complete=S.returnAction(p,loan)
    assert(action and not notice and not complete)
    action:perform()
    assert(origin:contains(book) and not other:contains(book),"Return must use the actual current bag as source")
    action,notice,complete=S.returnAction(p,loan)
    assert(not action and complete)
end)
test("food care restores hunger without an extra calorie reserve",function()
    local p=T.playerNew(); p.values.HUNGER=.16; p.calories=0
    local meal=T.add(p.inventory,T.item("Food",{hunger=-.24,baseHunger=-.24,calories=170}))
    assert(C.start(p,"meditation",false)); T.run(p)
    assert(math.abs(p.values.HUNGER)<.000001)
    assert(math.abs(meal:getHungerChange()+.08)<.000001,"Only .16 of the .24 hunger relief should be consumed")
    local full=T.playerNew(); full.values.HUNGER=0; full.calories=0
    local untouched=T.add(full.inventory,T.item("Food",{hunger=-.24,baseHunger=-.24,calories=170}))
    assert(C.start(full,"meditation",false)); T.run(full)
    assert(untouched:getHungerChange()==-.24,"A full survivor must not eat just to fill an arbitrary calorie reserve")
end)
test("opening borrowed food returns the new empty can and borrowed opener to their exact sources",function()
    local saved={ArrayList=ArrayList,HandcraftLogic=HandcraftLogic,getScriptManager=getScriptManager,ISEntityUI=ISEntityUI,ResourceType=ResourceType,ISCraftingUI=ISCraftingUI}
    ArrayList={new=function() local values={}; local list=T.list(values); function list:add(value) values[#values+1]=value end return list end}
    ResourceType={Item="Item"}
    local output={getFullName=function() return "Base.OpenedFixtureCan" end,isCantEat=function() return false end,
        getPoisonPower=function() return 0 end,getFoodSicknessChange=function() return 0 end,isAlcoholic=function() return false end,
        isDangerousUncooked=function() return false end,getHungerChange=function() return -.5 end,getThirstChange=function() return 0 end}
    local recipe={isAnySurfaceCraft=function() return false end,isCanBeDoneFromFloor=function() return false end,
        getOutputs=function() return T.list({{getResourceType=function() return "Item" end,getItem=function() return output end}}) end}
    function getScriptManager() return {getCraftRecipe=function(_,name) return name=="OpenFixture" and recipe or nil end} end
    HandcraftLogic={new=function(player)
        local logic={player=player}
        function logic:setIsoObject() end
        function logic:findCraftSurface() return nil end
        function logic:setContainers(containers) self.containers=containers end
        function logic:setRecipeFromContextClick(_,item) self.item=item end
        function logic:tool()
            for index=0,self.containers:size()-1 do
                local items=self.containers:get(index):getItems()
                for at=0,items:size()-1 do local item=items:get(at); if item:getFullType()=="Base.FixtureOpener" then return item end end
            end
        end
        function logic:canPerformCurrentRecipe() return self:tool()~=nil end
        function logic:getRecipeData()
            local tool=self:tool()
            return {getAllInputItems=function() return T.list({self.item,tool}) end,
                getAllPutBackInputItems=function() return T.list({tool}) end}
        end
        function logic:isUsingRecipeAtHandBenefit() return false end
        function logic:startCraftAction(action) ISTimedActionQueue.add(action) end
        return logic
    end}
    ISEntityUI={HandcraftStart=function(player,logic)
        local action=T.action(player,"ISHandcraftAction",function()
            T.remove(logic.item:getContainer(),logic.item)
            T.add(player.inventory,T.item("Food",{fullType="Base.OpenedFixtureCan",replace="Base.EmptyFixtureCan"}))
        end)
        function action:setOnComplete() end
        return action
    end}
    ISCraftingUI={ReturnItemsToOriginalContainer=function() error("Do not rely on the native helper which skips Disorganized characters") end}
    ISInventoryPaneContextMenu.transferIfNeeded=function(player,item)
        if item:getContainer()~=player:getInventory() then
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player,item,item:getContainer(),player:getInventory()))
        end
    end
    local p=T.playerNew(); p.values.HUNGER=.5; p.traits.disorganized=true
    local pantry,toolbox=T.container(1,0),T.container(0,1)
    for _,container in ipairs({pantry,toolbox}) do
        local square=container.square; container.square=nil
        container.containingItem=T.item("InventoryContainer",{inventory=container,
            world={getSquare=function() return square end,getFluidContainer=function() return nil end}})
    end
    T.add(pantry,T.item("Food",{fullType="Base.ClosedFixtureCan",hunger=0,cantEat=true,sealed=true,openingRecipe="OpenFixture"}))
    local opener=T.add(toolbox,T.item("InventoryItem",{fullType="Base.FixtureOpener"}))
    local ownedCan=T.add(p.inventory,T.item("InventoryItem",{fullType="Base.EmptyFixtureCan"}))
    p.nearby={pantry,toolbox}
    local unavailable=C.prepare(p,false,true)
    assert(unavailable.nearbyFood==0 and unavailable.openingReason:find("opener",1,true))
    assert(C.prepare(p,true,true).nearbyFood==1)
    assert(C.start(p,"yoga",true))
    for i=1,14 do T.tick(p) end
    assert(toolbox:contains(opener) and not p.inventory:contains(opener))
    assert(#pantry.items==1 and pantry.items[1]:getFullType()=="Base.EmptyFixtureCan" and pantry.items[1]~=ownedCan)
    assert(p.inventory:contains(ownedCan) and C.status(p).pendingReturns==0)
    C.stop(p)
    local interrupted=T.playerNew(); interrupted.values.HUNGER=.3
    local foodSource,toolSource=T.container(1,0),T.container(0,1)
    local closed=T.add(foodSource,T.item("Food",{fullType="Base.ClosedFixtureCan",hunger=0,cantEat=true,sealed=true,openingRecipe="OpenFixture"}))
    local sharedOpener=T.add(toolSource,T.item("InventoryItem",{fullType="Base.FixtureOpener"}))
    interrupted.nearby={foodSource,toolSource}
    assert(C.start(interrupted,"yoga",true)); T.tick(interrupted)
    assert(C.status(interrupted).phase=="collecting" and interrupted.inventory:contains(closed))
    T.remove(toolSource,sharedOpener)
    for i=1,6 do T.tick(interrupted) end
    assert(C.status(interrupted).active and hasHistory(interrupted,"Yoga"),"Losing a shared opener must not stop noncritical training")
    assert(foodSource:contains(closed) and C.status(interrupted).pendingReturns==0,"The unopened borrowed can must return to its source")
    assert(not hasHistory(interrupted,"ISHandcraftAction") and #interrupted.halos==0)
    T.add(toolSource,sharedOpener); T.now=T.now+61000
    for i=1,14 do T.tick(interrupted) end
    assert(hasHistory(interrupted,"ISHandcraftAction") and hasHistory(interrupted,"eat"),"A usable opener permits a later retry")
    assert(C.status(interrupted).pendingReturns==0 and toolSource:contains(sharedOpener))
    C.stop(interrupted)
    ArrayList,HandcraftLogic,getScriptManager,ISEntityUI,ResourceType,ISCraftingUI=saved.ArrayList,saved.HandcraftLogic,saved.getScriptManager,saved.ISEntityUI,saved.ResourceType,saved.ISCraftingUI
end)
print("CONTRACTS PASS "..passed.." cases; game boundaries are explicit doubles, not gameplay evidence")
if not loadTest then function loadTest(name) return assert(loadfile("tests/"..name))() end end
if not readReference and arg and arg[1] then
    local root=arg[1]
    function readReference(name) local f=assert(io.open(root.."/"..name,"rb")); local text=f:read("*a"); f:close(); return text end
    function loadUpstream(name) return assert(loadstring(readReference("lua/"..name),name))() end
end
if loadUpstream then loadTest("upstream.lua") end
