local runtime = "mods/AutoMindful/common/media/lua/client/"
package.path = runtime .. "?.lua;" .. package.path
for _, name in ipairs({"TimedActions/ISTimedActionQueue", "TimedActions/ISReadABook", "TimedActions/ISDrinkFluidAction", "TimedActions/ISWaitWhileGettingUp", "ISUI/ISWorldObjectContextMenu", "ISUI/ISInventoryPaneContextMenu", "TimedActions/ISInventoryTransferUtil", "TimedActions/ISBaseTimedAction"}) do
    package.preload[name] = function() return true end
end
local T = {now = 0, client = false, sleepNeeded = true, sleepAllowed = true}
AutoMindfulTest = T
CharacterStat = {HUNGER="HUNGER", THIRST="THIRST", BOREDOM="BOREDOM", ENDURANCE="ENDURANCE", FATIGUE="FATIGUE", PAIN="PAIN", PANIC="PANIC"}
CharacterTrait = {ILLITERATE="illiterate", DISCIPLINED="disciplined", COUCHPOTATO="couchpotato"}
ItemTag = {UNINTERESTING="uninteresting", PICTUREBOOK="picturebook", PICTURE="picture"}
MoodleType = {FOOD_EATEN="food", PAIN="pain"}
Perks = {Meditation="Meditation", Fitness="Fitness", Nimble="Nimble"}
Fluid = {Water="Water"}
SkillBook = {Cooking=true}
SandboxVars = {Yoga={KeepBags=true}, Meditation={KeepBags=true}, LSMeditation={RemoveLevitation=false}}
Events = {}
for _, name in ipairs({"OnPlayerUpdate", "OnPlayerDeath", "OnGameStart"}) do Events[name] = {Add=function() end} end
function getTimestampMs() return T.now end
function isClient() return T.client end
function getServerOptions() return {getBoolean=function(_, key) return key == "SleepNeeded" and T.sleepNeeded or key == "SleepAllowed" and T.sleepAllowed end} end
function getText(key) return key end
function instanceof(item, kind) return item.kind == kind end
function getPlayerInventory() return true end
function getPlayerLoot() return true end
function getSpecificPlayer() return T.player end
function T.list(items)
    return {size=function() return #items end, get=function(_, index) return items[index+1] end, isEmpty=function() return #items == 0 end, contains=function(_, value) for _, item in ipairs(items) do if item == value then return true end end return false end}
end
function T.container(x, y)
    local c = {items={}}
    function c:getItems() return T.list(self.items) end
    function c:getOutermostContainer() return self end
    function c:hasRoomFor() return not self.full end
    function c:getSourceGrid() return {getX=function() return x or 0 end, getY=function() return y or 0 end, getZ=function() return 0 end} end
    return c
end
local nextID = 0
function T.item(kind, properties)
    nextID = nextID + 1
    local i = properties or {}
    i.kind, i.id, i.tags, i.data = kind, nextID, i.tags or {}, i.data or {}
    function i:getID() return self.id end
    function i:getContainer() return self.container end
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
    function f:canPlayerEmpty() return true end
    function f:getCapacity() return p.capacity or 1 end
    function f:getAmount() return self.amount end
    function f:isPureFluid() return not p.mixed end
    function f:isPoisonous() return p.poison or false end
    function f:isTainted() return p.tainted or false end
    return T.item("Water", {fluid=f})
end
function T.add(container, item)
    container.items[#container.items+1] = item
    item.container = container
    return item
end
function T.playerNew()
    local p = {inventory=T.container(), values={HUNGER=0.05, THIRST=0, BOREDOM=0, ENDURANCE=1, FATIGUE=0, PAIN=0, PANIC=0}, meditation=0, xp=0, yoga={0,0,100}, hours=10, calories=2000, read={}, printRead={}, history={}, traits={}}
    p.data = {LSMoodles={Embarrassed={Value=0,Level=0}, MindfulState={Value=0,Level=0}, WasTaughtSkill={Value=0,Level=0}, Zen={Value=0,Level=0}}}
    function p:getModData() return self.data end
    function p:getInventory() return self.inventory end
    function p:isLocalPlayer() return true end
    function p:getPlayerNum() return 0 end
    function p:getStats() return {get=function(_, name) return p.values[name] or 0 end, getNumVisibleZombies=function() return p.zombies or 0 end, getNumChasingZombies=function() return 0 end, getNumVeryCloseZombies=function() return 0 end} end
    function p:getBodyDamage() return {getOverallBodyHealth=function() return 100 end, getNumPartsBleeding=function() return 0 end} end
    function p:getNutrition() return {getCalories=function() return p.calories end} end
    function p:getMoodles() return {getMoodleLevel=function(_, kind) return kind == "pain" and p.painMoodle or kind == "food" and p.foodMoodle or 0 end} end
    function p:getPerkLevel(perk) return perk == "Meditation" and self.meditation or 0 end
    function p:getXp() return {getXP=function() return p.xp end} end
    function p:getHoursSurvived() return self.hours end
    function p:getLastHourSleeped() return 0 end
    function p:getSquare() return self.inventory:getSourceGrid() end
    function p:isSitOnGround() return self.sitting or false end
    function p:isSitting() return self.sitting or false end
    function p:reportEvent() self.sitting = true end
    function p:setVariable() end
    function p:tooDarkToRead() return self.dark or false end
    function p:hasTrait(trait) return self.traits[trait] end
    function p:isLiteratureRead(title) return self.read[title] end
    function p:getReadPrintMedia() local ids={} for id in pairs(self.printRead) do ids[#ids+1]=id end return T.list(ids) end
    function p:hasTimedActions() return #ISTimedActionQueue.getTimedActionQueue(self).queue > 0 end
    function p:isDead() return self.dead or false end
    function p:isOnFire() return false end
    function p:getVehicle() return nil end
    function p:isPlayerMoving() return self.moving or false end
    function p:isAiming() return false end
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
    return a
end
ISReadABook = {new=function(_, p, item) return T.action(p,"read",function() if not p.refuseCare then p.values.BOREDOM=math.max(0,p.values.BOREDOM+item:getBoredomChange()) end end) end}
ISDrinkFluidAction = {new=function(_, p, item, percentage)
    p.drinkPercentage = percentage
    return T.action(p,"drink",function() if not p.refuseCare then p.values.THIRST=0 end end)
end}
ISWaitWhileGettingUp = {new=function(_, p) return T.action(p,"stand",function() p.sitting=false end) end}
ISWearClothing = {new=function(_,p) return T.action(p,"wear") end}
ISWorldObjectContextMenu = {onSleepWalkToComplete=function() T.player.asleep=true end}
ISInventoryPaneContextMenu = {
    getEatingMask=function() return nil end,
    eatItem=function(item, fraction) local p=T.player ISTimedActionQueue.add(T.action(p,"eat",function() if not p.refuseCare then p.values.HUNGER=math.max(-0.1,p.values.HUNGER+item:getHungerChange()*fraction); p.calories=p.calories+item:getCalories()*fraction end end)) end,
    getContainers=function(player) return T.list(player.nearby or {}) end,
}
ISInventoryTransferUtil = {newInventoryTransferAction=function(p,item,source,target) return T.action(p,"transfer",function() for index,entry in ipairs(source.items) do if entry == item then table.remove(source.items,index) break end end T.add(target,item) end) end}
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
test("missing clean water stops before training",function()
    local p=T.playerNew(); p.values.THIRST=0.3; assert(C.start(p,"both",false)); T.tick(p)
    assert(not C.status(p).active and not hasHistory(p,"Meditation") and not hasHistory(p,"Yoga"))
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
    T.add(p.inventory,T.water({tainted=true})); T.add(p.inventory,T.water({mixed=true})); T.add(p.inventory,T.water({capacity=5}))
    local scan=S.scan(p,false); assert(#scan.food == 1 and scan.food[1].item == good and #scan.literature == 0 and #scan.water == 0)
end)
test("nearby collection is opt-in and respects adjacent range and capacity",function()
    local S=require "AutoMindful/Supplies"; local p=T.playerNew(); local near=T.container(1,0); local far=T.container(2,0)
    T.add(near,T.item("Food")); T.add(far,T.item("Food")); p.nearby={near,far}
    assert(#S.scan(p,false).food == 0 and #S.scan(p,true).food == 1)
    p.inventory.full=true; assert(not S.choose(p,"food",true,{}))
    p.inventory.full=false; assert(S.choose(p,"food",true,{}).item == near.items[1])
end)
test("missing Lifestyle rejects start but status and preparation remain usable",function()
    local upstream=ZenWellnessContextMenu; ZenWellnessContextMenu=nil
    local p=T.playerNew(); local started,message=C.start(p,"both",false)
    assert(not started and type(message) == "string" and not C.status(p).active)
    assert(type(C.prepare(p,false).message) == "string")
    ZenWellnessContextMenu=upstream
end)
print("CONTRACTS PASS "..passed.." cases; game boundaries are explicit doubles, not gameplay evidence")
if not loadTest then function loadTest(name) return assert(loadfile("tests/"..name))() end end
if not readReference and arg and arg[1] then
    local root=arg[1]
    function readReference(name) local f=assert(io.open(root.."/"..name,"rb")); local text=f:read("*a"); f:close(); return text end
    function loadUpstream(name) return assert(loadstring(readReference("lua/"..name),name))() end
end
if loadUpstream then loadTest("upstream.lua") end
